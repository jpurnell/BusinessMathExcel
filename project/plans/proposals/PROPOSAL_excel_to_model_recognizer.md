# Design Proposal: Excel→ModelDefinition Recognizer

**Date:** 2026-09-01
**Status:** Proposed
**Supersedes:** `PROPOSAL_excel_to_dsl_recognizer.md` (same day, not implemented — kept for its
`ModelImporter` defect analysis and its adversarial review, which named the pivot)
**Companion:** `BusinessMath/project/plans/proposals/TypedModelAuthoring.md`
**Master Plan Reference:** Architecture — Import pipeline
**Amended:** 2026-09-01 — `IF` and the comparison operators pulled forward into Phase 2, amending
decision D8. See §15 Q0 for the measurement that forced it.

---

## 1. Objective

Recognize the semantic structure of an imported workbook and emit a **`ModelDefinition`** — named
accounts with per-period formulas, evaluated by `FormulaEvaluator` and resolved by `CycleSolver`
— with per-cell provenance for every account.

The target changed from `BusinessMathDSL` (see the superseded proposal's header). `ModelDefinition`
is a far closer fit: **a workbook already *is* named accounts with formulas and cycles.** Where
the previous plan needed five new DSL types and a breaking change before it could represent a
paper LBO, this one needs a recognizer and a function registry.

**Goal: 100% coverage of the Wharton LBO practice workbook.** 30% is an interim milestone.

## 2. Motivation

**Current situation.** The export half of the pipeline is complete. The import half stops at
structural transcription, and its defects are unchanged from the superseded proposal:

- `ModelImporter.swift:57-61` — every node is `addInput(label: refString, …)`. The label **is**
  the cell address (`"B4"`, `"C7"`), all dumped into one section named `"Imported"`.
- `ModelImporter.swift:161-165` — `.cellRange`, `.sheetRef`, `.namedRange`, `.power`, and all six
  comparison operators collapse to `.text("UNSUPPORTED")`.
- `convertAST` never receives the `warnings` array, so that loss is **silent**. Warnings fire
  only for `.date`/`.error`/`.array` cell *types* at line 93. A workbook can import 60% lossy and
  report nothing.
- `ModelImporter.swift:29-32` — `importWorkbook` takes `sheets.first`. We export multi-sheet and
  cannot import it.

**What changed upstream.** Three capabilities already ship in BusinessMath that the previous plan
proposed to build:

| Need | Already ships |
|---|---|
| Per-period values | `TimeSeries<T>` (`Time Series/TimeSeries.swift:108`) |
| Named-account model with formulas | `ModelDefinition<T>` (`Model Definition/ModelDefinition.swift:119`) |
| Cycle detection + resolution | `DependencyReport`, `CycleSolver.solve`, `IterativeCycleSolver` (`87a717e`) |

Circular interest — the shape of every levered workbook — is resolved by machinery written for
exactly this case. We consume it; we do not rebuild it.

**Workaround today.** A developer reads the workbook by eye and hand-writes the model, with no
record of which cell any figure came from.

**Drawback.** Hand-transcription is where a growth rate gets read off the wrong row and a
one-time cost silently becomes recurring. Provenance is the deliverable, not a nicety — it is the
direct answer to the failure the orcaset article describes: an out-of-band evaluator producing
plausible numbers that nothing traces back to the sheet.

## 3. Proposed Architecture

Five stages. Each is independently testable and consumes only the stage above.

```
Workbook
  → [Stage 0] ModelImporter          (existing; defects fixed here)
  → [Stage 1] SheetGrid              layout + period-axis analysis
  → [Stage 2] LabeledSeries          label binding, orientation resolution
  → [Stage 3] RecognizedAccount      formula translation + unit inference
  → [Stage 4] RecognizedModel        Sendable plan with provenance
  → [Stage 5] ModelDefinition  |  typed Swift source
```

Stages 1–2 are **carried forward unchanged** from the superseded proposal; only the back half
changed. `Import/` stays purely structural — it must never guess, so a workbook we cannot
interpret still round-trips. `Recognition/` is the interpretive layer above it.

**New Files:**

| File | Role |
|---|---|
| `Recognition/SheetGrid.swift` | Cell topology, orientation, period-axis detection |
| `Recognition/PeriodAxis.swift` | Recovered time axis → `[Period]` |
| `Recognition/LabeledSeries.swift` | A text label bound to a run of value cells |
| `Recognition/Lexicon.swift` | Label → unit/role vocabulary, user-extensible |
| `Recognition/FormulaTranslator.swift` | `NodeFormula` → `FormulaEvaluator` grammar string |
| `Recognition/UnitInference.swift` | Cell format + label → `Money`/`Rate`/`Ratio`/`Duration` |
| `Recognition/RecognizedModel.swift` | Sendable plan: accounts, residue, provenance |
| `Recognition/ExcelRecognizer.swift` | Stage 1–4 driver, public entry point |
| `Recognition/Diagnostic.swift` | Severity, code, cell, message |
| `Materialize/ModelBuilder.swift` | Plan → `ModelDefinition` (throws) |
| `Materialize/TypedSourceWriter.swift` | Plan → typed Swift source (`Account`/`Expr`) |

**Modified:** `Import/ModelImporter.swift` (the four defects above); `Package.swift` (bump the
BusinessMath pin).

### The plan/materialize split

Stages 1–4 emit `RecognizedModel` — plain `Sendable` data. Stage 5 consumes it. Two reasons:

1. **Recognition must be inspectable before it is executed.** A plan can be diffed, reviewed, and
   tested without constructing anything.
2. **`ModelDefinition` construction can fail** — an unknown account, an unparseable formula, a
   unit conflict. Materialization validates and **throws**; recognition never does.

`TypedSourceWriter` emits the `Account<Unit>` / `Expr<Unit>` form from
`TypedModelAuthoring.md`, with provenance comments. For an agent workflow this is the more useful
artifact: diffable, checkable into a repo, and type-checked by the compiler.

### Why this is dramatically simpler than the DSL target

An Excel formula `=D5*(1+$B$2)` becomes the account formula `[Revenue] * (1 + [Growth Rate])`
plus a lag declaration. There is no need to *recognize* that this means
`Revenue { Base; GrowthRate }` — the formula translates structurally. **Pattern recognition
collapses from "infer the modelling intent" to "rename cell references to account names, and
record their lag."** What remains genuinely inferential is Stage 2 (which label owns which row)
and unit inference — not the formula semantics.

### Lag decomposition (Stage 3's real work)

Formulas in `ModelDefinition` are **period-local by design** — `FormulaEvaluator.swift:119-124`
and `CycleSolver.swift:222-226` both document the exclusion of cross-period references, and
assign the rollforward to the caller. Upstream `TypedModelAuthoring.md` Part 2.5 supplies that
caller as `PeriodDriver` + `Rollforward`.

So Stage 3 must **split each formula by reference lag**, which the grid makes mechanical: a
reference's lag is its column offset (or row offset, transposed) from the cell being defined.

| Excel cell | References | Lag | Becomes |
|---|---|---|---|
| `D6 = C6*1.15` | `C6` — one column left, same row | 1 | `Rollforward(opening: "Revenue Prior", closing: "Revenue", seed: <C6>)` + `[Revenue] = [Revenue Prior] * 1.15` |
| `D9 = D6-D7` | same column | 0 | `[EBITDA] = [Revenue] - [COGS]` — period-local, no rollforward |
| `D12 = C12+D10` | `C12` lag 1, `D10` lag 0 | mixed | Split: prior term via rollforward, current term local |
| `D5 = $B$2` | absolute, off-timeline | n/a | Scalar input account, constant across periods |

A lag greater than 1, or a *forward* reference (negative lag), emits `.unsupportedLag` and drops
to residue — Wharton needs neither, and guessing at them would be exactly the kind of plausible
wrong answer this design refuses.

### Formula uniformity, and demoting `IF` to data

**A row must reduce to one formula.** `ModelDefinition` holds one formula per account, applied to
every period. So Stage 3 checks that every cell in a bound row has the same formula shape modulo
column offset before collapsing it into an account. Per-period *values* vary freely — inputs are
`TimeSeries` — but per-period *shape* does not.

This check is a feature, not a tax. A single cell in a row differing from its neighbours is the
most common real-world spreadsheet defect and is invisible in Excel, where every cell is
independently legitimate. Here it cannot pass silently: a non-uniform row emits
`.nonUniformRow` naming the offending cells, and the recognizer does not pick a majority shape.

Two legitimate causes of non-uniformity, distinguished and handled differently:

| Cause | Handling |
|---|---|
| **First period differs** (`C6 = 100`, then `D6 = C6*1.15`) | Normal rollforward seeding — `Rollforward.seed` takes the literal. Not a diagnostic. |
| **Structural break** (`0` for four periods, then a balloon) | Re-expressed as an indicator input series — see below. |
| **Anything else** | `.nonUniformRow`, to residue. A hand-edited cell is a finding, not something to average away. |

**Recognized `IF`s that only test the timeline become data.** Upstream
(`TypedModelAuthoring.md`, "When *not* to reach for `IF`") the rule is: *if the condition is
answerable from the timeline alone, it is data; if it depends on a computed value, it is `IF`.*
The recognizer applies it.

`=IF(D$4=2027, -[Debt], 0)` tests only period position, so it is transcribed as an indicator
input series `[0,0,0,0,1,0]` multiplied through, leaving the formula uniform and putting the
schedule in the inputs where every other assumption lives. `=IF([Cash]>[Floor], …)` depends on a
computed value and is transcribed as a real `IF`.

```swift
public struct RecognizedIndicator: Sendable, Equatable {
    public let name: String
    /// One value per period, 1 or 0.
    public let values: [Double]
    /// The `IF` this replaced, retained so the rewrite is auditable.
    public let derivedFrom: String
    public let provenance: [CellRef]
}
```

`derivedFrom` matters: the rewrite is a judgement the recognizer made, so it stays inspectable
rather than being silently applied. `RecognizerOptions.demoteTimelineConditionals` (default
`true`) turns it off for a caller who wants a literal transcription.

### Dynamic references — `INDIRECT`, `ADDRESS`, `OFFSET` (Stage 3, advanced)

**Status: deferred.** Not needed for Wharton, and not on the critical path. Written down now
because a production credit model was measured against the pipeline on 2026-09-01 and the
handling is non-obvious enough to be worth deciding once rather than improvising later.

A dynamic reference computes *which cell to read* instead of naming it. The canonical form:

```
Comp!C4 = INDIRECT(ADDRESS(1,1,2,1,C$1),TRUE)
```

`ADDRESS` builds the string `'A'!A$1` — where the sheet name comes from the *value of* `C1` —
and `INDIRECT` dereferences it. In the measured model, row 1 was a header of sheet names
(`C1="A"`, `D1="B"`, `J1="C"`) matching per-entity sheets named `A`, `B`, `C`. The sheet is a
comparison grid built out of dispatch.

**This is not an import concern.** `Import/` transcribes it faithfully already — verified:

```swift
.function("INDIRECT", [
  .function("ADDRESS", [.number(1), .number(1), .number(2), .number(1), .ref(C1)]),
  .bool(true)])
```

The sheet-name argument binds to a real node because cell identity ignores `$` markers. Nothing
is lost, and no warning fires. The question is entirely what Stage 3 does with it.

#### Three tiers

**Tier 1 — constant-foldable.** Every `ADDRESS` argument reduces to a constant:

| Argument | Foldable when |
|---|---|
| `row_num`, `column_num` | numeric literals; `ROW()`/`COLUMN()`, which are constants *for the cell being defined*; or arithmetic over those (`ROW()+109`) |
| `abs_num`, `a1` | numeric literals |
| `sheet_text` | a `.ref` to a node whose ``NodeKind`` is `.textInput` — proven data, not computation |

Fold to a concrete cross-sheet reference and emit `.foldedDynamicReference` (info) so the
rewrite is auditable rather than invisible.

The `sheet_text` rule is what does the real work, and it excludes more than it looks. In the
measured model `F1…I1` held `IF(LEFT(E$1,8)="Scenario",E$1,"")` — computed, so any
`ADDRESS(…,F$1)` is **not** foldable even though its neighbours are. "Is this cell data or
computation" is already answerable from `NodeKind`; no new analysis is needed.

**Tier 2 — guarded dispatch.** The dominant shape in the measured model (11 occurrences) was

```
IF(ISNUMBER(sel), INDIRECT(ADDRESS(ROW()+109, 10+sel, …)), INDIRECT(ADDRESS(ROW()-x, 8, …)))
```

The else-branch folds; the then-branch has a column offset driven by a selector input. Once `IF`
and the comparison operators land — Phase 2, pulled forward from D8 per §15 Q0 — keep the
conditional and fold the provable branch, marking the other dynamic. Until then the whole cell is
residue.

**Tier 3 — genuinely dynamic.** Any argument depending on a computed value. `.dynamicReference`
(error) and residue.

#### The rule that outranks the tiers

`Comp!C4` carries `"A"` in its cache. Promoting a cached value for a reference we could not fold
would look flawless and be exactly the failure this project exists to prevent. **An unfoldable
dynamic reference becomes residue. It never becomes a constant.**

#### `OFFSET` is the larger population

Counted across 5011 formulas in the measured model: **65 `INDIRECT`, 424 `OFFSET`, 250 `MATCH`**.
`OFFSET(base, rows, cols)` is the same construct — a reference computed from a base plus offsets
— and is 6.5× more common. It belongs in the same tiered treatment from the start; treating
`INDIRECT` as the special case would miss most of the actual volume.

#### Folding is a snapshot, and should say so

`INDIRECT` survives row insertion; a resolved reference does not. Folding is therefore a semantic
change, not a pure rewrite — correct for translating a model as it stands, wrong if the result is
expected to track edits to the source workbook. The provenance comment must record that the
reference was folded, not merely where it came from.

#### What Stage 2 owes this

Only that `SheetGrid` can express "a cell references another sheet by name-as-data". No folding,
no diagnostics, no `OFFSET` handling in Stage 2.

### Sensitivity tables

A What-If data table is not a formula and must not be recognized as accounts. Core already has
the destination types (`Scenario Analysis/SensitivityAnalysis.swift`):

| Excel construct | Emitted as |
|---|---|
| Two-variable data table | `TwoWayScenarioSensitivityAnalysis` — `inputDriver1/2`, `inputValues1/2: [Double]`, `results: [[Double]]` (`:318`) |
| One-variable data table | `ScenarioSensitivityAnalysis` — `inputValues: [Double]`, `outputValues: [Double]` (`:142`) |
| Tornado layout | `TornadoDiagramAnalysis` (`:759`) |

> **Correction, 2026-09-01.** The detection signal below is wrong, and measurement proved it.
> Excel does not store a What-If table as `.array` cells. It writes **one self-closing formula
> element** on the table's anchor cell:
> `<f t="dataTable" ref="P6:T10" dt2D="1" r1="D11" r2="D21"/>`, where `ref` is the span and
> `r1`/`r2` are the row and column input cells. Neither reference workbook contains a single
> `.array` cell; the Wharton model contains exactly one `dataTable` element. SwiftXLSX 0.7.0
> surfaces it as `_DATATABLE(span, inputs...)`, so Phase 6 reads the drivers and the span
> **directly from the file** instead of inferring them from a grid of array cells. This is
> strictly better: `r1`/`r2` are the sensitivity drivers, stated by Excel.

**Yes — a two-way table is an array of arrays**, `results: [[Double]]`, indexed
`[inputValues1][inputValues2]`. That is precisely Wharton's IRR sensitivity: exit multiple ×
revenue growth → IRR grid.

**Detection has a concrete signal already visible to us.** Excel stores data-table results as
array formulas (`{=TABLE(r,c)}`), and `ModelImporter.swift:92-93` currently discards exactly that
cell type — `case .date, .error, .array:` → "Unsupported cell type". So the `.array` cells that
today produce a warning are the data table, and recognition means reading the rectangle around
them: corner cell holds the driving formula, the top row and left column hold the input values.

`RecognizedModel` therefore carries tables alongside accounts:

```swift
public struct RecognizedModel: Sendable {
    public let periods: [Period]
    public let accounts: [RecognizedAccount]
    public let rollforwards: [RecognizedRollforward]
    public let sensitivityTables: [RecognizedSensitivityTable]
    public let residue: [Residue]
}

public struct RecognizedRollforward: Sendable, Equatable {
    public let opening: String
    public let closing: String
    public let seed: Double
    public let lag: Int                 // always 1 in v1
    public let provenance: [CellRef]
}

public struct RecognizedSensitivityTable: Sendable, Equatable {
    public enum Shape: Sendable, Equatable { case oneWay, twoWay }
    public let shape: Shape
    public let rowDriver: String?
    public let columnDriver: String
    public let rowValues: [Double]
    public let columnValues: [Double]
    /// Cached results as they stood in the sheet — reported, never used as truth.
    public let cachedResults: [[Double]]
    public let outputAccount: String
    public let provenance: [CellRef]
}
```

`cachedResults` is deliberately named. The sheet's stored numbers are evidence of what Excel
computed, not a substitute for recomputing — recomputation runs through `runTwoWaySensitivity`
against the recognized model, and a mismatch is a `.sensitivityMismatch` diagnostic. Reporting a
cached value as though we had evaluated it is the specific dishonesty this project exists to
avoid.

## 4. API Surface

```swift
public enum ExcelRecognizer {
    /// Recognition is best-effort and never throws: a workbook that does not fit
    /// yields a partial model plus diagnostics.
    public static func recognize(
        _ workbook: Workbook,
        options: RecognizerOptions = RecognizerOptions()
    ) -> RecognitionResult

    public static func recognize(
        _ sheet: Worksheet,
        options: RecognizerOptions = RecognizerOptions()
    ) -> RecognitionResult
}

public struct RecognizerOptions: Sendable {
    public enum Orientation: Sendable, Equatable {
        case auto, periodsAcrossColumns, periodsDownRows
    }
    public var orientation: Orientation
    public var lexicon: Lexicon
    public var granularity: PeriodType?     // nil = infer from headers
    public var inferUnits: Bool             // default true
    public var maximumPeriods: Int          // default 200
    public var maximumCells: Int            // default 100_000

    public init(/* all defaulted */)
}

public struct RecognitionResult: Sendable {
    public let model: RecognizedModel
    public let diagnostics: [Diagnostic]
    public let coverage: Coverage
}

/// How much of the sheet the recognizer accounted for. Tracked to 100% on Wharton.
public struct Coverage: Sendable, Equatable {
    public let populatedCells: Int
    public let recognizedCells: Int
    public var fraction: Double { get }
}

public struct RecognizedModel: Sendable {
    public let periods: [Period]
    public let accounts: [RecognizedAccount]
    public let residue: [Residue]
}

/// One account destined for a `ModelDefinition`, with the cells it came from.
public struct RecognizedAccount: Sendable, Equatable {
    public let name: String
    /// `FormulaEvaluator` grammar, or `nil` for an input account.
    public let formula: String?
    /// Literal values when this account is an input.
    public let values: [Period: Double]?
    /// Inferred unit; `nil` when inference was inconclusive.
    public let unit: UnitKind?
    /// For `.rate`, the period the rate is expressed per.
    public let basis: PeriodType?
    /// Every cell that contributed. Never empty.
    public let provenance: [CellRef]
}

public enum UnitKind: String, Sendable, Equatable, CaseIterable {
    case money, rate, ratio, duration
}

public struct Residue: Sendable, Equatable {
    public let label: String
    public let cells: [CellRef]
    public let reason: DiagnosticCode
}

public struct Diagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable { case info, warning, error }
    public let severity: Severity
    public let code: DiagnosticCode
    public let cell: CellRef?
    public let message: String
}

public enum DiagnosticCode: String, Sendable, Equatable, CaseIterable {
    case unsupportedFormulaNode
    case unregisteredFunction        // an Excel function with no registry entry
    case ambiguousOrientation
    case noPeriodAxis
    case labelUnbound
    case duplicateAccountName
    case unitInferenceFailed
    case unitConflict
    case crossSheetReference
    case scanLimitReached
    case unsupportedLag              // lag > 1, or a forward reference
    case sensitivityMismatch         // recomputed grid ≠ the sheet's cached grid
    case nonUniformRow               // a hand-edited cell breaks the row's shape
    case conditionalDemotedToData    // info: an IF became an indicator series
    case dynamicReference            // INDIRECT/OFFSET whose target cannot be proven
    case foldedDynamicReference      // info: a dynamic reference resolved to a static one
}

// MARK: - Materialization

public enum ModelBuilder {
    /// - Throws: ``MaterializationError`` on unknown accounts, unparseable formulas,
    ///   or unit conflicts. Validates before constructing.
    public static func modelDefinition(
        from model: RecognizedModel
    ) throws -> ModelDefinition<Double>
}

public enum MaterializationError: Error, Sendable, Equatable {
    case unresolvedReference(account: String, missing: String)
    case invalidFormula(account: String, underlying: FormulaError)
    case duplicateAccount(String)
    case unitConflict(account: String, UnitKind, UnitKind)
}

public enum TypedSourceWriter {
    /// Emits `Account<Unit>` / `Expr<Unit>` Swift source per `TypedModelAuthoring.md`.
    /// Each declaration carries a trailing `// <sheet>!<cell>` provenance comment.
    public static func swiftSource(
        for model: RecognizedModel,
        modelName: String = "importedModel"
    ) -> String
}
```

### Example output

Workbook: `B6 = "Revenue"`, `C6 = 1000000`, `D6 = C6*1.15`; `B7 = "Growth"`, `C7 = 0.15` (percent format).

```swift
// Recognized from Forecast.xlsx — 100% coverage, 0 diagnostics
let revenue = Account<Money>("Revenue")          // Forecast!B6
let growth  = Account<Rate>("Growth", basis: .annual)  // Forecast!B7

