import BusinessMath
import SwiftXLSX

/// Stage 1 — the time axis recovered from a sheet's headings.
///
/// The periods are BusinessMath's own `Period` values, which is what makes the
/// result usable by `ModelDefinition` downstream rather than a local stand-in
/// that would need translating again.
///
/// ## Recognized granularity
///
/// **Annual only.** Not an oversight and not a placeholder — a deliberate scope,
/// chosen from the reference workbooks rather than from imagination. Neither the
/// Wharton LBO Practice Model nor the credit model measured alongside it contains
/// a single quarterly, monthly, or date-valued heading; Wharton's axis is six
/// calendar years.
///
/// Recognizing quarters would mean guessing at a spelling (`Q1 2024`? `1Q24`?
/// `Q1`?) and generalizing the strictly-increasing rule to `(year, quarter)`
/// pairs, with no file to check the guess against. That is how a recognizer
/// acquires code that is confidently wrong. The set should grow when a workbook
/// that needs it arrives.
///
/// The fiscal and estimate spellings — `FY2024`, `FY24`, `2024E` — are accepted
/// and tested, but appear in **neither** reference workbook, so they are
/// supported rather than evidenced.
public struct PeriodAxis: Sendable, Equatable {

    /// The recovered periods, in axis order.
    public let periods: [Period]

    /// The heading cells the periods came from, in the same order.
    ///
    /// Always the same length as ``periods``: every period names the cell it was
    /// read from, so a recognition result can be traced back to the sheet.
    ///
    /// On a derived axis there is no cell a period was read from, so these are the
    /// cells at each position on the axis line — the sheet coordinates the period
    /// occupies rather than the heading it was named by.
    public let sources: [CellRef]

    /// The granularity of the recovered periods. Always `.annual` — see the type's
    /// discussion.
    ///
    /// On a derived axis this is the granularity of the *encoding*, not a claim
    /// about the sheet: ordinal positions have no duration, and `Period` has no
    /// case that says so. ``provenance`` is what distinguishes them.
    public let granularity: PeriodType

    /// How the axis was established — read from headings, or derived from the
    /// sheet's own arithmetic.
    ///
    /// Worth asking before reading ``periods``. A heading axis carries the years
    /// the sheet named. A derived axis carries positions, and nothing inside a
    /// `Period` says which of the two it is holding.
    public let provenance: SheetGrid.AxisProvenance

    /// The column immediately before the timeline, when it holds values belonging
    /// to a series rather than to any period.
    ///
    /// A transaction model has figures that belong to no year: the equity written
    /// at close, an opening balance, a purchase price. Wharton puts them in the
    /// column left of its first year, headed `Closing`, and its IRR runs from
    /// there — `D61:I61` against an axis of `E27:J27`. A series bound only to
    /// period columns would miss the initial outflow entirely and compute a return
    /// on nothing.
    ///
    /// Kept separate from ``periods`` rather than prepended to it. It is not a
    /// period, and giving it one would place a cash flow in a year it did not
    /// happen.
    public let anchor: Anchor?

    /// A column of values sitting before the timeline.
    public struct Anchor: Sendable, Equatable {

        /// The column index, or row index when periods run down rows.
        public let position: Int

        /// The heading, as written — `Closing`, `At Close`, `Initial`.
        public let label: String

        /// The heading cell the anchor was recognized from.
        public let source: CellRef

        /// Creates an anchor.
        ///
        /// - Parameters:
        ///   - position: The column or row index.
        ///   - label: The heading text.
        ///   - source: The heading cell.
        public init(position: Int, label: String, source: CellRef) {
            self.position = position
            self.label = label
            self.source = source
        }
    }

    /// The number of periods on the axis.
    public var count: Int { periods.count }

    // MARK: - Building

