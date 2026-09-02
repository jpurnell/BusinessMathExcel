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

        /// The account this formula actually defines, when it is not the one the
        /// row is labelled with.
        ///
        /// A row that grows off its own prior value — `D6 = C6 * 1.15` — reads in
        /// the sheet as *this period equals last period times 1.15*. The values
        /// printed in that row are therefore the **openings**: 1,000,000 then
        /// 1,150,000 then 1,322,500. What the formula computes is the *next*
        /// period's figure, which is a closing balance.
        ///
        /// So the row's own label stays on the carried series, where the sheet's
        /// numbers are, and the derived account takes a `Closing` suffix. Naming
        /// them the other way round produces a model that is correct and reports
        /// every figure one period early.
        public let definedAccount: String?

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

        /// The opening value for the first period, read from ``seedCell``.
        ///
        /// Resolved here rather than at materialization so the plan is
        /// self-contained: a builder that had to be handed the grid to finish
        /// reading the plan would not be working from a plan.
        public let seed: Double

        /// Creates a recognized carry.
        ///
        /// - Parameters:
        ///   - opening: The account receiving the prior period's value.
        ///   - closing: The account carried forward.
        ///   - seedCell: The cell holding the first period's opening value.
        ///   - seed: That cell's value.
        public init(opening: String, closing: String, seedCell: CellRef, seed: Double) {
            self.opening = opening
            self.closing = closing
            self.seedCell = seedCell
            self.seed = seed
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
        var definedAccount: String?
        let ownAccount = accountName(for: cell, in: grid, axis: axis)
        let formula = rewrite(
            ast,
            definedAt: cell,
            grid: grid,
            axis: axis,
            rollforwards: &rollforwards,
            diagnostics: &diagnostics
        )

        // A row growing off its own prior value keeps its label on the carried
        // series, because that is where the sheet's printed numbers are.
        if let selfCarry = rollforwards.first(where: { $0.closing == ownAccount }) {
            definedAccount = "\(ownAccount) Closing"
            rollforwards = rollforwards.map {
                $0 == selfCarry
                    ? RecognizedRollforward(
                        opening: ownAccount,
                        closing: "\(ownAccount) Closing",
                        seedCell: $0.seedCell,
                        seed: $0.seed)
                    : $0
            }
        }

        return Split(
            formula: definedAccount == nil
                ? formula
                : formula.replacingOccurrences(
                    of: quoted("\(ownAccount) Opening"), with: quoted(ownAccount)),
            definedAccount: definedAccount,
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

        case .cellRange(let range):
            return rewrite(range: range, definedAt: cell, grid: grid, axis: axis,
                           diagnostics: &diagnostics)

        case .namedRange(let alias):
            // A name is an alias for a cell, so it takes the cell's road: pinned
            // or filling across, on the axis or off it, all decided the same way.
            // Excel's own resolution is case-insensitive, and a model that writes
            // `Circ` in one formula and `circ` in the next means the same switch.
            guard let target = grid.namedCells.first(where: {
                $0.key.compare(alias, options: .caseInsensitive) == .orderedSame
            })?.value else {
                diagnostics.append(
                    Diagnostic(
                        severity: .error, code: .unsupportedFormulaNode, cell: cell,
                        message: "\(cell.reference) refers to the name '\(alias)', which this "
                            + "sheet does not define as a single cell on itself. It may point "
                            + "at another sheet, a range, or an expression; whichever it is, "
                            + "resolving it to a guess would build the model off the wrong "
                            + "number"))
                return "0"
            }
            return name(
                of: target, definedAt: cell, grid: grid, axis: axis,
                rollforwards: &rollforwards, diagnostics: &diagnostics)

        case .sheetRef, .error, .concatenate:
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .unsupportedFormulaNode, cell: cell,
                    message: "\(cell.reference) uses a construct the translator cannot express"))
            return "0"
        }
    }

    /// A cell range as a list of the accounts it covers.
    ///
    /// A range that stays within one period is a list of accounts read in that
    /// period: `SUM(E42:E46)` totals five rows of a cash-flow build, and every one
    /// of them is an account. There is no time in the construct at all, so it
    /// translates to `EBITDA, Less: Taxes, …` and the surrounding `SUM` needs
    /// nothing special — the grammar has been variadic since the function registry
    /// landed. Cells the range passes over that hold nothing are skipped, which is
    /// what Excel's own `SUM` does with a blank.
    ///
    /// A range running **along** the timeline is a different construct and is
    /// refused. `SUM(C2:E2)` totals one account across every period — an aggregate
    /// over time, not a period-local formula. Rendering it as `SUM(Revenue)` would
    /// read as this period's revenue and quietly drop five years, which is exactly
    /// the kind of answer that looks right.
    ///
    /// - Parameters:
    ///   - range: The range to translate.
    ///   - cell: The cell whose formula holds it, for diagnostics.
    ///   - grid: The sheet's topology.
    ///   - axis: The period axis.
    ///   - diagnostics: Findings collected so far.
    /// - Returns: The accounts, comma-separated, or `"0"` when refused.
    private static func rewrite(
        range: CellRange,
        definedAt cell: CellRef,
        grid: SheetGrid,
        axis: PeriodAxis,
        diagnostics: inout [Diagnostic]
    ) -> String {
        guard let orientation = grid.orientation else { return refuse(range, at: cell, &diagnostics) }
        let positions = Set(
            axis.sources.map { orientation == .periodsAcrossColumns ? $0.column : $0.row })

        let from = orientation == .periodsAcrossColumns ? range.start.column : range.start.row
        let to = orientation == .periodsAcrossColumns ? range.end.column : range.end.row
        guard from == to else {
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .unsupportedFormulaNode, cell: cell,
                    message: "\(cell.reference) reads \(range.start.reference):"
                        + "\(range.end.reference), which runs along the timeline rather than "
                        + "down one period. That is an aggregate over time, and translating "
                        + "it period-locally would silently drop every period but one"))
            return "0"
        }
        guard positions.contains(from) || axis.anchor?.position == from else {
            return refuse(range, at: cell, &diagnostics)
        }

        let lineFrom = orientation == .periodsAcrossColumns ? range.start.row : range.start.column
        let lineTo = orientation == .periodsAcrossColumns ? range.end.row : range.end.column
        let names = stride(from: min(lineFrom, lineTo), through: max(lineFrom, lineTo), by: 1)
            .map { line in
                orientation == .periodsAcrossColumns
                    ? CellRef(column: from, row: line)
                    : CellRef(column: line, row: from)
            }
            .filter { grid.cells[$0] != nil }
            .map { quoted(accountName(for: $0, in: grid, axis: axis)) }

        guard !names.isEmpty else { return refuse(range, at: cell, &diagnostics) }
        return names.joined(separator: ", ")
    }

    /// Reports a range the translator cannot place and yields a neutral rendering.
    private static func refuse(
        _ range: CellRange, at cell: CellRef, _ diagnostics: inout [Diagnostic]
    ) -> String {
        diagnostics.append(
            Diagnostic(
                severity: .error, code: .unsupportedFormulaNode, cell: cell,
                message: "\(cell.reference) reads \(range.start.reference):"
                    + "\(range.end.reference), which the translator cannot place on the "
                    + "period axis"))
        return "0"
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
        definedAt cell: CellRef,
        seededFrom reference: CellRef,
        in grid: SheetGrid,
        axis: PeriodAxis,
        into rollforwards: inout [RecognizedRollforward],
        diagnostics: inout [Diagnostic]
    ) -> String {
        let opening = "\(account) Opening"
        let seedCell = seedCell(forRowDefining: cell, in: grid, axis: axis) ?? reference
        guard let seed = seedValue(at: seedCell, in: grid) else {
            diagnostics.append(
                Diagnostic(
                    severity: .error, code: .unseededCarry, cell: cell,
                    message: "\(cell.reference) carries \(account) forward, but "
                        + "\(seedCell.reference) states no opening value for it — it is "
                        + "computed and the file cached no result. Seeding zero would give a "
                        + "model that runs and is wrong in every period"))
            return opening
        }
        let record = RecognizedRollforward(
            opening: opening, closing: account, seedCell: seedCell, seed: seed)
        if !rollforwards.contains(record) { rollforwards.append(record) }
        return opening
    }

    /// The cell holding the first-period value of the row that `cell` belongs to.
    ///
    /// A carry opens where the sheet says it opens, and the sheet says it in the
    /// row's **own** first period — not in the cell being referenced. For a row
    /// growing off itself, `D6 = C6 * 1.15`, these are the same cell and the
    /// distinction costs nothing. For a link to another row they are not:
    /// `D4 = C7` says opening debt follows last period's closing debt, but the
    /// opening balance is the hard number typed in `C4`, and `C7` is a formula
    /// that in period one has no prior period to compute from.
    ///
    /// - Parameters:
    ///   - cell: The cell whose formula carries.
    ///   - grid: The sheet's topology.
    ///   - axis: The period axis.
    /// - Returns: The row's first-period cell, or `nil` if the axis has no periods.
    private static func seedCell(
        forRowDefining cell: CellRef,
        in grid: SheetGrid,
        axis: PeriodAxis
    ) -> CellRef? {
        guard let orientation = grid.orientation else { return nil }
        let positions = axis.sources.map {
            orientation == .periodsAcrossColumns ? $0.column : $0.row
        }
        guard let first = positions.min() else { return nil }
        return orientation == .periodsAcrossColumns
            ? CellRef(column: first, row: cell.row)
            : CellRef(column: cell.column, row: first)
    }

    /// The value a seed cell holds.
    ///
    /// A literal is read directly; a computed cell is read from what the file
    /// recorded Excel producing for it. That is evidence about an opening balance,
    /// not a substitute for a formula: the cell's own rule still becomes an
    /// account, and this only supplies the period before the timeline begins,
    /// where by definition no rule of ours ran.
    ///
    /// - Parameters:
    ///   - reference: The seed cell.
    ///   - grid: The sheet's topology.
    /// - Returns: The value, or `nil` when the cell states none.
    private static func seedValue(at reference: CellRef, in grid: SheetGrid) -> Double? {
        if case .input(let literal)? = grid.cells[reference] { return literal }
        if case .number(let cached)? = grid.cachedValues[reference] { return cached }
        return nil
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
            return quoted(
                carry(
                    to: account, definedAt: cell, seededFrom: reference, in: grid,
                    axis: axis, into: &rollforwards, diagnostics: &diagnostics))
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
            return quoted(
                carry(
                    to: account, definedAt: cell, seededFrom: reference, in: grid,
                    axis: axis, into: &rollforwards, diagnostics: &diagnostics))

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
        // The nearest label before the cell itself, not before the first period.
        // A line can hold several tables side by side, and `H5` on the Wharton
        // ANSWER KEY belongs to the label in `F5`, not to the one in `B5` — naming
        // it for `B5` would build a model off a number from the wrong table.
        let here = orientation == .periodsAcrossColumns ? reference.column : reference.row

        var best: (position: Int, text: String)?
        for (cellRef, kind) in grid.cells {
            let cellLine = orientation == .periodsAcrossColumns ? cellRef.row : cellRef.column
            let position = orientation == .periodsAcrossColumns ? cellRef.column : cellRef.row
            guard cellLine == line, position < here else { continue }
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
