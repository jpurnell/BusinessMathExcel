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
        public let cellToNode: [CellRef: NodeRef]

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
            return ImportResult(model: ExcelModel(), cellToNode: [:], warnings: [])
        }
        return importSheet(sheet)
    }

    /// Imports a specific worksheet into an ``ExcelModel``.
    ///
    /// - Parameter sheet: The worksheet to import.
    /// - Returns: An ``ImportResult`` containing the model, cell-to-node mapping, and warnings.
    public static func importSheet(_ sheet: Worksheet) -> ImportResult {
        let model = ExcelModel()
        var cellToNode: [CellRef: NodeRef] = [:]
        var warnings: [String] = []

        let sortedRefs = sheet.cellReferences.sorted { a, b in
            let refA = CellRef(a)
            let refB = CellRef(b)
            if refA.row != refB.row { return refA.row < refB.row }
            return refA.column < refB.column
        }

        for refString in sortedRefs {
            let cellRef = CellRef(refString)
            guard let value = sheet.cell(at: refString) else { continue }

            switch value {
            case .number(let num):
                let ref = model.addInput(
                    label: refString,
                    value: num,
                    section: "Imported"
                )
                cellToNode[cellRef] = ref

            case .text(let str):
                let ref = model.addTextInput(
                    label: refString,
                    value: str,
                    section: "Imported"
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
                    section: "Imported"
                )
                cellToNode[cellRef] = ref

            case .bool(let b):
                let ref = model.addFormula(
                    label: refString,
                    formula: .bool(b),
                    section: "Imported"
                )
                cellToNode[cellRef] = ref

            case .blank:
                break

            case .date, .error, .array:
                warnings.append("Unsupported cell type at \(refString)")
            }
        }

        return ImportResult(
            model: model,
            cellToNode: cellToNode,
            warnings: warnings
        )
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