let importedModel = ModelDefinition<Double>(periods: periods)
    .defining(revenue, as: revenue.prior * (ratio(1) + growth.expr))   // Forecast!D6
```

## 5. MCP Schema

**Tool Description:** Recognize an Excel workbook as a named-account model and return it with
per-cell provenance.

**REQUIRED STRUCTURE (JSON):**
```json
{
  "workbookPath": "/abs/path/Forecast.xlsx",
  "sheetName": "Forecast",
  "orientation": "auto",
  "granularity": "annual",
  "inferUnits": true,
  "maximumPeriods": 200,
  "emitSource": true,
  "lexiconAdditions": {"money": ["Net sales", "Turnover"]}
}
```

**Parameter Types:**
- `workbookPath` (string, required): absolute path to a `.xlsx`.
- `sheetName` (string, optional): omit to recognize all sheets.
- `orientation` (string): `"auto"` | `"periodsAcrossColumns"` | `"periodsDownRows"`.
- `granularity` (string, optional): `"annual"` | `"quarterly"` | `"monthly"` | `"semiannual"`.
  Omit to infer from header cells.
- `inferUnits` (boolean): default `true`.
- `maximumPeriods` (integer > 0, ≤ 1000), `maximumCells` (integer > 0).
- `emitSource` (boolean): include generated typed Swift. Default `false`.
- `lexiconAdditions` (object): `UnitKind` → array of label synonyms. Keys must be `"money"`,
  `"rate"`, `"ratio"`, `"duration"`.

**Response:** `{ "model": {...}, "diagnostics": [...], "coverage": {...}, "source": "..." }`.
Every account carries `provenance`, so any number can be verified against the sheet. Periods are
exchanged as granularity + index, not ISO 8601 instants — `Period` is a closed interval.

**Determinism:** Fully deterministic; no seed.

## 6. Constraints & Compliance

**Concurrency:** every recognizer type is an immutable `Sendable` value type. `RecognizedModel`
carries no BusinessMath model types, only plain data, so the plan crosses isolation freely.

**Safety:** no force unwraps, no `try!`, no force casts. Growth-rate and ratio inference divide by
a prior-period value; each site guards zero and emits a diagnostic rather than an infinity.

**No silent loss:** every unrecognized construct produces a `Diagnostic` **or** a `Residue`
entry. This is the rule `ModelImporter` violates today and the one this design exists to fix.

**Bounded work:** `maximumCells` and `maximumPeriods` bound every scan; reaching either emits
`.scanLimitReached` rather than truncating quietly.

**No traps on user data:** `ModelBuilder` validates and throws. Unlike the superseded proposal,
there is no trapping-initializer hazard — `ModelDefinition` throws already.

**DocC:** all public API documented.

## 7. Source & API Compatibility

**Breaking changes:** none to existing types. `Recognition/` and `Materialize/` are new surface.

**Behavioral changes to `ModelImporter`** (both intended fixes):
1. `.cellRange` and `.power` stop producing `.text("UNSUPPORTED")`. `ModelImporterTests` is the
   only in-repo caller.
2. `ImportResult.warnings` becomes non-empty for workbooks that previously reported none.

**Dependency change:** the BusinessMath pin is `exact: "2.2.1"` (`Package.swift:13`); upstream is
now at **`v2.7.0`**. `BusinessMathDSL`, `Model Definition/`, and `FormulaEvaluator.swift` are all
**unchanged between `2.6.0` and `2.7.0`**, so every finding in this proposal holds at either tag.
Phase 0 bumps to `2.7.0`; later phases bump again to pick up
`TypedModelAuthoring.md`'s 2a–2d (registry, `IF`, `PeriodDriver`) and Phase 3 (typed layer). Per
`CLAUDE.md`, a pin change failing with *"does not match previously recorded value"* needs both
`Package.resolved` **and** the fingerprint at
`~/.swiftpm/security/fingerprints/<package>-<hash>.json` corrected. This has bitten the project
before (`da8c5a8`).

**Incremental adoption:** `ExcelRecognizer` is additive; `ModelImporter` still works standalone.

## 8. Backend Abstraction

**Not applicable.** Stages 1–2 are `O(populated cells)` with dictionary lookups; Stage 3 is
`O(accounts × formula nodes)`. A 100k-cell workbook is a few million scalar comparisons. There is
no kernel worth handing to Metal or Accelerate.

## 9. Dependencies

**Internal:** `Import/ModelImporter.swift`, `Model/NodeFormula.swift`, `Model/NodeRef.swift`.

**External (existing packages):**
- `SwiftXLSX` — `Workbook`, `Worksheet`, `CellRef`, `CellRange`, `FormulaAST`.
- `BusinessMath` — `ModelDefinition`, `FormulaEvaluator`, `TimeSeries`, `Period`, `PeriodType`,
  `CycleSolver`, and (after `TypedModelAuthoring.md` Phase 3) `Account`/`Expr`/`Unit`.

**Removed as a dependency target:** `BusinessMathDSL`. It is being deleted; nothing here uses it.

**Blocking upstream work** (`TypedModelAuthoring.md`):
- **Phase 2a–2c** — the function registry. Without it, `SUM(D5:D16)` and `NPV(rate, range)` have
  nowhere to go. This gates Wharton coverage above roughly the interim milestone.
- **Phase 3** — `Account`/`Expr`. Gates `TypedSourceWriter` only; `ModelBuilder` works against the
  string API without it.

## 10. Test Strategy

**Test Categories:**

- *Golden path* — fixture workbooks → expected accounts, formulas, units, provenance.
- *Round-trip identity* — build a `ModelDefinition`, export via `ModelExporter`, recognize, and
  assert the recovered accounts and formulas match. Strongest available property.
- *Formula translation* — `NodeFormula` → grammar strings that `FormulaEvaluator.tokenise`
  accepts; names with `&`, `/`, and spaces survive via the bracketed form.
- *Cycle* — a workbook with circular interest recognizes, and the resulting `ModelDefinition`
  produces a `DependencyReport` with the expected SCC, then converges through `CycleSolver`.
- *Lag decomposition* — `D6 = C6*1.15` yields one `RecognizedRollforward` and a period-local
  formula; `D9 = D6-D7` yields no rollforward; the mixed case `D12 = C12+D10` splits correctly.
  A lag-2 reference emits `.unsupportedLag` and does not silently become lag 1.
- *Sensitivity tables* — a two-variable data table is recognized from its `_DATATABLE` marker (`ref` span plus `r1`/`r2` drivers) with the
  correct drivers and axes; the **recomputed** grid is compared against the sheet's
  `cachedResults`, and a deliberate corruption of a cached cell produces `.sensitivityMismatch`
  rather than being accepted.
- *Unit inference* — a percent-formatted cell infers `.ratio`; a row labelled "growth" infers
  `.rate`; an inconclusive cell emits `.unitInferenceFailed` rather than guessing.
- *Negative recognition (critical)* — an Excel function with no registry entry must emit
  `.unregisteredFunction` and place the account in `residue`. It must **not** be dropped, and its
  value must **not** be replaced by a cached constant from the sheet. Substituting a plausible
  number for a formula we cannot evaluate is the precise failure this project exists to avoid.
- *Provenance* — every account's `provenance` cells actually hold the values claimed; never empty.
- *Orientation* — across-columns and down-rows; ambiguous sheets emit `.ambiguousOrientation`
  and do not guess.
- *Edge cases* — empty sheet, single period, label with no values, values with no label,
  duplicate labels (`.duplicateAccountName`), a sheet at `maximumCells`.
- *Dynamic references* — `INDIRECT(ADDRESS(1,1,2,1,C$1))` with `C1` a text input folds to a
  cross-sheet reference and emits `.foldedDynamicReference`; the same formula with `C1` holding a
  *formula* does not fold and emits `.dynamicReference`. Critically, the unfoldable case must
  **not** acquire the cached value Excel left in the cell.
- *Determinism* — identical workbook → identical results including diagnostic ordering.
- *Importer regression* — `SUM(D5:D16)` and `(1+r)^n` import as real nodes; unsupported nodes now
  appear in `warnings`.

**Reference Truth:**

1. **Wharton LBO Practice Model** (Penn Career Services, publicly available) — published
   **IRR 24.67%**, **MoM 3.01**, independently reproduced by orcaset's `examples/paper-lbo`.
   Primary coverage benchmark.
2. **Excel** for formula-shape fixtures — expected values computed in Excel and recorded in each
   fixture's companion `.md`, never inferred.
3. **`FormulaEvaluator` itself** for the translation property — comparing against the shipped
   evaluator rather than a hand-computed expectation.

**Validation Trace (REQUIRED):**

> **Translation.** Fixture `RevenueGrowth.xlsx`, sheet `Forecast`:
> `B6 = "Revenue"`, `C6 = 1000000`, `D6 = C6*1.15`, `E6 = D6*1.15`.
> Excel evaluates `D6 = 1,150,000`, `E6 = 1,322,500`.
>
> `ExcelRecognizer.recognize(sheet)` must yield a `RecognizedAccount` named `"Revenue"` with
> `unit == .money`, `provenance == [C6, D6, E6]`, and a formula that
> `FormulaEvaluator.tokenise` accepts. `ModelBuilder.modelDefinition(from:)` then
> `.evaluate()` must return `[1_000_000, 1_150_000, 1_322_500]` (accuracy `1e-6`) —
> **matching Excel's own values, not merely self-consistent.**
> `coverage.fraction == 1.0`, `diagnostics == []`.
>
> **Circular interest.** Fixture `CircularInterest.xlsx`: interest on average debt balance,
> debt reduced by a sweep funded from cash flow net of interest.
> `dependencyReport()` must report exactly one SCC containing `Interest` and `Closing Debt`;
> `evaluate()` must converge within `IterationSettings.maxIterations` (100). Year-1 interest on
> a 120 draw at 10% with full sweep must be **11.75** — the average-balance figure. Beginning-
> balance gives 12.00, so this single value distinguishes a correct cyclic solve from a model
> that quietly broke the cycle by timing.
>
> **Negative case.** A workbook containing `=VLOOKUP(...)` with no registry entry must produce
> a `.unregisteredFunction` diagnostic at that cell, a `Residue` entry, and **no account** whose
> value is the cached number Excel left in the cell.

Floating-point assertions use accuracy-based comparison per project testing rules.

## 11. Architecture Decision Review

**ADR Check:**
- [x] Reviewed `development-guidelines/rules/architecture_decisions.md`
- [x] Supersedes an existing ADR? **No**
- [x] Amends an existing ADR? **Yes — decision D8** (`IF` + comparison operators), which placed
  this work behind the upstream function-registry gate. Amended 2026-09-01 to Phase 2 of this
  repo on measured evidence; see §15 Q0. D9, which governs what an `IF` *means*, is unchanged.
- [x] New ADR required? **Yes — two**

**New ADR Drafts:**

- **Title:** The Excel import target is `ModelDefinition`
- **Category:** architecture
- **Key decision:** Workbooks import as named accounts with formulas, not as typed scalar
  components. A workbook already has that shape, and `ModelDefinition` brings cycle detection and
  resolution for free. Typed `Account`/`Expr` is a projection over the result, not the target.

- **Title:** Lossy import must be loud
- **Category:** api
- **Key decision:** Any construct the import or recognition path cannot represent produces a
  `Diagnostic` or `Residue` entry. Silent substitution of a plausible value — including reading a
  cell's cached result in place of a formula we cannot evaluate — is prohibited.

## 12. Adversarial Review

**Strongest case for a different approach.**

A reviewer would say: *if a workbook is already named accounts with formulas, why is there a
recognizer at all?* Translate every populated cell into an account named by its address
(`[B6]`, `[C7]`), translate every formula structurally, and hand the result to `ModelDefinition`.
That is mechanical, needs no lexicon, no orientation detection, and no unit inference — and it
would reach very high coverage almost immediately, because it never has to *understand* anything.

That alternative is genuinely strong. The entire inferential apparatus in Stages 1–2 exists to
turn `[B6]` into `[Revenue]`, and a reviewer can fairly ask whether that naming is worth the
machinery when the model computes identically either way.

**Where this design is most likely wrong.**

The load-bearing assumption is that **account naming is worth its cost.** If label binding is
unreliable on real workbooks — merged header blocks, multi-row headers, labels embedded in number
formats — we get a model whose accounts are named `[Revenue]` for the rows we understood and
`[D14]` for the rest. That hybrid may be worse than consistent addresses: it *looks* semantic
while being partial, which invites misplaced trust.

Second: unit inference may be a liability rather than an asset. Inferring `.rate` from a label
containing "growth" is a heuristic, and a wrong unit produces a **compile error in generated
source** that the user cannot fix without editing the generated file. A wrong unit is worse than
no unit — which is why `unit` is `UnitKind?` and inference failure is a diagnostic rather than a
guess, but the incentive to guess will be strong when coverage is the tracked metric.

Third, a constraint accepted with little challenge: that `Import/` must stay purely structural.
Fusing recognition into import would let the label column inform naming directly and would be
simpler. It is kept separate to preserve a lossless transcription path — a judgement, not a
requirement.

**What an experienced critic would say.**

*"You are measuring coverage, which rewards naming a cell something rather than nothing — and
your unit inference turns a wrong guess into a compile error in code the user did not write."*

**Why we are proceeding anyway — with two changes.** Addresses-as-accounts (Alternative 1) is
adopted as the **fallback for anything Stage 2 cannot bind**, so the mechanical path is not
rejected but subsumed: an unbound row becomes `[D14]` with a `.labelUnbound` diagnostic, and
coverage still counts it. That makes the naming layer a strict improvement over the mechanical
baseline rather than a bet against it. **Change one:** `Coverage` gains a second axis — cells
recognized *and named* versus cells recognized at all — so the metric cannot be gamed by naming
things badly. **Change two:** unit inference is opt-out via `RecognizerOptions.inferUnits`, and
`TypedSourceWriter` emits an untyped `Account` when `unit == nil` rather than picking one.

### Adversarial review of the 2026-09-01 amendments

`session_workflow.md` requires a pass arguing *against* the design before a proposal is
presented. The two amendments made on 2026-09-01 — the dynamic-reference tiers (§3) and the D8
change (§15 Q0) — were written and committed without one. This is that pass, run late. It found
one blocking defect and three corrections.

**BLOCKING — shared formulas are silently imported as constants.** The attack was "`ROW()` is a
constant for the cell being defined — is it?" Checking rather than assuming: OOXML stores a
repeated formula once on a master cell as `<f t="shared" ref="D5:D16" si="0">D4*1.1</f>`, and
every dependent cell carries only `<f t="shared" si="0"/>` with **no formula text**, the formula
being derived by offsetting the master's relative references.

`SwiftXLSX.WorksheetParser` has no `t="shared"` handling. Measured on the Wharton `ANSWER KEY`:
**155 formula elements, 74 carrying text, 81 with empty bodies.** Our importer reports exactly 74
formulas. The other **81 computed cells arrive as `.number` inputs** — they carry cached values,
so they look like clean data — and produce **no warning**.

That is the precise thing the "Lossy import must be loud" ADR prohibits: a cached result standing
in for a formula. It is a worse failure than the `INDIRECT` case this amendment was written about,
because it is silent and it makes a model *look* correct.

Two consequences beyond the defect itself. Every import-fidelity figure recorded before
2026-09-01 undercounts the denominator and must be restated. And Phase 2 Task 6 cannot proceed
on top of it: uniformity asks whether a row's cells share a formula shape, and `t="shared"` is
**Excel's own declaration that they do** — the `ref` attribute names the exact span. Reading it
does not merely stop the loss, it hands Task 6 its answer directly.

**Correction 1 — the Tier 1 fold criterion is too weak.** §3 folds when the sheet-name argument
resolves to a `.textInput`. That proves the cell is *not computed*; it does not prove it is not
*meant to vary*. In the measured model `C1 = "A"` is exactly the knob a user retypes to point the
comparison somewhere else. Folding it converts dispatch into a fixed reference — a semantic
downgrade the current write-up does not distinguish from folding a literal. `.foldedDynamicReference`
should be **warning** severity when the driver is an input cell, and info only when every argument
is a literal.

**Correction 2 — "`OFFSET` is the same construct" overstates it.** `OFFSET(ref, rows, cols,
[height], [width])` returns a *range* when the size arguments are present, where `ADDRESS` always
yields a single cell. The tiers still apply, but the fold target differs and the write-up should
not imply one substitution rule covers both.

**Correction 3 — the D8 evidence is not reproducible from this repo.** The 2982-of-5011 `IF`
measurement comes from a private workbook that cannot be checked in. The decision may still be
right — the reasoning about operators not being registry entries stands on its own — but a reader
cannot verify the number, and the only *reproducible* evidence, Wharton, shows one occurrence.
Recorded so the decision is not later mistaken for having had public backing.

**Not upheld.** The objection that adding six enum cases in Phase 2 costs consumers a second
source-breaking change was considered and rejected: `NodeFormula` is pre-1.0, Phase 1 already
broke it once for `.power`, and deferring to batch with unknown Stage 3 additions trades a certain
small cost for a speculative one.

## 13. Alternatives Considered

**Alternative 1: Mechanical transcription — accounts named by cell address.**
- *Advantage:* No lexicon, no orientation detection, no unit inference. Near-total coverage
  immediately. Model computes identically.
- *Disadvantage:* `[D14] * [B7]` is unreadable and unmaintainable; the output is a recalculated
  spreadsheet, not a model anyone would edit.
- *Status:* **Adopted as the fallback path**, not rejected. Unbound rows take it (§12).

**Alternative 2: Target `BusinessMathDSL` (the superseded proposal).**
- *Advantage:* Typed components with financial semantics.
- *Disadvantage:* Requires five new DSL types and a breaking change before a paper LBO is
  expressible; targets a module with zero consumers that is being deleted.
- *Why rejected:* See the superseded proposal's header.

**Alternative 3: Emit typed Swift source only; no `ModelBuilder`.**
- *Advantage:* Smaller surface; generated source is just text, and the user compiles it.
- *Disadvantage:* No programmatic workbook→model path, which blocks the MCP use case in the
  master plan.
- *Why rejected:* `ModelDefinition` throws rather than traps, so the hazard that motivated this
  alternative in the superseded proposal no longer exists.

**Alternative 4: Evaluate formulas in Swift and write cached values.**
- *Advantage:* Trivial; always produces numbers.
- *Disadvantage:* It is the exact anti-pattern the orcaset article documents — a second evaluator
  whose results nothing traces back to the sheet. We already have one instance of this shape in
  `MonteCarloExtension.evaluateFormula`, where `case .function: return 0`
  (`MonteCarloExtension.swift:164`) silently returns zero for every `PMT`/`NPV`/`IRR` node.
- *Why rejected:* Categorically. Registry delegation (`TypedModelAuthoring.md` §4) is the
  correct answer — one implementation, canonical, tested against Excel.

## 14. Future Directions

- **Multi-sheet recognition** — cross-sheet references currently diagnose; a workbook-level pass
  would restore symmetry with `MultiSheetExporter`.
- **Registry growth driven by residue** — `.unregisteredFunction` diagnostics are a ranked
  worklist of which Excel function to register next.
- **Named-range support** — `.namedRange` carries real semantic signal; an author already told us
  what a cell means. Possibly a higher-yield naming source than label binding.
- **Learned lexicon** — seeded from a corpus rather than hand-listed.
- **Round-trip editing** — recognize, modify the `ModelDefinition`, re-export to `.xlsx`.
- **`OFFSET`/`MATCH` folding beyond Tier 1** — the tiered scheme in §3 covers the provable cases;
  a corpus pass would show whether Tier 2 guarded dispatch is worth the conditional machinery.
- **`MonteCarloExtension` repair** — its silent-zero evaluator should route through the registry
  once it exists, eliminating the last second-evaluator in this package.

## 15. Open Questions

0. ~~**Should `IF` + comparison operators move earlier than D8 schedules them?**~~
   **Resolved 2026-09-01: yes. Pulled forward into Phase 2, amending D8.**

   The evidence, kept because it is the whole reason: measured against a production credit model,
   **2982 of 5011 formulas contain `IF`**, and the `equal` operator alone accounted for 39 of the
   48 import warnings on its comparison sheet. The Wharton model shows exactly **one** — so the
   reference workbook badly understates a gap that dominates real ones. Deciding this phase order
   from Wharton alone would have been deciding it from an unrepresentative sample.

   Three things make forward the right direction rather than merely the tempting one. The work is
   cheap and self-contained: comparison operators are the same shape as `NodeFormula.power`, which
   cost one enum case and five switch sites. It depends on nothing upstream — D8 placed it behind
   the function-registry gate, but comparison operators are *operators*, not registry entries, and
   `IF` is a control construct rather than a financial function. And it unblocks work already
   written down: Tier 2 of the dynamic-reference scheme (§3) cannot proceed without it.

   **What D8 got right, and is retained:** `IF` still must not become a general conditional in
   `ModelDefinition`. Decision D9 stands — an `IF` answerable from the timeline alone is demoted
   to an indicator series, and only a genuinely value-dependent `IF` survives as a conditional.
   Pulling the *representation* forward does not pull forward the *semantics*.
1. **Does `ModelBuilder` ship before `TypedSourceWriter`?** `ModelBuilder` only needs the string
   API and could land in Phase 3; `TypedSourceWriter` waits on upstream Phase 3. Recommend yes.
2. ~~**Prior-period reference syntax.**~~ **Resolved 2026-09-01: not supported, deliberately.**
   `FormulaEvaluator.swift:119-124` and `CycleSolver.swift:222-226` both document the exclusion;
   the latter states that "the roll-forward that carries a closing balance into the next period
   stays the caller's loop." Upstream `TypedModelAuthoring.md` Part 2.5 makes that loop reusable
   as `PeriodDriver` + `Rollforward`. **Consequence for this proposal:** Stage 3 must
   *decompose* each Excel formula into a period-local part plus rollforward declarations —
   see §3 below. This is new recognizer work, not a free ride.
3. ~~**How is a two-variable What-If data table recognized?**~~ **Resolved 2026-09-01.** Core
   already ships `TwoWayScenarioSensitivityAnalysis`
   (`Scenario Analysis/SensitivityAnalysis.swift:318`) with exactly the right shape —
   `inputDriver1/2: String`, `inputValues1/2: [Double]`, `results: [[Double]]` — plus
   `runTwoWaySensitivity` (`:585`), one-way `ScenarioSensitivityAnalysis` (`:142`), and
   `TornadoDiagramAnalysis` (`:759`). Recognition emits these types directly; see §3.
4. **Coverage denominator** — do label cells and formatting-only cells count as "populated"?
   Affects whether 100% is attainable in principle.
5. **Should unit inference default on or off** in v1? (§12 argues the risk both ways.)

## 16. Documentation Strategy

**Documentation Type:** Narrative Article Required

**Complexity Threshold Check:**
- Combines 3+ APIs? **Yes** — `ModelImporter`, `ExcelRecognizer`, `ModelBuilder`,
  `TypedSourceWriter`, plus `ModelDefinition`/`FormulaEvaluator`/`CycleSolver`.
- Requires 50+ lines? **Yes** — the five-stage pipeline with worked examples.
- Needs theory/background? **Yes** — why recognition is lossy and why honest residue reporting
  matters more than coverage is the conceptual core.

**Article Name:** `RecognitionGuide.md` in `Sources/BusinessMathExcel/BusinessMathExcel.docc/`.
No collision with any Swift symbol name.

---

## Proposed Phasing

Coverage on the Wharton workbook is tracked at every phase, targeting 100%. It is a progress
metric, not a kill gate.

| Phase | Repo | Scope | Gate |
|---|---|---|---|
| 0 | Excel | Bump the BusinessMath pin; drop any `BusinessMathDSL` reference | `swift build` clean |
| 1 | Excel | `ModelImporter` fixes (`.cellRange`, `.power`, threaded warnings, multi-sheet) | Lossy imports now warn; regression tests green |
| 2 | Excel | Stages 1–2 (`SheetGrid`, `PeriodAxis`, `LabeledSeries`) + `Coverage` instrumented, with address-fallback naming. **Plus `IF` and the comparison operators in `NodeFormula`** (pulled forward from D8 — see §15 Q0; representation only, semantics stay with D9). **Measured 2026-09-01: `ANSWER KEY` 70% coverage (196 of 279 cells), 36 series — 26 uniform, 3 seeded rollforward, 7 non-uniform** | Wharton coverage measured **and per-row formula uniformity reported** — the count of non-uniform rows is the number that determines how much of the sheet is hand-edited, and how far `IF`-free encoding can reach |
| — | — | **Upstream gate:** `TypedModelAuthoring.md` 2a–2c (function registry) **and 2d (`PeriodDriver`)**. No longer covers `IF`/comparisons, which moved to Phase 2 | Registry + driver green |
| 3 | Excel | Stage 3 `FormulaTranslator` with **lag decomposition** + Stage 4 assembly + `ModelMaterializer` (renamed from `ModelBuilder`; the name was taken in core). Dynamic references (§3) are **Tier 1 folding only** — an unfoldable `INDIRECT`/`OFFSET` goes to residue rather than blocking the phase | ✅ **Done 2026-09-02.** Golden path reproduces Excel's own 1,000,000 / 1,150,000 / 1,322,500. `ANSWER KEY`: 21 accounts, 3 rollforwards, 12 residue |
| 4 | Excel | Circular-interest recognition through the cycle solver under `PeriodDriver` | ✅ **Done 2026-09-02. Year-1 interest 11.75** on a cash-swept revolver (beginning-balance accrual gives 12.00); **Wharton IRR 24.67% / MoM 3.01** still reproduce through recognition. The `ANSWER KEY` as a whole does **not** yet materialize — see Phase 5 |
| — | — | **Upstream gate:** `TypedModelAuthoring.md` Phase 3 (`Account`/`Expr`) | Typed layer green |
| 5a | Excel | **Block detection** (the measured blocker) | ✅ **Done 2026-09-02.** `ANSWER KEY` materializes and runs; **125 of 125 values match the sheet's own**. One account dropped and named — see §17.7 |
| 5b | Excel | `UnitInference` | ✅ **Done 2026-09-02.** 30 of 46 accounts carry a unit, 0 conflicts; every one of the sheet's 17 formats read correctly — see §18.7 |
| 5c | Excel | `TypedSourceWriter`, on BusinessMath 2.9.0 | ✅ **Done 2026-09-03.** Emitted source compiles and evaluates to the plan's numbers, proven by a golden file the test target builds. `ANSWER KEY`: 33 typed line items, 10 of 30 definitions checked by the build — see §19.7 |
| 6 | Excel | Data-table recognition via `_DATATABLE` markers (**not** `.array` cells — see §3 correction) → `TwoWayScenarioSensitivityAnalysis` | Recomputed grid matches Wharton's published IRR sensitivity; **100% coverage** |
| 7 | Excel | `RecognitionGuide.md`, README, CHANGELOG, master plan reconciliation | Quality gate 0/0 |

Phases 1–2 depend on nothing upstream and produce the measured evidence that shapes everything
after. Phase 6 is last because the What-If table is the one Wharton construct with no obvious
mapping to accounts-and-formulas, and it should be designed against real coverage data rather
than speculation.
### Measured after Phases 3 and 4 — 2026-09-02

Reported by `WhartonImportMeasurementTests`, which prints rather than gates.

| | `ANSWER KEY` | `BLANK MODEL` |
|---|---|---|
| Populated cells | 279 | 157 |
| Recognized | 196 (70%) | 88 (56%) |
| Series bound | 36 | 19 |
| — uniform / seeded / non-uniform | 26 / 3 / 7 | 14 / 1 / 4 |
| Accounts translated | 21 | 6 |
| Rollforwards | 3 | 1 |
| Residue | 12 | 7 |
| Materializes | no | no |

Recognition coverage has not moved since Phase 2, which is expected: Phases 3 and 4 turned
recognized cells into *runnable* ones rather than recognizing more of them. What did move is
that a plan now materializes and runs — proven on the golden path and on the revolver, and
refused on Wharton for one identifiable reason.

**The blocker is a column collision, not a formula gap.** Rows 3 through 11 of the `ANSWER KEY`
hold two assumption tables side by side: a label in B with its value in D, and a second label in
F with its value in H. Neither is a period series — they sit sixteen rows above the timeline in
row 27. But H is also the 2026 column, so label binding sweeps each row across the axis and
reads an unrelated cell as that row's 2026 value. `Revenue growth` is `10%` in D11 and
`SUM(H9:H10)` in H11; the row therefore disagrees with itself, is refused as non-uniform, and
`% growth` — which needs it — cannot resolve. Materialization stops there.

Six of the seven non-uniform rows on the `ANSWER KEY` are this one overlap. The remaining
diagnostics are genuine and much smaller: four duplicate labels (disambiguated by cell, not
lost), four unsupported constructs, and one forward reference.

This is what makes **block detection** Phase 5's first item rather than `UnitInference`. The
recognizer currently assumes one sheet is one timeline; a real model is a stack of blocks, only
some of which are on the axis. Nothing downstream can be measured honestly until a sheet's
assumptions stop being read as periods, and the fix is worth more than any further formula
coverage: it is one cause standing between a 70%-recognized sheet and a sheet that runs.

The refusals themselves are the design working. Every one of these produced a *diagnostic and
residue* rather than a number — including `unseededCarry`, added in Phase 4 after a carry seeded
with a fabricated zero produced a model that ran, converged, and was wrong in every period.


## 17. Phase 5 Design — Block Detection

Added 2026-09-02, after the Phase 3–4 measurement. This section specifies the work that must
land before `UnitInference`, and it exists because the measurement said so rather than because
the plan predicted it.

### 17.1 What the sheet actually looks like

The `ANSWER KEY` is not one grid. Above the model it holds **three label/value tables side by
side**, and below it one timeline:

```
      B                     D        F                     H       J               L
  2   Assumptions                    Purchase Price Analysis
  3   Purchase Price Fin.            Purchase Multiple      5
  4   Debt                  0.6      Entry EBITDA           40
  5   Equity                =1-D4    Total Purchase Price   =H4*H3
  …
  9   2023 Revenue          100      Term Loan              =D4*H5   Purchase Price   =…
 11   Revenue growth        0.10     Total Sources          =SUM(…)  Total Uses       =…
  …
 27   P&L Analysis          Closing  2023  2024  2025  2026  2027  2028   <- the axis, row 27
 30   Revenue                        =…    =…    =…    =…    =…    =…
