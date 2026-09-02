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
| `ModelImporter` | Converts SwiftXLSX Workbook cells into ExcelModel graph, single-sheet or all sheets; reports every construct it cannot translate |
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
| Testing | XCTest, 293 tests across 24 files |

### Module Status

- [x] BusinessMathExcel — 138 public APIs, 100% documented, 293 tests

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
│   └── (24 test files, 293 tests)
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

### Unreleased — Excel→ModelDefinition Recognizer, Phase 0
- [x] BusinessMath pin bumped 2.2.1 → 2.7.0, which is where `ModelDefinition`, `Period`,
      `PeriodType`, and the cycle solvers live — 2.2.1 had no `Model Definition/` at all
- [x] No `BusinessMathDSL` reference existed in this repo, so that half of the phase was
      already satisfied
- [x] No source changes were needed; 293 tests pass unchanged across the bump

### Unreleased — Excel→ModelDefinition Recognizer, Phase 1
- [x] `ModelImporter.convertAST` reports every formula node it drops; it previously took no
      warnings parameter at all, so a workbook could import substantially lossy in silence
- [x] `.cellRange` translates to `NodeFormula.range` — `SUM(D5:D16)`, `NPV(rate, D5:D16)`,
      `IRR(D4:D16)` are what real financial workbooks are made of
- [x] `NodeFormula.power` added; `(1+r)^n` round-trips as `^` and is evaluated directly rather
      than through `MonteCarloExtension`'s `case .function: return 0`
- [x] Array-formula cells named as such rather than lumped in with `.date`/`.error` — they are
      the detection signal for sensitivity-table recognition in Phase 6
- [x] `ModelImporter.importAllSheets(_:)` imports every worksheet; labels are sheet-qualified
      and `ImportResult.sheetCellToNode` keeps colliding cell references apart

### Unreleased — SwiftXLSX 0.7.0 and the shared-formula correction
- [x] SwiftXLSX bumped 0.6.0 → 0.7.0: shared formulas and What-If data tables were being read as
      their cached constants, so 81 of 155 formula cells on the Wharton `ANSWER KEY` were invisible
- [x] Corrected import fidelity on that sheet: **155 formula cells, 139 clean, 16 degraded,
      12 warnings** — the earlier "65 of 74" measured less than half the formulas
- [x] Phase 6's detection signal corrected in the proposal: data tables are `<f t="dataTable">`
      elements naming their span and drivers, not `.array` cells. Neither reference workbook has
      a single `.array` cell

### Unreleased — Excel→ModelDefinition Recognizer, Phase 2 (complete)
- [x] Comparison operators in `NodeFormula`, pulled forward from D8; `IF` needed nothing,
      being a function rather than an AST node
- [x] `Coverage` and `Diagnostic` — the vocabulary the stages report through
- [x] `SheetGrid`: topology and axis detection, with the rule and its exclusions documented
- [x] `PeriodAxis`: headings to BusinessMath `Period` values; annual only, chosen from the files
- [x] `LabeledSeries`: binding anchored on the axis rather than on adjacency
- [x] `FormulaUniformity`: R1C1 shape comparison honouring `$`, plus a `seededRollforward`
      classification so the commonest expressible structure is not counted as a hand edit
- [x] **Measured on the Wharton `ANSWER KEY`: 6 annual periods, 279 populated cells, 196
      recognized (70%), 36 series bound — 26 uniform, 3 seeded rollforward, 7 non-uniform.**
      Six of the seven are the assumptions-block artifact, leaving one genuine irregularity.
      Coverage is reported, never asserted

### Superseded — Excel→ModelDefinition Recognizer, Phase 2 (scope, as planned)
- [ ] Stages 1–2: `SheetGrid`, `PeriodAxis`, `LabeledSeries`, with address-fallback naming
- [ ] `Coverage` instrumented, plus per-row formula-uniformity reporting
- [ ] `IF` and the comparison operators in `NodeFormula` — **pulled forward** from decision D8,
      which had placed them behind the upstream function-registry gate. They are operators rather
      than registry entries, so they need nothing upstream, and a production credit model measured
      2982 `IF`s across 5011 formulas where Wharton shows one. Representation only: D9 still
      governs what an `IF` *means*, and a timeline-answerable `IF` is still demoted to data.
      See `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` §15 Q0.
### Unreleased — Excel→ModelDefinition Recognizer, Phases 3 and 4 (complete)
- [x] `LagDecomposition`: a period-local formula plus the carries it implies, with `$` read as
      the seam between "fills across" and "pinned"
- [x] `RecognizedModel` / `ExcelRecognizer`: recognition never throws and produces a plan;
      anything it cannot express becomes residue with a reason
