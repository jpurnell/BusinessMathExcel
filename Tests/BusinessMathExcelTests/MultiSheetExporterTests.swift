import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class MultiSheetExporterTests: XCTestCase {

    // MARK: - Single Section

    func testSingleSectionProducesOneSheet() throws {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)

        let wb = try MultiSheetExporter.export(model)

        XCTAssertEqual(wb.sheets.count, 1)
    }

    // MARK: - Multi-Section

    func testMultiSectionProducesMultipleSheets() throws {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addFormula(label: "Monthly", formula: .number(0.004167))
        model.addOutput(label: "Result", formula: .number(100))

        let wb = try MultiSheetExporter.export(model)

        XCTAssertEqual(wb.sheets.count, 3)
    }

    // MARK: - Cross-Sheet Formula

    func testCrossSheetFormulaResolvesToSheetReference() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.05)
        model.addOutput(label: "Result", formula: .multiply(.ref(rate), .number(100)))

        let wb = try MultiSheetExporter.export(model)

        XCTAssertEqual(wb.sheets.count, 2)

        let resultsSheet = wb.sheets.last
        XCTAssertNotNil(resultsSheet)

        let refs = resultsSheet?.cellReferences ?? []
        var foundSheetRef = false
        for ref in refs {
            if let ast = resultsSheet?.formulaAST(at: ref) {
                if astContainsSheetRef(ast) {
                    foundSheetRef = true
                    break
                }
            }
        }
        XCTAssertTrue(foundSheetRef, "Cross-sheet formula should contain a SheetReference")
    }

    private func astContainsSheetRef(_ ast: FormulaAST) -> Bool {
        switch ast {
        case .sheetRef:
            return true
        case .add(let l, let r), .subtract(let l, let r),
             .multiply(let l, let r), .divide(let l, let r):
            return astContainsSheetRef(l) || astContainsSheetRef(r)
        case .negate(let e):
            return astContainsSheetRef(e)
        case .function(_, let args):
            return args.contains { astContainsSheetRef($0) }
        default:
            return false
        }
    }

    // MARK: - Same-Sheet Formula

    func testSameSheetFormulaResolvesToLocalCellRef() throws {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 10)
        let b = model.addInput(label: "B", value: 20)
        model.addFormula(label: "Sum", formula: .add(.ref(a), .ref(b)), section: "Inputs")

        let wb = try MultiSheetExporter.export(model)

        XCTAssertEqual(wb.sheets.count, 1, "All nodes are in 'Inputs' section, so one sheet")
    }

    // MARK: - Title

    func testTitleWrittenOnEachSheet() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let wb = try MultiSheetExporter.export(model, title: "Test Model")

        XCTAssertEqual(wb.sheets.count, 2)
    }

    // MARK: - Custom Sheet Names

    func testCustomSheetNamesApplied() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let layout = MultiSheetLayoutStrategy(sheetNames: [
            "Inputs": "Parameters",
            "Results": "Output"
        ])
        let wb = try MultiSheetExporter.export(model, layout: layout)

        XCTAssertEqual(wb.sheets.count, 2)
    }

    // MARK: - Table Headers

    func testTableHeadersWrittenWhenPresent() throws {
        let model = ExcelModel()
        let r0c0 = model.addInput(label: "P1", value: 1, section: "Schedule")
        let r0c1 = model.addInput(label: "Amt1", value: 500, section: "Schedule")
        let r1c0 = model.addInput(label: "P2", value: 2, section: "Schedule")
        let r1c1 = model.addInput(label: "Amt2", value: 500, section: "Schedule")
        model.registerTable(
            label: "Schedule",
            columns: ["Period", "Amount"],
            rows: [[r0c0, r0c1], [r1c0, r1c1]]
        )

        let layout = MultiSheetLayoutStrategy(
            perSheetLayout: CompactLayoutStrategy()
        )
        let wb = try MultiSheetExporter.export(model, layout: layout)

        XCTAssertEqual(wb.sheets.count, 1)
    }

    // MARK: - Integration: DCF Model

    func testDCFModelMultiSheetExport() throws {
        let model = DCFModelBuilder.build(
            discountRate: 0.10,
            cashFlows: [-50_000, 15_000, 20_000, 25_000]
        )

        let wb = try MultiSheetExporter.export(model)

        XCTAssertGreaterThanOrEqual(wb.sheets.count, 2,
            "DCF model should produce at least 2 sheets")
    }
}
