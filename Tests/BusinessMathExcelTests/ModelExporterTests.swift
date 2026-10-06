import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct ModelExporterTests {

    private func makeSimpleModel() throws -> ExcelModel {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Quantity", value: 5)
        let price = try #require(model.node(named: "Price"))
        let qty = try #require(model.node(named: "Quantity"))
        model.addOutput(
            label: "Total",
            formula: .multiply(.ref(price), .ref(qty))
        )
        return model
    }

    // MARK: - Basic Export

    @Test func createsWorkbookWithOneSheet() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model)

        #expect(wb.sheets.count == 1)
    }

    @Test func defaultSheetName() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model)

        #expect(wb.sheets[0].name == "Model")
    }

    @Test func customSheetName() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model, sheetName: "Revenue")

        #expect(wb.sheets[0].name == "Revenue")
    }

    // MARK: - Title

    @Test func writesTitle() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model, title: "Revenue Model")
        let sheet = wb.sheets[0]

        #expect(sheet.cell(at: "C1") == .text("Revenue Model"))
    }

    @Test func customTitle() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model, title: "Cost Analysis")
        let sheet = wb.sheets[0]

        #expect(sheet.cell(at: "C1") == .text("Cost Analysis"))
    }

    // MARK: - Section Headers

    @Test func writesSectionHeaders() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        #expect(sheet.cell(at: "C3") == .text("Inputs"))
    }

    // MARK: - Input Nodes

    @Test func writesInputLabels() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        #expect(sheet.cell(at: "C4") == .text("Price"))
        #expect(sheet.cell(at: "C5") == .text("Quantity"))
    }

    @Test func writesInputValues() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        if case .number(let value) = sheet.cell(at: "D4") {
            #expect(abs(value - 100) <= 0.01)
        } else {
            Issue.record("D4 should contain input value 100")
        }

        if case .number(let value) = sheet.cell(at: "D5") {
            #expect(abs(value - 5) <= 0.01)
        } else {
            Issue.record("D5 should contain input value 5")
        }
    }

    // MARK: - Formula Nodes

    @Test func writesFormulaNode() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Annual Rate", value: 0.065)
        model.addFormula(
            label: "Monthly Rate",
            formula: .divide(.ref(rate), .number(12))
        )

        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let formulaCell = try #require(sheet.cell(at: "D7"))
        #expect(formulaCell.isFormula == true)
    }

    // MARK: - Output Nodes

    @Test func writesOutputAsFormula() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let outputRef = "D8"
        let outputCell = try #require(sheet.cell(at: outputRef))
        #expect(outputCell.isFormula == true)
    }

    // MARK: - Label Nodes

    @Test func writesLabelNode() throws {
        let model = ExcelModel()
        model.addLabel("Summary")

        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        #expect(sheet.cell(at: "D4") == .text("Summary"))
    }

    // MARK: - Text Input Nodes

    @Test func writesTextInputNode() throws {
        let model = ExcelModel()
        model.addTextInput(label: "Title", value: "Loan Schedule")

        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        #expect(sheet.cell(at: "D4") == .text("Loan Schedule"))
    }

    // MARK: - Error Handling

    @Test func danglingReferenceThrows() {
        let model = ExcelModel()
        let orphan = NodeRef(label: "Ghost")
        model.addOutput(label: "Bad", formula: .ref(orphan))

        if let error = #expect(throws: (any Error).self, performing: { try ModelExporter.export(model) }) {
            #expect(error is ResolutionError)
        }
    }

    // MARK: - Financial Formulas

    @Test func pmtFormulaResolvesCorrectly() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.005)
        let nper = model.addInput(label: "Periods", value: 360)
        let pv = model.addInput(label: "Principal", value: 250_000)

        model.addOutput(
            label: "Payment",
            formula: .pmt(rate: .ref(rate), nper: .ref(nper), pv: .ref(pv))
        )

        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let paymentAST = try #require(sheet.formulaAST(at: "D9"))

        if case .function(let name, let args) = paymentAST {
            #expect(name == "PMT")
            #expect(args.count == 3)
            #expect(args[0] == .cellRef(CellRef(column: 4, row: 4)))
            #expect(args[1] == .cellRef(CellRef(column: 4, row: 5)))
            #expect(args[2] == .cellRef(CellRef(column: 4, row: 6)))
        } else {
            Issue.record("Expected PMT function")
        }
    }

    // MARK: - Round-Trip

    @Test func savesToFile() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try wb.save(to: url)
        #expect(try url.checkResourceIsReachable())
    }

    @Test func roundTripPreservesValues() throws {
        let model = try makeSimpleModel()
        let wb = try ModelExporter.export(model, title: "Test")

        let data = try wb.save()
        let reloaded = try Workbook(xlsxData: data)

        #expect(reloaded.sheets.count == 1)
        #expect(reloaded.sheets[0].cell(at: "C1") == .text("Test"))
    }
}
