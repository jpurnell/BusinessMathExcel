import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Measurement across a corpus of workbooks nobody wrote for us.
///
/// ## Why a corpus and not a fixture
///
/// The Wharton practice model is a *fixture*: every recognition rule was measured
/// against it, and 85% coverage there says how well the rules fit the file they
/// were fitted to. A second workbook — a production credit model — dropped that to
/// 18% the first time it was tried, which is what a fixture cannot tell you.
///
/// A corpus is the control. These tests read whatever workbooks are configured,
/// report what recognition and the dependency graph each recover, and assert
/// almost nothing — the numbers are the point, and a threshold here would only
/// invite tuning the rules to the corpus, which is how the fixture stopped being
/// informative.
///
/// ## Configuring it
///
/// Set `BUSINESSMATHEXCEL_CORPUS` to a colon-separated list of directories, which
/// are searched recursively for `.xlsx` files:
///
/// ```
/// BUSINESSMATHEXCEL_CORPUS="/path/one:/path/two" swift test --filter Corpus
/// ```
///
/// Unset, every test here skips. The workbooks are private — teaching material and
/// employer files — so none is checked in and none should be.
final class CorpusMeasurementTests: XCTestCase {

    /// One workbook's measurements.
    private struct Reading {
        let name: String
        let sheets: Int
        let cells: Int
        let formulas: Int
        let sheetsWithAxis: Int
        let accounts: Int
        let graphNodes: Int
    }

    /// Whether a cell is a quantity rather than a caption.
    ///
    /// The filter that turns a spreadsheet's calculation-order graph into a model
    /// graph: a title is not a node, and neither is a cell holding nothing.
    private func isQuantity(_ value: CellValue) -> Bool {
        if value.isFormula { return true }
        if case .number = value.resolved { return true }
        return false
    }

    private func corpusFiles() throws -> [String] {
        guard let configured = ProcessInfo.processInfo.environment["BUSINESSMATHEXCEL_CORPUS"],
              !configured.isEmpty
        else {
            throw XCTSkip(
                "Set BUSINESSMATHEXCEL_CORPUS to a colon-separated list of directories. "
                    + "The workbooks are private and are not checked in.")
        }

        var files: [String] = []
        for root in configured.split(separator: ":").map(String.init) {
            guard let walk = FileManager.default.enumerator(atPath: root) else { continue }
            for case let entry as String in walk
            where entry.lowercased().hasSuffix(".xlsx") && !entry.contains("~$") {
                files.append(root + "/" + entry)
            }
        }
        guard !files.isEmpty else { throw XCTSkip("No .xlsx files under the configured roots.") }
        return files.sorted()
    }

    private func read(_ path: String) -> Reading? {
        let name = (path as NSString).lastPathComponent
        guard let workbook = try? Workbook(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        var cells = 0, formulas = 0, withAxis = 0, accounts = 0, nodes = 0
        for sheet in workbook.sheets {
            let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
            cells += grid.populatedCells
            formulas += grid.formulaASTs.count
            if grid.orientation != nil { withAxis += 1 }
            accounts += ExcelRecognizer.recognize(sheet, in: workbook).model.accounts.count
            nodes += DependencyGraph(sheet: sheet, including: isQuantity).allCells.count
        }
        return Reading(
            name: name, sheets: workbook.sheets.count, cells: cells, formulas: formulas,
            sheetsWithAxis: withAxis, accounts: accounts, graphNodes: nodes)
    }

    // MARK: - The measurement

    /// What the corpus says about recognition, reported rather than gated.
    ///
    /// The comparison that matters is the last two columns: how much a pipeline
    /// that begins by looking for a timeline recovers, against how much a
    /// dependency graph recovers from the same files. A graph can be built from any
    /// sheet that has formulas at all, because "what does this read" is answerable
    /// without deciding first what kind of model it is.
    func testReportsWhatTheCorpusRecovers() throws {
        let files = try corpusFiles()
        var readings: [Reading] = []
        var unreadable: [String] = []

        for path in files {
            if let reading = read(path) { readings.append(reading) }
            else { unreadable.append((path as NSString).lastPathComponent) }
        }

        let withAxis = readings.filter { $0.sheetsWithAxis > 0 }
        let cells = readings.reduce(0) { $0 + $1.cells }
        let formulas = readings.reduce(0) { $0 + $1.formulas }
        let accounts = readings.reduce(0) { $0 + $1.accounts }
        let nodes = readings.reduce(0) { $0 + $1.graphNodes }

        print("""
            CORPUS
              workbooks read       \(readings.count)\(unreadable.isEmpty ? "" : " (\(unreadable.count) unreadable)")
              cells                \(cells)
              formulas             \(formulas)

              workbooks with a recognizable timeline   \(withAxis.count)
              workbooks without one                    \(readings.count - withAxis.count)

              accounts recovered by recognition        \(accounts)
              nodes recovered by the dependency graph  \(nodes)
            """)

        for reading in readings.sorted(by: { $0.cells > $1.cells }).prefix(8) {
            print("""
                CORPUS   \(reading.name) — \(reading.sheets) sheets, \(reading.cells) cells, \
                \(reading.formulas) formulas, axis on \(reading.sheetsWithAxis), \
                \(reading.accounts) accounts, \(reading.graphNodes) graph nodes
                """)
        }

        // Reported, not gated. A threshold here would be tuned to this corpus, and
        // the whole reason the corpus exists is that the fixture already was.
        XCTAssertFalse(readings.isEmpty, "something should have been readable")
    }

    /// A graph can be built wherever there are formulas at all.
    ///
    /// This is the one thing worth asserting rather than merely printing, because
    /// it is the claim the graph projection rests on: *what does this cell read* is
    /// answerable from any sheet, without first deciding what kind of model it is.
    /// A timeline is a property some models have; a dependency is what every
    /// formula is.
    func testEveryWorkbookWithFormulasYieldsAGraph() throws {
        let files = try corpusFiles()
        var checked = 0
        var barren: [String] = []

        for path in files {
            guard let workbook = try? Workbook(contentsOf: URL(fileURLWithPath: path)) else {
                continue
            }
            for sheet in workbook.sheets {
                let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
                guard grid.formulaASTs.count > 0 else { continue }
                checked += 1
                let graph = DependencyGraph(sheet: sheet, including: isQuantity)
                if graph.allCells.isEmpty {
                    barren.append("\((path as NSString).lastPathComponent)/\(sheet.name)")
                }
            }
        }

        print("CORPUS graph built on \(checked) sheets holding formulas")
        XCTAssertEqual(
            barren, [],
            "a sheet with formulas has dependencies, so it has a graph")
        XCTAssertGreaterThan(checked, 0)
    }
}
