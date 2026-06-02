import SwiftXLSX

/// Runs Monte Carlo simulation on an ``ExcelModel`` and adds result sheets
/// to an exported workbook.
///
/// Varies specified input nodes by their assigned distributions across N iterations,
/// evaluates the output formula for each, and writes:
/// - A "Simulation Data" sheet with one row per trial
/// - A "Summary" sheet with AVERAGE, STDEV, MIN, MAX, and PERCENTILE formulas
public enum MonteCarloExtension {

    /// Configuration for a single input to vary.
    public struct InputVariation: Sendable {

        /// The input node to vary.
        public let ref: NodeRef

        /// The probability distribution to sample from.
        public let distribution: Distribution

        /// Creates an input variation.
        ///
        /// - Parameters:
        ///   - ref: The input node reference.
        ///   - distribution: The distribution to sample from.
        public init(ref: NodeRef, distribution: Distribution) {
            self.ref = ref
            self.distribution = distribution
        }
    }

    /// Adds Monte Carlo simulation sheets to an exported workbook.
    ///
    /// - Parameters:
    ///   - workbook: The workbook to add sheets to (typically from ``ModelExporter``).
    ///   - model: The source model.
    ///   - outputRef: The output node whose value is tracked across trials.
    ///   - variations: Input nodes and their distributions.
    ///   - iterations: Number of simulation trials. Defaults to 1000.
    ///   - seed: Optional deterministic seed for reproducible results.
    /// - Returns: The modified workbook with simulation sheets added.
    @discardableResult
    public static func apply(
        to workbook: Workbook,
        model: ExcelModel,
        outputRef: NodeRef,
        variations: [InputVariation],
        iterations: Int = 1000,
        seed: UInt64? = nil
    ) -> Workbook {
        var rng: any RandomNumberGenerator = seed.map { SeededRNG(seed: $0) }
            ?? SystemRandomNumberGenerator() as any RandomNumberGenerator

        let results = runSimulation(
            model: model,
            outputRef: outputRef,
            variations: variations,
            iterations: iterations,
            rng: &rng
        )

        writeDataSheet(to: workbook, variations: variations, results: results)
        writeSummarySheet(to: workbook, dataRowCount: iterations)

        return workbook
    }

    // MARK: - Private

    private static func runSimulation(
        model: ExcelModel,
        outputRef: NodeRef,
        variations: [InputVariation],
        iterations: Int,
        rng: inout any RandomNumberGenerator
    ) -> SimulationData {
        var inputColumns: [[Double]] = Array(
            repeating: [],
            count: variations.count
        )
        var outputValues: [Double] = []

        guard let outputKind = model.kind(of: outputRef) else {
            return SimulationData(inputColumns: inputColumns, outputValues: outputValues)
        }

        for _ in 0..<iterations {
            var inputSnapshot: [NodeRef: Double] = [:]

            for (col, variation) in variations.enumerated() {
                let value = variation.distribution.sample(using: &rng)
                inputSnapshot[variation.ref] = value
                inputColumns[col].append(value)
            }

            let output = evaluateOutput(
                kind: outputKind,
                model: model,
                inputOverrides: inputSnapshot
            )
            outputValues.append(output)
        }

        return SimulationData(inputColumns: inputColumns, outputValues: outputValues)
    }

    private static func evaluateOutput(
        kind: NodeKind,
        model: ExcelModel,
        inputOverrides: [NodeRef: Double]
    ) -> Double {
        switch kind {
        case .output(let formula), .formula(let formula):
            return evaluateFormula(formula, model: model, inputOverrides: inputOverrides)
        case .input(let value):
            return value
        case .textInput, .label:
            return 0
        }
    }

    private static func evaluateFormula(
        _ formula: NodeFormula,
        model: ExcelModel,
        inputOverrides: [NodeRef: Double]
    ) -> Double {
        switch formula {
        case .ref(let nodeRef):
            if let override = inputOverrides[nodeRef] {
                return override
            }
            guard let kind = model.kind(of: nodeRef) else { return 0 }
            return evaluateOutput(kind: kind, model: model, inputOverrides: inputOverrides)

        case .number(let value):
            return value

        case .text, .bool:
            return 0

        case .add(let lhs, let rhs):
            return evaluateFormula(lhs, model: model, inputOverrides: inputOverrides)
                + evaluateFormula(rhs, model: model, inputOverrides: inputOverrides)

        case .subtract(let lhs, let rhs):
            return evaluateFormula(lhs, model: model, inputOverrides: inputOverrides)
                - evaluateFormula(rhs, model: model, inputOverrides: inputOverrides)

        case .multiply(let lhs, let rhs):
            return evaluateFormula(lhs, model: model, inputOverrides: inputOverrides)
                * evaluateFormula(rhs, model: model, inputOverrides: inputOverrides)

        case .divide(let lhs, let rhs):
            let denominator = evaluateFormula(rhs, model: model, inputOverrides: inputOverrides)
            guard denominator != 0 else { return 0 }
            return evaluateFormula(lhs, model: model, inputOverrides: inputOverrides) / denominator

        case .negate(let expr):
            return -evaluateFormula(expr, model: model, inputOverrides: inputOverrides)

        case .function:
            return 0
        }
    }

    private static func writeDataSheet(
        to workbook: Workbook,
        variations: [InputVariation],
        results: SimulationData
    ) {
        let sheet = workbook.addSheet(name: "Simulation Data")

        for (col, variation) in variations.enumerated() {
            sheet.write(
                variation.ref.label,
                to: CellRef(column: col + 1, row: 1).reference,
                style: .header
            )
        }
        let outputCol = variations.count + 1
        sheet.write("Output", to: CellRef(column: outputCol, row: 1).reference, style: .header)

        for (row, output) in results.outputValues.enumerated() {
            let excelRow = row + 2
            for (col, values) in results.inputColumns.enumerated() {
                sheet.write(
                    values[row],
                    to: CellRef(column: col + 1, row: excelRow).reference
                )
            }
            sheet.write(output, to: CellRef(column: outputCol, row: excelRow).reference)
        }
    }

    private static func writeSummarySheet(
        to workbook: Workbook,
        dataRowCount: Int
    ) {
        let sheet = workbook.addSheet(name: "Summary")
        let dataRange = "'Simulation Data'!A2:A\(dataRowCount + 1)"

        let stats: [(String, String)] = [
            ("Mean", "AVERAGE"),
            ("Std Dev", "STDEV"),
            ("Min", "MIN"),
            ("Max", "MAX"),
            ("Count", "COUNT"),
        ]

        var row = 1
        for (label, fn) in stats {
            sheet.write(label, to: CellRef(column: 1, row: row).reference, style: .header)
            sheet.writeFormula(
                "=\(fn)(\(dataRange))",
                to: CellRef(column: 2, row: row).reference,
                style: .currency
            )
            row += 1
        }

        row += 1
        sheet.write("Percentiles", to: CellRef(column: 1, row: row).reference, style: .header)
        row += 1

        let percentiles = [0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99]
        for pct in percentiles {
            let pctLabel = "P\(Int(pct * 100))"
            sheet.write(pctLabel, to: CellRef(column: 1, row: row).reference, style: .header)
            sheet.writeFormula(
                "=PERCENTILE(\(dataRange),\(pct))",
                to: CellRef(column: 2, row: row).reference,
                style: .currency
            )
            row += 1
        }

        sheet.setColumnWidth(column: "A", width: 14)
        sheet.setColumnWidth(column: "B", width: 18)
    }
}

// MARK: - Internal Types

private struct SimulationData {
    let inputColumns: [[Double]]
    let outputValues: [Double]
}

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
