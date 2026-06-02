import SwiftXLSX

/// Lays out an ``ExcelModel`` vertically: title row, then sections stacked
/// with labels in one column and values in the next.
///
/// Default layout uses a 2-column gutter (A–B), labels in column C,
/// and values in column D, matching `DesignBundle.default`.
public struct VerticalLayoutStrategy: LayoutStrategy, Sendable {

    /// The 1-based column index for node labels.
    public let labelColumn: Int

    /// The 1-based column index for node values and formulas.
    public let valueColumn: Int

    /// Creates a vertical layout strategy.
    ///
    /// - Parameters:
    ///   - labelColumn: Column for labels. Defaults to 3 (column C).
    ///   - valueColumn: Column for values. Defaults to 4 (column D).
    public init(labelColumn: Int = 3, valueColumn: Int = 4) {
        self.labelColumn = labelColumn
        self.valueColumn = valueColumn
    }

    /// Assigns cell positions to all nodes in the model.
    ///
    /// Layout:
    /// - Row 1: reserved for title
    /// - Row 2: blank separator
    /// - Then each section: header row, node rows, blank separator
    ///
    /// - Parameter model: The model to lay out.
    /// - Returns: Cell positions for every node.
    public func assign(_ model: ExcelModel) -> CellAssignment {
        var mapping: [NodeRef: CellRef] = [:]
        var labelMapping: [NodeRef: CellRef] = [:]
        var sectionRows: [String: Int] = [:]

        var row = 3

        for section in model.sections {
            sectionRows[section.name] = row
            row += 1

            for ref in section.refs {
                labelMapping[ref] = CellRef(column: labelColumn, row: row)
                mapping[ref] = CellRef(column: valueColumn, row: row)
                row += 1
            }

            row += 1
        }

        return CellAssignment(
            mapping: mapping,
            labelMapping: labelMapping,
            sectionRows: sectionRows,
            lastRow: row
        )
    }
}
