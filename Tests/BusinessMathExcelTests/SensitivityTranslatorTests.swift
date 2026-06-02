import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

@available(*, deprecated)
final class SensitivityTranslatorTests: XCTestCase {

    private func makeSampleAnalysis() -> ScenarioSensitivityAnalysis {
        ScenarioSensitivityAnalysis(
            inputDriver: "Revenue",
            inputValues: [800, 900, 1000, 1100, 1200],
            outputValues: [50, 75, 100, 125, 150]
        )
    }

    func testCreatesWorkbook() {
        let analysis = makeSampleAnalysis()
        let workbook = SensitivityTranslator.workbook(from: analysis)

        XCTAssertEqual(workbook.sheets.count, 1)
        XCTAssertEqual(workbook.sheets[0].name, "Sensitivity Analysis")
    }

    func testWritesDriverName() {
        let analysis = makeSampleAnalysis()
        let workbook = SensitivityTranslator.workbook(from: analysis)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(sheet.cell(at: "A1"), .text("Revenue"))
    }

    func testWritesHeaders() {
        let analysis = makeSampleAnalysis()
        let workbook = SensitivityTranslator.workbook(from: analysis)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(sheet.cell(at: "A2"), .text("Input Value"))
        XCTAssertEqual(sheet.cell(at: "B2"), .text("Output Value"))
    }

    func testWritesDataRows() {
        let analysis = makeSampleAnalysis()
        let workbook = SensitivityTranslator.workbook(from: analysis)
        let sheet = workbook.sheets[0]

        if case .number(let input) = sheet.cell(at: "A3") {
            XCTAssertEqual(input, 800, accuracy: 0.01)
        } else {
            XCTFail("A3 should contain first input value")
        }

        if case .number(let output) = sheet.cell(at: "B3") {
            XCTAssertEqual(output, 50, accuracy: 0.01)
        } else {
            XCTFail("B3 should contain first output value")
        }
    }

    func testWritesOutputRangeFormula() {
        let analysis = makeSampleAnalysis()
        let workbook = SensitivityTranslator.workbook(from: analysis)
        let sheet = workbook.sheets[0]

        let rangeRow = 3 + analysis.count
        let ref = CellRef(column: 1, row: rangeRow)
        XCTAssertEqual(sheet.cell(at: ref.reference), .text("Output Range"))

        let valRef = CellRef(column: 2, row: rangeRow)
        XCTAssertTrue(sheet.cell(at: valRef.reference)?.isFormula == true)
    }

    func testMultipleAnalyses() {
        let rev = makeSampleAnalysis()
        let cost = ScenarioSensitivityAnalysis(
            inputDriver: "Cost",
            inputValues: [400, 500, 600],
            outputValues: [120, 100, 80]
        )
        let workbook = SensitivityTranslator.workbook(from: [rev, cost])
        let sheet = workbook.sheets[0]

        XCTAssertEqual(sheet.cell(at: "A1"), .text("Revenue"))

        let costStartRow = 1 + 1 + rev.count + 1 + 1 + 1
        let costRef = CellRef(column: 1, row: costStartRow)
        XCTAssertEqual(sheet.cell(at: costRef.reference), .text("Cost"))
    }

    func testCustomSheetName() {
        let analysis = makeSampleAnalysis()
        let workbook = SensitivityTranslator.workbook(from: analysis, sheetName: "Revenue Impact")

        XCTAssertEqual(workbook.sheets[0].name, "Revenue Impact")
    }

    func testSavesToFile() throws {
        let analysis = makeSampleAnalysis()
        let workbook = SensitivityTranslator.workbook(from: analysis)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sens_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
