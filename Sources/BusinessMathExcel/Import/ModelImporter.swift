import SwiftXLSX

/// Imports a SwiftXLSX `Workbook` into an ``ExcelModel`` graph.
///
/// Walks the cells of the first worksheet, creates ``NodeRef`` identities for
/// each non-blank cell, and builds ``NodeFormula`` expressions from formula ASTs.
/// Value cells become inputs; formula cells become formula nodes; cells with
/// no dependents become outputs.
///
/// Import is lossy where the source workbook uses constructs ``NodeFormula``
/// cannot express. Every such loss is reported in ``ImportResult/warnings``
/// naming the cell and the construct, so a partially-translated workbook is
/// never mistaken for a complete one.
public enum ModelImporter {

    /// The result of importing a workbook.
    public struct ImportResult: Sendable {

        /// The imported model.
        public let model: ExcelModel

        /// Maps cell references to their corresponding node references.
        ///
        /// A cell reference carries no sheet, so for a multi-sheet import this holds
        /// the **first** sheet's mapping only — `A1` means something different on
        /// every sheet. Use ``sheetCellToNode`` when more than one sheet is in play.
        public let cellToNode: [CellRef: NodeRef]

        /// Cell-to-node mappings for each imported sheet, keyed by sheet name.
        ///
        /// Unlike ``cellToNode`` this survives sheets that share cell references,
        /// which every multi-sheet workbook does.
        public let sheetCellToNode: [String: [CellRef: NodeRef]]

        /// Warnings generated during import.
        ///
        /// Non-empty whenever the import dropped or degraded something: an
        /// unsupported cell type, an unsupported formula node, or a reference
        /// to a cell the importer had not yet seen.
        public let warnings: [String]
    }

    /// Imports the first sheet of a workbook into an ``ExcelModel``.
    ///
    /// - Parameter workbook: The workbook to import.
    /// - Returns: An ``ImportResult`` containing the model, cell-to-node mapping, and warnings.
    public static func importWorkbook(_ workbook: Workbook) -> ImportResult {
        guard let sheet = workbook.sheets.first else {
            return ImportResult(
                model: ExcelModel(),
                cellToNode: [:],
                sheetCellToNode: [:],
                warnings: []
            )
        }
        return importSheet(sheet)
    }

    /// Imports a specific worksheet into an ``ExcelModel``.
    ///
    /// - Parameter sheet: The worksheet to import.
    /// - Returns: An ``ImportResult`` containing the model, cell-to-node mapping, and warnings.
    public static func importSheet(_ sheet: Worksheet) -> ImportResult {
        let model = ExcelModel()
        var warnings: [String] = []
        let cellToNode = addCells(
            orderedCells(of: sheet),
            to: model,
            labelPrefix: "",
            section: "Imported",
            warnings: &warnings
        )
        return ImportResult(
            model: model,
            cellToNode: cellToNode,
            sheetCellToNode: [sheet.name: cellToNode],
            warnings: warnings
        )
    }

    /// Imports every worksheet of a workbook into a single ``ExcelModel``.
    ///
    /// Each sheet becomes its own section, and node labels are qualified with the
    /// sheet name (`Inputs!A1`) so that sheets sharing a cell reference stay
    /// distinct. Formulas resolve only against cells on their own sheet;
    /// cross-sheet references (`FormulaAST.sheetRef`) are not yet translated and
    /// are reported in ``ImportResult/warnings`` rather than dropped.
    ///
    /// - Parameter workbook: The workbook to import.
    /// - Returns: An ``ImportResult`` whose ``ImportResult/sheetCellToNode`` holds one
    ///   mapping per sheet.
    public static func importAllSheets(_ workbook: Workbook) -> ImportResult {
        let model = ExcelModel()
        var warnings: [String] = []
        var perSheet: [String: [CellRef: NodeRef]] = [:]

        for sheet in workbook.sheets {
            perSheet[sheet.name] = addCells(
                orderedCells(of: sheet),
                to: model,
                labelPrefix: "\(sheet.name)!",
                section: sheet.name,
                warnings: &warnings
            )
        }

        let firstMapping = workbook.sheets.first.flatMap { perSheet[$0.name] } ?? [:]
        return ImportResult(
            model: model,
            cellToNode: firstMapping,
            sheetCellToNode: perSheet,
            warnings: warnings
        )
    }

