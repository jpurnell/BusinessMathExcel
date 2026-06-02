# Changelog

All notable changes to BusinessMathExcel will be documented in this file.

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
