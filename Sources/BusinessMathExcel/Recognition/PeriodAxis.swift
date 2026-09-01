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
    public let sources: [CellRef]

    /// The granularity of the recovered periods. Always `.annual` — see the type's
    /// discussion.
    public let granularity: PeriodType

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
            PeriodAxis(periods: periods, sources: grid.axisCells, granularity: .annual),
            []
        )
    }
}
