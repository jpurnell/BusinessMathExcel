import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct DCFModelBuilderTests {

    private func makeModel() -> ExcelModel {
        DCFModelBuilder.build(
            discountRate: 0.10,
            cashFlows: [-1000, 300, 400, 500, 200]
        )
    }

    // MARK: - Input Nodes

    @Test func hasDiscountRateInput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Discount Rate"))
        if case .input(let value) = model.kind(of: ref) {
            #expect(abs(value - 0.10) <= 0.0001)
        } else {
            Issue.record("Expected input node")
        }
    }

    @Test func hasInitialInvestmentInput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Initial Investment"))
        if case .input(let value) = model.kind(of: ref) {
            #expect(abs(value - -1000) <= 0.01)
        } else {
            Issue.record("Expected input node")
        }
    }

    @Test func hasCashFlowInputs() throws {
        let model = makeModel()
        for year in 1...4 {
            let ref = try #require(model.node(named: "Year \(year) Cash Flow"))
            #expect(ref.label == "Year \(year) Cash Flow", "Missing input for year \(year)")
        }
    }

    // MARK: - Output Nodes

    @Test func hasNPVOutput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "NPV"))
        if case .output = model.kind(of: ref) {
        } else {
            Issue.record("Expected output node")
        }
    }

    @Test func hasIRROutput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "IRR"))
        if case .output = model.kind(of: ref) {
        } else {
            Issue.record("Expected output node")
        }
    }

    // MARK: - NPV Formula Structure

    @Test func npvFormulaIncludesInitialInvestment() throws {
        let model = makeModel()
        let npvRef = try #require(model.node(named: "NPV"))
        if case .output(let formula) = model.kind(of: npvRef) {
            if case .add(_, let npvCall) = formula {
                if case .function(let name, _) = npvCall {
                    #expect(name == "NPV")
                } else {
                    Issue.record("Expected NPV function")
                }
            } else {
                Issue.record("Expected add(initialInvestment, NPV(...))")
            }
        } else {
            Issue.record("Expected output node")
        }
    }

    @Test func irrFormulaReferencesAllCashFlows() throws {
        let model = makeModel()
        let irrRef = try #require(model.node(named: "IRR"))
        if case .output(let formula) = model.kind(of: irrRef) {
            if case .function(let name, let args) = formula {
                #expect(name == "IRR")
                if case .range(let refs) = args[0] {
                    #expect(refs.count == 5)
                } else {
                    Issue.record("Expected range argument containing all cash flow refs")
                }
            } else {
                Issue.record("Expected IRR function")
            }
        } else {
            Issue.record("Expected output node")
        }
    }

    // MARK: - Node Count

    @Test func nodeCount() {
        let model = makeModel()
        let expectedInputs = 1 + 5
        let expectedOutputs = 2
        #expect(model.nodeCount == (expectedInputs + expectedOutputs))
    }

    // MARK: - Export

    @Test func exportsToWorkbook() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "DCF Analysis", sheetName: "DCF")

        #expect(wb.sheets.count == 1)
        #expect(wb.sheets[0].name == "DCF")
    }

    @Test func exportedNPVFormula() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let npvRef = try #require(model.node(named: "NPV"))
        let npvCell = try #require(assignment.mapping[npvRef])

        let npvFormula = try #require(sheet.formulaAST(at: npvCell.reference))
        // The first flow is the outlay at time zero, so it sits outside NPV(), which
        // discounts from period one.
        #expect(FormulaSerializer.serialize(npvFormula) == "D7+NPV(D4,D8:D11)")
    }

    @Test func savesToFile() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "DCF")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcf_model_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try wb.save(to: url)
        #expect(try url.checkResourceIsReachable())
    }

    // MARK: - Range-Based Formulas

    @Test func irrExportsAsCellRange() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let irrRef = try #require(model.node(named: "IRR"))
        let irrCell = try #require(assignment.mapping[irrRef])

        let ast = try #require(sheet.formulaAST(at: irrCell.reference))

        let formula = FormulaSerializer.serialize(ast)
        #expect(formula.contains(":"), "IRR should use a cell range (A1:A5), got: \(formula)")
        #expect(!(formula.hasPrefix("IRR(D") && formula.contains(",D")), "IRR should not list individual cells, got: \(formula)")
    }

    @Test func npvExportsWithCellRange() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let npvRef = try #require(model.node(named: "NPV"))
        let npvCell = try #require(assignment.mapping[npvRef])

        let ast = try #require(sheet.formulaAST(at: npvCell.reference))

        let formula = FormulaSerializer.serialize(ast)
        #expect(formula.contains(":"), "NPV values should use a cell range, got: \(formula)")
    }

    // MARK: - Edge Cases

    @Test func minimalCashFlows() {
        let model = DCFModelBuilder.build(
            discountRate: 0.10,
            cashFlows: [-500, 600]
        )

        #expect(model.node(named: "NPV")?.label == "NPV")
        #expect(model.node(named: "IRR")?.label == "IRR")
    }

    @Test func singleCashFlowProducesNoOutputs() {
        let model = DCFModelBuilder.build(
            discountRate: 0.10,
            cashFlows: [-500]
        )

        #expect(model.node(named: "NPV") == nil)
        #expect(model.node(named: "IRR") == nil)
    }
}
