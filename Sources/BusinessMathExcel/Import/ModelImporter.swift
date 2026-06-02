import SwiftXLSX

/// Imports a SwiftXLSX `Workbook` into an ``ExcelModel`` graph.
///
/// Walks the cells of the first worksheet, creates ``NodeRef`` identities for
/// each non-blank cell, and builds ``NodeFormula`` expressions from formula ASTs.
/// Value cells become inputs; formula cells become formula nodes; cells with
/// no dependents become outputs.
public enum ModelImporter {

    /// The result of importing a workbook.
    public struct ImportResult: Sendable {

        /// The imported model.
        public let model: ExcelModel

        /// Maps cell references to their corresponding node references.
        public let cellToNode: [CellRef: NodeRef]

        /// Warnings generated during import (e.g., unsupported cell types).
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
                let nodeFormula = convertAST(ast, cellToNode: cellToNode)
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
        depth: Int = 0
    ) -> NodeFormula {
        guard depth < 500 else { return .text("DEPTH_EXCEEDED") }

        switch ast {
        case .cellRef(let cellRef):
            if let nodeRef = cellToNode[cellRef] {
                return .ref(nodeRef)
            }
            return .text("REF:\(cellRef.reference)")

        case .number(let value):
            return .number(value)

        case .text(let value):
            return .text(value)

        case .bool(let value):
            return .bool(value)

        case .add(let lhs, let rhs):
            return .add(
                convertAST(lhs, cellToNode: cellToNode, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, depth: depth + 1)
            )

        case .subtract(let lhs, let rhs):
            return .subtract(
                convertAST(lhs, cellToNode: cellToNode, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, depth: depth + 1)
            )

        case .multiply(let lhs, let rhs):
            return .multiply(
                convertAST(lhs, cellToNode: cellToNode, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, depth: depth + 1)
            )

        case .divide(let lhs, let rhs):
            return .divide(
                convertAST(lhs, cellToNode: cellToNode, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, depth: depth + 1)
            )

        case .negate(let expr):
            return .negate(convertAST(expr, cellToNode: cellToNode, depth: depth + 1))

        case .function(let name, let args):
            return .function(name, args.map {
                convertAST($0, cellToNode: cellToNode, depth: depth + 1)
            })

        case .cellRange, .sheetRef, .namedRange, .error,
             .power, .concatenate,
             .equal, .notEqual, .greaterThan, .lessThan,
             .greaterOrEqual, .lessOrEqual:
            return .text("UNSUPPORTED")
        }
    }
}