    /// A worksheet's non-empty cells in reading order: top to bottom, then left to right.
    ///
    /// Formulas are converted against the cells already seen, so the order decides
    /// which references resolve.
    ///
    /// - Parameter sheet: The worksheet to read.
    /// - Returns: Each cell's reference string paired with its value.
    static func orderedCells(of sheet: Worksheet) -> [(reference: String, value: CellValue)] {
        sheet.cellReferences
            .sorted { lhs, rhs in
                let refA = CellRef(lhs)
                let refB = CellRef(rhs)
                if refA.row != refB.row { return refA.row < refB.row }
                return refA.column < refB.column
            }
            .compactMap { reference in
                guard let value = sheet.cell(at: reference) else { return nil }
                return (reference: reference, value: value)
            }
    }

    /// Imports an explicit ordered list of cells into an ``ExcelModel``.
    ///
    /// This is the seam every other entry point funnels through. It is also how the
    /// tests reach cell types `Worksheet` has no public write for — `.array`,
    /// `.date`, and `.error`.
    ///
    /// - Parameter cells: Cells in the order they should be imported. Formulas resolve
    ///   only against cells earlier in this list.
    /// - Returns: An ``ImportResult`` containing the model, cell-to-node mapping, and warnings.
    static func importCells(_ cells: [(reference: String, value: CellValue)]) -> ImportResult {
        let model = ExcelModel()
        var warnings: [String] = []
        let cellToNode = addCells(
            cells,
            to: model,
            labelPrefix: "",
            section: "Imported",
            warnings: &warnings
        )
        return ImportResult(
            model: model,
            cellToNode: cellToNode,
            sheetCellToNode: ["": cellToNode],
            warnings: warnings
        )
    }

    /// Adds an ordered list of cells to an existing model.
    ///
    /// - Parameters:
    ///   - cells: Cells in import order. Formulas resolve only against cells earlier
    ///     in this list, and only against cells passed to this same call — which is
    ///     what keeps each sheet's references inside its own sheet.
    ///   - model: The model to add nodes to.
    ///   - labelPrefix: Prepended to each node label, e.g. `Inputs!`, so that sheets
    ///     sharing a cell reference do not collide in the model's name index.
    ///   - section: The section these cells belong to.
    ///   - warnings: Accumulated import warnings.
    /// - Returns: This call's cell-to-node mapping.
    private static func addCells(
        _ cells: [(reference: String, value: CellValue)],
        to model: ExcelModel,
        labelPrefix: String,
        section: String,
        warnings: inout [String]
    ) -> [CellRef: NodeRef] {
        var cellToNode: [CellRef: NodeRef] = [:]

        for (reference, value) in cells {
            let cellRef = CellRef(reference)
            let refString = labelPrefix + reference

            switch value {
            case .number(let num):
                let ref = model.addInput(
                    label: refString,
                    value: num,
                    section: section
                )
                cellToNode[cellRef] = ref

            case .text(let str):
                let ref = model.addTextInput(
                    label: refString,
                    value: str,
                    section: section
                )
                cellToNode[cellRef] = ref

            case .formula(let ast, _):
                let nodeFormula = convertAST(
                    ast,
                    cellToNode: cellToNode,
                    cell: refString,
                    warnings: &warnings
                )
                let ref = model.addFormula(
                    label: refString,
                    formula: nodeFormula,
                    section: section
                )
                cellToNode[cellRef] = ref

            case .bool(let b):
                let ref = model.addFormula(
                    label: refString,
                    formula: .bool(b),
                    section: section
                )
                cellToNode[cellRef] = ref

            case .blank:
                break

            case .array:
                // Array formulas are how Excel stores data tables ({=TABLE(r,c)}),
                // which are the detection signal for sensitivity-table recognition.
                // Recognition is Phase 6; naming them here is what stops the signal
                // from being lost silently before it can be built on.
                warnings.append(
                    "Array formula at \(refString) was not imported. Array formulas are "
                        + "how Excel stores data tables ({=TABLE(r,c)}); recognizing them "
                        + "is not yet supported"
                )

            case .date:
                warnings.append("Unsupported cell type 'date' at \(refString)")

            case .error(let excelError):
                warnings.append(
                    "Unsupported cell type 'error' at \(refString): the cell holds "
                        + "\(excelError.rawValue)"
                )
            }
        }

        return cellToNode
    }

    // MARK: - Private

