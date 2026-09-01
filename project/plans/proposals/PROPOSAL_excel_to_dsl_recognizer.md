# Design Proposal: Excel→BusinessMathDSL Recognizer

**Date:** 2026-09-01
**Status:** **SUPERSEDED, same day, by `PROPOSAL_excel_to_model_recognizer.md`.** Not implemented.

> **Why the target changed.** This proposal aimed at `BusinessMathDSL`. Two findings retired it:
>
> 1. **`BusinessMathDSL` has zero consumers** — only its own four test files import it, and no
>    sibling package declares it as a dependency. It is being deleted
>    (`BusinessMath/project/plans/proposals/TypedModelAuthoring.md`).
> 2. **`ModelDefinition` is the better target and already ships.** Named accounts, string
>    formulas over `TimeSeries`, `requiredInputs()`, `evaluationOrder()`, SCC cycle detection,
>    and iterative cycle resolution all landed in `87a717e`. A workbook *is* named accounts with
>    formulas and cycles; the fit is far closer than typed scalar components ever were.
>
> Appendix A's Gaps B, C, and D dissolve against `ModelDefinition`. Gap E dissolves because every
> account in a `ModelDefinition` is a name. Gap A1 is subsumed by deleting the module containing
> it.
>
> **Still valid and carried forward verbatim:** the five-stage pipeline shape, `SheetGrid` /
> `PeriodAxis` / `LabeledSeries` (Stages 1–2), `Coverage`, the diagnostics-and-residue contract,
> per-cell provenance, and the `ModelImporter` defects in §2 — which are unchanged and still need
> fixing.
>
> **Read `PROPOSAL_excel_to_model_recognizer.md` for the live plan.**

**Master Plan Reference:** Architecture — Import pipeline (`.xlsx → ModelImporter → ExcelModel → FormulaMapper → BusinessMath`)

---

## 1. Objective

Complete the import half of the pipeline by recognizing the *semantic structure* of an
imported workbook and emitting a `BusinessMathDSL` model — either as live DSL values or as
reviewable Swift source.

Today `ModelImporter` produces an `ExcelModel` whose nodes are labeled by cell address
(`"B4"`, `"C7"`) and dumped into a single section named `"Imported"`. `FormulaMapper` then
counts function names into two `Set<String>` buckets. Neither step recovers what a workbook
*means*, and nothing in this package constructs a `CashFlowModel`, `Revenue`, or `Expenses`.

This proposal adds the missing layer: **`Recognition/`**, which turns addressed cells into
named, period-aware, role-assigned components with full provenance back to their source cells.

## 2. Motivation

**Current situation.** The stated mission is a *bidirectional* translation layer. The export
direction is complete (four single-sheet strategies, a multi-sheet exporter with cross-sheet
formula resolution). The import direction stops at a structural transcription:

- `ModelImporter.swift:57-61` — every node is `addInput(label: refString, …)`. The label *is*
  the cell address. The "named DAG, not addresses" property we advertise holds only for
  models we authored.
- `ModelImporter.swift:161-165` — `.cellRange`, `.sheetRef`, `.namedRange`, `.power`, and all
  six comparison operators collapse to `.text("UNSUPPORTED")`. Real financial workbooks are
  built from `SUM(D5:D16)`, `NPV(rate,D5:D16)`, and `(1+r)^n`.
- `convertAST` never receives the `warnings` array, so that loss is **silent**. Warnings only
  fire for `.date`/`.error`/`.array` cell *types* at line 93.
- `ModelImporter.swift:29-32` — `importWorkbook` takes `sheets.first`. We export multi-sheet
  but cannot import multi-sheet.

**Workaround today.** A developer who wants a workbook in the DSL reads it by eye and
hand-writes `CashFlowModel { … }`. There is no tooling assist.

**Drawback.** The hand-transcription step is where numbers get transposed, a growth rate gets
read off the wrong row, or a one-time cost silently becomes recurring — with no record of
which cell any figure came from. That is precisely the failure mode described in
*"Agents still can't automate Excel"* (orcaset, 2026): an out-of-band evaluator producing
plausible numbers that nothing traces back to the sheet. Provenance is the deliverable here,
not a nicety.

**Why now.** `BusinessMathDSL` exists and is a first-class library product of BusinessMath
(`Package.swift:12-18` in that repo). It is the natural import target, and it is currently
unreachable from this package — we depend on the `BusinessMath` product only
(`Package.swift:13-22`).

## 3. Proposed Architecture

A five-stage pipeline. Each stage is independently testable and consumes only the stage above,
so a failure is localized rather than diffused through one large translate function.

```
Workbook
  → [Stage 0] ModelImporter          (existing; extended — see §7)
  → [Stage 1] SheetGrid              layout + period-axis analysis
  → [Stage 2] LabeledSeries          label binding, orientation resolution
  → [Stage 3] RecognizedComponent    formula-shape pattern matching
  → [Stage 4] RecognizedModel        role assembly (Sendable plan)
  → [Stage 5] CashFlowModel  |  Swift source
```

