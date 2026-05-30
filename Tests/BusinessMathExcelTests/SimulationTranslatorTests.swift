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

    func testSummarySheetHasStatistics() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)
        let summary = workbook.sheets[0]

        XCTAssertEqual(summary.cell(at: "A3"), .string("Statistic"))
        XCTAssertEqual(summary.cell(at: "B3"), .string("Value"))

        if case .number(let mean) = summary.cell(at: "B4") {
            XCTAssertEqual(mean, results.statistics.mean, accuracy: 0.01)
        } else {
            XCTFail("B4 should contain the mean value")
        }
    }

    func testSummarySheetHasPercentiles() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)
        let summary = workbook.sheets[0]

        XCTAssertEqual(summary.cell(at: "A11"), .string("Percentile"))
    }

    func testDataSheetHasAllTrials() {
        let results = makeSampleResults()
        let workbook = SimulationTranslator.workbook(from: results)
        let data = workbook.sheets[1]

        XCTAssertEqual(data.cell(at: "A1"), .string("Trial"))
        XCTAssertEqual(data.cell(at: "B1"), .string("Value"))

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

        XCTAssertEqual(summary.cell(at: "A1"), .string("NPV Distribution"))
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
