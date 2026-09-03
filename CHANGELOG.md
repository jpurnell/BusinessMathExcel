# Changelog

All notable changes to BusinessMathExcel will be documented in this file.

## [Unreleased]

## [0.7.0] - 2026-09-03

**A spreadsheet can be read as a model.** 0.6.0 could read a workbook and say what two of its
stages meant. This release recovers a runnable model from one: the accounts, the timeline, the
rules that hold in every period, and the balances that carry between them — then materializes a
`ModelDefinition`, or emits it as Swift a compiler can check.

Measured on the Wharton LBO Practice Model, a teaching workbook with a published answer key:

| | |
|---|---|
| Recognition coverage | **85%** — 238 of 279 populated cells |
| Accounts recovered | 46 |
| Values matching the sheet's own | **125 of 125** |
| Published IRR | **24.67%**, reproduced |
| Published multiple of money | **3.01×**, reproduced |
| Emitted Swift | 167 lines, 33 typed line items |

The layering is the design. `Import/` never interprets. `Recognition/` interprets and **never
throws** — it produces a plan, and anything it cannot express becomes residue carrying the
reason. `Materialize/` validates and **throws**, because a model built from a plan with a hole in
it would run and produce numbers.

Every refusal in that middle layer exists because guessing produces a model that runs and is
wrong: a row computing two ways, a reference reaching two periods back, an opening balance nobody
stated, one name meaning both a balance and a percentage. **A formula's cached value is never
substituted for a formula that could not be translated** — the number would be right once, and
wrong forever after the first input changed.

Needs **BusinessMath 2.9.0** and **SwiftXLSX 0.10.0**, both released for this work. Three
SwiftXLSX releases came out of it (0.8.0 named ranges, 0.9.0 cell styles, 0.10.0 cached formula
writes), and all three were the same shape: information the reader already understood, with no
way for a caller to reach or state it.


### Added
- `RecognizedSensitivity`: a two-variable What-If table, read. Excel writes one as a single
  marker on the body's top-left cell — everything that gives it meaning sits around the body and
  is identified by position, not by any label: values for the row driver above, values for the
  column driver to the left, and the formula being measured in the corner.
- `RecognizedSensitivity.analysis()`: maps to BusinessMath's `TwoWayScenarioSensitivityAnalysis`,
  keeping the orientation that type documents — `results[i][j]` is `inputValues1[i]` against
  `inputValues2[j]`, so the column driver is driver 1. Getting it backwards transposes a grid
  silently, so it is pinned by an asymmetric fixture where a transpose cannot pass.
- `RecognizedModel.sensitivities`: beside the accounts rather than among them. A table is an
  analysis *of* the model, and a grid of answers is not a rule, so `ModelMaterializer` ignores it.
- Requires **SwiftXLSX 0.10.0** (pin bumped from 0.9.0) for `write(_:to:cached:style:)` — a data
  table's body is cached numbers under one marker, and until 0.10.0 no workbook built in code
  could be made to look like that.

### Measured
- Wharton `ANSWER KEY`, 2026-09-03: one 5×5 table read, drivers `Multiple (based on 2028 EBITDA)`
  × `Revenue growth`. **Recognition coverage 72% → 85%** (202 → 238 of 279) — the table's 36
  cells, exactly, which had been excluded from binding on purpose since Phase 5a. The 125-of-125
  agreement is unmoved, as it must be.
- Recomputing the grid is **not** possible and the measurement says why: the measured output is
  `IRR` over a whole row — an aggregate over the timeline, which a period-local model does not
  compute — reducing `Equity of PE Firm`, the row already recorded as beyond a model with one
  rule per account.

### Added (Phase 5c)
- `RecognizedExpression`: a recognized formula as a tree — account references, numbers, binary
  operators with comparisons distinguished from arithmetic, negation, calls, and the list a cell
  range expands to. `LagDecomposition` builds it and the formula string is **rendered from it**,
  so there is one source of truth.
