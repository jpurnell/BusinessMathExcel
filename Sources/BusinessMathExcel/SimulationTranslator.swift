import BusinessMath
import SwiftXLSX

/// Translates a BusinessMath `SimulationResults` into a SwiftXLSX `Workbook`.
@available(*, deprecated, message: "Use MonteCarloExtension with ModelExporter for live formulas")
public enum SimulationTranslator {

    /// Creates a workbook containing simulation results with statistics and percentiles.
    ///
    /// - Parameters:
    ///   - results: The simulation results to translate.
    ///   - title: Title for the simulation. Defaults to "Monte Carlo Simulation".
    /// - Returns: A `Workbook` ready to save as .xlsx.
    public static func workbook(
        from results: SimulationResults,
        title: String = "Monte Carlo Simulation"
    ) -> Workbook {
        let wb = Workbook()

        let summary = wb.addSheet(name: "Summary")
        writeSummary(from: results, title: title, to: summary)

        let data = wb.addSheet(name: "Simulation Data")
        writeRawData(from: results, to: data)

        return wb
    }

    private static func writeSummary(
        from results: SimulationResults,
        title: String,
        to sheet: Worksheet
    ) {
        sheet.setColumnWidth(column: "A", width: 22)
        sheet.setColumnWidth(column: "B", width: 18)

        let lastDataRow = results.values.count + 1
        let dataRange = "'Simulation Data'!B2:B\(lastDataRow)"

        sheet.write(title, to: "A1", style: .header)

        sheet.write("Statistic", to: "A3", style: .header)
        sheet.write("Value", to: "B3", style: .header)

        let formulas: [(String, String)] = [
            ("Mean", "=AVERAGE(\(dataRange))"),
            ("Median", "=MEDIAN(\(dataRange))"),
            ("Std Deviation", "=STDEV(\(dataRange))"),
            ("Minimum", "=MIN(\(dataRange))"),
            ("Maximum", "=MAX(\(dataRange))"),
            ("Count", "=COUNT(\(dataRange))"),
        ]

        for (index, row) in formulas.enumerated() {
            let r = index + 4
            sheet.write(row.0, to: CellRef(column: 1, row: r).reference)
            sheet.writeFormula(row.1, to: CellRef(column: 2, row: r).reference, style: .currency)
        }

        let pctStartRow = formulas.count + 5
        sheet.write("Percentile", to: CellRef(column: 1, row: pctStartRow).reference, style: .header)
        sheet.write("Value", to: CellRef(column: 2, row: pctStartRow).reference, style: .header)

        let percentiles: [(String, String)] = [
            ("5th", "=PERCENTILE(\(dataRange),0.05)"),
            ("10th", "=PERCENTILE(\(dataRange),0.10)"),
            ("25th (Q1)", "=PERCENTILE(\(dataRange),0.25)"),
            ("50th (Median)", "=PERCENTILE(\(dataRange),0.50)"),
            ("75th (Q3)", "=PERCENTILE(\(dataRange),0.75)"),
            ("90th", "=PERCENTILE(\(dataRange),0.90)"),
            ("95th", "=PERCENTILE(\(dataRange),0.95)"),
            ("99th", "=PERCENTILE(\(dataRange),0.99)"),
        ]

        for (index, row) in percentiles.enumerated() {
            let r = pctStartRow + 1 + index
            sheet.write(row.0, to: CellRef(column: 1, row: r).reference)
            sheet.writeFormula(row.1, to: CellRef(column: 2, row: r).reference, style: .currency)
        }
    }

    private static func writeRawData(
        from results: SimulationResults,
        to sheet: Worksheet
    ) {
        sheet.setColumnWidth(column: "A", width: 12)
        sheet.setColumnWidth(column: "B", width: 18)

        sheet.write("Trial", to: "A1", style: .header)
        sheet.write("Value", to: "B1", style: .header)

        for (index, value) in results.values.enumerated() {
            let row = index + 2
            sheet.write(Double(index + 1), to: CellRef(column: 1, row: row).reference, style: .integer)
            sheet.write(value, to: CellRef(column: 2, row: row).reference, style: .currency)
        }
    }
}
