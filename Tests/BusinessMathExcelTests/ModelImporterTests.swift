import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class ModelImporterTests: XCTestCase {

    // MARK: - Empty Workbook

    func testEmptyWorkbookProducesEmptyModel() {
        let wb = Workbook()
        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.model.nodeCount, 0)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    // MARK: - Value Cells

    func testImportsNumberCellAsInput() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(42.0, to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.model.nodeCount, 1)

        let ref = result.model.node(named: "A1")
        XCTAssertNotNil(ref)
        if case .input(let value) = result.model.kind(of: ref!) {
            XCTAssertEqual(value, 42, accuracy: 0.01)
        } else {
            XCTFail("Expected input node")
        }
    }

    func testImportsTextCellAsTextInput() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write("Revenue", to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        let ref = result.model.node(named: "A1")
        XCTAssertNotNil(ref)
        XCTAssertEqual(result.model.kind(of: ref!), .textInput("Revenue"))
    }

    func testSkipsBlankCells() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A3")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.model.nodeCount, 2)
    }

    // MARK: - Formula Cells

    func testImportsFormulaCellAsFormula() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(10.0, to: "A1")
        sheet.write(20.0, to: "A2")
        sheet.write(
            FormulaAST.add(.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.model.nodeCount, 3)

        let formulaRef = result.model.node(named: "A3")
        XCTAssertNotNil(formulaRef)
        if case .formula = result.model.kind(of: formulaRef!) {
        } else {
            XCTFail("Expected formula node")
        }
    }

    func testFormulaReferencesResolveToNodes() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(100.0, to: "A1")
        sheet.write(
            FormulaAST.multiply(.cellRef(CellRef("A1")), .number(2)),
            to: "A2"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a1 = result.model.node(named: "A1")!
        let a2 = result.model.node(named: "A2")!

        if case .formula(let formula) = result.model.kind(of: a2) {
            if case .multiply(let lhs, let rhs) = formula {
                XCTAssertEqual(lhs, .ref(a1))
                XCTAssertEqual(rhs, .number(2))
            } else {
                XCTFail("Expected multiply formula")
            }
        } else {
            XCTFail("Expected formula node")
        }
    }

    func testImportsFunctionFormula() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(
            FormulaAST.function("SUM", [.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))]),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a3 = result.model.node(named: "A3")!

        if case .formula(let formula) = result.model.kind(of: a3) {
            if case .function(let name, let args) = formula {
                XCTAssertEqual(name, "SUM")
                XCTAssertEqual(args.count, 2)
            } else {
                XCTFail("Expected function formula")
            }
        } else {
            XCTFail("Expected formula node")
        }
    }

    // MARK: - Cell-to-Node Mapping

    func testCellToNodeMapping() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(42.0, to: "B3")

        let result = ModelImporter.importWorkbook(wb)
        let cellRef = CellRef("B3")
        XCTAssertNotNil(result.cellToNode[cellRef])
    }

    // MARK: - Round-Trip

    func testRoundTripExportImport() throws {
        let model = ExcelModel()
        let a = model.addInput(label: "Price", value: 100)
        let b = model.addInput(label: "Qty", value: 5)
        model.addOutput(label: "Total", formula: .multiply(.ref(a), .ref(b)))

        let wb = try ModelExporter.export(model, title: "Test")
        let result = ModelImporter.importWorkbook(wb)

        XCTAssertGreaterThan(result.model.nodeCount, 0)
    }

    // MARK: - Multiple Cells

    func testImportsMultipleCells() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "B1")
        sheet.write(3.0, to: "C1")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.model.nodeCount, 3)
    }

    // MARK: - Import Sheet

    func testImportSpecificSheet() {
        let wb = Workbook()
        wb.addSheet(name: "Empty")
        let data = wb.addSheet(name: "Data")
        data.write(42.0, to: "A1")

        let result = ModelImporter.importSheet(data)
        XCTAssertEqual(result.model.nodeCount, 1)
    }
}
