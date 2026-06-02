import XCTest
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX
import Foundation

final class DesktopDemoTest: XCTestCase {

    func testAmortizationToDesktop() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let maturity = calendar.date(from: DateComponents(year: 2055, month: 1, day: 1))!

        let mortgage = DebtInstrument(
            principal: 500_000,
            interestRate: 0.065,
            startDate: start,
            maturityDate: maturity,
            paymentFrequency: .monthly,
            amortizationType: .levelPayment
        )
        let schedule = mortgage.schedule()
        let workbook = AmortizationTranslator.workbook(from: schedule, sheetName: "30yr Mortgage")

        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/Demo-Amortization.xlsx")
        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSimulationToDesktop() throws {
        var values: [Double] = []
        var state: UInt64 = 42
        for _ in 0..<1000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u1 = Double(state >> 11) / Double(1 << 53)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u2 = Double(state >> 11) / Double(1 << 53)
            let z = (-2.0 * log(max(u1, 1e-10))).squareRoot() * cos(2.0 * .pi * u2)
            values.append(100_000 + z * 25_000)
        }

        let results = SimulationResults(values: values)
        let workbook = SimulationTranslator.workbook(from: results, title: "NPV Distribution — 1000 Trials")

        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/Demo-Simulation.xlsx")
        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testTornadoToDesktop() throws {
        let tornado = TornadoDiagramAnalysis(
            inputs: ["Revenue Growth", "COGS %", "Tax Rate", "Discount Rate", "CapEx"],
            impacts: [
                "Revenue Growth": 450_000,
                "COGS %": 320_000,
                "Tax Rate": 180_000,
                "Discount Rate": 150_000,
                "CapEx": 90_000,
            ],
            lowValues: [
                "Revenue Growth": 750_000,
                "COGS %": 820_000,
                "Tax Rate": 900_000,
                "Discount Rate": 920_000,
                "CapEx": 960_000,
            ],
            highValues: [
                "Revenue Growth": 1_200_000,
                "COGS %": 1_140_000,
                "Tax Rate": 1_080_000,
                "Discount Rate": 1_070_000,
                "CapEx": 1_050_000,
            ],
            baseCaseOutput: 1_000_000
        )
        let workbook = TornadoTranslator.workbook(from: tornado)

        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/Demo-Tornado.xlsx")
        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSensitivityToDesktop() throws {
        let revenue = ScenarioSensitivityAnalysis(
            inputDriver: "Revenue ($K)",
            inputValues: [600, 700, 800, 900, 1000, 1100, 1200],
            outputValues: [20, 45, 70, 100, 130, 155, 180]
        )
        let cogs = ScenarioSensitivityAnalysis(
            inputDriver: "COGS (%)",
            inputValues: [0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70],
            outputValues: [160, 145, 130, 110, 90, 70, 50]
        )
        let workbook = SensitivityTranslator.workbook(from: [revenue, cogs])

        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/Demo-Sensitivity.xlsx")
        try workbook.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
