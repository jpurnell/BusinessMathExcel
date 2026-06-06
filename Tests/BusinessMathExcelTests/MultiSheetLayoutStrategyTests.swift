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
}