- `RecognizedAccount.expression`: the same rule the formula string states, before it became text.
- `TypedSourceWriter.swiftSource(for:sheetName:modelName:)`: emits a plan as Swift source — an
  `enum` of static members with `definition()` and `run()`, so it compiles into a library or test
  target rather than only as `main.swift`. Every declaration carries a `// sheet!cell` comment.
- Requires **BusinessMath 2.9.0** (pin bumped from 2.8.0) for `LineItem`, `Expr` and
  `validateUnits()`.

### Fixed
- Renaming an account was textual, so it also rewrote the inside of a longer name containing it —
  `Debt` within `Debt Service`. It is structural now, which the tree makes possible.
- `case "\\", "_" where !inLiteral` in `UnitInference` binds the guard to the last pattern only,
  so a backslash inside a number-format literal set the skip marker and consumed the next
  character — which can be the quote that closes the literal, running it on to swallow the rest
  of the format.

### Measured
- Wharton `ANSWER KEY`, 2026-09-03: 167 lines emitted, 33 typed line items (Money 20, Rate 5,
  Ratio 8), and 10 of 30 definitions checked by the build. Nothing is refused by the algebra:
  of the twenty untyped, thirteen are accounts the sheet states no unit for, six are `SUM` or
  `AVERAGE` — which the typed layer upstream has no overload for — and one reads a unitless
  account. The 125-of-125 agreement with the sheet's cached values is unchanged.

### Added (Phase 5b)
- `UnitInference`: what a number *is*, read from how the sheet presents it. The format
  establishes the dimension, the label may sharpen it, and neither invents one. Where two units
  both fit — `0.0%` is what an interest rate and a margin both carry — the weaker claim wins:
  calling a rate a `ratio` is imprecise but true, calling a margin a `rate` is false.
- `ImportResult.numberFormats` and `SheetGrid.numberFormats`: each cell's format string as the
  file states it, carried and never interpreted. `General` is carried through as written.
- `RecognizedAccount.unit` is populated. An account whose cells state nothing gets `nil` and
  `unitInferenceFailed` at **info**, not warning: a workbook that formats nothing is not
  defective. Cells stating different dimensions give no unit and `unitConflict` at warning,
  which is the one place unit inference can catch a defect rather than describe one.
- Needs **SwiftXLSX 0.9.0** (`Worksheet.style(at:)`), pin bumped from 0.8.0. Styles had been
  resolved on read since the reader was written and kept where no caller could reach them.

### Measured
- Wharton `ANSWER KEY`, 2026-09-02: 30 of 46 accounts carry a unit — 18 money, 5 rate, 7 ratio —
  with **0 conflicts**. Sixteen state nothing, which is the honest figure rather than a
  shortfall: 148 of the sheet's 279 cells are formatted `General`. All 17 distinct formats read
  correctly. The 125-of-125 agreement is unchanged, as it must be.

### Added (Phase 5a)
- `ScalarBlock` and `ScalarAssumption`: a label outside the timeline owning one value is an
  assumption. A literal becomes an input holding for every period; a formula stays derived, so
  `Total Purchase Price` remains `Entry EBITDA * Purchase Multiple` rather than `200`.
- `DataTableBlock`: the rectangle a What-If table occupies. Excel declares the span once, on the
  master cell, and leaves the rest of the grid holding cached numbers; a two-way table also
  occupies the input row above it and the input column to its left.
- `ModelMaterializer.buildResolvable(from:)` and `ResolvableModel`: builds the part of a plan
  that resolves and returns what it dropped, transitively. Refusal, not repair — nothing is
  filled in or defaulted, and a duplicate account or unparseable formula still throws, because
  those are defects in recognition rather than gaps in the sheet.
- `SheetGrid.namedCells` and `accountName(at:)`; `ExcelRecognizer.recognize(_:options:in:)` takes
  the workbook, because a named range is workbook-level and cannot be read from a sheet alone.
- `DiagnosticCode.ambiguousAssumption` and `DiagnosticCode.unresolvedReference`.
- Named ranges resolve, on **SwiftXLSX 0.8.0** (pin bumped from 0.7.0). A resolved name then
  takes the cell's own road: pinned or filling across, on the axis or off it.
