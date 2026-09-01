# CURRENT: ModelImporter Fixes (Recognizer Phase 1)

**Started:** 2026-09-01
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

- [ ] **RED** — test: a workbook whose formula contains an unsupported node produces a non-empty
      `ImportResult.warnings`.
- [ ] **GREEN** — add `warnings: inout [String]` to `convertAST`; append on every fallthrough to
      `.text("UNSUPPORTED")`. Include the cell reference and the node kind in the message.
- [ ] **REFACTOR** — consider a typed warning rather than `String`; the recognizer will want
      `DiagnosticCode` later. Keep `[String]` if typing it expands scope.
- [ ] Commit.

## Task 2 — Support `.cellRange`

`:161-165` collapses `.cellRange` to `.text("UNSUPPORTED")`. Real financial workbooks are
`SUM(D5:D16)`, `NPV(rate, D5:D16)`, `IRR(D4:D16)`. Nothing meaningful imports without this.

- [ ] **RED** — test: `=SUM(D5:D16)` imports as a range-bearing `NodeFormula`, not `"UNSUPPORTED"`.
- [ ] **GREEN** — map `FormulaAST.cellRange` → `NodeFormula.range([NodeRef])`, resolving each
      cell in the range through `cellToNode`. Cells not yet seen are the interesting case —
      decide and document: warn and degrade, or defer resolution.
- [ ] Edge: a range spanning cells that are not all present in `cellToNode`.
- [ ] Commit.

## Task 3 — Support `.power`

Same line. `(1+r)^n` appears in every discounting formula.

- [ ] **RED** — test: `=(1+B2)^B3` imports without `"UNSUPPORTED"`.
- [ ] **GREEN** — `NodeFormula` has no `.power` case. Either add one (and handle it in
      `resolve(using:)`, and in `MonteCarloExtension.evaluateFormula`), or map to
      `.function("POWER", [base, exponent])`. **Decide deliberately** — adding a case touches
      every exhaustive switch over `NodeFormula`.
- [ ] Commit.

## Task 4 — Stop discarding `.array` cells

`:92-93` lumps `.array` in with `.date`/`.error` as "Unsupported cell type". **These are Excel
data tables** (`{=TABLE(r,c)}`) and are the detection signal for sensitivity-table recognition in
Phase 6. Losing them quietly forecloses that.

- [ ] **RED** — test: a workbook containing a two-variable data table produces a warning that
      *identifies it as an array formula*, distinct from `.date`/`.error`.
- [ ] **GREEN** — split `.array` out of the shared case with a specific message naming the cell.
      Do **not** attempt table recognition here; Phase 6 owns that. This task only stops the
      silent loss.
- [ ] Commit.

## Task 5 — Multi-sheet import

`:29-32` — `importWorkbook` takes `sheets.first`. We export multi-sheet via `MultiSheetExporter`
but cannot import it. The pipeline is asymmetric in the direction that now matters.

- [ ] **RED** — test: a two-sheet workbook imports both sheets' cells.
- [ ] **GREEN** — add a multi-sheet entry point. Keep the existing single-sheet signature working.
- [ ] Cross-sheet references (`FormulaAST.sheetRef`) stay unsupported in this phase but must
      **warn**, not vanish.
- [ ] Commit.

---

## Expected breakage (intended — see proposal §7)

- `ModelImporterTests` asserts on the `"UNSUPPORTED"` sentinel string. Those assertions change.
- `ImportResult.warnings` becomes non-empty for workbooks that previously reported none. Any test
  asserting `warnings.isEmpty` needs updating. **This is the fix, not a regression.**

## Done when

- [ ] All five tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings, no overrides**, run with `--continue-on-failure` so a
      build failure cannot mask 44 unrun checkers.
- [ ] CHANGELOG entry noting the two intended behavioural changes.
- [ ] Move this file to `project/checklists/completed/`.

## Do NOT do in this phase

- Recognition, naming, units, or lag decomposition — that is Phase 2+.
- Fixing `MonteCarloExtension.swift:164` (`case .function: return 0`). Real bug, known, scheduled
  as a Future Direction once the upstream function registry exists.
- Bumping the BusinessMath pin. That is Phase 0 of the *next* stage and needs the fingerprint
  dance from `CLAUDE.md`.
