import SwiftXLSX

/// Lays out an ``ExcelModel`` with sections arranged side-by-side.
///
/// Each section occupies a column pair (label + value). Nodes within each section
/// stack vertically. Sections flow left-to-right, separated by ``sectionGap``
/// blank columns.
///
/// ## Layout
///
/// ```
/// Row 1: Title
/// Row 2: Blank
/// Row 3+:
///   Col C  Col D    Col F  Col G    Col I  Col J
///   Inputs           Calcs          Results
///   Price    100     Monthly  ▪     Total    ▪
///   Rate    0.06     Payment  ▪     Interest ▪
///   Term     360
/// ```
public struct HorizontalLayoutStrategy: LayoutStrategy, Sendable {

    /// The 1-based column for the first section's labels.
    public let startColumn: Int

    /// Blank columns between adjacent sections.
    public let sectionGap: Int

    /// The 1-based row where section headers begin (after title).
    public let startRow: Int

    /// Creates a horizontal layout strategy.
    ///
    /// - Parameters:
    ///   - startColumn: Column for the first section's labels. Defaults to 3 (column C).
    ///   - sectionGap: Blank columns between sections. Defaults to 1.
    ///   - startRow: Row where section content begins. Defaults to 3.
    public init(startColumn: Int = 3, sectionGap: Int = 1, startRow: Int = 3) {
        self.startColumn = startColumn
        self.sectionGap = sectionGap
        self.startRow = startRow
    }

    /// Assigns cell positions to all nodes in the model.
    ///
    /// Sections are placed left-to-right. Each section gets a label column
    /// and a value column. Nodes within a section stack vertically.
    ///
    /// - Parameter model: The model to lay out.
    /// - Returns: Cell positions for every node.
    public func assign(_ model: ExcelModel) -> CellAssignment {
        var mapping: [NodeRef: CellRef] = [:]
        var labelMapping: [NodeRef: CellRef] = [:]
        var sectionRows: [String: Int] = [:]
        var tableColumnHeaders: [String: [CellRef]] = [:]

        var currentColumn = startColumn
        var maxRow = startRow

        for section in model.sections {
            let labelCol = currentColumn

            sectionRows[section.name] = startRow
            var row = startRow + 1

            if let table = model.table(named: section.name) {
                let colCount = table.columns.count
                var headerCells: [CellRef] = []
                for colIndex in 0..<colCount {
                    headerCells.append(CellRef(column: labelCol + colIndex, row: row))
                }
                tableColumnHeaders[table.label] = headerCells
                row += 1

                for tableRow in table.rows {
                    for (colIndex, ref) in tableRow.enumerated() {
                        mapping[ref] = CellRef(column: labelCol + colIndex, row: row)
                    }
                    row += 1
                }

                if row > maxRow { maxRow = row }
                currentColumn = labelCol + colCount + sectionGap
            } else {
                let valueCol = labelCol + 1

                for ref in section.refs {
                    labelMapping[ref] = CellRef(column: labelCol, row: row)
                    mapping[ref] = CellRef(column: valueCol, row: row)
                    row += 1
                }

                if row > maxRow { maxRow = row }
                currentColumn = valueCol + 1 + sectionGap
            }
        }

        return CellAssignment(
            mapping: mapping,
            labelMapping: labelMapping,
            sectionRows: sectionRows,
            lastRow: maxRow,
            tableColumnHeaders: tableColumnHeaders
        )
    }
}
