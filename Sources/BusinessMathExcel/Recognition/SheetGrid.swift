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
    public enum Orientation: Sendable, Hashable {

        /// Periods run left to right along a row.
        case periodsAcrossColumns

        /// Periods run top to bottom down a column.
        case periodsDownRows
    }

    /// How the axis was established.
    ///
    /// Header detection is what a reader would do and is right whenever it works,
    /// so it is tried first and kept where it succeeds. Shape runs are the
    /// fallback: on most real sheets there is no heading row the detector can read,
    /// and a timeline leaves a second trace in the arithmetic itself.
    ///
    /// Which of the two answered matters downstream, because the periods differ in
    /// kind. A heading axis carries the years the sheet named; a derived axis
    /// carries positions, and nothing inside a `Period` says which it is holding.
    public enum AxisProvenance: Sendable, Equatable {

        /// Read from a row or column of period headings.
        case headings

        /// Derived from the span the given number of shape runs agreed on.
        case shapeRuns(agreeing: Int)
    }

    /// Every populated cell, by position.
    public let cells: [CellRef: NodeKind]

    /// What the file recorded Excel computing for each formula cell.
    public let cachedValues: [CellRef: CellValue]

    /// Each formula cell's AST as the file wrote it, with `$` markers intact.
    public let formulaASTs: [CellRef: FormulaAST]

    /// Each cell's number format string, as the file states it.
    ///
    /// Often the only statement a workbook makes about what a number *is*, and so
    /// the evidence unit inference reads. Carried unread by every other stage.
    public let numberFormats: [CellRef: String]

    /// The workbook's named ranges that point at a single cell on **this** sheet.
    ///
    /// A named range is workbook-level, so it reaches recognition from outside
    /// rather than from the sheet. Names pointing at another sheet, at a range, or
    /// at an expression are left out: this map answers one question — *which cell
    /// does this name mean here* — and a name it cannot answer for is better
    /// absent than approximated, so the formula holding it is refused rather than
    /// resolved to the wrong cell.
    public let namedCells: [String: CellRef]

    /// What the binder called each cell, once binding has run.
    ///
    /// Empty on a freshly built grid and filled in by ``ExcelRecognizer`` after
    /// ``LabeledSeries`` and ``ScalarBlock`` have decided which label owns what.
    /// It exists because those two settle a question the grid cannot: when two
    /// rows carry the same heading the binder keeps both and distinguishes the
    /// second by its cell, and a translator that re-derives a name from the
    /// nearest label throws that away — resolving a reference to whichever row the
    /// label search reaches first, which may be an assumption rather than the row
    /// meant. That is a model that runs and is wrong, so the binder's answer is
    /// carried rather than recomputed.
    public var accountNames: [CellRef: String] = [:]

    /// What accounts other sheets call their cells, by sheet name.
    ///
    /// A model that separates data from calculation puts the two on different
    /// sheets, so the calculation sheet's formulas reach off it for almost every
    /// operand. Resolving those needs the other sheet's binding, which is why
    /// ``ExcelRecognizer/recognize(_:options:)-(Workbook,_)`` binds every sheet
    /// before translating any of them.
    ///
    /// Empty when a sheet is recognized on its own, in which case a reference off
    /// it is refused — there is nothing to resolve against, and guessing would
    /// invent an account.
    public var foreignAccountNames: [String: [CellRef: String]] = [:]

    /// What the binder called a cell, ignoring its `$` markers.
    ///
    /// A ``CellRef`` carries whether each half was pinned, and hashes it, so
    /// `$B$2` and `B2` are different keys for the same cell. A formula writes the
    /// pinned form and the binder records the plain one, so a lookup that did not
    /// normalize would silently miss every absolute reference — which is most of
    /// the references to an assumption.
    ///
    /// - Parameter cell: The cell, pinned or not.
    /// - Returns: The account name, or `nil` when nothing bound that cell.
    public func accountName(at cell: CellRef) -> String? {
        accountNames[CellRef(column: cell.column, row: cell.row)]
    }

    /// Records what the binder called a cell, ignoring its `$` markers.
    ///
    /// - Parameters:
    ///   - name: The account name.
    ///   - cell: The cell it belongs to.
    public mutating func name(_ name: String, at cell: CellRef) {
        accountNames[CellRef(column: cell.column, row: cell.row)] = name
    }

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
    ///
    /// For a derived axis these are the cells of the line immediately above the
    /// span — the boundary between the assumptions above and the series below.
    /// They are positions rather than headings, and may hold nothing at all.
    public let axisCells: [CellRef]

    /// How the axis was established, or `nil` when there is no axis.
    public let axisProvenance: AxisProvenance?

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

        // The header answer first: it is what a reader would do, and it is right
        // whenever it works. An explicit orientation is honoured even where it finds
        // no headings — a caller who states the direction is taken at their word,
        // and that is not something shape evidence should override.
        var orientation: Orientation?
        var axisLine: Int?
        var axisCells: [CellRef] = []
        var provenance: AxisProvenance?
        var headingsReadBothWays = false

        switch options.orientation {
        case .periodsAcrossColumns:
            orientation = .periodsAcrossColumns
            axisLine = rowRun?.line
            axisCells = rowRun?.cells ?? []

        case .periodsDownRows:
            orientation = .periodsDownRows
            axisLine = columnRun?.line
            axisCells = columnRun?.cells ?? []

        case .auto:
            switch (rowRun, columnRun) {
            case (nil, nil):
                break

            case (let row?, nil):
                orientation = .periodsAcrossColumns
                axisLine = row.line
                axisCells = row.cells

            case (nil, let column?):
                orientation = .periodsDownRows
                axisLine = column.line
                axisCells = column.cells

            case (let row?, let column?):
                if row.cells.count > column.cells.count {
                    orientation = .periodsAcrossColumns
                    axisLine = row.line
                    axisCells = row.cells
                } else if column.cells.count > row.cells.count {
                    orientation = .periodsDownRows
                    axisLine = column.line
                    axisCells = column.cells
                } else {
                    headingsReadBothWays = true
                    diagnostics.append(
                        Diagnostic(
                            severity: .error, code: .ambiguousOrientation,
                            message: "Row \(row.line) and column \(column.line) each hold "
                                + "\(row.cells.count) period headings; the sheet reads equally "
                                + "well both ways, so no direction was chosen"))
                }
            }
        }
        if !axisCells.isEmpty { provenance = .headings }

        // What the sheet's own arithmetic says, which is a separate question. It is
        // asked either way: as the fallback where the headings said nothing, and as
        // the check where they said something.
        let runs = ShapeRun.find(in: result.formulaASTs)
        let consensus = ShapeRun.consensus(among: runs)

        if axisCells.isEmpty {
            // Headings that read equally well both ways made two claims and were not
            // believed. That is a different situation from a sheet that made none,
            // and settling it from a third source would be the resolving-rather-than-
            // reporting this phase refuses everywhere else.
            if !headingsReadBothWays, let consensus,
               orientation.map({ $0 == consensus.orientation }) ?? true,
               let derived = derivedAxis(from: consensus, among: runs) {
                orientation = consensus.orientation
                axisLine = derived.line
                axisCells = derived.cells
                provenance = .shapeRuns(agreeing: consensus.agreeing)
            } else if options.orientation == .auto, !headingsReadBothWays {
                diagnostics.append(
                    Diagnostic(
                        severity: .error, code: .noPeriodAxis,
                        message: "No row or column holds two or more consecutive, advancing "
                            + "period headings, and no span of the sheet's formulas is agreed "
                            + "on by enough filled rows to derive one"))
            }
        } else if let consensus, let orientation,
                  disagrees(consensus, with: axisCells, along: orientation) {
            diagnostics.append(
                Diagnostic(
                    severity: .warning, code: .derivedAxisDiffers,
                    message: "The headings put the timeline at "
                        + "\(span(of: axisCells, along: orientation)) "
                        + "\(direction(orientation)), while \(consensus.agreeing) runs of like "
                        + "formulas agree on \(consensus.positions.lowerBound)..."
                        + "\(consensus.positions.upperBound) "
                        + "\(direction(consensus.orientation)). The headings were kept"))
        }

        return SheetGrid(
            cells: cells, cachedValues: cached, formulaASTs: result.formulaASTs,
            numberFormats: result.numberFormats, namedCells: namedCells,
            nodeToCell: nodeToCell, bounds: bounds, orientation: orientation,
            axisLine: axisLine, axisCells: axisCells, axisProvenance: provenance,
            diagnostics: diagnostics)
    }

    /// The axis a consensus span implies, placed on the line above it.
    ///
    /// The line matters as much as the span. ``axisLine`` is the boundary every
    /// later stage reads the sheet against — assumptions above it, series below —
    /// and the first agreeing run is the first series, so the boundary sits directly
    /// above it.
    ///
    /// That costs the boundary line itself, which on a derived sheet may hold real
    /// figures rather than headings: it is scanned by neither stage and becomes
    /// residue. One line, and it buys an axis on a sheet that would otherwise have
    /// none.
    ///
    /// - Parameters:
    ///   - consensus: The span the runs agreed on.
    ///   - runs: Every run on the sheet, to find which of them agreed.
    /// - Returns: The line and its cells, or `nil` when the span starts at the top
    ///   of the sheet and there is no line above it to put the axis on.
    private static func derivedAxis(
        from consensus: ShapeRun.Consensus, among runs: [ShapeRun]
    ) -> (line: Int, cells: [CellRef])? {
        let agreeing = runs.filter {
            $0.positions == consensus.positions && $0.orientation == consensus.orientation
        }
        guard let firstLine = agreeing.map(\.line).min() else { return nil }

        let line = firstLine - 1
        guard line >= 1 else { return nil }

        let cells = consensus.positions.map { position in
            consensus.orientation == .periodsAcrossColumns
                ? CellRef(column: position, row: line)
                : CellRef(column: line, row: position)
        }
        return (line, cells)
    }

    /// `across` or `down`, for a message a reader has to make sense of.
    private static func direction(_ orientation: Orientation) -> String {
        orientation == .periodsAcrossColumns ? "across" : "down"
    }

    /// The span a set of axis cells covers, along the axis direction.
    private static func span(of axisCells: [CellRef], along orientation: Orientation) -> String {
        let positions = axisCells.map { orientation == .periodsAcrossColumns ? $0.column : $0.row }
        guard let low = positions.min(), let high = positions.max() else { return "nothing" }
        return "\(low)...\(high)"
    }

    /// Whether the arithmetic and the headings name different timelines.
    ///
    /// Direction counts as a difference. A span of columns and a span of rows are
    /// different findings even where the integers coincide — and that case is not
    /// hypothetical: it is how one credit model reads its own sheet.
    ///
    /// **Narrower than inequality, and measurement is why.** The first rule written
    /// here reported any difference in span, and the first sheet it ran on was the
    /// Wharton ANSWER KEY: headings across columns 5–10, seventeen runs agreeing on
    /// 5–9. Nothing is wrong there. The sheet's last year is computed differently
    /// from the five before it — an exit, a terminal value — so the filled rule
    /// stops one column short of the timeline it belongs to.
    ///
    /// A run span *inside* the heading span is the same timeline with an end
    /// computed its own way, which is corroboration rather than contradiction. Only
    /// a span reaching outside the headings is evidence they found the wrong thing.
    private static func disagrees(
        _ consensus: ShapeRun.Consensus, with axisCells: [CellRef], along orientation: Orientation
    ) -> Bool {
        guard consensus.orientation == orientation else { return true }
        let positions = axisCells.map { orientation == .periodsAcrossColumns ? $0.column : $0.row }
        guard let low = positions.min(), let high = positions.max() else { return true }
        return consensus.positions.lowerBound < low || consensus.positions.upperBound > high
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
