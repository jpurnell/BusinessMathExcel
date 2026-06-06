import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class CompactLayoutStrategyTests: XCTestCase {

    // MARK: - Empty Model

    func testEmptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertTrue(assignment.mapping.isEmpty)
        XCTAssertTrue(assignment.labelMapping.isEmpty)
        XCTAssertTrue(assignment.sectionRows.isEmpty)
        XCTAssertTrue(assignment.tableColumnHeaders.isEmpty)
    }

    // MARK: - Single Section

    func testSingleSectionPlacesLabelsAndValues() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.labelMapping[ref]?.column, 3)
        XCTAssertEqual(assignment.mapping[ref]?.column, 4)
        XCTAssertEqual(assignment.sectionRows["Inputs"], 3)
        XCTAssertEqual(assignment.mapping[ref]?.row, 4)
    }

    // MARK: - Multi-Section: No Blank Separator Rows

    func testMultiSectionNoBlankRows() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputHeader = assignment.sectionRows["Inputs"]!
        let inputDataRow = assignment.mapping[model.node(named: "A")!]!.row
        let calcHeader = assignment.sectionRows["Calculations"]!

        XCTAssertEqual(inputHeader, 3)
        XCTAssertEqual(inputDataRow, 4)
        XCTAssertEqual(calcHeader, 5, "Next section header should immediately follow without blank row")
    }

    func testThreeSectionsFlowWithoutGaps() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputsRow = assignment.sectionRows["Inputs"]!
        let calcsRow = assignment.sectionRows["Calculations"]!
        let resultsRow = assignment.sectionRows["Results"]!

        // Inputs: header at 3, A at 4, B at 5
        // Calculations: header at 6, C at 7
        // Results: header at 8, D at 9
        XCTAssertEqual(inputsRow, 3)
        XCTAssertEqual(calcsRow, 6)
        XCTAssertEqual(resultsRow, 8)
    }

    // MARK: - Custom Columns

    func testCustomLabelAndValueColumns() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = CompactLayoutStrategy(labelColumn: 1, valueColumn: 2)
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.labelMapping[ref]?.column, 1)
        XCTAssertEqual(assignment.mapping[ref]?.column, 2)
    }

    // MARK: - All Refs Assigned

    func testAllRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        for ref in model.allRefs {
            XCTAssertNotNil(assignment.mapping[ref], "Missing mapping for \(ref.label)")
            XCTAssertNotNil(assignment.labelMapping[ref], "Missing label mapping for \(ref.label)")
        }
    }

    // MARK: - No Cell Collisions

    func testNoCellCollisions() {
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
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    // MARK: - Compact vs Vertical Comparison

    func testCompactProducesFewerRowsThanVertical() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let compact = CompactLayoutStrategy()
        let vertical = VerticalLayoutStrategy()

        let compactAssignment = compact.assign(model)
        let verticalAssignment = vertical.assign(model)

        XCTAssertLessThan(compactAssignment.lastRow, verticalAssignment.lastRow,
            "Compact should use fewer rows than vertical")
    }

    // MARK: - Table-Aware: Column Headers

    func testTableSectionPopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertFalse(assignment.tableColumnHeaders.isEmpty)
        XCTAssertNotNil(assignment.tableColumnHeaders["Schedule"])
        XCTAssertEqual(assignment.tableColumnHeaders["Schedule"]?.count, 2)
    }

    // MARK: - Table-Aware: Body Nodes

    func testTableBodyNodesOmittedFromLabelMapping() {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNil(assignment.labelMapping[ref],
                "Table body node '\(label)' should not be in labelMapping")
        }
    }

    func testTableBodyNodesInMapping() {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNotNil(assignment.mapping[ref],
                "Table body node '\(label)' should be in mapping")
        }
    }

    // MARK: - Table-Aware: Mixed Content

    func testMixedTableAndNonTableSections() {
        let model = makeTableModel()
        let strategy = CompactLayoutStrategy()
        let assignment = strategy.assign(model)

        let rate = model.node(named: "Rate")!
        XCTAssertNotNil(assignment.labelMapping[rate],
            "Non-table node should have label mapping")
        XCTAssertNotNil(assignment.mapping[rate],
            "Non-table node should have value mapping")

        let total = model.node(named: "Total")!
        XCTAssertNotNil(assignment.labelMapping[total],
            "Non-table output node should have label mapping")
        XCTAssertNotNil(assignment.mapping[total],
            "Non-table output node should have value mapping")

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    // MARK: - Integration: ModelExporter

    func testExportProducesValidWorkbook() throws {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Qty", value: 5)
        let price = model.node(named: "Price")!
        let qty = model.node(named: "Qty")!
        model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(qty)))

        let strategy = CompactLayoutStrategy()
        let wb = try ModelExporter.export(model, layout: strategy)

        XCTAssertEqual(wb.sheets.count, 1)
    }

    // MARK: - Integration: AmortizationModelBuilder with Table

    func testAmortizationWithCompactTableExport() throws {
        let model = AmortizationModelBuilder.build(
            principal: 100_000,
            annualRate: 0.06,
            termMonths: 3
        )

        let strategy = CompactLayoutStrategy()
        let wb = try ModelExporter.export(model, layout: strategy)

        XCTAssertEqual(wb.sheets.count, 1)
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
