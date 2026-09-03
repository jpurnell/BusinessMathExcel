import BusinessMath
import SwiftXLSX

/// Stage 4 — what a workbook was understood to mean.
///
/// Plain data. Recognition produces a plan and constructs nothing, for two
/// reasons: a plan can be diffed, reviewed and tested before anything is built
/// from it, and building can fail in ways recognition should not — an unknown
/// account, a unit conflict — which belong to materialization, where they can
/// throw.
public struct RecognizedModel: Sendable {

    /// The recovered timeline.
    public let periods: [Period]

    /// The accounts, supplied and derived.
    public let accounts: [RecognizedAccount]

    /// Balances that carry from one period into the next.
    public let rollforwards: [LagDecomposition.RecognizedRollforward]

    /// What was seen and not understood.
    ///
    /// A row here is **not** an account. It was read, its cells are named, and the
    /// reason is recorded — but nothing was invented to stand in for it.
    public let residue: [Residue]

    /// Creates a recognized model.
    ///
    /// - Parameters:
    ///   - periods: The timeline.
    ///   - accounts: The accounts understood.
    ///   - rollforwards: The carries between periods.
    ///   - residue: What was not understood.
    public init(
        periods: [Period],
        accounts: [RecognizedAccount],
        rollforwards: [LagDecomposition.RecognizedRollforward],
        residue: [Residue]
    ) {
        self.periods = periods
        self.accounts = accounts
        self.rollforwards = rollforwards
        self.residue = residue
    }
}

/// One account destined for a `ModelDefinition`, with the cells it came from.
public struct RecognizedAccount: Sendable, Equatable {

    /// The account's name.
    public let name: String

    /// The formula, in `FormulaEvaluator` grammar, or `nil` when supplied.
    ///
    /// Exactly one of ``formula`` and ``values`` is present. An account is either
    /// data the model is given or a rule it computes; a thing that is both is a
    /// model that disagrees with itself, and `ModelDefinition` refuses it.
    public let formula: String?

    /// The formula as a tree, when this account has one.
    ///
    /// The same rule the formula string states, before it became text. A consumer
    /// that needs the shape — emitting typed Swift source, say — reads this rather
    /// than parsing the string back, which is recovering by inference something
    /// the recognizer knew for certain.
    public let expression: RecognizedExpression?

    /// The literal values, when this account is supplied.
    public let values: [Period: Double]?

    /// The inferred unit.
    ///
    /// Always `nil` for now. Unit inference is Phase 5, and `nil` states honestly
    /// that nothing was inferred rather than implying a default.
    public let unit: UnitKind?

    /// Every cell that contributed. **Never empty** — an account that cannot say
    /// where it came from cannot be checked against the sheet.
    public let provenance: [CellRef]

    /// Creates a recognized account.
    ///
    /// - Parameters:
    ///   - name: The account's name.
    ///   - formula: The formula, when derived.
    ///   - expression: The same formula as a tree, when the caller has one.
    ///   - values: The literals, when supplied.
    ///   - unit: The inferred unit, if any.
    ///   - provenance: The cells it came from.
    public init(
        name: String,
        formula: String? = nil,
        expression: RecognizedExpression? = nil,
        values: [Period: Double]? = nil,
        unit: UnitKind? = nil,
        provenance: [CellRef]
    ) {
        self.name = name
        self.formula = formula
        self.expression = expression
        self.values = values
        self.unit = unit
        self.provenance = provenance
    }

    /// Creates a derived account from its expression.
    ///
    /// The formula string is rendered from the tree, so the two cannot disagree.
    ///
    /// - Parameters:
    ///   - name: The account name.
    ///   - expression: The rule.
    ///   - unit: The unit its cells stated, if any.
    ///   - provenance: The cells it was read from.
    public init(
        name: String,
        expression: RecognizedExpression,
        unit: UnitKind? = nil,
        provenance: [CellRef]
    ) {
        self.name = name
        self.formula = expression.rendered()
        self.expression = expression
        self.values = nil
        self.unit = unit
        self.provenance = provenance
    }
}

/// The kind of quantity an account holds.
///
/// Inference is Phase 5; the vocabulary is defined here so the shape of a
/// recognized account does not change when it arrives.
public enum UnitKind: String, Sendable, Equatable, CaseIterable {

    /// An amount of money.
    case money

    /// A rate per period, such as an interest rate.
    case rate

    /// A dimensionless proportion, such as a margin.
    case ratio

    /// A count of periods.
    case duration
}

/// Something read from the sheet and not understood.
public struct Residue: Sendable, Equatable {

    /// The label the row carried, or its address when unlabelled.
    public let label: String

    /// The cells it occupied, so it can be found again.
    public let cells: [CellRef]

    /// Why it was not translated.
    public let reason: DiagnosticCode

    /// Creates a residue entry.
    ///
    /// - Parameters:
    ///   - label: The row's label or address.
    ///   - cells: The cells it occupied.
    ///   - reason: Why it was not translated.
    public init(label: String, cells: [CellRef], reason: DiagnosticCode) {
        self.label = label
        self.cells = cells
        self.reason = reason
    }
}

/// What recognition produced, and what it could not.
public struct RecognitionResult: Sendable {

    /// The plan.
    public let model: RecognizedModel

    /// Everything recognition could not do, and why.
    public let diagnostics: [Diagnostic]

    /// How much of the sheet was accounted for.
    public let coverage: Coverage

    /// Creates a recognition result.
    ///
    /// - Parameters:
    ///   - model: The plan.
    ///   - diagnostics: What could not be done.
    ///   - coverage: How much was accounted for.
    public init(model: RecognizedModel, diagnostics: [Diagnostic], coverage: Coverage) {
        self.model = model
        self.diagnostics = diagnostics
        self.coverage = coverage
    }
}
