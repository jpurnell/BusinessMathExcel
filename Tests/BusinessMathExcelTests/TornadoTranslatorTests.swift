import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

@available(*, deprecated)
final class TornadoTranslatorTests: XCTestCase {

    private func makeSampleAnalysis() -> TornadoDiagramAnalysis {
        TornadoDiagramAnalysis(
            inputs: ["Revenue", "Cost of Goods", "Tax Rate"],
            impacts: [
                "Revenue": 50_000,
                "Cost of Goods": 30_000,
                "Tax Rate": 10_000,
            ],
            lowValues: [
                "Revenue": 80_000,
                "Cost of Goods": 90_000,
                "Tax Rate": 95_000,
            ],
            highValues: [
                "Revenue": 130_000,
                "Cost of Goods": 120_000,
                "Tax Rate": 105_000,
            ],
            baseCaseOutput: 100_000
        )
    }

    func testCreatesWorkbook() {
        let analysis = makeSampleAnalysis()
        let workbook = TornadoTranslator.workbook(from: analysis)

        XCTAssertEqual(workbook.sheets.count, 1)
        XCTAssertEqual(workbook.sheets[0].name, "Tornado Analysis")
    }

    func testBaseCaseHeader() {
        let analysis = makeSampleAnalysis()
        let workbook = TornadoTranslator.workbook(from: analysis)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(sheet.cell(at: "A1"), .text("Base Case Output"))
        if case .number(let value) = sheet.cell(at: "B1") {
            XCTAssertEqual(value, 100_000, accuracy: 0.01)
        } else {
            XCTFail("B1 should contain base case output value")
        }
    }

    func testColumnHeaders() {
        let analysis = makeSampleAnalysis()
        let workbook = TornadoTranslator.workbook(from: analysis)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(sheet.cell(at: "A3"), .text("Input Driver"))
        XCTAssertEqual(sheet.cell(at: "B3"), .text("Low Output"))
        XCTAssertEqual(sheet.cell(at: "C3"), .text("High Output"))
        XCTAssertEqual(sheet.cell(at: "D3"), .text("Impact"))
        XCTAssertEqual(sheet.cell(at: "E3"), .text("% of Base"))
    }

    func testDataRowsOrderedByImpact() {
        let analysis = makeSampleAnalysis()
        let workbook = TornadoTranslator.workbook(from: analysis)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(sheet.cell(at: "A4"), .text("Revenue"))
        XCTAssertEqual(sheet.cell(at: "A5"), .text("Cost of Goods"))
        XCTAssertEqual(sheet.cell(at: "A6"), .text("Tax Rate"))

        XCTAssertTrue(sheet.cell(at: "D4")?.isFormula == true)
        XCTAssertTrue(sheet.cell(at: "E4")?.isFormula == true)
    }

    func testCustomSheetName() {
        let analysis = makeSampleAnalysis()
        let workbook = TornadoTranslator.workbook(from: analysis, sheetName: "Drivers")

        XCTAssertEqual(workbook.sheets[0].name, "Drivers")
    }

    func testSavesToFile() throws {
        let analysis = makeSampleAnalysis()
        let workbook = TornadoTranslator.workbook(from: analysis)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tornado_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
