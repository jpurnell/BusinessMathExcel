import SwiftXLSX

/// Lays out an ``ExcelModel`` vertically with no blank separator rows between sections.
///
/// Identical to ``VerticalLayoutStrategy`` except sections flow directly from
/// one to the next, producing a denser worksheet. Table-aware: detects
/// registered ``TableRef`` and renders as grids with column headers.
///
/// ## Layout
///
/// ```
/// Row 1: Title
/// Row 2: Blank
/// Row 3: Inputs          (section header)
/// Row 4: Principal  100000
/// Row 5: Rate       0.06
/// Row 6: Calculations    (section header — no blank row)
/// Row 7: Monthly Rt  ▪
/// Row 8: Results         (section header — no blank row)
/// Row 9: NPV        ▪
/// ```
public struct CompactLayoutStrategy: LayoutStrategy, Sendable {

    /// The 1-based column index for node labels.
    public let labelColumn: Int

    /// The 1-based column index for node values and formulas.
    public let valueColumn: Int

    /// Creates a compact layout strategy.
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
    /// - Then each section: header row, node rows (no blank separator after)
    ///
    /// - Parameter model: The model to lay out.
    /// - Returns: Cell positions for every node.
    public func assign(_ model: ExcelModel) -> CellAssignment {
        var mapping: [NodeRef: CellRef] = [:]
        var labelMapping: [NodeRef: CellRef] = [:]
        var sectionRows: [String: Int] = [:]
        var tableColumnHeaders: [String: [CellRef]] = [:]

        var row = 3

        for section in model.sections {
            sectionRows[section.name] = row
            row += 1

            if let table = model.table(named: section.name) {
                let colCount = table.columns.count
                var headerCells: [CellRef] = []
                for colIndex in 0..<colCount {
                    headerCells.append(CellRef(column: labelColumn + colIndex, row: row))
                }
                tableColumnHeaders[table.label] = headerCells
                row += 1

                for tableRow in table.rows {
                    for (colIndex, ref) in tableRow.enumerated() {
                        mapping[ref] = CellRef(column: labelColumn + colIndex, row: row)
                    }
                    row += 1
                }
            } else {
                for ref in section.refs {
                    labelMapping[ref] = CellRef(column: labelColumn, row: row)
                    mapping[ref] = CellRef(column: valueColumn, row: row)
                    row += 1
                }
            }
        }

        return CellAssignment(
            mapping: mapping,
            labelMapping: labelMapping,
            sectionRows: sectionRows,
            lastRow: row,
            tableColumnHeaders: tableColumnHeaders
        )
    }
}
