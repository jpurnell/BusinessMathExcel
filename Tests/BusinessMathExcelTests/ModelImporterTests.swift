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

    func testImportsNumberCellAsInput() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(42.0, to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.model.nodeCount, 1)

        let ref = try XCTUnwrap(result.model.node(named: "A1"))
        if case .input(let value) = result.model.kind(of: ref) {
            XCTAssertEqual(value, 42, accuracy: 0.01)
        } else {
            XCTFail("Expected input node")
        }
    }

    func testImportsTextCellAsTextInput() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write("Revenue", to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        let ref = try XCTUnwrap(result.model.node(named: "A1"))
        XCTAssertEqual(result.model.kind(of: ref), .textInput("Revenue"))
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

    func testImportsFormulaCellAsFormula() throws {
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

        let formulaRef = try XCTUnwrap(result.model.node(named: "A3"))
        if case .formula = result.model.kind(of: formulaRef) {
        } else {
            XCTFail("Expected formula node")
        }
    }

    func testFormulaReferencesResolveToNodes() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(100.0, to: "A1")
        sheet.write(
            FormulaAST.multiply(.cellRef(CellRef("A1")), .number(2)),
            to: "A2"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a1 = try XCTUnwrap(result.model.node(named: "A1"))
        let a2 = try XCTUnwrap(result.model.node(named: "A2"))

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

    func testImportsFunctionFormula() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(
            FormulaAST.function("SUM", [.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))]),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a3 = try XCTUnwrap(result.model.node(named: "A3"))

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

    // MARK: - Warnings for Unsupported Formula Nodes

    func testUnsupportedFormulaNodeProducesWarning() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(FormulaAST.namedRange("TaxRate"), to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertFalse(
            result.warnings.isEmpty,
            "An unsupported AST node must be reported, not silently dropped"
        )
    }

    func testUnsupportedFormulaWarningNamesCellAndNodeKind() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(FormulaAST.concatenate(.text("a"), .text("b")), to: "B7")

        let result = ModelImporter.importWorkbook(wb)
        let warning = try XCTUnwrap(result.warnings.first)
        XCTAssertTrue(warning.contains("B7"), "Warning should name the cell: \(warning)")
        XCTAssertTrue(
            warning.contains("concatenate"),
            "Warning should name the node kind: \(warning)"
        )
    }

    func testNestedUnsupportedNodeProducesWarning() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(
            FormulaAST.add(.cellRef(CellRef("A1")), .namedRange("Adjustment")),
            to: "A2"
        )

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertFalse(
            result.warnings.isEmpty,
            "Unsupported nodes nested inside a supported operator must still warn"
        )
    }

    func testFullySupportedFormulaProducesNoWarnings() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(
            FormulaAST.add(.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    // MARK: - Cell Ranges

    func testImportsCellRangeAsRange() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        for row in 5...16 {
            sheet.write(Double(row), to: "D\(row)")
        }
        sheet.write(
            FormulaAST.function("SUM", [.cellRange(CellRange(from: "D5", to: "D16"))]),
            to: "D17"
        )

        let result = ModelImporter.importWorkbook(wb)
        let d17 = try XCTUnwrap(result.model.node(named: "D17"))
        guard case .formula(let formula) = try XCTUnwrap(result.model.kind(of: d17)) else {
            return XCTFail("Expected formula node")
        }
        guard case .function(let name, let args) = formula else {
            return XCTFail("Expected function formula, got \(formula)")
        }
        XCTAssertEqual(name, "SUM")
        guard case .range(let refs) = args.first else {
            return XCTFail("Expected a range argument, got \(String(describing: args.first))")
        }
        XCTAssertEqual(refs.count, 12)
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testBareCellRangeImportsAsRange() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(FormulaAST.cellRange(CellRange(from: "A1", to: "A2")), to: "A3")

        let result = ModelImporter.importWorkbook(wb)
        let a3 = try XCTUnwrap(result.model.node(named: "A3"))
        guard case .formula(.range(let refs)) = try XCTUnwrap(result.model.kind(of: a3)) else {
            return XCTFail("Expected a range formula")
        }
        XCTAssertEqual(refs.count, 2)
    }

    func testCellRangeToleratesBlankInteriorCells() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        // D9 is left blank — a separator row inside a summed range is ordinary Excel,
        // and must not poison the range.
        for row in 5...16 where row != 9 {
            sheet.write(Double(row), to: "D\(row)")
        }
        sheet.write(
            FormulaAST.function("SUM", [.cellRange(CellRange(from: "D5", to: "D16"))]),
            to: "D17"
        )

        let result = ModelImporter.importWorkbook(wb)
        let d17 = try XCTUnwrap(result.model.node(named: "D17"))
        guard case .formula(.function(_, let args)) = try XCTUnwrap(result.model.kind(of: d17)),
              case .range(let refs) = args.first else {
            return XCTFail("Expected a range argument")
        }
        XCTAssertEqual(refs.count, 11, "Blank interior cells are skipped, not fatal")
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testUnanchoredCellRangeWarnsAndDegrades() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        // The formula sits above the cells it sums, so neither endpoint has been
        // imported when the range is converted.
        sheet.write(
            FormulaAST.function("SUM", [.cellRange(CellRange(from: "D5", to: "D16"))]),
            to: "A1"
        )
        for row in 5...16 {
            sheet.write(Double(row), to: "D\(row)")
        }

        let result = ModelImporter.importWorkbook(wb)
        let warning = try XCTUnwrap(result.warnings.first)
        XCTAssertTrue(warning.contains("D5:D16"), "Warning should name the range: \(warning)")
        XCTAssertTrue(warning.contains("A1"), "Warning should name the cell: \(warning)")
    }

    func testCellRangeResolvesBackToACellRangeOnExport() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        for row in 5...16 {
            sheet.write(Double(row), to: "D\(row)")
        }
        sheet.write(
            FormulaAST.function("SUM", [.cellRange(CellRange(from: "D5", to: "D16"))]),
            to: "D17"
        )

        let result = ModelImporter.importWorkbook(wb)
        let exported = try ModelExporter.export(result.model, title: "Round Trip")
        let outSheet = try XCTUnwrap(exported.sheets.first)
        let sumCell = try XCTUnwrap(
            outSheet.cellReferences
                .compactMap { outSheet.cell(at: $0)?.formulaAST }
                .first { if case .function("SUM", _) = $0 { return true } else { return false } }
        )
        guard case .function(_, let args) = sumCell, case .cellRange = args.first else {
            return XCTFail("SUM should export a single CellRange argument, got \(sumCell)")
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
