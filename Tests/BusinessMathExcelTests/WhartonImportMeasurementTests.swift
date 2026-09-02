import XCTest
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
final class WhartonImportMeasurementTests: XCTestCase {

    private static let fixtureName = "Wharton-LBO-Practice-Model.xlsx"

    private func fixture() throws -> Workbook {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(Self.fixtureName)")

        guard (try? url.checkResourceIsReachable()) == true else {
            throw XCTSkip(
                "\(Self.fixtureName) is not present. See Tests/Fixtures/README.md to fetch it."
            )
        }
        return try Workbook(contentsOf: url)
    }

    // MARK: - The Fixture Identifies Itself

    func testWorkbookHasTheExpectedSheets() throws {
        let workbook = try fixture()
        XCTAssertEqual(workbook.sheets.map(\.name), ["KEY NOTES", "BLANK MODEL", "ANSWER KEY"])
    }

    func testAnswerKeyCarriesThePublishedIRR() throws {
        let workbook = try fixture()
        let answerKey = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })

        // C64 = IRR(D61:I61). Excel's cached result is the published 24.67%, which
        // is what makes this the right file rather than merely a similar one.
        guard case .formula(_, let cached) = answerKey.cell(at: "C64"),
              case .number(let irr)? = cached else {
            return XCTFail("ANSWER KEY!C64 should be a formula with a cached value")
        }
        XCTAssertEqual(irr, 0.2467, accuracy: 0.0001)
    }

    // MARK: - Recognition

    func testRecognizesThePeriodAxisOnTheModelSheets() throws {
        let workbook = try fixture()
        for name in ["ANSWER KEY", "BLANK MODEL"] {
            let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == name })
            let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

            XCTAssertEqual(grid.orientation, .periodsAcrossColumns, name)
            XCTAssertEqual(grid.axisLine, 27, "\(name): the axis is row 27")
            XCTAssertEqual(
                grid.axisCells.map(\.reference), ["E27", "F27", "G27", "H27", "I27", "J27"],
                "\(name): 2023 through 2028"
            )
            XCTAssertTrue(grid.diagnostics.isEmpty, "\(name): \(grid.diagnostics)")
        }
    }

    func testTheNotesSheetHasNoPeriodAxis() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "KEY NOTES" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

        XCTAssertNil(grid.orientation, "A page of prose is not a model")
        XCTAssertEqual(grid.diagnostics.map(\.code), [.noPeriodAxis])
    }

    func testTheAxisIsReadFromAComputedHeaderRow() throws {
        // Only E27 is a typed year; F27 onward are `=E27+1`. An axis detector that
        // ignored what the file recorded Excel computing would find nothing here,
        // which is the common case rather than the exotic one.
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(sheet)

        XCTAssertNil(result.cachedValues[CellRef("E27")], "E27 is typed, not computed")
        XCTAssertEqual(result.cachedValues[CellRef("F27")], .number(2024))
    }

    func testRecoversTheModelsSixYearTimeline() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let (axis, diagnostics) = PeriodAxis.build(from: grid)

        let recovered = try XCTUnwrap(axis)
        XCTAssertEqual(recovered.count, 6, "2023 plus five projection years")
        XCTAssertEqual(recovered.granularity, .annual)
        XCTAssertEqual(recovered.periods, (2023...2028).map(Period.year))
        XCTAssertEqual(recovered.sources.map(\.reference), grid.axisCells.map(\.reference))
        XCTAssertTrue(diagnostics.isEmpty, "Got: \(diagnostics)")
    }

    func testBindsTheProfitAndLossRowsToTheirLabels() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try XCTUnwrap(PeriodAxis.build(from: grid).axis)
        let (series, _) = LabeledSeries.bind(in: grid, axis: axis)

        let names = Set(series.map(\.name))
        for expected in ["Revenue", "EBITDA", "EBIT", "Less: D&A", "Less: Interest"] {
            XCTAssertTrue(names.contains(expected), "Expected a series named \"\(expected)\"")
        }

        let revenue = try XCTUnwrap(series.first { $0.name == "Revenue" })
        XCTAssertEqual(
            revenue.populatedCells.count, axis.count,
            "Revenue runs the full timeline"
        )
    }

    func testReportsRecognitionCoverageAndUniformity() throws {
        let workbook = try fixture()

        for name in ["ANSWER KEY", "BLANK MODEL"] {
            let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == name })
            let imported = ModelImporter.importSheet(sheet)
            let grid = SheetGrid.build(from: imported)
            guard let axis = PeriodAxis.build(from: grid).axis else {
                return XCTFail("\(name) should have a period axis")
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
            XCTAssertGreaterThan(series.count, 0, "\(name): something should bind")
        }
    }

    /// How far a recognized plan gets toward running, and what stops it.
    ///
    /// Recognition coverage says how much of the sheet we can name. This says how
    /// much of it we can *run*, which is the harder number and the one that moves
    /// last. Materialization throws on the first unresolved reference rather than
    /// building a definition with a hole in it, so a single row lost upstream
    /// stops the whole sheet — which is the point of reporting both.
    func testReportsMaterializationReach() throws {
        let workbook = try fixture()

        for name in ["ANSWER KEY", "BLANK MODEL"] {
            let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == name })
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
            XCTAssertGreaterThan(
                plan.model.accounts.count, 0, "\(name): something should translate")
        }
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
    func testTheRecognizedModelAgreesWithTheSheetsOwnValues() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try XCTUnwrap(PeriodAxis.build(from: grid).axis)

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
                        "\(account.name) @\(cells[index].reference): "
                            + "\(computed) vs \(expected)")
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

        XCTAssertTrue(
            disagreed.isEmpty,
            "every value the model produces must match the one Excel cached in that "
                + "cell. A model that runs and disagrees is worse than one that refuses"
        )
        XCTAssertGreaterThan(agreed, 100, "and it must actually be checking something")
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
    func testAssumptionRowsDoNotCollideWithThePeriodAxis() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))

        // The overlap itself is a fact about the sheet and has not gone away.
        XCTAssertEqual(grid.axisLine, 27, "the timeline is row 27")
        XCTAssertNotNil(grid.cells[CellRef("H27")], "and H is one of its period columns")
        XCTAssertNotNil(grid.formulaASTs[CellRef("H11")], "H11 is a sources-and-uses total")

        let axis = try XCTUnwrap(PeriodAxis.build(from: grid).axis)
        let (series, _) = LabeledSeries.bind(in: grid, axis: axis)

        XCTAssertFalse(
            series.contains { $0.populatedCells.contains(CellRef("H11")) },
            "H11 belongs to the label in F11, not to anything in column B"
        )

        let (uniformity, _) = FormulaUniformity.assess(series, in: grid)
        let nonUniform = uniformity.filter { $0.kind == .nonUniform }
        XCTAssertEqual(
            nonUniform.count, 1,
            "seven before Rule 1. Remaining: \(nonUniform.map(\.series.name))"
        )
    }

    func testRecognizesTheAtCloseColumnBeforeTheTimeline() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let grid = SheetGrid.build(from: ModelImporter.importSheet(sheet))
        let axis = try XCTUnwrap(PeriodAxis.build(from: grid).axis)

        let anchor = try XCTUnwrap(axis.anchor, "column D is headed \"Closing\"")
        XCTAssertEqual(anchor.label, "Closing")
        XCTAssertEqual(anchor.source.reference, "D27")
        XCTAssertEqual(axis.count, 6, "and it is still not counted as a period")
    }

    func testReproducesThePublishedIRRThroughRecognition() throws {
        // The reference figure, reached through the pipeline rather than by reading
        // the sheet's cached answer: bind the equity row, take its at-close value
        // and its periods, and compute.
        //
        // The at-close column is what makes this work. Bound to period columns
        // alone the row is [0, 0, 0, 0, 240.98] with no investment in it, and a
        // return computed on that is meaningless — or worse, plausible.
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let imported = ModelImporter.importSheet(sheet)
        let grid = SheetGrid.build(from: imported)
        let axis = try XCTUnwrap(PeriodAxis.build(from: grid).axis)
        let (series, _) = LabeledSeries.bind(in: grid, axis: axis)

        let equity = try XCTUnwrap(series.first { $0.name == "Equity of PE Firm" })
        XCTAssertEqual(equity.anchorCell?.reference, "D61")

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

        XCTAssertEqual(flows.count, 6, "at close, then five years")
        XCTAssertEqual(flows.first, -80, "the equity cheque")

        let rate = try irr(cashFlows: flows)
        XCTAssertEqual(rate, 0.2467, accuracy: 0.0001, "the published IRR of 24.67%")
    }

    func testReproducesThePublishedMultipleOfMoney() throws {
        let workbook = try fixture()
        let sheet = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })

        guard case .formula(_, let exitCached) = sheet.cell(at: "I61"),
              case .number(let exit)? = exitCached,
              case .formula(_, let equityCached) = sheet.cell(at: "H10"),
              case .number(let invested)? = equityCached else {
            return XCTFail("expected an exit value and an equity contribution")
        }

        XCTAssertEqual(exit / invested, 3.01, accuracy: 0.01, "the published MoM of 3.01")
    }

    // MARK: - Import Fidelity

    func testEveryPopulatedCellBecomesANode() throws {
        let workbook = try fixture()
        let answerKey = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
        let result = ModelImporter.importSheet(answerKey)

        let populated = answerKey.cellReferences.filter { reference in
            guard let value = answerKey.cell(at: reference) else { return false }
            if case .blank = value { return false }
            return true
        }.count

        XCTAssertEqual(
            result.model.nodeCount, populated,
            "Structural transcription must not drop cells; interpretation happens above this layer"
        )
    }

    func testReportsImportFidelity() throws {
        let workbook = try fixture()
        let answerKey = try XCTUnwrap(workbook.sheets.first { $0.name == "ANSWER KEY" })
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

        XCTAssertGreaterThan(clean, 0, "Some formulas must survive translation")
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
