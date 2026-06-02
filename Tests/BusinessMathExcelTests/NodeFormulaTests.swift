import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class NodeFormulaTests: XCTestCase {

    // MARK: - Leaf Resolution

    func testResolveRef() throws {
        let node = NodeRef(label: "Revenue")
        let cell = CellRef(column: 1, row: 1)
        let formula = NodeFormula.ref(node)

        let ast = try formula.resolve(using: [node: cell])
        XCTAssertEqual(ast, .cellRef(cell))
    }

    func testResolveNumber() throws {
        let ast = try NodeFormula.number(42).resolve(using: [:])
        XCTAssertEqual(ast, .number(42))
    }

    func testResolveText() throws {
        let ast = try NodeFormula.text("hello").resolve(using: [:])
        XCTAssertEqual(ast, .text("hello"))
    }

    func testResolveBool() throws {
        let ast = try NodeFormula.bool(true).resolve(using: [:])
        XCTAssertEqual(ast, .bool(true))
    }

    // MARK: - Arithmetic Resolution

    func testResolveAdd() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)
        let mapping: [NodeRef: CellRef] = [a: cellA, b: cellB]

        let formula = NodeFormula.add(.ref(a), .ref(b))
        let ast = try formula.resolve(using: mapping)
        XCTAssertEqual(ast, .add(.cellRef(cellA), .cellRef(cellB)))
    }

    func testResolveSubtract() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)

        let ast = try NodeFormula.subtract(.ref(a), .ref(b))
            .resolve(using: [a: cellA, b: cellB])
        XCTAssertEqual(ast, .subtract(.cellRef(cellA), .cellRef(cellB)))
    }

    func testResolveMultiply() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)

        let ast = try NodeFormula.multiply(.ref(a), .ref(b))
            .resolve(using: [a: cellA, b: cellB])
        XCTAssertEqual(ast, .multiply(.cellRef(cellA), .cellRef(cellB)))
    }

    func testResolveDivide() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)

        let ast = try NodeFormula.divide(.ref(a), .ref(b))
            .resolve(using: [a: cellA, b: cellB])
        XCTAssertEqual(ast, .divide(.cellRef(cellA), .cellRef(cellB)))
    }

    func testResolveNegate() throws {
        let a = NodeRef(label: "A")
        let cellA = CellRef(column: 1, row: 1)

        let ast = try NodeFormula.negate(.ref(a)).resolve(using: [a: cellA])
        XCTAssertEqual(ast, .negate(.cellRef(cellA)))
    }

    // MARK: - Function Resolution

    func testResolveFunction() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 1, row: 2)

        let formula = NodeFormula.function("SUM", [.ref(a), .ref(b)])
        let ast = try formula.resolve(using: [a: cellA, b: cellB])
        XCTAssertEqual(ast, .function("SUM", [.cellRef(cellA), .cellRef(cellB)]))
    }

    func testResolveNestedFormula() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let c = NodeRef(label: "C")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 1, row: 2)
        let cellC = CellRef(column: 1, row: 3)
        let mapping: [NodeRef: CellRef] = [a: cellA, b: cellB, c: cellC]

        let formula = NodeFormula.multiply(
            .add(.ref(a), .ref(b)),
            .ref(c)
        )
        let ast = try formula.resolve(using: mapping)
        XCTAssertEqual(
            ast,
            .multiply(.add(.cellRef(cellA), .cellRef(cellB)), .cellRef(cellC))
        )
    }

    // MARK: - Error Handling

    func testDanglingReferenceThrows() {
        let orphan = NodeRef(label: "Orphan")
        let formula = NodeFormula.ref(orphan)

        XCTAssertThrowsError(try formula.resolve(using: [:])) { error in
            guard let resError = error as? ResolutionError else {
                XCTFail("Expected ResolutionError")
                return
            }
            if case .danglingReference(let ref) = resError {
                XCTAssertEqual(ref, orphan)
            } else {
                XCTFail("Expected danglingReference")
            }
        }
    }

    func testDanglingReferenceInNestedFormula() {
        let valid = NodeRef(label: "Valid")
        let orphan = NodeRef(label: "Orphan")
        let cell = CellRef(column: 1, row: 1)

        let formula = NodeFormula.add(.ref(valid), .ref(orphan))
        XCTAssertThrowsError(try formula.resolve(using: [valid: cell]))
    }

    // MARK: - Convenience Builders

    func testSumBuilder() {
        let a = NodeFormula.number(1)
        let b = NodeFormula.number(2)
        let sum = NodeFormula.sum([a, b])

        if case .function(let name, let args) = sum {
            XCTAssertEqual(name, "SUM")
            XCTAssertEqual(args.count, 2)
        } else {
            XCTFail("Expected function case")
        }
    }

    func testPmtBuilder() {
        let pmt = NodeFormula.pmt(
            rate: .number(0.05),
            nper: .number(360),
            pv: .number(250_000)
        )
        if case .function(let name, let args) = pmt {
            XCTAssertEqual(name, "PMT")
            XCTAssertEqual(args.count, 3)
        } else {
            XCTFail("Expected function case")
        }
    }

    func testIpmtBuilder() {
        let ipmt = NodeFormula.ipmt(
            rate: .number(0.005),
            per: .number(1),
            nper: .number(360),
            pv: .number(250_000)
        )
        if case .function(let name, let args) = ipmt {
            XCTAssertEqual(name, "IPMT")
            XCTAssertEqual(args.count, 4)
        } else {
            XCTFail("Expected function case")
        }
    }

    func testPpmtBuilder() {
        let ppmt = NodeFormula.ppmt(
            rate: .number(0.005),
            per: .number(1),
            nper: .number(360),
            pv: .number(250_000)
        )
        if case .function(let name, let args) = ppmt {
            XCTAssertEqual(name, "PPMT")
            XCTAssertEqual(args.count, 4)
        } else {
            XCTFail("Expected function case")
        }
    }

    func testNpvBuilder() {
        let npv = NodeFormula.npv(
            rate: .number(0.10),
            values: [.number(-1000), .number(300), .number(400), .number(500)]
        )
        if case .function(let name, let args) = npv {
            XCTAssertEqual(name, "NPV")
            XCTAssertEqual(args.count, 5)
        } else {
            XCTFail("Expected function case")
        }
    }

    func testIrrBuilder() {
        let irr = NodeFormula.irr([.number(-1000), .number(300), .number(400), .number(500)])
        if case .function(let name, let args) = irr {
            XCTAssertEqual(name, "IRR")
            XCTAssertEqual(args.count, 4)
        } else {
            XCTFail("Expected function case")
        }
    }

    func testPmtBuilderResolvesToFormulaAST() throws {
        let rate = NodeRef(label: "Rate")
        let nper = NodeRef(label: "Nper")
        let pv = NodeRef(label: "PV")
        let cellRate = CellRef(column: 2, row: 1)
        let cellNper = CellRef(column: 2, row: 2)
        let cellPV = CellRef(column: 2, row: 3)

        let pmt = NodeFormula.pmt(rate: .ref(rate), nper: .ref(nper), pv: .ref(pv))
        let ast = try pmt.resolve(using: [rate: cellRate, nper: cellNper, pv: cellPV])

        XCTAssertEqual(
            ast,
            .function("PMT", [.cellRef(cellRate), .cellRef(cellNper), .cellRef(cellPV)])
        )
    }
}
