import Foundation
import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

@Suite struct SimulationTranslatorTests {

    private func makeSampleResults() -> SimulationResults {
        let values = (0..<100).map { Double($0) * 1000 }
        return SimulationResults(values: values)
    }

    @Test func translatorCreatesTwoSheets() {
        let results = makeSampleResults()
        let workbook = legacy.simulationWorkbook(from: results)

        #expect(workbook.sheets.count == 2)
        #expect(workbook.sheets[0].name == "Summary")
        #expect(workbook.sheets[1].name == "Simulation Data")
    }

    @Test func summarySheetHasFormulas() {
        let results = makeSampleResults()
        let workbook = legacy.simulationWorkbook(from: results)
        let summary = workbook.sheets[0]

        #expect(summary.cell(at: "A3") == .text("Statistic"))
        #expect(summary.cell(at: "B3") == .text("Value"))

        #expect(summary.cell(at: "A4") == .text("Mean"))
        #expect(summary.cell(at: "B4")?.isFormula == true)
        #expect(summary.cell(at: "A6") == .text("Std Deviation"))
        #expect(summary.cell(at: "B6")?.isFormula == true)
    }

    @Test func summarySheetHasPercentileFormulas() {
        let results = makeSampleResults()
        let workbook = legacy.simulationWorkbook(from: results)
        let summary = workbook.sheets[0]

        #expect(summary.cell(at: "A11") == .text("Percentile"))

        #expect(summary.cell(at: "B12")?.isFormula == true)
    }

    @Test func dataSheetHasAllTrials() {
        let results = makeSampleResults()
        let workbook = legacy.simulationWorkbook(from: results)
        let data = workbook.sheets[1]

        #expect(data.cell(at: "A1") == .text("Trial"))
        #expect(data.cell(at: "B1") == .text("Value"))

        if case .number(let firstValue) = data.cell(at: "B2") {
            #expect(abs(firstValue - 0) <= 0.01)
        } else {
            Issue.record("B2 should contain the first trial value")
        }

        if case .number(let lastValue) = data.cell(at: "B101") {
            #expect(abs(lastValue - 99_000) <= 0.01)
        } else {
            Issue.record("B101 should contain the last trial value")
        }
    }

    @Test func customTitle() {
        let results = makeSampleResults()
        let workbook = legacy.simulationWorkbook(from: results, title: "NPV Distribution")
        let summary = workbook.sheets[0]

        #expect(summary.cell(at: "A1") == .text("NPV Distribution"))
    }

    @Test func savesToFile() throws {
        let results = makeSampleResults()
        let workbook = legacy.simulationWorkbook(from: results)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        #expect(try url.checkResourceIsReachable())
    }
}
