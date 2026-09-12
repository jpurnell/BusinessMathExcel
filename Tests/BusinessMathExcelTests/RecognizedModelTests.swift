import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Stage 4 — the plan a workbook becomes.
///
/// `RecognizedModel` is plain data. Recognition never constructs a
/// `ModelDefinition` and never throws: a workbook that does not fit yields a
/// partial plan plus residue, which can be read and argued with before anything
/// is built from it.
final class RecognizedModelTests: XCTestCase {

    private func recognize(_ build: (Worksheet) -> Void) throws -> RecognitionResult {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        build(sheet)
        return ExcelRecognizer.recognize(try XCTUnwrap(wb.sheets.first))
    }

    // MARK: - Inputs and formulas

    func testARowOfLiteralsBecomesAnInputAccount() throws {
        let result = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(121.0, to: "E2")
        }

        let revenue = try XCTUnwrap(result.model.accounts.first { $0.name == "Revenue" })
        XCTAssertNil(revenue.formula, "an input is supplied, not derived")
        XCTAssertEqual(revenue.values?.count, 3)
    }

    func testARowOfFormulasBecomesADerivedAccount() throws {
        let result = try recognize { sheet in
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

        let profit = try XCTUnwrap(result.model.accounts.first { $0.name == "Profit" })
        let formula = try XCTUnwrap(profit.formula)
        XCTAssertTrue(formula.contains("Revenue"))
        XCTAssertNil(profit.values, "a derived account carries no literals")
    }

    // MARK: - Provenance

    func testEveryAccountNamesTheCellsItCameFrom() throws {
        let result = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
        }

        for account in result.model.accounts {
            XCTAssertFalse(
                account.provenance.isEmpty,
                "\(account.name) claims values from nowhere"
            )
        }
    }

    func testProvenanceCellsHoldWhatTheAccountClaims() throws {
        let result = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
        }

        let revenue = try XCTUnwrap(result.model.accounts.first { $0.name == "Revenue" })
        XCTAssertEqual(
            Set(revenue.provenance.map(\.reference)), ["C2", "D2"],
            "the cells named are the cells read"
        )
    }

    // MARK: - Residue

    func testAnUnregisteredFunctionGoesToResidueRatherThanAnAccount() throws {
        let result = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Looked up", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(
                    FormulaAST.function("VLOOKUP", [.cellRef(CellRef("\(column)2"))]),
                    to: "\(column)4")
            }
        }

        XCTAssertNil(
            result.model.accounts.first { $0.name == "Looked up" },
            "a row we cannot translate must not become an account"
        )
        let residue = try XCTUnwrap(result.model.residue.first { $0.label == "Looked up" })
        XCTAssertEqual(residue.reason, .unregisteredFunction)
        XCTAssertFalse(residue.cells.isEmpty, "residue says where it came from too")
    }

    func testAHandEditedRowGoesToResidue() throws {
        let result = try recognize { sheet in
            sheet.write("Base", to: "A2")
            sheet.write("Doubled", to: "A3")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(2)), to: "C3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(3)), to: "D3")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("E2")), .number(2)), to: "E3")
        }

        XCTAssertNil(result.model.accounts.first { $0.name == "Doubled" })
        let residue = try XCTUnwrap(result.model.residue.first { $0.label == "Doubled" })
        XCTAssertEqual(residue.reason, .nonUniformRow)
    }

    // MARK: - Rollforwards

    func testASelfReferencingRowContributesARollforward() throws {
        let result = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(1.15)), to: "D2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(1.15)), to: "E2")
        }

        XCTAssertFalse(
            result.model.rollforwards.isEmpty,
            "growth off last year's figure is a carry, and the plan must say so"
        )
    }

    // MARK: - Shape

    func testRecognitionNeverThrowsOnASheetItCannotRead() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Notes")
        sheet.write("Just some prose", to: "A1")

        let result = ExcelRecognizer.recognize(sheet)
        XCTAssertTrue(result.model.accounts.isEmpty)
        XCTAssertFalse(result.diagnostics.isEmpty, "and it says why")
    }

    func testCoverageIsReported() throws {
        let result = try recognize { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(121.0, to: "E2")
        }

        XCTAssertGreaterThan(result.coverage.populatedCells, 0)
        XCTAssertGreaterThan(result.coverage.fraction, 0)
    }
}
