import BusinessMath
import SwiftXLSX

/// Turns a worksheet into a plan for a `ModelDefinition`.
///
/// Drives Stages 1 through 4: topology, timeline, label binding, uniformity, and
/// translation. **Never throws.** A sheet that does not fit yields a partial plan
/// plus diagnostics and residue, because a workbook is someone else's document and
/// refusing the whole of it over one row nobody can parse is not a service.
///
/// The one thing it will not do is invent. A row it cannot translate becomes
/// residue naming its cells and the reason; the cached value Excel left in those
/// cells is never promoted to stand in for the formula.
public enum ExcelRecognizer {

    /// Recognizes one worksheet.
    ///
    /// - Parameters:
    ///   - sheet: The worksheet to read.
    ///   - options: Recognizer options.
    ///   - workbook: The book the sheet came from, when there is one. Named ranges
    ///     are workbook-level, so a formula written `= Balance * Rate` cannot be
    ///     read from the sheet alone. Passing the book is what makes those names
    ///     resolvable; omitting it leaves them refused rather than guessed.
    /// - Returns: The plan, the diagnostics, and the coverage.
    public static func recognize(
        _ sheet: Worksheet,
        options: RecognizerOptions = RecognizerOptions(),
        in workbook: Workbook? = nil
    ) -> RecognitionResult {
        let imported = ModelImporter.importSheet(sheet)
        var grid = SheetGrid.build(
            from: imported, options: options,
            namedCells: namedCells(from: workbook, for: sheet))
        var diagnostics = grid.diagnostics

        let (axis, axisDiagnostics) = PeriodAxis.build(from: grid, options: options)
        diagnostics.append(contentsOf: axisDiagnostics)

        guard let axis else {
            return RecognitionResult(
                model: RecognizedModel(
                    periods: [], accounts: [], rollforwards: [], residue: []),
                diagnostics: diagnostics,
                coverage: Coverage(populatedCells: grid.populatedCells, recognizedCells: 0)
            )
        }

        let (series, bindingDiagnostics) = LabeledSeries.bind(in: grid, axis: axis)
        diagnostics.append(contentsOf: bindingDiagnostics)

        // Binding settles what each cell is called, including the disambiguation it
        // applies when two rows share a heading. Every name is settled *before* a
        // single formula is translated, because a translation reads these answers
        // and cannot be revised once a later collision renames something.
        let (boundScalars, scalarDiagnostics) = ScalarBlock.bind(in: grid, axis: axis)
        var assumptions: [ScalarAssumption] = []
        let seriesNames = Set(series.map(\.name))
        for assumption in boundScalars {
            // Both survive a collision. Dropping the assumption because a row shares
            // its heading loses a figure the model is built on, and leaves every
            // reference to it resolving to the row instead — the same confusion in
            // the other direction.
            guard seriesNames.contains(assumption.name) else {
                assumptions.append(assumption)
                continue
            }
            diagnostics.append(
                Diagnostic(
                    severity: .warning, code: .duplicateAccountName,
                    cell: assumption.labelCell,
                    message: "\"\(assumption.name)\" names both a series on the timeline and "
                        + "an assumption at \(assumption.labelCell.reference); the assumption "
                        + "is distinguished by its cell"))
            assumptions.append(
                ScalarAssumption(
                    name: "\(assumption.name) (\(assumption.labelCell.reference))",
                    labelCell: assumption.labelCell,
                    valueCell: assumption.valueCell))
        }

        for entry in series {
            for cell in entry.populatedCells { grid.name(entry.name, at: cell) }
            if let anchor = entry.anchorCell { grid.name(entry.name, at: anchor) }
        }
        for assumption in assumptions { grid.name(assumption.name, at: assumption.valueCell) }

        let (uniformity, uniformityDiagnostics) = FormulaUniformity.assess(series, in: grid)
        diagnostics.append(contentsOf: uniformityDiagnostics)

        var accounts: [RecognizedAccount] = []
        var rollforwards: [LagDecomposition.RecognizedRollforward] = []
        var residue: [Residue] = []
        var recognized: Set<CellRef> = Set(axis.sources)

        for report in uniformity {
            let entry = report.series
            let cells = entry.populatedCells + [entry.anchorCell].compactMap { $0 }

            // A row that disagrees with itself has no single formula, so it cannot
            // become an account. Picking one of its shapes would be the majority
            // vote decision D10 forbids.
            guard report.kind != .nonUniform else {
                residue.append(
                    Residue(label: entry.name, cells: cells, reason: .nonUniformRow))
                continue
            }

            guard let account = translate(
                entry,
                seeded: report.kind == .seededRollforward,
                in: grid,
                axis: axis,
                imported: imported,
                rollforwards: &rollforwards,
                diagnostics: &diagnostics,
                residue: &residue
            ) else { continue }

            accounts.append(account)
            recognized.formUnion(cells)
            if let labelCell = entry.labelCell { recognized.insert(labelCell) }
        }

        // Assumptions stated outside the timeline. They are translated last so a
        // name already taken by a series wins: a row with six periods of figures is
        // more surely an account than a label with one.
        diagnostics.append(contentsOf: scalarDiagnostics)

        for assumption in assumptions {
            guard let account = translate(
                assumption, in: grid, axis: axis, imported: imported,
                diagnostics: &diagnostics)
            else {
                residue.append(
                    Residue(
                        label: assumption.name,
                        cells: [assumption.labelCell, assumption.valueCell],
                        reason: .unsupportedFormulaNode))
                continue
            }
            accounts.append(account)
            recognized.insert(assumption.labelCell)
            recognized.insert(assumption.valueCell)
        }

        // A What-If table's cells were excluded from binding above, because a label
        // beside the grid would otherwise claim them. Reading the table is what
        // turns them from cells deliberately skipped into cells understood.
        let sensitivities = RecognizedSensitivity.read(in: grid, axis: axis)
        for table in sensitivities {
            recognized.formUnion(table.cells.filter { grid.cells[$0] != nil })
        }

        return RecognitionResult(
            model: RecognizedModel(
                periods: axis.periods,
                accounts: accounts,
                rollforwards: rollforwards,
                sensitivities: sensitivities,
                residue: residue
            ),
            diagnostics: diagnostics,
            coverage: Coverage(
                populatedCells: grid.populatedCells, recognizedCells: recognized.count)
        )
    }