- A `SUM` over a cell range reads as the accounts it covers. A range is readable because it stays
  in one column, not because that column is a period; one running *along* the timeline is refused
  with a message of its own, since translating it period-locally would drop every period but one.

### Fixed
- A label swept the whole period axis and claimed values belonging to other labels. Real models
  put small tables side by side, and on the Wharton `ANSWER KEY` their value columns land in the
  timeline's columns: `Revenue growth` claimed a sources-and-uses total and was refused as a row
  that disagreed with itself. A label now owns a value only when no other text cell stands
  between them. Non-uniform rows fell from 7 to 1.
- The anchor column was read as *at close* everywhere, including sixteen rows above the timeline
  where it is just the column the assumptions were typed into.
- **A reference re-derived its account name from the nearest label**, discarding the
  disambiguation binding applies when two rows share a heading. `Equity of PE Firm` summed a
  column containing `Debt` in row 58 and resolved it to the `Debt` *assumption* in row 4 — 60%.
  It computed 0.6 in every period against a sheet saying 0 and then 240.98: a model that ran,
  converged, and was wrong. References take the binder's name, and both names survive a collision
  rather than one being dropped.
- A row pinned to its own first period — `F33 = $E$33`, the idiom for *set this in year one and
  hold it* — translated to an account defined as itself, which formed a one-account cycle and
  failed as underdetermined. It now takes the seed's own definition.
- A text literal rendered as a bare name, which reads as an account reference and would bind to a
  real account spelled that way. Refused with a reason: a model of numbers has nowhere to put a
  word.
- `CellRef` hashes its `$` markers, so a lookup keyed on a plain cell missed every absolute
  reference — which is most references to an assumption.

### Measured
- Wharton `ANSWER KEY`, 2026-09-02: **the sheet materializes, runs, and reproduces 125 of the
  125 values Excel cached in it**, to 1e-4 relative. Recognition coverage 72% (202 of 279),
  46 accounts, residue 3, non-uniform rows 1, `unsupportedFormulaNode` 0. IRR 24.67% and MoM 3.01
  still reproduce.
- One account is left out and named: `Equity of PE Firm` needs row 58, which holds literals until
  the final year and then a formula — a terminal event rather than a period series, which a model
  with one rule per account cannot state.

### Added (Phases 3–4)
- `LagDecomposition`: splits an Excel formula into a period-local formula and the carries it
  implies, reading `$` as the seam between a reference that fills across (last period) and one
  that is pinned (an assumption).
- `RecognizedModel` and `ExcelRecognizer`: recognition never throws. It produces a plan, and
  anything it cannot express becomes residue carrying the reason.
- `ModelMaterializer`: turns a plan into a `ModelDefinition` and its rollforwards. This one
  validates and throws — a definition with a hole in it would run and produce numbers. Named
  for the `ModelBuilder` in the proposal, which is a name BusinessMath already exports.
- `DiagnosticCode.unseededCarry`: a rollforward whose opening the sheet does not state anywhere
  is refused rather than seeded with zero.

### Fixed
- A row growing off its own prior value kept its label on the derived account. `D6 = C6 * 1.15`
  says *this* period equals last period times 1.15, so the row's printed values are its
  openings and the formula computes a close. The row's label now stays on the carried series
  and the derived account takes a `Closing` suffix. The old naming was self-consistent,
  evaluated cleanly, threw nothing, and reported every figure one period early.
- Carries were seeded from the *referenced* cell rather than from the defining row's own first
  period. For a self-carry these are the same cell; for `D4 = C7` — opening debt follows last
  period's closing debt — they are not, and the referenced cell is a formula that in period one
  has no prior period to compute from. Year-one interest on a cash-swept revolver read as
  -0.88 before this and 11.75 after.
- Seeding fell back to zero when a cell stated no value, which is a fabricated opening balance.
  It now reports `unseededCarry` and sends the row to residue.
- On a seeded row the rule was read from the first formula cell. Where the seed is a typed
  number that cell is already the second period, which is why this held; where the seed is
  itself computed, the opening balance's own arithmetic was adopted as the rule for every
  period. Seeded rows now read the rule from after the seed. Uniform rows are unchanged,
  because there the first period may be the cell reaching into the at-close column.

