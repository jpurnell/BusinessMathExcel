import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

/// What a cell *is*, read from the shape of the graph rather than from its label.
///
/// The recognizer asks whether a sheet is a financial model and returns nothing
/// when the answer is no. This asks something every spreadsheet can answer: does
/// this cell feed anything, and is it fed by anything. Two bits, four answers, and
/// they land on the vocabulary modellers already use — parameters, objectives,
/// calculation, and the labels that are part of no computation at all.
///
/// Nothing here is fitted to a corpus. It is the definition of an edge.
@Suite struct GraphRoleTests {

    private func roles(_ build: (Worksheet) -> Void) -> [String: GraphRole] {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Model")
        build(sheet)
        let partition = GraphPartition(sheet: sheet)
        var byReference: [String: GraphRole] = [:]
        for (cell, role) in partition.roles { byReference[cell.cell.reference] = role }
        return byReference
    }

    /// The whole partition on one sheet: a rate nothing computes, a total nothing
    /// reads, the step between them, and a caption that is part of neither.
    @Test func everyCellTakesItsRoleFromItsEdges() {
        let roles = roles { sheet in
            sheet.write("Assumptions", to: "A1")
            sheet.write(0.05, to: "B1")
            sheet.write(1000.0, to: "B2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("B2")), .cellRef(CellRef("B1"))),
                        to: "B3")
            sheet.write(FormulaAST.add(.cellRef(CellRef("B3")), .cellRef(CellRef("B2"))), to: "B4")
        }

        #expect(roles["B1"] == .parameter, "a rate nothing computes, feeding something")
        #expect(roles["B2"] == .parameter)
        #expect(roles["B3"] == .calculation, "fed, and feeding")
        #expect(roles["B4"] == .objective, "computed from something, read by nothing")
        #expect(roles["A1"] == .unreachable, "a caption is part of no computation")
    }

    /// A number can be unreachable too. What makes a cell a parameter is that
    /// something reads it, not that it holds a figure.
    @Test func aFigureNothingReadsIsUnreachable() {
        let roles = roles { sheet in
            sheet.write(42.0, to: "D9")
            sheet.write(1.0, to: "B1")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("B1")), .number(2)), to: "B2")
        }

        #expect(roles["D9"] == .unreachable, "a figure in no computation is still orphaned")
        #expect(roles["B1"] == .parameter)
        #expect(roles["B2"] == .objective)
    }

    /// Every populated cell gets a role. There is no residue here and no refusal —
    /// that is the difference between this and the recognizer.
    @Test func everyPopulatedCellIsClassified() {
        let roles = roles { sheet in
            sheet.write("Title", to: "A1")
            sheet.write(1.0, to: "B1")
            sheet.write(FormulaAST.add(.cellRef(CellRef("B1")), .number(1)), to: "B2")
            sheet.write(FormulaAST.add(.cellRef(CellRef("B2")), .number(1)), to: "B3")
        }
        #expect(roles.count == 4, "Got: \(roles)")
    }

    /// A cycle does not stop a cell having a role. Both cells are fed and feeding,
    /// so both are calculation — which is what they are.
    @Test func cellsInACycleStillTakeRoles() {
        let roles = roles { sheet in
            sheet.write(FormulaAST.add(.cellRef(CellRef("B2")), .number(1)), to: "B1")
            sheet.write(FormulaAST.add(.cellRef(CellRef("B1")), .number(1)), to: "B2")
        }

        #expect(roles["B1"] == .calculation)
        #expect(roles["B2"] == .calculation)
    }
}
