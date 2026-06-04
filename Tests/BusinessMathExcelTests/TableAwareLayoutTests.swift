import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class TableAwareLayoutTests: XCTestCase {

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

    func testHorizontalTableSectionPopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertFalse(assignment.tableColumnHeaders.isEmpty,
            "Table column headers should be populated")
        XCTAssertNotNil(assignment.tableColumnHeaders["Schedule"])
        XCTAssertEqual(assignment.tableColumnHeaders["Schedule"]?.count, 2)
    }

    func testHorizontalTableBodyNodesOmittedFromLabelMapping() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNil(assignment.labelMapping[ref],
                "Table body node '\(label)' should not be in labelMapping")
        }
    }

    func testHorizontalTableBodyNodesInMapping() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNotNil(assignment.mapping[ref],
                "Table body node '\(label)' should be in mapping")
        }
    }

    func testHorizontalTableSpansCorrectColumns() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy(startColumn: 3)
        let assignment = strategy.assign(model)

        let p1 = model.node(named: "P1")!
        let amt1 = model.node(named: "Amt1")!

        let p1Col = assignment.mapping[p1]?.column
        let amt1Col = assignment.mapping[amt1]?.column

        XCTAssertNotNil(p1Col)
        XCTAssertNotNil(amt1Col)
        XCTAssertEqual(amt1Col, p1Col! + 1, "Table columns should be adjacent")
    }

    func testHorizontalTableRowsStackVertically() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let p1Row = assignment.mapping[model.node(named: "P1")!]?.row
        let p2Row = assignment.mapping[model.node(named: "P2")!]?.row

        XCTAssertNotNil(p1Row)
        XCTAssertNotNil(p2Row)
        XCTAssertEqual(p2Row, p1Row! + 1)
    }

    func testHorizontalNonTableSectionsUnaffected() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let rate = model.node(named: "Rate")!
        XCTAssertNotNil(assignment.labelMapping[rate],
            "Non-table node should have label mapping")
        XCTAssertNotNil(assignment.mapping[rate],
            "Non-table node should have value mapping")
    }

    // MARK: - DashboardLayoutStrategy Table Awareness

    func testDashboardTableSectionPopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        XCTAssertNotNil(assignment.tableColumnHeaders["Schedule"])
        XCTAssertEqual(assignment.tableColumnHeaders["Schedule"]?.count, 2)
    }

    func testDashboardTableBodyNodesOmittedFromLabelMapping() {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNil(assignment.labelMapping[ref],
                "Table body node '\(label)' should not be in labelMapping")
        }
    }

    func testDashboardTableBodyNodesInMapping() {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNotNil(assignment.mapping[ref],
                "Table body node '\(label)' should be in mapping")
        }
    }

    // MARK: - No Collisions with Mixed Content

    func testNoCellCollisionsWithTables() {
        let model = makeTableModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    func testDashboardNoCellCollisionsWithTables() {
        let model = makeTableModel()
        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    // MARK: - Integration: Amortization + Table-Aware Export

    func testAmortizationWithHorizontalTableExport() throws {
        let model = AmortizationModelBuilder.build(
            principal: 100_000,
            annualRate: 0.06,
            termMonths: 3
        )

        let strategy = HorizontalLayoutStrategy()
        let wb = try ModelExporter.export(model, layout: strategy)
        let sheet = wb.sheets[0]

        XCTAssertEqual(wb.sheets.count, 1)
        XCTAssertNotNil(sheet)
    }
}
