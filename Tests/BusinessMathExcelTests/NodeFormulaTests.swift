import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct NodeFormulaTests {

    // MARK: - Leaf Resolution

    @Test func resolveRef() throws {
        let node = NodeRef(label: "Revenue")
        let cell = CellRef(column: 1, row: 1)
        let formula = NodeFormula.ref(node)

        let ast = try formula.resolve(using: [node: cell])
        #expect(ast == .cellRef(cell))
    }

    @Test func resolveNumber() throws {
        let ast = try NodeFormula.number(42).resolve(using: [:])
        #expect(ast == .number(42))
    }

    @Test func resolveText() throws {
        let ast = try NodeFormula.text("hello").resolve(using: [:])
        #expect(ast == .text("hello"))
    }

    @Test func resolveBool() throws {
        let ast = try NodeFormula.bool(true).resolve(using: [:])
        #expect(ast == .bool(true))
    }

    // MARK: - Arithmetic Resolution

    @Test func resolveAdd() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)
        let mapping: [NodeRef: CellRef] = [a: cellA, b: cellB]

        let formula = NodeFormula.add(.ref(a), .ref(b))
        let ast = try formula.resolve(using: mapping)
        #expect(ast == .add(.cellRef(cellA), .cellRef(cellB)))
    }

    @Test func resolveSubtract() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)

        let ast = try NodeFormula.subtract(.ref(a), .ref(b))
            .resolve(using: [a: cellA, b: cellB])
        #expect(ast == .subtract(.cellRef(cellA), .cellRef(cellB)))
    }

    @Test func resolveMultiply() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)

        let ast = try NodeFormula.multiply(.ref(a), .ref(b))
            .resolve(using: [a: cellA, b: cellB])
        #expect(ast == .multiply(.cellRef(cellA), .cellRef(cellB)))
    }

    @Test func resolveDivide() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 2, row: 1)

        let ast = try NodeFormula.divide(.ref(a), .ref(b))
            .resolve(using: [a: cellA, b: cellB])
        #expect(ast == .divide(.cellRef(cellA), .cellRef(cellB)))
    }

    @Test func resolveNegate() throws {
        let a = NodeRef(label: "A")
        let cellA = CellRef(column: 1, row: 1)

        let ast = try NodeFormula.negate(.ref(a)).resolve(using: [a: cellA])
        #expect(ast == .negate(.cellRef(cellA)))
    }

    // MARK: - Function Resolution

    @Test func resolveFunction() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)
        let cellB = CellRef(column: 1, row: 2)

        let formula = NodeFormula.function("SUM", [.ref(a), .ref(b)])
        let ast = try formula.resolve(using: [a: cellA, b: cellB])
        #expect(ast == .function("SUM", [.cellRef(cellA), .cellRef(cellB)]))
    }

    @Test func resolveNestedFormula() throws {
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
        #expect(ast == .multiply(.add(.cellRef(cellA), .cellRef(cellB)), .cellRef(cellC)))
    }

    // MARK: - Error Handling

    @Test func danglingReferenceThrows() {
        let orphan = NodeRef(label: "Orphan")
        let formula = NodeFormula.ref(orphan)

        if let error = #expect(throws: (any Error).self, performing: { try formula.resolve(using: [:]) }) {
            guard let resError = error as? ResolutionError else {
                Issue.record("Expected ResolutionError")
                return
            }
            if case .danglingReference(let ref) = resError {
                #expect(ref == orphan)
            } else {
                Issue.record("Expected danglingReference")
            }
        }
    }

    @Test func danglingReferenceInNestedFormula() {
        let valid = NodeRef(label: "Valid")
        let orphan = NodeRef(label: "Orphan")
        let cell = CellRef(column: 1, row: 1)

        let formula = NodeFormula.add(.ref(valid), .ref(orphan))
        #expect(throws: (any Error).self) { try formula.resolve(using: [valid: cell]) }
    }

    // MARK: - Convenience Builders

    @Test func sumBuilder() {
        let a = NodeFormula.number(1)
        let b = NodeFormula.number(2)
        let sum = NodeFormula.sum([a, b])

        if case .function(let name, let args) = sum {
            #expect(name == "SUM")
            #expect(args.count == 2)
        } else {
            Issue.record("Expected function case")
        }
    }

    @Test func pmtBuilder() {
        let pmt = NodeFormula.pmt(
            rate: .number(0.05),
            nper: .number(360),
            pv: .number(250_000)
        )
        if case .function(let name, let args) = pmt {
            #expect(name == "PMT")
            #expect(args.count == 3)
        } else {
            Issue.record("Expected function case")
        }
    }

    @Test func ipmtBuilder() {
        let ipmt = NodeFormula.ipmt(
            rate: .number(0.005),
            per: .number(1),
            nper: .number(360),
            pv: .number(250_000)
        )
        if case .function(let name, let args) = ipmt {
            #expect(name == "IPMT")
            #expect(args.count == 4)
        } else {
            Issue.record("Expected function case")
        }
    }

    @Test func ppmtBuilder() {
        let ppmt = NodeFormula.ppmt(
            rate: .number(0.005),
            per: .number(1),
            nper: .number(360),
            pv: .number(250_000)
        )
        if case .function(let name, let args) = ppmt {
            #expect(name == "PPMT")
            #expect(args.count == 4)
        } else {
            Issue.record("Expected function case")
        }
    }

    @Test func npvBuilder() {
        let npv = NodeFormula.npv(
            rate: .number(0.10),
            values: [.number(-1000), .number(300), .number(400), .number(500)]
        )
        if case .function(let name, let args) = npv {
            #expect(name == "NPV")
            #expect(args.count == 5)
        } else {
            Issue.record("Expected function case")
        }
    }

    @Test func irrBuilderWithLiterals() {
        let irr = NodeFormula.irr([.number(-1000), .number(300), .number(400), .number(500)])
        if case .function(let name, let args) = irr {
            #expect(name == "IRR")
            #expect(args.count == 4)
        } else {
            Issue.record("Expected function case")
        }
    }

    // MARK: - Range Resolution

    @Test func rangeResolvesToCellRange() throws {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let c = NodeRef(label: "C")
        let cellA = CellRef(column: 4, row: 5)
        let cellB = CellRef(column: 4, row: 6)
        let cellC = CellRef(column: 4, row: 7)

        let formula = NodeFormula.range([a, b, c])
        let ast = try formula.resolve(using: [a: cellA, b: cellB, c: cellC])
        #expect(ast == .cellRange(CellRange(from: cellA, to: cellC)))
    }

    @Test func rangeDanglingReferenceThrows() {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let cellA = CellRef(column: 1, row: 1)

        let formula = NodeFormula.range([a, b])
        #expect(throws: (any Error).self) { try formula.resolve(using: [a: cellA]) }
    }

    @Test func irrBuilderUsesRange() {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let irr = NodeFormula.irr([.ref(a), .ref(b)])

        if case .function(let name, let args) = irr {
            #expect(name == "IRR")
            #expect(args.count == 1)
            if case .range(let refs) = args[0] {
                #expect(refs.count == 2)
            } else {
                Issue.record("Expected range argument")
            }
        } else {
            Issue.record("Expected function case")
        }
    }

    @Test func npvBuilderUsesRange() {
        let rate = NodeFormula.number(0.10)
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "B")
        let npv = NodeFormula.npv(rate: rate, values: [.ref(a), .ref(b)])

        if case .function(let name, let args) = npv {
            #expect(name == "NPV")
            #expect(args.count == 2)
            if case .range(let refs) = args[1] {
                #expect(refs.count == 2)
            } else {
                Issue.record("Expected range as second argument")
            }
        } else {
            Issue.record("Expected function case")
        }
    }

    @Test func pmtBuilderResolvesToFormulaAST() throws {
        let rate = NodeRef(label: "Rate")
        let nper = NodeRef(label: "Nper")
        let pv = NodeRef(label: "PV")
        let cellRate = CellRef(column: 2, row: 1)
        let cellNper = CellRef(column: 2, row: 2)
        let cellPV = CellRef(column: 2, row: 3)

        let pmt = NodeFormula.pmt(rate: .ref(rate), nper: .ref(nper), pv: .ref(pv))
        let ast = try pmt.resolve(using: [rate: cellRate, nper: cellNper, pv: cellPV])

        #expect(ast == .function("PMT", [.cellRef(cellRate), .cellRef(cellNper), .cellRef(cellPV)]))
    }
}
