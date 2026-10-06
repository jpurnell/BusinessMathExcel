import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct HorizontalLayoutStrategyTests {

    // MARK: - Empty Model

    @Test func emptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.mapping.isEmpty)
        #expect(assignment.labelMapping.isEmpty)
        #expect(assignment.sectionRows.isEmpty)
        #expect(assignment.tableColumnHeaders.isEmpty)
    }

    // MARK: - Single Section

    @Test func singleSectionPlacesLabelsAtStartColumn() throws {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let labelCell = try #require(assignment.labelMapping[ref])
        #expect(labelCell.column == 3)
    }

    @Test func singleSectionPlacesValuesNextToLabels() throws {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let valueCell = try #require(assignment.mapping[ref])
        #expect(valueCell.column == 4)
    }

    @Test func singleSectionNodeStartsAtStartRow() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Price", value: 100)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let sectionRow = assignment.sectionRows["Inputs"]
        #expect(sectionRow == 3)

        let valueRow = assignment.mapping[ref]?.row
        #expect(valueRow == 4)
    }

    // MARK: - Multi-Section Side-by-Side

    @Test func twoSectionsPlacedSideBySide() throws {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        let rate = try #require(model.node(named: "Rate"))
        model.addOutput(label: "Result", formula: .ref(rate))
        let result = try #require(model.node(named: "Result"))

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let rateCol = assignment.mapping[rate]?.column
        let resultCol = assignment.mapping[result]?.column

        #expect(rateCol == 4)
        #expect(resultCol == 7)
    }

    @Test func sectionsShareSameStartRow() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let inputsRow = assignment.sectionRows["Inputs"]
        let resultsRow = assignment.sectionRows["Results"]

        #expect(inputsRow == resultsRow)
    }

    @Test func threeSectionsWithCorrectGaps() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = HorizontalLayoutStrategy(startColumn: 3, sectionGap: 1)
        let assignment = strategy.assign(model)

        let aColNode = try #require(model.node(named: "A"))

        let aCol = try #require(assignment.mapping[aColNode]).column
        let bColNode = try #require(model.node(named: "B"))
        let bCol = try #require(assignment.mapping[bColNode]).column
        let cColNode = try #require(model.node(named: "C"))
        let cCol = try #require(assignment.mapping[cColNode]).column

        #expect(aCol == 4)
        #expect(bCol == 7)
        #expect(cCol == 10)
    }

    // MARK: - Section Headers

    @Test func sectionHeadersAtCorrectColumns() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(Set(assignment.sectionRows.keys) == ["Inputs", "Results"])
    }

    // MARK: - Custom Parameters

    @Test func customStartColumn() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = HorizontalLayoutStrategy(startColumn: 5)
        let assignment = strategy.assign(model)

        #expect(assignment.labelMapping[ref]?.column == 5)
        #expect(assignment.mapping[ref]?.column == 6)
    }

    @Test func customSectionGap() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = HorizontalLayoutStrategy(startColumn: 3, sectionGap: 3)
        let assignment = strategy.assign(model)

        let aColNode = try #require(model.node(named: "A"))

        let aCol = try #require(assignment.mapping[aColNode]).column
        let bColNode = try #require(model.node(named: "B"))
        let bCol = try #require(assignment.mapping[bColNode]).column

        #expect(aCol == 4)
        #expect(bCol == 9)
    }

    @Test func customStartRow() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = HorizontalLayoutStrategy(startRow: 5)
        let assignment = strategy.assign(model)

        #expect(assignment.sectionRows["Inputs"] == 5)
        #expect(assignment.mapping[ref]?.row == 6)
    }

    // MARK: - All Refs Assigned

    @Test func allRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = HorizontalLayoutStrategy()
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

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let allCells = valueCells + labelCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    // MARK: - Nodes Stack Vertically Within Section

    @Test func nodesStackVerticallyWithinSection() throws {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addInput(label: "B", value: 2)
        let c = model.addInput(label: "C", value: 3)

        let strategy = HorizontalLayoutStrategy()
        let assignment = strategy.assign(model)

        let rowA = try #require(assignment.mapping[a]?.row)
        let rowB = try #require(assignment.mapping[b]?.row)
        let rowC = try #require(assignment.mapping[c]?.row)
        #expect(rowB == (rowA + 1))
        #expect(rowC == (rowB + 1))
    }

    // MARK: - Integration with ModelExporter

    @Test func exportProducesValidWorkbook() throws {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Qty", value: 5)
        let price = try #require(model.node(named: "Price"))
        let qty = try #require(model.node(named: "Qty"))
        model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(qty)))

        let strategy = HorizontalLayoutStrategy()
        let wb = try ModelExporter.export(model, layout: strategy)

        #expect(wb.sheets.count == 1)
    }
}
