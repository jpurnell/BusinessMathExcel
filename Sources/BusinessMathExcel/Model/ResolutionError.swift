/// Errors that occur when resolving a ``NodeFormula`` to a `FormulaAST`.
public enum ResolutionError: Error, Sendable, Equatable {

    /// A formula references a node that has no cell assignment in the mapping.
    case danglingReference(NodeRef)
}
