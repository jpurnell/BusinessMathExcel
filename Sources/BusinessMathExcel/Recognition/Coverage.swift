/// How much of a sheet the recognizer accounted for.
///
/// Tracked as a progress metric toward 100%, not as a gate. A recognizer that
/// fails a build on a coverage threshold invites the one behaviour this package
/// refuses — recognizing something badly in order to make a number go up.
public struct Coverage: Sendable, Equatable {

    /// Cells holding a value, formula, or label. Blank cells are not counted.
    public let populatedCells: Int

    /// Populated cells the recognizer accounted for, whether as part of an
    /// account or as residue. A cell that produced only a diagnostic is not
    /// recognized.
    public let recognizedCells: Int

    /// Creates a coverage measurement.
    ///
    /// - Parameters:
    ///   - populatedCells: Cells holding something.
    ///   - recognizedCells: Cells the recognizer accounted for.
    public init(populatedCells: Int, recognizedCells: Int) {
        self.populatedCells = populatedCells
        self.recognizedCells = recognizedCells
    }

    /// The recognized share of the sheet, from `0` to `1`.
    ///
    /// An empty sheet is `0` rather than a division by zero. Nothing was missed,
    /// but nothing was recognized either, and reporting `1` would let an empty
    /// sheet read as perfect coverage.
    public var fraction: Double {
        guard populatedCells > 0 else { return 0 }
        return Double(recognizedCells) / Double(populatedCells)
    }

    /// Whether every populated cell was accounted for.
    ///
    /// False for an empty sheet: there is nothing to be complete about.
    public var isComplete: Bool {
        populatedCells > 0 && recognizedCells == populatedCells
    }
}
