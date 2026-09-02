import SwiftXLSX

/// Why the recognizer could not account for something, or what it decided.
///
/// Recognition is best-effort and never throws. A workbook that does not fit
/// yields a partial result plus diagnostics, so the caller can see exactly what
/// was not understood rather than inferring it from a number that looks low.
public struct Diagnostic: Sendable, Equatable {

    /// How much a finding matters.
    public enum Severity: Sendable, Equatable {

        /// A decision worth surfacing, not a problem.
        case info

        /// Something was degraded but the result remains usable.
        case warning

        /// Something could not be represented at all.
        case error
    }

    /// How much this finding matters.
    public let severity: Severity

    /// What kind of finding this is.
    public let code: DiagnosticCode

    /// The cell the finding concerns, or `nil` when it concerns the sheet.
    public let cell: CellRef?

    /// A human-readable explanation naming what was found and where.
    public let message: String

    /// Creates a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: How much this finding matters.
    ///   - code: What kind of finding this is.
    ///   - cell: The cell concerned, or `nil` for a sheet-level finding.
    ///   - message: A human-readable explanation.
    public init(severity: Severity, code: DiagnosticCode, cell: CellRef? = nil, message: String) {
        self.severity = severity
        self.code = code
        self.cell = cell
        self.message = message
    }
}

/// The kinds of finding recognition can report.
///
/// Raw values cross process boundaries through the MCP schema, so renaming a
/// case is a breaking change. The set is complete rather than grown per stage: a
/// `CaseIterable` with holes invites a second enum alongside it later, and codes
/// owned by stages that do not exist yet are listed with the stage that owns them.
public enum DiagnosticCode: String, Sendable, Equatable, CaseIterable {

    /// A formula node the importer cannot represent.
    case unsupportedFormulaNode

    /// An Excel function with no registry entry. Stage 3.
    case unregisteredFunction

    /// Rows and columns both read as a period axis, so neither was chosen.
    case ambiguousOrientation

    /// No row or column reads as a period axis.
    case noPeriodAxis

    /// A run of values with no label to bind to.
    case labelUnbound

    /// Two accounts resolved to the same name.
    case duplicateAccountName

    /// A cell's unit could not be inferred. Stage 3.
    case unitInferenceFailed

    /// Two cells in one account disagree about the unit. Stage 3.
    case unitConflict

    /// A reference to another sheet, which recognition does not yet follow.
    case crossSheetReference

    /// The sheet exceeds `maximumCells` and was not fully scanned.
    case scanLimitReached

    /// A reference more than one period back, or forward. Stage 3.
    case unsupportedLag

    /// A recomputed sensitivity grid disagrees with the sheet's cached grid. Stage 6.
    case sensitivityMismatch

    /// A cell in a bound row breaks the row's formula shape — a hand edit.
    case nonUniformRow

    /// An `IF` answerable from the timeline alone became an indicator series. Stage 3.
    case conditionalDemotedToData

    /// An `INDIRECT` or `OFFSET` whose target cannot be proven. Stage 3.
    case dynamicReference

    /// A dynamic reference resolved to a static one. Stage 3.
    case foldedDynamicReference

    /// A carry whose opening value the sheet does not state. Stage 3.
    ///
    /// A rollforward needs the period before the timeline, and that figure lives
    /// in the first period's own cell. When that cell is itself computed and the
    /// file carries no cached value for it, there is nothing to seed from — and
    /// seeding zero produces a model that runs, converges, and is wrong from the
    /// first period on.
    case unseededCarry
}
