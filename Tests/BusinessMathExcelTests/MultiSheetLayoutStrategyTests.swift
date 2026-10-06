import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct MultiSheetLayoutStrategyTests {

    // MARK: - Empty Model

    @Test func emptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.isEmpty)
        #expect(assignment.sheetOrder.isEmpty)
        #expect(assignment.globalMapping.isEmpty)
    }

    // MARK: - Single Section

    @Test func singleSectionProducesOneSheet() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.count == 1)
        #expect(assignment.sheetOrder == ["Inputs"])
        #expect(Array(assignment.sheets.keys) == ["Inputs"])
    }

    @Test func singleSectionAssignmentHasCorrectMapping() throws {
        let model = ExcelModel()
        let ref = model.addInput(label: "Rate", value: 0.05)

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        let sheetAssignment = try #require(assignment.sheets["Inputs"])
        #expect(sheetAssignment.mapping.count == 1)

        let global = try #require(assignment.globalMapping[ref])
        #expect(global.sheetName == "Inputs")
    }

    // MARK: - Multi-Section

    @Test func multiSectionProducesOneSheetPerSection() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.count == 3)
        #expect(assignment.sheetOrder == ["Inputs", "Calculations", "Results"])
    }

    // MARK: - Custom Sheet Names

    @Test func customSheetNamesApplied() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addOutput(label: "NPV", formula: .number(100))

        let strategy = MultiSheetLayoutStrategy(sheetNames: [
            "Inputs": "Loan Parameters",
            "Results": "Analysis"
        ])
        let assignment = strategy.assign(model)

        #expect(assignment.sheetOrder == ["Loan Parameters", "Analysis"])
        #expect(Set(assignment.sheets.keys) == ["Loan Parameters", "Analysis"])
        #expect(assignment.sheets["Inputs"] == nil)
    }

    // MARK: - Per-Sheet Layout Respected

    @Test func perSheetLayoutUsesProvidedStrategy() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)

        let compact = CompactLayoutStrategy(labelColumn: 5, valueColumn: 6)
        let strategy = MultiSheetLayoutStrategy(perSheetLayout: compact)
        let assignment = strategy.assign(model)

        let sheetAssignment = try #require(assignment.sheets["Inputs"])

        let cells = Array(sheetAssignment.labelMapping.values)
        for cell in cells {
            #expect(cell.column == 5, "Per-sheet layout should use custom labelColumn")
        }
    }

    // MARK: - Global Mapping

    @Test func globalMappingIncludesAllNodes() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))
        let c = model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.globalMapping.count == 3)
        #expect(assignment.globalMapping[a]?.sheetName == "Inputs")
        #expect(assignment.globalMapping[b]?.sheetName == "Calculations")
        #expect(assignment.globalMapping[c]?.sheetName == "Results")
    }

    // MARK: - Default Sheet Names

    @Test func defaultSheetNamesUseSectionNames() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1, section: "My Inputs")
        model.addOutput(label: "B", formula: .number(2), section: "My Results")

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        #expect(assignment.sheetOrder == ["My Inputs", "My Results"])
    }

    // MARK: - Table-Aware Per-Sheet Layout

    @Test func tableSectionPreservedOnSheet() throws {
        let model = ExcelModel()
        let r0c0 = model.addInput(label: "P1", value: 1, section: "Schedule")
        let r0c1 = model.addInput(label: "Amt1", value: 500, section: "Schedule")
        let r1c0 = model.addInput(label: "P2", value: 2, section: "Schedule")
        let r1c1 = model.addInput(label: "Amt2", value: 500, section: "Schedule")
        model.registerTable(
            label: "Schedule",
            columns: ["Period", "Amount"],
            rows: [[r0c0, r0c1], [r1c0, r1c1]]
        )

        let strategy = MultiSheetLayoutStrategy(
            perSheetLayout: CompactLayoutStrategy()
        )
        let assignment = strategy.assign(model)

        let scheduleSheet = try #require(assignment.sheets["Schedule"])
        #expect(Array(scheduleSheet.tableColumnHeaders.keys) == ["Schedule"], "Table column headers should be populated on the sheet")
    }

    // MARK: - SheetGroup

    @Test func sheetGroupTwoSectionsOnOneSheet() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Parameters", sections: ["Inputs", "Calculations"]),
            SheetGroup(name: "Output", sections: ["Results"])
        ])
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.count == 2)
        #expect(assignment.sheetOrder == ["Parameters", "Output"])
    }

    @Test func sheetGroupCombinedSheetContainsAllNodes() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Combined", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        #expect(assignment.globalMapping[a]?.sheetName == "Combined")
        #expect(assignment.globalMapping[b]?.sheetName == "Combined")
    }

    @Test func sheetGroupPreservesSectionHeaders() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Combined", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        let sheet = try #require(assignment.sheets["Combined"])
        #expect(Set(sheet.sectionRows.keys) == ["Inputs", "Calculations"], "Grouped sheet should preserve section headers")
    }

    @Test func sheetGroupGlobalMappingAllNodesPresent() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))
        let c = model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Data", sections: ["Inputs", "Calculations"]),
            SheetGroup(name: "Output", sections: ["Results"])
        ])
        let assignment = strategy.assign(model)

        #expect(assignment.globalMapping.count == 3)
        #expect(assignment.globalMapping[a]?.sheetName == "Data")
        #expect(assignment.globalMapping[b]?.sheetName == "Data")
        #expect(assignment.globalMapping[c]?.sheetName == "Output")
    }

    @Test func sheetGroupUngroupedSectionsGetOwnSheet() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Data", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.count == 2)
        #expect(Set(assignment.sheets.keys) == ["Data", "Results"], "Ungrouped section should get its own sheet")
    }

    @Test func sheetGroupEmptyGroupsDefaultsToOnePerSection() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = MultiSheetLayoutStrategy(groups: [])
        let assignment = strategy.assign(model)

        #expect(assignment.sheets.count == 2)
        #expect(assignment.sheetOrder == ["Inputs", "Results"])
    }

    @Test func sheetGroupWithTableAwareLayout() throws {
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

        let strategy = MultiSheetLayoutStrategy(
            groups: [
                SheetGroup(name: "All Data", sections: ["Inputs", "Schedule"])
            ],
            perSheetLayout: CompactLayoutStrategy()
        )
        let assignment = strategy.assign(model)

        let sheet = try #require(assignment.sheets["All Data"])
        #expect(Array(sheet.tableColumnHeaders.keys) == ["Schedule"], "Table should be detected on grouped sheet")
    }

    @Test func sheetGroupNoCellCollisions() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "All", sections: ["Inputs", "Calculations", "Results"])
        ])
        let assignment = strategy.assign(model)

        let sheet = try #require(assignment.sheets["All"])

        let valueCells = Array(sheet.mapping.values)
        let labelCells = Array(sheet.labelMapping.values)
        let allCells = valueCells + labelCells

        let uniqueCells = Set(allCells)
        #expect(uniqueCells.count == allCells.count, "Cell collision detected")
    }

    @Test func sheetGroupWithMultiSheetExporter() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.05)
        model.addOutput(label: "Result", formula: .multiply(.ref(rate), .number(100)))

        let layout = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "All", sections: ["Inputs", "Results"])
        ])
        let wb = try MultiSheetExporter.export(model, layout: layout)

        #expect(wb.sheets.count == 1, "All sections grouped onto one sheet")
    }

    @Test func sheetGroupOrderMatchesGroupOrder() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Output", sections: ["Results"]),
            SheetGroup(name: "Data", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        #expect(assignment.sheetOrder == ["Output", "Data"], "Sheet order should match group order")
    }
}
