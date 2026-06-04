import SwiftXLSX

/// Lays out an ``ExcelModel`` in a grid of sections.
///
/// Sections are arranged left-to-right in rows of ``columnCount`` sections,
/// wrapping to new row-bands when the current band is full. Each section
/// gets a label column and a value column within its grid cell.
///
/// ## Layout (columnCount = 2)
///
/// ```
/// Row 1: Title
/// Row 2: Blank
///
///   ┌── Band 1 ──────────────────────────────┐
///   │  Col C  Col D      Col F  Col G        │
///   │  Inputs             Cash Flows          │
///   │  Principal  100000  CF0     -50000      │
///   │  Rate       0.06    CF1      15000      │
///   └─────────────────────────────────────────┘
///
///   ┌── Band 2 ──────────────────────────────┐
///   │  Col C  Col D      Col F  Col G        │
///   │  Calculations       Results             │
///   │  Monthly Rt  ▪      NPV     ▪          │
///   └─────────────────────────────────────────┘
/// ```
public struct DashboardLayoutStrategy: LayoutStrategy, Sendable {

    /// Number of sections per row-band.
    public let columnCount: Int

    /// The 1-based column where the grid starts.
    public let startColumn: Int

    /// Blank columns between sections in the same row-band.
    public let sectionGap: Int

    /// Blank rows between row-bands.
    public let bandGap: Int

    /// Creates a dashboard layout strategy.
    ///
    /// - Parameters:
    ///   - columnCount: Sections per row-band. Defaults to 2.
    ///   - startColumn: Column where the grid starts. Defaults to 3 (column C).
    ///   - sectionGap: Blank columns between sections. Defaults to 1.
    ///   - bandGap: Blank rows between bands. Defaults to 2.
    public init(
        columnCount: Int = 2,
        startColumn: Int = 3,
        sectionGap: Int = 1,
        bandGap: Int = 2
    ) {
        self.columnCount = max(1, columnCount)
        self.startColumn = startColumn
        self.sectionGap = sectionGap
        self.bandGap = bandGap
    }

    /// Assigns cell positions to all nodes in the model.
    ///
    /// Sections fill left-to-right in bands of ``columnCount``. Each band's
    /// height is determined by the tallest section in that band.
    ///
    /// - Parameter model: The model to lay out.
    /// - Returns: Cell positions for every node.
    public func assign(_ model: ExcelModel) -> CellAssignment {
        var mapping: [NodeRef: CellRef] = [:]
        var labelMapping: [NodeRef: CellRef] = [:]
        var sectionRows: [String: Int] = [:]
        var tableColumnHeaders: [String: [CellRef]] = [:]

        let sections = model.sections
        guard !sections.isEmpty else {
            return CellAssignment(
                mapping: [:],
                labelMapping: [:],
                sectionRows: [:],
                lastRow: startRow
            )
        }

        var bandStartRow = startRow
        var sectionIndex = 0

        while sectionIndex < sections.count {
            let bandEnd = min(sectionIndex + columnCount, sections.count)
            var bandMaxRow = bandStartRow

            for slotIndex in 0..<(bandEnd - sectionIndex) {
                let section = sections[sectionIndex + slotIndex]
                let labelCol = columnForSlot(slotIndex)

                sectionRows[section.name] = bandStartRow
                var row = bandStartRow + 1

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
                } else {
                    let valueCol = labelCol + 1

                    for ref in section.refs {
                        labelMapping[ref] = CellRef(column: labelCol, row: row)
                        mapping[ref] = CellRef(column: valueCol, row: row)
                        row += 1
                    }
                }

                if row > bandMaxRow {
                    bandMaxRow = row
                }
            }

            sectionIndex = bandEnd
            bandStartRow = bandMaxRow + bandGap
        }

        return CellAssignment(
            mapping: mapping,
            labelMapping: labelMapping,
            sectionRows: sectionRows,
            lastRow: bandStartRow,
            tableColumnHeaders: tableColumnHeaders
        )
    }

    // MARK: - Private

    private var startRow: Int { 3 }

    private func columnForSlot(_ slot: Int) -> Int {
        startColumn + slot * (2 + sectionGap)
    }
}
