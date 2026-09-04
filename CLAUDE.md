# BusinessMathExcel — Bidirectional Excel Translation Layer

Translates between BusinessMath computational models and Excel workbooks with live formulas. Pure Swift, Foundation only.

## Session Start

Read documents in this order for full context recovery:
1. `project/master_plan.md` — Vision and priorities
2. `development-guidelines/rules/coding_rules.md` — Forbidden patterns, safety rules
3. `development-guidelines/rules/test_driven_development.md` — Testing contract
4. `project/checklists/CURRENT_*.md` — Active tasks (if any)
5. Latest file in `project/summaries/` — Where we left off (if any)

## Development Workflow

```
0. DESIGN   -> Propose architecture (design_proposal.md)
1. RED      -> Write failing tests first
2. GREEN    -> Minimum code to pass
3. REFACTOR -> Clean up, keep tests green
4. DOCUMENT -> DocC comments and examples
5. VERIFY   -> swift build + swift test (zero warnings/errors)
```

## Key Rules

- No force unwraps (`!`), no `try!`, no force casts (`as!`)
- Guard clauses for all validation; early returns over nested ifs
- Division safety: always check for zero before dividing
- Swift 6 strict concurrency compliance (all types Sendable)
- All public APIs require DocC documentation

## Architecture

```
Single-sheet: ExcelModel (DAG) -> LayoutStrategy -> ModelExporter -> SwiftXLSX Workbook -> .xlsx
Multi-sheet:  ExcelModel (DAG) -> MultiSheetLayoutStrategy -> MultiSheetExporter -> SwiftXLSX Workbook -> .xlsx
Import:       .xlsx -> SwiftXLSX Workbook -> ModelImporter -> ExcelModel (DAG) -> FormulaMapper -> BusinessMath
```

- `ExcelModel` is a DAG of InputNode/FormulaNode/OutputNode, connected by `NodeRef` identities
- Cell positions (A1, B2) are assigned at export time by `LayoutStrategy`, not hardcoded in the model
- Single-sheet strategies (all conform to `LayoutStrategy` protocol):
  - `VerticalLayoutStrategy` (default) — sections stacked with blank separator rows, opt-in table awareness
  - `CompactLayoutStrategy` — vertical, no separators, table-aware
  - `HorizontalLayoutStrategy` — sections side-by-side, table-aware
  - `DashboardLayoutStrategy` — N-column grid with band wrapping, table-aware
- Multi-sheet: `MultiSheetLayoutStrategy` assigns each section to its own worksheet (or groups sections via `SheetGroup`); `MultiSheetExporter` writes with automatic cross-sheet formula resolution
- Compact, Horizontal, and Dashboard strategies are table-aware: they detect registered `TableRef` and render grids with column headers
- `NodeFormula` references other nodes by `NodeRef`, resolved to `FormulaAST` at export
- Builders (AmortizationModelBuilder, DCFModelBuilder) auto-construct models from BusinessMath types
- Extensions (MonteCarloExtension) attach simulation to any model

## Dependencies

- `SwiftXLSX` — bidirectional .xlsx read/write with FormulaAST. Pinned `exact: "0.12.0"` to
  `github.com/jpurnell/SwiftXLSX`. From 0.12.0 it depends on `SwiftExcelCore`, which holds the
  spreadsheet vocabulary — `CellValue`, `CellRef`, `FormulaAST`, `ExcelError`,
  `CellValueProvider`. SwiftXLSX re-exports it, so `import SwiftXLSX` still sees those types and
  nothing here needed changing.
- `BusinessMath` — financial/statistical computation. Pinned `exact: "2.9.0"` to
  `github.com/jpurnell/BusinessMath`. 2.7.0 first supplied `ModelDefinition`, `Period`,
  `PeriodType` and the cycle solvers the recognizer targets; 2.8.0 added the function registry
  and `PeriodDriver`; 2.9.0 adds the typed layer — `ModelUnit`, `LineItem<U>`, `Expr<U>`,
  `validateUnits()` — which is what `TypedSourceWriter` emits against.
- `SwiftXLSX` is Foundation-only. `BusinessMath` is not: from 2.7.0 it pulls
  swift-numerics, swift-collections, SwiftDeterminism, swift-crypto, and swift-asn1.
- Local working copies live at `../../../SwiftXLSX` (i.e. `Development/Swift/SwiftXLSX`, not a
  sibling of this repo) and `../BusinessMath`, but the build resolves
  the pinned tags from GitHub — editing a sibling checkout does **not** affect this build.
- If resolution fails with "does not match previously recorded value", an upstream tag has
  been moved. `Package.resolved` is not the only record: SwiftPM also keeps a trust-on-first-use
  fingerprint per version at `~/.swiftpm/security/fingerprints/<package>-<hash>.json`, and it
  must be corrected too or every resolve keeps failing.

## Releases

- Tags are **`vX.Y.Z`**, matching BusinessMath and `development-guidelines/rules/release_checklist.md`.
  This repo's own `0.5.0` tag predates the convention and has not been retagged.
- Dependency pins in `Package.swift` stay unprefixed (`exact: "0.7.0"`) — SwiftPM strips a leading
  `v` when matching a tag to a version, so the pin is unaffected by the tag's form.
- SwiftXLSX was retagged to `vX.Y.Z` on 2026-09-01 with revisions unchanged, so no pin, lockfile,
  or fingerprint record needed correcting.

## Quality Gate

`quality-gate` — zero errors, zero warnings, no overrides. `swift build && swift test` is the
subset the gate runs first; passing it is necessary, not sufficient. A build failure stops the
run, so a green-looking report with `1 of 45 checkers` means 44 checkers never ran and found
nothing because they were never asked. Use `--continue-on-failure` to see the whole picture.

## References

- Full guidelines: `development-guidelines/README.md`
- Coding rules: `development-guidelines/rules/coding_rules.md`
- TDD contract: `development-guidelines/rules/test_driven_development.md`
- SwiftXLSX source: `../../../SwiftXLSX/`
- BusinessMath source: `../BusinessMath/`
