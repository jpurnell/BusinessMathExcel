import SwiftXLSX

/// Stage 1 — a sheet's topology, and which way its time axis runs.
///
/// Consumes ``ModelImporter/ImportResult`` rather than a `Worksheet`. Import is
/// a faithful structural transcription; recognition is the interpretive layer
/// above it, and reaching past it to the file would give two sources of truth
/// for what a cell contains.
///
/// ## How the axis is found
///
/// A **candidate axis** is a run of two or more period headings — see the
/// `PeriodHeader` rule — in consecutive cells along one row or one column,
/// whose years strictly increase.
///
/// Each part of that rule excludes something real:
///
/// - **Two or more** — a lone `2024` is a label, not an axis. One heading
///   establishes no direction.
/// - **Consecutive** — `2024`, `Notes`, `2025` is two runs of one. A gap means
///   the headings are not one series.
/// - **Strictly increasing** — a row of repeated `2024` is a set of columns that
///   happen to share a year, not a timeline.
///
/// The longest candidate row is compared with the longest candidate column:
///
/// | Outcome | Result |
/// |---|---|
/// | Neither qualifies | ``DiagnosticCode/noPeriodAxis``, orientation `nil` |
/// | One is longer | That direction wins |
/// | Both, equal length | ``DiagnosticCode/ambiguousOrientation``, orientation `nil` |
///
/// The tie is reported rather than broken. A sheet that reads equally well both
/// ways has not told us which it is, and answering anyway would be a coin toss
/// presented as a finding.
///
/// ``RecognizerOptions/orientation`` overrides all of this: a caller who states
/// the direction is taken at their word.
public struct SheetGrid: Sendable {

    /// Which way the time axis runs.
    public enum Orientation: Sendable, Equatable {

        /// Periods run left to right along a row.
        case periodsAcrossColumns

        /// Periods run top to bottom down a column.
        case periodsDownRows
    }

    /// Every populated cell, by position.
    public let cells: [CellRef: NodeKind]

    /// What the file recorded Excel computing for each formula cell.
    public let cachedValues: [CellRef: CellValue]

    /// Each formula cell's AST as the file wrote it, with `$` markers intact.
    public let formulaASTs: [CellRef: FormulaAST]

    /// The workbook's named ranges that point at a single cell on **this** sheet.
    ///
    /// A named range is workbook-level, so it reaches recognition from outside
    /// rather than from the sheet. Names pointing at another sheet, at a range, or
    /// at an expression are left out: this map answers one question — *which cell
    /// does this name mean here* — and a name it cannot answer for is better
    /// absent than approximated, so the formula holding it is refused rather than
    /// resolved to the wrong cell.
    public let namedCells: [String: CellRef]

    /// Where each node sits, the inverse of the importer's cell-to-node map.
    ///
    /// A ``NodeFormula`` references nodes rather than positions, so anything
    /// asking a geometric question about a formula — such as whether two cells
    /// hold the same shape one column apart — has to come back through this.
    public let nodeToCell: [NodeRef: CellRef]

    /// The smallest range containing every populated cell, or `nil` if empty.
    public let bounds: CellRange?

    /// The number of populated cells.
    public var populatedCells: Int { cells.count }

    /// The axis direction, or `nil` when it could not be established.
    public let orientation: Orientation?

    /// The row holding the axis when periods run across columns, or the column
    /// when they run down rows. `nil` when there is no axis.
    public let axisLine: Int?

    /// The heading cells forming the axis, in period order. Empty when there is
    /// no axis.
    public let axisCells: [CellRef]

    /// What could not be established, and why.
    public let diagnostics: [Diagnostic]

    // MARK: - Building