### Measured
- Wharton `ANSWER KEY`, 2026-09-02: 21 accounts, 3 rollforwards, 12 residue, recognition
  coverage 70%. The golden path reproduces Excel's own 1,000,000 / 1,150,000 / 1,322,500, and a
  cash-swept revolver accrues 11.75 in year one where beginning-balance timing gives 12.00. The
  sheet as a whole does not yet materialize: rows 3–11 are two side-by-side assumption tables
  whose value column H is also the 2026 period column, so `Revenue growth` reads as `10%` in
  D11 and `SUM(H9:H10)` in H11 and is refused as non-uniform. See
  `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md`.

## [0.6.0] - 2026-09-01

Reading a real Excel workbook works, and the first two stages of recognition can say what one
means. Both halves of that sentence were untrue at 0.5.0: the reader returned an empty workbook
for any file Excel wrote, and nothing above the importer existed.

### Added
- `ModelImporter.importAllSheets(_:)`: imports every worksheet of a workbook into one
  `ExcelModel`. Node labels are qualified with the sheet name (`Inputs!A1`) and each sheet
  becomes its own section, so sheets sharing a cell reference stay distinct.
  `importWorkbook` and `importSheet` keep their single-sheet behaviour.
- `ImportResult.sheetCellToNode`: one cell-to-node mapping per sheet name. `cellToNode` is
  unchanged for single-sheet callers; for a multi-sheet import it holds the first sheet's
  mapping, since a `CellRef` carries no sheet and cannot honestly hold more.
- `NodeFormula.power(_:_:)`: exponentiation as a first-class case rather than
  `POWER(base, exponent)` function dispatch, so `(1+r)^n` survives a round trip as `^` and
  is evaluated directly by `MonteCarloExtension` instead of falling into its
  `case .function: return 0`.

### Fixed
- **The import path reported success while dropping formulas.** `ModelImporter.convertAST`
  never received the warnings array — it was not a parameter — so unsupported AST nodes were
  rewritten to `.text("UNSUPPORTED")` in silence. Warnings fired only for `.date`/`.error`/
  `.array` *cell types*. A workbook could import substantially lossy and report nothing.
  Every degrade now warns, naming the cell and the construct: the unsupported-node
  fallthrough, a reference to a cell not yet imported (which becomes the literal text
  `REF:A5`), and exceeding the 500-deep nesting guard.
- `.cellRange` imported as `UNSUPPORTED`. Real financial workbooks are `SUM(D5:D16)`,
  `NPV(rate, D5:D16)`, `IRR(D4:D16)`; nothing meaningful imported without it. Ranges now
  become `NodeFormula.range`. Both endpoints must resolve, because the exported `CellRange`
  is re-derived from them and an unresolvable endpoint would silently export a narrower
  range than the source had; that case warns and degrades. Interior cells that do not
  resolve are skipped silently — a blank separator row inside a summed range is ordinary
  Excel, and only the endpoints determine the exported range.
- `.power` imported as `UNSUPPORTED`. `(1+r)^n` appears in every discounting formula.
- Array-formula cells shared the generic "Unsupported cell type" message with `.date` and
  `.error`. Array formulas are how Excel stores data tables (`{=TABLE(r,c)}`) and are the
  detection signal for sensitivity-table recognition; each of the three now says what it
  actually found. Recognition itself is not attempted — an array cell still produces no node.

### Changed
- **`ImportResult.warnings` is now non-empty for workbooks that previously reported none.**
  This is the fix, not a regression: those workbooks were always importing lossy, and the
  silence was the defect. Tests asserting `warnings.isEmpty` on a workbook using ranges,
  exponentiation, or cross-sheet references need updating.
- **`ModelImporter` no longer emits the `"UNSUPPORTED"` sentinel for cell ranges or
  exponentiation**, which now translate. It remains for `sheetRef`, `namedRange`, `error`,
  `concatenate`, and the comparison operators.
