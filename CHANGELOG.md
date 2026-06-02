# Changelog

All notable changes to BusinessMathExcel will be documented in this file.

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
