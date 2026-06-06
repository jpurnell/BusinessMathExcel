import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class MultiSheetAssignmentTests: XCTestCase {

    // MARK: - SheetCell

    func testSheetCellEquality() {
        let a = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let b = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let c = SheetCell(sheetName: "Results", cell: CellRef(column: 3, row: 4))

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSheetCellHashing() {
        let a = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let b = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let c = SheetCell(sheetName: "Results", cell: CellRef(column: 3, row: 4))

        var set: Set<SheetCell> = []
        set.insert(a)
        set.insert(b)
        set.insert(c)

        XCTAssertEqual(set.count, 2)
    }

    // MARK: - MultiSheetAssignment

    func testSheetsPopulatedPerSection() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addOutput(label: "Result", formula: .number(100))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheets.count, 2)
        XCTAssertNotNil(assignment.sheets["Inputs"])
        XCTAssertNotNil(assignment.sheets["Results"])
    }

    func testSheetOrderPreservesInsertionOrder() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheetOrder, ["Inputs", "Calculations", "Results"])
    }

    func testGlobalMappingContainsAllNodes() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))
        let c = model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertNotNil(assignment.globalMapping[a])
        XCTAssertNotNil(assignment.globalMapping[b])
        XCTAssertNotNil(assignment.globalMapping[c])

        XCTAssertEqual(assignment.globalMapping[a]?.sheetName, "Inputs")
        XCTAssertEqual(assignment.globalMapping[b]?.sheetName, "Calculations")
        XCTAssertEqual(assignment.globalMapping[c]?.sheetName, "Results")
    }

    func testEmptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertTrue(assignment.sheets.isEmpty)
        XCTAssertTrue(assignment.sheetOrder.isEmpty)
        XCTAssertTrue(assignment.globalMapping.isEmpty)
    }
}
