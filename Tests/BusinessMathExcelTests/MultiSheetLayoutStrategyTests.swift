import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class MultiSheetLayoutStrategyTests: XCTestCase {

    // MARK: - Empty Model

    func testEmptyModelProducesEmptyAssignment() {
        let model = ExcelModel()
        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertTrue(assignment.sheets.isEmpty)
        XCTAssertTrue(assignment.sheetOrder.isEmpty)
        XCTAssertTrue(assignment.globalMapping.isEmpty)
    }

    // MARK: - Single Section

    func testSingleSectionProducesOneSheet() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheets.count, 1)
        XCTAssertEqual(assignment.sheetOrder, ["Inputs"])
        XCTAssertNotNil(assignment.sheets["Inputs"])
    }

    func testSingleSectionAssignmentHasCorrectMapping() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Rate", value: 0.05)

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        let sheetAssignment = assignment.sheets["Inputs"]
        XCTAssertNotNil(sheetAssignment)
        XCTAssertEqual(sheetAssignment?.mapping.count, 1)

        let global = assignment.globalMapping[ref]
        XCTAssertNotNil(global)
        XCTAssertEqual(global?.sheetName, "Inputs")
    }

    // MARK: - Multi-Section

    func testMultiSectionProducesOneSheetPerSection() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheets.count, 3)
        XCTAssertEqual(assignment.sheetOrder, ["Inputs", "Calculations", "Results"])
    }

    // MARK: - Custom Sheet Names

    func testCustomSheetNamesApplied() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addOutput(label: "NPV", formula: .number(100))

        let strategy = MultiSheetLayoutStrategy(sheetNames: [
            "Inputs": "Loan Parameters",
            "Results": "Analysis"
        ])
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheetOrder, ["Loan Parameters", "Analysis"])
        XCTAssertNotNil(assignment.sheets["Loan Parameters"])
        XCTAssertNotNil(assignment.sheets["Analysis"])
        XCTAssertNil(assignment.sheets["Inputs"])
    }

    // MARK: - Per-Sheet Layout Respected

    func testPerSheetLayoutUsesProvidedStrategy() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)

        let compact = CompactLayoutStrategy(labelColumn: 5, valueColumn: 6)
        let strategy = MultiSheetLayoutStrategy(perSheetLayout: compact)
        let assignment = strategy.assign(model)

        let sheetAssignment = assignment.sheets["Inputs"]
        XCTAssertNotNil(sheetAssignment)

        let cells = Array(sheetAssignment?.labelMapping.values ?? [:].values)
        for cell in cells {
            XCTAssertEqual(cell.column, 5, "Per-sheet layout should use custom labelColumn")
        }
    }

    // MARK: - Global Mapping

    func testGlobalMappingIncludesAllNodes() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))
        let c = model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.globalMapping.count, 3)
        XCTAssertEqual(assignment.globalMapping[a]?.sheetName, "Inputs")
        XCTAssertEqual(assignment.globalMapping[b]?.sheetName, "Calculations")
        XCTAssertEqual(assignment.globalMapping[c]?.sheetName, "Results")
    }

    // MARK: - Default Sheet Names

    func testDefaultSheetNamesUseSectionNames() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1, section: "My Inputs")
        model.addOutput(label: "B", formula: .number(2), section: "My Results")

        let strategy = MultiSheetLayoutStrategy()
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheetOrder, ["My Inputs", "My Results"])
    }

    // MARK: - Table-Aware Per-Sheet Layout

    func testTableSectionPreservedOnSheet() {
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

        let scheduleSheet = assignment.sheets["Schedule"]
        XCTAssertNotNil(scheduleSheet)
        XCTAssertFalse(scheduleSheet?.tableColumnHeaders.isEmpty ?? true,
            "Table column headers should be populated on the sheet")
    }

    // MARK: - SheetGroup

    func testSheetGroupTwoSectionsOnOneSheet() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Parameters", sections: ["Inputs", "Calculations"]),
            SheetGroup(name: "Output", sections: ["Results"])
        ])
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheets.count, 2)
        XCTAssertEqual(assignment.sheetOrder, ["Parameters", "Output"])
    }

    func testSheetGroupCombinedSheetContainsAllNodes() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Combined", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.globalMapping[a]?.sheetName, "Combined")
        XCTAssertEqual(assignment.globalMapping[b]?.sheetName, "Combined")
    }

    func testSheetGroupPreservesSectionHeaders() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Combined", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        let sheet = assignment.sheets["Combined"]
        XCTAssertNotNil(sheet)
        XCTAssertNotNil(sheet?.sectionRows["Inputs"],
            "Grouped sheet should preserve section headers")
        XCTAssertNotNil(sheet?.sectionRows["Calculations"],
            "Grouped sheet should preserve section headers")
    }

    func testSheetGroupGlobalMappingAllNodesPresent() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addFormula(label: "B", formula: .number(2))
        let c = model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Data", sections: ["Inputs", "Calculations"]),
            SheetGroup(name: "Output", sections: ["Results"])
        ])
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.globalMapping.count, 3)
        XCTAssertEqual(assignment.globalMapping[a]?.sheetName, "Data")
        XCTAssertEqual(assignment.globalMapping[b]?.sheetName, "Data")
        XCTAssertEqual(assignment.globalMapping[c]?.sheetName, "Output")
    }

    func testSheetGroupUngroupedSectionsGetOwnSheet() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Data", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheets.count, 2)
        XCTAssertNotNil(assignment.sheets["Data"])
        XCTAssertNotNil(assignment.sheets["Results"],
            "Ungrouped section should get its own sheet")
    }

    func testSheetGroupEmptyGroupsDefaultsToOnePerSection() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addOutput(label: "B", formula: .number(2))

        let strategy = MultiSheetLayoutStrategy(groups: [])
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheets.count, 2)
        XCTAssertEqual(assignment.sheetOrder, ["Inputs", "Results"])
    }

    func testSheetGroupWithTableAwareLayout() {
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

        let sheet = assignment.sheets["All Data"]
        XCTAssertNotNil(sheet)
        XCTAssertFalse(sheet?.tableColumnHeaders.isEmpty ?? true,
            "Table should be detected on grouped sheet")
    }

    func testSheetGroupNoCellCollisions() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addInput(label: "B", value: 2)
        model.addFormula(label: "C", formula: .number(3))
        model.addOutput(label: "D", formula: .number(4))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "All", sections: ["Inputs", "Calculations", "Results"])
        ])
        let assignment = strategy.assign(model)

        let sheet = assignment.sheets["All"]
        XCTAssertNotNil(sheet)

        let valueCells = Array(sheet?.mapping.values ?? [:].values)
        let labelCells = Array(sheet?.labelMapping.values ?? [:].values)
        let allCells = valueCells + labelCells

        let uniqueCells = Set(allCells)
        XCTAssertEqual(uniqueCells.count, allCells.count, "Cell collision detected")
    }

    func testSheetGroupWithMultiSheetExporter() throws {
        let model = ExcelModel()
        let rate = model.addInput(label: "Rate", value: 0.05)
        model.addOutput(label: "Result", formula: .multiply(.ref(rate), .number(100)))

        let layout = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "All", sections: ["Inputs", "Results"])
        ])
        let wb = try MultiSheetExporter.export(model, layout: layout)

        XCTAssertEqual(wb.sheets.count, 1,
            "All sections grouped onto one sheet")
    }

    func testSheetGroupOrderMatchesGroupOrder() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addFormula(label: "B", formula: .number(2))
        model.addOutput(label: "C", formula: .number(3))

        let strategy = MultiSheetLayoutStrategy(groups: [
            SheetGroup(name: "Output", sections: ["Results"]),
            SheetGroup(name: "Data", sections: ["Inputs", "Calculations"])
        ])
        let assignment = strategy.assign(model)

        XCTAssertEqual(assignment.sheetOrder, ["Output", "Data"],
            "Sheet order should match group order")
    }
}
