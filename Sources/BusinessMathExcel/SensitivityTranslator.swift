import BusinessMath
import SwiftXLSX

/// Translates a BusinessMath `ScenarioSensitivityAnalysis` into a SwiftXLSX `Workbook`.
public enum SensitivityTranslator {

    /// Creates a workbook from one or more sensitivity analyses.
    ///
    /// - Parameters:
    ///   - analyses: One or more sensitivity analyses to include.
    ///   - sheetName: Name for the worksheet. Defaults to "Sensitivity Analysis".
    /// - Returns: A `Workbook` ready to save as .xlsx.
    public static func workbook(
        from analyses: [ScenarioSensitivityAnalysis],
        sheetName: String = "Sensitivity Analysis"
    ) -> Workbook {
        let wb = Workbook()
        let sheet = wb.addSheet(name: sheetName)

        var currentRow = 1
        for (index, analysis) in analyses.enumerated() {
            if index > 0 { currentRow += 1 }
            currentRow = writeAnalysis(analysis, to: sheet, startingRow: currentRow)
        }

        sheet.setColumnWidth(column: "A", width: 18)
        sheet.setColumnWidth(column: "B", width: 18)

        return wb
    }

    /// Creates a workbook from a single sensitivity analysis.
    public static func workbook(
        from analysis: ScenarioSensitivityAnalysis,
        sheetName: String = "Sensitivity Analysis"
    ) -> Workbook {
        workbook(from: [analysis], sheetName: sheetName)
    }

    private static func writeAnalysis(
        _ analysis: ScenarioSensitivityAnalysis,
        to sheet: Worksheet,
        startingRow: Int
    ) -> Int {
        var row = startingRow

        sheet.write(analysis.inputDriver, to: CellRef(column: 1, row: row).reference, style: .header)
        row += 1

        sheet.write("Input Value", to: CellRef(column: 1, row: row).reference, style: .header)
        sheet.write("Output Value", to: CellRef(column: 2, row: row).reference, style: .header)
        row += 1

        for i in 0..<analysis.count {
            sheet.write(
                analysis.inputValues[i],
                to: CellRef(column: 1, row: row).reference,
                style: .currency
            )
            sheet.write(
                analysis.outputValues[i],
                to: CellRef(column: 2, row: row).reference,
                style: .currency
            )
            row += 1
        }

        sheet.write("Output Range", to: CellRef(column: 1, row: row).reference, style: .header)
        sheet.write(analysis.outputRange, to: CellRef(column: 2, row: row).reference, style: .currency)
        row += 1

        return row
    }
}
