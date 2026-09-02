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
    /// - Returns: The plan, the diagnostics, and the coverage.
    public static func recognize(
        _ sheet: Worksheet,
        options: RecognizerOptions = RecognizerOptions()
    ) -> RecognitionResult {
        let imported = ModelImporter.importSheet(sheet)
        let grid = SheetGrid.build(from: imported, options: options)
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

        return RecognitionResult(
            model: RecognizedModel(
                periods: axis.periods,
                accounts: accounts,
                rollforwards: rollforwards,
                residue: residue
            ),
            diagnostics: diagnostics,
            coverage: Coverage(
                populatedCells: grid.populatedCells, recognizedCells: recognized.count)
        )
    }

    // MARK: - Private

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
                name: entry.name, values: values, provenance: provenance)
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
            formula: split.formula,
            provenance: provenance
        )
    }
}
