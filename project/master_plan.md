# BusinessMathExcel Master Plan

**Purpose:** Source of truth for project vision, architecture, and goals.

---

## Project Overview

### Mission
Provide a bidirectional translation layer between BusinessMath computational models
and Excel workbooks with live, interactive formulas. Models are constructed as
computational graphs (DAGs) that export to .xlsx with cell-referenced formulas,
and import back from .xlsx into graph form.

### Target Users
- **BusinessMath consumers** who need Excel output for financial models, reports, and analysis
- **Swift developers** who need to generate Excel files with live formulas from any Swift application
- **MCP server operators** who want to return downloadable Excel workbooks from tool calls

### Key Differentiators
- **Computational graph architecture** — models are DAGs of NodeRef/NodeFormula, cell positions assigned at export
- **Live Excel formulas** — exported workbooks recalculate when inputs change (PMT, NPV, IRR, SUM, etc.)
- **Bidirectional** — import .xlsx back into graph form, categorize formulas by type
- **Pure Swift, Foundation only** — no external dependencies beyond BusinessMath + SwiftXLSX
- **Open XML compliant** — produces files that open in Excel, Numbers, Google Sheets, LibreOffice

---

## Architecture

### The Pipeline

```
Export: ExcelModel (DAG) -> LayoutStrategy -> ModelExporter -> SwiftXLSX Workbook -> .xlsx
Import: .xlsx -> SwiftXLSX Workbook -> ModelImporter -> ExcelModel (DAG) -> FormulaMapper -> BusinessMath
```

### Core Types

| Type | Responsibility |
|------|---------------|
| `NodeRef` | UUID-based stable node identity, decoupled from cell positions |
| `NodeFormula` | Recursive enum referencing NodeRefs; resolves to FormulaAST at export |
| `ExcelModel` | DAG container with sections, node lookup, table registration |
| `LayoutStrategy` | Protocol for pluggable cell positioning (labels, values, sections) |
| `VerticalLayoutStrategy` | Default layout: 2-col gutter, labels in C, values in D, opt-in table awareness |
| `CompactLayoutStrategy` | Vertical layout, no separators between sections, table-aware |
| `HorizontalLayoutStrategy` | Sections side-by-side, table-aware grid rendering |
| `DashboardLayoutStrategy` | N-column grid of sections with band wrapping, table-aware |
| `SheetGroup` | Named group of sections that share a worksheet |
| `MultiSheetLayoutStrategy` | Each section on its own worksheet or grouped via SheetGroup, configurable per-sheet layout |
| `SheetCell` | Sheet-qualified cell reference for cross-sheet formula resolution |
| `MultiSheetAssignment` | Per-sheet CellAssignment collection with global node mapping |
| `ModelExporter` | Converts ExcelModel to single-sheet SwiftXLSX Workbook with resolved formulas |
| `MultiSheetExporter` | Converts ExcelModel to multi-sheet Workbook with cross-sheet formula resolution |
| `ModelImporter` | Converts SwiftXLSX Workbook cells into ExcelModel graph |
| `FormulaMapper` | Categorizes imported formulas into financial/statistical groups |

### Builders (auto-construct models from BusinessMath types)

| Builder | Input | Output |
|---------|-------|--------|
| `AmortizationModelBuilder` | Principal, rate, term | ExcelModel with PMT/IPMT/PPMT table |
| `DCFModelBuilder` | Discount rate, cash flows | ExcelModel with NPV/IRR formulas |

### Extensions

| Extension | Purpose |
|-----------|---------|
| `MonteCarloExtension` | N-iteration simulation with Distribution types, adds Data + Summary sheets |

### Legacy Translators (deprecated)

| Translator | Replacement |
|------------|-------------|
| `AmortizationTranslator` | `AmortizationModelBuilder` + `ModelExporter` |
| `SensitivityTranslator` | `ExcelModel` + `ModelExporter` |
| `SimulationTranslator` | `MonteCarloExtension` + `ModelExporter` |
| `TornadoTranslator` | `ExcelModel` + `ModelExporter` |

---

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.2 (strict concurrency) |
| Platform | macOS 14+, iOS 17+ |
| Dependencies | SwiftXLSX 0.2.0, BusinessMath 2.2.1 — both pinned `exact:` to their GitHub URLs |
| Testing | XCTest, 271 tests across 24 files |

### Module Status

- [x] BusinessMathExcel — 136 public APIs, 100% documented, 271 tests

### Project Structure

