import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

/// Splitting a formula by how far back it reaches.
///
/// A `ModelDefinition` formula is period-local: it reads accounts in the period
/// being evaluated and never another. A spreadsheet formula routinely reaches one
/// column left. The offset along the period axis is that reach, and it is
/// mechanical — the grid knows where every cell sits — so a formula can be split
/// into the part that stays and the part that becomes a rollforward.
@Suite struct LagDecompositionTests {

    /// Years across C..E, so the period columns are C, D, E.
    private func sheet(
        names: [String: CellRef] = [:],
        _ build: (Worksheet) -> Void
    ) -> (SheetGrid, PeriodAxis) {
        let wb = Workbook()
        let sheet = wb.addSheet(name: "Model")
        sheet.write("2024", to: "C1")
        sheet.write("2025", to: "D1")
        sheet.write("2026", to: "E1")
        build(sheet)
        let grid = SheetGrid.build(
            from: ModelImporter.importSheet(sheet), namedCells: names)
        guard let axis = PeriodAxis.build(from: grid).axis else {
            preconditionFailure("the fixture always has an axis")
        }
        return (grid, axis)
    }

    // MARK: - Lag zero

    @Test func aFormulaReadingItsOwnPeriodHasNoLag() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Cost", to: "A3")
            sheet.write("Profit", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(100.0, to: "\(column)2")
                sheet.write(40.0, to: "\(column)3")
                sheet.write(
                    FormulaAST.subtract(
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("\(column)3"))),
                    to: "\(column)4")
            }
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        #expect(split.rollforwards.isEmpty, "same period, so nothing carries")
        #expect(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
    }

    // MARK: - Lag one

    @Test func aSelfReferenceOnePeriodBackBecomesARollforward() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(1.15)), to: "D2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("D2")), .number(1.15)), to: "E2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        #expect(split.rollforwards.count == 1, "one reach back, one carry")
        #expect(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
    }

    @Test func theCarriedReferenceIsRewrittenToItsOpeningAccount() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(FormulaAST.multiply(.cellRef(CellRef("C2")), .number(1.15)), to: "D2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        let carry = try #require(split.rollforwards.first)
        #expect(carry.opening != carry.closing, "an account cannot open at its own close in the same period")
        #expect(split.formula.contains(carry.opening), "the period-local formula reads the opening account, not the prior cell")
    }

    // MARK: - Mixed

    @Test func aFormulaReachingBothWaysSplits() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Cash", to: "A2")
            sheet.write("Flow", to: "A3")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)3") }
            sheet.write(100.0, to: "C2")
            // D2 = C2 + D3 — one term reaches back, one stays.
            sheet.write(
                FormulaAST.add(.cellRef(CellRef("C2")), .cellRef(CellRef("D3"))), to: "D2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        #expect(split.rollforwards.count == 1, "only the lagged term carries")
        #expect(split.diagnostics.isEmpty)
        #expect(split.formula.contains("Flow"), "the same-period term survives by name")
    }

    // MARK: - Off the axis

    @Test func aReferenceOffThePeriodAxisIsNotALag() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Growth", to: "A6")
            sheet.write(0.15, to: "B6")
            sheet.write("Revenue", to: "A2")
            // D2 = B6 * 100 — B is not a period column, so B6 is a scalar input.
            sheet.write(
                FormulaAST.multiply(.cellRef(CellRef("B6")), .number(100)), to: "D2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D2"), in: grid, axis: axis))
        #expect(split.rollforwards.isEmpty, "a scalar is constant, not carried")
        #expect(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
    }

    // MARK: - Refusals

    @Test func aReachOfTwoPeriodsIsRefused() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            // E2 = C2 — two columns back. Wharton needs no such thing, and a
            // rollforward cannot express it.
            sheet.write(FormulaAST.cellRef(CellRef("C2")), to: "E2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("E2"), in: grid, axis: axis))
        #expect(split.diagnostics.map(\.code) == [.unsupportedLag])
        #expect(split.rollforwards.isEmpty, "and it is not quietly treated as lag 1")
    }

    @Test func aForwardReferenceIsRefused() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "D2")
            sheet.write(110.0, to: "E2")
            // C2 = D2 — reading the future.
            sheet.write(FormulaAST.cellRef(CellRef("D2")), to: "C2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("C2"), in: grid, axis: axis))
        #expect(split.diagnostics.map(\.code) == [.unsupportedLag])
    }

    @Test func aRefusalNamesTheCellAndTheReach() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write(FormulaAST.cellRef(CellRef("C2")), to: "E2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("E2"), in: grid, axis: axis))
        let diagnostic = try #require(split.diagnostics.first)
        #expect(diagnostic.cell == CellRef("E2"))
        #expect(diagnostic.message.contains("2"), "Got: \(diagnostic.message)")
    }

    // MARK: - Pinned references

    @Test func aPinnedReferenceIsAnAssumptionNotACarry() throws {
        // `$B$6` names the same cell from every period, so it is a rate, not last
        // period's anything. Reading the `$` is the difference between a
        // rollforward and a constant — and getting it wrong turns an interest rate
        // into a balance that carries.
        let (grid, axis) = sheet { sheet in
            sheet.write("Rate", to: "A6")
            sheet.write(0.1, to: "B6")
            sheet.write("Debt", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write("Interest", to: "A3")
            for column in ["C", "D", "E"] {
                sheet.write(
                    FormulaAST.multiply(
                        .cellRef(CellRef("\(column)2")), .cellRef(CellRef("$B$6"))),
                    to: "\(column)3")
            }
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D3"), in: grid, axis: axis))
        #expect(split.rollforwards.isEmpty, "a pinned cell carries nothing")
        #expect(split.formula.contains("Rate"))
    }

    @Test func aPinnedReferenceOnePeriodBackIsStillAnAssumption() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Base", to: "A2")
            sheet.write(100.0, to: "C2")
            sheet.write(110.0, to: "D2")
            sheet.write("Derived", to: "A3")
            // `$C$2` from D: one column left, but pinned, so it does not move.
            sheet.write(FormulaAST.cellRef(CellRef("$C$2")), to: "D3")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D3"), in: grid, axis: axis))
        #expect(split.rollforwards.isEmpty)
        #expect(split.diagnostics.isEmpty)
    }

    // MARK: - Cell ranges

    /// A range down one period column is a sum of accounts in that period.
    ///
    /// `E47 = SUM(E42:E46)` on the Wharton `ANSWER KEY` totals five rows of a cash
    /// flow build. Every one of them is an account, the range holds no time in it
    /// at all, and the whole construct is `SUM([EBITDA], [Less: Taxes], …)` — which
    /// the grammar has expressed since the function registry landed.
    @Test func aRangeWithinOnePeriodBecomesItsAccounts() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("EBITDA", to: "A2")
            sheet.write("Taxes", to: "A3")
            sheet.write("Total", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(10.0, to: "\(column)2")
                sheet.write(2.0, to: "\(column)3")
                sheet.write(
                    FormulaAST.function(
                        "SUM", [.cellRange(CellRange(from: CellRef("\(column)2"),
                                                     to: CellRef("\(column)3")))]),
                    to: "\(column)4")
            }
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        #expect(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
        #expect(split.formula == "SUM(EBITDA, Taxes)")
    }

    @Test func aRangeSkipsTheBlankRowsInsideIt() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("EBITDA", to: "A2")
            sheet.write("Taxes", to: "A4")
            sheet.write("Total", to: "A5")
            for column in ["C", "D", "E"] {
                sheet.write(10.0, to: "\(column)2")
                sheet.write(2.0, to: "\(column)4")
                sheet.write(
                    FormulaAST.function(
                        "SUM", [.cellRange(CellRange(from: CellRef("\(column)2"),
                                                     to: CellRef("\(column)4")))]),
                    to: "\(column)5")
            }
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D5"), in: grid, axis: axis))
        #expect(split.formula == "SUM(EBITDA, Taxes)", "row 3 holds nothing, and Excel's SUM passes over it")
    }

    /// A range running along the timeline is a different thing and is refused.
    ///
    /// `SUM(C2:E2)` totals one account across every period. That is an aggregate
    /// over time, not a period-local formula, and the two cannot share a
    /// translation: rendering it as `SUM(Revenue)` would read as this period's
    /// revenue and quietly drop five years.
    @Test func aRangeAlongTheTimelineIsRefused() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue", to: "A2")
            sheet.write("Total", to: "A3")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write(
                FormulaAST.function(
                    "SUM", [.cellRange(CellRange(from: CellRef("C2"), to: CellRef("E2")))]),
                to: "C3")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("C3"), in: grid, axis: axis))
        #expect(split.diagnostics.map(\.code) == [.unsupportedFormulaNode], "reported, not rendered as something that means less")
    }

    // MARK: - Named ranges

    /// A named range pointing at a cell on this sheet reads as that cell's account.
    ///
    /// The Wharton `ANSWER KEY` routes its circularity switch through one:
    /// `E36 = E54 * -1 * Circ`, where `Circ` is `'ANSWER KEY'!$M$1`. Until
    /// SwiftXLSX 0.8.0 the reference was unresolvable — the name arrived with
    /// nothing to look it up in — and the row went to residue, taking
    /// `Less: Interest` and, through it, `EBT` down with it.
    @Test func aNamedRangeResolvesThroughTheNormalReferenceRules() throws {
        let (grid, axis) = sheet(names: ["Rate": CellRef("$B$3")]) { sheet in
            sheet.write("Interest Rate", to: "A3")
            sheet.write(0.1, to: "B3")
            sheet.write("Charge", to: "A4")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write(
                FormulaAST.multiply(.cellRef(CellRef("C2")), .namedRange("Rate")), to: "C4")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("C4"), in: grid, axis: axis))
        #expect(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
        #expect(split.formula == "(C2 * [Interest Rate])", "the name resolves to B3, and B3's account is the one its row names — the name in the formula and the name of the account are different things and need not agree")
    }

    @Test func anUnknownNamedRangeIsRefused() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Charge", to: "A3")
            for column in ["C", "D", "E"] { sheet.write(10.0, to: "\(column)2") }
            sheet.write(
                FormulaAST.multiply(.cellRef(CellRef("C2")), .namedRange("Missing")), to: "C3")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("C3"), in: grid, axis: axis))
        #expect(split.diagnostics.map(\.code) == [.unsupportedFormulaNode], "a name with nothing behind it is reported, not treated as zero silently")
    }

    /// A range off the timeline is still a column of accounts.
    ///
    /// `Total Uses = SUM(L9:L10)` sits in the assumptions block, where no column
    /// is a period. What makes a range readable is that it stays in one column, so
    /// every cell in it belongs to a different account read at the same moment —
    /// not that the column happens to be a year. Requiring a period column here
    /// meant the Wharton sources-and-uses totals worked or failed according to
    /// whether their block happened to overlap the timeline's columns.
    @Test func aRangeOutsideThePeriodColumnsStillReadsAsAccounts() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Term Loan", to: "A2")
            sheet.write("Equity", to: "A3")
            sheet.write("Total Sources", to: "A4")
            sheet.write(60.0, to: "B2")
            sheet.write(40.0, to: "B3")
            sheet.write(
                FormulaAST.function(
                    "SUM", [.cellRange(CellRange(from: CellRef("B2"), to: CellRef("B3")))]),
                to: "B4")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("B4"), in: grid, axis: axis))
        #expect(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
        #expect(split.formula == "SUM([Term Loan], Equity)")
    }

    /// A text literal is not an account, and must not be rendered as one.
    ///
    /// The Wharton `ANSWER KEY` closes its sources-and-uses with
    /// `IF(L11=H11,"True",L11-H11)` — a display check that shows a word when the
    /// two agree. A model of numbers cannot hold a word. Rendering `"True"` as the
    /// bare name `True` produced a formula that read it as an *account*, which
    /// either fails to resolve or, worse, binds to a real account that happens to
    /// be spelled that way.
    @Test func aTextLiteralIsRefusedRatherThanReadAsAnAccount() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Check", to: "A2")
            sheet.write("True", to: "A3")
            for column in ["C", "D", "E"] { sheet.write(1.0, to: "\(column)3") }
            sheet.write(
                FormulaAST.function(
                    "IF",
                    [.equal(.cellRef(CellRef("C3")), .number(1)),
                     .text("True"),
                     .number(0)]),
                to: "C2")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("C2"), in: grid, axis: axis))
        #expect(split.diagnostics.map(\.code) == [.unsupportedFormulaNode])
        // Row 3 really is named `True`, which is the trap: the reference to C3
        // *should* read as that account, and the literal in the second argument
        // should not — one is a cell on that row, the other is a word.
        #expect(split.formula == "IF((True = 1.0), 0, 0.0)")
    }

    // MARK: - Held flat at the first period

    /// A row pinned to its own first period is constant, not self-defining.
    ///
    /// `F33 = $E$33` on the Wharton `ANSWER KEY`, where `E33 = D10`, is the ordinary
    /// idiom for *set this in year one and hold it*. Read cell by cell it says the
    /// row equals itself, which translated to `% margin = [% margin]` — an account
    /// defined as itself, which materializes, forms a one-account cycle, and fails
    /// as underdetermined because any value at all satisfies it.
    ///
    /// What the row actually means is the seed's own definition, repeated.
    @Test func aRowPinnedToItsOwnSeedTakesTheSeedsDefinition() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("EBITDA margin", to: "A3")
            sheet.write(0.4, to: "B3")
            sheet.write("% margin", to: "A4")
            sheet.write(FormulaAST.cellRef(CellRef("B3")), to: "C4")
            sheet.write(FormulaAST.cellRef(CellRef("$C$4")), to: "D4")
            sheet.write(FormulaAST.cellRef(CellRef("$C$4")), to: "E4")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        #expect(split.diagnostics.isEmpty, "Got: \(split.diagnostics)")
        #expect(split.formula == "[EBITDA margin]")
        #expect(split.rollforwards.isEmpty, "holding flat is not a carry")
    }

    @Test func aRowPinnedToALiteralSeedIsThatConstant() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Tax Rate", to: "A4")
            sheet.write(0.25, to: "C4")
            sheet.write(FormulaAST.cellRef(CellRef("$C$4")), to: "D4")
            sheet.write(FormulaAST.cellRef(CellRef("$C$4")), to: "E4")
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        #expect(split.formula == "0.25", "the seed states it; nothing else does")
    }

    /// A pinned reference to *another* row is unaffected.
    @Test func aPinnedReferenceToAnotherRowStillNamesThatRow() throws {
        let (grid, axis) = sheet { sheet in
            sheet.write("Revenue growth", to: "A3")
            sheet.write(0.1, to: "B3")
            sheet.write("% growth", to: "A4")
            for column in ["C", "D", "E"] {
                sheet.write(FormulaAST.cellRef(CellRef("$B$3")), to: "\(column)4")
            }
        }

        let split = try #require(LagDecomposition.decompose(cell: CellRef("D4"), in: grid, axis: axis))
        #expect(split.formula == "[Revenue growth]")
    }
}