    /// Recovers the time axis from a grid's detected headings.
    ///
    /// Reads the years through the same rule the grid used to find them, so the
    /// two cannot drift apart.
    ///
    /// - Parameters:
    ///   - grid: A grid whose axis has been detected.
    ///   - options: Recognizer options.
    /// - Returns: The axis, or `nil` when the grid found none, together with any
    ///   diagnostics. A grid with no axis produces no diagnostic here: it has
    ///   already reported that, and repeating it would double-count one problem.
    public static func build(
        from grid: SheetGrid,
        options: RecognizerOptions = RecognizerOptions()
    ) -> (axis: PeriodAxis?, diagnostics: [Diagnostic]) {
        guard !grid.axisCells.isEmpty else { return (nil, []) }

        // A derived axis has no headings — that is its premise — so its periods are
        // ordinal: position 1, 2, 3, in span order, asserting sequence and nothing
        // else. The structure of a model is mechanical and logical; its labels are
        // arbitrary and human. Reading whatever text happened to sit above the span
        // would make a structural finding depend on the arbitrary part, and would
        // fail in exactly the cases this path exists to serve.
        //
        // Counted from one rather than zero, and not as a matter of taste.
        // `Period.year(0)` does not survive Foundation's Gregorian era boundary: it
        // comes back equal to `Period.year(1)`, which would silently collapse the
        // first two periods of every derived axis into one.
        //
        // No anchor either. The anchor rule reads a heading beside the timeline,
        // which is the one thing a derived axis is defined by not having.
        if case .shapeRuns(let agreeing)? = grid.axisProvenance {
            return (
                PeriodAxis(
                    periods: (1...grid.axisCells.count).map { Period.year($0) },
                    sources: grid.axisCells,
                    granularity: .annual,
                    provenance: .shapeRuns(agreeing: agreeing),
                    anchor: nil
                ),
                []
            )
        }

        var periods: [Period] = []
        for cell in grid.axisCells {
            guard let kind = grid.cells[cell],
                  let year = PeriodHeader.year(of: kind, cached: grid.cachedValues[cell]) else {
                // Unreachable through `SheetGrid`, which only reports cells that
                // already parsed. Guarded rather than assumed, so a future change
                // to the detector surfaces here instead of producing a short axis.
                return (
                    nil,
                    [Diagnostic(
                        severity: .error, code: .noPeriodAxis, cell: cell,
                        message: "\(cell.reference) was reported as a period heading but does "
                            + "not read as one")]
                )
            }
            periods.append(Period.year(year))
        }

        return (
            PeriodAxis(
                periods: periods,
                sources: grid.axisCells,
                granularity: .annual,
                provenance: .headings,
                anchor: anchor(before: grid.axisCells, in: grid)
            ),
            []
        )
    }

    /// The anchor column before a timeline, if there is one.
    ///
    /// Two conditions, and the second is the one that matters. The cell on the axis
    /// line immediately before the first period must hold text that is **not** a
    /// period — a heading like `Closing`. And the column below it must hold more
    /// figures than text.
    ///
    /// Without that second test, every sheet whose row labels happen to sit against
    /// the timeline would grow a phantom period out of its own labels. The
    /// discriminator is what lies *below* the heading: a label column holds words,
    /// an anchor column holds money.
    ///
    /// - Parameters:
    ///   - axisCells: The period headings, in order.
    ///   - grid: The sheet's topology.
    /// - Returns: The anchor, or `nil`.
    private static func anchor(before axisCells: [CellRef], in grid: SheetGrid) -> Anchor? {
        guard let orientation = grid.orientation, let first = axisCells.first else { return nil }

        let axisLine = orientation == .periodsAcrossColumns ? first.row : first.column
        let firstPeriod = orientation == .periodsAcrossColumns ? first.column : first.row
        let candidate = firstPeriod - 1
        guard candidate >= 1 else { return nil }

        let headingCell = orientation == .periodsAcrossColumns
            ? CellRef(column: candidate, row: axisLine)
            : CellRef(column: axisLine, row: candidate)

        guard case .textInput(let heading)? = grid.cells[headingCell] else { return nil }
        let label = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, PeriodHeader.year(of: label) == nil else { return nil }

        var figures = 0
        var words = 0
        for (cellRef, kind) in grid.cells {
            let position = orientation == .periodsAcrossColumns ? cellRef.column : cellRef.row
            let line = orientation == .periodsAcrossColumns ? cellRef.row : cellRef.column
            guard position == candidate, line != axisLine else { continue }
            switch kind {
            case .input, .formula, .output: figures += 1
            case .textInput, .label: words += 1
            }
        }

        guard figures > words else { return nil }
        return Anchor(position: candidate, label: label, source: headingCell)
    }
}
