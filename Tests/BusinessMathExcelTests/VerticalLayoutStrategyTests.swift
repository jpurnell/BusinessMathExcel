import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class VerticalLayoutStrategyTests: XCTestCase {

    func testEmptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertTrue(assignment.mapping.isEmpty)
        XCTAssertTrue(assignment.labelMapping.isEmpty)
        XCTAssertTrue(assignment.sectionRows.isEmpty)
    }

    func testNodesMapToValueColumn() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let cell = assignment.mapping[ref]
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.column, 4)
    }

    func testNodesMapToLabelColumn() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let label = assignment.labelMapping[ref]
        XCTAssertNotNil(label)
        XCTAssertEqual(label?.column, 3)
    }

    func testLabelAndValueShareSameRow() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let labelRow = assignment.labelMapping[ref]?.row
        let valueRow = assignment.mapping[ref]?.row
        XCTAssertEqual(labelRow, valueRow)
    }

    func testSectionHeaderRow() {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let headerRow = assignment.sectionRows["Inputs"]
        XCTAssertNotNil(headerRow)
        XCTAssertEqual(headerRow, 3)
    }

    func testMultipleSectionsMaintainOrder() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addFormula(label: "Monthly", formula: .number(0.004167))
        model.addOutput(label: "Result", formula: .number(100))

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputsRow = assignment.sectionRows["Inputs"]
        let calcsRow = assignment.sectionRows["Calculations"]
        let resultsRow = assignment.sectionRows["Results"]

        XCTAssertNotNil(inputsRow)
        XCTAssertNotNil(calcsRow)
        XCTAssertNotNil(resultsRow)

        XCTAssertLessThan(inputsRow!, calcsRow!)
        XCTAssertLessThan(calcsRow!, resultsRow!)
    }

    func testBlankRowBetweenSections() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputHeader = assignment.sectionRows["Inputs"]!
        let inputDataRow = assignment.mapping[model.node(named: "A")!]!.row
        let calcHeader = assignment.sectionRows["Calculations"]!

        XCTAssertEqual(inputDataRow, inputHeader + 1)
        XCTAssertEqual(calcHeader, inputDataRow + 2)
    }

    func testCustomColumns() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = VerticalLayoutStrategy(labelColumn: 1, valueColumn: 2)
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.labelMapping[ref]?.column, 1)
        XCTAssertEqual(assignment.mapping[ref]?.column, 2)
    }

    func testTitleRowReserved() {
        let model = ExcelModel()
        model.addInput(label: "X", value: 1)

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        let firstSectionRow = assignment.sectionRows.values.min()!
        XCTAssertGreaterThanOrEqual(firstSectionRow, 3)
    }

    func testAllRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)

        for ref in model.allRefs {
            XCTAssertNotNil(assignment.mapping[ref], "Missing mapping for \(ref.label)")
            XCTAssertNotNil(assignment.labelMapping[ref], "Missing label mapping for \(ref.label)")
        }
    }

    // MARK: - Table Awareness (opt-in)

    func testTableAwareDefaultsToFalse() {
        let strategy = VerticalLayoutStrategy()
        let model = makeTableModel()
        let assignment = strategy.assign(model)

        XCTAssertTrue(assignment.tableColumnHeaders.isEmpty,
            "Default strategy should not produce table column headers")

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNotNil(assignment.labelMapping[ref],
                "Non-table-aware should give every node a label mapping")
        }
    }

    func testTableAwarePopulatesColumnHeaders() {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        XCTAssertFalse(assignment.tableColumnHeaders.isEmpty)
        XCTAssertNotNil(assignment.tableColumnHeaders["Schedule"])
        XCTAssertEqual(assignment.tableColumnHeaders["Schedule"]?.count, 2)
    }

    func testTableAwareBodyNodesOmittedFromLabelMapping() {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNil(assignment.labelMapping[ref],
                "Table body node '\(label)' should not be in labelMapping")
        }
    }

    func testTableAwareBodyNodesInMapping() {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let tableNodeLabels = ["P1", "Amt1", "P2", "Amt2"]
        for label in tableNodeLabels {
            let ref = model.node(named: label)!
            XCTAssertNotNil(assignment.mapping[ref],
                "Table body node '\(label)' should be in mapping")
        }
    }

    func testTableAwareNonTableSectionsUnaffected() {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let rate = model.node(named: "Rate")!
        XCTAssertNotNil(assignment.labelMapping[rate])
        XCTAssertNotNil(assignment.mapping[rate])

        let total = model.node(named: "Total")!
        XCTAssertNotNil(assignment.labelMapping[total])
        XCTAssertNotNil(assignment.mapping[total])
    }

    func testTableAwareNoCellCollisions() {
        let model = makeTableModel()
        let strategy = VerticalLayoutStrategy(tableAware: true)
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let headerCells = assignment.tableColumnHeaders.values.flatMap { $0 }
        let allCells = valueCells + labelCells + headerCells

        let uniqueCells = Set(allCells)
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    func testTableAwareIntegrationWithModelExporter() throws {
        let model = AmortizationModelBuilder.build(
            principal: 100_000,
            annualRate: 0.06,
            termMonths: 3
        )

        let strategy = VerticalLayoutStrategy(tableAware: true)
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
