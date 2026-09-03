# BusinessMathExcel Capability Map

**Purpose:** Scannable inventory of what this project can do — feature areas, key types, external interfaces, and application domains.

**Last reviewed:** 2026-09-01 (reviewed for v0.6.0)

> **Format reference:** See `development-guidelines/rules/capability_map.md` for field definitions,
> naming conventions, and maintenance rules.

---

## Computational Model

**Key types:** `ExcelModel`, `NodeRef`, `NodeKind`, `NodeFormula`, `ModelSection`, `TableRef`, `ResolutionError`
**Interfaces:** `addInput(label:value:section:)`, `addFormula(label:formula:section:)`, `addOutput(label:formula:section:)`, `add(_:kind:section:)`, `registerTable(label:columns:rows:)`
**Applications:** Describing a spreadsheet's logic as a graph before deciding where anything sits on a page, so the same model can be laid out several ways

Cell positions are assigned at export, never stored in the model. `NodeRef` identity is UUID-based
and independent of labels, which is what lets an importer mint identities before it has resolved
the formulas that reference them.

## Layout Strategies

**Key types:** `LayoutStrategy`, `VerticalLayoutStrategy`, `CompactLayoutStrategy`, `HorizontalLayoutStrategy`, `DashboardLayoutStrategy`, `CellAssignment`
**Interfaces:** `LayoutStrategy.assign(_:)`
**Applications:** Rendering one model as a stacked statement, a side-by-side comparison, or an N-column dashboard without rewriting the model

## Multi-Sheet Export

**Key types:** `MultiSheetLayoutStrategy`, `MultiSheetExporter`, `MultiSheetAssignment`, `SheetCell`, `SheetGroup`
**Interfaces:** `MultiSheetExporter.export(_:assignment:title:)`
**Applications:** Splitting a model across worksheets by section or group, with cross-sheet formula references resolved automatically

## Single-Sheet Export

**Key types:** `ModelExporter`
**Interfaces:** `ModelExporter.export(_:title:strategy:)`
**Applications:** Producing a workbook with live formulas — the recipient can change an input and watch results recalculate, rather than receiving baked numbers
**Dependencies:** SwiftXLSX

## Workbook Import

**Key types:** `ModelImporter`, `ModelImporter.ImportResult`, `FormulaMapper`
**Interfaces:** `importWorkbook(_:)`, `importSheet(_:)`, `importAllSheets(_:)`
**Applications:** Recovering a computational graph from an existing spreadsheet, measuring how much of a real workbook can be represented
**Dependencies:** SwiftXLSX

Structural transcription only — it never interprets. Anything it cannot represent is reported in
`ImportResult.warnings` naming the cell and the construct; nothing is dropped silently, and a
formula's cached value is never substituted for a formula that could not be translated.

## Workbook Recognition

**Key types:** `SheetGrid`, `PeriodAxis`, `LabeledSeries`, `ScalarBlock`, `ScalarAssumption`, `DataTableBlock`, `RecognizedSensitivity`, `UnitInference`, `FormulaUniformity`, `LagDecomposition`, `RecognizedModel`, `ExcelRecognizer`, `PeriodHeader`, `Coverage`, `Diagnostic`, `DiagnosticCode`, `RecognizerOptions`
**Interfaces:** `ExcelRecognizer.recognize(_:options:in:)`, `SheetGrid.build(from:options:)`, `PeriodAxis.build(from:options:)`, `LabeledSeries.bind(in:axis:)`, `FormulaUniformity.assess(_:in:)`, `LagDecomposition.decompose(cell:in:axis:)`
**Applications:** Working out what a spreadsheet *means* rather than what it contains — where its timeline runs, which label owns which row, whether a row computes the same way in every period, and which references reach back a period rather than sideways to an assumption
**Dependencies:** BusinessMath (`Period`, `PeriodType`)

Stages 1–4 of the Excel→`ModelDefinition` recognizer. Interpretive, and deliberately separate from
`Import/`, which never interprets. Reports ambiguity rather than resolving it: a sheet readable
both ways yields no orientation, a row that disagrees with itself yields no shape, and a carry
whose opening the sheet never states is refused rather than seeded with zero. Recognition never
throws — it produces a plan, and what it cannot express becomes residue carrying the reason.
Coverage is reported as a progress metric and never gates a build.

`$` is read as the seam between a reference that fills across (last period, a carry) and one that
is pinned (this rate, an assumption); reading it wrong turns an interest rate into a balance that
carries. A row growing off its own prior value keeps its label on the *carried* series, because
that is where the sheet's printed numbers are — the derived account takes a `Closing` suffix.

