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

    // MARK: - What-If tables

    /// A two-way data table occupies its body *and* the inputs around it.
    ///
    /// Excel declares the body on the table's master cell — `<f t="dataTable"
    /// ref="P6:T10" dt2D="1"/>` — and leaves every other cell in the grid holding
    /// nothing but a cached number. The varying inputs sit in the row above and
    /// the column to the left, which is what makes it two-way, so the block a
    /// reader must account for is one row taller and one column wider than the
    /// span the file states.
    func testATwoWayTableOccupiesItsHeadersToo() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C9")
        sheet.write("2025", to: "D9")
        sheet.write("2026", to: "E9")
        sheet.write(
            FormulaAST.function(
                "_DATATABLE",
                [.text("D4:E5"), .cellRef(CellRef("A1")), .cellRef(CellRef("A2"))]),
            to: "D4")

        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let block = try XCTUnwrap(DataTableBlock.find(in: grid).first)

        XCTAssertEqual(block.body, CellRange(from: CellRef("D4"), to: CellRef("E5")))
        XCTAssertTrue(block.contains(CellRef("D4")), "the body")
        XCTAssertTrue(block.contains(CellRef("C3")), "the corner, above and left")
        XCTAssertTrue(block.contains(CellRef("D3")), "a column input, in the row above")
        XCTAssertTrue(block.contains(CellRef("C5")), "a row input, in the column left")
        XCTAssertFalse(block.contains(CellRef("B4")), "and no further than that")
        XCTAssertFalse(block.contains(CellRef("F4")))
    }

    /// A label beside a table does not own the table's cells.
    ///
    /// This is the collision Rule 1 fixed for series, one block further right. On
    /// the Wharton `ANSWER KEY` the IRR sensitivity grid sits in columns N through
    /// T on the same rows as the assumption tables, so `Total Purchase Price` in
    /// `F5` owned its own value in `H5` *and* six cells of the grid's header row,
    /// and was refused as owning seven things.
    func testALabelDoesNotOwnTheCellsOfATableBesideIt() throws {
        let result = scalars { sheet in
            withAxisBelow(sheet)
            sheet.write("Total Purchase Price", to: "A2")
            sheet.write(200.0, to: "B2")
            // A two-way table whose body is F3:G4, so its inputs occupy E2:G2.
            sheet.write(
                FormulaAST.function(
                    "_DATATABLE",
                    [.text("F3:G4"), .cellRef(CellRef("A9")), .cellRef(CellRef("A10"))]),
                to: "F3")
            for column in ["E", "F", "G"] { sheet.write(0.06, to: "\(column)2") }
        }

        let scalar = try XCTUnwrap(
            result.scalars.first { $0.name == "Total Purchase Price" },
            "Got: \(result.scalars.map(\.name)), \(result.diagnostics.map(\.code.rawValue))"
        )
        XCTAssertEqual(scalar.valueCell, CellRef("B2"), "its own value, and only that")
    }

    /// A one-way table is taken at exactly the span the file states.
    ///
    /// Which side a one-way table's inputs sit on is in the `dtr` attribute, which
    /// the reader does not carry. Guessing both sides would swallow a column of
    /// real accounts; claiming neither leaves a label reported rather than read,
    /// and reported is the failure worth having.
    func testAOneWayTableClaimsOnlyItsBody() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C9")
        sheet.write("2025", to: "D9")
        sheet.write("2026", to: "E9")
        sheet.write(
            FormulaAST.function(
                "_DATATABLE", [.text("D4:E5"), .cellRef(CellRef("A1"))]),
            to: "D4")

        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let block = try XCTUnwrap(DataTableBlock.find(in: grid).first)

        XCTAssertTrue(block.contains(CellRef("D4")))
        XCTAssertFalse(block.contains(CellRef("C3")), "no header row or column is assumed")
    }

    /// A reference names the account the binder gave that cell, not a re-derived
    /// label.
    ///
    /// Two rows may carry the same heading; the binder keeps both and distinguishes
    /// the second by its cell. Re-deriving a name from the nearest label throws that
    /// away, so a reference to the second row resolves to the **first** — and if the
    /// first is an assumption rather than a row, the formula quietly reads a
    /// percentage where it wanted a balance.
    ///
    /// This is what the Wharton `ANSWER KEY` did: `Equity of PE Firm` sums a column
    /// that includes `Debt` in row 58, and resolved it to the `Debt` assumption in
    /// row 4, which is 60%. Every period came out as 0.6 against a sheet saying
    /// 0 and then 240.98 — a model that ran, converged, and was wrong.
    func testAReferenceUsesTheBindersNameForTheCell() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C5")
        sheet.write("2025", to: "D5")
        sheet.write("2026", to: "E5")
        // An assumption called Debt, above the timeline.
        sheet.write("Debt", to: "A2")
        sheet.write(0.6, to: "B2")
        // A row also called Debt, on the timeline.
        sheet.write("Debt", to: "A6")
        for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)6") }
        sheet.write("Equity", to: "A7")
        for column in ["C", "D", "E"] {
            sheet.write(FormulaAST.cellRef(CellRef("\(column)6")), to: "\(column)7")
        }

        sheet.write("Loan", to: "A8")
        for column in ["C", "D", "E"] {
            sheet.write(FormulaAST.cellRef(CellRef("$B$2")), to: "\(column)8")
        }

        let plan = ExcelRecognizer.recognize(sheet)
        let names = plan.model.accounts.map(\.name)

        let equity = try XCTUnwrap(plan.model.accounts.first { $0.name == "Equity" }, "\(names)")
        XCTAssertEqual(
            equity.formula, "Debt",
            "the row on the timeline keeps the plain heading, and the reference to "
                + "its cell resolves there"
        )

        let loan = try XCTUnwrap(plan.model.accounts.first { $0.name == "Loan" }, "\(names)")
        XCTAssertEqual(
            loan.formula, "[Debt (A2)]",
            "and the assumption, distinguished by its cell, stays reachable. Dropping "
                + "it would lose 60% and send this reference to the row instead"
        )
        XCTAssertTrue(names.contains("Debt (A2)"), "both survive. Got: \(names)")
    }
}
