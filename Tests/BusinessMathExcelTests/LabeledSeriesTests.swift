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
}
