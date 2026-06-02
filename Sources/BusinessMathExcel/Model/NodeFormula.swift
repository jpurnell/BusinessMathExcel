import SwiftXLSX

/// A formula expression that references nodes by ``NodeRef`` instead of cell positions.
///
/// Mirrors `FormulaAST` but uses graph-level references. Call ``resolve(using:)``
/// to convert to a `FormulaAST` with concrete cell references at export time.
public indirect enum NodeFormula: Equatable, Hashable, Sendable {

    /// Reference to another node in the graph.
    case ref(NodeRef)

    /// A literal number.
    case number(Double)

    /// A literal string.
    case text(String)

    /// A literal boolean.
    case bool(Bool)

    /// Addition of two expressions.
    case add(NodeFormula, NodeFormula)

    /// Subtraction of two expressions.
    case subtract(NodeFormula, NodeFormula)

    /// Multiplication of two expressions.
    case multiply(NodeFormula, NodeFormula)

    /// Division of two expressions.
    case divide(NodeFormula, NodeFormula)

    /// Negation of an expression.
    case negate(NodeFormula)

    /// A named function call with arguments.
    case function(String, [NodeFormula])

    /// Resolves this formula into a `FormulaAST` by replacing ``NodeRef`` references
    /// with concrete `CellRef` positions.
    ///
    /// - Parameter mapping: Maps each referenced node to its assigned cell position.
    /// - Returns: The resolved `FormulaAST`.
    /// - Throws: ``ResolutionError/danglingReference(_:)`` if a referenced node has no mapping.
    public func resolve(using mapping: [NodeRef: CellRef]) throws -> FormulaAST {
        switch self {
        case .ref(let nodeRef):
            guard let cellRef = mapping[nodeRef] else {
                throw ResolutionError.danglingReference(nodeRef)
            }
            return .cellRef(cellRef)

        case .number(let value):
            return .number(value)

        case .text(let value):
            return .text(value)

        case .bool(let value):
            return .bool(value)

        case .add(let lhs, let rhs):
            return try .add(lhs.resolve(using: mapping), rhs.resolve(using: mapping))

        case .subtract(let lhs, let rhs):
            return try .subtract(lhs.resolve(using: mapping), rhs.resolve(using: mapping))

        case .multiply(let lhs, let rhs):
            return try .multiply(lhs.resolve(using: mapping), rhs.resolve(using: mapping))

        case .divide(let lhs, let rhs):
            return try .divide(lhs.resolve(using: mapping), rhs.resolve(using: mapping))

        case .negate(let expr):
            return try .negate(expr.resolve(using: mapping))

        case .function(let name, let args):
            return try .function(name, args.map { try $0.resolve(using: mapping) })
        }
    }
}

// MARK: - Convenience Builders

extension NodeFormula {

    /// Creates a SUM function over the given arguments.
    ///
    /// - Parameter args: The values to sum.
    /// - Returns: A ``NodeFormula/function(_:_:)`` wrapping SUM.
    public static func sum(_ args: [NodeFormula]) -> NodeFormula {
        .function("SUM", args)
    }

    /// Creates a PMT function: `PMT(rate, nper, pv)`.
    ///
    /// - Parameters:
    ///   - rate: The interest rate per period.
    ///   - nper: The total number of payment periods.
    ///   - pv: The present value (loan principal).
    /// - Returns: A ``NodeFormula/function(_:_:)`` wrapping PMT.
    public static func pmt(rate: NodeFormula, nper: NodeFormula, pv: NodeFormula) -> NodeFormula {
        .function("PMT", [rate, nper, pv])
    }

    /// Creates an IPMT function: `IPMT(rate, per, nper, pv)`.
    ///
    /// - Parameters:
    ///   - rate: The interest rate per period.
    ///   - per: The period for which to find the interest.
    ///   - nper: The total number of payment periods.
    ///   - pv: The present value.
    /// - Returns: A ``NodeFormula/function(_:_:)`` wrapping IPMT.
    public static func ipmt(
        rate: NodeFormula,
        per: NodeFormula,
        nper: NodeFormula,
        pv: NodeFormula
    ) -> NodeFormula {
        .function("IPMT", [rate, per, nper, pv])
    }

    /// Creates a PPMT function: `PPMT(rate, per, nper, pv)`.
    ///
    /// - Parameters:
    ///   - rate: The interest rate per period.
    ///   - per: The period for which to find the principal.
    ///   - nper: The total number of payment periods.
    ///   - pv: The present value.
    /// - Returns: A ``NodeFormula/function(_:_:)`` wrapping PPMT.
    public static func ppmt(
        rate: NodeFormula,
        per: NodeFormula,
        nper: NodeFormula,
        pv: NodeFormula
    ) -> NodeFormula {
        .function("PPMT", [rate, per, nper, pv])
    }

    /// Creates an NPV function: `NPV(rate, value1, value2, ...)`.
    ///
    /// - Parameters:
    ///   - rate: The discount rate per period.
    ///   - values: The series of cash flows.
    /// - Returns: A ``NodeFormula/function(_:_:)`` wrapping NPV.
    public static func npv(rate: NodeFormula, values: [NodeFormula]) -> NodeFormula {
        .function("NPV", [rate] + values)
    }

    /// Creates an IRR function: `IRR(values)`.
    ///
    /// - Parameter values: The series of cash flows.
    /// - Returns: A ``NodeFormula/function(_:_:)`` wrapping IRR.
    public static func irr(_ values: [NodeFormula]) -> NodeFormula {
        .function("IRR", values)
    }
}
