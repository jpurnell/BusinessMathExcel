import Foundation

/// A recognized formula, before it becomes text.
///
/// ## Why the tree is kept
///
/// Rendering to a string is lossy in a way that is easy to miss, because the
/// string looks complete: `([Revenue] * [Margin])` reads perfectly and carries no
/// indication of where one operand ends. Anything downstream that needs the shape
/// back — a source writer emitting `revenue.expr * margin.expr`, a renamer, a
/// dependency view — has to recover by parsing what we ourselves just wrote.
///
/// That has come up three times in this project already: units were lost when
/// `Expr` rendered to a string upstream and had to be carried alongside; named
/// ranges were parsed by the reader and discarded before any caller could reach
/// them; and `FormulaEvaluator.Node` is internal, so a formula cannot be parsed
/// back here even in principle. Writing a parser for our own output would be a
/// fourth instance of recovering by inference something known for certain a moment
/// earlier.
///
/// So ``LagDecomposition`` builds this, and the formula string is **rendered from
/// it** rather than built alongside it. There is one source of truth, and the two
/// cannot drift.
public indirect enum RecognizedExpression: Sendable, Equatable {

    /// A reference to a named account, unquoted.
    ///
    /// The raw name, not the bracketed form. Quoting is a property of the grammar
    /// the formula is rendered into, and a consumer emitting Swift wants the name
    /// as the sheet gave it.
    case account(String)

    /// A numeric literal.
    case number(Double)

    /// A binary operation.
    case binary(Operator, RecognizedExpression, RecognizedExpression)

    /// Arithmetic negation.
    case negated(RecognizedExpression)

    /// A call to a registered function.
    ///
    /// A ``list(_:)`` argument flattens into the argument list when rendered, which
    /// is how a cell range reaches `SUM` as several arguments rather than one.
    case call(String, [RecognizedExpression])

    /// Several expressions in sequence, as a cell range expands to.
    case list([RecognizedExpression])

    /// A construct the translator refused.
    ///
    /// Rendered as `0`, which is a placeholder standing where a formula would have
    /// been — the account carrying it goes to residue, so the zero is never
    /// evaluated. It is not a claim that the cell holds nothing.
    case refused

    /// The operators the formula grammar reads.
    public enum Operator: String, Sendable, Equatable, CaseIterable {

        /// Addition.
        case add = "+"

        /// Subtraction.
        case subtract = "-"

        /// Multiplication.
        case multiply = "*"

        /// Division.
        case divide = "/"

        /// Equality.
        case equal = "="

        /// Inequality.
        case notEqual = "<>"

        /// Greater than.
        case greaterThan = ">"

        /// Less than.
        case lessThan = "<"

        /// Greater than or equal to.
        case greaterOrEqual = ">="

        /// Less than or equal to.
        case lessOrEqual = "<="

        /// Whether this operator compares rather than computes.
        ///
        /// A comparison yields a condition, which the typed layer has no unit for,
        /// so a consumer emitting typed source has to treat it differently.
        public var isComparison: Bool {
            switch self {
            case .add, .subtract, .multiply, .divide: return false
            case .equal, .notEqual, .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual:
                return true
            }
        }
    }

    /// Every account this expression reads, in the order it reads them.
    public var accounts: [String] {
        switch self {
        case .account(let name): return [name]
        case .number, .refused: return []
        case .binary(_, let lhs, let rhs): return lhs.accounts + rhs.accounts
        case .negated(let operand): return operand.accounts
        case .call(_, let arguments): return arguments.flatMap(\.accounts)
        case .list(let items): return items.flatMap(\.accounts)
        }
    }

    /// This expression with one account renamed.
    ///
    /// Renaming in the tree rather than in rendered text. A string replacement
    /// would also rewrite an account that merely *contains* the old name, and it
    /// cannot tell a reference from a coincidence inside a longer one.
    ///
    /// - Parameters:
    ///   - old: The name to replace.
    ///   - new: What to replace it with.
    /// - Returns: The expression, renamed.
    public func renaming(_ old: String, to new: String) -> RecognizedExpression {
        switch self {
        case .account(let name):
            return .account(name == old ? new : name)
        case .number, .refused:
            return self
        case .binary(let op, let lhs, let rhs):
            return .binary(op, lhs.renaming(old, to: new), rhs.renaming(old, to: new))
        case .negated(let operand):
            return .negated(operand.renaming(old, to: new))
        case .call(let name, let arguments):
            return .call(name, arguments.map { $0.renaming(old, to: new) })
        case .list(let items):
            return .list(items.map { $0.renaming(old, to: new) })
        }
    }

    /// The expression as a formula string, in `FormulaEvaluator` grammar.
    ///
    /// - Returns: The formula.
    public func rendered() -> String {
        switch self {
        case .account(let name):
            return Self.quoted(name)

        case .number(let value):
            return "\(value)"

        case .binary(let op, let lhs, let rhs):
            return "(\(lhs.rendered()) \(op.rawValue) \(rhs.rendered()))"

        case .negated(let operand):
            return "(-\(operand.rendered()))"

        case .call(let name, let arguments):
            // A list flattens into the argument list, which is how a range reaches
            // a function as several arguments rather than one.
            let flattened = arguments.flatMap { argument -> [RecognizedExpression] in
                if case .list(let items) = argument { return items }
                return [argument]
            }
            return "\(name)(\(flattened.map { $0.rendered() }.joined(separator: ", ")))"

        case .list(let items):
            return items.map { $0.rendered() }.joined(separator: ", ")

        case .refused:
            return "0"
        }
    }

    /// An account name as the grammar must receive it.
    ///
    /// A bare name is left bare; anything else is bracketed. The evaluator reads
    /// `&`, `/` and spaces as operators and separators, so `Sales & Marketing`
    /// reaches it as three tokens and `A/P` would silently become a division. The
    /// bracketed form is the grammar's own escape for exactly this.
    ///
    /// - Parameter name: The account name.
    /// - Returns: The name, bracketed if it needs to be.
    static func quoted(_ name: String) -> String {
        let isBare = !name.isEmpty
            && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            && !(name.first?.isNumber ?? true)
        return isBare ? name : "[\(name)]"
    }
}
