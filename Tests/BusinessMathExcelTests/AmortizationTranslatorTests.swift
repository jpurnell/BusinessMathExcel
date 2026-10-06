import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX
import Foundation

@Suite struct AmortizationTranslatorTests {

    private func makeSampleSchedule() throws -> AmortizationSchedule {
        let start = try #require(TestCalendar.noon(year: 2025, month: 1, day: 1))
        let maturity = try #require(TestCalendar.noon(year: 2025, month: 4, day: 1))

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

    @Test func translatorCreatesWorkbook() throws {
        let schedule = try makeSampleSchedule()
        let workbook = legacy.amortizationWorkbook(from: schedule)

        #expect(workbook.sheets.count == 1)
        #expect(workbook.sheets.first?.name == "Amortization Schedule")
    }

    @Test func translatorWritesHeaders() throws {
        let schedule = try makeSampleSchedule()
        let workbook = legacy.amortizationWorkbook(from: schedule)
        let sheet = workbook.sheets[0]

        #expect(sheet.cell(at: "A1") == .text("Period"))
        #expect(sheet.cell(at: "B1") == .text("Beginning Balance"))
        #expect(sheet.cell(at: "C1") == .text("Payment"))
        #expect(sheet.cell(at: "D1") == .text("Principal"))
        #expect(sheet.cell(at: "E1") == .text("Interest"))
        #expect(sheet.cell(at: "F1") == .text("Ending Balance"))
    }

    @Test func translatorWritesDataRows() throws {
        let schedule = try makeSampleSchedule()
        let workbook = legacy.amortizationWorkbook(from: schedule)
        let sheet = workbook.sheets[0]

        #expect(schedule.periods.count == 3)

        if case .text(let label) = sheet.cell(at: "A2") {
            #expect(!label.isEmpty, "Period label should not be empty")
        } else {
            Issue.record("A2 should be a string period label")
        }

        if case .number(let balance) = sheet.cell(at: "B2") {
            #expect(abs(balance - 100_000) <= 0.01)
        } else {
            Issue.record("B2 should be a number for beginning balance")
        }
    }

    @Test func translatorWritesTotalsRowWithFormulas() throws {
        let schedule = try makeSampleSchedule()
        let workbook = legacy.amortizationWorkbook(from: schedule)
        let sheet = workbook.sheets[0]

        let totalsRow = schedule.periods.count + 2
        #expect(sheet.cell(at: "A\(totalsRow)") == .text("Total"))

        let lastDataRow = schedule.periods.count + 1
        assertFormula(sheet, at: "C\(totalsRow)", equals: "SUM(C2:C\(lastDataRow))")
        assertFormula(sheet, at: "D\(totalsRow)", equals: "SUM(D2:D\(lastDataRow))")
        assertFormula(sheet, at: "E\(totalsRow)", equals: "SUM(E2:E\(lastDataRow))")
    }

    private func assertFormula(
        _ sheet: Worksheet, at ref: String, equals expected: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let cell = sheet.cell(at: ref), cell.isFormula,
              let ast = cell.formulaAST else {
            Issue.record("Expected formula at \(ref)", sourceLocation: sourceLocation)
            return
        }
        let serialized = FormulaSerializer.serialize(ast)
        #expect(serialized == expected, sourceLocation: sourceLocation)
    }

    @Test func translatorSavesToFile() throws {
        let schedule = try makeSampleSchedule()
        let workbook = legacy.amortizationWorkbook(from: schedule)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("amort_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try workbook.save(to: url)
        #expect(try url.checkResourceIsReachable())
    }

    @Test func translatorWithCustomSheetName() throws {
        let schedule = try makeSampleSchedule()
        let workbook = legacy.amortizationWorkbook(
            from: schedule,
            sheetName: "Mortgage"
        )

        #expect(workbook.sheets.first?.name == "Mortgage")
    }
}
