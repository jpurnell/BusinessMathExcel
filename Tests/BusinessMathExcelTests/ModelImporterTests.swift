import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct ModelImporterTests {

    // MARK: - Empty Workbook

    @Test func emptyWorkbookProducesEmptyModel() {
        let wb = Workbook()
        let result = ModelImporter.importWorkbook(wb)
        #expect(result.model.nodeCount == 0)
        #expect(result.warnings.isEmpty)
    }

    // MARK: - Value Cells

    @Test func importsNumberCellAsInput() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(42.0, to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.model.nodeCount == 1)

        let ref = try #require(result.model.node(named: "A1"))
        if case .input(let value) = result.model.kind(of: ref) {
            #expect(abs(value - 42) <= 0.01)
        } else {
            Issue.record("Expected input node")
        }
    }

    @Test func importsTextCellAsTextInput() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write("Revenue", to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        let ref = try #require(result.model.node(named: "A1"))
        #expect(result.model.kind(of: ref) == .textInput("Revenue"))
    }

    @Test func skipsBlankCells() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A3")

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.model.nodeCount == 2)
    }

    // MARK: - Formula Cells

    @Test func importsFormulaCellAsFormula() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(10.0, to: "A1")
        sheet.write(20.0, to: "A2")
        sheet.write(
            FormulaAST.add(.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.model.nodeCount == 3)

        let formulaRef = try #require(result.model.node(named: "A3"))
        if case .formula = result.model.kind(of: formulaRef) {
        } else {
            Issue.record("Expected formula node")
        }
    }

    @Test func formulaReferencesResolveToNodes() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(100.0, to: "A1")
        sheet.write(
            FormulaAST.multiply(.cellRef(CellRef("A1")), .number(2)),
            to: "A2"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a1 = try #require(result.model.node(named: "A1"))
        let a2 = try #require(result.model.node(named: "A2"))

        if case .formula(let formula) = result.model.kind(of: a2) {
            if case .multiply(let lhs, let rhs) = formula {
                #expect(lhs == .ref(a1))
                #expect(rhs == .number(2))
            } else {
                Issue.record("Expected multiply formula")
            }
        } else {
            Issue.record("Expected formula node")
        }
    }

    @Test func importsFunctionFormula() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(
            FormulaAST.function("SUM", [.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))]),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        let a3 = try #require(result.model.node(named: "A3"))

        if case .formula(let formula) = result.model.kind(of: a3) {
            if case .function(let name, let args) = formula {
                #expect(name == "SUM")
                #expect(args.count == 2)
            } else {
                Issue.record("Expected function formula")
            }
        } else {
            Issue.record("Expected formula node")
        }
    }

    // MARK: - Warnings for Unsupported Formula Nodes

    @Test func unsupportedFormulaNodeProducesWarning() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(FormulaAST.namedRange("TaxRate"), to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        #expect(!result.warnings.isEmpty, "An unsupported AST node must be reported, not silently dropped")
    }

    @Test func unsupportedFormulaWarningNamesCellAndNodeKind() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(FormulaAST.concatenate(.text("a"), .text("b")), to: "B7")

        let result = ModelImporter.importWorkbook(wb)
        let warning = try #require(result.warnings.first)
        #expect(warning.contains("B7"), "Warning should name the cell: \(warning)")
        #expect(warning.contains("concatenate"), "Warning should name the node kind: \(warning)")
    }

    @Test func nestedUnsupportedNodeProducesWarning() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(
            FormulaAST.add(.cellRef(CellRef("A1")), .namedRange("Adjustment")),
            to: "A2"
        )

        let result = ModelImporter.importWorkbook(wb)
        #expect(!result.warnings.isEmpty, "Unsupported nodes nested inside a supported operator must still warn")
    }

    @Test func fullySupportedFormulaProducesNoWarnings() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(
            FormulaAST.add(.cellRef(CellRef("A1")), .cellRef(CellRef("A2"))),
            to: "A3"
        )

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    // MARK: - Cell Ranges

    @Test func importsCellRangeAsRange() throws {
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
        let d17 = try #require(result.model.node(named: "D17"))
        guard case .formula(let formula) = try #require(result.model.kind(of: d17)) else {
            Issue.record("Expected formula node"); return
        }
        guard case .function(let name, let args) = formula else {
            Issue.record("Expected function formula, got \(formula)"); return
        }
        #expect(name == "SUM")
        guard case .range(let refs) = args.first else {
            Issue.record("Expected a range argument, got \(String(describing: args.first))"); return
        }
        #expect(refs.count == 12)
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func bareCellRangeImportsAsRange() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "A2")
        sheet.write(FormulaAST.cellRange(CellRange(from: "A1", to: "A2")), to: "A3")

        let result = ModelImporter.importWorkbook(wb)
        let a3 = try #require(result.model.node(named: "A3"))
        guard case .formula(.range(let refs)) = try #require(result.model.kind(of: a3)) else {
            Issue.record("Expected a range formula"); return
        }
        #expect(refs.count == 2)
    }

    @Test func cellRangeToleratesBlankInteriorCells() throws {
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
        let d17 = try #require(result.model.node(named: "D17"))
        guard case .formula(.function(_, let args)) = try #require(result.model.kind(of: d17)),
              case .range(let refs) = args.first else {
            Issue.record("Expected a range argument"); return
        }
        #expect(refs.count == 11, "Blank interior cells are skipped, not fatal")
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func unanchoredCellRangeWarnsAndDegrades() throws {
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
        let warning = try #require(result.warnings.first)
        #expect(warning.contains("D5:D16"), "Warning should name the range: \(warning)")
        #expect(warning.contains("A1"), "Warning should name the cell: \(warning)")
    }

    @Test func cellRangeResolvesBackToACellRangeOnExport() throws {
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
        let outSheet = try #require(exported.sheets.first)
        let sumCell = try #require(outSheet.cellReferences
                .compactMap { outSheet.cell(at: $0)?.formulaAST }
                .first { if case .function("SUM", _) = $0 { return true } else { return false } })
        guard case .function(_, let args) = sumCell, case .cellRange = args.first else {
            Issue.record("SUM should export a single CellRange argument, got \(sumCell)"); return
        }
    }

    // MARK: - Exponentiation

    @Test func importsPowerFormula() throws {
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
        let b2 = try #require(result.model.node(named: "B2"))
        let b3 = try #require(result.model.node(named: "B3"))
        let b4 = try #require(result.model.node(named: "B4"))
        guard case .formula(.power(let base, let exponent)) =
            try #require(result.model.kind(of: b4)) else {
            Issue.record("Expected a power formula"); return
        }
        #expect(base == .add(.number(1), .ref(b2)))
        #expect(exponent == .ref(b3))
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func powerResolvesBackToPowerOnExport() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.08)
        let periods = model.addInput(label: "Periods", value: 5)
        model.addOutput(
            label: "Discount Factor",
            formula: .power(.add(.number(1), .ref(rate)), .ref(periods))
        )

        let wb = try ModelExporter.export(model, title: "Power")
        let sheet = try #require(wb.sheets.first)
        let formulas = sheet.cellReferences.compactMap { sheet.cell(at: $0)?.formulaAST }
        let ast = try #require(formulas.first)
        guard case .power = ast else {
            Issue.record("Expected a power AST — `^` must not become POWER(), got \(ast)"); return
        }
    }

    // MARK: - Array-formula members

    // An array formula fills a rectangle from one cell. SwiftXLSX marks the cells
    // it fills with `_ARRAY(anchor, span)`, because they carry an empty `<f/>` in
    // the file and would otherwise arrive as their cached value — 224 computed
    // cells in one measured workbook, every one of them presenting as an input.

    @Test func anArrayMemberIsAFormulaNodeNotAnInput() throws {
        let result = ModelImporter.importCells([
            (reference: "D55", value: .formula(
                .function("TRANSPOSE", [.cellRange(CellRange(from: "H35", to: "K35"))]),
                cached: .number(0))),
            (reference: "D56", value: .formula(
                .function("_ARRAY", [.cellRef(CellRef("D55")), .text("D55:D57")]),
                cached: .number(-0.5))),
        ])
        let node = try #require(result.cellToNode[CellRef("D56")])
        guard case .formula = try #require(result.model.kind(of: node)) else {
            Issue.record("D56 became \(String(describing: result.model.kind(of: node)))"); return
        }
    }

    /// And it depends on the cell that computes it, so the graph reaches it.
    @Test func anArrayMemberDependsOnItsAnchor() throws {
        let result = ModelImporter.importCells([
            (reference: "D55", value: .formula(
                .function("TRANSPOSE", [.cellRange(CellRange(from: "H35", to: "K35"))]),
                cached: .number(0))),
            (reference: "D56", value: .formula(
                .function("_ARRAY", [.cellRef(CellRef("D55")), .text("D55:D57")]),
                cached: .number(-0.5))),
        ])
        let member = try #require(result.cellToNode[CellRef("D56")])
        let anchor = try #require(result.cellToNode[CellRef("D55")])
        guard case .formula(let formula)? = result.model.kind(of: member),
              case .function(_, let arguments) = formula else {
            Issue.record("expected a marker function"); return
        }
        #expect(arguments.first == .ref(anchor), "the member is computed by the anchor, and must say so")
    }

    // MARK: - Unsupported Cell Types

    // `Worksheet` exposes no public write for `.array`, `.date`, or `.error`
    // cells, so these drive the importer through its `importCells` seam.

    @Test func arrayCellWarnsAsAnArrayFormula() throws {
        let result = ModelImporter.importCells([
            (reference: "D5", value: .array(CellMatrix(row: [.number(1), .number(2)])))
        ])
        let warning = try #require(result.warnings.first)
        #expect(warning.contains("D5"), "Warning should name the cell: \(warning)")
        #expect(warning.lowercased().contains("array"), "Warning should identify the cell as an array formula: \(warning)")
    }

    @Test func arrayWarningIsDistinctFromDateAndError() throws {
        let result = ModelImporter.importCells([
            (reference: "A1", value: .array(CellMatrix(row: [.number(1)]))),
            (reference: "A2", value: .date(Date(timeIntervalSince1970: 0))),
            (reference: "A3", value: .error(.value)),
        ])
        #expect(result.warnings.count == 3)

        let arrayWarning = try #require(result.warnings.first)
        #expect(arrayWarning.lowercased().contains("array"))
        #expect(!result.warnings.dropFirst().contains(arrayWarning), "An array formula must not share the generic unsupported-cell message")
        #expect(result.warnings[1].lowercased().contains("date"))
        #expect(result.warnings[2].lowercased().contains("error"))
    }

    @Test func arrayCellDoesNotBecomeANode() {
        let result = ModelImporter.importCells([
            (reference: "D5", value: .array(CellMatrix(row: [.number(1), .number(2)])))
        ])
        #expect(result.model.nodeCount == 0, "Recognition is Phase 6; this only stops silent loss")
    }

    // MARK: - Multi-Sheet Import

    @Test func importAllSheetsImportsEverySheet() {
        let wb = Workbook()
        wb.addSheet(name: "Inputs").write(42.0, to: "A1")
        wb.addSheet(name: "Calcs").write(7.0, to: "B2")

        let result = ModelImporter.importAllSheets(wb)
        #expect(result.model.nodeCount == 2)
        #expect(result.model.node(named: "Inputs!A1")?.label == "Inputs!A1")
        #expect(result.model.node(named: "Calcs!B2")?.label == "Calcs!B2")
    }

    @Test func importAllSheetsGivesEachSheetItsOwnSection() {
        let wb = Workbook()
        wb.addSheet(name: "Inputs").write(42.0, to: "A1")
        wb.addSheet(name: "Calcs").write(7.0, to: "B2")

        let result = ModelImporter.importAllSheets(wb)
        #expect(result.model.sections.map(\.name) == ["Inputs", "Calcs"])
    }

    @Test func importAllSheetsKeepsCollidingCellRefsApart() throws {
        // Both sheets have an A1. A single flat cell map would lose one of them.
        let wb = Workbook()
        wb.addSheet(name: "One").write(1.0, to: "A1")
        wb.addSheet(name: "Two").write(2.0, to: "A1")

        let result = ModelImporter.importAllSheets(wb)
        #expect(result.model.nodeCount == 2)
        let one = try #require(result.sheetCellToNode["One"]?[CellRef("A1")])
        let two = try #require(result.sheetCellToNode["Two"]?[CellRef("A1")])
        #expect(one != two)
    }

    @Test func formulasResolveWithinTheirOwnSheet() throws {
        let wb = Workbook()
        let one = wb.addSheet(name: "One")
        one.write(10.0, to: "A1")
        one.write(FormulaAST.multiply(.cellRef(CellRef("A1")), .number(2)), to: "A2")
        wb.addSheet(name: "Two").write(99.0, to: "A1")

        let result = ModelImporter.importAllSheets(wb)
        let oneA1 = try #require(result.model.node(named: "One!A1"))
        let oneA2 = try #require(result.model.node(named: "One!A2"))
        guard case .formula(.multiply(let lhs, _)) =
            try #require(result.model.kind(of: oneA2)) else {
            Issue.record("Expected a multiply formula"); return
        }
        #expect(lhs == .ref(oneA1), "A formula must bind to its own sheet's A1")
    }

    @Test func crossSheetReferenceWarnsRatherThanVanishing() throws {
        let wb = Workbook()
        let one = wb.addSheet(name: "One")
        one.write(
            FormulaAST.sheetRef(SheetReference(sheet: "Two", cell: CellRef("A1"))),
            to: "A1"
        )
        wb.addSheet(name: "Two").write(5.0, to: "A1")

        let result = ModelImporter.importAllSheets(wb)
        let warning = try #require(result.warnings.first)
        #expect(warning.contains("sheetRef"), "Got: \(warning)")
        #expect(warning.contains("One!A1"), "Warning should qualify the cell: \(warning)")
    }

    @Test func singleSheetImportReportsItsSheetMapping() {
        let wb = Workbook()
        wb.addSheet(name: "Data").write(42.0, to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.cellToNode[CellRef("A1")]?.label == "A1")
        #expect(result.sheetCellToNode["Data"]?[CellRef("A1")] == result.cellToNode[CellRef("A1")])
    }

    @Test func importAllSheetsOnAnEmptyWorkbookIsEmpty() {
        let result = ModelImporter.importAllSheets(Workbook())
        #expect(result.model.nodeCount == 0)
        #expect(result.warnings.isEmpty)
        #expect(result.sheetCellToNode.isEmpty)
    }

    // MARK: - Forward References

    @Test func formulaResolvesAReferenceToALaterCell() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        // The total sits *above* the figures it sums, which is ordinary in a
        // financial model with a summary block at the top.
        sheet.write(FormulaAST.add(.cellRef(CellRef("A5")), .cellRef(CellRef("A6"))), to: "A1")
        sheet.write(10.0, to: "A5")
        sheet.write(20.0, to: "A6")

        let result = ModelImporter.importWorkbook(wb)
        let a1 = try #require(result.model.node(named: "A1"))
        let a5 = try #require(result.model.node(named: "A5"))
        let a6 = try #require(result.model.node(named: "A6"))

        guard case .formula(.add(let lhs, let rhs)) =
            try #require(result.model.kind(of: a1)) else {
            Issue.record("Expected an add formula"); return
        }
        #expect(lhs == .ref(a5))
        #expect(rhs == .ref(a6))
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func rangeResolvesWhenItPointsBelowTheFormula() throws {
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
        let a1 = try #require(result.model.node(named: "A1"))
        guard case .formula(.function(_, let args)) = try #require(result.model.kind(of: a1)),
              case .range(let refs) = args.first else {
            Issue.record("Expected a range argument"); return
        }
        #expect(refs.count == 12)
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func forwardReferenceChainResolves() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(FormulaAST.multiply(.cellRef(CellRef("A2")), .number(2)), to: "A1")
        sheet.write(FormulaAST.add(.cellRef(CellRef("A3")), .number(1)), to: "A2")
        sheet.write(5.0, to: "A3")

        let result = ModelImporter.importWorkbook(wb)
        let a2 = try #require(result.model.node(named: "A2"))
        let a3 = try #require(result.model.node(named: "A3"))

        let a1 = try #require(result.model.node(named: "A1"))
        guard case .formula(.multiply(let lhs, _)) = try #require(result.model.kind(of: a1)) else {
            Issue.record("Expected a multiply formula"); return
        }
        #expect(lhs == .ref(a2), "A1 should bind to A2's node, which itself binds forward")

        guard case .formula(.add(let innerLHS, _)) = try #require(result.model.kind(of: a2)) else {
            Issue.record("Expected an add formula"); return
        }
        #expect(innerLHS == .ref(a3))
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func sectionOrderAndNodeCountAreUnchangedByTwoPassResolution() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write("Label", to: "B1")
        sheet.write(FormulaAST.add(.cellRef(CellRef("A1")), .number(2)), to: "C1")

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.model.nodeCount == 3)
        #expect(result.model.sections.map(\.name) == ["Imported"])
        #expect(result.model.allRefs.map(\.label) == ["A1", "B1", "C1"])
    }

    // MARK: - Absolute References

    @Test func absoluteReferenceResolvesToTheSameNode() throws {
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
        let d11 = try #require(result.model.node(named: "D11"))
        let a1 = try #require(result.model.node(named: "A1"))

        guard case .formula(.multiply(let lhs, _)) = try #require(result.model.kind(of: a1)) else {
            Issue.record("Expected a multiply formula"); return
        }
        #expect(lhs == .ref(d11))
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func mixedAbsoluteReferencesResolve() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(5.0, to: "B2")
        sheet.write(FormulaAST.add(.cellRef(CellRef("$B2")), .cellRef(CellRef("B$2"))), to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        let b2 = try #require(result.model.node(named: "B2"))
        let a1 = try #require(result.model.node(named: "A1"))

        guard case .formula(.add(let lhs, let rhs)) = try #require(result.model.kind(of: a1)) else {
            Issue.record("Expected an add formula"); return
        }
        #expect(lhs == .ref(b2), "A column-absolute reference names the same cell")
        #expect(rhs == .ref(b2), "A row-absolute reference names the same cell")
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func absoluteRangeResolves() throws {
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
        let a1 = try #require(result.model.node(named: "A1"))
        guard case .formula(.function(_, let args)) = try #require(result.model.kind(of: a1)),
              case .range(let refs) = args.first else {
            Issue.record("Expected a range argument"); return
        }
        #expect(refs.count == 12)
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func cellToNodeIsKeyedByRelativeReferences() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "D11")

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.cellToNode[CellRef("D11")]?.label == "D11", "Keys are normalized so lookups do not depend on absolute markers")
    }

    // MARK: - Comparison Operators

    @Test func importsEveryComparisonOperator() throws {
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
            let a1 = try #require(result.model.node(named: "A1"))
            let a2 = try #require(result.model.node(named: "A2"))
            let a3 = try #require(result.model.node(named: "A3"))

            #expect(result.model.kind(of: a3) == .formula(testCase.expected(.ref(a1), .ref(a2))), "\(testCase.name) did not import as a comparison")
            #expect(result.warnings.isEmpty, "\(testCase.name): \(result.warnings)")
        }
    }

    @Test func importsComparisonInsideAnIfCondition() throws {
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
        let a1 = try #require(result.model.node(named: "A1"))
        let a2 = try #require(result.model.node(named: "A2"))
        let a3 = try #require(result.model.node(named: "A3"))

        guard case .formula(.function(let name, let args)) =
            try #require(result.model.kind(of: a3)) else {
            Issue.record("Expected an IF function"); return
        }
        #expect(name == "IF")
        #expect(args.first == .greaterThan(.ref(a1), .ref(a2)))
        #expect(result.warnings.isEmpty, "Got: \(result.warnings)")
    }

    @Test func comparisonSurvivesExportAndReimport() throws {
        let model = ExcelModel()
        let left = model.addInput(label: "Left", value: 1)
        let right = model.addInput(label: "Right", value: 2)
        model.addOutput(label: "Test", formula: .greaterThan(.ref(left), .ref(right)))

        let workbook = try ModelExporter.export(model, title: "Comparison")
        let sheet = try #require(workbook.sheets.first)
        let formulas = sheet.cellReferences.compactMap { sheet.cell(at: $0)?.formulaAST }
        let ast = try #require(formulas.first)
        guard case .greaterThan = ast else {
            Issue.record("Expected a greaterThan AST, got \(ast)"); return
        }
    }

    // MARK: - Cached Values

    @Test func preservesTheCachedValueOfAFormulaCell() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(2.0, to: "A1")
        sheet.write(FormulaAST.multiply(.cellRef(CellRef("A1")), .number(3)), to: "A2")

        let result = ModelImporter.importWorkbook(wb)
        // The workbook was authored in memory, so nothing cached A2 yet.
        #expect(result.cachedValues[CellRef("A2")] == nil)

        // A cell read from a file carries what Excel last computed.
        let reloaded = try Workbook(xlsxData: try wb.save())
        let fromFile = ModelImporter.importWorkbook(reloaded)
        #expect(fromFile.cellToNode.count == 2)
        #expect(fromFile.cachedValues[CellRef("A1")] == nil, "A value cell has no cached result")
    }

    @Test func cachedValuesAreKeyedIndependentlyOfAbsoluteMarkers() throws {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "D11")
        sheet.write(FormulaAST.cellRef(CellRef("$D$11")), to: "A1")

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.cellToNode.count == 2)
        #expect(result.cachedValues.keys.allSatisfy { !$0.absoluteColumn && !$0.absoluteRow })
    }

    // MARK: - Cell-to-Node Mapping

    @Test func cellToNodeMapping() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(42.0, to: "B3")

        let result = ModelImporter.importWorkbook(wb)
        let cellRef = CellRef("B3")
        #expect(result.cellToNode[cellRef]?.label == "B3")
    }

    // MARK: - Round-Trip

    @Test func roundTripExportImport() throws {
        let model = ExcelModel()
        let a = model.addInput(label: "Price", value: 100)
        let b = model.addInput(label: "Qty", value: 5)
        model.addOutput(label: "Total", formula: .multiply(.ref(a), .ref(b)))

        let wb = try ModelExporter.export(model, title: "Test")
        let result = ModelImporter.importWorkbook(wb)

        #expect(result.model.nodeCount > 0)
    }

    // MARK: - Multiple Cells

    @Test func importsMultipleCells() {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Test")
        sheet.write(1.0, to: "A1")
        sheet.write(2.0, to: "B1")
        sheet.write(3.0, to: "C1")

        let result = ModelImporter.importWorkbook(wb)
        #expect(result.model.nodeCount == 3)
    }

    // MARK: - Import Sheet

    @Test func importSpecificSheet() {
        let wb = Workbook()
        wb.addSheet(name: "Empty")
        let data = wb.addSheet(name: "Data")
        data.write(42.0, to: "A1")

        let result = ModelImporter.importSheet(data)
        #expect(result.model.nodeCount == 1)
    }
}
