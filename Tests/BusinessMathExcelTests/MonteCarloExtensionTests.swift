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

    // MARK: - Formula Evaluation

    func testEvaluatesPowerFormula() throws {
        let model = ExcelModel()
        let base = model.addInput(label: "Base", value: 2)
        let output = model.addOutput(label: "Cubed", formula: .power(.ref(base), .number(3)))
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb,
            model: model,
            outputRef: output,
            variations: [.init(ref: base, distribution: .uniform(min: 2, max: 2))],
            iterations: 3,
            seed: 42
        )

        let data = try XCTUnwrap(wb.sheets.first { $0.name == "Simulation Data" })
        guard case .number(let value) = try XCTUnwrap(data.cell(at: "B2")) else {
            return XCTFail("Expected a numeric output value")
        }
        XCTAssertEqual(
            value, 8, accuracy: 1e-9,
            "2^3 must evaluate to 8, not fall through to a silent zero"
        )
    }

    func testEvaluatesComparisonAsOneOrZero() throws {
        // Excel treats TRUE and FALSE as 1 and 0 in arithmetic. This evaluator has
        // no boolean channel, so that is the only representation available to it.
        for (label, formula, expected) in [
            ("true", NodeFormula.greaterThan(.number(2), .number(1)), 1.0),
            ("false", NodeFormula.greaterThan(.number(1), .number(2)), 0.0),
        ] {
            let model = ExcelModel()
            let base = model.addInput(label: "Base", value: 1)
            let output = model.addOutput(label: "Flag", formula: formula)
            let wb = try ModelExporter.export(model)

            MonteCarloExtension.apply(
                to: wb, model: model, outputRef: output,
                variations: [.init(ref: base, distribution: .uniform(min: 1, max: 1))],
                iterations: 2, seed: 7
            )

            let data = try XCTUnwrap(wb.sheets.first { $0.name == "Simulation Data" })
            guard case .number(let value) = try XCTUnwrap(data.cell(at: "B2")) else {
                return XCTFail("\(label): expected a numeric output")
            }
            XCTAssertEqual(value, expected, accuracy: 1e-9, "comparison evaluating \(label)")
        }
    }

    func testEvaluatesBooleanAsOneOrZero() throws {
        // TRUE previously evaluated to 0, the same value used for "cannot evaluate",
        // which made a true condition indistinguishable from an unsupported one.
        let model = ExcelModel()
        let base = model.addInput(label: "Base", value: 1)
        let output = model.addOutput(label: "Flag", formula: .bool(true))
        let wb = try ModelExporter.export(model)

        MonteCarloExtension.apply(
            to: wb, model: model, outputRef: output,
            variations: [.init(ref: base, distribution: .uniform(min: 1, max: 1))],
            iterations: 2, seed: 7
        )

        let data = try XCTUnwrap(wb.sheets.first { $0.name == "Simulation Data" })
        guard case .number(let value) = try XCTUnwrap(data.cell(at: "B2")) else {
            return XCTFail("Expected a numeric output")
        }
        XCTAssertEqual(value, 1, accuracy: 1e-9)
    }

    // MARK: - Sheet Creation

    func testAddsDataSheet() throws {
        let (model, output) = makeModel()
        let price = try XCTUnwrap(model.node(named: "Price"))
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
        let price = try XCTUnwrap(model.node(named: "Price"))
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
        let price = try XCTUnwrap(model.node(named: "Price"))
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
        let price = try XCTUnwrap(model.node(named: "Price"))
        let qty = try XCTUnwrap(model.node(named: "Quantity"))
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
        let price = try XCTUnwrap(model.node(named: "Price"))
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
        let price = try XCTUnwrap(model.node(named: "Price"))
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
        let price = try XCTUnwrap(model.node(named: "Price"))

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
        let price = try XCTUnwrap(model.node(named: "Price"))
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
        XCTAssertTrue(try url.checkResourceIsReachable())
    }
}