```
BusinessMathExcel/
├── Package.swift
├── CLAUDE.md
├── CHANGELOG.md
├── .claude/
├── Sources/BusinessMathExcel/
│   ├── Model/
│   │   ├── NodeRef.swift
│   │   ├── NodeFormula.swift
│   │   ├── ExcelModel.swift
│   │   └── ResolutionError.swift
│   ├── Export/
│   │   ├── LayoutStrategy.swift
│   │   ├── VerticalLayoutStrategy.swift
│   │   ├── CompactLayoutStrategy.swift
│   │   ├── HorizontalLayoutStrategy.swift
│   │   ├── DashboardLayoutStrategy.swift
│   │   ├── ModelExporter.swift
│   │   ├── MultiSheetAssignment.swift
│   │   ├── MultiSheetLayoutStrategy.swift
│   │   └── MultiSheetExporter.swift
│   ├── Builders/
│   │   ├── AmortizationModelBuilder.swift
│   │   └── DCFModelBuilder.swift
│   ├── Import/
│   │   ├── ModelImporter.swift
│   │   └── FormulaMapper.swift
│   ├── Extensions/
│   │   ├── Distribution.swift
│   │   └── MonteCarloExtension.swift
│   ├── BusinessMathExcel.docc/
│   │   └── BusinessMathExcel.md          (landing page)
│   ├── AmortizationTranslator.swift      (deprecated)
│   ├── SensitivityTranslator.swift       (deprecated)
│   ├── SimulationTranslator.swift        (deprecated)
│   └── TornadoTranslator.swift           (deprecated)
├── Tests/BusinessMathExcelTests/
│   └── (24 test files, 271 tests)
└── development-guidelines/               (gitignored)
```

---

## Completed Phases

### v0.1.0 — Legacy Translators
- [x] AmortizationTranslator, SensitivityTranslator, SimulationTranslator, TornadoTranslator
- [x] Pre-computed values written to Excel (no live formulas)

### v0.2.0 — Package Modernization
- [x] Swift 6.2, local SwiftXLSX dependency, live formula strings

### v0.3.0 — Computational Graph Architecture
- [x] Phase 1: Core types (NodeRef, NodeFormula, ExcelModel, ResolutionError)
- [x] Phase 2: Export pipeline (LayoutStrategy, VerticalLayoutStrategy, ModelExporter)
- [x] Phase 3: Builders (AmortizationModelBuilder, DCFModelBuilder)
- [x] Phase 4: Import pipeline (ModelImporter, FormulaMapper)
- [x] Phase 5: Monte Carlo extension (Distribution, MonteCarloExtension)
- [x] Phase 6: Legacy deprecation (all 4 translators deprecated)

### v0.4.0 — Custom Layout Strategies
- [x] HorizontalLayoutStrategy: sections side-by-side
- [x] DashboardLayoutStrategy: N-column grid with band wrapping
- [x] Table-aware rendering: CellAssignment.tableColumnHeaders, ExcelModel.allTables
- [x] ModelExporter table header writing

### v0.5.0 — Compact and Multi-Sheet Layout
- [x] CompactLayoutStrategy: vertical, no separators, table-aware
- [x] MultiSheetLayoutStrategy: each section on its own worksheet
- [x] MultiSheetExporter: multi-sheet export with cross-sheet formula resolution
- [x] SheetCell + MultiSheetAssignment: cross-sheet data types


### Unreleased — Dependency Pin and a Zero-Warning Gate
- [x] BusinessMath 2.2.1 pin repaired after the upstream tag moved; SwiftPM's fingerprint
      record was the actual blocker, not `Package.resolved`
- [x] `.quality-gate.yml` reduced to keys the schema defines — `checkers:`/`exclude:` were
      fiction the decoder discarded, so the file never described what ran
- [x] DocC catalogue added; `doc-lint` and `doc-code` now have something to examine
- [x] 121 test force unwraps replaced with `try XCTUnwrap`; zero force unwraps in the repo
- [x] Full gate green: 40 of 45 checkers, 0 errors, 0 warnings, no overrides

---

## Future Work

- SensitivityModelBuilder — varies one input across a range, records output
- TornadoModelBuilder — ranked sensitivity analysis with live formulas
- Cross-sheet formula references in MonteCarloExtension
- Additional Distribution types (beta, Poisson)
- Summary sheet generation — auto-generated sheet referencing key outputs from other sheets

---

## References

| Resource | Location |
|----------|----------|
| SwiftXLSX source | `../SwiftXLSX/` (local working copy; the build resolves the pinned tag) |
| BusinessMath source | `../BusinessMath/` (local working copy; the build resolves the pinned tag) |
| CHANGELOG | `./CHANGELOG.md` |

---

**Last Updated:** 2026-08-26 — reconciled dependency form (remote pinned, not local paths), test counts (271, not 274/257), the source tree (DocC catalogue), and recorded the unreleased gate work.
