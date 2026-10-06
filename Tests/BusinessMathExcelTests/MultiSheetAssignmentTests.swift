import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct MultiSheetAssignmentTests {

    // MARK: - SheetCell

    @Test func sheetCellEquality() {
        let a = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let b = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let c = SheetCell(sheetName: "Results", cell: CellRef(column: 3, row: 4))

        #expect(a == b)
        #expect(a != c)
    }

    @Test func sheetCellHashing() {
        let a = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let b = SheetCell(sheetName: "Inputs", cell: CellRef(column: 3, row: 4))
        let c = SheetCell(sheetName: "Results", cell: CellRef(column: 3, row: 4))

        var set: Set<SheetCell> = []
        set.insert(a)
        set.insert(b)
        set.insert(c)

        #expect(set.count == 2)
    }

    // MARK: - MultiSheetAssignment

    @Test func sheetsPopulatedPerSection() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addOutput(label: "Result", formula: .number(100))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.count == 2)
        #expect(Set(assignment.sheets.keys) == ["Inputs", "Results"])
    }

    @Test func sheetOrderPreservesInsertionOrder() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.sheetOrder == ["Inputs", "Calculations", "Results"])
    }

    @Test func globalMappingContainsAllNodes() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))
        let c = model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(Set(assignment.globalMapping.keys) == [a, b, c])

        #expect(assignment.globalMapping[a]?.sheetName == "Inputs")
        #expect(assignment.globalMapping[b]?.sheetName == "Calculations")
        #expect(assignment.globalMapping[c]?.sheetName == "Results")
    }

    @Test func emptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.isEmpty)
        #expect(assignment.sheetOrder.isEmpty)
        #expect(assignment.globalMapping.isEmpty)
    }
}
