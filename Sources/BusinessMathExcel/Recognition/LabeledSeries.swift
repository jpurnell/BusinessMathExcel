import SwiftXLSX

/// Stage 2 — a label bound to the values it names, one per period.
///
/// ## What decides which cells belong together
///
/// The **axis**, not adjacency. Once ``PeriodAxis`` has established which columns
/// (or rows) hold periods, a series is simply that row's cells in those columns.
///
/// This answers a question that looks hard from the other direction. Scanning for
/// runs of adjacent values forces a ruling on whether a blank breaks a run — and
/// there is no good ruling, because a blank inside a row of figures is ordinary
/// while a blank between two blocks is meaningful. Anchoring on the axis makes the
/// question moot: a blank in a period column is a **missing value for that
/// period**, recorded as `nil` in ``cells``, and the boundary was already
/// established by the axis rather than guessed from spacing.
///
/// It also handles the layout every real model uses, where a label in column B is
/// separated from values starting in column E by empty formatting columns.
///
/// ## Naming
///
/// The label is the nearest text cell on the series' own line, ahead of the first
/// period. A series with no such cell is still recognized — it is named for the
/// first cell it holds and reported as ``DiagnosticCode/labelUnbound`` at `info`.
/// Values without a heading are a naming problem, not a reason to drop data.
public struct LabeledSeries: Sendable, Equatable {

    /// The series' name: its label, or its first cell's address when unlabelled.
    ///
    /// Unique within a sheet. A repeated label is disambiguated by appending its
    /// label cell, and reported as ``DiagnosticCode/duplicateAccountName``.
    public let name: String

    /// The cell the label was read from, or `nil` when the name is address-derived.
    public let labelCell: CellRef?

    /// The row this series occupies, or the column when periods run down rows.
    public let line: Int

    /// One entry per period, in axis order. `nil` where that period has no cell.
    public let cells: [CellRef?]

    /// The series' value in the anchor column, when it has one.
    ///
    /// Deliberately not part of ``cells``, which stays aligned one-to-one with the
    /// axis. This value belongs to the series but to no period — an equity cheque
    /// written at close, an opening balance — and a consumer that needs it, such
    /// as a return calculation, prepends it knowingly rather than finding it mixed
    /// into the timeline.
    public let anchorCell: CellRef?

    /// The cells that actually hold something, in axis order.
    public var populatedCells: [CellRef] { cells.compactMap { $0 } }

    // MARK: - Binding

    /// Binds every series on a sheet to its label.
    ///
    /// - Parameters:
    ///   - grid: The sheet's topology, with an established orientation.
    ///   - axis: The recovered time axis.
    /// - Returns: One series per line holding values in the period columns, plus
    ///   diagnostics for unlabelled and duplicated series.
    public static func bind(
        in grid: SheetGrid,
        axis: PeriodAxis
    ) -> (series: [LabeledSeries], diagnostics: [Diagnostic]) {
        guard let orientation = grid.orientation, let axisLine = grid.axisLine else {
            return ([], [])
        }

        let periodPositions = axis.sources.map {
            orientation == .periodsAcrossColumns ? $0.column : $0.row
        }
        guard let firstPeriod = periodPositions.min() else { return ([], []) }

        var diagnostics: [Diagnostic] = []
        var series: [LabeledSeries] = []
        var usedNames: Set<String> = []

        for line in linesHoldingValues(in: grid, orientation: orientation, at: periodPositions)
        where line != axisLine {
            let cells = periodPositions.map { position -> CellRef? in
                let ref = cellRef(line: line, position: position, orientation: orientation)
                return grid.cells[ref] == nil ? nil : ref
            }
            guard let firstCell = cells.compactMap({ $0 }).first else { continue }

            let anchorCell = axis.anchor.map {
                cellRef(line: line, position: $0.position, orientation: orientation)
            }
            let boundAnchor = anchorCell.flatMap { grid.cells[$0] == nil ? nil : $0 }

            let labelCell = label(in: grid, line: line, before: firstPeriod, orientation: orientation)
            var name = labelCell.flatMap { text(of: grid.cells[$0]) } ?? firstCell.reference

            if let labelCell, usedNames.contains(name) {
                // Both survive: a repeated heading is a naming collision, and
                // dropping one would lose a row of the model to a formatting habit.
                diagnostics.append(
                    Diagnostic(
                        severity: .warning, code: .duplicateAccountName, cell: labelCell,
                        message: "\"\(name)\" labels more than one series; the one at "
                            + "\(labelCell.reference) is distinguished by its cell"))
                name = "\(name) (\(labelCell.reference))"
            } else if labelCell == nil {
                diagnostics.append(
                    Diagnostic(
                        severity: .info, code: .labelUnbound, cell: firstCell,
                        message: "The series at \(firstCell.reference) has no label ahead of it "
                            + "and is named for its first cell"))
            }

            usedNames.insert(name)
            series.append(
                LabeledSeries(
                    name: name, labelCell: labelCell, line: line, cells: cells,
                    anchorCell: boundAnchor))
        }

        return (series, diagnostics)
    }

    // MARK: - Private

    /// Lines holding at least one cell in a period position, in order.
    private static func linesHoldingValues(
        in grid: SheetGrid,
        orientation: SheetGrid.Orientation,
        at periodPositions: [Int]
    ) -> [Int] {
        let positions = Set(periodPositions)
        var lines: Set<Int> = []
        for ref in grid.cells.keys {
            let position = orientation == .periodsAcrossColumns ? ref.column : ref.row
            guard positions.contains(position) else { continue }
            lines.insert(orientation == .periodsAcrossColumns ? ref.row : ref.column)
        }
        return lines.sorted()
    }

    /// The nearest text cell on a line, ahead of the first period.
    private static func label(
        in grid: SheetGrid,
        line: Int,
        before firstPeriod: Int,
        orientation: SheetGrid.Orientation
    ) -> CellRef? {
        var candidates: [(position: Int, ref: CellRef)] = []
        for (ref, kind) in grid.cells {
            let lineOf = orientation == .periodsAcrossColumns ? ref.row : ref.column
            let position = orientation == .periodsAcrossColumns ? ref.column : ref.row
            guard lineOf == line, position < firstPeriod, text(of: kind) != nil else { continue }
            candidates.append((position, ref))
        }
        // Nearest to the values, so a sub-heading beats the section title above it.
        return candidates.max { $0.position < $1.position }?.ref
    }

    private static func cellRef(
        line: Int, position: Int, orientation: SheetGrid.Orientation
    ) -> CellRef {
        orientation == .periodsAcrossColumns
            ? CellRef(column: position, row: line)
            : CellRef(column: line, row: position)
    }

    private static func text(of kind: NodeKind?) -> String? {
        switch kind {
        case .textInput(let value), .label(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }
}
