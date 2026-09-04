import Foundation
import SwiftXLSX

/// A run of adjacent cells computing the same way.
///
/// ## Why this exists
///
/// ``PeriodAxis`` reads a timeline off a row of period headings, which is how a
/// person finds one. On real workbooks that frequently fails: a teaching model
/// heads its columns `0, 1, 2 …`, a credit model heads them `FYE` and `LTM`, and
/// many sheets carry no heading row at all. Measured across three corpora, 60 of
/// 77 workbooks, 12 of 18 sheets on one credit model, and 100 of 104 on one media
/// model had no timeline the header detector could find.
///
/// But a timeline leaves a second trace, and a stronger one. **A rule filled
/// across a row is the same formula in every column** — a fact about the formulas
/// rather than about the labels above them. Three cells side by side sharing one
/// R1C1 shape are three periods of one account, whatever sits above them and
/// whether or not anything does.
///
/// ## What a run is not
///
/// A run is not an account, and not yet an axis. It is evidence: collect the runs
/// on a sheet and the span the most of them agree on is a timeline the sheet's own
/// arithmetic asserts. On a credit-model sheet where header detection found five
/// year-like values down a column and read the whole sheet sideways, sixteen runs
/// agreed on one span across — which is not merely another candidate but better
/// evidence, of a kind a heading row cannot supply.
public struct ShapeRun: Sendable, Equatable {

    /// The row the run lies along, or the column when it runs downward.
    public let line: Int

    /// The columns the run spans, or the rows when it runs downward.
    public let positions: ClosedRange<Int>

    /// Which way the run runs.
    public let orientation: SheetGrid.Orientation

    /// The shared R1C1 shape, in ``FormulaUniformity``'s canonical form.
    public let shape: String

    /// How many cells the run covers.
    public var length: Int { positions.count }

    /// The shortest run that can be a timeline.
    ///
    /// Two adjacent cells computing alike is as likely to be a pair of one-offs as
    /// a rule filled across; three is the point at which repetition is the simpler
    /// explanation.
    public static let minimumLength = 3

    /// Every run on a sheet, across rows and down columns.
    ///
    /// Both directions, because a model may run either way and the sheet decides.
    /// A run down a column and a run across a row are both returned; which of them
    /// describes the timeline is a question for whatever weighs the evidence.
    ///
    /// - Parameters:
    ///   - grid: The sheet's topology.
    ///   - minimumLength: The shortest run to report.
    /// - Returns: The runs, unordered.
    public static func find(
        in grid: SheetGrid, minimumLength: Int = ShapeRun.minimumLength
    ) -> [ShapeRun] {
        var acrossRows: [Int: [(position: Int, shape: String)]] = [:]
        var downColumns: [Int: [(position: Int, shape: String)]] = [:]

        for (cell, ast) in grid.formulaASTs {
            let shape = FormulaUniformity.canonicalShape(of: ast, at: cell)
            acrossRows[cell.row, default: []].append((cell.column, shape))
            downColumns[cell.column, default: []].append((cell.row, shape))
        }

        var runs = spans(
            in: acrossRows, orientation: .periodsAcrossColumns, minimumLength: minimumLength)
        runs += spans(
            in: downColumns, orientation: .periodsDownRows, minimumLength: minimumLength)
        return runs
    }

    /// Maximal runs of adjacent, like-shaped cells along each line.
    private static func spans(
        in lines: [Int: [(position: Int, shape: String)]],
        orientation: SheetGrid.Orientation,
        minimumLength: Int
    ) -> [ShapeRun] {
        var runs: [ShapeRun] = []
        for (line, cells) in lines {
            let ordered = cells.sorted { $0.position < $1.position }
            var start = 0
            while start < ordered.count {
                var end = start
                // Adjacent and alike. A gap ends a run, because adjacency is what
                // makes it a span rather than a set of cells that happen to match.
                while end + 1 < ordered.count,
                      ordered[end + 1].position == ordered[end].position + 1,
                      ordered[end + 1].shape == ordered[start].shape {
                    end += 1
                }
                if end - start + 1 >= minimumLength {
                    runs.append(
                        ShapeRun(
                            line: line,
                            positions: ordered[start].position...ordered[end].position,
                            orientation: orientation,
                            shape: ordered[start].shape))
                }
                start = end + 1
            }
        }
        return runs
    }
}