    /// Builds a grid from an imported sheet.
    ///
    /// - Parameters:
    ///   - result: The importer's output for one sheet.
    ///   - options: Recognizer options.
    ///   - namedCells: The workbook's named ranges that point at a single cell on
    ///     this sheet. Names are workbook-level, so they arrive from the caller
    ///     rather than from the sheet; anything not resolvable to one cell here is
    ///     deliberately absent, and the formulas using it are refused.
    /// - Returns: The grid, with diagnostics for anything it could not establish.
    public static func build(
        from result: ModelImporter.ImportResult,
        options: RecognizerOptions = RecognizerOptions(),
        namedCells: [String: CellRef] = [:]
    ) -> SheetGrid {
        var diagnostics: [Diagnostic] = []

        var cells: [CellRef: NodeKind] = [:]
        for (cellRef, nodeRef) in result.cellToNode {
            guard let kind = result.model.kind(of: nodeRef) else { continue }
            cells[cellRef] = kind
        }

        if cells.count > options.maximumCells {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: .scanLimitReached,
                    message: "The sheet has \(cells.count) populated cells, above the "
                        + "\(options.maximumCells) limit; only the first \(options.maximumCells) "
                        + "in reading order were scanned"
                )
            )
            let kept = cells.sorted { readingOrder($0.key, $1.key) }.prefix(options.maximumCells)
            cells = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }

        let cached = result.cachedValues
        var nodeToCell: [NodeRef: CellRef] = [:]
        for (cellRef, nodeRef) in result.cellToNode { nodeToCell[nodeRef] = cellRef }
        let bounds = boundingRange(of: cells.keys)
        let rowRun = longestRun(in: cells, cached: cached, along: .row)
        let columnRun = longestRun(in: cells, cached: cached, along: .column)

        switch options.orientation {
        case .periodsAcrossColumns:
            return SheetGrid(
                cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: .periodsAcrossColumns,
                axisLine: rowRun?.line, axisCells: rowRun?.cells ?? [], diagnostics: diagnostics)

        case .periodsDownRows:
            return SheetGrid(
                cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: .periodsDownRows,
                axisLine: columnRun?.line, axisCells: columnRun?.cells ?? [],
                diagnostics: diagnostics)

        case .auto:
            break
        }

        switch (rowRun, columnRun) {
        case (nil, nil):
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .noPeriodAxis,
                    message: "No row or column holds two or more consecutive, advancing "
                        + "period headings"))
            return SheetGrid(
                cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: nil, axisLine: nil, axisCells: [],
                diagnostics: diagnostics)

        case (let row?, nil):
            return SheetGrid(
                cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: .periodsAcrossColumns,
                axisLine: row.line, axisCells: row.cells, diagnostics: diagnostics)

        case (nil, let column?):
            return SheetGrid(
                cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: .periodsDownRows,
                axisLine: column.line, axisCells: column.cells, diagnostics: diagnostics)

        case (let row?, let column?):
            if row.cells.count > column.cells.count {
                return SheetGrid(
                    cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: .periodsAcrossColumns,
                    axisLine: row.line, axisCells: row.cells, diagnostics: diagnostics)
            }
            if column.cells.count > row.cells.count {
                return SheetGrid(
                    cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: .periodsDownRows,
                    axisLine: column.line, axisCells: column.cells, diagnostics: diagnostics)
            }
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .ambiguousOrientation,
                    message: "Row \(row.line) and column \(column.line) each hold "
                        + "\(row.cells.count) period headings; the sheet reads equally well "
                        + "both ways, so no direction was chosen"))
            return SheetGrid(
                cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs, namedCells: namedCells,
                nodeToCell: nodeToCell, bounds: bounds, orientation: nil, axisLine: nil, axisCells: [],
                diagnostics: diagnostics)
        }
    }

    // MARK: - Private

    private enum Axis { case row, column }

    private struct Run {
        let line: Int
        let cells: [CellRef]
    }

    /// The longest qualifying run of period headings along one axis.
    private static func longestRun(
        in cells: [CellRef: NodeKind],
        cached: [CellRef: CellValue],
        along axis: Axis
    ) -> Run? {
        var headings: [Int: [(position: Int, cell: CellRef, year: Int)]] = [:]
        for (cellRef, kind) in cells {
            guard let year = PeriodHeader.year(of: kind, cached: cached[cellRef]) else { continue }
            let line = axis == .row ? cellRef.row : cellRef.column
            let position = axis == .row ? cellRef.column : cellRef.row
            headings[line, default: []].append((position, cellRef, year))
        }

        var best: Run?
        for line in headings.keys.sorted() {
            guard let entries = headings[line]?.sorted(by: { $0.position < $1.position }) else {
                continue
            }
            var run: [(position: Int, cell: CellRef, year: Int)] = []
            for entry in entries {
                if let previous = run.last,
                   entry.position != previous.position + 1 || entry.year <= previous.year {
                    if run.count >= 2, run.count > (best?.cells.count ?? 1) {
                        best = Run(line: line, cells: run.map(\.cell))
                    }
                    run = []
                }
                run.append(entry)
            }
            if run.count >= 2, run.count > (best?.cells.count ?? 1) {
                best = Run(line: line, cells: run.map(\.cell))
            }
        }
        return best
    }

    private static func boundingRange(of refs: some Collection<CellRef>) -> CellRange? {
        guard let first = refs.first else { return nil }
        var minColumn = first.column, maxColumn = first.column
        var minRow = first.row, maxRow = first.row
        for ref in refs {
            minColumn = min(minColumn, ref.column)
            maxColumn = max(maxColumn, ref.column)
            minRow = min(minRow, ref.row)
            maxRow = max(maxRow, ref.row)
        }
        return CellRange(
            from: CellRef(column: minColumn, row: minRow),
            to: CellRef(column: maxColumn, row: maxRow))
    }

    private static func readingOrder(_ lhs: CellRef, _ rhs: CellRef) -> Bool {
        lhs.row != rhs.row ? lhs.row < rhs.row : lhs.column < rhs.column
    }
}