**New Files:**

| File | Role |
|------|------|
| `Sources/BusinessMathExcel/Recognition/SheetGrid.swift` | Cell topology, orientation, period-axis detection |
| `Sources/BusinessMathExcel/Recognition/PeriodAxis.swift` | Recovered time axis (years / quarters, start period) |
| `Sources/BusinessMathExcel/Recognition/LabeledSeries.swift` | A text label bound to a run of value cells |
| `Sources/BusinessMathExcel/Recognition/SeriesFit.swift` | Constant / growth / percentage-of fit + residual |
| `Sources/BusinessMathExcel/Recognition/Lexicon.swift` | Label → role vocabulary, user-extensible |
| `Sources/BusinessMathExcel/Recognition/RecognizedModel.swift` | Sendable plan: components, residue, provenance |
| `Sources/BusinessMathExcel/Recognition/ExcelRecognizer.swift` | Stage 1–4 driver, public entry point |
| `Sources/BusinessMathExcel/Recognition/Diagnostic.swift` | Severity, code, cell, message |
| `Sources/BusinessMathExcel/Materialize/DSLMaterializer.swift` | Plan → live `CashFlowModel` (throws) |
| `Sources/BusinessMathExcel/Materialize/DSLSourceWriter.swift` | Plan → Swift source text |

**Modified Files:**

- `Sources/BusinessMathExcel/Import/ModelImporter.swift` — support `.cellRange` and `.power`;
  thread `warnings` through `convertAST`; add `importWorkbook(allSheets:)`.
- `Package.swift` — add the `BusinessMathDSL` product dependency; bump the BusinessMath pin.

**Module Placement.** `Recognition/` is a new peer of `Import/` and `Export/`. It is kept
separate from `Import/` deliberately: `Import/` is a faithful structural transcription with no
interpretation, and it must stay that way so a workbook we cannot interpret still round-trips.
Recognition is the interpretive layer stacked on top.

### The two-stage output split (key decision)

Stages 1–4 produce `RecognizedModel` — plain `Sendable` data. Stage 5 consumes it. This split
is forced by two properties of `BusinessMathDSL` verified in `../BusinessMath` at `v2.6.0`:

1. **No DSL type conforms to `Sendable`** (`grep -rc Sendable Sources/BusinessMathDSL/*.swift`
   → no matches). Our project rule requires all types be `Sendable`. If the recognizer
   returned DSL values directly, its result type could not conform.
2. **DSL initializers trap on out-of-range input.** `Base.init` calls `preconditionFailure`
   on a negative amount (`Revenue.swift:74`), `GrowthRate.init` on a rate below −100%
   (`Revenue.swift:90`), and `Seasonality.init` on factors that do not sum to 4.0
   (`Revenue.swift:106,111`); `Taxes.swift:102,118` and `Forecast.swift:28-151` do the same for
   rates, margins, and year counts. A recognizer that reads `-5000` from a cell and constructs
   `Base(-5000)` **crashes the process** — an untrappable failure driven by arbitrary user data.

So the plan stage carries validated plain scalars, and materialization validates ranges and
**throws** before ever calling a trapping initializer.

The source-writing sink is not a secondary convenience. For an agent workflow the reviewable
Swift text is the more useful artifact: it is diffable, it can be checked in, and a human can
see what was inferred before any of it runs.

## 4. API Surface