```

Column `D` is the at-close anchor for the timeline, and *also* the value column for the
left-hand assumptions table. Column `H` is the 2026 period, and *also* the value column for the
middle table. Neither coincidence is unusual; both are invisible to a recognizer that treats a
sheet as one grid with one timeline.

### 17.2 The two defects, which compound

**Defect 1 — a label claims values belonging to another label.** Binding sweeps a row's label
across every axis column, so `B11` ("Revenue growth") claims `H11`, which is the middle table's
`SUM(H9:H10)` and belongs to `F11` ("Total Sources"). The row then holds `10%` and a
sources-and-uses total, disagrees with itself, and is refused as non-uniform. Six of the seven
non-uniform rows on the `ANSWER KEY` are this.

**Defect 2 — no scalars.** Fix defect 1 alone and `Revenue growth` has no cells on the axis at
all; it holds one value in `D11`, which the recognizer reads as an at-close anchor because `D`
is the anchor column *for the timeline block*. Row 11 is not in that block, so `D11` is not an
anchor — it is the assumption's value. Without a way to say that, the row still vanishes, and
`% growth`, which references it, still cannot resolve.

Neither fix is worth anything without the other. That is why they are one phase.

### 17.3 Rule 1 — a value belongs to its nearest label

A label owns a value cell only when no other text cell lies between them on the same line.

This is local, needs no notion of a block, and is the whole of defect 1. On row 9, `F9`
("Term Loan") stands between `B9` and `H9`, so `H9` is Term Loan's, not `2023 Revenue`'s. On
row 30 nothing stands between `B30` and `E30:J30`, so the model rows are untouched.

Chosen over the alternatives because it reads the sheet the way a person does. A column-range
rule ("the timeline owns E:J") needs the ranges to come from somewhere, and the only honest
source is the same nearest-label logic. A density rule ("a row on the timeline populates most
of its periods") drops `Exit Value`, which legitimately holds one cell in the final year.

### 17.4 Rule 2 — the timeline governs its own block

The period axis governs rows at or below its heading line, not the whole sheet. Outside that
block:

- The anchor column carries no special meaning; a value there is just a value.
- A label owning exactly one value becomes a **scalar** — an assumption with one figure that
  holds for every period, materialized as an input with that value repeated across the
  timeline. `Revenue growth` becomes `0.10` in all six years, and `% growth` resolves.
- A label owning a *formula* off the axis becomes a **derived scalar**: `Total Purchase Price`
  is `=H4*H3`, which is `Entry EBITDA * Purchase Multiple` and wants to stay that way rather
  than being flattened to `200`.

The boundary is the axis heading line because that is what the sheet itself declares. A model
that puts timeline rows *above* its year header is not supported and will report rather than
guess — a limitation worth stating, not worth pre-solving.

### 17.5 What this is not

Not general section detection. Blank-row spacing, merged headings, and bold formatting are all
tempting signals and all unreliable — §12 already records the merged-header problem. Rules 1
and 2 use only what the recognizer already trusts: where the axis is, and which cells hold
text. Anything they cannot place still becomes residue with a reason.

### 17.6 Gate

The `ANSWER KEY` **materializes and runs**. That is a step change from "70% recognized" and it
is the number to report: the sheet either produces a `ModelDefinition` that evaluates over six
periods, or it names the row that stopped it.

### 17.7 Measured — 2026-09-02

Block detection landed as designed, and the design was incomplete. Rules 1 and 2 did what §17.3
and §17.4 said they would; three further blockers stood behind them, none of them block
detection, and each was found by measuring rather than by reasoning:

- **`SUM` over a cell range.** `SUM(E42:E46)` is a sum of accounts read at one moment. A range
  is readable because it stays in one column, not because that column is a period — the Wharton
  sources-and-uses totals were working or failing according to whether their block happened to
  overlap the timeline's columns.
- **The named range `Circ`.** Unresolvable rather than unsupported: SwiftXLSX parsed
  `xl/workbook.xml` for defined names and discarded the result twice. Fixed upstream and released
  as SwiftXLSX 0.8.0.
- **The IRR sensitivity grid.** A What-If table declares its span on its master cell, and
  everything else in it is a cached number. Without knowing that, any label on those rows appears
  to own them — the same collision Rule 1 fixed for series, one block further right.

And one defect the measurement exposed that was older than this phase. A reference re-derived its
account name from the nearest label, discarding the disambiguation binding applies when two rows
share a heading. `Equity of PE Firm` summed a column containing `Debt` in row 58 and resolved it
to the `Debt` **assumption** in row 4 — 60%. It computed 0.6 in every period against a sheet
saying 0 and then 240.98: a model that ran, converged, and was wrong. References now take the
name the binder gave the cell.

| | Phases 3–4 | Phase 5 |
|---|---|---|
| Recognized cells | 196 (70%) | 202 (72%) |
| Accounts | 21 | 46 |
| Residue | 12 | 3 |
| Non-uniform rows | 7 | 1 |
| `unsupportedFormulaNode` | 4 | 0 |
| Materializes | no | **yes** |
| Values matching the sheet's own | — | **125 of 125** |

Every formula on the `ANSWER KEY` now translates, and every value the model produces matches what
Excel cached in that cell to 1e-4 relative. The tolerance is relative because the sheet holds both
a 0.4 margin and a 240 exit value, and it is loose enough to absorb the difference between Excel's
iteration on the circular block and ours, which is about 5e-6.

**What is left, and why.** One account, `Equity of PE Firm`, is dropped: it needs row 58, `Debt`
in the exit analysis, which holds literals until the final year and then a formula. That is a
*terminal event* rather than a period series, and a `ModelDefinition` has one rule per account for
all periods — the same expressiveness limit that made a seeded row need a rollforward, in a shape
no rollforward fits. `Exit Value` in row 60 is the same thing with one cell. This is a real limit
and it is named rather than worked around; the exit block is also where IRR and MoM come from, and
those still reproduce through a path that reads the row directly.

The `BLANK MODEL` sheet does not run, which is correct: it is the exercise with the answers
removed, so rows its formulas depend on are genuinely empty.

`ModelMaterializer.buildResolvable(from:)` was added for this. `build(from:)` throws on the first
hole, which is right when a caller wants a whole model or nothing, and wrong when the question is
how much of a workbook works. It removes what cannot resolve and returns it — refusal, not repair.

## 18. Phase 5b Design — Unit Inference

Added 2026-09-02. `TypedSourceWriter` stays gated on `TypedModelAuthoring.md` Phase 3; unit
inference is not, and is written first so the typed writer has something to type with.

### 18.1 What the sheet says, measured before designing

Every format string on the Wharton `ANSWER KEY`, by frequency:

| Cells | Format | Says |
|---|---|---|
| 148 | `General` | nothing |
| 96 | `_(* #,##0.0_);…` | a number, no unit |
| 57 + 39 + 22 + 6 + 3 | `…[$$-409]…`, `…"$"…` | money |
| 35 + 25 + 11 | `0%`, `0.0%`, `…#,##0.0%…` | a proportion |
| 7 | `"Year"\ #` | a period count |
| 7 + 1 | `0.00"x"`, `_(0.0\x_)…` | a multiple |

Three things follow, and each shapes the design more than any reasoning would have.

**The format is evidence, not proof.** `E36` is `Less: Interest` — money by any reading — and its
format is the plain `_(* #,##0.0_)` with no currency in it at all. A design keyed on format alone
would call it unitless, and one keyed on format *first* still must let the label speak.

**Most cells say nothing.** 148 of 279 are `General`. Any design that requires a unit will invent
most of them.

**Format cannot separate `rate` from `ratio`.** `0.0%` is what `Interest Rate`, `Revenue growth`,
`EBITDA margin` and `Debt` (as a percentage of purchase price) all carry. The dimension is
visible; the per-period sense is not.

### 18.2 The rule

Format establishes the **dimension**; the label may sharpen it; neither invents one.

- A format containing a currency symbol — `"$"`, `[$$-409]`, any `[$…]` — is ``UnitKind/money``.
- A format containing `%` outside a literal is a proportion.
- A format containing `"x"` or an escaped `\x` is a multiple, which is dimensionless, so
  ``UnitKind/ratio``.
- A format naming a period — `"Year"`, `"Yr"` — is ``UnitKind/duration``.
- Anything else, `General` included, states nothing.

### 18.3 When two units both fit, take the weaker claim

A proportion is a ``UnitKind/ratio`` unless the label says it is per period — `rate`, `yield`,
`p.a.`, `per annum`, `growth`. This asymmetry is deliberate and is the whole of the judgment
here: calling an interest rate a `ratio` is *imprecise but true*, since a rate is a proportion;
calling a margin a `rate` is *false*. Where the evidence supports both, the design takes the claim
that cannot be wrong.

### 18.4 Silence is a result

An account whose cells state nothing gets `unit == nil` and a
``DiagnosticCode/unitInferenceFailed`` at `info`. Not a warning — a workbook that formats nothing
is not defective, and 148 warnings would bury the findings that matter. §15 already settled what
`nil` means downstream: `TypedSourceWriter` emits an untyped account rather than picking one.

### 18.5 Disagreement within a row is a finding

Cells bound to one account that state *different* dimensions produce
``DiagnosticCode/unitConflict`` and no unit. A row holding both money and a percentage is either a
modelling error or a row bound to the wrong cells, and both are worth seeing. This is the one
place unit inference can catch a defect rather than merely describe one.

### 18.6 Gate

Every `$`-formatted account on the `ANSWER KEY` is money and every `%`-formatted one is a
proportion; nothing formatted `General` is assigned a unit; and the count of accounts left
unitless is reported rather than minimised.

### 18.7 Measured — 2026-09-02

| | `ANSWER KEY` |
|---|---|
| Accounts carrying a unit | 30 of 46 |
| — money | 18 |
| — rate | 5 |
| — ratio | 7 |
| Stating nothing | 16 |
| Conflicts | 0 |

Every one of the sheet's 17 distinct formats is read correctly: each currency form is money, each
genuine percent a proportion, both multiple forms a ratio, the year header a duration, and
`General`, the date, the hidden format and the two width-padded plain formats state nothing.

Two things the design did not anticipate, both found by running it:

**`_` is a width placeholder, not a character.** `#,##0_)_%` displays no percentage — the `%` is
padding. 39 cells carry a currency format padded that way and would have read as rows
contradicting themselves; 7 more are plain numbers that would have read as proportions. Excel's
format grammar has two skip markers, `\` which shows the next character and `_` which shows a
space as wide as it, and only reading both alike gets these right.

**The at-close cell is evidence.** `Purchase Price` in row 28 carries a plain number format in
every period and a currency format in its at-close cell — which is the sheet's only statement
about what the row is. Inference now reads the anchor along with the periods; without it the
account came out unitless while its own cells said money.

Sixteen accounts state nothing, which is the honest figure rather than a shortfall: 148 of the
sheet's 279 cells are formatted `General`, and inventing units for them was never the goal. The
125-of-125 agreement with the sheet's cached values is unchanged, as it must be — a unit is
metadata about a number, not a change to it.

## 19. Phase 5c Design — `TypedSourceWriter`

Added 2026-09-03, once **BusinessMath 2.9.0** shipped the layer this emits against: `ModelUnit`,
`LineItem<U>`, `Expr<U>`, the operator algebra, and `validateUnits()`.

### 19.1 What it is for

A recognized workbook can already be materialized and run. That is the right answer for a tool;
it is the wrong answer for a person, who wants to *read* what the sheet said, keep it under
version control, and have a compiler check it. Emitted source is diffable, reviewable, and — the
point of the typed layer — wrong in ways the build catches.

### 19.2 The problem: a rendered formula is lossy

`RecognizedAccount.formula` is a string in `FormulaEvaluator` grammar: `([Revenue] * [Margin])`.
To emit `revenue.expr * margin.expr` the writer needs the operator structure back, and the string
does not carry it. `FormulaEvaluator.Node` is internal to BusinessMath, so it cannot be parsed
here either.

This is the third time this session the same shape has appeared. Units were lost when `Expr`
rendered to a string, and had to be carried alongside. Named ranges were parsed by SwiftXLSX and
discarded before any caller could reach them. Here the structure is built by ``LagDecomposition``
and thrown away at the moment it becomes text.

Writing a parser for our own output would be the fourth instance of the same mistake: recovering
by inference something we knew for certain a moment earlier.

**So the recognizer carries the tree.** ``LagDecomposition`` builds a `RecognizedExpression` and
*renders* the formula string from it. The string stays byte-identical — which the existing 471
tests, including the 125-of-125 Wharton agreement, are what prove.

### 19.3 Units decide the spelling, and silence is not a unit

§12's amendment stands: an account whose unit was never established emits **untyped**. Since
`LineItem<U>` has no untyped form, that means the string API:

```swift
// Typed — the sheet said what this is.
let revenue = LineItem<Money>("Revenue")            // ANSWER KEY!E30
let margin  = LineItem<Ratio>("EBITDA margin")      // ANSWER KEY!D10

model = model.defining(ebitda, as: revenue.expr * margin.expr)

// Untyped — the sheet formatted nothing, so nothing is claimed.
model = model.defining("Total FCF", as: "([EBITDA] - [Less: Taxes])")   // ANSWER KEY!E47
```

The two mix freely in one model, which is exactly what `1.10-TypedModelAuthoring.md` says the
string API is for. Sixteen of the `ANSWER KEY`'s 46 accounts state no unit, so this is the common
case on real input, not a corner.

An expression **mixing** a typed and an untyped operand cannot be written typed either, because
there is no `Expr` for the untyped side. Those definitions go out untyped whole, rather than
half-cast into something that would not compile.

### 19.4 What the emitted file must satisfy

Not "looks plausible" — it must **compile against BusinessMath 2.9.0** and evaluate to the same
numbers the plan does. A generated file that does not compile is worse than none, and one that
compiles but computes differently is worse still.

The test therefore renders, writes, compiles, and runs. That cannot use `Process` — the safety
checker refuses an unbounded spawn, correctly, and the same constraint that redirected the
compile-failure checks in `TypedModelAuthoring` applies here. The check instead compares the
emitted source against a **checked-in golden file** compiled as part of the test target: if the
writer's output diverges from the golden, the test fails; the golden itself compiles and runs
because it is ordinary source in the package.

### 19.5 Provenance is not a comment ornament

Every declaration carries `// <sheet>!<cell>`. On a 46-account sheet, the first question a reader
asks of any line is *which cell did this come from* — and it is the only way to check the
recognizer's work against the workbook by hand. Where an account has several cells the anchor is
named, since that is the one a reader would look at first.

### 19.6 Gate

The `ANSWER KEY` emits source that compiles, and evaluating it reproduces the same 125 values the
plan does. Accounts whose unit is unknown are emitted untyped, and the count of each is reported.

### 19.7 Measured — 2026-09-03

The `ANSWER KEY` emits 167 lines of Swift.

| | |
|---|---|
| Typed line items | 33 — Money 20, Rate 5, Ratio 8 |
| Definitions | 30 |
| — checked by the build | 10 |
| — string API | 20 |

The gate is met: emitted source compiles and evaluates to the plan's numbers. That is proven on a
small fixture rather than on Wharton, because the proof is a **checked-in golden file compiled by
the test target**, and a 167-line generated file for a workbook that cannot itself be checked in
would be a fixture nobody could regenerate. `GoldenSourceTests` compiles the writer's output,
runs it, and compares it account by account against materializing the same plan — then
regenerates and diffs, so the compiling file cannot drift from what the writer now emits.

**Why twenty definitions are not compiler-checked**, counted rather than estimated:

| Reason | Count |
|---|---|
| The account states no unit | 13 |
| `SUM` — no typed overload upstream | 5 |
| `AVERAGE` — no typed overload upstream | 1 |
| Reads an account that states no unit | 1 |

Nothing is refused by the algebra. Every untyped definition has an external cause, and thirteen
of the twenty are the same one: those rows carry the plain accounting format, which §18 already
established states nothing. The typed layer is doing what it can with what the sheet said.

**Two findings worth carrying forward.**

`SUM` and `AVERAGE` account for six. BusinessMath's typed layer has `min`, `max` and `abs` and
nothing else, so a total — which is what a financial model is mostly made of — cannot be written
typed. A variadic `sum` over same-unit expressions is the obvious addition and belongs upstream in
a later minor, not here.

The growth-factor idiom was found by measuring. `Revenue Closing = Revenue * (1 + [% growth])` is
`Money × (Ratio + Rate)`, which has no overload — and that refusal is exactly why `factor(_:)`
exists upstream. The recognizer renders every growth row in that shape, so recognising it is the
difference between emitting the commonest line in modelling typed and sending it to the string
API. Matched narrowly: exactly `1`, exactly a rate on the other side.
