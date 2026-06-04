import SwiftXLSX

/// Exports an ``ExcelModel`` to a SwiftXLSX `Workbook` with live formulas.
///
/// The exporter resolves ``NodeFormula`` references into concrete cell references
/// using a ``LayoutStrategy``, then writes labels, values, and formulas to the worksheet.
public enum ModelExporter {

    /// Exports the model to a workbook.
    ///
    /// - Parameters:
    ///   - model: The computational graph to export.
    ///   - title: Title text written in the first row. Defaults to "Model".
    ///   - sheetName: Name for the worksheet. Defaults to "Model".
    ///   - layout: Strategy for assigning cell positions. Defaults to ``VerticalLayoutStrategy``.
    ///   - design: Visual styling bundle. Defaults to `.default`.
    /// - Returns: A `Workbook` ready to save as .xlsx.
    /// - Throws: ``ResolutionError`` if a formula references an unmapped node.
    public static func export(
        _ model: ExcelModel,
        title: String = "Model",
        sheetName: String = "Model",
        layout: any LayoutStrategy = VerticalLayoutStrategy(),
        design: DesignBundle = .default
    ) throws -> Workbook {
        let assignment = layout.assign(model)
        let wb = Workbook()
        let sheet = wb.addSheet(name: sheetName)

        configureColumns(sheet: sheet, design: design)
        writeTitle(title, to: sheet, design: design)
        writeSectionHeaders(assignment.sectionRows, to: sheet, design: design)
        writeTableHeaders(assignment: assignment, model: model, to: sheet, design: design)
        try writeNodes(model: model, assignment: assignment, to: sheet, design: design)

        return wb
    }

    // MARK: - Private

    private static func configureColumns(sheet: Worksheet, design: DesignBundle) {
        for col in 1...design.gutterColumnCount {
            sheet.setColumnWidth(
                column: columnLetter(for: col),
                width: design.gutterColumnWidth
            )
        }

        let labelCol = design.gutterColumnCount + 1
        sheet.setColumnWidth(column: columnLetter(for: labelCol), width: 20)

        let valueCol = design.gutterColumnCount + 2
        sheet.setColumnWidth(column: columnLetter(for: valueCol), width: design.dataColumnWidth)
    }

    private static func writeTitle(
        _ title: String,
        to sheet: Worksheet,
        design: DesignBundle
    ) {
        let labelCol = design.gutterColumnCount + 1
        let titleStyle = CellStyle(font: design.titleFont)
        sheet.write(title, to: CellRef(column: labelCol, row: 1).reference, style: titleStyle)
        sheet.setRowHeight(row: 1, height: design.titleRowHeight)
    }

    private static func writeSectionHeaders(
        _ sectionRows: [String: Int],
        to sheet: Worksheet,
        design: DesignBundle
    ) {
        let labelCol = design.gutterColumnCount + 1
        let headerStyle = CellStyle(font: design.labelFont)

        for (name, row) in sectionRows {
            sheet.write(
                name,
                to: CellRef(column: labelCol, row: row).reference,
                style: headerStyle
            )
        }
    }

    private static func writeTableHeaders(
        assignment: CellAssignment,
        model: ExcelModel,
        to sheet: Worksheet,
        design: DesignBundle
    ) {
        let headerStyle = CellStyle(font: design.labelFont)
        for (tableLabel, headerCells) in assignment.tableColumnHeaders {
            guard let table = model.table(named: tableLabel) else { continue }
            for (i, cell) in headerCells.enumerated() where i < table.columns.count {
                sheet.write(table.columns[i], to: cell.reference, style: headerStyle)
            }
        }
    }

    private static func writeNodes(
        model: ExcelModel,
        assignment: CellAssignment,
        to sheet: Worksheet,
        design: DesignBundle
    ) throws {
        let labelStyle = CellStyle(font: design.labelFont)
        let outputStyle = CellStyle.currency.with(font: Font(bold: true))

        for ref in model.allRefs {
            guard let kind = model.kind(of: ref),
                  let valueCell = assignment.mapping[ref] else { continue }

            if let labelCell = assignment.labelMapping[ref] {
                sheet.write(ref.label, to: labelCell.reference, style: labelStyle)
            }

            switch kind {
            case .input(let value):
                sheet.write(value, to: valueCell.reference, style: .input)

            case .textInput(let value):
                sheet.write(value, to: valueCell.reference, style: .general)

            case .formula(let formula):
                let ast = try formula.resolve(using: assignment.mapping)
                sheet.write(ast, to: valueCell.reference, style: .general)

            case .output(let formula):
                let ast = try formula.resolve(using: assignment.mapping)
                sheet.write(ast, to: valueCell.reference, style: outputStyle)

            case .label(let text):
                sheet.write(text, to: valueCell.reference, style: .general)
            }
        }
    }

    private static func columnLetter(for column: Int) -> String {
        var result = ""
        var n = column
        while n > 0 {
            n -= 1
            let charValue = 65 + (n % 26)
            guard let scalar = UnicodeScalar(charValue) else { break }
            result = String(scalar) + result
            n /= 26
        }
        return result
    }
}
