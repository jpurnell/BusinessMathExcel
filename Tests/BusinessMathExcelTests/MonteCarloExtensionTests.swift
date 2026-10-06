import Foundation
import Testing
@testable import BusinessMathExcel
import SwiftXLSX

@Suite struct MonteCarloExtensionTests {

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

    @Test func evaluatesPowerFormula() throws {
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

        let data = try #require(wb.sheets.first { $0.name == "Simulation Data" })
        guard case .number(let value) = try #require(data.cell(at: "B2")) else {
            Issue.record("Expected a numeric output value"); return
        }
        #expect(abs(value - 8) <= 1e-9, "2^3 must evaluate to 8, not fall through to a silent zero")
    }

    @Test func evaluatesComparisonAsOneOrZero() throws {
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

            let data = try #require(wb.sheets.first { $0.name == "Simulation Data" })
            guard case .number(let value) = try #require(data.cell(at: "B2")) else {
                Issue.record("\(label): expected a numeric output"); return
            }
            #expect(abs(value - expected) <= 1e-9, "comparison evaluating \(label)")
        }
    }

    @Test func evaluatesBooleanAsOneOrZero() throws {
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

        let data = try #require(wb.sheets.first { $0.name == "Simulation Data" })
        guard case .number(let value) = try #require(data.cell(at: "B2")) else {
            Issue.record("Expected a numeric output"); return
        }
        #expect(abs(value - 1) <= 1e-9)
    }

    // MARK: - Sheet Creation

    @Test func addsDataSheet() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
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

        #expect(wb.sheets.count == 3)
        #expect(wb.sheets[1].name == "Simulation Data")
    }

    @Test func addsSummarySheet() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
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

        #expect(wb.sheets[2].name == "Summary")
    }

    // MARK: - Data Sheet Content

    @Test func dataSheetHasCorrectRowCount() throws {
        let iterations = 50
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
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
        #expect(dataSheet.cell(at: "A1") == .text("Price"))
        #expect(dataSheet.cell(at: "B1") == .text("Output"))

        if case .number = dataSheet.cell(at: "A\(iterations + 1)") {
        } else {
            Issue.record("Expected data in last row")
        }
    }

    @Test func dataSheetHasHeaders() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
        let qty = try #require(model.node(named: "Quantity"))
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
        #expect(dataSheet.cell(at: "A1") == .text("Price"))
        #expect(dataSheet.cell(at: "B1") == .text("Quantity"))
        #expect(dataSheet.cell(at: "C1") == .text("Output"))
    }

    // MARK: - Summary Sheet Content

    @Test func summarySheetHasStatFormulas() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
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
        #expect(summary.cell(at: "A1") == .text("Mean"))
        #expect(summary.cell(at: "B1")?.isFormula == true)

        #expect(summary.cell(at: "A2") == .text("Std Dev"))
        #expect(summary.cell(at: "B2")?.isFormula == true)

        #expect(summary.cell(at: "A3") == .text("Min"))
        #expect(summary.cell(at: "A4") == .text("Max"))
        #expect(summary.cell(at: "A5") == .text("Count"))
    }

    @Test func summarySheetHasPercentileFormulas() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
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
        #expect(summary.cell(at: "A7") == .text("Percentiles"))
        #expect(summary.cell(at: "A8") == .text("P5"))
        #expect(summary.cell(at: "B8")?.isFormula == true)
    }

    @Test func everyPercentileIsLabelledWithItsWholePercent() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
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

        // Label and fraction are two renderings of one number. They are derived
        // from the integer percent, so neither can drift from the other by a
        // floating-point truncation.
        let summary = wb.sheets[2]
        let rows = 8...15
        let labels = rows.map { summary.cell(at: "A\($0)") }
        #expect(labels == ["P5", "P10", "P25", "P50", "P75", "P90", "P95", "P99"].map { .text($0) })

        let fractions = try rows.map { row -> String in
            let formula = FormulaSerializer.serialize(try #require(summary.formulaAST(at: "B\(row)")))
            return String(formula.split(separator: ",").last ?? "")
        }
        #expect(fractions == ["0.05)", "0.1)", "0.25)", "0.5)", "0.75)", "0.9)", "0.95)", "0.99)"])
    }

    // MARK: - Determinism

    @Test func seedProducesDeterministicResults() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))

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
                #expect(abs(v1 - v2) <= 1e-10)
            } else {
                Issue.record("Expected matching numbers at \(ref)")
            }
        }
    }

    // MARK: - Round-Trip

    @Test func savesToFile() throws {
        let (model, output) = makeModel()
        let price = try #require(model.node(named: "Price"))
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
        #expect(try url.checkResourceIsReachable())
    }
}
