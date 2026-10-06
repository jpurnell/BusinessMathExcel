import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct CompactLayoutStrategyTests {

    // MARK: - Empty Model

    @Test func emptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.mapping.isEmpty)
        #expect(assignment.labelMapping.isEmpty)
        #expect(assignment.sectionRows.isEmpty)
        #expect(assignment.tableColumnHeaders.isEmpty)
    }

    // MARK: - Single Section

    @Test func singleSectionPlacesLabelsAndValues() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.labelMapping[ref]?.column == 3)
        #expect(assignment.mapping[ref]?.column == 4)
        #expect(assignment.sectionRows["Inputs"] == 3)
        #expect(assignment.mapping[ref]?.row == 4)
    }

    // MARK: - Multi-Section: No Blank Separator Rows

    @Test func multiSectionNoBlankRows() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputHeader = try #require(assignment.sectionRows["Inputs"])
        let inputDataRowNode = try #require(model.node(named: "A"))
        let inputDataRow = try #require(assignment.mapping[inputDataRowNode]).row
        let calcHeader = try #require(assignment.sectionRows["Calculations"])

        #expect(inputHeader == 3)
        #expect(inputDataRow == 4)
        #expect(calcHeader == 5, "Next section header should immediately follow without blank row")
    }

    @Test func threeSectionsFlowWithoutGaps() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputsRow = try #require(assignment.sectionRows["Inputs"])
        let calcsRow = try #require(assignment.sectionRows["Calculations"])
        let resultsRow = try #require(assignment.sectionRows["Results"])

        // Inputs: header at 3, A at 4, B at 5
        // Calculations: header at 6, C at 7
        // Results: header at 8, D at 9
        #expect(inputsRow == 3)
        #expect(calcsRow == 6)
        #expect(resultsRow == 8)
    }

    // MARK: - Custom Columns

    @Test func customLabelAndValueColumns() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = CompactLayoutStrategy(labelColumn: 1, valueColumn: 2)
        let assignment = strategy.assign(model)

        #expect(assignment.labelMapping[ref]?.column == 1)
        #expect(assignment.mapping[ref]?.column == 2)
    }

    // MARK: - All Refs Assigned

    @Test func allRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let withoutValueCell = model.allRefs.filter { assignment.mapping[$0] == nil }.map(\.label)
        let withoutLabelCell = model.allRefs.filter { assignment.labelMapping[$0] == nil }.map(\.label)
        #expect(withoutValueCell == [], "Missing mapping")
        #expect(withoutLabelCell == [], "Missing label mapping")
    }

    // MARK: - No Cell Collisions

    @Test func noCellCollisions() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let allCells = valueCells + labelCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    // MARK: - Compact vs Vertical Comparison

    @Test func compactProducesFewerRowsThanVertical() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let compact = CompactLayoutStrategy()
        let vertical = VerticalLayoutStrategy()

        let compactAssignment = compact.assign(model)
        let verticalAssignment = vertical.assign(model)

        #expect(compactAssignment.lastRow < verticalAssignment.lastRow, "Compact should use fewer rows than vertical")
    }

    // MARK: - Table-Aware: Column Headers

    @Test func tableSectionPopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(!assignment.tableColumnHeaders.isEmpty)
        #expect(Array(assignment.tableColumnHeaders.keys) == ["Schedule"])
        #expect(assignment.tableColumnHeaders["Schedule"]?.count == 2)
    }

    // MARK: - Table-Aware: Body Nodes

    @Test func tableBodyNodesOmittedFromLabelMapping() throws {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = try #require(model.node(named: label))
            #expect(assignment.labelMapping[ref] == nil, "Table body node '\(label)' should not be in labelMapping")
        }
    }

    @Test func tableBodyNodesInMapping() throws {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        let unmapped = try tableNodeLabels.filter { label in
            assignment.mapping[try #require(model.node(named: label))] == nil
        }
        #expect(unmapped == [], "Table body nodes should be in mapping")
    }

    // MARK: - Table-Aware: Mixed Content

    @Test func mixedTableAndNonTableSections() throws {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let rate = try #require(model.node(named: "Rate"))
        let rateLabel = try #require(assignment.labelMapping[rate], "Non-table node should have label mapping")
        let rateValue = try #require(assignment.mapping[rate], "Non-table node should have value mapping")
        #expect(rateLabel.row == rateValue.row, "a node's label sits on the row of its value")
        #expect(rateLabel.column < rateValue.column, "and to the left of it")

        let total = try #require(model.node(named: "Total"))
        let totalLabel = try #require(assignment.labelMapping[total], "Non-table output node should have label mapping")
        let totalValue = try #require(assignment.mapping[total], "Non-table output node should have value mapping")
        #expect(totalLabel.row == totalValue.row, "a node's label sits on the row of its value")
        #expect(totalLabel.column < totalValue.column, "and to the left of it")

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    // MARK: - Integration: ModelExporter

    @Test func exportProducesValidWorkbook() throws {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Qty", value: 5)
        let price = try #require(model.node(named: "Price"))
        let qty = try #require(model.node(named: "Qty"))
        model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(qty)))

        let strategy = CompactLayoutStrategy()
        let wb = try ModelExporter.export(model, layout: strategy)

        #expect(wb.sheets.count == 1)
    }

    // MARK: - Integration: AmortizationModelBuilder with Table

    @Test func amortizationWithCompactTableExport() throws {
        let model = AmortizationModelBuilder.build(
            principal: 100_000,
            annualRate: 0.06,
            termMonths: 3
        )

        let strategy = CompactLayoutStrategy()
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
