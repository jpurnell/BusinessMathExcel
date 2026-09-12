import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class DashboardLayoutStrategyTests: XCTestCase {

    // MARK: - Empty Model

    func testEmptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = DashboardLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertTrue(assignment.mapping.isEmpty)
        XCTAssertTrue(assignment.labelMapping.isEmpty)
        XCTAssertTrue(assignment.sectionRows.isEmpty)
        XCTAssertTrue(assignment.tableColumnHeaders.isEmpty)
    }

    // MARK: - Single Section

    func testSingleSectionPlacedAtOrigin() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = DashboardLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.labelMapping[ref]?.column, 3)
        XCTAssertEqual(assignment.mapping[ref]?.column, 4)
        XCTAssertEqual(assignment.sectionRows["Inputs"], 3)
    }

    // MARK: - Grid Layout: Left-to-Right Fill

    func testTwoSectionsFillLeftToRight() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let inputsRow = assignment.sectionRows["Inputs"]
        let resultsRow = assignment.sectionRows["Results"]
        XCTAssertEqual(inputsRow, resultsRow, "Both sections should be in the same band")

        let aCol = try XCTUnwrap(assignment.mapping[XCTUnwrap(model.node(named: "A"))]).column
        let bCol = try XCTUnwrap(assignment.mapping[XCTUnwrap(model.node(named: "B"))]).column
        XCTAssertLessThan(aCol, bCol, "Section 2 should be to the right of section 1")
    }

    func testThreeSectionsWrapToSecondBand() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let inputsRow = try XCTUnwrap(assignment.sectionRows["Inputs"])
        let calcsRow = try XCTUnwrap(assignment.sectionRows["Calculations"])
        let resultsRow = try XCTUnwrap(assignment.sectionRows["Results"])

        XCTAssertEqual(inputsRow, calcsRow, "First two sections share a band")
        XCTAssertGreaterThan(resultsRow, calcsRow, "Third section wraps to next band")
    }

    // MARK: - Band Height Adapts to Tallest Section

    func testBandHeightAdaptsToTallestSection() throws {
        let model = ExcelModel()
        model.addInput(label: "A1", value: 1)
        model.addInput(label: "A2", value: 2)
        model.addInput(label: "A3", value: 3)
        model.addOutput(label: "B1", formula: .number(1))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let inputsRow = try XCTUnwrap(assignment.sectionRows["Inputs"])
        let resultsRow = try XCTUnwrap(assignment.sectionRows["Results"])

        XCTAssertEqual(inputsRow, resultsRow, "Same band")

        let lastInputRow = try XCTUnwrap(assignment.mapping[XCTUnwrap(model.node(named: "A3"))]).row
        let resultRow = try XCTUnwrap(assignment.mapping[XCTUnwrap(model.node(named: "B1"))]).row
        XCTAssertLessThanOrEqual(resultRow, lastInputRow,
            "Results section ends at or before the last input row")
    }

    func testNextBandStartsAfterTallestSection() throws {
        let model = ExcelModel()
        model.addInput(label: "A1", value: 1)
        model.addInput(label: "A2", value: 2)
        model.addInput(label: "A3", value: 3)
        model.addFormula(label: "B1", formula: .number(1))
        model.addOutput(label: "C1", formula: .number(2))

        let strategy = DashboardLayoutStrategy(columnCount: 2, bandGap: 2)
        let assignment = strategy.assign(model)

        let lastInputRow = try XCTUnwrap(assignment.mapping[XCTUnwrap(model.node(named: "A3"))]).row

        let resultsRow = try XCTUnwrap(assignment.sectionRows["Results"])
        XCTAssertEqual(resultsRow, lastInputRow + 1 + 2,
            "Next band starts after tallest section + bandGap")
    }

    // MARK: - Custom Parameters

    func testCustomColumnCount() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let inputsRow = try XCTUnwrap(assignment.sectionRows["Inputs"])
        let calcsRow = try XCTUnwrap(assignment.sectionRows["Calculations"])
        let resultsRow = try XCTUnwrap(assignment.sectionRows["Results"])

        XCTAssertEqual(inputsRow, calcsRow, "All three fit in one band")
        XCTAssertEqual(calcsRow, resultsRow)
    }

    func testCustomStartColumn() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = DashboardLayoutStrategy(startColumn: 5)
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.labelMapping[ref]?.column, 5)
        XCTAssertEqual(assignment.mapping[ref]?.column, 6)
    }

    func testCustomSectionGap() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = DashboardLayoutStrategy(columnCount: 2, startColumn: 3, sectionGap: 3)
        let assignment = strategy.assign(model)

        let aCol = try XCTUnwrap(assignment.mapping[XCTUnwrap(model.node(named: "A"))]).column
        let bCol = try XCTUnwrap(assignment.mapping[XCTUnwrap(model.node(named: "B"))]).column

        XCTAssertEqual(aCol, 4)
        XCTAssertEqual(bCol, 9)
    }

    // MARK: - All Refs Assigned

    func testAllRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = DashboardLayoutStrategy()
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

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let allCells = valueCells + labelCells

        let uniqueCells = Set(allCells)
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    // MARK: - Many Sections

    func testManySectionsWrapCorrectly() {
        let model = ExcelModel()
        for i in 0..<10 {
            model.addInput(label: "N\(i)", value: Double(i), section: "S\(i)")
        }

        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.mapping.count, 10)

        let valueCells = Array(assignment.mapping.values)
        let uniqueCells = Set(valueCells)
        XCTAssertEqual(uniqueCells.count, valueCells.count, "No collisions with many sections")
    }

    // MARK: - Integration

    func testExportProducesValidWorkbook() throws {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Qty", value: 5)
        let price = try XCTUnwrap(model.node(named: "Price"))
        let qty = try XCTUnwrap(model.node(named: "Qty"))
        model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(qty)))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let wb = try ModelExporter.export(model, layout: strategy)

        XCTAssertEqual(wb.sheets.count, 1)
    }
}