    // MARK: - Private

    /// The workbook's names that point at a single cell on this sheet.
    ///
    /// Kept deliberately narrow. A name pointing at a range, at an expression, or
    /// at a *different* sheet is left out, so the formula holding it is refused
    /// with a reason rather than resolved to something nearby. Cross-sheet
    /// recognition is a stage of its own and pretending otherwise would produce a
    /// model that reads a plausible number off the wrong page.
    ///
    /// - Parameters:
    ///   - workbook: The book, when the caller has one.
    ///   - sheet: The sheet being recognized.
    /// - Returns: Names to cells on this sheet.
    private static func namedCells(
        from workbook: Workbook?, for sheet: Worksheet
    ) -> [String: CellRef] {
        guard let workbook else { return [:] }
        var resolved: [String: CellRef] = [:]
        for named in workbook.namedRanges.all {
            switch workbook.namedRanges.resolve(named.name, inSheet: sheet.name) {
            case .cell(let ref):
                resolved[named.name] = ref
            case .sheetCell(let reference) where reference.sheetName == sheet.name:
                resolved[named.name] = reference.range.start
            default:
                continue
            }
        }
        return resolved
    }

    /// Turns one assumption into an account holding for every period.
    ///
    /// A literal becomes an input repeated across the timeline — `Revenue growth`
    /// is 10% in all six years, not in one of them. A formula stays derived:
    /// `Total Purchase Price` is `Entry EBITDA * Purchase Multiple`, and flattening
    /// it to `200` would answer the question while discarding the model.
    ///
    /// - Parameters:
    ///   - assumption: The bound label and its value.
    ///   - grid: The sheet's topology.
    ///   - axis: The period axis, whose periods the value is spread across.
    ///   - imported: The import the grid was built from.
    /// - Returns: The account, or `nil` when the formula could not be expressed.
    private static func translate(
        _ assumption: ScalarAssumption,
        in grid: SheetGrid,
        axis: PeriodAxis,
        imported: ModelImporter.ImportResult,
        diagnostics: inout [Diagnostic]
    ) -> RecognizedAccount? {
        let provenance = [assumption.labelCell, assumption.valueCell]
        let stated = unit(
            of: [assumption.valueCell], label: assumption.name, in: grid,
            diagnostics: &diagnostics)

        if grid.formulaASTs[assumption.valueCell] != nil {
            guard let split = LagDecomposition.decompose(
                cell: assumption.valueCell, in: grid, axis: axis),
                split.diagnostics.isEmpty
            else { return nil }
            return RecognizedAccount(
                name: assumption.name, expression: split.expression, unit: stated,
                provenance: provenance)
        }

        guard case .input(let value)? = grid.cells[assumption.valueCell] else { return nil }
        var values: [Period: Double] = [:]
        for period in axis.periods { values[period] = value }
        return RecognizedAccount(
            name: assumption.name, values: values, unit: stated, provenance: provenance)
    }

