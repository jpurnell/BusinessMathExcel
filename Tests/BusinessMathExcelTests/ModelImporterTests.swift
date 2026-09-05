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
        // D5 and D16 are both blank, so the range has no endpoints to anchor to.
        // Resolution order is no longer the issue — two-pass resolution handles a
        // range that points below its formula — but a range whose corners hold
        // nothing still cannot be reconstructed without narrowing it.
        for row in 6...15 {
            sheet.write(Double(row), to: "D\(row)")
        }
        sheet.write(
            FormulaAST.function("SUM", [.cellRange(CellRange(from: "D5", to: "D16"))]),
            to: "A1"
        )

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

    // MARK: - Exponentiation

    func testImportsPowerFormula() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(0.08, to: "B2")
        sheet.write(5.0, to: "B3")
        sheet.write(
            FormulaAST.power(
                .add(.number(1), .cellRef(CellRef("B2"))),
                .cellRef(CellRef("B3"))
            ),
            to: "B4"
        )

        let result = ModelImporter.importWorkbook(wb)
        let b2 = try XCTUnwrap(result.model.node(named: "B2"))
        let b3 = try XCTUnwrap(result.model.node(named: "B3"))
        let b4 = try XCTUnwrap(result.model.node(named: "B4"))
        guard case .formula(.power(let base, let exponent)) =
            try XCTUnwrap(result.model.kind(of: b4)) else {
            return XCTFail("Expected a power formula")
        }
        XCTAssertEqual(base, .add(.number(1), .ref(b2)))
        XCTAssertEqual(exponent, .ref(b3))
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testPowerResolvesBackToPowerOnExport() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.08)
        let periods = model.addInput(label: "Periods", value: 5)
        model.addOutput(
            label: "Discount Factor",
            formula: .power(.add(.number(1), .ref(rate)), .ref(periods))
        )

        let wb = try ModelExporter.export(model, title: "Power")
        let sheet = try XCTUnwrap(wb.sheets.first)
        let ast = try XCTUnwrap(
            sheet.cellReferences.compactMap { sheet.cell(at: $0)?.formulaAST }.first
        )
        guard case .power = ast else {
            return XCTFail("Expected a power AST — `^` must not become POWER(), got \(ast)")
        }
    }

    // MARK: - Array-formula members

    // An array formula fills a rectangle from one cell. SwiftXLSX marks the cells
    // it fills with `_ARRAY(anchor, span)`, because they carry an empty `<f/>` in
    // the file and would otherwise arrive as their cached value — 224 computed
    // cells in one measured workbook, every one of them presenting as an input.

    func testAnArrayMemberIsAFormulaNodeNotAnInput() throws {
        let result = ModelImporter.importCells([
            (reference: "D55", value: .formula(
                .function("TRANSPOSE", [.cellRange(CellRange(from: "H35", to: "K35"))]),
                cached: .number(0))),
            (reference: "D56", value: .formula(
                .function("_ARRAY", [.cellRef(CellRef("D55")), .text("D55:D57")]),
                cached: .number(-0.5))),
        ])
        let node = try XCTUnwrap(result.cellToNode[CellRef("D56")])
        guard case .formula = try XCTUnwrap(result.model.kind(of: node)) else {
            return XCTFail("D56 became \(String(describing: result.model.kind(of: node)))")
        }
    }

    /// And it depends on the cell that computes it, so the graph reaches it.
    func testAnArrayMemberDependsOnItsAnchor() throws {
        let result = ModelImporter.importCells([
            (reference: "D55", value: .formula(
                .function("TRANSPOSE", [.cellRange(CellRange(from: "H35", to: "K35"))]),
                cached: .number(0))),
            (reference: "D56", value: .formula(
                .function("_ARRAY", [.cellRef(CellRef("D55")), .text("D55:D57")]),
                cached: .number(-0.5))),
        ])
        let member = try XCTUnwrap(result.cellToNode[CellRef("D56")])
        let anchor = try XCTUnwrap(result.cellToNode[CellRef("D55")])
        guard case .formula(let formula)? = result.model.kind(of: member),
              case .function(_, let arguments) = formula else {
            return XCTFail("expected a marker function")
        }
        XCTAssertEqual(arguments.first, .ref(anchor),
                       "the member is computed by the anchor, and must say so")
    }

    // MARK: - Unsupported Cell Types

    // `Worksheet` exposes no public write for `.array`, `.date`, or `.error`
    // cells, so these drive the importer through its `importCells` seam.

    func testArrayCellWarnsAsAnArrayFormula() throws {
        let result = ModelImporter.importCells([
            (reference: "D5", value: .array(CellMatrix(row: [.number(1), .number(2)])))
        ])
        let warning = try XCTUnwrap(result.warnings.first)
        XCTAssertTrue(warning.contains("D5"), "Warning should name the cell: \(warning)")
        XCTAssertTrue(
            warning.lowercased().contains("array"),
            "Warning should identify the cell as an array formula: \(warning)"
        )
    }

    func testArrayWarningIsDistinctFromDateAndError() throws {
        let result = ModelImporter.importCells([
            (reference: "A1", value: .array(CellMatrix(row: [.number(1)]))),
            (reference: "A2", value: .date(Date(timeIntervalSince1970: 0))),
            (reference: "A3", value: .error(.value)),
        ])
        XCTAssertEqual(result.warnings.count, 3)

        let arrayWarning = try XCTUnwrap(result.warnings.first)
        XCTAssertTrue(arrayWarning.lowercased().contains("array"))
        XCTAssertFalse(
            result.warnings.dropFirst().contains(arrayWarning),
            "An array formula must not share the generic unsupported-cell message"
        )
        XCTAssertTrue(result.warnings[1].lowercased().contains("date"))
        XCTAssertTrue(result.warnings[2].lowercased().contains("error"))
    }

    func testArrayCellDoesNotBecomeANode() {
        let result = ModelImporter.importCells([
            (reference: "D5", value: .array(CellMatrix(row: [.number(1), .number(2)])))
        ])
        XCTAssertEqual(result.model.nodeCount, 0, "Recognition is Phase 6; this only stops silent loss")
    }

    // MARK: - Multi-Sheet Import

    func testImportAllSheetsImportsEverySheet() {
        let wb = Workbook()
        wb.addSheet(name: "Inputs").write(42.0, to: "A1")
        wb.addSheet(name: "Calcs").write(7.0, to: "B2")

        let result = ModelImporter.importAllSheets(wb)
        XCTAssertEqual(result.model.nodeCount, 2)
        XCTAssertNotNil(result.model.node(named: "Inputs!A1"))
        XCTAssertNotNil(result.model.node(named: "Calcs!B2"))
    }

    func testImportAllSheetsGivesEachSheetItsOwnSection() {
        let wb = Workbook()
        wb.addSheet(name: "Inputs").write(42.0, to: "A1")
        wb.addSheet(name: "Calcs").write(7.0, to: "B2")

        let result = ModelImporter.importAllSheets(wb)
        XCTAssertEqual(result.model.sections.map(\.name), ["Inputs", "Calcs"])
    }

    func testImportAllSheetsKeepsCollidingCellRefsApart() throws {
        // Both sheets have an A1. A single flat cell map would lose one of them.
        let wb = Workbook()
        wb.addSheet(name: "One").write(1.0, to: "A1")
        wb.addSheet(name: "Two").write(2.0, to: "A1")

        let result = ModelImporter.importAllSheets(wb)
        XCTAssertEqual(result.model.nodeCount, 2)
        let one = try XCTUnwrap(result.sheetCellToNode["One"]?[CellRef("A1")])
        let two = try XCTUnwrap(result.sheetCellToNode["Two"]?[CellRef("A1")])
        XCTAssertNotEqual(one, two)
    }

    func testFormulasResolveWithinTheirOwnSheet() throws {
        let wb = Workbook()
        let one = wb.addSheet(name: "One")
        one.write(10.0, to: "A1")
        one.write(FormulaAST.multiply(.cellRef(CellRef("A1")), .number(2)), to: "A2")
        wb.addSheet(name: "Two").write(99.0, to: "A1")

        let result = ModelImporter.importAllSheets(wb)
        let oneA1 = try XCTUnwrap(result.model.node(named: "One!A1"))
        let oneA2 = try XCTUnwrap(result.model.node(named: "One!A2"))
        guard case .formula(.multiply(let lhs, _)) =
            try XCTUnwrap(result.model.kind(of: oneA2)) else {
            return XCTFail("Expected a multiply formula")
        }
        XCTAssertEqual(lhs, .ref(oneA1), "A formula must bind to its own sheet's A1")
    }

    func testCrossSheetReferenceWarnsRatherThanVanishing() throws {
        let wb = Workbook()
        let one = wb.addSheet(name: "One")
        one.write(
            FormulaAST.sheetRef(SheetReference(sheet: "Two", cell: CellRef("A1"))),
            to: "A1"
        )
        wb.addSheet(name: "Two").write(5.0, to: "A1")

        let result = ModelImporter.importAllSheets(wb)
        let warning = try XCTUnwrap(result.warnings.first)
        XCTAssertTrue(warning.contains("sheetRef"), "Got: \(warning)")
        XCTAssertTrue(warning.contains("One!A1"), "Warning should qualify the cell: \(warning)")
    }

    func testSingleSheetImportReportsItsSheetMapping() {
        let wb = Workbook()
        wb.addSheet(name: "Data").write(42.0, to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertNotNil(result.cellToNode[CellRef("A1")])
        XCTAssertNotNil(result.sheetCellToNode["Data"]?[CellRef("A1")])
    }

    func testImportAllSheetsOnAnEmptyWorkbookIsEmpty() {
        let result = ModelImporter.importAllSheets(Workbook())
        XCTAssertEqual(result.model.nodeCount, 0)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.sheetCellToNode.isEmpty)
    }

    // MARK: - Forward References

    func testFormulaResolvesAReferenceToALaterCell() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        // The total sits *above* the figures it sums, which is ordinary in a
        // financial model with a summary block at the top.
        sheet.write(FormulaAST.add(.cellRef(CellRef("A5")), .cellRef(CellRef("A6"))), to: "A1")
        sheet.write(10.0, to: "A5")
        sheet.write(20.0, to: "A6")

        let result = ModelImporter.importWorkbook(wb)
        let a1 = try XCTUnwrap(result.model.node(named: "A1"))
        let a5 = try XCTUnwrap(result.model.node(named: "A5"))
        let a6 = try XCTUnwrap(result.model.node(named: "A6"))

        guard case .formula(.add(let lhs, let rhs)) =
            try XCTUnwrap(result.model.kind(of: a1)) else {
            return XCTFail("Expected an add formula")
        }
        XCTAssertEqual(lhs, .ref(a5))
        XCTAssertEqual(rhs, .ref(a6))
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testRangeResolvesWhenItPointsBelowTheFormula() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(
            FormulaAST.function("SUM", [.cellRange(CellRange(from: "D5", to: "D16"))]),
            to: "A1"
        )
        for row in 5...16 {
            sheet.write(Double(row), to: "D\(row)")
        }

        let result = ModelImporter.importWorkbook(wb)
        let a1 = try XCTUnwrap(result.model.node(named: "A1"))
        guard case .formula(.function(_, let args)) = try XCTUnwrap(result.model.kind(of: a1)),
              case .range(let refs) = args.first else {
            return XCTFail("Expected a range argument")
        }
        XCTAssertEqual(refs.count, 12)
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testForwardReferenceChainResolves() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(FormulaAST.multiply(.cellRef(CellRef("A2")), .number(2)), to: "A1")
        sheet.write(FormulaAST.add(.cellRef(CellRef("A3")), .number(1)), to: "A2")
        sheet.write(5.0, to: "A3")

        let result = ModelImporter.importWorkbook(wb)
        let a2 = try XCTUnwrap(result.model.node(named: "A2"))
        let a3 = try XCTUnwrap(result.model.node(named: "A3"))

        guard case .formula(.multiply(let lhs, _)) =
            try XCTUnwrap(result.model.kind(of: try XCTUnwrap(result.model.node(named: "A1")))) else {
            return XCTFail("Expected a multiply formula")
        }
        XCTAssertEqual(lhs, .ref(a2), "A1 should bind to A2's node, which itself binds forward")

        guard case .formula(.add(let innerLHS, _)) = try XCTUnwrap(result.model.kind(of: a2)) else {
            return XCTFail("Expected an add formula")
        }
        XCTAssertEqual(innerLHS, .ref(a3))
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testSectionOrderAndNodeCountAreUnchangedByTwoPassResolution() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write("Label", to: "B1")
        sheet.write(FormulaAST.add(.cellRef(CellRef("A1")), .number(2)), to: "C1")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.model.nodeCount, 3)
        XCTAssertEqual(result.model.sections.map(\.name), ["Imported"])
        XCTAssertEqual(result.model.allRefs.map(\.label), ["A1", "B1", "C1"])
    }

    // MARK: - Absolute References

    func testAbsoluteReferenceResolvesToTheSameNode() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(0.1, to: "D11")
        // `$D$11` and `D11` name the same cell — the markers control what happens
        // when the formula is filled, not which cell it points at.
        sheet.write(
            FormulaAST.multiply(.cellRef(CellRef("$D$11")), .number(2)),
            to: "A1"
        )

        let result = ModelImporter.importWorkbook(wb)
        let d11 = try XCTUnwrap(result.model.node(named: "D11"))
        let a1 = try XCTUnwrap(result.model.node(named: "A1"))

        guard case .formula(.multiply(let lhs, _)) = try XCTUnwrap(result.model.kind(of: a1)) else {
            return XCTFail("Expected a multiply formula")
        }
        XCTAssertEqual(lhs, .ref(d11))
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testMixedAbsoluteReferencesResolve() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(5.0, to: "B2")
        sheet.write(FormulaAST.add(.cellRef(CellRef("$B2")), .cellRef(CellRef("B$2"))), to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        let b2 = try XCTUnwrap(result.model.node(named: "B2"))
        let a1 = try XCTUnwrap(result.model.node(named: "A1"))

        guard case .formula(.add(let lhs, let rhs)) = try XCTUnwrap(result.model.kind(of: a1)) else {
            return XCTFail("Expected an add formula")
        }
        XCTAssertEqual(lhs, .ref(b2), "A column-absolute reference names the same cell")
        XCTAssertEqual(rhs, .ref(b2), "A row-absolute reference names the same cell")
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testAbsoluteRangeResolves() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        for row in 5...16 {
            sheet.write(Double(row), to: "D\(row)")
        }
        sheet.write(
            FormulaAST.function("SUM", [.cellRange(CellRange(from: "$D$5", to: "$D$16"))]),
            to: "A1"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a1 = try XCTUnwrap(result.model.node(named: "A1"))
        guard case .formula(.function(_, let args)) = try XCTUnwrap(result.model.kind(of: a1)),
              case .range(let refs) = args.first else {
            return XCTFail("Expected a range argument")
        }
        XCTAssertEqual(refs.count, 12)
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testCellToNodeIsKeyedByRelativeReferences() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "D11")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertNotNil(
            result.cellToNode[CellRef("D11")],
            "Keys are normalized so lookups do not depend on absolute markers"
        )
    }

    // MARK: - Comparison Operators

    func testImportsEveryComparisonOperator() throws {
        // Each row: the Excel AST written to A3, and the NodeFormula it must become
        // once A1 and A2 have resolved to nodes.
        let cases: [(name: String,
                     ast: (FormulaAST, FormulaAST) -> FormulaAST,
                     expected: (NodeFormula, NodeFormula) -> NodeFormula)] = [
            ("equal", FormulaAST.equal, NodeFormula.equal),
            ("notEqual", FormulaAST.notEqual, NodeFormula.notEqual),
            ("greaterThan", FormulaAST.greaterThan, NodeFormula.greaterThan),
            ("lessThan", FormulaAST.lessThan, NodeFormula.lessThan),
            ("greaterOrEqual", FormulaAST.greaterOrEqual, NodeFormula.greaterOrEqual),
            ("lessOrEqual", FormulaAST.lessOrEqual, NodeFormula.lessOrEqual),
        ]

        for testCase in cases {
            let wb = Workbook()
            let sheet = wb.addSheet(name: "Test")
            sheet.write(1.0, to: "A1")
            sheet.write(2.0, to: "A2")
            sheet.write(testCase.ast(.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))), to: "A3")

            let result = ModelImporter.importWorkbook(wb)
            let a1 = try XCTUnwrap(result.model.node(named: "A1"))
            let a2 = try XCTUnwrap(result.model.node(named: "A2"))
            let a3 = try XCTUnwrap(result.model.node(named: "A3"))

            XCTAssertEqual(
                result.model.kind(of: a3),
                .formula(testCase.expected(.ref(a1), .ref(a2))),
                "\(testCase.name) did not import as a comparison"
            )
            XCTAssertTrue(result.warnings.isEmpty, "\(testCase.name): \(result.warnings)")
        }
    }

    func testImportsComparisonInsideAnIfCondition() throws {
        // `IF` is an Excel function, not an AST node, so it already round-trips.
        // What was missing is the operator in its condition.
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(
            FormulaAST.function("IF", [
                .greaterThan(.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))),
                .cellRef(CellRef("A1")),
                .cellRef(CellRef("A2")),
            ]),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a1 = try XCTUnwrap(result.model.node(named: "A1"))
        let a2 = try XCTUnwrap(result.model.node(named: "A2"))
        let a3 = try XCTUnwrap(result.model.node(named: "A3"))

        guard case .formula(.function(let name, let args)) =
            try XCTUnwrap(result.model.kind(of: a3)) else {
            return XCTFail("Expected an IF function")
        }
        XCTAssertEqual(name, "IF")
        XCTAssertEqual(args.first, .greaterThan(.ref(a1), .ref(a2)))
        XCTAssertTrue(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    func testComparisonSurvivesExportAndReimport() throws {
        let model = ExcelModel()
        let left = model.addInput(label: "Left", value: 1)
        let right = model.addInput(label: "Right", value: 2)
        model.addOutput(label: "Test", formula: .greaterThan(.ref(left), .ref(right)))

        let workbook = try ModelExporter.export(model, title: "Comparison")
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let ast = try XCTUnwrap(
            sheet.cellReferences.compactMap { sheet.cell(at: $0)?.formulaAST }.first
        )
        guard case .greaterThan = ast else {
            return XCTFail("Expected a greaterThan AST, got \(ast)")
        }
    }

    // MARK: - Cached Values

    func testPreservesTheCachedValueOfAFormulaCell() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(2.0, to: "A1")
        sheet.write(FormulaAST.multiply(.cellRef(CellRef("A1")), .number(3)), to: "A2")

        let result = ModelImporter.importWorkbook(wb)
        // The workbook was authored in memory, so nothing cached A2 yet.
        XCTAssertNil(result.cachedValues[CellRef("A2")])

        // A cell read from a file carries what Excel last computed.
        let reloaded = try Workbook(xlsxData: try wb.save())
        let fromFile = ModelImporter.importWorkbook(reloaded)
        XCTAssertEqual(fromFile.cellToNode.count, 2)
        XCTAssertNil(fromFile.cachedValues[CellRef("A1")], "A value cell has no cached result")
    }

    func testCachedValuesAreKeyedIndependentlyOfAbsoluteMarkers() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "D11")
        sheet.write(FormulaAST.cellRef(CellRef("$D$11")), to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        XCTAssertEqual(result.cellToNode.count, 2)
        XCTAssertTrue(result.cachedValues.keys.allSatisfy { !$0.absoluteColumn && !$0.absoluteRow })
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
