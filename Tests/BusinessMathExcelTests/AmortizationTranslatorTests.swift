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

        XCTAssertEqual(sheet.cell(at: "A1"), .string("Period"))
        XCTAssertEqual(sheet.cell(at: "B1"), .string("Beginning Balance"))
        XCTAssertEqual(sheet.cell(at: "C1"), .string("Payment"))
        XCTAssertEqual(sheet.cell(at: "D1"), .string("Principal"))
        XCTAssertEqual(sheet.cell(at: "E1"), .string("Interest"))
        XCTAssertEqual(sheet.cell(at: "F1"), .string("Ending Balance"))
    }

    func testTranslatorWritesDataRows() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(from: schedule)
        let sheet = workbook.sheets[0]

        XCTAssertEqual(schedule.periods.count, 3)

        if case .string(let label) = sheet.cell(at: "A2") {
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

    func testTranslatorWritesTotalsRow() throws {
        let schedule = makeSampleSchedule()
        let workbook = AmortizationTranslator.workbook(from: schedule)
        let sheet = workbook.sheets[0]

        let totalsRow = schedule.periods.count + 2
        let totalsRef = "A\(totalsRow)"

        XCTAssertEqual(sheet.cell(at: totalsRef), .string("Total"))
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