- [x] `ModelMaterializer` (the proposal's `ModelBuilder`; that name is taken in core) — the
      opposite discipline: it validates and throws, because a definition with a hole in it
      would run and produce numbers
- [x] **Golden path: the validation trace reproduces Excel's own 1,000,000 / 1,150,000 /
      1,322,500.** A row growing off its own prior value prints its *openings*, so the row's
      label stays on the carried series and the derived account takes a `Closing` suffix.
      Naming them the other way round is self-consistent and reports every figure one period
      early — which is what this test exists to catch, and did
- [x] **Circular sweep: year-one interest 11.75** on a cash-swept revolver — 120 opening, 115
      closing, 117.5 average, 10%. Beginning-balance accrual gives 12.00, so that one number
      separates a correct cyclic solve from a model that broke the circle by timing. The cycle
      is found by `dependencyReport()` and converged by `PeriodDriver`
- [x] Carries seed from the defining row's **own** first period, not from the referenced cell.
      For a self-carry the two agree; for `D4 = C7` they do not, and the referenced cell is a
      formula with no prior period to compute from
- [x] `unseededCarry`: an opening the sheet does not state is refused, not defaulted to zero.
      The zero produced a model that ran, converged, and was wrong in every period
- [x] **Measured 2026-09-02 on the Wharton `ANSWER KEY`: 21 accounts, 3 rollforwards, 12
      residue; recognition coverage unchanged at 70%.** Phases 3 and 4 made recognized cells
      *runnable* rather than recognizing more of them. The sheet does not yet materialize, for
      one identifiable reason: rows 3–11 are two side-by-side assumption tables whose value
      column H is also the 2026 period column, so `Revenue growth` reads as `10%` in D11 and
      `SUM(H9:H10)` in H11 and is refused. This makes **block detection** Phase 5's first item,
      ahead of `UnitInference`

### Unreleased — Excel→ModelDefinition Recognizer, Phase 5a: block detection (complete)
- [x] **Rule 1** — a label owns a value only when no other text cell stands between them. Real
      models put small tables side by side and their value columns land wherever the page was
      laid out, including in the timeline's columns
- [x] **Rule 2** — the axis governs the rows at or below its heading line. Outside that block the
      anchor column carries no at-close meaning, and a label with one value is a **scalar**:
      a literal holds for every period, a formula stays derived
- [x] `ScalarBlock`, `DataTableBlock`; `ambiguousAssumption` and `unresolvedReference` diagnostics
- [x] `SUM` over a cell range — readable because it stays in one column, not because the column
      is a period. A range running *along* the timeline is refused with a reason
- [x] Named ranges, via **SwiftXLSX 0.8.0** — `Circ` was unresolvable, not unsupported: the
      reader parsed `xl/workbook.xml` for defined names and discarded the result twice
- [x] A What-If table speaks for its own cells. Excel declares the span on the master cell; a
      two-way table also occupies the input row above and column left
- [x] A text literal is not an account. `IF(L11=H11,"True",…)` rendered `True` as a bare name,
      which reads as a reference and would bind to a real account spelled that way
- [x] **A reference takes the name the binder gave the cell**, not one re-derived from the
      nearest label. `Equity of PE Firm` resolved row 58's `Debt` to the `Debt` *assumption* in
      row 4 and computed 60% in every period against a sheet saying 0 and then 240.98
- [x] `ModelMaterializer.buildResolvable(from:)` — builds what resolves and returns what it
      dropped. Refusal, not repair
- [x] **Measured 2026-09-02: the `ANSWER KEY` materializes and runs. 125 of 125 values match
      what Excel cached, to 1e-4 relative.** Recognition coverage 72% (202 of 279), 46 accounts,
      residue 3, non-uniform rows 1, `unsupportedFormulaNode` 0
- [x] One account left out and named: `Equity of PE Firm` needs row 58, which holds literals
      until the final year and then a formula — a *terminal event* rather than a period series,
      which a one-rule-per-account model cannot state. IRR 24.67% and MoM 3.01 still reproduce



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
| SwiftXLSX source | `../../../SwiftXLSX/` — i.e. `Development/Swift/SwiftXLSX`, not a sibling of this repo (local working copy; the build resolves the pinned tag) |
| BusinessMath source | `../BusinessMath/` (local working copy; the build resolves the pinned tag) |
| CHANGELOG | `./CHANGELOG.md` |

---

**Last Updated:** 2026-09-02 — recorded recognizer Phases 3 and 4, then Phase 5a (block detection) complete. The measured result: the Wharton `ANSWER KEY` materializes, runs, and reproduces 125 of 125 of the values Excel cached. Recorded the three blockers Phase 5's design did not predict, the SwiftXLSX 0.8.0 release that named ranges needed, and the older naming defect that made one account run and be wrong. Counts refreshed to 448 tests.
