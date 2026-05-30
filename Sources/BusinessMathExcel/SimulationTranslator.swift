import BusinessMath
import SwiftXLSX

/// Translates a BusinessMath `SimulationResults` into a SwiftXLSX `Workbook`.
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

        sheet.write(title, to: "A1", style: .header)

        sheet.write("Statistic", to: "A3", style: .header)
        sheet.write("Value", to: "B3", style: .header)

        let stats = results.statistics
        let rows: [(String, Double)] = [
            ("Mean", stats.mean),
            ("Median", stats.median),
            ("Std Deviation", stats.stdDev),
            ("Minimum", stats.min),
            ("Maximum", stats.max),
            ("Skewness", stats.skewness),
        ]

        for (index, row) in rows.enumerated() {
            let r = index + 4
            sheet.write(row.0, to: CellRef(column: 1, row: r).reference)
            sheet.write(row.1, to: CellRef(column: 2, row: r).reference, style: .currency)
        }

        let pctStartRow = rows.count + 5
        sheet.write("Percentile", to: CellRef(column: 1, row: pctStartRow).reference, style: .header)
        sheet.write("Value", to: CellRef(column: 2, row: pctStartRow).reference, style: .header)

        let pct = results.percentiles
        let percentiles: [(String, Double)] = [
            ("5th", pct.p5),
            ("10th", pct.p10),
            ("25th (Q1)", pct.p25),
            ("50th (Median)", pct.p50),
            ("75th (Q3)", pct.p75),
            ("90th", pct.p90),
            ("95th", pct.p95),
            ("99th", pct.p99),
        ]

        for (index, row) in percentiles.enumerated() {
            let r = pctStartRow + 1 + index
            sheet.write(row.0, to: CellRef(column: 1, row: r).reference)
            sheet.write(row.1, to: CellRef(column: 2, row: r).reference, style: .currency)
        }

        let countRow = pctStartRow + percentiles.count + 2
        sheet.write("Simulations", to: CellRef(column: 1, row: countRow).reference, style: .header)
        sheet.write(Double(results.values.count), to: CellRef(column: 2, row: countRow).reference, style: .integer)
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