```swift
// MARK: - Entry point

/// Recognizes the semantic structure of an imported workbook.
///
/// Recognition is best-effort and never throws: a workbook that does not fit the
/// DSL's shape yields a partial model plus diagnostics, not an error.
public enum ExcelRecognizer {

    public static func recognize(
        _ workbook: Workbook,
        options: RecognizerOptions = RecognizerOptions()
    ) -> RecognitionResult

    public static func recognize(
        _ sheet: Worksheet,
        options: RecognizerOptions = RecognizerOptions()
    ) -> RecognitionResult
}

// MARK: - Options

public struct RecognizerOptions: Sendable {

    /// Where the time axis runs. `.auto` infers from header cells.
    public enum Orientation: Sendable, Equatable {
        case auto
        case periodsAcrossColumns
        case periodsDownRows
    }

    public var orientation: Orientation
    public var lexicon: Lexicon
    /// Components below this confidence are demoted to residue. Default `0.6`.
    public var minimumConfidence: Double
    /// Relative tolerance for constant/growth fits. Default `1e-9`.
    public var fitTolerance: Double
    /// Hard bound on the recovered period axis. Default `200`.
    public var maximumPeriods: Int
    /// Hard bound on cells scanned per sheet. Default `100_000`.
    public var maximumCells: Int

    public init(
        orientation: Orientation = .auto,
        lexicon: Lexicon = .standard,
        minimumConfidence: Double = 0.6,
        fitTolerance: Double = 1e-9,
        maximumPeriods: Int = 200,
        maximumCells: Int = 100_000
    )
}

// MARK: - Result

public struct RecognitionResult: Sendable {
    public let model: RecognizedModel
    public let diagnostics: [Diagnostic]
    public let coverage: Coverage
}

/// How much of the sheet the recognizer accounted for.
public struct Coverage: Sendable, Equatable {
    public let populatedCells: Int
    public let recognizedCells: Int
    /// `recognizedCells / populatedCells`, or `0` when the sheet is empty.
    public var fraction: Double { get }
}

public struct RecognizedModel: Sendable {
    public let periods: PeriodAxis
    public let components: [RecognizedComponent]
    /// Series that were bound to a label but matched no pattern.
    public let residue: [Residue]
}

/// The recovered time axis.
public struct PeriodAxis: Sendable, Equatable {
    public enum Granularity: Sendable, Equatable { case annual, quarterly }
    public let granularity: Granularity
    public let count: Int
    /// Header cells the axis was read from, in period order.
    public let sources: [CellRef]
}

// MARK: - Components

/// One recognized DSL component, with the cells it was read from.
public enum RecognizedComponent: Sendable, Equatable {
    case revenueBase(Double, source: CellRef)
    case revenueGrowth(Double, source: CellRef?, fit: SeriesFit)
    case seasonality([Double], sources: [CellRef])
    case fixedExpense(Double, label: String, source: CellRef)
    case variableExpense(percentage: Double, of: Role, source: CellRef, fit: SeriesFit)
    case oneTimeExpense(Double, year: Int, source: CellRef)
    case straightLineDepreciation(asset: Double, years: Int, sources: [CellRef])
    case corporateTaxRate(Double, source: CellRef)
    case stateTaxRate(Double, source: CellRef)
}

/// How well a scalar parameter explains an observed series.
public struct SeriesFit: Sendable, Equatable {
    /// Max relative deviation between the fitted series and the observed one.
    public let residual: Double
    /// Number of periods the fit was measured over.
    public let periods: Int
    /// `true` when `residual <= options.fitTolerance`.
    public let isExact: Bool
}

public struct Residue: Sendable, Equatable {
    public let label: String
    public let cells: [CellRef]
    public let reason: DiagnosticCode
}

// MARK: - Diagnostics

public struct Diagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable { case info, warning, error }
    public let severity: Severity
    public let code: DiagnosticCode
    public let cell: CellRef?
    public let message: String
}

public enum DiagnosticCode: String, Sendable, Equatable, CaseIterable {
    case unsupportedFormulaNode
    case ambiguousOrientation
    case noPeriodAxis
    case labelUnbound
    case varyingGrowthRate
    case varyingExpenseRatio
    case roleConflict
    case valueOutOfDSLRange
    case scanLimitReached
    case crossSheetReference
}

// MARK: - Lexicon

/// Maps sheet labels to DSL roles. Case- and whitespace-insensitive.
public struct Lexicon: Sendable {
    public static let standard: Lexicon
    public init(_ mapping: [Role: Set<String>])
    public func role(for label: String) -> Role?
    /// Returns a copy with additional synonyms merged in.
    public func adding(_ mapping: [Role: Set<String>]) -> Lexicon
}

public enum Role: String, Sendable, Equatable, CaseIterable, Hashable {
    case revenue, expense, depreciation, tax, capex, workingCapital
}

// MARK: - Materialization (Stage 5)

public enum DSLMaterializer {
    /// Constructs a live `CashFlowModel`.
    ///
    /// - Throws: ``MaterializationError`` when a scalar falls outside the range a
    ///   DSL initializer accepts. The DSL traps rather than throwing on such input,
    ///   so every value is range-checked here first.
    public static func cashFlowModel(from model: RecognizedModel) throws -> CashFlowModel
}

public enum MaterializationError: Error, Sendable, Equatable {
    case valueOutOfRange(component: String, value: Double, permitted: ClosedRange<Double>)
    case missingRequiredRole(Role)
    case conflictingComponents(Role, count: Int)
}

public enum DSLSourceWriter {
    /// Emits compilable Swift source for the recognized model.
    ///
    /// Each emitted line carries a trailing `// <sheet>!<cell>` provenance comment.
    public static func swiftSource(
        for model: RecognizedModel,
        modelName: String = "importedModel"
    ) -> String
}
```

### Example output

For a workbook with `C6 = 1000000`, `D6 = C6*1.15`, `E6 = D6*1.15`, label `B6 = "Revenue"`:

```swift
// Recognized from Forecast.xlsx
let importedModel = CashFlowModel(
    revenue: Revenue {
        Base(1_000_000)      // Forecast!C6
        GrowthRate(0.15)     // Forecast!D6 (fit: exact over 2 periods)
    },
    expenses: Expenses {
        Fixed(100_000)       // Forecast!C9
    },
    taxes: Taxes {
        CorporateRate(0.21)  // Forecast!B3
    }
)
```

## 5. MCP Schema

**Tool Description:** Recognize the semantic structure of an Excel workbook and return a
BusinessMathDSL model plan with per-cell provenance.

**REQUIRED STRUCTURE (JSON):**
```json
{
  "workbookPath": "/abs/path/Forecast.xlsx",
  "sheetName": "Forecast",
  "orientation": "auto",
  "minimumConfidence": 0.6,
  "fitTolerance": 1e-9,
  "maximumPeriods": 200,
  "emitSource": true,
  "lexiconAdditions": {
    "revenue": ["Net sales", "Turnover"]
  }
}
```

**Parameter Types:**
- `workbookPath` (string, required): Absolute path to a `.xlsx` file.
- `sheetName` (string, optional): Worksheet to recognize. Omit to recognize all sheets.
- `orientation` (string, optional): One of `"auto"`, `"periodsAcrossColumns"`,
  `"periodsDownRows"`. Default `"auto"`.
- `minimumConfidence` (number, optional): `0.0`–`1.0`. Components below this are returned as
  residue. Default `0.6`.
- `fitTolerance` (number, optional): Relative tolerance for constant/growth fits. Must be > 0.
  Default `1e-9`.
- `maximumPeriods` (integer, optional): Upper bound on recovered periods. Must be > 0.
  Default `200`.
- `emitSource` (boolean, optional): Include generated Swift source in the response.
  Default `false`.
- `lexiconAdditions` (object, optional): Role → array of synonyms. Keys must be one of
  `"revenue"`, `"expense"`, `"depreciation"`, `"tax"`, `"capex"`, `"workingCapital"`.

**Response:** `{ "model": {...}, "diagnostics": [...], "coverage": {...}, "source": "..." }`.
Every component in `model.components` carries a `source` field naming the originating cell,
so a caller can verify any number against the sheet. No date values are exchanged; the period
axis is reported as a granularity plus a count.

**Determinism:** The recognizer is fully deterministic — no seed parameter is required.

## 6. Constraints & Compliance

**Concurrency:** Every recognizer type is an immutable value type conforming to `Sendable`.
The `RecognizedModel` plan is deliberately free of DSL types, which are *not* `Sendable`
(verified at `v2.6.0`); this keeps the recognizer's result type conformant without amending
BusinessMath. `DSLMaterializer` returns a non-`Sendable` `CashFlowModel` and is documented as
a same-isolation call.

**Safety:** No force unwraps, no `try!`, no force casts. All division guarded — growth-rate
and percentage fits divide by a prior-period value, so each site checks for zero and emits
`.varyingGrowthRate`/`.varyingExpenseRatio` rather than producing an infinity.

**No traps on user data:** The recognizer never calls a DSL initializer. `DSLMaterializer`
range-checks every scalar and throws `MaterializationError.valueOutOfRange` before
construction, because the DSL's own guards are `preconditionFailure` and cannot be caught.

**Bounded work:** `maximumCells` and `maximumPeriods` bound every scan. Reaching either emits
`.scanLimitReached` rather than truncating silently.

**No silent loss:** Every unrecognized construct produces either a `Diagnostic` or a `Residue`
entry. This is the rule the current importer violates, and the one this design exists to fix.

**Generics:** The DSL is `Double`-typed throughout (`Revenue.swift`, `Expenses.swift`,
`Taxes.swift`), so the recognizer is `Double`-typed too. Introducing a `Real` generic here
would be a conversion boundary with no consumer.

**DocC:** All public API documented per project rules.

## 7. Source & API Compatibility

**Breaking changes:** None to existing types. `Recognition/` and `Materialize/` are new
surface with no existing callers.

**Behavioral change to `ModelImporter`:** Two changes are visible to current callers.

1. `.cellRange` and `.power` stop producing `.text("UNSUPPORTED")` and start producing real
   nodes. Any caller that pattern-matches on the `"UNSUPPORTED"` sentinel changes behavior —
   this is a bug fix, and `ModelImporterTests` is the only in-repo caller.
2. `ImportResult.warnings` will become non-empty for workbooks that previously reported none.
   Callers that assert `warnings.isEmpty` will need updating. This is the intended fix.

`.sheetRef`, `.namedRange`, `.concatenate`, and the comparison operators remain unsupported in
this proposal, but now emit `.unsupportedFormulaNode` / `.crossSheetReference` diagnostics
instead of failing silently.

**Incremental adoption:** Yes. `ExcelRecognizer` is additive; `ModelImporter` continues to
work standalone for callers that want structural transcription without interpretation.

**Type-checking risk:** No overloads of existing functions introduced. The two
`recognize(_:options:)` overloads differ in first-parameter type (`Workbook` vs `Worksheet`),
which is unambiguous at every call site.

## 8. Backend Abstraction

**Not applicable.** Recognition is I/O-shaped, not compute-intensive: Stages 1–2 are
`O(populated cells)` with dictionary lookups, Stage 3 is `O(series × patterns)` where patterns
is a fixed small constant. A 100k-cell workbook is a few million scalar comparisons. There is
no kernel here worth handing to Metal or Accelerate, and adding a backend protocol would be
unjustified structure.

## 9. Dependencies

**Internal Dependencies:**
- `Import/ModelImporter.swift` — Stage 0 (extended by this proposal)
- `Model/NodeFormula.swift`, `Model/NodeRef.swift` — the graph being interpreted
- `SwiftXLSX` — `Workbook`, `Worksheet`, `CellRef`, `CellRange`, `FormulaAST`

**External Dependencies (new):**
- **`BusinessMathDSL`** product from the existing BusinessMath package dependency. Confirmed a
  first-class library product (`../BusinessMath/Package.swift:15-18`, target at line 125). No
  new *package* is introduced — only a second product from a package we already depend on.

**Version pin change — resolved 2026-09-01.** We pin `exact: "2.2.1"` (`Package.swift:13`); the
local working copy is at `v2.6.0`. Diffed: the `BusinessMathDSL` public API is **identical**
across those tags — 106 public symbols, none added, none removed. Only three files changed:

- `CashFlowModel.swift` — doc-comment only (a wrong `@CashFlowProjection` usage example).
- `Scenario.swift` / `ScenarioAnalysis.swift` — `sample()` gains a defaulted
  `seed: UInt64? = nil`, a `sample(using:)` generic overload is added, and a **Box-Muller pole
  bug** is fixed (the old path had no guard; `Double.random(in: 0..<1)` includes 0 and
  `log(0)` is −∞, so roughly one draw in 2⁵³ returned non-finite).

Both signature changes are source-compatible. **Recommendation: bump to `2.6.0`** — no DSL API
risk, and it carries a real fp-safety fix. Note that Phase 2/4 DSL work (Appendix A) will
require a further bump once landed.

Per `CLAUDE.md`, a pin change that fails with *"does not match previously recorded value"*
requires correcting both `Package.resolved` **and** the trust-on-first-use fingerprint at
`~/.swiftpm/security/fingerprints/<package>-<hash>.json`. Budget for this explicitly; it has
bitten this project before (commit `da8c5a8`).

## 10. Test Strategy

**Test Categories:**

- *Golden path* — hand-built fixture workbooks with known expected components.
- *Round-trip identity* — build a `CashFlowModel` in the DSL, export it with `ModelExporter`,
  recognize the result, assert the recovered components equal the originals.
- *Orientation* — periods across columns and down rows; ambiguous sheets emit
  `.ambiguousOrientation` and do not guess.
- *Negative recognition (critical)* — a workbook with **per-year varying** growth must produce
  **no** `.revenueGrowth` component and a `.varyingGrowthRate` diagnostic. Averaging the rates
  into a single plausible-looking scalar is the exact failure this design exists to prevent.
- *Provenance* — every emitted component's `source` cell actually holds the value claimed.
- *Trap avoidance* — a workbook with a negative revenue base or a tax rate of `1.4` must yield
  `MaterializationError.valueOutOfRange`, not a process trap.
- *Edge cases* — empty sheet, single period, label with no values, values with no label,
  duplicate labels (`.roleConflict`), a sheet at `maximumCells`.
- *Determinism* — same workbook recognized twice yields identical results, including
  diagnostic ordering.
- *Importer regression* — `SUM(D5:D16)` and `(1+r)^n` import as real nodes; unsupported nodes
  now appear in `warnings`.

**Reference Truth:**

1. **The DSL itself** for the round-trip property. `Revenue.swift:29-36` documents
   `Base(1_000_000)` + `GrowthRate(0.15)` → year 1 `1,000,000`, year 2 `1,150,000`,
   year 3 `1,322,500`. These are the library's own documented values, independently checkable.
2. **Excel** for formula-shape fixtures — expected values computed in Excel and recorded in
   the fixture's companion `.md`, never inferred.
3. **Wharton LBO Practice Model** (Penn Career Services, publicly available) as a realistic
   third-party workbook for coverage measurement. It is *not* expected to fully recognize; it
   is a benchmark for how honestly we report residue.

**Validation Trace (REQUIRED):**

> Fixture `RevenueGrowth.xlsx`, sheet `Forecast`:
> `B6 = "Revenue"`, `C6 = 1000000`, `D6 = C6*1.15`, `E6 = D6*1.15`.
> Excel evaluates `D6 = 1,150,000` and `E6 = 1,322,500`.
>
> `ExcelRecognizer.recognize(sheet)` must yield exactly:
> - `.revenueBase(1_000_000, source: CellRef("C6"))`
> - `.revenueGrowth(0.15, source: CellRef("D6"), fit: SeriesFit(residual: ≤ 1e-12, periods: 2, isExact: true))`
> - `coverage.fraction == 1.0`, `diagnostics == []`
>
> Then `DSLMaterializer.cashFlowModel(from:)` must produce a model whose
> `calculate(year: 3).revenue == 1_322_500` (accuracy `1e-6`), matching the DSL's own
> documented value in `Revenue.swift:36`.

> Negative-case fixture `VaryingGrowth.xlsx`:
> `C6 = 1000000`, `D6 = C6*1.12`, `E6 = D6*1.18`.
> Must yield `.revenueBase` **only**, a `.varyingGrowthRate` diagnostic at `E6`, and a
> `Residue` entry — and must **not** emit `.revenueGrowth(0.15, …)`.

Floating-point assertions use accuracy-based comparison per project testing rules.

## 11. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `development-guidelines/rules/architecture_decisions.md` for related decisions
- [x] Does this supersede an existing ADR? **No**
- [x] Does this amend an existing ADR? **No**
- [x] New ADR required? **Yes** — two decisions here outlive this feature

**New ADR Draft (required):**

- **Title:** Recognition emits a Sendable plan, not DSL values
- **Category:** architecture
- **Key decision:** The Excel→DSL path is split into a `Sendable` `RecognizedModel` plan and a
  separate materialization step, because `BusinessMathDSL` types are neither `Sendable` nor
  throwing-validated, and arbitrary workbook data would otherwise trap the process.

- **Title:** Lossy import must be loud
- **Category:** api
- **Key decision:** Any construct the import or recognition path cannot represent produces a
  `Diagnostic` or `Residue` entry. Silent substitution of a plausible value — including
  averaging a varying rate into a single scalar — is prohibited.

*Note:* `project/master_plan.md` has no "Collaboration Principles" section, though the
proposal template references one. Worth reconciling during the next doc-housekeeping pass.

## 12. Adversarial Review

**Strongest case for a different approach.**

A reviewer would reasonably argue: *skip the recognizer entirely and extend `BusinessMathDSL`
to accept per-period arrays* — `GrowthRate([0.12, 0.15, 0.09])`, `Fixed([…])`. Then import
becomes a near-mechanical transcription of each row into an array, and the whole
pattern-matching layer evaporates.

That alternative may genuinely be better. The DSL's expressiveness is the binding constraint
here, not our ability to detect patterns: `Revenue { Base; GrowthRate }` holds exactly *one*
scalar growth rate, so any workbook with year-varying growth — which is most real
workbooks — cannot be represented no matter how good the recognizer is. We are building a
sophisticated matcher against a target that may be too narrow.

**Where this design is most likely wrong.**

The load-bearing assumption is that **a useful fraction of real workbooks fit the DSL's scalar
shape.** If that fraction is near zero, this recognizer's honest behavior is to report
`coverage ≈ 0.1` and a page of residue on nearly every real input — technically correct,
practically useless. We would have built a very careful machine for producing "I can't
represent this."

Second: the label-binding heuristic assumes the Excel convention of labels left of values
(or above, for the transposed case). Workbooks with merged header blocks, multi-row headers,
or labels embedded in the number format will bind poorly, and `Coverage` will read as a
recognizer failure when it is really a layout-analysis failure.

A constraint accepted without much challenge: that `ModelImporter` must stay purely
structural. Fusing recognition into import would let the label column inform node naming
directly and would be simpler. It was kept separate to preserve a lossless transcription path,
but that is a judgment call, not a forced one.

**What an experienced critic would say.**

*"You are building an elaborate inference layer to hit a target API that is too narrow to
accept its own inferences, and you will discover this only after the pattern matcher works."*

**Response (revised 2026-09-01).** The critic is right, and the objection is now **accepted
rather than deferred.** With 100% Wharton coverage adopted as the goal, DSL expressiveness is
confirmed as the binding constraint, so widening `BusinessMathDSL` moves ahead of Stage 3 as a
hard prerequisite (§13 Alternative 1, and the DSL Gap Analysis below).

Two things survive unchanged from the original argument. First, Stages 1–2 are not wasted under
any outcome: `LabeledSeries` and `PeriodAxis` are exactly the inputs a widened DSL needs.
Second, `DSLSourceWriter` degrades gracefully — partial recognition still emits real Swift with
provenance comments and honest gaps.

**The change:** `Coverage` is promoted into the public result type and becomes a first-class
test assertion, measured on the Wharton workbook from Phase 1 onward. It is now a **progress
metric tracked to 100%**, not a go/no-go gate.

## 13. Alternatives Considered

**Alternative 1: Extend `BusinessMathDSL` first, then transcribe. — ADOPTED AS PREREQUISITE
(2026-09-01)**
- *Advantage:* Removes most of the inference problem; import becomes near-mechanical and the
  DSL gets strictly more expressive for hand-authors too.
- *Disadvantage:* It is a change to a different repository with its own release cycle, and it
  is a larger body of work than the recognizer that depends on it.
- *Status:* **No longer an alternative — it is a precondition.** With 100% Wharton coverage as
  the goal (§15 Q2), the binding constraint is DSL expressiveness, not pattern detection. See
  the DSL Gap Analysis below and the revised phasing.

**Alternative 2: Fuse recognition into `ModelImporter`.**
- *Advantage:* One pass, no intermediate types, and label context is available exactly where
  node names are assigned.
- *Disadvantage:* Destroys the lossless structural transcription path — a workbook we cannot
  interpret would no longer import at all — and makes the interpretation logic untestable
  without a full `Workbook` fixture for every case.
- *Why rejected:* The stages have genuinely different contracts. Import must never guess;
  recognition must guess and report its confidence.

**Alternative 3: Ship only `DSLSourceWriter`; drop `DSLMaterializer`.**
- *Advantage:* Sidesteps the non-`Sendable` and `preconditionFailure` problems entirely,
  since generated source is just text. Smaller surface.
- *Disadvantage:* No programmatic path from workbook to a live model, which blocks the MCP
  use case named in the master plan (return a computed result from a tool call).
- *Why rejected:* The trapping-initializer problem is solvable with range checks; giving up the
  live path to avoid it trades a real capability for a modest simplification. Kept as the
  fallback if materialization proves unstable.

**Alternative 4: Adopt orcaset's runtime model (effect handlers, fixed-point cycle solver).**
- *Advantage:* Genuinely handles circular workbooks (interest ↔ debt), which our DAG cannot
  represent at all.
- *Disadvantage:* It is a whole alternative evaluation engine, and we already have a modeling
  layer in `BusinessMathDSL`. Adopting it would mean maintaining two.
- *Why rejected:* Out of scope. Circularity is real and unaddressed — noted in §14 and §15 —
  but the answer belongs in the DSL, not in a second runtime bolted to the importer.

## 14. Future Directions

- **Per-period DSL components.** If Phase 1 coverage on realistic workbooks is low, widening
  `BusinessMathDSL` to accept arrays could turn most residue into recognized components.
- **Multi-sheet recognition.** Cross-sheet references currently produce a diagnostic; a
  workbook-level recognizer could resolve them, restoring symmetry with `MultiSheetExporter`.
- **Circularity.** Real workbooks contain interest ↔ debt cycles that neither our DAG nor the
  DSL represents. A detection pass that at least *reports* a cycle might come first.
- **Learned lexicon.** The `Lexicon` could be seeded from a corpus rather than hand-listed.
- **Confidence calibration.** `minimumConfidence` is currently a hand-set threshold; it could
  be tuned against a labeled corpus.
- **Named-range support.** `.namedRange` carries real semantic signal — an author already told
  us what a cell means — and might be a higher-yield recognition source than label binding.

## 15. Open Questions

1. **Does the BusinessMath pin move to `2.6.0`, or does `BusinessMathDSL` get consumed at
   `2.2.1`?** Needs a diff of the DSL API between those tags before Phase 1.
2. ~~**What coverage on the Wharton workbook is the go/no-go bar?**~~ **Resolved 2026-09-01:**
   **100% of the Wharton workbook is the goal.** 30% is an interim milestone, not a kill
   threshold. This makes Alternative 1 (widening `BusinessMathDSL`) a **prerequisite** rather
   than a fallback — see §13 and the revised phasing.
3. **Should `DSLMaterializer` exist in v1, or ship source-writing only?** (Alternative 3.)
4. **Should recognition failure on a *labeled* series be `.warning` or `.error`?** It is a
   normal outcome on real input, which argues for `.warning`, but that risks it being ignored.
5. **Quarterly support in v1?** `Revenue` supports `Seasonality`, and `CashFlowModel` has
   `calculateQuarters(year:)`, so the DSL is ready — but quarterly axis detection roughly
   doubles Stage 1's cases.

## 16. Documentation Strategy

**Documentation Type:** Narrative Article Required

**Complexity Threshold Check:**
- Does it combine 3+ APIs? **Yes** — `ModelImporter`, `ExcelRecognizer`, `DSLMaterializer`,
  `DSLSourceWriter`, plus `BusinessMathDSL` types.
- Does explanation require 50+ lines? **Yes** — the five-stage pipeline and the plan/materialize
  split both need worked examples.
- Does it need theory/background context? **Yes** — why recognition is lossy, and why honest
  residue reporting matters more than coverage, is the conceptual core.

**Article Name:** `RecognitionGuide.md` in `Sources/BusinessMathExcel/BusinessMathExcel.docc/`

Does not collide with any Swift symbol name (`ExcelRecognizer`, `RecognizedModel`,
`RecognitionResult` are all distinct).

---

---

## Appendix A: DSL Gap Analysis (added 2026-09-01)

With 100% Wharton coverage adopted as the goal, the recognizer's ceiling is set by what
`BusinessMathDSL` can express. `CashFlowModel.calculate(year:)` is, in full:

```swift
revenue      = revenue?.value(forYear: year) ?? 0
expenses     = expenses?.value(forYear: year, revenue: revenue) ?? 0
ebitda       = revenue - expenses
ebit         = ebitda - depreciation
taxes        = taxes?.value(on: ebit) ?? 0          // CashFlowModel.swift:197
netIncome    = ebit - taxes
freeCashFlow = netIncome + depreciation             // CashFlowModel.swift:223-230
```

The Wharton paper LBO requires: revenue, EBITDA, D&A, EBIT, **interest**, EBT, taxes, capex,
ΔNWC, FCF, draws, cash sweep, sweep paydown, debt before balloon, balloon payment, debt, debt
cash flows, purchase price, exit value, levered cash flow, MoM, IRR, sources & uses, and a 2-D
IRR sensitivity table.

| # | Gap | Severity | Evidence |
|---|-----|----------|----------|
| A | **Taxes computed on EBIT, not EBT.** No interest line exists anywhere in `CashFlowModel`, so an LBO's interest tax shield cannot be expressed. Produces a *wrong answer* for any levered model today — a correctness bug, not a missing feature. | Blocking | `CashFlowModel.swift:197` |
| B | **No time-varying parameters.** One `Base`, one `GrowthRate`, one `variablePercentage`, one `CorporateRate`. Wharton's flat 10% growth fits by luck; most real workbooks carry per-year assumptions. | Blocking | `Revenue.swift`, `Expenses.swift:138-144`, `Taxes.swift:127-131` |
| C | **No capital structure.** No debt balance, schedule, sweep, or balloon. `WACC`'s `CostOfDebt`/`DebtToEquity` are valuation ratios; `LiquidationWaterfall`/`Tier` distribute *proceeds*, not paydown over time. | Blocking | `WACC.swift`, `Tier.swift` |
| D | **No circularity resolution.** interest → average debt balance → cash sweep → FCF → interest is a genuine cycle. Wharton resolves it with Excel iterative calc plus a circuit breaker; `calculate(year:)` is straight-line with no fixed point. | Blocking | `CashFlowModel.swift:180-212` |
| E | **Two non-composing forecast models; labels destroyed.** `CashFlowModel` has no capex/ΔNWC; `Forecast` has `CapEx`/`WorkingCapital` but is consumed only by `DCFModel`. `Expenses` collapses every `Fixed(…)` into one `fixedAmount: Double`, so `Fixed(200_000) // Rent` + `Fixed(300_000) // Salaries` becomes `500_000` with both names gone — **directly defeating this proposal's provenance goal.** | High | `Expenses.swift:140-144`, `Forecast.swift:115-127` |

