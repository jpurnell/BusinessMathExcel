import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class ModelExporterTests: XCTestCase {

    private func makeSimpleModel() -> ExcelModel {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Quantity", value: 5)
        let price = model.node(named: "Price")!
        let qty = model.node(named: "Quantity")!
        model.addOutput(
            label: "Total",
            formula: .multiply(.ref(price), .ref(qty))
        )
        return model
    }

    // MARK: - Basic Export

    func testCreatesWorkbookWithOneSheet() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model)

        XCTAssertEqual(wb.sheets.count, 1)
    }

    func testDefaultSheetName() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model)

        XCTAssertEqual(wb.sheets[0].name, "Model")
    }

    func testCustomSheetName() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model, sheetName: "Revenue")

        XCTAssertEqual(wb.sheets[0].name, "Revenue")
    }

    // MARK: - Title

    func testWritesTitle() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model, title: "Revenue Model")
        let sheet = wb.sheets[0]

        XCTAssertEqual(sheet.cell(at: "C1"), .text("Revenue Model"))
    }

    func testCustomTitle() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model, title: "Cost Analysis")
        let sheet = wb.sheets[0]

        XCTAssertEqual(sheet.cell(at: "C1"), .text("Cost Analysis"))
    }

    // MARK: - Section Headers

    func testWritesSectionHeaders() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        XCTAssertEqual(sheet.cell(at: "C3"), .text("Inputs"))
    }

    // MARK: - Input Nodes

    func testWritesInputLabels() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        XCTAssertEqual(sheet.cell(at: "C4"), .text("Price"))
        XCTAssertEqual(sheet.cell(at: "C5"), .text("Quantity"))
    }

    func testWritesInputValues() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        if case .number(let value) = sheet.cell(at: "D4") {
            XCTAssertEqual(value, 100, accuracy: 0.01)
        } else {
            XCTFail("D4 should contain input value 100")
        }

        if case .number(let value) = sheet.cell(at: "D5") {
            XCTAssertEqual(value, 5, accuracy: 0.01)
        } else {
            XCTFail("D5 should contain input value 5")
        }
    }

    // MARK: - Formula Nodes

    func testWritesFormulaNode() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Annual Rate", value: 0.065)
        model.addFormula(
            label: "Monthly Rate",
            formula: .divide(.ref(rate), .number(12))
        )

        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let formulaCell = sheet.cell(at: "D7")
        XCTAssertNotNil(formulaCell)
        XCTAssertTrue(formulaCell?.isFormula == true)
    }

    // MARK: - Output Nodes

    func testWritesOutputAsFormula() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let outputRef = "D8"
        let outputCell = sheet.cell(at: outputRef)
        XCTAssertNotNil(outputCell)
        XCTAssertTrue(outputCell?.isFormula == true)
    }

    // MARK: - Label Nodes

    func testWritesLabelNode() throws {
        let model = ExcelModel()
        model.addLabel("Summary")

        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        XCTAssertEqual(sheet.cell(at: "D4"), .text("Summary"))
    }

    // MARK: - Text Input Nodes

    func testWritesTextInputNode() throws {
        let model = ExcelModel()
        model.addTextInput(label: "Title", value: "Loan Schedule")

        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        XCTAssertEqual(sheet.cell(at: "D4"), .text("Loan Schedule"))
    }

    // MARK: - Error Handling

    func testDanglingReferenceThrows() {
        let model = ExcelModel()
        let orphan = NodeRef(label: "Ghost")
        model.addOutput(label: "Bad", formula: .ref(orphan))

        XCTAssertThrowsError(try ModelExporter.export(model)) { error in
            XCTAssertTrue(error is ResolutionError)
        }
    }

    // MARK: - Financial Formulas

    func testPMTFormulaResolvesCorrectly() throws {
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

        let paymentAST = sheet.formulaAST(at: "D9")
        XCTAssertNotNil(paymentAST)

        if case .function(let name, let args) = paymentAST {
            XCTAssertEqual(name, "PMT")
            XCTAssertEqual(args.count, 3)
            XCTAssertEqual(args[0], .cellRef(CellRef(column: 4, row: 4)))
            XCTAssertEqual(args[1], .cellRef(CellRef(column: 4, row: 5)))
            XCTAssertEqual(args[2], .cellRef(CellRef(column: 4, row: 6)))
        } else {
            XCTFail("Expected PMT function")
        }
    }

    // MARK: - Round-Trip

    func testSavesToFile() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try wb.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRoundTripPreservesValues() throws {
        let model = makeSimpleModel()
        let wb = try ModelExporter.export(model, title: "Test")

        let data = try wb.save()
        let reloaded = try Workbook(xlsxData: data)

        XCTAssertEqual(reloaded.sheets.count, 1)
        XCTAssertEqual(reloaded.sheets[0].cell(at: "C1"), .text("Test"))
    }
}