    /// The unit an account's cells state, reporting silence and disagreement.
    ///
    /// The at-close cell counts. It holds one of the account's own figures — an
    /// opening balance, an equity cheque — and on the Wharton `ANSWER KEY` it is
    /// sometimes the only cell in the row formatted as money, the periods beside
    /// it carrying a plain number format. Leaving it out discards the sheet's only
    /// statement about what the row is.
    ///
    /// - Parameters:
    ///   - cells: The cells the account was read from.
    ///   - label: The account's name.
    ///   - grid: The sheet's topology, holding each cell's format.
    ///   - diagnostics: Findings collected so far.
    /// - Returns: The unit, or `nil` when the cells stated none or disagreed.
    private static func unit(
        of cells: [CellRef],
        label: String,
        in grid: SheetGrid,
        diagnostics: inout [Diagnostic]
    ) -> UnitKind? {
        let inferred = UnitInference.infer(
            formats: cells.map { grid.numberFormats[$0] }, label: label)

        if !inferred.conflicted.isEmpty {
            diagnostics.append(
                Diagnostic(
                    severity: .warning, code: .unitConflict, cell: cells.first,
                    message: "\"\(label)\" is formatted as "
                        + "\(inferred.conflicted.map(\.rawValue).sorted().joined(separator: " and "))"
                        + " in different periods, so no unit is taken from either. A row "
                        + "holding two dimensions is a modelling error or a row bound to the "
                        + "wrong cells"))
            return nil
        }

        if inferred.unit == nil {
            diagnostics.append(
                Diagnostic(
                    severity: .info, code: .unitInferenceFailed, cell: cells.first,
                    message: "\"\(label)\" states no unit: none of its cells carry a number "
                        + "format that says what the figures are. Reported rather than "
                        + "guessed, and a workbook that formats nothing is not defective"))
        }
        return inferred.unit
    }

    /// Turns one bound series into an account, or into residue.
    private static func translate(
        _ entry: LabeledSeries,
        seeded: Bool,
        in grid: SheetGrid,
        axis: PeriodAxis,
        imported: ModelImporter.ImportResult,
        rollforwards: inout [LagDecomposition.RecognizedRollforward],
        diagnostics: inout [Diagnostic],
        residue: inout [Residue]
    ) -> RecognizedAccount? {
        let cells = entry.populatedCells
        let anchor = [entry.anchorCell].compactMap { $0 }
        let provenance = anchor + cells
        guard !provenance.isEmpty else { return nil }

        // A row whose cells are all literals is data the model is given.
        let formulaCells = cells.filter { grid.formulaASTs[$0] != nil }

        // On a seeded row the first period is the seed and every period after it
        // is the rule, so the rule must be read from after the seed. Usually the
        // seed is a typed number and the first formula cell is already the second
        // period; when the seed is itself computed it is not, and reading the
        // first cell adopts the opening balance's own arithmetic as the rule for
        // all time. Only seeded rows skip: on a uniform row the first period may
        // be the one reaching into the at-close column, and that is the carry.
        var candidates = formulaCells
        if seeded, let first = cells.first, candidates.first == first {
            candidates.removeFirst()
        }
        guard let representative = candidates.first else {
            var values: [Period: Double] = [:]
            for (index, cell) in entry.cells.enumerated() {
                guard let cell, index < axis.periods.count,
                      let node = imported.cellToNode[cell],
                      case .input(let value)? = imported.model.kind(of: node) else { continue }
                values[axis.periods[index]] = value
            }
            guard !values.isEmpty else { return nil }
            return RecognizedAccount(
                name: entry.name, values: values,
                unit: unit(of: provenance, label: entry.name, in: grid, diagnostics: &diagnostics),
                provenance: provenance)
        }

        guard let split = LagDecomposition.decompose(
            cell: representative, in: grid, axis: axis) else { return nil }

        // Anything the translator could not express sends the row to residue with
        // the first reason given, rather than producing a formula with a hole in it.
        if let failure = split.diagnostics.first {
            diagnostics.append(contentsOf: split.diagnostics)
            residue.append(
                Residue(label: entry.name, cells: provenance, reason: failure.code))
            return nil
        }

        for carry in split.rollforwards where !rollforwards.contains(carry) {
            rollforwards.append(carry)
        }

        return RecognizedAccount(
            name: split.definedAccount ?? entry.name,
            expression: split.expression,
            unit: unit(of: provenance, label: entry.name, in: grid, diagnostics: &diagnostics),
            provenance: provenance
        )
    }
}
