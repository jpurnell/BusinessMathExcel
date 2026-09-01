/// Knobs a caller can turn before recognition runs.
///
/// Every default is the conservative choice: infer nothing a caller has stated,
/// and stop rather than grind on a sheet larger than expected.
public struct RecognizerOptions: Sendable {

    /// Which way the caller says the time axis runs.
    public enum Orientation: Sendable, Equatable {

        /// Work it out from the sheet, and report ambiguity rather than guess.
        case auto

        /// Periods run left to right along a row.
        case periodsAcrossColumns

        /// Periods run top to bottom down a column.
        case periodsDownRows
    }

    /// Axis direction. Defaults to ``Orientation/auto``.
    ///
    /// A stated direction is taken as fact and suppresses detection — a caller
    /// who knows their workbook should not have to argue with a heuristic.
    public var orientation: Orientation

    /// The largest number of populated cells to scan. Defaults to 100,000.
    ///
    /// Exceeding it yields ``DiagnosticCode/scanLimitReached`` and a partial
    /// result rather than an unbounded scan.
    public var maximumCells: Int

    /// Creates recognizer options.
    ///
    /// - Parameters:
    ///   - orientation: Axis direction, or `.auto` to detect it.
    ///   - maximumCells: The largest number of populated cells to scan.
    public init(orientation: Orientation = .auto, maximumCells: Int = 100_000) {
        self.orientation = orientation
        self.maximumCells = maximumCells
    }
}