- **`NodeFormula` gained a case, so exhaustive switches over it must add `.power`.** All
  five in-tree switches are updated: `resolve(using:)`, `ModelImporter.convertAST`,
  `MonteCarloExtension.evaluateFormula`, `MultiSheetExporter`'s cross-sheet resolution, and
  `FormulaMapper.collectFunctions`.

### Fixed
- Dependency resolution: SwiftPM's trust-on-first-use fingerprint record for BusinessMath
  2.2.1 still named revision `3af9184`, but the upstream `v2.2.1` tag had been moved forward
  one docs-only commit to `be8d9fd`. Every `swift build` failed at resolution with a revision
  mismatch that `Package.resolved` alone could not explain or fix. Pin and fingerprint both
  corrected; `3af9184` is an ancestor of `be8d9fd`, so no compiled code changed.
- `.quality-gate.yml` declared `checkers:` and `exclude:`. Neither key is in the gate's schema,
  so the decoder discarded both and the file was never evidence of what the gate ran. Removed;
  checker selection now honestly falls to the gate's default set.
- Force unwraps eliminated across the test suite (121 sites) in favour of `try XCTUnwrap`,
  which reports the unwrap site instead of trapping the whole run.
- File-existence assertions moved from `FileManager.fileExists(atPath:)` to
  `URL.checkResourceIsReachable()`, dropping string-path handling entirely.
- Unguarded floating-point division in `project/plans/completed/SignalLayer-Playground.swift`
  routed through a guarded `divide(_:by:)`. Script output is byte-identical.

### Added
- ReadmeExampleTests: compiles and runs the code samples printed in `README.md`, which nothing
  else compiles, and pins the exact formula the README claims the example produces.
- DocC catalogue at `Sources/BusinessMathExcel/BusinessMathExcel.docc` with a landing page
  covering the DAG model, layout-at-export-time, and the import path. Declared as a target
  resource rather than excluded, so the plugin still builds it.

### Changed
- **SwiftXLSX pinned to 0.7.0**, for the shared-formula fix released there. Excel stores a
  repeated formula once on its group's master cell and leaves the other members' `<f>` elements
  empty; every version before 0.7.0 read those cells as the constant Excel had cached in them.
  On the Wharton `ANSWER KEY` that was **81 of 155 formula cells** arriving as `.number` inputs.

  **Every import-fidelity figure recorded before this bump undercounts its denominator.** The
  corrected measurement for that sheet: **155 formula cells, 139 translated cleanly, 16 degraded,
  12 warnings.** The previously recorded "65 of 74 clean" was counting less than half the
  formulas on the sheet, because the rest were invisible.
- **SwiftXLSX pinned to 0.6.0**, up from 0.2.0, for the reader fix released there: every
  version before it selected the workbook part by substring match, which also matched the
  extended-properties relationship Excel writes first, so *any* Excel-authored file parsed
  to zero sheets and returned no error. This package's import half had therefore never been
  exercised against a real spreadsheet. No API drift across the four minor versions; the
  suite passes unchanged.

### Added
- **`Recognition/` — Stages 1–2 of the Excel→ModelDefinition recognizer.** `SheetGrid` (topology
  and period-axis detection), `PeriodAxis` (headings to BusinessMath `Period` values, annual
  only), `LabeledSeries` (labels bound by the axis rather than by adjacency), `FormulaUniformity`
  (R1C1 shape comparison honouring `$`), plus `Coverage` and `Diagnostic`.

  Measured on the Wharton LBO Practice Model `ANSWER KEY`: 6 annual periods, 279 populated cells,
  196 recognized (70%), 36 series bound — 26 uniform, 3 seeded rollforward, 7 non-uniform.
  Coverage is reported, never asserted: it is a progress metric toward 100%, and a build that
  failed on it would invite recognizing things badly to move the number.
- `ImportResult.cachedValues` and `ImportResult.formulaASTs` preserve what the file recorded —
  Excel's last computed result for each formula cell, and each formula's AST with its `$` markers
  intact. Recognition needs the first to read a computed header row and the second to tell a
  filled formula from a hand-edited one. Neither is ever substituted for a formula that could not
  be translated; they are evidence about the sheet, not values in a model.
