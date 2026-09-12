import SwiftXLSX

/// The rectangle a What-If table occupies on a sheet.
///
/// ## Why the reader must know where one is
///
/// Excel's Data Table is a block of answers, not a block of accounts. Every cell
/// in it holds the same formula evaluated against a different pair of inputs, and
/// the file says so once: the master cell carries
/// `<f t="dataTable" ref="P6:T10" dt2D="1"/>` and every other cell in the grid
/// holds a cached number and nothing else.
///
/// A recognizer that does not know this sees a rectangle of numbers, and any
/// label on those rows appears to own them. On the Wharton `ANSWER KEY` the IRR
/// sensitivity grid sits in columns N through T on the same rows as the
/// assumption tables, so `Total Purchase Price` in `F5` owned its own figure in
/// `H5` *and* six cells of the grid's header row — seven values for one label,
/// which is refused. Six of the sheet's seven ambiguous assumptions were this one
/// block, which is the same collision ``LabeledSeries`` solves for series, one
/// block further right.
///
/// Recognizing the table's *contents* is a later stage. This type answers only
/// the question the earlier stages need: which cells are spoken for.
///
/// ## What the block covers
///
/// A **two-way** table varies one input across the row above its body and another
/// down the column to its left, so the block is one row taller and one column
/// wider than the span the file states, corner included. The file marks this with
/// `dt2D`, which reaches us as the presence of a *second* input reference in the
/// marker.
///
/// A **one-way** table is taken at exactly its stated span. Which side its inputs
/// sit on is in the `dtr` attribute, which the reader does not carry; assuming
/// both sides would swallow a column of real accounts, and assuming neither
/// leaves a label reported rather than read. Reported is the failure worth having.
public struct DataTableBlock: Sendable, Equatable {

    /// The span the file states, holding the table's answers.
    public let body: CellRange

    /// The cell carrying the marker, which is the body's top-left.
    public let markerCell: CellRef

    /// Whether the table varies an input on both axes.
    public let isTwoWay: Bool

    /// Whether a cell falls inside the block, inputs included.
    ///
    /// - Parameter cell: The cell to test.
    /// - Returns: `true` when the table speaks for that cell.
    public func contains(_ cell: CellRef) -> Bool {
        let margin = isTwoWay ? 1 : 0
        let columns = min(body.start.column, body.end.column) - margin
            ... max(body.start.column, body.end.column)
        let rows = min(body.start.row, body.end.row) - margin
            ... max(body.start.row, body.end.row)
        return columns.contains(cell.column) && rows.contains(cell.row)
    }

    /// Finds every What-If table on a sheet.
    ///
    /// - Parameter grid: The sheet's topology.
    /// - Returns: One block per marker, in no particular order.
    public static func find(in grid: SheetGrid) -> [DataTableBlock] {
        var blocks: [DataTableBlock] = []
        for (cell, ast) in grid.formulaASTs {
            guard case .function(let name, let arguments) = ast,
                  name == "_DATATABLE",
                  case .text(let span)? = arguments.first,
                  let body = range(of: span)
            else { continue }
            blocks.append(
                DataTableBlock(
                    body: body, markerCell: cell, isTwoWay: arguments.count >= 3))
        }
        return blocks
    }

    /// Parses the `A1:B2` span the marker carries.
    ///
    /// - Parameter span: The span as written.
    /// - Returns: The range, or `nil` when it is not one.
    private static func range(of span: String) -> CellRange? {
        let parts = span.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return CellRange(from: CellRef(String(parts[0])), to: CellRef(String(parts[1])))
    }
}
