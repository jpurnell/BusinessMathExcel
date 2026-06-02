import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

final class SimulationTranslatorTests: XCTestCase {

    private func makeSampleResults() -> SimulationResults {
        let values = (0..<100).map { Double($0) * 1000 }
        return SimulationResults(values: values)
    }

    func testTranslatorCreatesTwoSheets() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)

        XCTAssertEqual(workbook.sheets.count, 2)
        XCTAssertEqual(workbook.sheets[0].name, "Summary")
        XCTAssertEqual(workbook.sheets[1].name, "Simulation Data")
    }

    func testSummarySheetHasFormulas() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)
        let summary = workbook.sheets[0]

        XCTAssertEqual(summary.cell(at: "A3"), .text("Statistic"))
        XCTAssertEqual(summary.cell(at: "B3"), .text("Value"))

        XCTAssertEqual(summary.cell(at: "A4"), .text("Mean"))
        XCTAssertTrue(summary.cell(at: "B4")?.isFormula == true)
        XCTAssertEqual(summary.cell(at: "A6"), .text("Std Deviation"))
        XCTAssertTrue(summary.cell(at: "B6")?.isFormula == true)
    }

    func testSummarySheetHasPercentileFormulas() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)
        let summary = workbook.sheets[0]

        XCTAssertEqual(summary.cell(at: "A11"), .text("Percentile"))

        XCTAssertTrue(summary.cell(at: "B12")?.isFormula == true)
    }

    func testDataSheetHasAllTrials() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)
        let data = workbook.sheets[1]

        XCTAssertEqual(data.cell(at: "A1"), .text("Trial"))
        XCTAssertEqual(data.cell(at: "B1"), .text("Value"))

        if case .number(let firstValue) = data.cell(at: "B2") {
            XCTAssertEqual(firstValue, 0, accuracy: 0.01)
        } else {
            XCTFail("B2 should contain the first trial value")
        }

        if case .number(let lastValue) = data.cell(at: "B101") {
            XCTAssertEqual(lastValue, 99_000, accuracy: 0.01)
        } else {
            XCTFail("B101 should contain the last trial value")
        }
    }

    func testCustomTitle() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results, title: "NPV Distribution")
        let summary = workbook.sheets[0]

        XCTAssertEqual(summary.cell(at: "A1"), .text("NPV Distribution"))
    }

    func testSavesToFile() throws {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