### Required BusinessMath work, in dependency order

This belongs in a **separate design proposal in the BusinessMath repository**; it is larger
than the recognizer that depends on it.

1. **Period-value primitive.** Replace bare `Double` parameters with a `Schedule`-like type:
   `.constant(x)` / `.growing(base:rate:)` / `.perPeriod([…])`. Highest leverage — fixes **B**
   and lets the recognizer transcribe an arbitrary row without inventing a scalar the sheet
   does not contain.
2. **Preserve line-item identity.** `Expenses` holds `[LineItem]` rather than summing to
   scalars. Fixes the provenance half of **E**.
3. **`DebtSchedule` component.** Draws, rate, sweep policy, balloon; introduces `interest` as a
   first-class line. Unblocks **C**.
4. **Move tax to EBT.** Fixes **A**, once (3) exists. Behavior change for existing callers —
   needs a deprecation story.
5. **Convergence loop.** Seeded iteration with tolerance, max-iters, and a thrown error on
   non-convergence. Fixes **D**. Borrow the *shape* of orcaset's `Iterate` / `_iterate_scc`;
   do not adopt their runtime (§13 Alternative 4).
6. **Unify `CashFlowModel` and `Forecast`** so capex/ΔNWC live in one place. Cleanup;
   deferrable.

Items 1–2 are self-contained and unblock recognizer Stages 1–3. Items 3–5 are the LBO block.

