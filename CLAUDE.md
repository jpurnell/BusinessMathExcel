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

- `SwiftXLSX` — bidirectional .xlsx read/write with FormulaAST. Pinned `.upToNextMinor(from: "0.23.0")` to
  `github.com/jpurnell/SwiftXLSX`. From 0.12.0 it depends on `SwiftExcelCore`, which holds the
  spreadsheet vocabulary — `CellValue`, `CellRef`, `FormulaAST`, `ExcelError`,
  `CellValueProvider`. SwiftXLSX re-exports it, so `import SwiftXLSX` still sees those types and
  nothing here needed changing.
- `BusinessMath` — financial/statistical computation. Pinned `exact: "2.15.0"` to
  `github.com/jpurnell/BusinessMath`. **That `exact:` is now a scheduled build failure — see
  "The pin that is about to break" below.** 2.7.0 first supplied `ModelDefinition`, `Period`,
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

## Why the pins are loose

Intra-family pins are **not** `exact:`, and that is deliberate.

`SwiftExcelCore` is `from:` wherever it appears. It is the shared vocabulary, so SwiftPM must
unify the family on a single version — two SwiftExcelCore versions would mean two `CellValue`
types and nothing would typecheck. `from:` enforces that *better* than `exact:`: it resolves to
the highest version satisfying every consumer, where `exact:` simply refuses. Two `exact:` pins
on one shared package deadlock the moment they differ, which is what stopped this repo resolving
after `DependencyGraph` moved to Core.

`SwiftXLSX` and `SwiftExcelFunctions` are `.upToNextMinor(from:)` rather than `from:`, because
the family ships breaking changes in *minor* versions while it is pre-1.0. A patch should flow
freely; a minor should be a deliberate bump.

Every justification originally recorded for the `exact:` pins was a lower bound — "anything
earlier would import a second `FormulaEvaluator`" — so the pins were always stricter than the
reasoning behind them.

## The SwiftExcel family

This repo is one of four packages, and the other three are where the spreadsheet work now lives:

```
SwiftExcelCore  ←  SwiftXLSX            syntax and storage
       ↑        ←  SwiftExcelFunctions  semantics  →  BusinessMath
                        ↑
                BusinessMathExcel        model translation  (this repo)
```

- **SwiftExcelCore** (`../../../SwiftExcelCore`) — the vocabulary: `CellValue`, `CellRef`,
  `FormulaAST`, `ExcelError`, `CellValueProvider`, `CellMatrix`.
- **SwiftExcelFunctions** (`../../../SwiftExcelFunctions`) — the function library and evaluator.
  163 functions; 99.62% agreement with Excel's own cached values over 155,897 corpus cells.

**This repo now depends on SwiftExcelFunctions**, at `.upToNextMinor(from: "0.7.1")`. The
sentence here previously said it did not, which was true when written and is the kind of claim
worth re-reading rather than trusting.

## The pin that broke, and how it was fixed

**Resolved 2026-09-12.** Kept as a worked example rather than deleted, because the prediction was
right, the ordering it identified was right, and the reasoning is worth reusing.

It was recorded on 2026-09-10 as a *scheduled* failure: this repo pinned BusinessMath
`exact: "2.15.0"` while SwiftExcelFunctions' `main` had moved to
`.upToNextMinor(from: "3.0.0-alpha.3")`, and `exact:` cannot satisfy `>= 3.0.0-alpha.3`. It
resolved only because it pinned SwiftExcelFunctions **v0.7.1**, whose manifest still asked for
`from: "2.11.0"`. The break was due at the next upstream bump, and it arrived exactly there.

It also recorded that **the fix was ordered and this half could not go first** — loosening this
repo's pin alone does not resolve, because v0.7.1 itself requires BusinessMath `< 3.0.0`. That
held too: both pins had to move together, after the upstream release existed.

Current state, all three moved in one commit:

| | pinned at |
|---|---|
| BusinessMath | `.upToNextMinor(from: "3.0.0-alpha.4")` |
| SwiftXLSX | `.upToNextMinor(from: "0.25.0")` |
| SwiftExcelFunctions | `.upToNextMinor(from: "0.9.3")` |

**572 tests pass against BusinessMath 3.0.0-alpha.4.** The runbook said to budget for the 3.0.0
breaking changes — `sampleSize` removed among them — and they cost nothing here. Worth recording:
the expensive-looking half of that migration was free, and the cheap-looking half (SwiftPM
version identity) was where all the difficulty actually was.

### The lesson that generalises

Not "avoid `exact:`" — the "Why the pins are loose" section below already said that, and saying
it again would not have helped. The lesson is that **the reasoning was applied to SwiftExcelCore
and never carried one dependency over to BusinessMath.** A rule written about one shared package
does not propagate itself to the next one; someone has to go and look.

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
