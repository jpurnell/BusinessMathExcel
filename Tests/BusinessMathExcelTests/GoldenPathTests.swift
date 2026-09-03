import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// The proposal's validation trace, end to end.
///
/// Every other test in this suite checks a stage against numbers we computed
/// ourselves, which proves the stages agree with each other and nothing more. This
/// one checks the whole pipeline against numbers **Excel** produced: a worksheet
/// with a literal and two growth formulas, whose displayed values are 1,000,000 /
/// 1,150,000 / 1,322,500. Read the sheet, recognize it, materialize it, run it,
/// and the three figures must come back — same order, same account, same sheet.
///
/// A pipeline can be entirely self-consistent and still be wrong by one period.
/// That is precisely the failure this test exists to catch, and it did catch it:
/// naming the derived account after the row put every figure one period early.
final class GoldenPathTests: XCTestCase {

    /// `B6 = "Revenue"`, `C6 = 1000000`, `D6 = C6*1.15`, `E6 = D6*1.15`.
    private func validationTrace() -> Worksheet? {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "Forecast")
        sheet.write("2024", to: "C5")
        sheet.write("2025", to: "D5")
        sheet.write("2026", to: "E5")
        sheet.write("Revenue", to: "B6")
        sheet.write(1_000_000.0, to: "C6")
        sheet.write(FormulaAST.multiply(.cellRef(CellRef("C6")), .number(1.15)), to: "D6")
        sheet.write(FormulaAST.multiply(.cellRef(CellRef("D6")), .number(1.15)), to: "E6")
        return workbook.sheets.first
    }

    /// Excel's own values for `C6:E6`.
    private let excelValues: [Double] = [1_000_000, 1_150_000, 1_322_500]

    func testTheValidationTraceReproducesExcelsNumbers() throws {
        let sheet = try XCTUnwrap(validationTrace())
        let recognition = ExcelRecognizer.recognize(sheet)

        // Notes are not problems. A hand-built fixture carries no number formats,
        // so unit inference reports that it found none — which is a fact about the
        // fixture, not a finding about the row.
        XCTAssertEqual(
            recognition.diagnostics.filter { $0.severity != .info }.map(\.code.rawValue), [],
            "a three-cell growth row is the simplest thing this recognizer handles"
        )
        XCTAssertTrue(
            recognition.model.residue.isEmpty,
            "nothing should be left over. Got: \(recognition.model.residue.map(\.label))"
        )
        XCTAssertEqual(
            recognition.coverage.recognizedCells, recognition.coverage.populatedCells,
            "every populated cell is accounted for"
        )

        let materialized = try ModelMaterializer.build(from: recognition.model)
        let driver = PeriodDriver(
            definition: materialized.definition, rollforwards: materialized.rollforwards)
        let evaluated = try driver.run(over: materialized.periods)

        let revenue = try XCTUnwrap(
            evaluated["Revenue"],
            "the row is labelled Revenue, so the series carrying its numbers is Revenue. "
                + "Got: \(evaluated.keys.sorted())"
        )
        let values = revenue.valuesArray
        XCTAssertEqual(values.count, excelValues.count)
        for (actual, expected) in zip(values, excelValues) {
            XCTAssertEqual(actual, expected, accuracy: 1e-6)
        }
    }

    /// The rename is load-bearing, so it gets its own assertion rather than riding
    /// along on the values above.
    func testTheRowsLabelStaysOnTheSeriesHoldingItsNumbers() throws {
        let sheet = try XCTUnwrap(validationTrace())
        let plan = ExcelRecognizer.recognize(sheet).model

        let carry = try XCTUnwrap(plan.rollforwards.first)
        XCTAssertEqual(carry.opening, "Revenue", "the sheet's figures are the openings")
        XCTAssertEqual(carry.closing, "Revenue Closing")
        XCTAssertEqual(carry.seed, 1_000_000, accuracy: 1e-9, "seeded from C6, not invented")

        let account = try XCTUnwrap(plan.accounts.first)
        XCTAssertEqual(account.name, "Revenue Closing")
        XCTAssertEqual(account.formula, "(Revenue * 1.15)")
    }
}
