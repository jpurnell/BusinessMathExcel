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