- **Comparison operators in `NodeFormula`** — `.equal`, `.notEqual`, `.greaterThan`, `.lessThan`,
  `.greaterOrEqual`, `.lessOrEqual`. All six previously degraded to `UNSUPPORTED`, which took the
  condition out of every `IF` in a workbook. `IF` itself needed nothing: Excel's `IF` is a
  function, not an AST node, so it already round-tripped.

  **Source-breaking for exhaustive switches over `NodeFormula`.** The five in this package are
  updated. Pulled forward from decision D8 — see the recognizer proposal §15 Q0.
- `ExcelModel.add(_:kind:section:)`: adds a node under a caller-supplied `NodeRef`. The
  other `add` methods mint an identity and store the node in one step, which cannot express
  a graph whose formulas reference nodes that do not exist yet. Minting identities first and
  adding fully-resolved nodes second keeps the model built once rather than mutated, which is
  what makes it safe to treat as immutable after construction.
- `WhartonImportMeasurementTests`: measures import fidelity against the Wharton LBO
  Practice Model, a workbook Excel actually wrote, rather than one `ModelExporter` produced.
  The fixture is not checked in — see `Tests/Fixtures/README.md` — and the tests skip when
  it is absent.

### Fixed
- `MonteCarloExtension` evaluated `TRUE` as `0` — the same value it returns for "cannot
  evaluate" — so a true condition could not be told apart from an unsupported one. Booleans and
  comparisons now evaluate to 1 and 0, matching how Excel treats them in arithmetic.
- **Forward references were lost.** `ModelImporter` resolved formulas in a single pass, so a
  reference to a cell it had not reached yet degraded to the literal text `REF:A5`. A total
  placed above the figures it sums — ordinary in any model with a summary block at the top —
  did not import. Resolution is now two-pass: every cell's identity is minted first, then
  formulas are converted against the complete map, so references resolve in either direction.
- **Absolute references never resolved.** `CellRef` is `Hashable` over its `$` marker flags,
  so `$D$11`, `$D11`, `D$11`, and `D11` were four distinct dictionary keys for one cell. The
  markers control what happens when a formula is filled, not which cell it points at, and
  absolute references are how every financial model pins a rate — so keying on the raw
  reference lost precisely the references that matter most. Cell identity now discards them.

### Changed
- **BusinessMath pinned to 2.7.0**, up from 2.2.1. 2.7.0 is where `ModelDefinition`, `Period`,
  `PeriodType`, and the cycle solvers live; 2.2.1 shipped no `Model Definition/` at all, so the
  recognizer work has no target without this. No source changes were needed and the suite passes
  unchanged across the bump. New transitive dependencies come with it — SwiftDeterminism 1.1.0,
  swift-crypto 3.15.1, swift-asn1 1.7.2 — so BusinessMath is no longer Foundation-only.
- Transitive dependencies floated with the re-resolve: swift-collections 1.5.1 -> 1.6.0,
  SwiftZIP 0.5.0 -> 0.6.0.

## [0.5.0] - 2026-06-06

### Added
- CompactLayoutStrategy: vertical layout with no blank separator rows between sections, table-aware
- MultiSheetLayoutStrategy: assigns each section to its own worksheet with configurable per-sheet layout
- MultiSheetExporter: exports ExcelModel to multi-sheet Workbook with automatic cross-sheet formula resolution
- SheetCell: sheet-qualified cell reference type for cross-sheet mapping
- MultiSheetAssignment: per-sheet CellAssignment collection with global node-to-sheet+cell mapping
- Cross-sheet formula resolution: formulas referencing nodes on other sheets automatically produce `'SheetName'!A1` references
- SheetGroup: named groups of sections that share a worksheet, for flexible multi-sheet layouts
- MultiSheetLayoutStrategy now supports `groups` parameter to place multiple sections on the same sheet
- VerticalLayoutStrategy: opt-in `tableAware` parameter for table-aware grid rendering (defaults to false)
- 54 new tests across 4 new test files + 17 added to existing test files

