import XCTest
@testable import BusinessMathExcel
import SwiftXLSX

final class MonteCarloExtensionTests: XCTestCase {

    private func makeModel() -> (ExcelModel, NodeRef) {
        let model = ExcelModel()
        let price = model.addInput(label: "Price", value: 100)
        let qty = model.addInput(label: "Quantity", value: 10)
        let revenue = model.addOutput(
            label: "Revenue",
            formula: .multiply(.ref(price), .ref(qty))
        )
        return (model, revenue)
    }

    // MARK: - Sheet Creation

    func testAddsDataSheet() throws {
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb,
            model: model,
            outputRef: output,
            variations: [
                .init(ref: price, distribution: .uniform(min: 80, max: 120))
            ],
            iterations: 10,
            seed: 42
        )

        XCTAssertEqual(wb.sheets.count, 3)
        XCTAssertEqual(wb.sheets[1].name, "Simulation Data")
    }

    func testAddsSummarySheet() throws {
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb,
            model: model,
            outputRef: output,
            variations: [
                .init(ref: price, distribution: .uniform(min: 80, max: 120))
            ],
            iterations: 10,
            seed: 42
        )

        XCTAssertEqual(wb.sheets[2].name, "Summary")
    }

    // MARK: - Data Sheet Content

    func testDataSheetHasCorrectRowCount() throws {
        let iterations = 50
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb,
            model: model,
            outputRef: output,
            variations: [
                .init(ref: price, distribution: .uniform(min: 80, max: 120))
            ],
            iterations: iterations,
            seed: 42
        )

        let dataSheet = wb.sheets[1]
        XCTAssertEqual(dataSheet.cell(at: "A1"), .text("Price"))
        XCTAssertEqual(dataSheet.cell(at: "B1"), .text("Output"))

        if case .number = dataSheet.cell(at: "A\(iterations + 1)") {
        } else {
            XCTFail("Expected data in last row")
        }
    }

    func testDataSheetHasHeaders() throws {
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!
        let qty = model.node(named: "Quantity")!
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb,
            model: model,
            outputRef: output,
            variations: [
                .init(ref: price, distribution: .uniform(min: 80, max: 120)),
                .init(ref: qty, distribution: .normal(mean: 10, stdDev: 2)),
            ],
            iterations: 5,
            seed: 42
        )

        let dataSheet = wb.sheets[1]
        XCTAssertEqual(dataSheet.cell(at: "A1"), .text("Price"))
        XCTAssertEqual(dataSheet.cell(at: "B1"), .text("Quantity"))
        XCTAssertEqual(dataSheet.cell(at: "C1"), .text("Output"))
    }

    // MARK: - Summary Sheet Content

    func testSummarySheetHasStatFormulas() throws {
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb,
            model: model,
            outputRef: output,
            variations: [
                .init(ref: price, distribution: .uniform(min: 80, max: 120))
            ],
            iterations: 100,
            seed: 42
        )

        let summary = wb.sheets[2]
        XCTAssertEqual(summary.cell(at: "A1"), .text("Mean"))
        XCTAssertTrue(summary.cell(at: "B1")?.isFormula == true)

        XCTAssertEqual(summary.cell(at: "A2"), .text("Std Dev"))
        XCTAssertTrue(summary.cell(at: "B2")?.isFormula == true)

        XCTAssertEqual(summary.cell(at: "A3"), .text("Min"))
        XCTAssertEqual(summary.cell(at: "A4"), .text("Max"))
        XCTAssertEqual(summary.cell(at: "A5"), .text("Count"))
    }

    func testSummarySheetHasPercentileFormulas() throws {
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb,
            model: model,
            outputRef: output,
            variations: [
                .init(ref: price, distribution: .uniform(min: 80, max: 120))
            ],
            iterations: 100,
            seed: 42
        )

        let summary = wb.sheets[2]
        XCTAssertEqual(summary.cell(at: "A7"), .text("Percentiles"))
        XCTAssertEqual(summary.cell(at: "A8"), .text("P5"))
        XCTAssertTrue(summary.cell(at: "B8")?.isFormula == true)
    }

    // MARK: - Determinism

    func testSeedProducesDeterministicResults() throws {
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!

        let wb1 = try ModelExporter.export(model)
        MonteCarloExtension.apply(
            to: wb1, model: model, outputRef: output,
            variations: [.init(ref: price, distribution: .uniform(min: 80, max: 120))],
            iterations: 10, seed: 42
        )

        let wb2 = try ModelExporter.export(model)
        MonteCarloExtension.apply(
            to: wb2, model: model, outputRef: output,
            variations: [.init(ref: price, distribution: .uniform(min: 80, max: 120))],
            iterations: 10, seed: 42
        )

        let data1 = wb1.sheets[1]
        let data2 = wb2.sheets[1]

        for row in 2...11 {
            let ref = "A\(row)"
            if case .number(let v1) = data1.cell(at: ref),
               case .number(let v2) = data2.cell(at: ref) {
                XCTAssertEqual(v1, v2, accuracy: 1e-10)
            } else {
                XCTFail("Expected matching numbers at \(ref)")
            }
        }
    }

    // MARK: - Round-Trip

    func testSavesToFile() throws {
        let (model, output) = makeModel()
        let price = model.node(named: "Price")!
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb, model: model, outputRef: output,
            variations: [.init(ref: price, distribution: .uniform(min: 80, max: 120))],
            iterations: 10, seed: 42
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc_test_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        try wb.save(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
