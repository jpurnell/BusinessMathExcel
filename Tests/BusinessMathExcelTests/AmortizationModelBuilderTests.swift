import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

final class AmortizationModelBuilderTests: XCTestCase {

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

    func testHasPrincipalInput() {
        let model = makeModel()
        let ref = model.node(named: "Principal")
        XCTAssertNotNil(ref)
        if case .input(let value) = model.kind(of: ref!) {
            XCTAssertEqual(value, principal, accuracy: 0.01)
        } else {
            XCTFail("Expected input node")
        }
    }

    func testHasAnnualRateInput() {
        let model = makeModel()
        let ref = model.node(named: "Annual Rate")
        XCTAssertNotNil(ref)
        if case .input(let value) = model.kind(of: ref!) {
            XCTAssertEqual(value, annualRate, accuracy: 0.0001)
        } else {
            XCTFail("Expected input node")
        }
    }

    func testHasTermInput() {
        let model = makeModel()
        let ref = model.node(named: "Term (months)")
        XCTAssertNotNil(ref)
        if case .input(let value) = model.kind(of: ref!) {
            XCTAssertEqual(value, Double(termMonths), accuracy: 0.01)
        } else {
            XCTFail("Expected input node")
        }
    }

    // MARK: - Calculation Nodes

    func testHasMonthlyRateFormula() {
        let model = makeModel()
        let ref = model.node(named: "Monthly Rate")
        XCTAssertNotNil(ref)
        if case .formula = model.kind(of: ref!) {
        } else {
            XCTFail("Expected formula node")
        }
    }

    func testHasMonthlyPaymentFormula() {
        let model = makeModel()
        let ref = model.node(named: "Monthly Payment")
        XCTAssertNotNil(ref)
        if case .formula = model.kind(of: ref!) {
        } else {
            XCTFail("Expected formula node")
        }
    }

    // MARK: - Table

    func testScheduleTableExists() {
        let model = makeModel()
        let table = model.table(named: "Schedule")
        XCTAssertNotNil(table)
    }

    func testScheduleTableHasCorrectRowCount() {
        let model = makeModel()
        let table = model.table(named: "Schedule")
        XCTAssertEqual(table?.rowCount, termMonths)
    }

    func testScheduleTableHasCorrectColumns() {
        let model = makeModel()
        let table = model.table(named: "Schedule")
        XCTAssertEqual(table?.columns, [
            "Period", "Beginning Balance", "Payment",
            "Interest", "Principal", "Ending Balance"
        ])
    }

    func testFirstRowBegBalReferencesPrincipal() {
        let model = makeModel()
        let table = model.table(named: "Schedule")!
        let begBalRef = table.cell(row: 0, column: 1)

        if case .formula(let formula) = model.kind(of: begBalRef) {
            let principalRef = model.node(named: "Principal")!
            XCTAssertEqual(formula, .ref(principalRef))
        } else {
            XCTFail("Expected formula referencing Principal")
        }
    }

    func testSecondRowBegBalReferencesFirstEndBal() {
        let model = makeModel()
        let table = model.table(named: "Schedule")!
        guard table.rowCount >= 2 else {
            XCTFail("Need at least 2 rows")
            return
        }

        let firstEndBal = table.cell(row: 0, column: 5)
        let secondBegBal = table.cell(row: 1, column: 1)

        if case .formula(let formula) = model.kind(of: secondBegBal) {
            XCTAssertEqual(formula, .ref(firstEndBal))
        } else {
            XCTFail("Expected formula referencing previous ending balance")
        }
    }

    // MARK: - Output Nodes

    func testHasTotalPaymentsOutput() {
        let model = makeModel()
        let ref = model.node(named: "Total Payments")
        XCTAssertNotNil(ref)
        if case .output = model.kind(of: ref!) {
        } else {
            XCTFail("Expected output node")
        }
    }

    func testHasTotalInterestOutput() {
        let model = makeModel()
        let ref = model.node(named: "Total Interest")
        XCTAssertNotNil(ref)
        if case .output = model.kind(of: ref!) {
        } else {
            XCTFail("Expected output node")
        }
    }

    // MARK: - Node Count

    func testNodeCount() {
        let model = makeModel()
        let expectedInputs = 3
        let expectedCalcs = 2
        let expectedTableCells = termMonths * 6
        let expectedOutputs = 2
        let expected = expectedInputs + expectedCalcs + expectedTableCells + expectedOutputs
        XCTAssertEqual(model.nodeCount, expected)
    }

    // MARK: - Export

    func testExportsToWorkbook() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "Amortization", sheetName: "Amortization")

        XCTAssertEqual(wb.sheets.count, 1)
        XCTAssertEqual(wb.sheets[0].name, "Amortization")
    }

    func testExportedPMTFormula() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model)
        let sheet = wb.sheets[0]

        let strategy = VerticalLayoutStrategy()
        let assignment = strategy.assign(model)
        let paymentRef = model.node(named: "Monthly Payment")!
        let paymentCell = assignment.mapping[paymentRef]!

        let ast = sheet.formulaAST(at: paymentCell.reference)
        XCTAssertNotNil(ast)

        if case .negate(let inner) = ast {
            if case .function(let name, _) = inner {
                XCTAssertEqual(name, "PMT")
            } else {
                XCTFail("Expected PMT function inside negate")
            }
        } else {
            XCTFail("Expected negated PMT formula")
        }
    }

    func testSavesToFile() throws {
        let model = makeModel()
        let wb = try ModelExporter.export(model, title: "Amortization")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("amort_model_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try wb.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - DebtInstrument Integration

    func testBuildFromDebtInstrument() {
        let calendar = Calendar.current
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

        let model = AmortizationModelBuilder.build(from: instrument)
        let table = model.table(named: "Schedule")
        XCTAssertEqual(table?.rowCount, 3)
    }
}
