import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Turning a workbook formula into one the evaluator will actually parse.
///
/// The test that matters is not "does it look right" but **does the upstream
/// parser accept it** — so these run the translated string back through
/// `FormulaEvaluator.accountNames(in:)`, which parses it and throws if it cannot.
/// A translator checked only against its own expectations is a translator that
/// agrees with itself.
final class FormulaTranslationTests: XCTestCase {

    private func sheet(_ build: (Worksheet) -> Void) -> (SheetGrid, PeriodAxis) {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        build(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        guard let axis = PeriodAxis.build(from: grid).axis else {
            preconditionFailure("the fixture always has an axis")
        }
        return (grid, axis)
    }

    /// Parses the translation the way the evaluator will, and returns the accounts
    /// it reads.
    private func accounts(in formula: String) throws -> Set<String> {
        try FormulaEvaluator<Double>.accountNames(in: formula)
    }

    // MARK: - The upstream parser accepts it

    func testArithmeticParses() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Cost", to: "A3")
            sheet.write("Profit", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(40.0, to: "\(column)3")
                sheet.write(
                    FormulaAST.subtract(
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))),
                    to: "\(column)4")
            }
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        XCTAssertEqual(try accounts(in: split.formula), ["Revenue", "Cost"])
    }

    func testAComparisonParses() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Target", to: "A3")
            sheet.write("Beat", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(90.0, to: "\(column)3")
                sheet.write(
                    FormulaAST.greaterThan(
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))),
                    to: "\(column)4")
            }
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        XCTAssertEqual(try accounts(in: split.formula), ["Revenue", "Target"])
    }

    func testARegisteredFunctionParses() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Cash", to: "A2")
            sheet.write("Debt", to: "A3")
            sheet.write("Sweep", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(60.0, to: "\(column)3")
                sheet.write(
                    FormulaAST.function("MIN", [
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))
                    ]),
                    to: "\(column)4")
            }
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        XCTAssertTrue(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
        XCTAssertEqual(
            try accounts(in: split.formula), ["Cash", "Debt"],
            "MIN is a function, not an account — the upstream parser must agree"
        )
    }

    // MARK: - Awkward names

    func testANameWithPunctuationSurvivesInBrackets() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Sales & Marketing", to: "A2")
            sheet.write("Revenue", to: "A3")
            sheet.write("Ratio", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(10.0, to: "\(column)2")
                sheet.write(100.0, to: "\(column)3")
                sheet.write(
                    FormulaAST.divide(
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))),
                    to: "\(column)4")
            }
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        XCTAssertTrue(
            split.formula.contains("[Sales & Marketing]"),
            "the ampersand would otherwise be read as an operator: \(split.formula)"
        )
        XCTAssertEqual(try accounts(in: split.formula), ["Sales & Marketing", "Revenue"])
    }

    func testAnAddressDerivedNameParses() throws {
        // An unlabelled row is named for its first cell — `C4`, which starts with a
        // letter and ends in digits, and is a perfectly ordinary identifier.
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(
                    FormulaAST.multiply(.cellRef(CellRef("\(column)2")), .number(2)),
                    to: "\(column)4")
            }
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        XCTAssertNoThrow(try accounts(in: split.formula))
    }

    // MARK: - Unregistered functions

    func testAnUnregisteredFunctionIsReportedAndNotInvented() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Looked up", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(
                    FormulaAST.function("VLOOKUP", [.cellRef(CellRef("\(column)2"))]),
                    to: "\(column)4")
            }
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        XCTAssertEqual(split.diagnostics.map(\.code), [.unregisteredFunction])
        XCTAssertTrue(
            split.diagnostics.first?.message.contains("VLOOKUP") == true,
            "the diagnostic names the function so the registry gap is actionable"
        )
    }

    func testAnUnregisteredFunctionNeverBecomesItsCachedNumber() throws {
        // The precise failure this project exists to avoid. The cell has a cached
        // value sitting in it, and translation must not reach for it.
        let wb = Workbook()
        let source = wb.addSheet(name: "Model")
        source.write("2024", to: "C1")
        source.write("2025", to: "D1")
        source.write("Revenue", to: "A2")
        source.write(100.0, to: "C2")
        source.write(100.0, to: "D2")
        source.write("Looked up", to: "A4")
        source.write(FormulaAST.function("VLOOKUP", [.cellRef(CellRef("C2"))]), to: "C4")
        source.write(FormulaAST.function("VLOOKUP", [.cellRef(CellRef("D2"))]), to: "D4")

        let reloaded = try Workbook(xlsxData: try wb.save())
        let sheet = try XCTUnwrap(reloaded.sheets.first)
        let imported = ModelImporter.importSheet(sheet)
        let grid = SheetGrid.build(from: imported)
        let axis = try XCTUnwrap(PeriodAxis.build(from: grid).axis)

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        XCTAssertEqual(split.diagnostics.map(\.code), [.unregisteredFunction])
        XCTAssertFalse(
            split.formula.contains("VLOOKUP"),
            "an unparseable name must not be handed to the evaluator either"
        )
    }

    func testRegisteredNamesAreCheckedAgainstTheRealRegistry() {
        // Not a hand-copied list. If upstream registers or removes a name, this
        // moves with it rather than drifting.
        XCTAssertNotNil(FormulaEvaluator<Double>.Function(rawValue: "MIN"))
        XCTAssertNil(FormulaEvaluator<Double>.Function(rawValue: "VLOOKUP"))
    }
}
