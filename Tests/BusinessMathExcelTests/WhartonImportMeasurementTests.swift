import Foundation
import Testing
@testable import BusinessMathExcel
import BusinessMath
import SwiftXLSX

/// Measures import fidelity against a workbook Excel actually wrote.
///
/// The rest of the suite builds workbooks with ``ModelExporter`` and reads them
/// back, which only ever exercises the shapes this package emits. This one reads
/// the Wharton LBO Practice Model — see `Tests/Fixtures/README.md` for how to
/// fetch it, and why it is not checked in.
///
/// These tests report a measurement rather than enforce a threshold. Coverage is
/// tracked as a progress metric toward 100%, not as a gate that fails a build.
@Suite(.enabled(
    if: WhartonFixture.isPresent,
    "Wharton-LBO-Practice-Model.xlsx is not present. See Tests/Fixtures/README.md to fetch it."
))
struct WhartonImportMeasurementTests {

    private func fixture() throws -> Workbook {
        try Workbook(contentsOf: WhartonFixture.url)
    }

    // MARK: - The Fixture Identifies Itself

    @Test func workbookHasTheExpectedSheets() throws {
        let workbook = try fixture()
        #expect(workbook.sheets.map(\.name) == ["KEY NOTES", "BLANK MODEL", "ANSWER KEY"])
    }

