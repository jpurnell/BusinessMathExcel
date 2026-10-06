import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct VerticalLayoutStrategyTests {

    @Test func emptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.mapping.isEmpty)
        #expect(assignment.labelMapping.isEmpty)
        #expect(assignment.sectionRows.isEmpty)
    }

    @Test func nodesMapToValueColumn() throws {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let cell = try #require(assignment.mapping[ref])
        #expect(cell.column == 4)
    }

    @Test func nodesMapToLabelColumn() throws {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let label = try #require(assignment.labelMapping[ref])
        #expect(label.column == 3)
    }

    @Test func labelAndValueShareSameRow() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let labelRow = assignment.labelMapping[ref]?.row
        let valueRow = assignment.mapping[ref]?.row
        #expect(labelRow == valueRow)
    }

    @Test func sectionHeaderRow() throws {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let headerRow = try #require(assignment.sectionRows["Inputs"])
        #expect(headerRow == 3)
    }

    @Test func multipleSectionsMaintainOrder() throws {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addFormula(label: "Monthly", formula: .number(0.004167))
        model.addOutput(label: "Result", formula: .number(100))

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputsRow = try #require(assignment.sectionRows["Inputs"])
        let calcsRow = try #require(assignment.sectionRows["Calculations"])
        let resultsRow = try #require(assignment.sectionRows["Results"])

        #expect(inputsRow < calcsRow)
        #expect(calcsRow < resultsRow)
    }

    @Test func blankRowBetweenSections() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputHeader = try #require(assignment.sectionRows["Inputs"])
        let inputDataRowNode = try #require(model.node(named: "A"))
        let inputDataRow = try #require(assignment.mapping[inputDataRowNode]).row
        let calcHeader = try #require(assignment.sectionRows["Calculations"])

        #expect(inputDataRow == (inputHeader + 1))
        #expect(calcHeader == (inputDataRow + 2))
    }

    @Test func customColumns() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = VerticalLayoutStrategy(labelColumn: 1, valueColumn: 2)
        let assignment = strategy.assign(model)

        #expect(assignment.labelMapping[ref]?.column == 1)
        #expect(assignment.mapping[ref]?.column == 2)
    }

    @Test func titleRowReserved() throws {
        let model = ExcelModel()
        model.addInput(label: "X", value: 1)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let firstSectionRow = try #require(assignment.sectionRows.values.min())
        #expect(firstSectionRow >= 3)
    }

    @Test func allRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let withoutValueCell = model.allRefs.filter { assignment.mapping[$0] == nil }.map(\.label)
        let withoutLabelCell = model.allRefs.filter { assignment.labelMapping[$0] == nil }.map(\.label)
        #expect(withoutValueCell == [], "Missing mapping")
        #expect(withoutLabelCell == [], "Missing label mapping")
    }

    // MARK: - Table Awareness (opt-in)

    @Test func tableAwareDefaultsToFalse() throws {
        let strategy = VerticalLayoutStrategy()
        let model = makeTableModel()
        let assignment = strategy.assign(model)

        #expect(assignment.tableColumnHeaders.isEmpty, "Default strategy should not produce table column headers")

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        let unlabelled = try tableNodeLabels.filter { label in
            assignment.labelMapping[try #require(model.node(named: label))] == nil
        }
        #expect(unlabelled == [], "Non-table-aware should give every node a label mapping")
    }

    @Test func tableAwarePopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        #expect(!assignment.tableColumnHeaders.isEmpty)
        #expect(Array(assignment.tableColumnHeaders.keys) == ["Schedule"])
        #expect(assignment.tableColumnHeaders["Schedule"]?.count == 2)
    }

    @Test func tableAwareBodyNodesOmittedFromLabelMapping() throws {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = try #require(model.node(named: label))
            #expect(assignment.labelMapping[ref] == nil, "Table body node '\(label)' should not be in labelMapping")
        }
    }

    @Test func tableAwareBodyNodesInMapping() throws {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        let unmapped = try tableNodeLabels.filter { label in
            assignment.mapping[try #require(model.node(named: label))] == nil
        }
        #expect(unmapped == [], "Table body nodes should be in mapping")
    }

    @Test func tableAwareNonTableSectionsUnaffected() throws {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let rate = try #require(model.node(named: "Rate"))
        let rateLabel = try #require(assignment.labelMapping[rate])
        let rateValue = try #require(assignment.mapping[rate])
        #expect(rateLabel.row == rateValue.row, "a node's label sits on the row of its value")
        #expect(rateLabel.column < rateValue.column, "and to the left of it")

        let total = try #require(model.node(named: "Total"))
        let totalLabel = try #require(assignment.labelMapping[total])
        let totalValue = try #require(assignment.mapping[total])
        #expect(totalLabel.row == totalValue.row, "a node's label sits on the row of its value")
        #expect(totalLabel.column < totalValue.column, "and to the left of it")
    }

    @Test func tableAwareNoCellCollisions() {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    @Test func tableAwareIntegrationWithModelExporter() throws {
        let model = AmortizationModelBuilder.build(
            principal: 100_000,
            annualRate: 0.06,
            termMonths: 3
        )

        let strategy = VerticalLayoutStrategy(tableAware: true)
        let wb = try ModelExporter.export(model, layout: strategy)

        #expect(wb.sheets.count == 1)
    }

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
}
