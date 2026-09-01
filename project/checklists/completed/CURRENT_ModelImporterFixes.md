# COMPLETED: ModelImporter Fixes (Recognizer Phase 1)

**Started:** 2026-09-01
**Completed:** 2026-09-01 — commits `c7ea9a9`, `f287818`, `8328f4e`, `175a72a`, `bb1b54c`
**Proposal:** `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` (§2, §7, phasing)
**Summary:** `project/summaries/2026-09-01_excel_to_modeldefinition_pivot.md`
**Depends on:** nothing upstream — fully self-contained
**Unblocks:** Phase 2 coverage + formula-uniformity measurement on the Wharton workbook

All work is in `Sources/BusinessMathExcel/Import/ModelImporter.swift`.
**TDD per project rules: failing test first, then minimum code, then refactor. Commit at each
green state.**

---

## Task 1 — Thread `warnings` through `convertAST` (do this first)

Smallest change, and it makes Tasks 2–4 visible.

`convertAST` does not take the `warnings` array as a parameter at all, so every unsupported AST
node vanishes silently. Warnings currently fire only for `.date`/`.error`/`.array` **cell types**
at `:93`. A workbook can import 60% lossy and report nothing.

- [x] **RED** — test: a workbook whose formula contains an unsupported node produces a non-empty
      `ImportResult.warnings`.
- [x] **GREEN** — add `warnings: inout [String]` to `convertAST`; append on every fallthrough to
      `.text("UNSUPPORTED")`. Include the cell reference and the node kind in the message.
- [x] **REFACTOR** — consider a typed warning rather than `String`; the recognizer will want
      `DiagnosticCode` later. Keep `[String]` if typing it expands scope.
- [x] Commit.

## Task 2 — Support `.cellRange`

`:161-165` collapses `.cellRange` to `.text("UNSUPPORTED")`. Real financial workbooks are
`SUM(D5:D16)`, `NPV(rate, D5:D16)`, `IRR(D4:D16)`. Nothing meaningful imports without this.

- [x] **RED** — test: `=SUM(D5:D16)` imports as a range-bearing `NodeFormula`, not `"UNSUPPORTED"`.
- [x] **GREEN** — map `FormulaAST.cellRange` → `NodeFormula.range([NodeRef])`, resolving each
      cell in the range through `cellToNode`. Cells not yet seen are the interesting case —
      decide and document: warn and degrade, or defer resolution.
- [x] Edge: a range spanning cells that are not all present in `cellToNode`.
- [x] Commit.

## Task 3 — Support `.power`

Same line. `(1+r)^n` appears in every discounting formula.

- [x] **RED** — test: `=(1+B2)^B3` imports without `"UNSUPPORTED"`.
- [x] **GREEN** — `NodeFormula` has no `.power` case. Either add one (and handle it in
      `resolve(using:)`, and in `MonteCarloExtension.evaluateFormula`), or map to
      `.function("POWER", [base, exponent])`. **Decide deliberately** — adding a case touches
      every exhaustive switch over `NodeFormula`.
- [x] Commit.

## Task 4 — Stop discarding `.array` cells

`:92-93` lumps `.array` in with `.date`/`.error` as "Unsupported cell type". **These are Excel
data tables** (`{=TABLE(r,c)}`) and are the detection signal for sensitivity-table recognition in
Phase 6. Losing them quietly forecloses that.

- [x] **RED** — test: a workbook containing a two-variable data table produces a warning that
      *identifies it as an array formula*, distinct from `.date`/`.error`.
- [x] **GREEN** — split `.array` out of the shared case with a specific message naming the cell.
      Do **not** attempt table recognition here; Phase 6 owns that. This task only stops the
      silent loss.
- [x] Commit.

## Task 5 — Multi-sheet import

`:29-32` — `importWorkbook` takes `sheets.first`. We export multi-sheet via `MultiSheetExporter`
but cannot import it. The pipeline is asymmetric in the direction that now matters.

