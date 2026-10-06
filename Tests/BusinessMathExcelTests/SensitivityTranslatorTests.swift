import Foundation
import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

@Suite struct SensitivityTranslatorTests {

    private func makeSampleAnalysis() -> ScenarioSensitivityAnalysis {
        ScenarioSensitivityAnalysis(
            inputDriver: "Revenue",
            inputValues: [800, 900, 1000, 1100, 1200],
            outputValues: [50, 75, 100, 125, 150]
        )
    }

    @Test func createsWorkbook() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.sensitivityWorkbook(from: analysis)

        #expect(workbook.sheets.count == 1)
        #expect(workbook.sheets[0].name == "Sensitivity Analysis")
    }

    @Test func writesDriverName() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.sensitivityWorkbook(from: analysis)
        let sheet = workbook.sheets[0]

        #expect(sheet.cell(at: "A1") == .text("Revenue"))
    }

    @Test func writesHeaders() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.sensitivityWorkbook(from: analysis)
        let sheet = workbook.sheets[0]

        #expect(sheet.cell(at: "A2") == .text("Input Value"))
        #expect(sheet.cell(at: "B2") == .text("Output Value"))
    }

    @Test func writesDataRows() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.sensitivityWorkbook(from: analysis)
        let sheet = workbook.sheets[0]

        if case .number(let input) = sheet.cell(at: "A3") {
            #expect(abs(input - 800) <= 0.01)
        } else {
            Issue.record("A3 should contain first input value")
        }

        if case .number(let output) = sheet.cell(at: "B3") {
            #expect(abs(output - 50) <= 0.01)
        } else {
            Issue.record("B3 should contain first output value")
        }
    }

    @Test func writesOutputRangeFormula() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.sensitivityWorkbook(from: analysis)
        let sheet = workbook.sheets[0]

        let rangeRow = 3 + analysis.count
        let ref = CellRef(column: 1, row: rangeRow)
        #expect(sheet.cell(at: ref.reference) == .text("Output Range"))

        let valRef = CellRef(column: 2, row: rangeRow)
        #expect(sheet.cell(at: valRef.reference)?.isFormula == true)
    }

    @Test func multipleAnalyses() {
        let rev = makeSampleAnalysis()
        let cost = ScenarioSensitivityAnalysis(
            inputDriver: "Cost",
            inputValues: [400, 500, 600],
            outputValues: [120, 100, 80]
        )
        let workbook = legacy.sensitivityWorkbook(from: [rev, cost])
        let sheet = workbook.sheets[0]

        #expect(sheet.cell(at: "A1") == .text("Revenue"))

        let costStartRow = 1 + 1 + rev.count + 1 + 1 + 1
        let costRef = CellRef(column: 1, row: costStartRow)
        #expect(sheet.cell(at: costRef.reference) == .text("Cost"))
    }

    @Test func customSheetName() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.sensitivityWorkbook(from: analysis, sheetName: "Revenue Impact")

        #expect(workbook.sheets[0].name == "Revenue Impact")
    }

    @Test func savesToFile() throws {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.sensitivityWorkbook(from: analysis)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sens_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        #expect(try url.checkResourceIsReachable())
    }
}
