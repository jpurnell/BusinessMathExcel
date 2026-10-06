import Foundation
import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

@Suite struct AmortizationModelBuilderTests {

    private let principal = 100_000.0
    private let annualRate = 0.06
    private let termMonths = 3

    private func makeModel() -> ExcelModel {
        AmortizationModelBuilder.build(
            principal: principal,
            annualRate: annualRate,
            termMonths: termMonths
        )
    }

    // MARK: - Input Nodes

    @Test func hasPrincipalInput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Principal"))
        if case .input(let value) = model.kind(of: ref) {
            #expect(abs(value - principal) <= 0.01)
        } else {
            Issue.record("Expected input node")
        }
    }

    @Test func hasAnnualRateInput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Annual Rate"))
        if case .input(let value) = model.kind(of: ref) {
            #expect(abs(value - annualRate) <= 0.0001)
        } else {
            Issue.record("Expected input node")
        }
    }

    @Test func hasTermInput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Term (months)"))
        if case .input(let value) = model.kind(of: ref) {
            #expect(abs(value - Double(termMonths)) <= 0.01)
        } else {
            Issue.record("Expected input node")
        }
    }

    // MARK: - Calculation Nodes

    @Test func hasMonthlyRateFormula() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Monthly Rate"))
        if case .formula = model.kind(of: ref) {
        } else {
            Issue.record("Expected formula node")
        }
    }

    @Test func hasMonthlyPaymentFormula() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Monthly Payment"))
        if case .formula = model.kind(of: ref) {
        } else {
            Issue.record("Expected formula node")
        }
    }

    // MARK: - Table

    @Test func scheduleTableExists() throws {
        let model = makeModel()
        let table = try #require(model.table(named: "Schedule"))
        #expect(table.label == "Schedule")
    }

    @Test func scheduleTableHasCorrectRowCount() {
        let model = makeModel()
        let table = model.table(named: "Schedule")
        #expect(table?.rowCount == termMonths)
    }

    @Test func scheduleTableHasCorrectColumns() {
        let model = makeModel()
        let table = model.table(named: "Schedule")
        #expect(table?.columns == [
            "Period", "Beginning Balance", "Payment",
            "Interest", "Principal", "Ending Balance"
        ])
    }

    @Test func firstRowBegBalReferencesPrincipal() throws {
        let model = makeModel()
        let table = try #require(model.table(named: "Schedule"))
        let begBalRef = table.cell(row: 0, column: 1)

        if case .formula(let formula) = model.kind(of: begBalRef) {
            let principalRef = try #require(model.node(named: "Principal"))
            #expect(formula == .ref(principalRef))
        } else {
            Issue.record("Expected formula referencing Principal")
        }
    }

    @Test func secondRowBegBalReferencesFirstEndBal() throws {
        let model = makeModel()
        let table = try #require(model.table(named: "Schedule"))
        guard table.rowCount >= 2 else {
            Issue.record("Need at least 2 rows")
            return
        }

        let firstEndBal = table.cell(row: 0, column: 5)
        let secondBegBal = table.cell(row: 1, column: 1)

        if case .formula(let formula) = model.kind(of: secondBegBal) {
            #expect(formula == .ref(firstEndBal))
        } else {
            Issue.record("Expected formula referencing previous ending balance")
        }
    }

    // MARK: - Output Nodes

    @Test func hasTotalPaymentsOutput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Total Payments"))
        if case .output = model.kind(of: ref) {
        } else {
            Issue.record("Expected output node")
        }
    }

    @Test func hasTotalInterestOutput() throws {
        let model = makeModel()
        let ref = try #require(model.node(named: "Total Interest"))
        if case .output = model.kind(of: ref) {
        } else {
            Issue.record("Expected output node")
        }
    }

    // MARK: - Node Count

    @Test func nodeCount() {
        let model = makeModel()
        let expectedInputs = 3
        let expectedCalcs = 2
        let expectedTableCells = termMonths * 6
        let expectedOutputs = 2
        let expected = expectedInputs + expectedCalcs + expectedTableCells + expectedOutputs
        #expect(model.nodeCount == expected)
    }

    // MARK: - Export

    @Test func exportsToWorkbook() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "Amortization", sheetName: "Amortization")

        #expect(wb.sheets.count == 1)
        #expect(wb.sheets[0].name == "Amortization")
    }

    @Test func exportedPMTFormula() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let paymentRef = try #require(model.node(named: "Monthly Payment"))
        let paymentCell = try #require(assignment.mapping[paymentRef])

        let ast = try #require(sheet.formulaAST(at: paymentCell.reference))

        if case .negate(let inner) = ast {
            if case .function(let name, _) = inner {
                #expect(name == "PMT")
            } else {
                Issue.record("Expected PMT function inside negate")
            }
        } else {
            Issue.record("Expected negated PMT formula")
        }
    }

    @Test func savesToFile() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "Amortization")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("amort_model_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try wb.save(to: url)
        #expect(try url.checkResourceIsReachable())
    }

    // MARK: - DebtInstrument Integration

    @Test func buildFromDebtInstrument() throws {
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

        let model = AmortizationModelBuilder.build(from: instrument)
        let table = model.table(named: "Schedule")
        #expect(table?.rowCount == 3)
    }
}
