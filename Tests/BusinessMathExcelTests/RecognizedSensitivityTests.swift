import Foundation
import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Reading a What-If table, not merely knowing where one is.
///
/// Excel writes a two-variable data table as a single marker on the body's
/// top-left cell. Everything that gives it meaning sits *around* the body and is
/// identified by position rather than by any label: the values substituted into
/// each driver are the row above and the column to the left, and the formula being
/// measured is the corner cell above and left of both.
///
/// Orientation is the thing to get wrong, so the fixtures here are deliberately
/// asymmetric — a transposed reading fails rather than passing by symmetry.
@Suite struct RecognizedSensitivityTests {

    /// A 2×3 grid: two column-inputs down, three row-inputs across.
    ///
    /// ```
    ///        N        O      P      Q
    ///   4  =Payback  0.06   0.08   0.10     <- row inputs, into B2
    ///   5  3.0        11     12     13      <- column input 3.0, into B3
    ///   6  4.0        21     22     23
    /// ```
    private func sheet(twoWay: Bool = true) -> Worksheet? {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C9")
        sheet.write("2025", to: "D9")
        sheet.write("2026", to: "E9")

        sheet.write("Growth", to: "A2")
        sheet.write(0.08, to: "B2")
        sheet.write("Multiple", to: "A3")
        sheet.write(4.0, to: "B3")
        sheet.write("Payback", to: "A4")
        sheet.write(7.0, to: "B4")

        // The measured formula, in the corner.
        sheet.write(FormulaAST.cellRef(CellRef("B4")), to: "N4")
        // Row inputs across, column inputs down.
        sheet.write(0.06, to: "O4")
        sheet.write(0.08, to: "P4")
        sheet.write(0.10, to: "Q4")
        sheet.write(3.0, to: "N5")
        sheet.write(4.0, to: "N6")

        let results: [[Double]] = [[11, 12, 13], [21, 22, 23]]
        for (row, values) in results.enumerated() {
            for (column, value) in values.enumerated() {
                sheet.write(value, to: "\(["O", "P", "Q"][column])\(5 + row)")
            }
        }

        // The marker sits on the body's top-left cell and that cell also holds a
        // cached answer — which is how Excel writes it, and why the value has to be
        // given here rather than written separately and overwritten.
        let marker: FormulaAST = twoWay
            ? .function("_DATATABLE",
                        [.text("O5:Q6"), .cellRef(CellRef("B2")), .cellRef(CellRef("B3"))])
            : .function("_DATATABLE", [.text("O5:Q6"), .cellRef(CellRef("B2"))])
        sheet.write(marker, to: "O5", cached: .number(11))

        return workbook.sheets.first
    }

    private func read(twoWay: Bool = true) throws -> RecognizedSensitivity {
        let sheet = try #require(self.sheet(twoWay: twoWay))
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try #require(PeriodAxis.build(from: grid).axis)
        return try #require(RecognizedSensitivity.read(in: grid, axis: axis).first, "no table was read")
    }

    // MARK: - Drivers

    @Test func bothDriversAreNamedByTheirAccounts() throws {
        let table = try read()
        #expect(table.rowDriver == "Growth", "the row inputs substitute into B2")
        #expect(table.columnDriver == "Multiple", "the column inputs substitute into B3")
    }

    @Test func theMeasuredOutputIsIdentified() throws {
        let table = try read()
        #expect(table.measuredCell == CellRef("N4"), "the corner, above and left of the body, is where the measured formula sits")
    }

    /// A driver the sheet gives no label falls back to its address rather than to
    /// nothing — a table whose drivers cannot be named is still a table.
    @Test func anUnlabelledDriverFallsBackToItsAddress() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C9")
        sheet.write("2025", to: "D9")
        sheet.write("2026", to: "E9")
        sheet.write(0.08, to: "B2")     // no label beside it
        sheet.write("Multiple", to: "A3")
        sheet.write(4.0, to: "B3")
        sheet.write(0.06, to: "O4")
        sheet.write(3.0, to: "N5")
        sheet.write(
            FormulaAST.function(
                "_DATATABLE",
                [.text("O5:O5"), .cellRef(CellRef("B2")), .cellRef(CellRef("B3"))]),
            to: "O5", cached: .number(11))

        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try #require(PeriodAxis.build(from: grid).axis)
        let table = try #require(RecognizedSensitivity.read(in: grid, axis: axis).first)