- [x] **RED** — test: a two-sheet workbook imports both sheets' cells.
- [x] **GREEN** — add a multi-sheet entry point. Keep the existing single-sheet signature working.
- [x] Cross-sheet references (`FormulaAST.sheetRef`) stay unsupported in this phase but must
      **warn**, not vanish.
- [x] Commit.

---

## Expected breakage (intended — see proposal §7)

- `ModelImporterTests` asserts on the `"UNSUPPORTED"` sentinel string. Those assertions change.
- `ImportResult.warnings` becomes non-empty for workbooks that previously reported none. Any test
  asserting `warnings.isEmpty` needs updating. **This is the fix, not a regression.**

## Done when

- [x] All five tasks green, committed individually.
- [x] `swift build && swift test` clean.
- [x] **Quality gate 0 errors / 0 warnings, no overrides**, run with `--continue-on-failure` so a
      build failure cannot mask 44 unrun checkers.
- [x] CHANGELOG entry noting the two intended behavioural changes.
- [x] Move this file to `project/checklists/completed/`.

## Do NOT do in this phase

- Recognition, naming, units, or lag decomposition — that is Phase 2+.
- Fixing `MonteCarloExtension.swift:164` (`case .function: return 0`). Real bug, known, scheduled
  as a Future Direction once the upstream function registry exists.
- Bumping the BusinessMath pin. That is Phase 0 of the *next* stage and needs the fingerprint
  dance from `CLAUDE.md`.

---

## Decisions made (the ones this checklist left open)

**Task 2 — cells not yet seen.** Warn and degrade, not defer. A range's endpoints must both
resolve, because `NodeFormula.range` re-derives the exported `CellRange` from its first and
last reference: an unresolvable endpoint would silently export a *narrower* range than the
source workbook had, which is a wrong number rather than a missing one. Interior cells that
do not resolve are skipped without a warning — a blank separator row inside `SUM(D5:D16)` is
ordinary Excel, and only the endpoints determine the exported range.

Deferred resolution would additionally fix forward references, but `ExcelModel` has no way to
attach a formula to a `NodeRef` after the fact, so a second pass means changing the model
layer. Left for a deliberate decision; the unanchored-range warning makes the limitation
visible meanwhile.

**Task 3 — new case, or map to `POWER()`.** Added `NodeFormula.power`. Mapping to
`.function("POWER", …)` would have routed `^` into `MonteCarloExtension.evaluateFormula`'s
`case .function: return 0`, so every discount factor in a simulation would evaluate to zero
and the mean, stddev and percentiles would be computed from that — the same second-evaluator
failure recorded under "Do NOT do in this phase". A real case is evaluated correctly today
and needs nothing from the future function registry. It also keeps `(1+r)^n` re-exporting as
`(1+r)^n` rather than `POWER(1+r,n)`.

Cost, as the checklist predicted: all five exhaustive switches over `NodeFormula` were
touched, and downstream code switching exhaustively over it must add a `.power` case.

**Task 4 — reaching the branch at all.** `Worksheet` has no public write for `.array`,
`.date`, or `.error`, and SwiftXLSX's reader never emits them, so the branch was unreachable
from a black-box test. Extracted the internal `importCells` / `orderedCells` seam that every
entry point now funnels through. `importSheet` and `importWorkbook` are unchanged for callers.

**Task 5 — multi-sheet identity.** Sheets share cell references, so node labels are qualified
(`Inputs!A1`) and each sheet becomes its own section. `ImportResult` gained `sheetCellToNode`;
`cellToNode` is unchanged for single-sheet callers and, for a multi-sheet import, documented
as the first sheet's mapping, since a `CellRef` carries no sheet.

## Carried forward

- **Deferred formula resolution** (see Task 2 above) — needs an `ExcelModel` API for attaching
  a formula to an existing `NodeRef`.
- **Cross-sheet references** (`FormulaAST.sheetRef`) still do not translate. They warn and
  name the qualified cell, which is all this phase promised.
- **`MonteCarloExtension.swift` `case .function: return 0`** remains, unchanged and out of
  scope. `.power` no longer routes through it, but `NPV`/`IRR` from `DCFModelBuilder` still do.