## [0.4.0] - 2026-06-04

### Added
- HorizontalLayoutStrategy: sections arranged side-by-side with configurable start column, gap, and start row
- DashboardLayoutStrategy: N-column grid of sections with band wrapping and configurable column count, gaps
- Table-aware layout rendering: strategies detect registered TableRef and render as grids with column headers
- CellAssignment.tableColumnHeaders: optional field for table column header positions (backward-compatible)
- ExcelModel.allTables: public accessor for all registered tables
- ModelExporter now writes table column headers when present in CellAssignment
- 53 new tests across 4 test files (LayoutFoundationTests, HorizontalLayoutStrategyTests, DashboardLayoutStrategyTests, TableAwareLayoutTests)

### Changed
- ModelExporter.writeNodes now writes values for nodes without label mappings (supports table body nodes)

## [0.3.0] - 2026-06-02

### Deprecated
- AmortizationTranslator: use AmortizationModelBuilder with ModelExporter for live formulas
- SensitivityTranslator: use ExcelModel with ModelExporter for live formulas
- SimulationTranslator: use MonteCarloExtension with ModelExporter for live formulas
- TornadoTranslator: use ExcelModel with ModelExporter for live formulas

### Added
- NodeRef: UUID-based stable node identity decoupled from cell positions
- NodeFormula: recursive formula enum referencing NodeRefs, with resolve-to-FormulaAST
- ExcelModel: DAG container with section grouping, node lookup, and table registration
- ResolutionError: typed errors for formula resolution failures
- Convenience builders for SUM, PMT, IPMT, PPMT, NPV, IRR formulas
- 43 new tests across 3 test files (NodeRefTests, NodeFormulaTests, ExcelModelTests)
- LayoutStrategy protocol and CellAssignment result type for pluggable cell positioning
- VerticalLayoutStrategy: default layout with 2-column gutter, labels in C, values in D
- ModelExporter: converts ExcelModel DAG to SwiftXLSX Workbook with live formulas
- 26 new tests across 2 test files (VerticalLayoutStrategyTests, ModelExporterTests)
- AmortizationModelBuilder: constructs ExcelModel DAG with PMT/IPMT/PPMT formulas from loan parameters
- DCFModelBuilder: constructs ExcelModel DAG with NPV/IRR formulas from cash flows
- 30 new tests across 2 test files (AmortizationModelBuilderTests, DCFModelBuilderTests)
- Distribution enum: normal, uniform, triangular, lognormal sampling with deterministic seed support
- MonteCarloExtension: runs N-iteration simulation, writes Data + Summary sheets with PERCENTILE/AVERAGE/STDEV formulas
- 15 new tests across 2 test files (MonteCarloExtensionTests, DistributionTests)
- ModelImporter: converts SwiftXLSX Workbook cells into ExcelModel graph with NodeFormula references
- FormulaMapper: categorizes imported formulas into financial (PMT, NPV, IRR) and statistical (SUM, AVERAGE, STDEV) groups
- Added `cellReferences` public property to SwiftXLSX Worksheet for import iteration
- 25 new tests across 2 test files (ModelImporterTests, FormulaMapperTests)

## [0.2.0] - 2026-06-02

### Changed
- Updated swift-tools-version from 5.9 to 6.2
- Switched SwiftXLSX dependency from GitHub v0.1.0 to local path (v0.5.0+)
- Translators now use live Excel formulas (SUM, AVERAGE, PERCENTILE, etc.) instead of pre-computed values
- Added swift-docc-plugin dependency for documentation generation

### Removed
- Package.resolved (not needed with local path dependencies)

## [0.1.0] - 2026-05-21

### Added
- AmortizationTranslator: converts AmortizationSchedule to Excel workbook
- SensitivityTranslator: converts ScenarioSensitivityAnalysis to Excel workbook
- SimulationTranslator: converts SimulationResults to Excel workbook with Summary + Data sheets
- TornadoTranslator: converts TornadoDiagramAnalysis to Excel workbook
- 30 tests across 5 test files
