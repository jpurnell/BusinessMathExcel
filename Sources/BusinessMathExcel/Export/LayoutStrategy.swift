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

    /// Column header positions for registered tables, keyed by table label.
    ///
    /// Layout strategies that support table-aware rendering populate this field
    /// with one ``CellRef`` per column header. Strategies that do not support
    /// tables leave it empty.
    public let tableColumnHeaders: [String: [CellRef]]

    /// Creates a cell assignment.
    ///
    /// - Parameters:
    ///   - mapping: Node-to-value-cell positions.
    ///   - labelMapping: Node-to-label-cell positions.
    ///   - sectionRows: Section header row positions.
    ///   - lastRow: First unused row after all content.
    ///   - tableColumnHeaders: Column header positions for tables. Defaults to empty.
    public init(
        mapping: [NodeRef: CellRef],
        labelMapping: [NodeRef: CellRef],
        sectionRows: [String: Int],
        lastRow: Int,
        tableColumnHeaders: [String: [CellRef]] = [:]
    ) {
        self.mapping = mapping
        self.labelMapping = labelMapping
        self.sectionRows = sectionRows
        self.lastRow = lastRow
        self.tableColumnHeaders = tableColumnHeaders
    }
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
