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

        /// What Excel last computed for each formula cell, as the file recorded it.
        ///
        /// Preserved because the file said it and discarding it would be a fidelity
        /// loss — recognition needs it to read a computed header row, and a
        /// sensitivity check needs it to compare against a recomputed grid.
        ///
        /// **A cached value is evidence about the sheet, never a substitute for a
        /// formula.** Putting one into a model in place of a formula that could not
        /// be translated is the failure this package exists to prevent; keeping the
        /// file's own record of it is not.
        public let cachedValues: [CellRef: CellValue]

        /// Each cell's number format string, exactly as the file states it.
        ///
        /// Carried, not interpreted. A format is frequently the only statement a
        /// workbook makes about what a number *is* — `0.4` formatted `0%` is a
        /// proportion, the same `0.4` formatted `"$"#,##0` is money, and the label
        /// beside it may say neither. Deciding what a format means belongs to
        /// `Recognition/`; this layer's contract is that it never interprets, and
        /// `General` is carried through as written rather than dropped for meaning
        /// nothing.
        public let numberFormats: [CellRef: String]

        /// Each formula cell's AST exactly as the file wrote it.
        ///
        /// ``NodeFormula`` references nodes rather than addresses, which is what
        /// makes a model independent of layout — but it therefore cannot say
        /// whether a reference was written `D14` or `$D$14`. That distinction is
        /// invisible to evaluation and decisive for geometry: a formula filled
        /// across a row keeps its absolute references fixed and shifts its relative
        /// ones, so two cells only share a shape if they agree about which is which.
        ///
        /// Preserved for that reason, alongside ``cachedValues``, on the same
        /// principle: the file said it, so discarding it is a fidelity loss.
        public let formulaASTs: [CellRef: FormulaAST]

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
                cachedValues: [:],
                numberFormats: [:],
                formulaASTs: [:],
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
        let cells = orderedCells(of: sheet)
        let cellToNode = addCells(
            cells, to: model, labelPrefix: "", section: "Imported", warnings: &warnings)
        return ImportResult(
            model: model,
            cellToNode: cellToNode,
            sheetCellToNode: [sheet.name: cellToNode],
            cachedValues: cachedValues(cells),
            numberFormats: numberFormats(of: sheet),
            formulaASTs: formulaASTs(cells),
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
        var cached: [CellRef: CellValue] = [:]
        var asts: [CellRef: FormulaAST] = [:]
        var formats: [CellRef: String] = [:]

        for sheet in workbook.sheets {
            let cells = orderedCells(of: sheet)
            perSheet[sheet.name] = addCells(
                cells,
                to: model,
                labelPrefix: "\(sheet.name)!",
                section: sheet.name,
                warnings: &warnings
            )
            // Cell references carry no sheet, so the first sheet's entries win, in
            // step with `cellToNode` below.
            cached.merge(cachedValues(cells)) { existing, _ in existing }
            asts.merge(formulaASTs(cells)) { existing, _ in existing }
            formats.merge(numberFormats(of: sheet)) { existing, _ in existing }
        }

        let firstMapping = workbook.sheets.first.flatMap { perSheet[$0.name] } ?? [:]
        return ImportResult(
            model: model,
            cellToNode: firstMapping,
            sheetCellToNode: perSheet,
            cachedValues: cached,
            numberFormats: formats,
            formulaASTs: asts,
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
            cachedValues: cachedValues(cells),
            numberFormats: [:],
            formulaASTs: formulaASTs(cells),
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
        // Pass 1 mints an identity for every cell that becomes a node, without
        // reading any formula. Pass 2 can then resolve a reference in either
        // direction, so a total placed above the figures it sums binds to them
        // rather than degrading to literal text.
        var cellToNode: [CellRef: NodeRef] = [:]
        for (reference, value) in cells where becomesNode(value) {
            cellToNode[identity(CellRef(reference))] = NodeRef(label: labelPrefix + reference)
        }

        // Pass 2 walks the same cells in the same order, so node order, section
        // membership, and warning order are all unchanged by the split.
        for (reference, value) in cells {
            let label = labelPrefix + reference
            let kind: NodeKind

            switch value {
            case .number(let number):
                kind = .input(number)

            case .text(let text):
                kind = .textInput(text)

            case .bool(let flag):
                kind = .formula(.bool(flag))

            case .formula(let ast, _):
                kind = .formula(
                    convertAST(ast, cellToNode: cellToNode, cell: label, warnings: &warnings)
                )

            case .blank:
                continue

            case .array:
                // Array formulas are how Excel stores data tables ({=TABLE(r,c)}),
                // which are the detection signal for sensitivity-table recognition.
                // Recognition is a later phase; naming them here is what stops the
                // signal from being lost silently before it can be built on.
                warnings.append(
                    "Array formula at \(label) was not imported. Array formulas are "
                        + "how Excel stores data tables ({=TABLE(r,c)}); recognizing them "
                        + "is not yet supported"
                )
                continue

            case .date:
                warnings.append("Unsupported cell type 'date' at \(label)")
                continue

            case .error(let excelError):
                warnings.append(
                    "Unsupported cell type 'error' at \(label): the cell holds "
                        + "\(excelError.rawValue)"
                )
                continue
            }

            guard let ref = cellToNode[identity(CellRef(reference))] else { continue }
            model.add(ref, kind: kind, section: section)
        }

        return cellToNode
    }

    /// The identity of a cell, with absolute markers discarded.
    ///
    /// `$D$11`, `$D11`, `D$11`, and `D11` all name the same cell. The `$` controls
    /// what happens when a formula is filled across a range, not which cell it
    /// points at — but `CellRef` is `Hashable` over its marker flags, so the four
    /// forms are four different dictionary keys. Absolute references are how every
    /// financial model pins a rate or an assumption, so keying the cell map on the
    /// raw reference loses exactly the references that matter most.
    ///
    /// - Parameter cellRef: A cell reference in any of the four forms.
    /// - Returns: The equivalent fully-relative reference.
    private static func identity(_ cellRef: CellRef) -> CellRef {
        guard cellRef.absoluteColumn || cellRef.absoluteRow else { return cellRef }
        return CellRef(column: cellRef.column, row: cellRef.row)
    }

    /// The cached results the file recorded for its formula cells.
    ///
    /// - Parameter cells: Cells in import order.
    /// - Returns: Cached values, keyed by cell identity with `$` markers discarded.
    private static func cachedValues(
        _ cells: [(reference: String, value: CellValue)]
    ) -> [CellRef: CellValue] {
        var cached: [CellRef: CellValue] = [:]
        for (reference, value) in cells {
            guard case .formula(_, let result) = value, let result else { continue }
            cached[identity(CellRef(reference))] = result
        }
        return cached
    }

    /// Each cell's number format string, keyed by cell identity.
    ///
    /// - Parameter sheet: The worksheet.
    /// - Returns: The formats, including `General` where the file states it.
    private static func numberFormats(of sheet: Worksheet) -> [CellRef: String] {
        var formats: [CellRef: String] = [:]
        for reference in sheet.cellReferences {
            guard let style = sheet.style(at: reference) else { continue }
            formats[identity(CellRef(reference))] = style.numberFormat.formatString
        }
        return formats
    }

    /// Each formula cell's AST as written, keyed by cell identity.
    ///
    /// - Parameter cells: Cells in import order.
    /// - Returns: The formula ASTs, with `$` markers intact inside them.
    private static func formulaASTs(
        _ cells: [(reference: String, value: CellValue)]
    ) -> [CellRef: FormulaAST] {
        var asts: [CellRef: FormulaAST] = [:]
        for (reference, value) in cells {
            guard case .formula(let ast, _) = value else { continue }
            asts[identity(CellRef(reference))] = ast
        }
        return asts
    }

    /// Whether a cell contributes a node to the model.
    ///
    /// Blank cells carry nothing, and the unsupported types are reported rather
    /// than represented, so neither earns an identity in pass 1.
    ///
    /// - Parameter value: The cell's value.
    /// - Returns: `true` if the cell becomes a node.
    private static func becomesNode(_ value: CellValue) -> Bool {
        switch value {
        case .number, .text, .bool, .formula:
            return true
        case .blank, .array, .date, .error:
            return false
        }
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
            if let nodeRef = cellToNode[identity(cellRef)] {
                return .ref(nodeRef)
            }
            warnings.append(
                "Formula at \(cell) references \(cellRef.reference), which holds no "
                    + "value on this sheet; the reference was replaced with the literal "
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

        case .equal(let lhs, let rhs):
            return .equal(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .notEqual(let lhs, let rhs):
            return .notEqual(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .greaterThan(let lhs, let rhs):
            return .greaterThan(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .lessThan(let lhs, let rhs):
            return .lessThan(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .greaterOrEqual(let lhs, let rhs):
            return .greaterOrEqual(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .lessOrEqual(let lhs, let rhs):
            return .lessOrEqual(
                convertAST(lhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1),
                convertAST(rhs, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            )

        case .function(let name, let args):
            return .function(name, args.map {
                convertAST($0, cellToNode: cellToNode, cell: cell, warnings: &warnings, depth: depth + 1)
            })

        // `.missing` joins these rather than becoming 0 or "". An omitted argument
        // is not a value, and `ExcelModel`'s `NodeFormula` has no way to say "not
        // there"; substituting one would report that the sheet said something it
        // did not, which is the failure this whole layer is built to avoid.
        case .sheetRef, .namedRange, .error, .concatenate, .missing:
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
        guard cellToNode[identity(range.start)] != nil,
              cellToNode[identity(range.end)] != nil else {
            warnings.append(
                "Range \(range.reference) at \(cell) could not be anchored: its first or "
                    + "last cell is blank, or had not been imported when the formula was "
                    + "converted; the range was replaced with UNSUPPORTED"
            )
            return .text("UNSUPPORTED")
        }

        // `range.cells` runs from `start` to `end` in order, so the surviving
        // references keep both endpoints in their original positions.
        let refs = range.cells.compactMap { cellToNode[identity($0)] }
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
        case .missing: return "missing"
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
