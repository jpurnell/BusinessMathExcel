import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX
import Foundation

final class AmortizationTranslatorTests: XCTestCase {

    private func makeSampleSchedule() -> AmortizationSchedule {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let maturity = calendar.date(from: DateComponents(year: 2025, month: 4, day: 1))!

        let instrument = DebtInstrument(
            principal: 100_000,
            interestRate: 0.06,
            startDate: start,
            maturityDate: maturity,
            paymentFrequency: .monthly,
            amortizationType: .levelPayment
        )
        return instrument.schedule()
    }

    func testTranslatorCreatesWorkbook() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(from: schedule)

        XCTAssertEqual(workbook.sheets.count, 1)
        XCTAssertEqual(workbook.sheets.first?.name, "Amortization Schedule")
    }

    func testTranslatorWritesHeaders() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(from: schedule)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(sheet.cell(at: "A1"), .text("Period"))
        XCTAssertEqual(sheet.cell(at: "B1"), .text("Beginning Balance"))
        XCTAssertEqual(sheet.cell(at: "C1"), .text("Payment"))
        XCTAssertEqual(sheet.cell(at: "D1"), .text("Principal"))
        XCTAssertEqual(sheet.cell(at: "E1"), .text("Interest"))
        XCTAssertEqual(sheet.cell(at: "F1"), .text("Ending Balance"))
    }

    func testTranslatorWritesDataRows() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(from: schedule)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(schedule.periods.count, 3)

        if case .text(let label) = sheet.cell(at: "A2") {
            XCTAssertFalse(label.isEmpty, "Period label should not be empty")
        } else {
            XCTFail("A2 should be a string period label")
        }

        if case .number(let balance) = sheet.cell(at: "B2") {
            XCTAssertEqual(balance, 100_000, accuracy: 0.01)
        } else {
            XCTFail("B2 should be a number for beginning balance")
        }
    }

    func testTranslatorWritesTotalsRowWithFormulas() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(from: schedule)
        let sheet = workbook.sheets[0]

        let totalsRow = schedule.periods.count + 2
        XCTAssertEqual(sheet.cell(at: "A\(totalsRow)"), .text("Total"))

        let lastDataRow = schedule.periods.count + 1
        assertFormula(sheet, at: "C\(totalsRow)", equals: "SUM(C2:C\(lastDataRow))")
        assertFormula(sheet, at: "D\(totalsRow)", equals: "SUM(D2:D\(lastDataRow))")
        assertFormula(sheet, at: "E\(totalsRow)", equals: "SUM(E2:E\(lastDataRow))")
    }

    private func assertFormula(
        _ sheet: Worksheet, at ref: String, equals expected: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let cell = sheet.cell(at: ref), cell.isFormula,
              let ast = cell.formulaAST else {
            XCTFail("Expected formula at \(ref)", file: file, line: line)
            return
        }
        let serialized = FormulaSerializer.serialize(ast)
        XCTAssertEqual(serialized, expected, file: file, line: line)
    }

    func testTranslatorSavesToFile() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(from: schedule)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("amort_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testTranslatorWithCustomSheetName() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(
            from: schedule,
            sheetName: "Mortgage"
        )

        XCTAssertEqual(workbook.sheets.first?.name, "Mortgage")
    }
}
