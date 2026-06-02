import BusinessMath
import SwiftXLSX

/// Translates a BusinessMath `TornadoDiagramAnalysis` into a SwiftXLSX `Workbook`.
@available(*, deprecated, message: "Use ExcelModel with ModelExporter for live formulas")
public enum TornadoTranslator {

    /// Creates a workbook containing tornado diagram analysis data.
    ///
    /// - Parameters:
    ///   - analysis: The tornado analysis to translate.
    ///   - sheetName: Name for the worksheet. Defaults to "Tornado Analysis".
    /// - Returns: A `Workbook` ready to save as .xlsx.
    public static func workbook(
        from analysis: TornadoDiagramAnalysis,
        sheetName: String = "Tornado Analysis"
    ) -> Workbook {
        let wb = Workbook()
        let sheet = wb.addSheet(name: sheetName)

        writeBaseCaseHeader(from: analysis, to: sheet)
        writeDataTable(from: analysis, to: sheet)
        setColumnWidths(on: sheet)

        return wb
    }

    private static func writeBaseCaseHeader(
        from analysis: TornadoDiagramAnalysis,
        to sheet: Worksheet
    ) {
        sheet.write("Base Case Output", to: "A1", style: .header)
        sheet.write(analysis.baseCaseOutput, to: "B1", style: .currency)
    }

    private static func writeDataTable(
        from analysis: TornadoDiagramAnalysis,
        to sheet: Worksheet
    ) {
        let headers = ["Input Driver", "Low Output", "High Output", "Impact", "% of Base"]
        for (col, header) in headers.enumerated() {
            let ref = CellRef(column: col + 1, row: 3)
            sheet.write(header, to: ref.reference, style: .header)
        }

        for (index, input) in analysis.inputs.enumerated() {
            let row = index + 4

            sheet.write(input, to: CellRef(column: 1, row: row).reference)

            let low = analysis.lowValues[input] ?? 0
            sheet.write(low, to: CellRef(column: 2, row: row).reference, style: .currency)

            let high = analysis.highValues[input] ?? 0
            sheet.write(high, to: CellRef(column: 3, row: row).reference, style: .currency)

            sheet.writeFormula(
                "=C\(row)-B\(row)",
                to: CellRef(column: 4, row: row).reference,
                style: .currency
            )

            sheet.writeFormula(
                "=D\(row)/$B$1",
                to: CellRef(column: 5, row: row).reference,
                style: .percent
            )
        }
    }

    private static func setColumnWidths(on sheet: Worksheet) {
        sheet.setColumnWidth(column: "A", width: 20)
        sheet.setColumnWidth(column: "B", width: 16)
        sheet.setColumnWidth(column: "C", width: 16)
        sheet.setColumnWidth(column: "D", width: 14)
        sheet.setColumnWidth(column: "E", width: 12)
    }
}