    private static func convertAST(
        _ ast: FormulaAST,
        cellToNode: [CellRef: NodeRef],
        cell: String,
        warnings: inout [String],
        depth: Int = 0
    ) -> NodeFormula {
        guard depth < 500 else {
            warnings.append(
                "Formula at \(cell) exceeds the maximum nesting depth of 500; "
                    + "the remainder was replaced with DEPTH_EXCEEDED"
            )
            return .text("DEPTH_EXCEEDED")
        }

        switch ast {
        case .cellRef(let cellRef):
            if let nodeRef = cellToNode[cellRef] {
                return .ref(nodeRef)
            }
            warnings.append(
                "Formula at \(cell) references \(cellRef.reference), which the importer "
                    + "has not seen; the reference was replaced with the literal "
                    + "text REF:\(cellRef.reference)"
            )
            return .text("REF:\(cellRef.reference)")

        case .cellRange(let range):
            return convertRange(range, cellToNode: cellToNode, cell: cell, warnings: &warnings)

        case .number(let value):
            return .number(value)

        case .text(let value):
            return .text(value)

        case .bool(let value):
            return .bool(value)

        case .add(let lhs, let rhs):
            return .add(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .subtract(let lhs, let rhs):
            return .subtract(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .multiply(let lhs, let rhs):
            return .multiply(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .divide(let lhs, let rhs):
            return .divide(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .power(let base, let exponent):
            return .power(
                convertAST(base, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(exponent, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .negate(let expr):
            return .negate(
                convertAST(expr, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .function(let name, let args):
            return .function(name, args.map {
                convertAST($0, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            })

        case .sheetRef, .namedRange, .error, .concatenate,
             .equal, .notEqual, .greaterThan, .lessThan,
             .greaterOrEqual, .lessOrEqual:
            warnings.append(
                "Unsupported formula node '\(nodeKindName(ast))' at \(cell); "
                    + "it was replaced with UNSUPPORTED"
            )
            return .text("UNSUPPORTED")
        }
    }

    /// Converts a `CellRange` into a ``NodeFormula/range(_:)`` of node references.
    ///
    /// ``NodeFormula/range(_:)`` re-derives the exported `CellRange` from its first and
    /// last reference, so both endpoints must resolve for the range to survive a round
    /// trip. A range whose endpoint is blank, or which sits above the cells it covers so
    /// that they have not been imported yet, cannot be anchored: it warns and degrades
    /// rather than silently exporting a narrower range than the source workbook had.
    ///
    /// Interior cells that do not resolve are skipped without a warning. A blank
    /// separator row inside `SUM(D5:D16)` is ordinary Excel, not a defect, and the
    /// exported range is unaffected because only the endpoints determine it.
    ///
    /// - Parameters:
    ///   - range: The source range.
    ///   - cellToNode: Cells imported so far, in workbook order.
    ///   - cell: The cell whose formula contains this range, for warning messages.
    ///   - warnings: Accumulated import warnings.
    /// - Returns: A ``NodeFormula/range(_:)``, or `.text("UNSUPPORTED")` if unanchored.
    private static func convertRange(
        _ range: CellRange,
        cellToNode: [CellRef: NodeRef],
        cell: String,
        warnings: inout [String]
    ) -> NodeFormula {
        guard cellToNode[range.start] != nil, cellToNode[range.end] != nil else {
            warnings.append(
                "Range \(range.reference) at \(cell) could not be anchored: its first or "
                    + "last cell is blank, or had not been imported when the formula was "
                    + "converted; the range was replaced with UNSUPPORTED"
            )
            return .text("UNSUPPORTED")
        }

        // `range.cells` runs from `start` to `end` in order, so the surviving
        // references keep both endpoints in their original positions.
        let refs = range.cells.compactMap { cellToNode[$0] }
        return .range(refs)
    }

    /// The `FormulaAST` case name for a node, used to make warnings specific.
    ///
    /// - Parameter ast: The node to name.
    /// - Returns: The case name, matching the `FormulaAST` declaration.
    private static func nodeKindName(_ ast: FormulaAST) -> String {
        switch ast {
        case .cellRef: return "cellRef"
        case .cellRange: return "cellRange"
        case .sheetRef: return "sheetRef"
        case .namedRange: return "namedRange"
        case .number: return "number"
        case .text: return "text"
        case .bool: return "bool"
        case .error: return "error"
        case .add: return "add"
        case .subtract: return "subtract"
        case .multiply: return "multiply"
        case .divide: return "divide"
        case .power: return "power"
        case .negate: return "negate"
        case .concatenate: return "concatenate"
        case .equal: return "equal"
        case .notEqual: return "notEqual"
        case .greaterThan: return "greaterThan"
        case .lessThan: return "lessThan"
        case .greaterOrEqual: return "greaterOrEqual"
        case .lessOrEqual: return "lessOrEqual"
        case .function: return "function"
        }
    }
}
