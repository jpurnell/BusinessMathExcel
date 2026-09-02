import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

/// Stage 2 — binding a label to the values it names.
final class LabeledSeriesTests: XCTestCase {

    private func bind(
        _ build: (Worksheet) -> Void
    ) -> (series: [LabeledSeries], diagnostics: [Diagnostic]) {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        build(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        guard let axis = PeriodAxis.build(from: grid).axis else { return ([], []) }
        return LabeledSeries.bind(in: grid, axis: axis)
    }

    /// Years across C..E, so the period columns are C, D, E.
    private func withAxis(_ sheet: Worksheet) {
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
    }

    // MARK: - Binding

    func testALabelBindsToTheValuesInThePeriodColumns() throws {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(121.0, to: "E2")
        }

        XCTAssertEqual(result.series.count, 1)
        let series = try XCTUnwrap(result.series.first)
        XCTAssertEqual(series.name, "Revenue")
        XCTAssertEqual(series.labelCell, CellRef("A2"))
        XCTAssertEqual(series.cells.map { $0?.reference }, ["C2", "D2", "E2"])
    }

    func testALabelBindsAcrossAGapBetweenItAndItsValues() throws {
        // The label sits in column A and the values begin at C, with B empty.
        // The axis already said which columns hold periods, so the gap is layout,
        // not a boundary.
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(121.0, to: "E2")
        }

        XCTAssertEqual(result.series.first?.name, "Revenue")
    }

    func testABlankPeriodIsAHoleNotABreak() throws {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            // D2 deliberately blank
            sheet.write(121.0, to: "E2")
        }

        XCTAssertEqual(result.series.count, 1, "One series with a hole, not two series")
        let series = try XCTUnwrap(result.series.first)
        XCTAssertEqual(series.cells.map { $0?.reference }, ["C2", nil, "E2"])
        XCTAssertEqual(series.populatedCells.count, 2)
    }

    func testTheAxisRowIsNotItselfASeries() {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Year", to: "A1")
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
        }

        XCTAssertEqual(result.series.map(\.name), ["Revenue"])
    }

    func testARowWithNoValuesInThePeriodColumnsIsNotASeries() {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Section heading", to: "A2")
            sheet.write("Revenue", to: "A3")
            sheet.write(100.0, to: "C3")
        }

        XCTAssertEqual(result.series.map(\.name), ["Revenue"])
    }

    // MARK: - Naming

    func testValuesWithNoLabelAreNamedByAddressAndReported() throws {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
        }

        let series = try XCTUnwrap(result.series.first)
        XCTAssertEqual(series.name, "C2", "Named for the first cell it holds")
        XCTAssertNil(series.labelCell)
        XCTAssertEqual(result.diagnostics.map(\.code), [.labelUnbound])
        XCTAssertEqual(result.diagnostics.first?.severity, .info, "Recognized, not lost")
    }

    func testDuplicateLabelsBothSurviveAndAreReported() throws {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write("Revenue", to: "A3")
            sheet.write(200.0, to: "C3")
        }

        XCTAssertEqual(result.series.count, 2, "Neither is dropped")
        XCTAssertEqual(Set(result.series.map(\.name)).count, 2, "And they are distinguishable")
        XCTAssertTrue(result.series.contains { $0.name == "Revenue" })
        XCTAssertEqual(result.diagnostics.map(\.code), [.duplicateAccountName])
    }

    // MARK: - Orientation

    func testBindsSeriesWhenPeriodsRunDownRows() throws {
        let result = bind { sheet in
            sheet.write("2024", to: "A3")
            sheet.write("2025", to: "A4")
            sheet.write("2026", to: "A5")
            sheet.write("Revenue", to: "B1")
            sheet.write(100.0, to: "B3")
            sheet.write(110.0, to: "B4")
            sheet.write(121.0, to: "B5")
        }

        let series = try XCTUnwrap(result.series.first)
        XCTAssertEqual(series.name, "Revenue")
        XCTAssertEqual(series.cells.map { $0?.reference }, ["B3", "B4", "B5"])
    }

    // MARK: - Rule 1: a value belongs to its nearest label

    /// A second label on the same line owns the values after it.
    ///
    /// This is the layout the Wharton `ANSWER KEY` uses above its model: three
    /// assumption tables side by side, each a label with its value beside it. The
    /// tables know nothing of the timeline below them, but their value columns
    /// land in the timeline's columns, and a label that sweeps the whole axis
    /// claims figures belonging to the table on its right.
    func testALabelDoesNotClaimValuesAfterAnotherLabel() throws {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Purchase Multiple", to: "A2")
            sheet.write(5.0, to: "B2")
            // A second table starts here; D2 is its value, not the first table's.
            sheet.write("Entry EBITDA", to: "C2")
            sheet.write(40.0, to: "D2")
        }

        XCTAssertFalse(
            result.series.contains { $0.populatedCells.contains(CellRef("D2")) },
            "C2 stands between the first label and D2, so D2 is not Purchase Multiple's"
        )
        XCTAssertFalse(
            result.series.contains { $0.populatedCells.contains(CellRef("C2")) },
            "and C2 is a heading, not a value in the 2025 column"
        )
        // Neither table is a period series — they are assumptions that happen to
        // sit under the timeline's columns. Turning them into scalars is Rule 2.
        XCTAssertTrue(result.series.isEmpty)
    }

    func testAValueBoundedByNoInterveningLabelStillBinds() throws {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(121.0, to: "E2")
            // A label further right than every value it could claim.
            sheet.write("Note", to: "G2")
        }

        let series = try XCTUnwrap(result.series.first { $0.name == "Revenue" })
        XCTAssertEqual(
            series.cells.map { $0?.reference }, ["C2", "D2", "E2"],
            "a label after the values takes nothing from the one before them"
        )
    }

    func testAModelRowIsUntouched() throws {
        let result = bind { sheet in
            withAxis(sheet)
            sheet.write("Revenue", to: "A2")
            for column in ["C", "D", "E"] { sheet.write(100.0, to: "\(column)2") }
        }

        let series = try XCTUnwrap(result.series.first)
        XCTAssertEqual(series.cells.map { $0?.reference }, ["C2", "D2", "E2"])
    }
}
