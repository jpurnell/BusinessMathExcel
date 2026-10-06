import Foundation
import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

@Suite struct TornadoTranslatorTests {

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

    @Test func createsWorkbook() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.tornadoWorkbook(from: analysis)

        #expect(workbook.sheets.count == 1)
        #expect(workbook.sheets[0].name == "Tornado Analysis")
    }

    @Test func baseCaseHeader() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.tornadoWorkbook(from: analysis)
        let sheet = workbook.sheets[0]

        #expect(sheet.cell(at: "A1") == .text("Base Case Output"))
        if case .number(let value) = sheet.cell(at: "B1") {
            #expect(abs(value - 100_000) <= 0.01)
        } else {
            Issue.record("B1 should contain base case output value")
        }
    }

    @Test func columnHeaders() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.tornadoWorkbook(from: analysis)
        let sheet = workbook.sheets[0]

        #expect(sheet.cell(at: "A3") == .text("Input Driver"))
        #expect(sheet.cell(at: "B3") == .text("Low Output"))
        #expect(sheet.cell(at: "C3") == .text("High Output"))
        #expect(sheet.cell(at: "D3") == .text("Impact"))
        #expect(sheet.cell(at: "E3") == .text("% of Base"))
    }

    @Test func dataRowsOrderedByImpact() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.tornadoWorkbook(from: analysis)
        let sheet = workbook.sheets[0]

        #expect(sheet.cell(at: "A4") == .text("Revenue"))
        #expect(sheet.cell(at: "A5") == .text("Cost of Goods"))
        #expect(sheet.cell(at: "A6") == .text("Tax Rate"))

        #expect(sheet.cell(at: "D4")?.isFormula == true)
        #expect(sheet.cell(at: "E4")?.isFormula == true)
    }

    @Test func customSheetName() {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.tornadoWorkbook(from: analysis, sheetName: "Drivers")

        #expect(workbook.sheets[0].name == "Drivers")
    }

    @Test func savesToFile() throws {
        let analysis = makeSampleAnalysis()
        let workbook = legacy.tornadoWorkbook(from: analysis)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tornado_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        #expect(try url.checkResourceIsReachable())
    }
}
