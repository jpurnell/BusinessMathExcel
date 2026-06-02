import BusinessMath
import SwiftXLSX

/// Translates a BusinessMath `AmortizationSchedule` into a SwiftXLSX `Workbook`.
public enum AmortizationTranslator {

    /// Creates a workbook containing the amortization schedule.
    ///
    /// - Parameters:
    ///   - schedule: The amortization schedule to translate.
    ///   - sheetName: Name for the worksheet. Defaults to "Amortization Schedule".
    /// - Returns: A `Workbook` ready to save as .xlsx.
    public static func workbook(
        from schedule: AmortizationSchedule,
        sheetName: String = "Amortization Schedule"
    ) -> Workbook {
        let wb = Workbook()
        let sheet = wb.addSheet(name: sheetName)

        writeHeaders(to: sheet)
        writeDataRows(from: schedule, to: sheet)
        writeTotalsRow(from: schedule, to: sheet)
        setColumnWidths(on: sheet)

        return wb
    }

    private static func writeHeaders(to sheet: Worksheet) {
        let headers = ["Period", "Beginning Balance", "Payment",
                       "Principal", "Interest", "Ending Balance"]
        for (col, header) in headers.enumerated() {
            let ref = CellRef(column: col + 1, row: 1)
            sheet.write(header, to: ref.reference, style: .header)
        }
    }

    private static func writeDataRows(
        from schedule: AmortizationSchedule,
        to sheet: Worksheet
    ) {
        for (index, period) in schedule.periods.enumerated() {
            let row = index + 2

            let periodRef = CellRef(column: 1, row: row)
            sheet.write(period.label, to: periodRef.reference)

            let beginRef = CellRef(column: 2, row: row)
            sheet.write(
                schedule.beginningBalance[period] ?? 0,
                to: beginRef.reference,
                style: .currency
            )

            let payRef = CellRef(column: 3, row: row)
            sheet.write(
                schedule.payment[period] ?? 0,
                to: payRef.reference,
                style: .currency
            )

            let princRef = CellRef(column: 4, row: row)
            sheet.write(
                schedule.principal[period] ?? 0,
                to: princRef.reference,
                style: .currency
            )

            let intRef = CellRef(column: 5, row: row)
            sheet.write(
                schedule.interest[period] ?? 0,
                to: intRef.reference,
                style: .currency
            )

            let endRef = CellRef(column: 6, row: row)
            sheet.write(
                schedule.endingBalance[period] ?? 0,
                to: endRef.reference,
                style: .currency
            )
        }
    }

    private static func writeTotalsRow(
        from schedule: AmortizationSchedule,
        to sheet: Worksheet
    ) {
        let lastDataRow = schedule.periods.count + 1
        let totalsRow = lastDataRow + 1

        let labelRef = CellRef(column: 1, row: totalsRow)
        sheet.write("Total", to: labelRef.reference, style: .header)

        sheet.writeFormula(
            "=SUM(C2:C\(lastDataRow))",
            to: CellRef(column: 3, row: totalsRow).reference,
            style: .currency
        )
        sheet.writeFormula(
            "=SUM(D2:D\(lastDataRow))",
            to: CellRef(column: 4, row: totalsRow).reference,
            style: .currency
        )
        sheet.writeFormula(
            "=SUM(E2:E\(lastDataRow))",
            to: CellRef(column: 5, row: totalsRow).reference,
            style: .currency
        )
    }

    private static func setColumnWidths(on sheet: Worksheet) {
        sheet.setColumnWidth(column: "A", width: 14)
        sheet.setColumnWidth(column: "B", width: 18)
        sheet.setColumnWidth(column: "C", width: 14)
        sheet.setColumnWidth(column: "D", width: 14)
        sheet.setColumnWidth(column: "E", width: 14)
        sheet.setColumnWidth(column: "F", width: 18)
    }
}
