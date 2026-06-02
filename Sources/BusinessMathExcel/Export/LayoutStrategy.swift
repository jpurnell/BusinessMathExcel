import SwiftXLSX

/// The result of laying out an ``ExcelModel`` onto a worksheet grid.
public struct CellAssignment: Sendable {

    /// Maps each node to its value cell position.
    public let mapping: [NodeRef: CellRef]

    /// Maps each node to its label cell position.
    public let labelMapping: [NodeRef: CellRef]

    /// The row where each section header is placed, keyed by section name.
    public let sectionRows: [String: Int]

    /// The first unused row after all content.
    public let lastRow: Int
}

/// Assigns cell positions to nodes in an ``ExcelModel``.
///
/// Conforming types determine where labels and values appear on the worksheet grid.
/// Cell positions are consumed by ``ModelExporter`` to write formulas and values.
public protocol LayoutStrategy: Sendable {

    /// Computes cell positions for all nodes in the model.
    ///
    /// - Parameter model: The model to lay out.
    /// - Returns: A ``CellAssignment`` with all node positions.
    func assign(_ model: ExcelModel) -> CellAssignment
}
