import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Phase 4 — a workbook whose accounts depend on each other within a period.
///
/// A revolver with a cash sweep is the standard shape: interest accrues on the
/// *average* balance, repayment is whatever cash is left after paying it, and the
/// closing balance falls by the repayment. Each of those three needs one of the
/// others, so the sheet contains a genuine circle rather than an ordering problem.
///
/// Excel resolves this with iterative calculation. The bar here is that we do the
/// same thing and get the same answer — and one number decides it. On a 120 draw
/// at 10%, a correct cyclic solve accrues **11.75**; a model that quietly breaks
/// the circle by accruing on the beginning balance instead gets **12.00**. Both
/// run, both converge, and only one is right.
final class CircularSweepTests: XCTestCase {

    /// A three-year revolver: interest on the average balance, cash-swept.
    ///
    /// ```
    ///          C(2024)  D(2025)  E(2026)
    ///   3 Cash    16.75    16.75    16.75
    ///   4 Open   120       =C7      =D7
    ///   5 Int    =0.1*(C4+C7)/2     ...
    ///   6 Repay  =C3-C5             ...
    ///   7 Close  =C4-C6             ...
    /// ```
    private func revolver(openingDebt: FormulaWriter) -> Worksheet? {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Debt")
        for (column, year) in zip(["C", "D", "E"], ["2024", "2025", "2026"]) {
            sheet.write(year, to: "\(column)2")
        }
        sheet.write("Cash Available", to: "A3")
        sheet.write("Opening Debt", to: "A4")
        sheet.write("Interest", to: "A5")
        sheet.write("Repayment", to: "A6")
        sheet.write("Closing Debt", to: "A7")

        for column in ["C", "D", "E"] { sheet.write(16.75, to: "\(column)3") }
        openingDebt(sheet)
        sheet.write(FormulaAST.cellRef(CellRef("C7")), to: "D4")
        sheet.write(FormulaAST.cellRef(CellRef("D7")), to: "E4")

        for column in ["C", "D", "E"] {
            sheet.write(
                FormulaAST.multiply(
                    .number(0.1),
                    .divide(
                        .add(.cellRef(CellRef("\(column)4")), .cellRef(CellRef("\(column)7"))),
                        .number(2))),
                to: "\(column)5")
            sheet.write(
                FormulaAST.subtract(
                    .cellRef(CellRef("\(column)3")), .cellRef(CellRef("\(column)5"))),
                to: "\(column)6")
            sheet.write(
                FormulaAST.subtract(
                    .cellRef(CellRef("\(column)4")), .cellRef(CellRef("\(column)6"))),
                to: "\(column)7")
        }
        return workbook.sheets.first
    }

    private typealias FormulaWriter = (Worksheet) -> Void

    /// The opening balance as a model states it: a hard number in year one.
    private let drawnDown: FormulaWriter = { $0.write(120.0, to: "C4") }

    // MARK: - The cycle

    func testTheSweepIsRecognizedAsExactlyOneCycle() throws {
        let sheet = try XCTUnwrap(revolver(openingDebt: drawnDown))
        let plan = ExcelRecognizer.recognize(sheet)
        XCTAssertEqual(plan.diagnostics.map(\.code.rawValue), [])

        let report = try ModelMaterializer.build(from: plan.model).definition.dependencyReport()
        XCTAssertEqual(report.cycles.count, 1, "one circle, not one per account in it")

        let cycle = try XCTUnwrap(report.cycles.first)
        XCTAssertTrue(
            cycle.accounts.contains("Interest") && cycle.accounts.contains("Closing Debt"),
            "the circle is interest against the balance it accrues on. Got: \(cycle.accounts)"
        )
    }

    // MARK: - The number that decides it

    func testYearOneInterestAccruesOnTheAverageBalance() throws {
        let sheet = try XCTUnwrap(revolver(openingDebt: drawnDown))
        let built = try ModelMaterializer.build(from: ExcelRecognizer.recognize(sheet).model)
        let evaluated = try PeriodDriver(
            definition: built.definition, rollforwards: built.rollforwards
        ).run(over: built.periods)

        let interest = try XCTUnwrap(evaluated["Interest"]?.valuesArray.first)
        XCTAssertEqual(
            interest, 11.75, accuracy: 1e-9,
            "120 opening, 115 closing, 117.5 average, 10% — 11.75. Accruing on the "
                + "beginning balance instead gives 12.00, which is what breaking the cycle "
                + "by timing looks like from the outside: a model that runs and converges"
        )
        XCTAssertEqual(
            try XCTUnwrap(evaluated["Closing Debt"]?.valuesArray.first), 115, accuracy: 1e-9,
            "and the balance the interest was accrued on is the one that closes"
        )
    }

    func testTheCarrySeedsFromTheRowsOwnFirstPeriod() throws {
        let sheet = try XCTUnwrap(revolver(openingDebt: drawnDown))
        let carry = try XCTUnwrap(ExcelRecognizer.recognize(sheet).model.rollforwards.first)
        // D4 = C7, but the opening balance is the 120 typed into C4. Seeding from
        // the referenced cell reads a formula that has no prior period to compute
        // from, which is where the zero came from.
        XCTAssertEqual(carry.seedCell, CellRef("C4"))
        XCTAssertEqual(carry.seed, 120, accuracy: 1e-9)
    }

    // MARK: - When the sheet does not say

    func testACarryWithNoStatedOpeningIsRefused() throws {
        let sheet = try XCTUnwrap(
            revolver(openingDebt: {
                // C4 computed, and no cached value for it — the file states no
                // opening balance anywhere.
                $0.write(FormulaAST.multiply(.cellRef(CellRef("C3")), .number(2)), to: "C4")
            }))
        let plan = ExcelRecognizer.recognize(sheet)

        XCTAssertTrue(
            plan.diagnostics.contains { $0.code == .unseededCarry },
            "an unstated opening is reported, not defaulted. Got: "
                + "\(plan.diagnostics.map(\.code.rawValue))"
        )
        XCTAssertFalse(
            plan.model.rollforwards.contains { $0.seed == 0 },
            "and no rollforward is seeded with an invented zero"
        )
    }
}
