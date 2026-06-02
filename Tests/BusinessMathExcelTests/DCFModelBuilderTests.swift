import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class DCFModelBuilderTests: XCTestCase {

    private func makeModel() -> ExcelModel {
        DCFModelBuilder.build(
            discountRate: 0.10,
            cashFlows: [-1000, 300, 400, 500, 200]
        )
    }

    // MARK: - Input Nodes

    func testHasDiscountRateInput() {
        let model = makeModel()
        let ref = model.node(named: "Discount Rate")
        XCTAssertNotNil(ref)
        if case .input(let value) = model.kind(of: ref!) {
            XCTAssertEqual(value, 0.10, accuracy: 0.0001)
        } else {
            XCTFail("Expected input node")
        }
    }

    func testHasInitialInvestmentInput() {
        let model = makeModel()
        let ref = model.node(named: "Initial Investment")
        XCTAssertNotNil(ref)
        if case .input(let value) = model.kind(of: ref!) {
            XCTAssertEqual(value, -1000, accuracy: 0.01)
        } else {
            XCTFail("Expected input node")
        }
    }

    func testHasCashFlowInputs() {
        let model = makeModel()
        for year in 1...4 {
            let ref = model.node(named: "Year \(year) Cash Flow")
            XCTAssertNotNil(ref, "Missing input for year \(year)")
        }
    }

    // MARK: - Output Nodes

    func testHasNPVOutput() {
        let model = makeModel()
        let ref = model.node(named: "NPV")
        XCTAssertNotNil(ref)
        if case .output = model.kind(of: ref!) {
        } else {
            XCTFail("Expected output node")
        }
    }

    func testHasIRROutput() {
        let model = makeModel()
        let ref = model.node(named: "IRR")
        XCTAssertNotNil(ref)
        if case .output = model.kind(of: ref!) {
        } else {
            XCTFail("Expected output node")
        }
    }

    // MARK: - NPV Formula Structure

    func testNPVFormulaIncludesInitialInvestment() {
        let model = makeModel()
        let npvRef = model.node(named: "NPV")!
        if case .output(let formula) = model.kind(of: npvRef) {
            if case .add(_, let npvCall) = formula {
                if case .function(let name, _) = npvCall {
                    XCTAssertEqual(name, "NPV")
                } else {
                    XCTFail("Expected NPV function")
                }
            } else {
                XCTFail("Expected add(initialInvestment, NPV(...))")
            }
        } else {
            XCTFail("Expected output node")
        }
    }

    func testIRRFormulaReferencesAllCashFlows() {
        let model = makeModel()
        let irrRef = model.node(named: "IRR")!
        if case .output(let formula) = model.kind(of: irrRef) {
            if case .function(let name, let args) = formula {
                XCTAssertEqual(name, "IRR")
                if case .range(let refs) = args[0] {
                    XCTAssertEqual(refs.count, 5)
                } else {
                    XCTFail("Expected range argument containing all cash flow refs")
                }
            } else {
                XCTFail("Expected IRR function")
            }
        } else {
            XCTFail("Expected output node")
        }
    }

    // MARK: - Node Count

    func testNodeCount() {
        let model = makeModel()
        let expectedInputs = 1 + 5
        let expectedOutputs = 2
        XCTAssertEqual(model.nodeCount, expectedInputs + expectedOutputs)
    }

    // MARK: - Export

    func testExportsToWorkbook() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "DCF Analysis", sheetName: "DCF")

        XCTAssertEqual(wb.sheets.count, 1)
        XCTAssertEqual(wb.sheets[0].name, "DCF")
    }

    func testExportedNPVFormula() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let npvRef = model.node(named: "NPV")!
        let npvCell = assignment.mapping[npvRef]!

        let ast = sheet.formulaAST(at: npvCell.reference)
        XCTAssertNotNil(ast)
        XCTAssertTrue(ast != nil)
    }

    func testSavesToFile() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "DCF")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcf_model_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try wb.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Range-Based Formulas

    func testIRRExportsAsCellRange() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let irrRef = model.node(named: "IRR")!
        let irrCell = assignment.mapping[irrRef]!

        let ast = sheet.formulaAST(at: irrCell.reference)
        XCTAssertNotNil(ast)

        let formula = FormulaSerializer.serialize(ast!)
        XCTAssertTrue(
            formula.contains(":"),
            "IRR should use a cell range (A1:A5), got: \(formula)"
        )
        XCTAssertFalse(
            formula.hasPrefix("IRR(D") && formula.contains(",D"),
            "IRR should not list individual cells, got: \(formula)"
        )
    }

    func testNPVExportsWithCellRange() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let npvRef = model.node(named: "NPV")!
        let npvCell = assignment.mapping[npvRef]!

        let ast = sheet.formulaAST(at: npvCell.reference)
        XCTAssertNotNil(ast)

        let formula = FormulaSerializer.serialize(ast!)
        XCTAssertTrue(
            formula.contains(":"),
            "NPV values should use a cell range, got: \(formula)"
        )
    }

    // MARK: - Edge Cases

    func testMinimalCashFlows() {
        let model = DCFModelBuilder.build(
            discountRate: 0.10,
            cashFlows: [-500, 600]
        )

        XCTAssertNotNil(model.node(named: "NPV"))
        XCTAssertNotNil(model.node(named: "IRR"))
    }

    func testSingleCashFlowProducesNoOutputs() {
        let model = DCFModelBuilder.build(
            discountRate: 0.10,
            cashFlows: [-500]
        )

        XCTAssertNil(model.node(named: "NPV"))
        XCTAssertNil(model.node(named: "IRR"))
    }
}
