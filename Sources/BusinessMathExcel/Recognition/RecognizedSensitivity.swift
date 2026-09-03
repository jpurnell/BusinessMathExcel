import Foundation
import BusinessMath
import SwiftXLSX

/// A two-variable What-If table, read.
///
/// ## What the file states, and what it leaves to position
///
/// Excel writes a data table as a single marker on the body's top-left cell —
/// `<f t="dataTable" ref="P6:T10" dt2D="1" r1="D11" r2="D21"/>` — and every other
/// cell in the body holds a cached number with no formula at all. The marker names
/// the span and the two cells values are substituted *into*. It names nothing else.
///
/// Everything that gives the table meaning sits around the body and is identified
/// by where it is:
///
/// | Where | What it is |
/// |---|---|
/// | The row above the body | The values substituted into the row driver |
/// | The column left of the body | The values substituted into the column driver |
/// | The corner, above and left | The formula being measured |
///
/// ## A table is not an account
///
/// It is an analysis *of* the model: a grid of answers the model already produced
/// under different assumptions. So it sits beside the accounts in
/// ``RecognizedModel`` rather than among them, and ``ModelMaterializer`` ignores
/// it. A grid of answers is not a rule.
///
/// ## What this does not do
///
/// It does not recompute the grid. That needs the measured output, which on a real
/// sheet is typically an aggregate over the whole timeline — `IRR` over an equity
/// row, say — and every formula in a `ModelDefinition` is period-local by design.
/// Reading what the sheet computed is a different claim from being able to compute
/// it again, and only the first is made here.
public struct RecognizedSensitivity: Sendable, Equatable {

    /// The account whose value varies across the top of the table.
    ///
    /// Named for the account the marker's row-input cell belongs to, or that
    /// cell's address when the sheet gives it no label. A table whose drivers
    /// cannot be named is still a table.
    public let rowDriver: String

    /// The account whose value varies down the side of the table.
    public let columnDriver: String

    /// The values substituted into ``rowDriver``, left to right.
    public let rowValues: [Double]

    /// The values substituted into ``columnDriver``, top to bottom.
    public let columnValues: [Double]

    /// The answers, `results[column][row]`.
    ///
    /// Indexed the way the grid is laid out and the way
    /// `TwoWayScenarioSensitivityAnalysis` documents: the outer array walks
    /// ``columnValues`` — down the side — and the inner walks ``rowValues``.
    public let results: [[Double]]

    /// Where the formula being measured lives.
    ///
    /// The corner cell, above and left of the body. Kept as a cell rather than
    /// resolved to an account because it frequently is not one: on the Wharton
    /// sheet it points at an `IRR` over a whole row, which the period-local
    /// grammar has no account for.
    public let measuredCell: CellRef

    /// The cells this table occupies, body and inputs.
    public let cells: [CellRef]

    /// Reads every two-variable table on a sheet.
    ///
    /// - Parameters:
    ///   - grid: The sheet's topology.
    ///   - axis: The recovered time axis, for naming the drivers.
    /// - Returns: One entry per two-variable table. One-variable tables are not
    ///   returned: they have a single driver, and reading one as two-variable
    ///   would invent an axis the file does not describe.
    public static func read(in grid: SheetGrid, axis: PeriodAxis) -> [RecognizedSensitivity] {
        var tables: [RecognizedSensitivity] = []
        for (cell, ast) in grid.formulaASTs.sorted(by: { $0.key.reference < $1.key.reference }) {
            guard case .function("_DATATABLE", let arguments) = ast,
                  arguments.count >= 3,
                  case .text(let span)? = arguments.first,
                  case .cellRef(let rowInput) = arguments[1],
                  case .cellRef(let columnInput) = arguments[2],
                  let body = range(of: span)
            else { continue }

            let top = min(body.start.row, body.end.row)
            let left = min(body.start.column, body.end.column)
            let bottom = max(body.start.row, body.end.row)
            let right = max(body.start.column, body.end.column)
            guard top > 1, left > 1 else { continue }

            let rowValues = (left...right).compactMap {
                value(at: CellRef(column: $0, row: top - 1), in: grid)
            }
            let columnValues = (top...bottom).compactMap {
                value(at: CellRef(column: left - 1, row: $0), in: grid)
            }
            guard rowValues.count == right - left + 1,
                  columnValues.count == bottom - top + 1
            else { continue }

            var results: [[Double]] = []
            for row in top...bottom {
                let line = (left...right).compactMap {
                    value(at: CellRef(column: $0, row: row), in: grid)
                }
                guard line.count == rowValues.count else { break }
                results.append(line)
            }
            guard results.count == columnValues.count else { continue }

            var occupied: [CellRef] = []
            for row in (top - 1)...bottom {
                for column in (left - 1)...right {
                    occupied.append(CellRef(column: column, row: row))
                }
            }

            tables.append(
                RecognizedSensitivity(
                    rowDriver: driverName(at: rowInput, in: grid, axis: axis),
                    columnDriver: driverName(at: columnInput, in: grid, axis: axis),
                    rowValues: rowValues,
                    columnValues: columnValues,
                    results: results,
                    measuredCell: CellRef(column: left - 1, row: top - 1),
                    cells: occupied))
            _ = cell
        }
        return tables
    }

    /// This table as BusinessMath's own analysis type.
    ///
    /// `TwoWayScenarioSensitivityAnalysis` documents `results[i][j]` as the output
    /// for `inputValues1[i]` and `inputValues2[j]`. The outer index walks this
    /// table's ``columnValues``, so the column driver is driver 1 — an ordering
    /// worth stating, because getting it backwards transposes a grid silently.
    ///
    /// - Returns: The analysis.
    public func analysis() -> TwoWayScenarioSensitivityAnalysis {
        TwoWayScenarioSensitivityAnalysis(
            inputDriver1: columnDriver,
            inputDriver2: rowDriver,
            inputValues1: columnValues,
            inputValues2: rowValues,
            results: results)
    }

    // MARK: - Private

    /// The account a driver cell belongs to, or its address.
    private static func driverName(
        at cell: CellRef, in grid: SheetGrid, axis: PeriodAxis
    ) -> String {
        if let bound = grid.accountName(at: cell) { return bound }
        guard let orientation = grid.orientation else { return cell.reference }

        // The nearest label before the cell on its own line — the same rule the
        // rest of recognition names by, so a driver and the account it drives get
        // the same name.
        let line = orientation == .periodsAcrossColumns ? cell.row : cell.column
        let here = orientation == .periodsAcrossColumns ? cell.column : cell.row

        var best: (position: Int, text: String)?
        for (reference, kind) in grid.cells {
            let cellLine = orientation == .periodsAcrossColumns ? reference.row : reference.column
            let position = orientation == .periodsAcrossColumns
                ? reference.column : reference.row
            guard cellLine == line, position < here,
                  case .textInput(let text) = kind
            else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if best == nil || position > (best?.position ?? 0) { best = (position, trimmed) }
        }
        return best?.text ?? cell.reference
    }

    /// A cell's number, whether typed or computed.
    private static func value(at cell: CellRef, in grid: SheetGrid) -> Double? {
        if case .input(let literal)? = grid.cells[cell] { return literal }
        if case .number(let cached)? = grid.cachedValues[cell] { return cached }
        return nil
    }

    /// Parses the `A1:B2` span the marker carries.
    private static func range(of span: String) -> CellRange? {
        let parts = span.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return CellRange(from: CellRef(String(parts[0])), to: CellRef(String(parts[1])))
    }
}
