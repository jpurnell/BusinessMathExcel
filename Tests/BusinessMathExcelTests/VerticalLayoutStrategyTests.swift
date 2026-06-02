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
}
