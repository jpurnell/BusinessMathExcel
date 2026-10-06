import Foundation
import Testing
@testable import BusinessMathExcel

@Suite struct ExcelModelTests {

    // MARK: - Adding Nodes

    @Test func addInput() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Principal", value: 250_000)

        #expect(model.nodeCount == 1)
        #expect(ref.label == "Principal")
        if case .input(let value) = model.kind(of: ref) {
            #expect(abs(value - 250_000) <= 0.01)
        } else {
            Issue.record("Expected input node")
        }
    }

    @Test func addTextInput() {
        let model = ExcelModel()
        let ref = model.addTextInput(label: "Title", value: "Loan Schedule")

        #expect(model.nodeCount == 1)
        #expect(model.kind(of: ref) == .textInput("Loan Schedule"))
    }

    @Test func addFormula() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Annual Rate", value: 0.065)
        let formula = NodeFormula.divide(.ref(rate), .number(12))
        let monthly = model.addFormula(label: "Monthly Rate", formula: formula)

        #expect(model.nodeCount == 2)
        #expect(model.kind(of: monthly) == .formula(formula))
    }

    @Test func addOutput() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 10)
        let b = model.addInput(label: "B", value: 20)
        let sumFormula = NodeFormula.add(.ref(a), .ref(b))
        let result = model.addOutput(label: "Total", formula: sumFormula)

        #expect(model.nodeCount == 3)
        #expect(model.kind(of: result) == .output(sumFormula))
    }

    @Test func addLabel() {
        let model = ExcelModel()
        let ref = model.addLabel("Summary")

        #expect(model.nodeCount == 1)
        #expect(model.kind(of: ref) == .label("Summary"))
    }

    // MARK: - Lookup

    @Test func nodeLookupByName() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Principal", value: 100_000)

        #expect(model.node(named: "Principal") == ref)
    }

    @Test func nodeLookupMissingReturnsNil() {
        let model = ExcelModel()
        #expect(model.node(named: "Nonexistent") == nil)
    }

    @Test func kindOfUnknownRefReturnsNil() {
        let model = ExcelModel()
        let unknown = NodeRef(label: "Ghost")
        #expect(model.kind(of: unknown) == nil)
    }

    // MARK: - Sections

    @Test func defaultSections() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addFormula(label: "Monthly", formula: .number(0.05 / 12))
        model.addOutput(label: "Result", formula: .number(100))

        let sectionNames = model.sections.map(\.name)
        #expect(sectionNames == ["Inputs", "Calculations", "Results"])
    }

    @Test func customSection() {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 50, section: "Product")
        model.addInput(label: "Quantity", value: 100, section: "Product")

        #expect(model.sections.count == 1)
        #expect(model.sections[0].name == "Product")
        #expect(model.sections[0].refs.count == 2)
    }

    @Test func allRefsPreservesOrder() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addInput(label: "B", value: 2)
        let c = model.addFormula(label: "C", formula: .add(.ref(a), .ref(b)))

        let refs = model.allRefs
        #expect(refs.count == 3)
        #expect(refs[0] == a)
        #expect(refs[1] == b)
        #expect(refs[2] == c)
    }

    // MARK: - Tables

    @Test func registerTable() {
        let model = ExcelModel()
        let r0c0 = model.addInput(label: "Period_0", value: 1, section: "Schedule")
        let r0c1 = model.addInput(label: "Payment_0", value: 500, section: "Schedule")
        let r1c0 = model.addInput(label: "Period_1", value: 2, section: "Schedule")
        let r1c1 = model.addInput(label: "Payment_1", value: 500, section: "Schedule")

        let table = model.registerTable(
            label: "Schedule",
            columns: ["Period", "Payment"],
            rows: [[r0c0, r0c1], [r1c0, r1c1]]
        )

        #expect(table.rowCount == 2)
        #expect(table.columns == ["Period", "Payment"])
        #expect(table.cell(row: 0, column: 0) == r0c0)
        #expect(table.cell(row: 1, column: 1) == r1c1)
    }

    @Test func tableLookupByName() throws {
        let model = ExcelModel()
        let ref = model.addInput(label: "Cell", value: 1, section: "Data")
        model.registerTable(label: "MyTable", columns: ["Col"], rows: [[ref]])

        let table = try #require(model.table(named: "MyTable"))
        #expect(table.label == "MyTable")
    }

    @Test func tableLookupMissingReturnsNil() {
        let model = ExcelModel()
        #expect(model.table(named: "Nonexistent") == nil)
    }

    // MARK: - Node Count

    @Test func emptyModelHasZeroNodes() {
        let model = ExcelModel()
        #expect(model.nodeCount == 0)
    }

    @Test func nodeCountReflectsAllTypes() throws {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addTextInput(label: "B", value: "text")
        let a = try #require(model.node(named: "A"))
        model.addFormula(label: "C", formula: .ref(a))
        model.addOutput(label: "D", formula: .number(1))
        model.addLabel("E")

        #expect(model.nodeCount == 5)
    }

    // MARK: - Sendable

    @Test func sendableConformance() async {
        let model = ExcelModel()
        model.addInput(label: "X", value: 1)
        // Crossing into a Task is what requires Sendable; the compiler is the
        // assertion. The count read on the far side shows it is the same model.
        let count = await Task { model.nodeCount }.value
        #expect(count == 1)
    }
}
