import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct LayoutFoundationTests {

    // MARK: - CellAssignment tableColumnHeaders

    @Test func cellAssignmentDefaultTableColumnHeadersIsEmpty() {
        let assignment = CellAssignment(
            mapping: [:],
            labelMapping: [:],
            sectionRows: [:],
            lastRow: 1
        )
        #expect(assignment.tableColumnHeaders.isEmpty)
    }

    @Test func cellAssignmentExplicitTableColumnHeaders() {
        let headers: [String: [CellRef]] = [
            "Schedule": [
                CellRef(column: 3, row: 5),
                CellRef(column: 4, row: 5),
                CellRef(column: 5, row: 5)
            ]
        ]
        let assignment = CellAssignment(
            mapping: [:],
            labelMapping: [:],
            sectionRows: [:],
            lastRow: 1,
            tableColumnHeaders: headers
        )
        #expect(assignment.tableColumnHeaders.count == 1)
        #expect(assignment.tableColumnHeaders["Schedule"]?.count == 3)
    }

    // MARK: - ExcelModel.allTables

    @Test func allTablesEmptyByDefault() {
        let model = ExcelModel()
        #expect(model.allTables.isEmpty)
    }

    @Test func allTablesReturnsRegisteredTables() {
        let model = ExcelModel()
        let r0 = model.addInput(label: "P1", value: 1, section: "Schedule")
        let r1 = model.addInput(label: "P2", value: 2, section: "Schedule")
        model.registerTable(label: "Schedule", columns: ["Period"], rows: [[r0], [r1]])

        #expect(model.allTables.count == 1)
        #expect(Array(model.allTables.keys) == ["Schedule"])
        #expect(model.allTables["Schedule"]?.columns == ["Period"])
        #expect(model.allTables["Schedule"]?.rowCount == 2)
    }

    @Test func allTablesReturnsMultipleTables() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1, section: "T1")
        let b = model.addInput(label: "B", value: 2, section: "T2")
        model.registerTable(label: "T1", columns: ["Col1"], rows: [[a]])
        model.registerTable(label: "T2", columns: ["Col2"], rows: [[b]])

        #expect(model.allTables.count == 2)
        #expect(Set(model.allTables.keys) == ["T1", "T2"])
    }

    // MARK: - ModelExporter writes table column headers

    @Test func exporterWritesTableColumnHeaders() throws {
        let model = ExcelModel()
        let r0c0 = model.addInput(label: "P1", value: 1, section: "Schedule")
        let r0c1 = model.addInput(label: "Amt1", value: 500, section: "Schedule")
        let r1c0 = model.addInput(label: "P2", value: 2, section: "Schedule")
        let r1c1 = model.addInput(label: "Amt2", value: 500, section: "Schedule")
        model.registerTable(
            label: "Schedule",
            columns: ["Period", "Amount"],
            rows: [[r0c0, r0c1], [r1c0, r1c1]]
        )

        let strategy = TableAwareVerticalLayoutStub(model: model)
        let wb = try ModelExporter.export(model, layout: strategy)
        let sheet = wb.sheets[0]

        #expect(sheet.cell(at: "C4") == .text("Period"))
        #expect(sheet.cell(at: "D4") == .text("Amount"))
    }

    // MARK: - Backward compatibility

    @Test func verticalLayoutStillProducesEmptyTableHeaders() {
        let model = ExcelModel()
        model.addInput(label: "X", value: 1)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.tableColumnHeaders.isEmpty)
    }
}

// MARK: - Test Stub

/// A stub layout strategy that produces table column headers for testing
/// the ModelExporter table-header-writing path.
private struct TableAwareVerticalLayoutStub: LayoutStrategy {
    let model: ExcelModel

    func assign(_ model: ExcelModel) -> CellAssignment {
        var mapping: [NodeRef: CellRef] = [:]
        var labelMapping: [NodeRef: CellRef] = [:]
        var sectionRows: [String: Int] = [:]
        var tableColumnHeaders: [String: [CellRef]] = [:]

        var row = 3

        for section in model.sections {
            sectionRows[section.name] = row
            row += 1

            if let table = model.table(named: section.name) {
                let headerRow = row
                var headerCells: [CellRef] = []
                for colIndex in 0..<table.columns.count {
                    headerCells.append(CellRef(column: 3 + colIndex, row: headerRow))
                }
                tableColumnHeaders[table.label] = headerCells
                row += 1

                for tableRow in table.rows {
                    for (colIndex, ref) in tableRow.enumerated() {
                        mapping[ref] = CellRef(column: 3 + colIndex, row: row)
                    }
                    row += 1
                }
            } else {
                for ref in section.refs {
                    labelMapping[ref] = CellRef(column: 3, row: row)
                    mapping[ref] = CellRef(column: 4, row: row)
                    row += 1
                }
            }

            row += 1
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