        #expect(table.rowDriver == "B2")
    }

    // MARK: - Orientation

    /// The asymmetry is the point: 2 rows, 3 columns, and values that differ by
    /// row and by column, so a transposed reading cannot pass.
    @Test func theGridIsReadInTheDocumentedOrientation() throws {
        let table = try read()

        #expect(table.rowValues.elementsEqual([0.06, 0.08, 0.10], by: { $0.isEqual(to: $1) }), "across the top, into the row driver")
        #expect(table.columnValues.elementsEqual([3.0, 4.0], by: { $0.isEqual(to: $1) }), "down the side, into the column driver")

        #expect(table.results.count == 2, "one row per column-input value")
        #expect(table.results.first?.count == 3, "one column per row-input value")
        #expect(table.results == [[11, 12, 13], [21, 22, 23]])
    }

    // MARK: - One-way tables

    /// The file says whether a table is two-way. Guessing would invent an axis.
    @Test func aOneWayTableIsNotReadAsTwoWay() throws {
        let sheet = try #require(self.sheet(twoWay: false))
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try #require(PeriodAxis.build(from: grid).axis)

        #expect(RecognizedSensitivity.read(in: grid, axis: axis).isEmpty, "a one-way table has one driver, and reading it as two would invent the other")
    }

    @Test func aSheetWithNoTableYieldsNone() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("Revenue", to: "A2")
        sheet.write(100.0, to: "C2")
        sheet.write(110.0, to: "D2")

        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try #require(PeriodAxis.build(from: grid).axis)
        #expect(RecognizedSensitivity.read(in: grid, axis: axis).isEmpty)
    }

    // MARK: - Upstream

    /// `TwoWayScenarioSensitivityAnalysis` documents `results[i][j]` as the output
    /// for `inputValues1[i]` and `inputValues2[j]`, so the column driver — whose
    /// values index the outer array — is driver 1.
    @Test func itMapsToTheUpstreamAnalysis() throws {
        let analysis = try read().analysis()

        #expect(analysis.inputDriver1 == "Multiple")
        #expect(analysis.inputValues1.elementsEqual([3.0, 4.0], by: { $0.isEqual(to: $1) }))
        #expect(analysis.inputDriver2 == "Growth")
        #expect(analysis.inputValues2.elementsEqual([0.06, 0.08, 0.10], by: { $0.isEqual(to: $1) }))
        #expect(analysis.results[1][2] == 23, "second multiple, third growth rate")
    }

    // MARK: - Into the plan

    /// A table reaches the plan, beside the accounts rather than among them.
    @Test func aRecognizedTableReachesThePlan() throws {
        let sheet = try #require(self.sheet())
        let plan = ExcelRecognizer.recognize(sheet)

        let table = try #require(plan.model.sensitivities.first, "no table in the plan")
        #expect(table.rowDriver == "Growth")
        #expect(table.columnDriver == "Multiple")
    }

    /// A grid of answers is not a rule. It is an analysis *of* the model — the
    /// numbers the model already produced under other assumptions — so nothing in
    /// it can define an account, and materialization has nothing to do with it.
    @Test func aTableIsNotAnAccount() throws {
        let sheet = try #require(self.sheet())
        let plan = ExcelRecognizer.recognize(sheet)

        #expect(!plan.model.accounts.contains { $0.name.contains("Payback") && $0.formula != nil }, "the measured formula is read as a cell, not lifted into an account")

        let built = try ModelMaterializer.build(from: plan.model)
        for name in built.definition.definitions.map(\.name) {
            #expect(!(name.hasPrefix("O") || name.hasPrefix("P") || name.hasPrefix("Q")), "no grid cell became a definition. Got: \(name)")
        }
    }

    /// The table's cells were excluded from binding on purpose since Phase 5a —
    /// a label beside the grid would otherwise claim them. Reading the table turns
    /// them from cells we exclude into cells we understand, which is the whole
    /// coverage argument for this phase.
    @Test func theTablesCellsCountAsRecognized() throws {
        let sheet = try #require(self.sheet())
        let plan = ExcelRecognizer.recognize(sheet)

        let table = try #require(plan.model.sensitivities.first)
        #expect(table.cells.count == 12, "a 2×3 body, plus the row above and the column left, plus the corner")

        // Every populated cell the table covers is accounted for.
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let populated = table.cells.filter { grid.cells[$0] != nil }
        #expect(populated.count == 12, "the fixture fills the whole block, so all of it should count")
        #expect(plan.coverage.recognizedCells >= populated.count, "coverage counts them")
    }

    @Test func aSheetWithNoTableHasNoneInThePlan() throws {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("Revenue", to: "A2")
        sheet.write(100.0, to: "C2")
        sheet.write(110.0, to: "D2")

        let plan = ExcelRecognizer.recognize(try #require(workbook.sheets.first))
        #expect(plan.model.sensitivities.isEmpty)
        #expect(plan.diagnostics.filter { $0.severity != .info }.map(\.code.rawValue) == [], "and a sheet without one is not remarkable")
    }
}