    @Test func answerKeyCarriesThePublishedIRR() throws {
        let workbook = try fixture()
        let answerKey = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })

        // C64 = IRR(D61:I61). Excel's cached result is the published 24.67%, which
        // is what makes this the right file rather than merely a similar one.
        guard case .formula(_, let cached) = answerKey.cell(at: "C64"),
              case .number(let irr)? = cached else {
            Issue.record("ANSWER KEY!C64 should be a formula with a cached value")
            return
        }
        #expect(abs(irr - 0.2467) <= 0.0001)
    }

    // MARK: - Recognition

    @Test func recognizesThePeriodAxisOnTheModelSheets() throws {
        let workbook = try fixture()
        for name in ["ANSWER KEY", "BLANK MODEL"] {
            let sheet = try #require(workbook.sheets.first { $0.name == name })
            let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

            #expect(grid.orientation == .periodsAcrossColumns, "\(name)")
            #expect(grid.axisLine == 27, "\(name): the axis is row 27")
            #expect(grid.axisCells.map(\.reference) == ["E27", "F27", "G27", "H27", "I27", "J27"], "\(name): 2023 through 2028")
            #expect(grid.diagnostics.isEmpty, "\(name): \(grid.diagnostics)")
        }
    }

    @Test func theNotesSheetHasNoPeriodAxis() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "KEY NOTES" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

        #expect(grid.orientation == nil, "A page of prose is not a model")
        #expect(grid.diagnostics.map(\.code) == [.noPeriodAxis])
    }

    @Test func theAxisIsReadFromAComputedHeaderRow() throws {
        // Only E27 is a typed year; F27 onward are `=E27+1`. An axis detector that
        // ignored what the file recorded Excel computing would find nothing here,
        // which is the common case rather than the exotic one.
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(sheet)

        #expect(result.cachedValues[CellRef("E27")] == nil, "E27 is typed, not computed")
        #expect(result.cachedValues[CellRef("F27")] == .number(2024))
    }

    @Test func recoversTheModelsSixYearTimeline() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let (axis, diagnostics) = PeriodAxis.build(from: grid)

        let recovered = try #require(axis)
        #expect(recovered.count == 6, "2023 plus five projection years")
        #expect(recovered.granularity == .annual)
        #expect(recovered.periods == (2023...2028).map(Period.year))
        #expect(recovered.sources.map(\.reference) == grid.axisCells.map(\.reference))
        #expect(diagnostics.isEmpty, "Got: \(diagnostics)")
    }

    @Test func bindsTheProfitAndLossRowsToTheirLabels() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try #require(PeriodAxis.build(from: grid).axis)
        let (series, _) = LabeledSeries.bind(in: grid, axis: axis)

        let names = Set(series.map(\.name))
        for expected in ["Revenue", "EBITDA", "EBIT", "Less: D&A", "Less: Interest"] {
            #expect(names.contains(expected), "Expected a series named \"\(expected)\"")
        }

        let revenue = try #require(series.first { $0.name == "Revenue" })
        #expect(revenue.populatedCells.count == axis.count, "Revenue runs the full timeline")
    }

    @Test func reportsRecognitionCoverageAndUniformity() throws {
        let workbook = try fixture()

        for name in ["ANSWER KEY", "BLANK MODEL"] {
            let sheet = try #require(workbook.sheets.first { $0.name == name })
            let imported = ModelImporter.importSheet(sheet)
            let grid = SheetGrid.build(from: imported)
            guard let axis = PeriodAxis.build(from: grid).axis else {
                Issue.record("\(name) should have a period axis")
                return
            }
            let (series, bindingDiagnostics) = LabeledSeries.bind(in: grid, axis: axis)
            let (uniformity, uniformityDiagnostics) = FormulaUniformity.assess(series, in: grid)

            // A cell is accounted for if the recognizer can say what it is: a value
            // in a series, the label naming that series, or a heading on the axis.
            var explained = Set(series.flatMap(\.populatedCells))
            explained.formUnion(series.compactMap(\.labelCell))
            explained.formUnion(axis.sources)
            let recognized = explained.count
            let coverage = Coverage(
                populatedCells: grid.populatedCells, recognizedCells: recognized)

            let uniform = uniformity.filter { $0.kind == .uniform }.count
            let seeded = uniformity.filter { $0.kind == .seededRollforward }.count
            let broken = uniformity.filter { $0.kind == .nonUniform }.count

            // The stage figure above counts what *binding* explains. The recognizer
            // also reads assumptions outside the timeline, so its own coverage is
            // the number to quote; reporting only the first understates the whole
            // by however much of the sheet is not a period series.
            let whole = ExcelRecognizer.recognize(sheet, in: workbook).coverage

            print("""
                WHARTON recognition — \(name)
                  periods            \(axis.count) (\(axis.granularity))
                  populated cells    \(grid.populatedCells)
                  bound to series    \(recognized)  (\(Int(coverage.fraction * 100))%)
                  recognized in all  \(whole.recognizedCells)  (\(Int(whole.fraction * 100))%)
                  series bound       \(series.count)
                    uniform          \(uniform)
                    seeded forward   \(seeded)
                    non-uniform      \(broken)
                  diagnostics        \(bindingDiagnostics.count + uniformityDiagnostics.count)
                """)

            // Reported, never gated. Coverage is a progress metric toward 100%,
            // and a build that fails on it invites recognizing things badly to
            // move the number.
            #expect(series.count > 0, "\(name): something should bind")
        }
    }

    /// How far a recognized plan gets toward running, and what stops it.
    ///
    /// Recognition coverage says how much of the sheet we can name. This says how
    /// much of it we can *run*, which is the harder number and the one that moves
    /// last. Materialization throws on the first unresolved reference rather than
    /// building a definition with a hole in it, so a single row lost upstream
    /// stops the whole sheet — which is the point of reporting both.
    @Test func reportsMaterializationReach() throws {
        let workbook = try fixture()

        for name in ["ANSWER KEY", "BLANK MODEL"] {
            let sheet = try #require(workbook.sheets.first { $0.name == name })
            let plan = ExcelRecognizer.recognize(sheet, in: workbook)

            var byCode: [String: Int] = [:]
            for diagnostic in plan.diagnostics { byCode[diagnostic.code.rawValue, default: 0] += 1 }

            var outcome = "runs"
            var cycles = 0
            var evaluated = 0
            do {
                let built = try ModelMaterializer.build(from: plan.model)
                cycles = try built.definition.dependencyReport().cycles.count
                let driver = PeriodDriver(
                    definition: built.definition, rollforwards: built.rollforwards)
                evaluated = try driver.run(over: built.periods).count
            } catch {
                outcome = "\(error)"
            }

            let codes = byCode.sorted { $0.key < $1.key }
                .map { "\($0.key) x\($0.value)" }
                .joined(separator: ", ")

            print("""
                WHARTON materialization — \(name)
                  accounts           \(plan.model.accounts.count)
                  rollforwards       \(plan.model.rollforwards.count)
                  residue            \(plan.model.residue.count)
                  diagnostics        \(codes)
                  cycles             \(cycles)
                  evaluated accounts \(evaluated)
                  outcome            \(outcome)
                """)

            // Reported, never gated — same reason as coverage above.
            #expect(plan.model.accounts.count > 0, "\(name): something should translate")
        }
    }

    /// What the sheet says its numbers are.
    ///
    /// The gate from §18.6: every `$`-formatted account is money, every genuine
    /// `%` one is a proportion, nothing formatted `General` is given a unit, and
    /// the count left unitless is reported rather than minimised.
    @Test func reportsInferredUnits() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let plan = ExcelRecognizer.recognize(sheet, in: workbook)

        var byUnit: [String: Int] = [:]
        var wrong: [String] = []
        for account in plan.model.accounts {
            byUnit[account.unit?.rawValue ?? "—", default: 0] += 1

            // Every cell's own dimension, checked against the account's.
            let stated = Set(
                account.provenance.compactMap {
                    UnitInference.dimension(of: grid.numberFormats[$0])
                })
            guard stated.count == 1, let only = stated.first else { continue }
            let expected = only == .ratio && account.unit == .rate ? UnitKind.rate : only
            if account.unit != expected {
                wrong.append("\(account.name): cells say \(only), account says \(account.unit.map { "\($0)" } ?? "nothing")")
            }
        }

        print("""
            WHARTON units — ANSWER KEY
              accounts by unit   \(byUnit.sorted { $0.key < $1.key }
                    .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
              conflicts          \(plan.diagnostics.filter { $0.code == .unitConflict }.count)
              stating nothing    \(plan.diagnostics.filter { $0.code == .unitInferenceFailed }.count)
            """)

        #expect(wrong == [], "an account whose cells all state one dimension must carry it")
        #expect(plan.model.accounts.filter { $0.unit != nil }.count > 20, "and the sheet does state units, so something must have been read")
    }

    /// What the sheet emits as source, and how much of it is typed.
    ///
    /// The two numbers that matter are not "how much source" but how much of it
    /// the compiler will check. A definition emitted through the string API is a
    /// definition the build cannot verify — correct, but unchecked — so the split
    /// is the honest measure of what the typed layer bought on real input.
    @Test func reportsEmittedSource() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let plan = ExcelRecognizer.recognize(sheet, in: workbook).model

        let source = TypedSourceWriter.swiftSource(
            for: plan, sheetName: "ANSWER KEY", modelName: "AnswerKey")
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        let handles = lines.filter { $0.contains("LineItem<") }
        let definitions = lines.filter { $0.contains("model = model.defining(") }
        let untyped = definitions.filter { $0.contains("\", as: \"") }
        let typed = definitions.count - untyped.count

        var byUnit: [String: Int] = [:]
        for handle in handles {
            guard let open = handle.range(of: "LineItem<"),
                  let close = handle.range(of: ">(", range: open.upperBound..<handle.endIndex)
            else { continue }
            byUnit[String(handle[open.upperBound..<close.lowerBound]), default: 0] += 1
        }

        print("""
            WHARTON emitted source — ANSWER KEY
              lines                \(lines.count)
              typed line items     \(handles.count) — \(byUnit.sorted { $0.key < $1.key }
                    .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
              definitions          \(definitions.count)
                checked by build   \(typed)
                string API         \(untyped.count)
            """)

        // Reported, never gated — the same reason coverage is. A threshold here
        // would reward emitting typed source that happens to compile over emitting
        // the untyped spelling where the sheet genuinely said nothing.
        #expect(handles.count > 0, "the sheet does state units")
        #expect(definitions.count == plan.accounts.filter { $0.expression != nil }.count, "every derived account is emitted, typed or not — none is silently dropped")
    }

    /// The emitted source is valid Swift as far as this package can tell.
    ///
    /// Not a compile: that is what `GoldenSourceTests` is for, and it cannot be
    /// done for a fixture too large to check in. This is the weaker structural
    /// check that catches the failure a large sheet actually risks — an account
    /// name that breaks out of its string literal, or two accounts colliding on
    /// one identifier.
    @Test func theEmittedSourceIsStructurallySound() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let plan = ExcelRecognizer.recognize(sheet, in: workbook).model

        let source = TypedSourceWriter.swiftSource(
            for: plan, sheetName: "ANSWER KEY", modelName: "AnswerKey")

        let declared = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let range = line.range(of: "static let ") else { return nil }
                let rest = line[range.upperBound...]
                return rest.split(separator: " ").first.map(String.init)
            }
        #expect(declared.count == Set(declared).count, "two accounts sharing a Swift identifier would not compile. Got: \(Dictionary(grouping: declared, by: { $0 }).filter { $0.value.count > 1 }.keys)")

        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            #expect(line.filter { $0 == "\"" }.count % 2 == 0, "an unbalanced quote means a name broke out of its literal: \(line)")
        }
    }

    /// The sheet's IRR sensitivity table, read and mapped upstream.
    ///
    /// A 5×5 grid rather than the synthetic 2×3, which matters for orientation: the
    /// small fixture proves a transpose fails, and this proves the reading is right
    /// on the shape a real model actually uses. The values are the sheet's own,
    /// cached by Excel.
    @Test func readsTheSensitivityTable() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let plan = ExcelRecognizer.recognize(sheet, in: workbook)

        let table = try #require(plan.model.sensitivities.first, "the ANSWER KEY holds one IRR sensitivity table")

        #expect(table.rowDriver == "Revenue growth", "across the top")
        #expect(table.columnDriver == "Multiple (based on 2028 EBITDA)", "down the side")

        #expect(table.rowValues.count == 5)
        #expect(table.columnValues == [3, 4, 5, 6, 7], "exit multiples")
        for (actual, expected) in zip(table.rowValues, [0.06, 0.08, 0.10, 0.12, 0.14]) {
            #expect(abs(actual - expected) <= 1e-9)
        }

        #expect(table.results.count == 5, "one row per multiple")
        #expect(table.results.first?.count == 5, "one column per growth rate")

        // The grid rises in both directions — a higher exit multiple and faster
        // growth both help a return — so a transposed or reversed reading would
        // still be monotonic, and only the values themselves settle it.
        let first = try #require(table.results.first?.first)
        let last = try #require(table.results.last?.last)
        #expect(abs(first - -0.013185) <= 1e-5, "3× at 6% growth")
        #expect(abs(last - 0.420650) <= 1e-5, "7× at 14% growth")

        #expect(table.measuredCell == CellRef("O5"), "the corner cell, which points at the IRR in C64")
    }

    /// The mapping upstream keeps the orientation the analysis type documents.
    @Test func theSensitivityTableMapsUpstream() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let plan = ExcelRecognizer.recognize(sheet, in: workbook)
        let analysis = try #require(plan.model.sensitivities.first).analysis()

        #expect(analysis.inputDriver1 == "Multiple (based on 2028 EBITDA)")
        #expect(analysis.inputValues1 == [3, 4, 5, 6, 7])
        #expect(analysis.inputDriver2 == "Revenue growth")
        #expect(analysis.results.count == 5)
        #expect(abs(analysis.results[0][0] - -0.013185) <= 1e-5, "results[i][j] is inputValues1[i] against inputValues2[j]")
    }

    /// What the sheet's What-If table contributes, and what still blocks recomputing it.
    ///
    /// Reading a table is a different claim from being able to reproduce it. The
    /// second needs the measured output, and on this sheet that is an aggregate
    /// over the whole timeline — which is a thing a period-local model does not
    /// compute, by design. Reported rather than rounded off.
    @Test func reportsSensitivityRecognition() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let plan = ExcelRecognizer.recognize(sheet, in: workbook)

        let table = try #require(plan.model.sensitivities.first)
        let covered = table.cells.filter { grid.cells[$0] != nil }.count

        // What the measured cell points at, and whether the model can produce it.
        let measured = grid.formulaASTs[table.measuredCell]
        var target = "—"
        if case .cellRef(let reference)? = measured { target = reference.reference }
        let targetFormula = grid.formulaASTs[CellRef(target)]
        var aggregate = "—"
        if case .function(let name, _)? = targetFormula { aggregate = name }

        let resolvable = try ModelMaterializer.buildResolvable(from: plan.model)

        print("""
            WHARTON sensitivity — ANSWER KEY
              tables read          \(plan.model.sensitivities.count)
              drivers              \(table.columnDriver) × \(table.rowDriver)
              grid                 \(table.results.count) × \(table.rowValues.count)
              cells now counted    \(covered)
              measured cell        \(table.measuredCell.reference) → \(target) = \(aggregate)(…)
              recompute blocked by
                the output is an aggregate over the timeline, which a period-local
                model does not compute; and \(target) reduces a row this recognizer
                drops — \(resolvable.dropped.map(\.label).sorted())
            """)

        #expect(aggregate == "IRR", "the measured output is an internal rate of return over a whole row")
        #expect(resolvable.dropped.contains { $0.label == "Equity of PE Firm" }, "and that row is the one already recorded as beyond a one-rule-per-account model")
    }

    /// The measurement that matters: does the model agree with the sheet?
    ///
    /// Coverage says how much we can name; materialization says how much we can
    /// run. Neither says whether the numbers are *right*. This runs the recognized
    /// model over the timeline and compares every value against what Excel itself
    /// cached in that cell — the only reference that cannot be talked into
    /// agreeing with us.
    ///
    /// A row that grows off its own prior value prints its openings, so its cells
    /// belong to the carried account rather than to the one named for the formula.
    /// Comparing the wrong one of those reports every figure a period out, which
    /// is a bug in the comparison and looks exactly like a bug in the model.
    @Test func theRecognizedModelAgreesWithTheSheetsOwnValues() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try #require(PeriodAxis.build(from: grid).axis)

        let plan = ExcelRecognizer.recognize(sheet, in: workbook)
        let resolvable = try ModelMaterializer.buildResolvable(from: plan.model)
        let evaluated = try PeriodDriver(
            definition: resolvable.model.definition,
            rollforwards: resolvable.model.rollforwards
        ).run(over: resolvable.model.periods)

        var readAs: [String: String] = [:]
        for carry in plan.model.rollforwards where carry.closing == "\(carry.opening) Closing" {
            readAs[carry.closing] = carry.opening
        }

        let periodColumns = Set(axis.sources.map(\.column))
        var agreed = 0
        var disagreed: [String] = []

        for account in plan.model.accounts {
            guard let series = evaluated[readAs[account.name] ?? account.name] else { continue }
            let cells = account.provenance
                .filter { periodColumns.contains($0.column) }
                .sorted { $0.column < $1.column }

            for (index, period) in axis.periods.enumerated() {
                guard index < cells.count, let computed = series[period] else { continue }
                var cached: Double?
                if case .number(let value)? = grid.cachedValues[cells[index]] { cached = value }
                if case .input(let value)? = grid.cells[cells[index]] { cached = value }
                guard let expected = cached else { continue }

                // Relative, because the sheet spans a 0.4 margin and a 240 exit
                // value, and one absolute tolerance cannot be right for both.
                let error = abs(computed - expected) / max(abs(expected), 1)
                if error < 1e-4 { agreed += 1 } else {
                    disagreed.append(
                        "\(account.name) @\(cells[index].reference): \(computed) vs \(expected)")
                }
            }
        }

        print("""
            WHARTON agreement — ANSWER KEY
              dropped as unresolvable  \(resolvable.dropped.map(\.label).sorted())
              values agreeing          \(agreed)
              values disagreeing       \(disagreed.count)
            \(disagreed.map { "      \($0)" }.joined(separator: "\n"))
            """)

        #expect(disagreed.isEmpty, "every value the model produces must match the one Excel cached in that cell. A model that runs and disagrees is worse than one that refuses")
        #expect(agreed > 100, "and it must actually be checking something")
    }

    /// The collision that stopped the sheet, and the rule that resolves it.
    ///
    /// Rows 3 through 11 are two assumption tables side by side: a label in B with
    /// its value in D, and a second label in F with its value in H. Neither is a
    /// period series — they sit well above the timeline. But H is also the 2026
    /// column, so a label that swept the whole axis read `SUM(H9:H10)` — the middle
    /// table's sources-and-uses total — as `Revenue growth`'s 2026 value. The row
    /// held `10%` and a total, disagreed with itself, and was refused.
    ///
    /// Under Rule 1 a label owns a value only when no other text cell stands
    /// between them, so `H11` belongs to `F11` and `Revenue growth` no longer
    /// claims it. Six of the `ANSWER KEY`'s seven non-uniform rows were this one
    /// overlap; the one that remains is genuinely irregular.
    @Test func assumptionRowsDoNotCollideWithThePeriodAxis() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

        // The overlap itself is a fact about the sheet and has not gone away.
        #expect(grid.axisLine == 27, "the timeline is row 27")
        #expect(grid.formulaASTs[CellRef("H27")].map(FormulaSerializer.serialize) == "G27+1", "and H is one of its period columns")
        #expect(grid.formulaASTs[CellRef("H11")].map(FormulaSerializer.serialize) == "SUM(H9:H10)", "H11 is a sources-and-uses total")

        let axis = try #require(PeriodAxis.build(from: grid).axis)
        let (series, _) = LabeledSeries.bind(in: grid, axis: axis)

        #expect(!(series.contains { $0.populatedCells.contains(CellRef("H11")) }), "H11 belongs to the label in F11, not to anything in column B")

        let (uniformity, _) = FormulaUniformity.assess(series, in: grid)
        let nonUniform = uniformity.filter { $0.kind == .nonUniform }
        #expect(nonUniform.count == 1, "seven before Rule 1. Remaining: \(nonUniform.map(\.series.name))")
    }

    @Test func recognizesTheAtCloseColumnBeforeTheTimeline() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try #require(PeriodAxis.build(from: grid).axis)

        let anchor = try #require(axis.anchor, "column D is headed \"Closing\"")
        #expect(anchor.label == "Closing")
        #expect(anchor.source.reference == "D27")
        #expect(axis.count == 6, "and it is still not counted as a period")
    }

    @Test func reproducesThePublishedIRRThroughRecognition() throws {
        // The reference figure, reached through the pipeline rather than by reading
        // the sheet's cached answer: bind the equity row, take its at-close value
        // and its periods, and compute.
        //
        // The at-close column is what makes this work. Bound to period columns
        // alone the row is [0, 0, 0, 0, 240.98] with no investment in it, and a
        // return computed on that is meaningless — or worse, plausible.
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let imported = ModelImporter.importSheet(sheet)
        let grid = SheetGrid.build(from: imported)
        let axis = try #require(PeriodAxis.build(from: grid).axis)
        let (series, _) = LabeledSeries.bind(in: grid, axis: axis)

        let equity = try #require(series.first { $0.name == "Equity of PE Firm" })
        #expect(equity.anchorCell?.reference == "D61")

        func value(_ reference: CellRef?) -> Double? {
            guard let reference else { return nil }
            if case .number(let number)? = imported.cachedValues[reference] { return number }
            guard let node = imported.cellToNode[reference],
                  case .input(let literal)? = imported.model.kind(of: node) else { return nil }
            return literal
        }

        var flows: [Double] = []
        if let atClose = value(equity.anchorCell) { flows.append(atClose) }
        for cell in equity.cells { if let periodValue = value(cell) { flows.append(periodValue) } }

        #expect(flows.count == 6, "at close, then five years")
        #expect(flows.first == -80, "the equity cheque")

        let rate = try irr(cashFlows: flows)
        #expect(abs(rate - 0.2467) <= 0.0001, "the published IRR of 24.67%")
    }

    @Test func reproducesThePublishedMultipleOfMoney() throws {
        let workbook = try fixture()
        let sheet = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })

        guard case .formula(_, let exitCached) = sheet.cell(at: "I61"),
              case .number(let exit)? = exitCached,
              case .formula(_, let equityCached) = sheet.cell(at: "H10"),
              case .number(let invested)? = equityCached else {
            Issue.record("expected an exit value and an equity contribution")
            return
        }

        #expect(abs(exit / invested - 3.01) <= 0.01, "the published MoM of 3.01")
    }

    // MARK: - Import Fidelity

    @Test func everyPopulatedCellBecomesANode() throws {
        let workbook = try fixture()
        let answerKey = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(answerKey)

        let populated = answerKey.cellReferences.filter { reference in
            guard let value = answerKey.cell(at: reference) else { return false }
            if case .blank = value { return false }
            return true
        }.count

        #expect(result.model.nodeCount == populated, "Structural transcription must not drop cells; interpretation happens above this layer")
    }

    @Test func reportsImportFidelity() throws {
        let workbook = try fixture()
        let answerKey = try #require(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(answerKey)

        var clean = 0
        var degraded = 0
        for ref in result.model.allRefs {
            guard case .formula(let formula) = result.model.kind(of: ref) else { continue }
            if Self.isDegraded(formula) { degraded += 1 } else { clean += 1 }
        }

        print("""
            WHARTON import fidelity (ANSWER KEY):
              nodes            \(result.model.nodeCount)
              formula nodes    \(clean + degraded)  (\(clean) translated, \(degraded) degraded)
              warnings         \(result.warnings.count)
            """)

        #expect(clean > 0, "Some formulas must survive translation")
    }

    /// Whether a formula contains any of the importer's degrade sentinels.
    private static func isDegraded(_ formula: NodeFormula) -> Bool {
        switch formula {
        case .text(let value):
            return value == "UNSUPPORTED" || value == "DEPTH_EXCEEDED" || value.hasPrefix("REF:")
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs),
             .multiply(let lhs, let rhs), .divide(let lhs, let rhs),
             .power(let lhs, let rhs),
             .equal(let lhs, let rhs), .notEqual(let lhs, let rhs),
             .greaterThan(let lhs, let rhs), .lessThan(let lhs, let rhs),
             .greaterOrEqual(let lhs, let rhs), .lessOrEqual(let lhs, let rhs):
            return isDegraded(lhs) || isDegraded(rhs)
        case .negate(let expr):
            return isDegraded(expr)
        case .function(_, let args):
            return args.contains(where: isDegraded)
        case .ref, .number, .bool, .range:
            return false
        }
    }
}
