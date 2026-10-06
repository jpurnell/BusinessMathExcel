import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct TableAwareLayoutTests {

    // MARK: - Helpers

    private func makeTableModel() -> ExcelModel {
        let model = ExcelModel()

        model.addInput(label: "Rate", value: 0.05)

        let r0c0 = model.addInput(label: "P1", value: 1, section: "Schedule")
        let r0c1 = model.addInput(label: "Amt1", value: 500, section: "Schedule")
        let r1c0 = model.addInput(label: "P2", value: 2, section: "Schedule")
        let r1c1 = model.addInput(label: "Amt2", value: 500, section: "Schedule")
        model.registerTable(
            label: "Schedule",
            columns: ["Period", "Amount"],
            rows: [[r0c0, r0c1], [r1c0, r1c1]]
        )

        model.addOutput(label: "Total", formula: .number(1000))

        return model
    }

    // MARK: - HorizontalLayoutStrategy Table Awareness

    @Test func horizontalTableSectionPopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(!assignment.tableColumnHeaders.isEmpty, "Table column headers should be populated")
        #expect(Array(assignment.tableColumnHeaders.keys) == ["Schedule"])
        #expect(assignment.tableColumnHeaders["Schedule"]?.count == 2)
    }

    @Test func horizontalTableBodyNodesOmittedFromLabelMapping() throws {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = try #require(model.node(named: label))
            #expect(assignment.labelMapping[ref] == nil, "Table body node '\(label)' should not be in labelMapping")
        }
    }

    @Test func horizontalTableBodyNodesInMapping() throws {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        let unmapped = try tableNodeLabels.filter { label in
            assignment.mapping[try #require(model.node(named: label))] == nil
        }
        #expect(unmapped == [], "Table body nodes should be in mapping")
    }

    @Test func horizontalTableSpansCorrectColumns() throws {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy(startColumn: 3)
        let assignment = strategy.assign(model)

        let p1 = try #require(model.node(named: "P1"))
        let amt1 = try #require(model.node(named: "Amt1"))

        let p1Col = try #require(assignment.mapping[p1]?.column)
        let amt1Col = try #require(assignment.mapping[amt1]?.column)
        #expect(amt1Col == (p1Col + 1), "Table columns should be adjacent")
    }

    @Test func horizontalTableRowsStackVertically() throws {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let p1RowNode = try #require(model.node(named: "P1"))

        let p1Row = try #require(assignment.mapping[p1RowNode]).row
        let p2RowNode = try #require(model.node(named: "P2"))
        let p2Row = try #require(assignment.mapping[p2RowNode]).row
        #expect(p2Row == (p1Row + 1))
    }

    @Test func horizontalNonTableSectionsUnaffected() throws {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let rate = try #require(model.node(named: "Rate"))
        let rateLabel = try #require(assignment.labelMapping[rate], "Non-table node should have label mapping")
        let rateValue = try #require(assignment.mapping[rate], "Non-table node should have value mapping")
        #expect(rateLabel.row == rateValue.row, "a node's label sits on the row of its value")
        #expect(rateLabel.column < rateValue.column, "and to the left of it")
    }

    // MARK: - DashboardLayoutStrategy Table Awareness

    @Test func dashboardTableSectionPopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        #expect(Array(assignment.tableColumnHeaders.keys) == ["Schedule"])
        #expect(assignment.tableColumnHeaders["Schedule"]?.count == 2)
    }

    @Test func dashboardTableBodyNodesOmittedFromLabelMapping() throws {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = try #require(model.node(named: label))
            #expect(assignment.labelMapping[ref] == nil, "Table body node '\(label)' should not be in labelMapping")
        }
    }

    @Test func dashboardTableBodyNodesInMapping() throws {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        let unmapped = try tableNodeLabels.filter { label in
            assignment.mapping[try #require(model.node(named: label))] == nil
        }
        #expect(unmapped == [], "Table body nodes should be in mapping")
    }

    // MARK: - No Collisions with Mixed Content

    @Test func noCellCollisionsWithTables() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    @Test func dashboardNoCellCollisionsWithTables() {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    // MARK: - Integration: Amortization + Table-Aware Export

    @Test func amortizationWithHorizontalTableExport() throws {
        let model = AmortizationModelBuilder.build(
            principal: 100_000,
            annualRate: 0.06,
            termMonths: 3
        )

        let strategy = HorizontalLayoutStrategy()
        let wb = try ModelExporter.export(model, layout: strategy)
        let sheet = wb.sheets[0]

        #expect(wb.sheets.count == 1)
        #expect(sheet.name == "Model")
    }
}
