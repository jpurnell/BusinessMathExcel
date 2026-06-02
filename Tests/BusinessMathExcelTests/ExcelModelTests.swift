import XCTest
@testable import BusinessMathExcel

final class ExcelModelTests: XCTestCase {

    // MARK: - Adding Nodes

    func testAddInput() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Principal", value: 250_000)

        XCTAssertEqual(model.nodeCount, 1)
        XCTAssertEqual(ref.label, "Principal")
        if case .input(let value) = model.kind(of: ref) {
            XCTAssertEqual(value, 250_000, accuracy: 0.01)
        } else {
            XCTFail("Expected input node")
        }
    }

    func testAddTextInput() {
        let model = ExcelModel()
        let ref = model.addTextInput(label: "Title", value: "Loan Schedule")

        XCTAssertEqual(model.nodeCount, 1)
        XCTAssertEqual(model.kind(of: ref), .textInput("Loan Schedule"))
    }

    func testAddFormula() {
        let model = ExcelModel()
        let rate = model.addInput(label: "Annual Rate", value: 0.065)
        let formula = NodeFormula.divide(.ref(rate), .number(12))
        let monthly = model.addFormula(label: "Monthly Rate", formula: formula)

        XCTAssertEqual(model.nodeCount, 2)
        XCTAssertEqual(model.kind(of: monthly), .formula(formula))
    }

    func testAddOutput() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 10)
        let b = model.addInput(label: "B", value: 20)
        let sumFormula = NodeFormula.add(.ref(a), .ref(b))
        let result = model.addOutput(label: "Total", formula: sumFormula)

        XCTAssertEqual(model.nodeCount, 3)
        XCTAssertEqual(model.kind(of: result), .output(sumFormula))
    }

    func testAddLabel() {
        let model = ExcelModel()
        let ref = model.addLabel("Summary")

        XCTAssertEqual(model.nodeCount, 1)
        XCTAssertEqual(model.kind(of: ref), .label("Summary"))
    }

    // MARK: - Lookup

    func testNodeLookupByName() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Principal", value: 100_000)

        XCTAssertEqual(model.node(named: "Principal"), ref)
    }

    func testNodeLookupMissingReturnsNil() {
        let model = ExcelModel()
        XCTAssertNil(model.node(named: "Nonexistent"))
    }

    func testKindOfUnknownRefReturnsNil() {
        let model = ExcelModel()
        let unknown = NodeRef(label: "Ghost")
        XCTAssertNil(model.kind(of: unknown))
    }

    // MARK: - Sections

    func testDefaultSections() {
        let model = ExcelModel()
        model.addInput(label: "Rate", value: 0.05)
        model.addFormula(label: "Monthly", formula: .number(0.05 / 12))
        model.addOutput(label: "Result", formula: .number(100))

        let sectionNames = model.sections.map(\.name)
        XCTAssertEqual(sectionNames, ["Inputs", "Calculations", "Results"])
    }

    func testCustomSection() {
        let model = ExcelModel()
        model.addInput(label: "Price", value: 50, section: "Product")
        model.addInput(label: "Quantity", value: 100, section: "Product")

        XCTAssertEqual(model.sections.count, 1)
        XCTAssertEqual(model.sections[0].name, "Product")
        XCTAssertEqual(model.sections[0].refs.count, 2)
    }

    func testAllRefsPreservesOrder() {
        let model = ExcelModel()
        let a = model.addInput(label: "A", value: 1)
        let b = model.addInput(label: "B", value: 2)
        let c = model.addFormula(label: "C", formula: .add(.ref(a), .ref(b)))

        let refs = model.allRefs
        XCTAssertEqual(refs.count, 3)
        XCTAssertEqual(refs[0], a)
        XCTAssertEqual(refs[1], b)
        XCTAssertEqual(refs[2], c)
    }

    // MARK: - Tables

    func testRegisterTable() {
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

        XCTAssertEqual(table.rowCount, 2)
        XCTAssertEqual(table.columns, ["Period", "Payment"])
        XCTAssertEqual(table.cell(row: 0, column: 0), r0c0)
        XCTAssertEqual(table.cell(row: 1, column: 1), r1c1)
    }

    func testTableLookupByName() {
        let model = ExcelModel()
        let ref = model.addInput(label: "Cell", value: 1, section: "Data")
        model.registerTable(label: "MyTable", columns: ["Col"], rows: [[ref]])

        let table = model.table(named: "MyTable")
        XCTAssertNotNil(table)
        XCTAssertEqual(table?.label, "MyTable")
    }

    func testTableLookupMissingReturnsNil() {
        let model = ExcelModel()
        XCTAssertNil(model.table(named: "Nonexistent"))
    }

    // MARK: - Node Count

    func testEmptyModelHasZeroNodes() {
        let model = ExcelModel()
        XCTAssertEqual(model.nodeCount, 0)
    }

    func testNodeCountReflectsAllTypes() {
        let model = ExcelModel()
        model.addInput(label: "A", value: 1)
        model.addTextInput(label: "B", value: "text")
        let a = model.node(named: "A")!
        model.addFormula(label: "C", formula: .ref(a))
        model.addOutput(label: "D", formula: .number(1))
        model.addLabel("E")

        XCTAssertEqual(model.nodeCount, 5)
    }

    // MARK: - Sendable

    func testSendableConformance() {
        let model = ExcelModel()
        model.addInput(label: "X", value: 1)
        let expectation = expectation(description: "sendable")
        Task {
            _ = model.nodeCount
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}
