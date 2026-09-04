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
        let sheetsFromHeadings: Int
        let sheetsFromShapeRuns: Int
        let sheetsDisagreeing: Int
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
        var fromHeadings = 0, fromShapeRuns = 0, disagreeing = 0
        for sheet in workbook.sheets {
            let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
            cells += grid.populatedCells
            formulas += grid.formulaASTs.count
            if grid.orientation != nil { withAxis += 1 }
            switch grid.axisProvenance {
            case .headings: fromHeadings += 1
            case .shapeRuns: fromShapeRuns += 1
            case nil: break
            }
            if grid.diagnostics.contains(where: { $0.code == .derivedAxisDiffers }) {
                disagreeing += 1
            }
            accounts += ExcelRecognizer.recognize(sheet, in: workbook).model.accounts.count
            nodes += DependencyGraph(sheet: sheet, including: isQuantity).allCells.count
        }
        return Reading(
            name: name, sheets: workbook.sheets.count, cells: cells, formulas: formulas,
            sheetsWithAxis: withAxis, sheetsFromHeadings: fromHeadings,
            sheetsFromShapeRuns: fromShapeRuns, sheetsDisagreeing: disagreeing,
            accounts: accounts, graphNodes: nodes)
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
        let sheets = readings.reduce(0) { $0 + $1.sheets }
        let headingSheets = readings.reduce(0) { $0 + $1.sheetsFromHeadings }
        let derivedSheets = readings.reduce(0) { $0 + $1.sheetsFromShapeRuns }
        let disagreeingSheets = readings.reduce(0) { $0 + $1.sheetsDisagreeing }
        let derivedOnly = readings.filter { $0.sheetsFromHeadings == 0 && $0.sheetsFromShapeRuns > 0 }

        print("""
            CORPUS
              workbooks read       \(readings.count)\(unreadable.isEmpty ? "" : " (\(unreadable.count) unreadable)")
              cells                \(cells)
              formulas             \(formulas)

              workbooks with a recognizable timeline   \(withAxis.count)
              workbooks without one                    \(readings.count - withAxis.count)
              workbooks whose only timeline is derived \(derivedOnly.count)

              sheets                                   \(sheets)
              sheets with an axis read from headings   \(headingSheets)
              sheets with an axis derived from shape   \(derivedSheets)
              sheets with no axis at all               \(sheets - headingSheets - derivedSheets)
              sheets whose headings and formulas differ \(disagreeingSheets)

              accounts recovered by recognition        \(accounts)
              nodes recovered by the dependency graph  \(nodes)
            """)

        for reading in readings.sorted(by: { $0.cells > $1.cells }).prefix(8) {
            print("""
                CORPUS   \(reading.name) — \(reading.sheets) sheets, \(reading.cells) cells, \
                \(reading.formulas) formulas, axis on \(reading.sheetsWithAxis) \
                (\(reading.sheetsFromHeadings) read, \(reading.sheetsFromShapeRuns) derived, \
                \(reading.sheetsDisagreeing) disagreeing), \
                \(reading.accounts) accounts, \(reading.graphNodes) graph nodes
                """)
        }

        // Reported, not gated. A threshold here would be tuned to this corpus, and
        // the whole reason the corpus exists is that the fixture already was.
        XCTAssertFalse(readings.isEmpty, "something should have been readable")
    }

    /// Which functions do real workbooks actually call, and how often?
    ///
    /// An evaluator over the graph has to implement them, and the set is not a
    /// matter of taste: a spreadsheet calls what it calls. Counting them turns "how
    /// much of a function library do we need" from a judgement into a ranked list,
    /// and says which of them BusinessMath already answers for.
    ///
    /// Reported, not gated.
    func testWhichFunctionsTheCorpusCalls() throws {
        let files = try corpusFiles()
        var callsByName: [String: Int] = [:]
        var sheetsByName: [String: Int] = [:]
        var totalCalls = 0

        for path in files {
            guard let workbook = try? Workbook(contentsOf: URL(fileURLWithPath: path)) else {
                continue
            }
            for sheet in workbook.sheets {
                let imported = ModelImporter.importSheet(sheet)
                var onThisSheet: Set<String> = []
                for (_, ast) in imported.formulaASTs {
                    for name in CorpusMeasurementTests.functionNames(in: ast) {
                        callsByName[name, default: 0] += 1
                        totalCalls += 1
                        onThisSheet.insert(name)
                    }
                }
                for name in onThisSheet { sheetsByName[name, default: 0] += 1 }
            }
        }

        let registered = Set(FormulaEvaluator<Double>.Function.allCases.map(\.rawValue))
        let ranked = callsByName.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        let covered = ranked.filter { registered.contains($0.key) }.reduce(0) { $0 + $1.value }

        print("""
            FUNCTIONS
              distinct functions called  \(callsByName.count)
              total calls                \(totalCalls)
              calls BusinessMath names   \(covered) (\(totalCalls == 0 ? 0 : covered * 100 / totalCalls)%)
            """)

        for (name, calls) in ranked.prefix(30) {
            let mark = registered.contains(name) ? "registered" : "—"
            print("FUNCTIONS  \(name)  \(calls) calls, \(sheetsByName[name] ?? 0) sheets  \(mark)")
        }

        // `_RAW` is not an Excel function. It is SwiftXLSX's fallback for a formula
        // its parser could not read, holding the text verbatim. A formula with no
        // structure yields no edges, so this is the ceiling on any graph built from
        // these files, and what it trips on is worth knowing exactly.
        var shapes: [String: Int] = [:]
        var samples: [String: String] = [:]
        for path in files {
            guard let workbook = try? Workbook(contentsOf: URL(fileURLWithPath: path)) else {
                continue
            }
            for sheet in workbook.sheets {
                for (_, ast) in ModelImporter.importSheet(sheet).formulaASTs {
                    guard case .function("_RAW", let arguments) = ast,
                          case .text(let raw)? = arguments.first else { continue }
                    let shape = CorpusMeasurementTests.shape(of: raw)
                    shapes[shape, default: 0] += 1
                    if samples[shape] == nil { samples[shape] = String(raw.prefix(70)) }
                }
            }
        }

        print("UNPARSED  \(shapes.values.reduce(0, +)) formulas SwiftXLSX could not parse")
        for (shape, count) in shapes.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) })
            .prefix(15) {
            print("UNPARSED  \(shape)  \(count)  e.g. \(samples[shape] ?? "")")
        }

        // The tally above sees only formulas that parsed, so every function inside
        // the unparsed half was invisible to it. Scanning the raw text recovers
        // them, which is the only way to see the add-in calls at all.
        var inRaw: [String: Int] = [:]
        var rawSheets: [String: Int] = [:]
        for path in files {
            guard let workbook = try? Workbook(contentsOf: URL(fileURLWithPath: path)) else {
                continue
            }
            for sheet in workbook.sheets {
                var onThisSheet: Set<String> = []
                for (_, ast) in ModelImporter.importSheet(sheet).formulaASTs {
                    guard case .function("_RAW", let arguments) = ast,
                          case .text(let raw)? = arguments.first else { continue }
                    for name in CorpusMeasurementTests.calledNames(inRawText: raw) {
                        inRaw[name, default: 0] += 1
                        onThisSheet.insert(name)
                    }
                }
                for name in onThisSheet { rawSheets[name, default: 0] += 1 }
            }
        }

        let addIns = inRaw.filter { $0.key.hasPrefix("PSI") || $0.key.contains("RISK") }
        print("HIDDEN  \(inRaw.count) distinct functions inside unparsed formulas")
        for (name, calls) in inRaw.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) })
            .prefix(25) {
            let mark = registered.contains(name) ? "registered" : "—"
            print("HIDDEN  \(name)  \(calls) calls, \(rawSheets[name] ?? 0) sheets  \(mark)")
        }
        print("ADDIN  \(addIns.count) distinct simulation add-in functions")
        for (name, calls) in addIns.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            print("ADDIN  \(name)  \(calls) calls, \(rawSheets[name] ?? 0) sheets")
        }

        XCTAssertFalse(files.isEmpty)
    }

    /// Every name called as a function in raw formula text.
    ///
    /// A run of identifier characters immediately followed by `(`. String literals
    /// are skipped, so a parenthesis inside quoted text cannot invent a call.
    /// Add-in prefixes are dropped — `_xll.PsiNormal` and `PsiNormal` are one
    /// function, and the prefix says where Excel loaded it from rather than what it
    /// computes.
    private static func calledNames(inRawText raw: String) -> [String] {
        var found: [String] = []
        var identifier = ""
        var inQuotes = false

        for character in raw {
            if character == "\"" {
                inQuotes.toggle()
                identifier = ""
                continue
            }
            if inQuotes { continue }

            if character.isLetter || character.isNumber || character == "_" || character == "." {
                identifier.append(character)
                continue
            }
            if character == "(", !identifier.isEmpty {
                var name = identifier.uppercased()
                for prefix in ["_XLL.", "_XLFN."] where name.hasPrefix(prefix) {
                    name = String(name.dropFirst(prefix.count))
                }
                // A bare number before a parenthesis is arithmetic, not a call.
                if name.first?.isLetter == true { found.append(name) }
            }
            identifier = ""
        }
        return found
    }

    /// A coarse fingerprint of an unparsed formula, so failures group by cause.
    ///
    /// The leading call or token, not the whole text — two formulas failing for the
    /// same reason should land together however different their arguments are.
    private static func shape(of raw: String) -> String {
        let text = raw.hasPrefix("=") ? String(raw.dropFirst()) : raw
        if let parenthesis = text.firstIndex(of: "(") {
            let head = text[text.startIndex..<parenthesis]
            if head.allSatisfy({ $0.isLetter || $0 == "." || $0 == "_" }), !head.isEmpty {
                return "\(head.uppercased())(…)"
            }
        }
        if text.hasPrefix("{") { return "{array formula}" }
        if text.contains("!") { return "cross-sheet reference" }
        if let first = text.first, first.isNumber || first == "-" { return "arithmetic" }
        return String(text.prefix(12))
    }

    /// Every function name a formula calls, including nested ones.
    private static func functionNames(in ast: FormulaAST) -> [String] {
        var found: [String] = []
        var stack: [FormulaAST] = [ast]

        // Iterative, so a deeply nested formula cannot exhaust the stack.
        while let node = stack.popLast() {
            switch node {
            case .function(let name, let arguments):
                found.append(name.uppercased())
                stack.append(contentsOf: arguments)
            case .add(let lhs, let rhs), .subtract(let lhs, let rhs),
                 .multiply(let lhs, let rhs), .divide(let lhs, let rhs),
                 .power(let lhs, let rhs),
                 .greaterThan(let lhs, let rhs), .lessThan(let lhs, let rhs),
                 .greaterOrEqual(let lhs, let rhs), .lessOrEqual(let lhs, let rhs),
                 .equal(let lhs, let rhs), .notEqual(let lhs, let rhs),
                 .concatenate(let lhs, let rhs):
                stack.append(lhs)
                stack.append(rhs)
            case .negate(let inner):
                stack.append(inner)
            default:
                continue
            }
        }
        return found
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