---

## Proposed Phasing (revised 2026-09-01)

Coverage on the Wharton workbook is tracked as a progress metric at every phase, targeting
100%. It is no longer a kill gate.

| Phase | Repo | Scope | Gate |
|-------|------|-------|------|
| 0 | Excel | `Package.swift`: add `BusinessMathDSL` product, bump pin to `2.6.0` | `swift build` clean |
| 1 | Excel | `ModelImporter` fixes (`.cellRange`, `.power`, threaded warnings) + Stages 1–2 + `Coverage` instrumented | Wharton coverage measured and reported |
| 2 | **BusinessMath** | DSL gap items 1–2 (period values, line-item identity) | DSL tests green; no API regressions |
| 3 | Excel | Stage 3 pattern matching + Stage 4 assembly | Golden path + negative-recognition tests green; **~30% Wharton coverage (interim)** |
| 4 | **BusinessMath** | DSL gap items 3–5 (debt schedule, tax on EBT, convergence) | Paper-LBO reproduces Wharton IRR 24.67% / MoM 3.01 |
| 5 | Excel | `DSLSourceWriter` | Round-trip identity test green |
| 6 | Excel | `DSLMaterializer` + trap-avoidance tests | Quality gate 0/0; **100% Wharton coverage** |
| 7 | Excel | `RecognitionGuide.md`, README, CHANGELOG, master plan reconciliation | Release |

Phases 2 and 4 are BusinessMath work and gate everything downstream of them. The interleaving
is deliberate: Phase 1 produces the measured evidence that shapes Phase 2's design, rather than
widening the DSL on speculation.

**Reference targets for Phase 4:** the Wharton model's published answers — IRR **24.67%**,
MoM **3.01** — independently reproduced by orcaset's `examples/paper-lbo` and checkable against
`references/wharton-lbo-practice-model.xlsx` (Penn Career Services, publicly available).
