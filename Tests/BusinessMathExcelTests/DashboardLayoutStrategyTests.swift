import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct DashboardLayoutStrategyTests {

    // MARK: - Empty Model

    @Test func emptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = DashboardLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.mapping.isEmpty)
        #expect(assignment.labelMapping.isEmpty)
        #expect(assignment.sectionRows.isEmpty)
        #expect(assignment.tableColumnHeaders.isEmpty)
    }

    // MARK: - Single Section

    @Test func singleSectionPlacedAtOrigin() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = DashboardLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.labelMapping[ref]?.column == 3)
        #expect(assignment.mapping[ref]?.column == 4)
        #expect(assignment.sectionRows["Inputs"] == 3)
    }

    // MARK: - Grid Layout: Left-to-Right Fill

    @Test func twoSectionsFillLeftToRight() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let inputsRow = assignment.sectionRows["Inputs"]
        let resultsRow = assignment.sectionRows["Results"]
        #expect(inputsRow == resultsRow, "Both sections should be in the same band")

        let aColNode = try #require(model.node(named: "A"))

        let aCol = try #require(assignment.mapping[aColNode]).column
        let bColNode = try #require(model.node(named: "B"))
        let bCol = try #require(assignment.mapping[bColNode]).column
        #expect(aCol < bCol, "Section 2 should be to the right of section 1")
    }

    @Test func threeSectionsWrapToSecondBand() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let inputsRow = try #require(assignment.sectionRows["Inputs"])
        let calcsRow = try #require(assignment.sectionRows["Calculations"])
        let resultsRow = try #require(assignment.sectionRows["Results"])

        #expect(inputsRow == calcsRow, "First two sections share a band")
        #expect(resultsRow > calcsRow, "Third section wraps to next band")
    }

    // MARK: - Band Height Adapts to Tallest Section

    @Test func bandHeightAdaptsToTallestSection() throws {
        let model = ExcelModel()
        model.addInput(label: "A1", value: 1)
        model.addInput(label: "A2", value: 2)
        model.addInput(label: "A3", value: 3)
        model.addOutput(label: "B1", formula: .number(1))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let inputsRow = try #require(assignment.sectionRows["Inputs"])
        let resultsRow = try #require(assignment.sectionRows["Results"])

        #expect(inputsRow == resultsRow, "Same band")

        let lastInputRowNode = try #require(model.node(named: "A3"))

        let lastInputRow = try #require(assignment.mapping[lastInputRowNode]).row
        let resultRowNode = try #require(model.node(named: "B1"))
        let resultRow = try #require(assignment.mapping[resultRowNode]).row
        #expect(resultRow <= lastInputRow, "Results section ends at or before the last input row")
    }

    @Test func nextBandStartsAfterTallestSection() throws {
        let model = ExcelModel()
        model.addInput(label: "A1", value: 1)
        model.addInput(label: "A2", value: 2)
        model.addInput(label: "A3", value: 3)
        model.addFormula(label: "B1", formula: .number(1))
        model.addOutput(label: "C1", formula: .number(2))

        let strategy = DashboardLayoutStrategy(columnCount: 2, bandGap: 2)
        let assignment = strategy.assign(model)

        let lastInputRowNode = try #require(model.node(named: "A3"))

        let lastInputRow = try #require(assignment.mapping[lastInputRowNode]).row

        let resultsRow = try #require(assignment.sectionRows["Results"])
        #expect(resultsRow == (lastInputRow + 1 + 2), "Next band starts after tallest section + bandGap")
    }

    // MARK: - Custom Parameters

    @Test func customColumnCount() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        let inputsRow = try #require(assignment.sectionRows["Inputs"])
        let calcsRow = try #require(assignment.sectionRows["Calculations"])
        let resultsRow = try #require(assignment.sectionRows["Results"])

        #expect(inputsRow == calcsRow, "All three fit in one band")
        #expect(calcsRow == resultsRow)
    }

    @Test func customStartColumn() {
        let model = ExcelModel()
        let ref = model.addInput(label: "X", value: 1)

        let strategy = DashboardLayoutStrategy(startColumn: 5)
        let assignment = strategy.assign(model)

        #expect(assignment.labelMapping[ref]?.column == 5)
        #expect(assignment.mapping[ref]?.column == 6)
    }

    @Test func customSectionGap() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = DashboardLayoutStrategy(columnCount: 2, startColumn: 3, sectionGap: 3)
        let assignment = strategy.assign(model)

        let aColNode = try #require(model.node(named: "A"))

        let aCol = try #require(assignment.mapping[aColNode]).column
        let bColNode = try #require(model.node(named: "B"))
        let bCol = try #require(assignment.mapping[bColNode]).column

        #expect(aCol == 4)
        #expect(bCol == 9)
    }

    // MARK: - All Refs Assigned

    @Test func allRefsGetAssignments() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = DashboardLayoutStrategy()
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

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let assignment = strategy.assign(model)

        let valueCells = Array(assignment.mapping.values)
        let labelCells = Array(assignment.labelMapping.values)
        let allCells = valueCells + labelCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    // MARK: - Many Sections

    @Test func manySectionsWrapCorrectly() {
        let model = ExcelModel()
        for i in 0..<10 {
            model.addInput(label: "N\(i)", value: Double(i), section: "S\(i)")
        }

        let strategy = DashboardLayoutStrategy(columnCount: 3)
        let assignment = strategy.assign(model)

        #expect(assignment.mapping.count == 10)

        let valueCells = Array(assignment.mapping.values)
        let uniqueCells = Set(valueCells)
        #expect(uniqueCells.count == valueCells.count, "No collisions with many sections")
    }

    // MARK: - Integration

    @Test func exportProducesValidWorkbook() throws {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 100)
        model.addInput(label: "Qty", value: 5)
        let price = try #require(model.node(named: "Price"))
        let qty = try #require(model.node(named: "Qty"))
        model.addOutput(label: "Total", formula: .multiply(.ref(price), .ref(qty)))

        let strategy = DashboardLayoutStrategy(columnCount: 2)
        let wb = try ModelExporter.export(model, layout: strategy)

        #expect(wb.sheets.count == 1)
    }
}
