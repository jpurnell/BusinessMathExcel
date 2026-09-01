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

**Key types:** `SheetGrid`, `PeriodAxis`, `LabeledSeries`, `FormulaUniformity`, `PeriodHeader`, `Coverage`, `Diagnostic`, `DiagnosticCode`, `RecognizerOptions`
**Interfaces:** `SheetGrid.build(from:options:)`, `PeriodAxis.build(from:options:)`, `LabeledSeries.bind(in:axis:)`, `FormulaUniformity.assess(_:in:)`
**Applications:** Working out what a spreadsheet *means* rather than what it contains — where its timeline runs, which label owns which row, and whether a row computes the same way in every period
**Dependencies:** BusinessMath (`Period`, `PeriodType`)

Stages 1–2 of the Excel→`ModelDefinition` recognizer. Interpretive, and deliberately separate from
`Import/`, which never interprets. Reports ambiguity rather than resolving it: a sheet readable
both ways yields no orientation, and a row that disagrees with itself yields no shape. Coverage is
reported as a progress metric and never gates a build.

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
