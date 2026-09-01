# Changelog

All notable changes to BusinessMathExcel will be documented in this file.

## [Unreleased]

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
