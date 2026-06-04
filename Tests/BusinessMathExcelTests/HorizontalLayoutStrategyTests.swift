import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class HorizontalLayoutStrategyTests: XCTestCase {

    // MARK: - Empty Model

    func testEmptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertTrue(assignment.mapping.isEmpty)
        XCTAssertTrue(assignment.labelMapping.isEmpty)
        XCTAssertTrue(assignment.sectionRows.isEmpty)
        XCTAssertTrue(assignment.tableColumnHeaders.isEmpty)
    }

    // MARK: - Single Section

    func testSingleSectionPlacesLabelsAtStartColumn() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let labelCell = assignment.labelMapping[ref]
        XCTAssertNotNil(labelCell)
        XCTAssertEqual(labelCell?.column, 3)
    }

    func testSingleSectionPlacesValuesNextToLabels() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let valueCell = assignment.mapping[ref]
        XCTAssertNotNil(valueCell)
        XCTAssertEqual(valueCell?.column, 4)
    }

    func testSingleSectionNodeStartsAtStartRow() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let sectionRow = assignment.sectionRows["Inputs"]
        XCTAssertEqual(sectionRow, 3)

        let valueRow = assignment.mapping[ref]?.row
        XCTAssertEqual(valueRow, 4)
    }

    // MARK: - Multi-Section Side-by-Side

    func testTwoSectionsPlacedSideBySide() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        let rate = model.node(named: "Rate")!
        model.addOutput(label: "Result", formula: .ref(rate))
        let result = model.node(named: "Result")!

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let rateCol = assignment.mapping[rate]?.column
        let resultCol = assignment.mapping[result]?.column

        XCTAssertEqual(rateCol, 4)
        XCTAssertEqual(resultCol, 7)
    }

    func testSectionsShareSameStartRow() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputsRow = assignment.sectionRows["Inputs"]
        let resultsRow = assignment.sectionRows["Results"]

        XCTAssertEqual(inputsRow, resultsRow)
    }

    func testThreeSectionsWithCorrectGaps() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = HorizontalLayoutStrategy(startColumn: 3, sectionGap: 1)
        let assignment = strategy.assign(model)

        let aCol = assignment.mapping[model.node(named: "A")!]?.column
        let bCol = assignment.mapping[model.node(named: "B")!]?.column
        let cCol = assignment.mapping[model.node(named: "C")!]?.column

        XCTAssertEqual(aCol, 4)
        XCTAssertEqual(bCol, 7)
        XCTAssertEqual(cCol, 10)
    }

    // MARK: - Section Headers

    func testSectionHeadersAtCorrectColumns() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertNotNil(assignment.sectionRows["Inputs"])
        XCTAssertNotNil(assignment.sectionRows["Results"])
    }

    // MARK: - Custom Parameters

    func testCustomStartColumn() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = HorizontalLayoutStrategy(startColumn: 5)
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.labelMapping[ref]?.column, 5)
        XCTAssertEqual(assignment.mapping[ref]?.column, 6)
    }

    func testCustomSectionGap() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = HorizontalLayoutStrategy(startColumn: 3, sectionGap: 3)
        let assignment = strategy.assign(model)

        let aCol = assignment.mapping[model.node(named: "A")!]?.column
        let bCol = assignment.mapping[model.node(named: "B")!]?.column

        XCTAssertEqual(aCol, 4)
        XCTAssertEqual(bCol, 9)
    }

    func testCustomStartRow() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = HorizontalLayoutStrategy(startRow: 5)
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sectionRows["Inputs"], 5)
        XCTAssertEqual(assignment.mapping[ref]?.row, 6)
    }

    // MARK: - All Refs Assigned

    func testAllRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = HorizontalLayoutStrategy()
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

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let allCells = valueCells + labelCells

        let uniqueCells = Set(allCells)
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    // MARK: - Nodes Stack Vertically Within Section

    func testNodesStackVerticallyWithinSection() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addInput(label: "B", value: 2)
        let c = model.addInput(label: "C", value: 3)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let rowA = assignment.mapping[a]?.row
        let rowB = assignment.mapping[b]?.row
        let rowC = assignment.mapping[c]?.row

        XCTAssertNotNil(rowA)
        XCTAssertNotNil(rowB)
        XCTAssertNotNil(rowC)
        XCTAssertEqual(rowB, rowA! + 1)
        XCTAssertEqual(rowC, rowB! + 1)
    }

    // MARK: - Integration with ModelExporter

    func testExportProducesValidWorkbook() throws {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Qty", value: 5)
        let price = model.node(named: "Price")!
        let qty = model.node(named: "Qty")!
        model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(qty)))

        let strategy = HorizontalLayoutStrategy()
        let wb = try ModelExporter.export(model, layout: strategy)

        XCTAssertEqual(wb.sheets.count, 1)
    }
}
