import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// Splitting a formula by how far back it reaches.
///
/// A `ModelDefinition` formula is period-local: it reads accounts in the period
/// being evaluated and never another. A spreadsheet formula routinely reaches one
/// column left. The offset along the period axis is that reach, and it is
/// mechanical — the grid knows where every cell sits — so a formula can be split
/// into the part that stays and the part that becomes a rollforward.
final class LagDecompositionTests: XCTestCase {

    /// Years across C..E, so the period columns are C, D, E.
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

    // MARK: - Lag zero

    func testAFormulaReadingItsOwnPeriodHasNoLag() throws {
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
        XCTAssertTrue(split.rollforwards.isEmpty, "same period, so nothing carries")
        XCTAssertTrue(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
    }

    // MARK: - Lag one

    func testASelfReferenceOnePeriodBackBecomesARollforward() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(1.15)), to: "D2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(1.15)), to: "E2")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        XCTAssertEqual(split.rollforwards.count, 1, "one reach back, one carry")
        XCTAssertTrue(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
    }

    func testTheCarriedReferenceIsRewrittenToItsOpeningAccount() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(1.15)), to: "D2")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        let carry = try XCTUnwrap(split.rollforwards.first)
        XCTAssertNotEqual(
            carry.opening, carry.closing,
            "an account cannot open at its own close in the same period"
        )
        XCTAssertTrue(
            split.formula.contains(carry.opening),
            "the period-local formula reads the opening account, not the prior cell"
        )
    }

    // MARK: - Mixed

    func testAFormulaReachingBothWaysSplits() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Cash", to: "A2")
            sheet.write("Flow", to: "A3")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)3") }
            sheet.write(100.0, to: "C2")
            // D2 = C2 + D3 — one term reaches back, one stays.
            sheet.write(
                FormulaAST.add(.cellRef(CellRef("C2")), .cellRef(CellRef("D3"))), to: "D2")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        XCTAssertEqual(split.rollforwards.count, 1, "only the lagged term carries")
        XCTAssertTrue(split.diagnostics.isEmpty)
        XCTAssertTrue(split.formula.contains("Flow"), "the same-period term survives by name")
    }

    // MARK: - Off the axis

    func testAReferenceOffThePeriodAxisIsNotALag() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Growth", to: "A6")
            sheet.write(0.15, to: "B6")
            sheet.write("Revenue", to: "A2")
            // D2 = B6 * 100 — B is not a period column, so B6 is a scalar input.
            sheet.write(
                FormulaAST.multiply(.cellRef(CellRef("B6")), .number(100)), to: "D2")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        XCTAssertTrue(split.rollforwards.isEmpty, "a scalar is constant, not carried")
        XCTAssertTrue(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
    }

    // MARK: - Refusals

    func testAReachOfTwoPeriodsIsRefused() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            // E2 = C2 — two columns back. Wharton needs no such thing, and a
            // rollforward cannot express it.
            sheet.write(FormulaAST.cellRef(CellRef("C2")), to: "E2")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("E2"), in: grid, axis: axis))
        XCTAssertEqual(split.diagnostics.map(\.code), [.unsupportedLag])
        XCTAssertTrue(split.rollforwards.isEmpty, "and it is not quietly treated as lag 1")
    }

    func testAForwardReferenceIsRefused() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "D2")
            sheet.write(110.0, to: "E2")
            // C2 = D2 — reading the future.
            sheet.write(FormulaAST.cellRef(CellRef("D2")), to: "C2")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("C2"), in: grid, axis: axis))
        XCTAssertEqual(split.diagnostics.map(\.code), [.unsupportedLag])
    }

    func testARefusalNamesTheCellAndTheReach() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(FormulaAST.cellRef(CellRef("C2")), to: "E2")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("E2"), in: grid, axis: axis))
        let diagnostic = try XCTUnwrap(split.diagnostics.first)
        XCTAssertEqual(diagnostic.cell, CellRef("E2"))
        XCTAssertTrue(diagnostic.message.contains("2"), "Got: \(diagnostic.message)")
    }

    // MARK: - Pinned references

    func testAPinnedReferenceIsAnAssumptionNotACarry() throws {
        // `$B$6` names the same cell from every period, so it is a rate, not last
        // period's anything. Reading the `$` is the difference between a
        // rollforward and a constant — and getting it wrong turns an interest rate
        // into a balance that carries.
        let (grid, axis) = sheet { sheet in
            sheet.write("Rate", to: "A6")
            sheet.write(0.1, to: "B6")
            sheet.write("Debt", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write("Interest", to: "A3")
            for column in ["C", "D", "E"] {
                sheet.write(
                    FormulaAST.multiply(
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("$B$6"))),
                    to: "\(column)3")
            }
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D3"), in: grid, axis: axis))
        XCTAssertTrue(split.rollforwards.isEmpty, "a pinned cell carries nothing")
        XCTAssertTrue(split.formula.contains("Rate"))
    }

    func testAPinnedReferenceOnePeriodBackIsStillAnAssumption() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Base", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write("Derived", to: "A3")
            // `$C$2` from D: one column left, but pinned, so it does not move.
            sheet.write(FormulaAST.cellRef(CellRef("$C$2")), to: "D3")
        }

        let split = try XCTUnwrap(
            LagDecomposition.decompose(cell: CellRef("D3"), in: grid, axis: axis))
        XCTAssertTrue(split.rollforwards.isEmpty)
        XCTAssertTrue(split.diagnostics.isEmpty)
    }
}