A sheet is a stack of blocks, not one grid with one timeline. A label owns a value only when no
other text cell stands between them, because real models put small tables side by side and their
value columns land wherever the page was laid out. Outside the axis's own block the anchor column
carries no *at close* meaning and a label with one value is a scalar assumption. A What-If table
speaks for its own cells, which the file declares on the table's master cell. Names come from the
binder rather than being re-derived, so a reference to one of two rows sharing a heading resolves
to the one meant.

A **What-If table** is read rather than only located: two drivers, two value vectors, a grid of
answers, and the formula being measured — which maps to BusinessMath's own
`TwoWayScenarioSensitivityAnalysis`. It sits beside the accounts, not among them, because a grid
of answers is not a rule. Reading it is a different claim from being able to recompute it, and
only the first is made: the measured output on a real sheet is typically an aggregate over the
whole timeline, which a period-local model does not compute.

A number's **unit** comes from how the sheet presents it, because a format is usually the only
statement a workbook makes about meaning. The format establishes the dimension, the label may
sharpen it, and neither invents one; where a proportion could be a rate or a ratio, the claim that
cannot be wrong wins. An account whose cells state nothing carries no unit, reported at `info` —
most cells in a real workbook are formatted `General`, and a file that formats nothing is not
defective.

## Model Materialization

**Key types:** `ModelMaterializer`, `MaterializedModel`, `ResolvableModel`, `MaterializationError`, `TypedSourceWriter`
**Interfaces:** `ModelMaterializer.build(from:)`, `ModelMaterializer.buildResolvable(from:)`, `TypedSourceWriter.swiftSource(for:sheetName:modelName:)`
**Applications:** Turning a recognized plan into a `ModelDefinition` and its rollforwards, ready to run under `PeriodDriver` — including sheets whose accounts depend on each other within a period
**Dependencies:** BusinessMath (`ModelDefinition`, `Rollforward`, `PeriodDriver`, `Period`)

The opposite discipline to recognition. Recognition is best-effort and never throws, so a workbook
that half-fits still yields a readable plan; materialization validates and **throws**, because a
definition built from a plan with a hole in it would run and produce numbers. An unresolved
reference stops the sheet rather than being filled in.

Within-period circularity — interest on an average balance, swept against the cash left after
paying it — is carried through as a cycle and converged by `PeriodDriver`, not broken by timing.
The distinction is measurable: on a 120 draw at 10%, a correct cyclic solve accrues 11.75 where
beginning-balance timing gives 12.00. Both run and both converge.

`buildResolvable(from:)` answers a different question — not *is this model whole* but *how much of
this workbook works*. It removes what cannot resolve and returns it, transitively, so one row that
cannot be stated as a period rule does not hide an income statement that is sound. Still refusal
rather than repair: nothing is filled in, and a duplicate account or unparseable formula throws,
because those are defects in recognition rather than gaps in the sheet.

Measured against the Wharton `ANSWER KEY` on 2026-09-02: the sheet runs and reproduces **125 of
the 125 values Excel cached in it**.

`TypedSourceWriter` emits the plan as Swift a person can read, diff, and have a compiler check. A
definition goes out typed only when every account it reads has a known unit, every operation has
an overload upstream, and the result's unit matches — otherwise it goes out through the string
API, which makes no claim. Emitted source that does not compile is worse than none, so the writer
never guesses at a unit to reach the typed spelling.

## Model Builders

**Key types:** `AmortizationModelBuilder`, `DCFModelBuilder`
**Interfaces:** `AmortizationModelBuilder.build(from:)`, `DCFModelBuilder.build(from:)`
**Applications:** Turning a BusinessMath amortization schedule or DCF into a live workbook without hand-assembling the graph
**Dependencies:** BusinessMath

## Simulation

**Key types:** `MonteCarloExtension`, `Distribution`, `MonteCarloExtension.InputVariation`
**Interfaces:** `MonteCarloExtension.apply(to:model:outputRef:variations:iterations:seed:)`
**Applications:** Attaching Monte Carlo trials to any model and writing the data and summary sheets alongside it

Its evaluator returns zero for `.function` nodes, so a simulation over a model whose output is
`NPV` or `IRR` produces a column of zeros. Known, scheduled behind the upstream function registry,
and recorded here so the limitation is visible from the inventory rather than only in the source.

## Legacy Translators (deprecated 0.3.0)

**Key types:** `AmortizationTranslator`, `SensitivityTranslator`, `SimulationTranslator`, `TornadoTranslator`
**Interfaces:** `translate(_:)` on each
**Applications:** Superseded by the model-and-layout pipeline; retained for source compatibility
