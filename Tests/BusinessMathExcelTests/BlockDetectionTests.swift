import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Phase 5 Rule 2 — the period axis governs its own block, not the whole sheet.
///
/// A sheet is a stack of blocks and only some of them sit on the timeline. Above
/// the Wharton model are three assumption tables; their value columns land in the
/// timeline's columns by nothing more than where the page was laid out. Rule 1
/// stops a label claiming another table's figures. This is the other half: saying
/// what those figures *are*, rather than dropping them.
final class BlockDetectionTests: XCTestCase {

    private func scalars(
        _ build: (Worksheet) -> Void
    ) -> (scalars: [ScalarAssumption], diagnostics: [Diagnostic]) {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        build(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        guard let axis = PeriodAxis.build(from: grid).axis else { return ([], []) }
        return ScalarBlock.bind(in: grid, axis: axis)
    }

    /// Years across C..E on row 5, so rows 1–4 are outside the timeline block.
    private func withAxisBelow(_ sheet: Worksheet) {
        sheet.write("2024", to: "C5")
        sheet.write("2025", to: "D5")
        sheet.write("2026", to: "E5")
    }

    // MARK: - Outside the block

    func testALabelWithOneValueAboveTheAxisIsAScalar() throws {
        let result = scalars { sheet in
            withAxisBelow(sheet)
            sheet.write("Revenue growth", to: "A2")
            sheet.write(0.10, to: "B2")
        }

        let scalar = try XCTUnwrap(result.scalars.first { $0.name == "Revenue growth" })
        XCTAssertEqual(scalar.valueCell, CellRef("B2"))
    }

    func testEachTableOnALineBindsItsOwnScalar() throws {
        let result = scalars { sheet in
            withAxisBelow(sheet)
            sheet.write("Purchase Multiple", to: "A2")
            sheet.write(5.0, to: "B2")
            sheet.write("Entry EBITDA", to: "C2")
            sheet.write(40.0, to: "D2")
        }

        XCTAssertEqual(
            result.scalars.map(\.name).sorted(), ["Entry EBITDA", "Purchase Multiple"],
            "two tables side by side are two assumptions, not one confused row"
        )
        XCTAssertEqual(
            result.scalars.first { $0.name == "Entry EBITDA" }?.valueCell, CellRef("D2"))
    }

    func testASectionHeadingWithNoValueIsNotAScalar() throws {
        let result = scalars { sheet in
            withAxisBelow(sheet)
            sheet.write("Assumptions", to: "A2")
            sheet.write("Purchase Price Analysis", to: "C2")
        }

        XCTAssertTrue(
            result.scalars.isEmpty,
            "a heading owns no value, and inventing one for it would be worse than "
                + "leaving it unrecognized. Got: \(result.scalars.map(\.name))"
        )
    }

    func testARowOfManyValuesAboveTheAxisIsNotAScalar() throws {
        let result = scalars { sheet in
            withAxisBelow(sheet)
            // A header row of its own — several values, so not one assumption.
            sheet.write("Year", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(1.0, to: "\(column)2") }
        }

        XCTAssertTrue(result.scalars.isEmpty, "Got: \(result.scalars.map(\.name))")
        XCTAssertEqual(
            result.diagnostics.map(\.code), [.ambiguousAssumption],
            "reported rather than read as its first figure, which would be right "
                + "often enough to be dangerous"
        )
    }

    func testAHeadingIsNotReportedAsAnAmbiguousAssumption() throws {
        let result = scalars { sheet in
            withAxisBelow(sheet)
            sheet.write("Assumptions", to: "A2")
            sheet.write("Purchase Price Analysis", to: "C2")
        }

        XCTAssertTrue(
            result.diagnostics.isEmpty,
            "a title owns nothing and is not a finding. Got: "
                + "\(result.diagnostics.map(\.code.rawValue))"
        )
    }

    // MARK: - Inside the block

    func testARowOnTheTimelineIsNotAScalar() throws {
        let result = scalars { sheet in
            withAxisBelow(sheet)
            sheet.write("Revenue", to: "A6")
            for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)6") }
        }

        XCTAssertTrue(result.scalars.isEmpty, "row 6 is on the timeline")
    }

    // MARK: - Through recognition

    func testAScalarBecomesAnAccountHoldingItsValueInEveryPeriod() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        withAxisBelow(sheet)
        sheet.write("Revenue growth", to: "A2")
        sheet.write(0.10, to: "B2")
        sheet.write("Revenue", to: "A6")
        for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)6") }

        let plan = ExcelRecognizer.recognize(try XCTUnwrap(workbook.sheets.first))
        let growth = try XCTUnwrap(
            plan.model.accounts.first { $0.name == "Revenue growth" },
            "Got: \(plan.model.accounts.map(\.name))"
        )
        let values = try XCTUnwrap(growth.values)
        XCTAssertEqual(values.count, 3, "an assumption holds for every period")
        for period in plan.model.periods {
            XCTAssertEqual(values[period] ?? .nan, 0.10, accuracy: 1e-9)
        }
    }

    func testAScalarWhoseValueIsAFormulaStaysDerived() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        withAxisBelow(sheet)
        sheet.write("Purchase Multiple", to: "A2")
        sheet.write(5.0, to: "B2")
        sheet.write("Entry EBITDA", to: "A3")
        sheet.write(40.0, to: "B3")
        sheet.write("Total Purchase Price", to: "A4")
        sheet.write(
            FormulaAST.multiply(.cellRef(CellRef("B3")), .cellRef(CellRef("B2"))), to: "B4")

        let plan = ExcelRecognizer.recognize(try XCTUnwrap(workbook.sheets.first))
        let total = try XCTUnwrap(
            plan.model.accounts.first { $0.name == "Total Purchase Price" },
            "Got: \(plan.model.accounts.map(\.name))"
        )
        XCTAssertEqual(
            total.formula, "([Entry EBITDA] * [Purchase Multiple])",
            "200 is the answer, not the model"
        )
        XCTAssertNil(total.values)
    }

    /// A reference names the account that owns the cell, not the row's first label.
    func testAReferenceNamesTheAccountThatOwnsTheCell() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        withAxisBelow(sheet)
        // Two tables on one line. B2 is Left's; D2 is Right's.
        sheet.write("Left", to: "A2")
        sheet.write(2.0, to: "B2")
        sheet.write("Right", to: "C2")
        sheet.write(3.0, to: "D2")
        sheet.write("Doubled", to: "A3")
        sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(2)), to: "B3")

        let plan = ExcelRecognizer.recognize(try XCTUnwrap(workbook.sheets.first))
        let doubled = try XCTUnwrap(
            plan.model.accounts.first { $0.name == "Doubled" },
            "Got: \(plan.model.accounts.map(\.name))"
        )
        XCTAssertEqual(
            doubled.formula, "(Right * 2.0)",
            "D2 belongs to Right; naming it Left would build a model off the wrong number"
        )
    }
}
