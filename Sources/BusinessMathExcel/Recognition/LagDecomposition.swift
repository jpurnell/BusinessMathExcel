import BusinessMath
import SwiftXLSX

/// Stage 3 — splitting a formula by how far back along the timeline it reaches.
///
/// A `ModelDefinition` formula is period-local: it reads accounts in the period
/// being evaluated and never another. A spreadsheet formula routinely reaches one
/// column left, for last year's closing balance. Those two facts are reconciled
/// here rather than by widening the grammar.
///
/// The reach is **mechanical**, not inferred: a reference's lag is its offset
/// along the period axis from the cell being defined, and the grid knows where
/// every cell sits. That is what makes this a translation rather than a guess.
///
/// | Reach | Meaning |
/// |---|---|
/// | 0 | Same period. Stays in the formula, read by account name |
/// | 1 | Last period. Becomes a ``Rollforward``; the formula reads the opening account |
/// | Off the axis | Not a period at all. A scalar input, constant across the timeline |
/// | 2 or more, or forward | Refused — ``DiagnosticCode/unsupportedLag`` |
///
/// A reach of two cannot be expressed as a rollforward, which carries exactly one
/// period. Treating it as a reach of one would produce a model that runs, and is
/// wrong by a year. Refusing is the only honest answer.
public enum LagDecomposition {

    /// One cell's formula, split into what stays and what carries.
    public struct Split: Sendable {

        /// The period-local formula, in `FormulaEvaluator` grammar, with cell
        /// references replaced by account names.
        public let formula: String

        /// The carries this formula needs, one per reference reaching back.
        public let rollforwards: [RecognizedRollforward]

        /// What could not be translated.
        public let diagnostics: [Diagnostic]
    }

    /// A carry the recognizer inferred, before it becomes a `Rollforward`.
    ///
    /// Named separately from BusinessMath's `Rollforward` because recognition
    /// produces a plan and never constructs anything — the seed is not known until
    /// materialization reads the first period's cell.
    public struct RecognizedRollforward: Sendable, Equatable, Hashable {

        /// The account the formula reads for the prior period's value.
        public let opening: String

        /// The account whose value is carried forward.
        public let closing: String

        /// The cell the opening value is seeded from.
        public let seedCell: CellRef

        /// Creates a recognized carry.
        ///
        /// - Parameters:
        ///   - opening: The account receiving the prior period's value.
        ///   - closing: The account carried forward.
        ///   - seedCell: The cell holding the first period's opening value.
        public init(opening: String, closing: String, seedCell: CellRef) {
            self.opening = opening
            self.closing = closing
            self.seedCell = seedCell
        }
    }

    // MARK: - Decomposing

    /// Splits one cell's formula by reach.
    ///
    /// - Parameters:
    ///   - cell: The cell being defined.
    ///   - grid: The sheet's topology.
    ///   - axis: The recovered timeline.
    /// - Returns: The split, or `nil` when the cell holds no formula.
    public static func decompose(
        cell: CellRef,
        in grid: SheetGrid,
        axis: PeriodAxis
    ) -> Split? {
        guard let ast = grid.formulaASTs[cell] else { return nil }

        var rollforwards: [RecognizedRollforward] = []
        var diagnostics: [Diagnostic] = []
        let formula = rewrite(
            ast,
            definedAt: cell,
            grid: grid,
            axis: axis,
            rollforwards: &rollforwards,
            diagnostics: &diagnostics
        )

        return Split(
            formula: formula,
            rollforwards: rollforwards,
            diagnostics: diagnostics
        )
    }

    // MARK: - Private

    /// Rewrites a formula's references by name, recording the carries it needs.
    private static func rewrite(
        _ ast: FormulaAST,
        definedAt cell: CellRef,
        grid: SheetGrid,
        axis: PeriodAxis,
        rollforwards: inout [RecognizedRollforward],
        diagnostics: inout [Diagnostic]
    ) -> String {
        func each(_ operands: FormulaAST...) -> [String] {
            operands.map {
                rewrite(
                    $0, definedAt: cell, grid: grid, axis: axis,
                    rollforwards: &rollforwards, diagnostics: &diagnostics)
            }
        }

        switch ast {
        case .cellRef(let reference):
            return name(
                of: reference, definedAt: cell, grid: grid, axis: axis,
                rollforwards: &rollforwards, diagnostics: &diagnostics)

        case .number(let value):
            return "\(value)"

        case .text(let value):
            return quoted(value)

        case .bool(let value):
            return value ? "1" : "0"

        case .add(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) + \(parts[1]))"

        case .subtract(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) - \(parts[1]))"

