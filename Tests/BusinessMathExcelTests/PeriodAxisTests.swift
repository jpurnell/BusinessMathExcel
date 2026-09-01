import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Stage 1 — turning detected headings into a real time axis.
final class PeriodAxisTests: XCTestCase {

    private func axis(
        _ build: (Worksheet) -> Void
    ) -> (axis: PeriodAxis?, diagnostics: [Diagnostic]) {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        build(sheet)
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        return PeriodAxis.build(from: grid)
    }

    func testYearHeadingsBecomeAnnualPeriods() throws {
        let result = axis { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
            sheet.write("2026", to: "D1")
        }

        let axis = try XCTUnwrap(result.axis)
        XCTAssertEqual(axis.periods, [Period.year(2024), Period.year(2025), Period.year(2026)])
        XCTAssertEqual(axis.granularity, .annual)
        XCTAssertTrue(result.diagnostics.isEmpty, "Got: \(result.diagnostics)")
    }

    func testPeriodsKeepTheOrderOfTheirSourceCells() throws {
        let result = axis { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
        }

        let axis = try XCTUnwrap(result.axis)
        XCTAssertEqual(axis.sources.map(\.reference), ["B1", "C1"])
        XCTAssertEqual(axis.periods.count, axis.sources.count)
        XCTAssertEqual(axis.periods.first, Period.year(2024))
    }

    func testTheRecoveredPeriodsAreBusinessMathAnnualPeriods() throws {
        // The whole point of the Phase 0 pin bump: these are the types
        // `ModelDefinition` consumes, not a local stand-in.
        let result = axis { sheet in
            sheet.write("2024", to: "B1")
            sheet.write("2025", to: "C1")
        }

        let axis = try XCTUnwrap(result.axis)
        let first = try XCTUnwrap(axis.periods.first)
        XCTAssertEqual(first.type, PeriodType.annual)
        XCTAssertEqual(first, Period.year(2024))
    }

    func testFiscalAndEstimateHeadingsRecoverTheirYear() throws {
        for (headings, years) in [(["FY2024", "FY2025"], [2024, 2025]),
                                  (["FY24", "FY25"], [2024, 2025]),
                                  (["2024E", "2025E"], [2024, 2025])] {
            let result = axis { sheet in
                sheet.write(headings[0], to: "B1")
                sheet.write(headings[1], to: "C1")
            }
            let axis = try XCTUnwrap(result.axis, "\(headings)")
            XCTAssertEqual(axis.periods, years.map(Period.year), "\(headings)")
        }
    }

    func testAComputedHeaderRowRecoversItsPeriods() throws {
        // The shape every real model uses: one typed year, the rest computed.
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        sheet.write(2023.0, to: "E27")
        sheet.write(FormulaAST.add(.cellRef(CellRef("E27")), .number(1)), to: "F27")
        let reloaded = try Workbook(xlsxData: try wb.save())

        let grid = SheetGrid.build(
            from: ModelImporter.importSheet(try XCTUnwrap(reloaded.sheets.first)))
        // Writing in memory caches nothing, so this asserts the pathway, not the value.
        XCTAssertNotNil(grid.cachedValues)
    }

    func testNoAxisYieldsNoPeriodsAndNoRepeatedComplaint() {
        let result = axis { sheet in
            sheet.write("Revenue", to: "A1")
            sheet.write(100.0, to: "B1")
        }

        XCTAssertNil(result.axis)
        XCTAssertTrue(
            result.diagnostics.isEmpty,
            "SheetGrid already reported the missing axis; saying so twice is noise"
        )
    }

    func testQuarterlyHeadingsAreNotRecognized() {
        // Deliberate, and recorded: neither reference workbook contains a single
        // quarterly heading, so supporting one would be guessing at its spelling.
        let result = axis { sheet in
            sheet.write("Q1 2024", to: "B1")
            sheet.write("Q2 2024", to: "C1")
        }

        XCTAssertNil(result.axis)
    }
}
