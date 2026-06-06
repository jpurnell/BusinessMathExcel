import SwiftXLSX

/// Exports an ``ExcelModel`` to a multi-sheet SwiftXLSX `Workbook`.
///
/// Each section in the model becomes its own worksheet. Formulas that reference
/// nodes on other sheets are automatically resolved to cross-sheet references
/// (`'SheetName'!A1` format).
public enum MultiSheetExporter {

    /// Exports the model to a multi-sheet workbook.
    ///
    /// - Parameters:
    ///   - model: The computational graph to export.
    ///   - title: Title text written in the first row of each sheet. Defaults to "Model".
    ///   - layout: Multi-sheet layout strategy. Defaults to one section per sheet with vertical layout.
    ///   - design: Visual styling bundle. Defaults to `.default`.
    /// - Returns: A `Workbook` with one sheet per section, ready to save as .xlsx.
    /// - Throws: ``ResolutionError`` if a formula references an unmapped node.
    public static func export(
        _ model: ExcelModel,
        title: String = "Model",
        layout: MultiSheetLayoutStrategy = .init(),
        design: DesignBundle = .default
    ) throws -> Workbook {
        let multiAssignment = layout.assign(model)
        let wb = Workbook()

        for sheetName in multiAssignment.sheetOrder {
            guard let assignment = multiAssignment.sheets[sheetName] else { continue }
            let sheet = wb.addSheet(name: sheetName)

            configureColumns(sheet: sheet, design: design)
            writeTitle(title, to: sheet, design: design)
            writeSectionHeaders(assignment.sectionRows, to: sheet, design: design)
            writeTableHeaders(assignment: assignment, model: model, to: sheet, design: design)

            let section = model.sections.first { sec in
                let resolvedName = layout.sheetNames[sec.name] ?? sec.name
                return resolvedName == sheetName
            }
            guard let section = section else { continue }

            try writeNodes(
                section: section,
                model: model,
                assignment: assignment,
                multiAssignment: multiAssignment,
                currentSheet: sheetName,
                to: sheet,
                design: design
            )
        }

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
        section: ModelSection,
        model: ExcelModel,
        assignment: CellAssignment,
        multiAssignment: MultiSheetAssignment,
        currentSheet: String,
        to sheet: Worksheet,
        design: DesignBundle
    ) throws {
        let labelStyle = CellStyle(font: design.labelFont)
        let outputStyle = CellStyle.currency.with(font: Font(bold: true))

        for originalRef in section.refs {
            guard let kind = model.kind(of: originalRef) else { continue }

            let sectionRef = findSectionRef(
                for: originalRef,
                in: assignment
            )
            guard let valueCell = sectionRef.flatMap({ assignment.mapping[$0] })
                    ?? assignment.mapping.first(where: { _ in false })?.value
            else { continue }

            if let sectionRefUnwrapped = sectionRef,
               let labelCell = assignment.labelMapping[sectionRefUnwrapped] {
                sheet.write(originalRef.label, to: labelCell.reference, style: labelStyle)
            }

            switch kind {
            case .input(let value):
                sheet.write(value, to: valueCell.reference, style: .input)

            case .textInput(let value):
                sheet.write(value, to: valueCell.reference, style: .general)

            case .formula(let formula):
                let ast = try resolveWithCrossSheet(
                    formula: formula,
                    model: model,
                    multiAssignment: multiAssignment,
                    currentSheet: currentSheet,
                    localMapping: buildLocalMapping(assignment: assignment)
                )
                sheet.write(ast, to: valueCell.reference, style: .general)

            case .output(let formula):
                let ast = try resolveWithCrossSheet(
                    formula: formula,
                    model: model,
                    multiAssignment: multiAssignment,
                    currentSheet: currentSheet,
                    localMapping: buildLocalMapping(assignment: assignment)
                )
                sheet.write(ast, to: valueCell.reference, style: outputStyle)

            case .label(let text):
                sheet.write(text, to: valueCell.reference, style: .general)
            }
        }
    }

    private static func findSectionRef(
        for originalRef: NodeRef,
        in assignment: CellAssignment
    ) -> NodeRef? {
        if assignment.mapping[originalRef] != nil {
            return originalRef
        }
        return assignment.mapping.keys.first { $0.label == originalRef.label }
    }

    private static func buildLocalMapping(
        assignment: CellAssignment
    ) -> [String: CellRef] {
        var mapping: [String: CellRef] = [:]
        for (ref, cell) in assignment.mapping {
            mapping[ref.label] = cell
        }
        return mapping
    }

    private static func resolveWithCrossSheet(
        formula: NodeFormula,
        model: ExcelModel,
        multiAssignment: MultiSheetAssignment,
        currentSheet: String,
        localMapping: [String: CellRef]
    ) throws -> FormulaAST {
        switch formula {
        case .ref(let nodeRef):
            if let localCell = localMapping[nodeRef.label] {
                return .cellRef(localCell)
            }
            guard let sheetCell = multiAssignment.globalMapping[nodeRef] else {
                throw ResolutionError.danglingReference(nodeRef)
            }
            return .sheetRef(SheetReference(sheet: sheetCell.sheetName, cell: sheetCell.cell))

        case .number(let value):
            return .number(value)

        case .text(let value):
            return .text(value)

        case .bool(let value):
            return .bool(value)

        case .add(let lhs, let rhs):
            return try .add(
                resolveWithCrossSheet(formula: lhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping),
                resolveWithCrossSheet(formula: rhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping)
            )

        case .subtract(let lhs, let rhs):
            return try .subtract(
                resolveWithCrossSheet(formula: lhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping),
                resolveWithCrossSheet(formula: rhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping)
            )

        case .multiply(let lhs, let rhs):
            return try .multiply(
                resolveWithCrossSheet(formula: lhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping),
                resolveWithCrossSheet(formula: rhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping)
            )

        case .divide(let lhs, let rhs):
            return try .divide(
                resolveWithCrossSheet(formula: lhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping),
                resolveWithCrossSheet(formula: rhs, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping)
            )

        case .negate(let expr):
            return try .negate(
                resolveWithCrossSheet(formula: expr, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping)
            )

        case .range(let refs):
            var cells: [CellRef] = []
            for nodeRef in refs {
                if let localCell = localMapping[nodeRef.label] {
                    cells.append(localCell)
                } else {
                    guard let sheetCell = multiAssignment.globalMapping[nodeRef] else {
                        throw ResolutionError.danglingReference(nodeRef)
                    }
                    cells.append(sheetCell.cell)
                }
            }
            guard let first = cells.first, let last = cells.last else {
                return .text("")
            }
            return .cellRange(CellRange(from: first, to: last))

        case .function(let name, let args):
            return try .function(name, args.map {
                try resolveWithCrossSheet(formula: $0, model: model, multiAssignment: multiAssignment, currentSheet: currentSheet, localMapping: localMapping)
            })
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