// MARK: - What the runs agree on

extension ShapeRun {

    /// The span a sheet's own arithmetic asserts most often.
    ///
    /// A single run is one row's habit. A span that many runs independently agree
    /// on is a claim the sheet makes about its own shape, and the number agreeing
    /// is the strength of the claim — which is why ``agreeing`` is carried rather
    /// than discarded once the winner is known. A caller weighing a derived axis
    /// against a header one needs to see how much of the sheet stood behind it.
    public struct Consensus: Sendable, Equatable {

        /// The columns the agreeing runs span, or the rows when they run downward.
        public let positions: ClosedRange<Int>

        /// Which way the agreeing runs run.
        public let orientation: SheetGrid.Orientation

        /// How many runs agreed on this exact span.
        public let agreeing: Int

        /// How many cells the span covers — the number of periods it would yield.
        public var length: Int { positions.count }

        /// Creates a consensus span.
        ///
        /// - Parameters:
        ///   - positions: The span the runs agreed on.
        ///   - orientation: Which way they run.
        ///   - agreeing: How many runs agreed.
        public init(positions: ClosedRange<Int>, orientation: SheetGrid.Orientation, agreeing: Int) {
            self.positions = positions
            self.orientation = orientation
            self.agreeing = agreeing
        }
    }

    /// The fewest agreeing runs that can assert a timeline.
    ///
    /// The same argument as ``minimumLength``, applied to rows instead of cells.
    /// One run agreeing with itself is not evidence; two rows computing alike is
    /// as easily a pair as a pattern. Three is the point at which a filled rule
    /// is the simpler explanation.
    ///
    /// Far below what the reference sheets produce — the winning spans measured six
    /// agreeing runs on Kelly's Roast Beef and sixteen on the credit model's sheet
    /// `A` — so the floor screens noise without reaching the cases it exists for.
    public static let minimumAgreement = 3

    /// The span the most runs agree on, when one span does.
    ///
    /// Agreement is exact: two runs agree when they cover the same positions in the
    /// same direction. A span of columns and a span of rows are different findings
    /// even where the integers coincide, so they are tallied apart.
    ///
    /// Returns `nil` in the two cases where the sheet has not named a timeline:
    /// when no span reaches ``minimumAgreement``, and when two spans are supported
    /// equally. A tie is the sheet declining to choose, and choosing for it would
    /// be the same guess this phase refuses to make when a derived axis and a
    /// header axis disagree.
    ///
    /// - Parameters:
    ///   - runs: The runs found on one sheet, in any order.
    ///   - minimumAgreement: The fewest agreeing runs that can win.
    /// - Returns: The winning span with its evidence, or `nil`.
    public static func consensus(
        among runs: [ShapeRun], minimumAgreement: Int = ShapeRun.minimumAgreement
    ) -> Consensus? {
        struct Span: Hashable {
            let positions: ClosedRange<Int>
            let orientation: SheetGrid.Orientation
        }

        var tally: [Span: Int] = [:]
        for run in runs {
            tally[Span(positions: run.positions, orientation: run.orientation), default: 0] += 1
        }

        guard let best = tally.max(by: { $0.value < $1.value }) else { return nil }
        guard best.value >= minimumAgreement else { return nil }
        guard tally.values.filter({ $0 == best.value }).count == 1 else { return nil }

        return Consensus(
            positions: best.key.positions,
            orientation: best.key.orientation,
            agreeing: best.value)
    }
}
