# Changelog

All notable changes to BusinessMathExcel will be documented in this file.

## [Unreleased]

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