        case .multiply(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) * \(parts[1]))"

        case .divide(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) / \(parts[1]))"

        case .negate(let expr):
            return "(-\(each(expr)[0]))"

        case .power(let lhs, let rhs):
            // No exponent operator in the grammar, and no `POWER` registered
            // upstream, so this is a gap rather than a translation.
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .unregisteredFunction, cell: cell,
                    message: "\(cell.reference) raises to a power, which the formula grammar "
                        + "has no operator for"))
            _ = each(lhs, rhs)
            return "0"

        case .greaterThan(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) > \(parts[1]))"

        case .lessThan(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) < \(parts[1]))"

        case .greaterOrEqual(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) >= \(parts[1]))"

        case .lessOrEqual(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) <= \(parts[1]))"

        case .equal(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) = \(parts[1]))"

        case .notEqual(let lhs, let rhs):
            let parts = each(lhs, rhs)
            return "(\(parts[0]) <> \(parts[1]))"

        case .function(let name, let arguments):
            let upper = name.uppercased()
            let rendered = arguments.map {
                rewrite(
                    $0, definedAt: cell, grid: grid, axis: axis,
                    rollforwards: &rollforwards, diagnostics: &diagnostics)
            }
            // Checked against the shipped registry rather than a list copied into
            // this file, so a name registered or withdrawn upstream moves this with
            // it instead of leaving the two to drift.
            guard FormulaEvaluator<Double>.Function(rawValue: upper) != nil else {
                diagnostics.append(
                    Diagnostic(
                        severity: .error, code: .unregisteredFunction, cell: cell,
                        message: "\(cell.reference) calls '\(upper)', which the formula "
                            + "evaluator has no entry for; the cell goes to residue and its "
                            + "cached value is not used in its place"))
                return "0"
            }
            return "\(upper)(\(rendered.joined(separator: ", ")))"

        case .cellRange, .sheetRef, .namedRange, .error, .concatenate:
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .unsupportedFormulaNode, cell: cell,
                    message: "\(cell.reference) uses a construct the translator cannot express"))
            return "0"
        }
    }

    /// Records a carry and returns the opening account to read in its place.
    ///
    /// - Parameters:
    ///   - account: The account being carried.
    ///   - reference: The cell the prior value sits in, which seeds the first period.
    ///   - rollforwards: The carries collected so far.
    /// - Returns: The opening account's name.
    private static func carry(
        to account: String,
        seededFrom reference: CellRef,
        into rollforwards: inout [RecognizedRollforward]
    ) -> String {
        let opening = "\(account) Opening"
        let record = RecognizedRollforward(
            opening: opening, closing: account, seedCell: reference)
        if !rollforwards.contains(record) { rollforwards.append(record) }
        return opening
    }

    /// An account name as the grammar must receive it.
    ///
    /// A bare name is left bare; anything else is bracketed. The evaluator reads
    /// `&`, `/` and spaces as operators and separators, so `Sales & Marketing`
    /// reaches it as three tokens and fails — and `A/P` would silently become a
    /// division. The bracketed form is the grammar's own escape for exactly this.
    ///
    /// - Parameter name: The account name.
    /// - Returns: The name, bracketed if it needs to be.
    private static func quoted(_ name: String) -> String {
        let isBare = !name.isEmpty
            && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            && !(name.first?.isNumber ?? true)
        return isBare ? name : "[\(name)]"
    }

    /// The account name a reference resolves to, recording a carry when it reaches
    /// back one period.
    private static func name(
        of reference: CellRef,
        definedAt cell: CellRef,
        grid: SheetGrid,
        axis: PeriodAxis,
        rollforwards: inout [RecognizedRollforward],
        diagnostics: inout [Diagnostic]
    ) -> String {
        let account = accountName(for: reference, in: grid, axis: axis)

        guard let orientation = grid.orientation else { return quoted(account) }
        let positions = Set(
            axis.sources.map { orientation == .periodsAcrossColumns ? $0.column : $0.row })

        let here = orientation == .periodsAcrossColumns ? cell.column : cell.row
        let there = orientation == .periodsAcrossColumns ? reference.column : reference.row

        // A pinned reference names the same cell from every period, so it is an
        // assumption rather than anything to do with time. The sheet says which is
        // which: `E50 = D52` fills across and therefore means *last period*, while
        // `$D$8` does not move and therefore means *this rate*. Reading the `$` is
        // the difference between a rollforward and a constant, and getting it wrong
        // turns an interest rate into a balance that carries.
        let pinned = orientation == .periodsAcrossColumns
            ? reference.absoluteColumn
            : reference.absoluteRow
        guard !pinned else { return quoted(account) }

        // The at-close column is the period before the first one. A first-period
        // formula reaching into it is a carry whose seed sits there — which is
        // what the column is for. Without this it reads as an off-axis scalar,
        // and `Beginning = End` becomes a within-period circle the sheet does not
        // contain.
        if let anchor = axis.anchor,
           there == anchor.position,
           here == positions.min() {
            return quoted(carry(to: account, seededFrom: reference, into: &rollforwards))
        }

        // A reference off the period axis is a scalar: an assumption that holds
        // for every period rather than a value belonging to one.
        guard positions.contains(there), positions.contains(here) else {
            return quoted(account)
        }

        let lag = here - there
        switch lag {
        case 0:
            return quoted(account)

        case 1:
            return quoted(carry(to: account, seededFrom: reference, into: &rollforwards))

        default:
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .unsupportedLag, cell: cell,
                    message: "\(cell.reference) reaches \(lag) periods "
                        + "\(lag < 0 ? "forward" : "back") to \(reference.reference); a "
                        + "rollforward carries exactly one period, and treating this as one "
                        + "would produce a model that runs and is wrong by \(abs(lag) - 1) "
                        + "period(s)"))
            return quoted(account)
        }
    }

    /// The account a cell belongs to: its row's label, or its address when unlabelled.
    private static func accountName(
        for reference: CellRef, in grid: SheetGrid, axis: PeriodAxis
    ) -> String {
        guard let orientation = grid.orientation else { return reference.reference }
        let line = orientation == .periodsAcrossColumns ? reference.row : reference.column
        let firstPeriod = axis.sources
            .map { orientation == .periodsAcrossColumns ? $0.column : $0.row }
            .min() ?? 0

        var best: (position: Int, text: String)?
        for (cellRef, kind) in grid.cells {
            let cellLine = orientation == .periodsAcrossColumns ? cellRef.row : cellRef.column
            let position = orientation == .periodsAcrossColumns ? cellRef.column : cellRef.row
            guard cellLine == line, position < firstPeriod else { continue }
            guard case .textInput(let text) = kind else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if best == nil || position > (best?.position ?? 0) {
                best = (position, trimmed)
            }
        }
        return best?.text ?? reference.reference
    }
}
