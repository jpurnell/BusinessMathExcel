# CURRENT: Recognizer Phase 2 — Stages 1–2, Coverage, and comparison operators

**Started:** 2026-09-01
**Proposal:** `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` (§3, §4, §10, phasing)
**Depends on:** Phase 0 (BusinessMath 2.7.0) and Phase 1 (`ModelImporter`), both complete
**Unblocks:** Stage 3 `FormulaTranslator` — and the coverage number that shapes everything after

New code lives in `Sources/BusinessMathExcel/Recognition/`, a peer of `Import/` and `Export/`.
The split is deliberate and load-bearing: `Import/` is a faithful structural transcription that
never interprets, so a workbook we cannot understand still round-trips. Recognition is the
interpretive layer stacked on top, and nothing in it may reach back down.

**TDD per project rules: failing test first, minimum code, refactor. Commit at each green state.**

---

## Task 1 — Comparison operators in `NodeFormula` (do this first)

Pulled forward from decision D8; see the proposal §15 Q0 for the measurement. Doing it first
means the Coverage numbers Tasks 5–7 report are not depressed by a gap already decided.

`FormulaAST` has six comparison cases; `NodeFormula` has none, so all six degrade to
`UNSUPPORTED`. Same shape as `NodeFormula.power`, which cost one case and five switch sites.

**`IF` itself needs nothing.** Excel's `IF` is a function, not an AST node, so it already imports
as `.function("IF", args)` and round-trips today. Verified on both reference workbooks. Only the
*operators inside its condition* are missing. Do not add an `IF` case.

- [x] **RED** — test: `=A1>B1` imports as a comparison, not `UNSUPPORTED`; one test per operator.
- [x] **RED** — test: `=IF(A1>B1, A1, B1)` imports with a real comparison in the condition.
- [x] **GREEN** — add `.equal`, `.notEqual`, `.greaterThan`, `.lessThan`, `.greaterOrEqual`,
      `.lessOrEqual` to `NodeFormula` and handle each in all five exhaustive switches:
      `resolve(using:)`, `ModelImporter.convertAST`, `MonteCarloExtension.evaluateFormula`,
      `MultiSheetExporter`, `FormulaMapper.collectFunctions`.
- [x] **Decided:** 1 and 0, Excel's arithmetic convention. Checking `.bool` first was the
      right instruction — it returned 0 for *both* TRUE and FALSE, the same value it uses
      for "cannot evaluate", so a true condition was indistinguishable from an unsupported
      one. Fixed alongside; leaving it would have made `A1>B1` yield 1 while `TRUE` yielded 0.
- [x] ~~**Decide:** what `MonteCarloExtension` returns for a comparison.~~ It is a `Double` evaluator
      with no boolean channel. Excel treats TRUE/FALSE as 1/0 in arithmetic, so 1/0 is defensible
      and matches the existing `.bool` handling — but check what `.bool` actually does first
      rather than assuming, and write down whichever you choose.
- [x] Round-trip test: comparison survives export and re-import.
- [x] Commit.

**Scope guard.** This adds *representation only*. D9 still governs what an `IF` means — a
timeline-answerable `IF` becomes an indicator series, and that is Stage 3's decision, not this
task's. Adding the cases does not decide the semantics.

## Task 2 — `Diagnostic` and `Coverage`

The vocabulary everything else reports through. Small, and blocking for Tasks 3–6.

- [ ] **RED** — test: `Coverage.fraction` is `recognized / populated`, and `0` for an empty sheet
      rather than a division by zero.
- [ ] **GREEN** — `Diagnostic` (severity, code, cell, message), `DiagnosticCode` per proposal §4,
      `Coverage`. All `Sendable`, all DocC'd.
- [ ] Include `.dynamicReference` and `.foldedDynamicReference` in the enum even though Stage 3
      owns them — the enum should be complete, and a `CaseIterable` with holes invites a second
      one later.
- [ ] Commit.

## Task 3 — `SheetGrid` (Stage 1)

Cell topology and orientation. Consumes an `ImportResult`; knows cell positions, which the
`ExcelModel` deliberately does not.

- [ ] **RED** — test: a sheet with years across the top resolves `.periodsAcrossColumns`; one with
      years down the side resolves `.periodsDownRows`.
- [ ] **RED** — test: a sheet where both could be read as an axis emits `.ambiguousOrientation`
      and picks neither. **Not guessing is the feature.**
- [ ] **RED** — test: a sheet with no axis at all emits `.noPeriodAxis`.
- [ ] **GREEN** — implement.
- [ ] **Decide:** what counts as evidence of an axis. Write the rule down in the type's DocC; a
      heuristic nobody can read is a heuristic nobody can fix.
- [ ] Edge: empty sheet, single column, a sheet at `maximumCells`  (`.scanLimitReached`).
- [ ] Commit.

## Task 4 — `PeriodAxis` (Stage 1)

Recovered headers to `[Period]`, using BusinessMath's `Period`/`PeriodType` — the reason Phase 0
bumped the pin.

- [ ] **RED** — test: `2024 2025 2026` recovers three annual periods via `Period.year(_:)`.
- [ ] **RED** — test: header forms real models use — `FY24`, `2024E`, `Q1 2024`. Pick the set
      deliberately and record what is *not* recognized rather than letting it be implicit.
- [ ] **RED** — test: a header that parses to a non-monotonic or duplicated sequence is reported,
      not silently accepted.
- [ ] **GREEN** — implement, honouring `RecognizerOptions.granularity` when supplied and inferring
      when it is `nil`.
- [ ] Commit.

## Task 5 — `LabeledSeries` (Stage 2) with address-fallback naming

- [ ] **RED** — test: a text cell binds to the run of value cells on its row.
- [ ] **RED** — test: values with no label get an address-derived name and an `.labelUnbound`
      info diagnostic — they are recognized, not dropped.
- [ ] **RED** — test: duplicate labels emit `.duplicateAccountName` and both survive distinctly.
- [ ] **GREEN** — implement for both orientations.
- [ ] **Decide:** whether a blank cell breaks a run. A blank inside a row of figures is ordinary;
      a blank separating two blocks is meaningful. Choose, document, and test the boundary.
- [ ] Commit.

## Task 6 — Formula uniformity

Phase 2's gate names this explicitly: the count of non-uniform rows is what tells us how much of
a sheet is hand-edited, and how far `IF`-free encoding can reach.

- [ ] **RED** — test: a row whose cells share a shape modulo column offset is uniform.
- [ ] **RED** — test: one hand-edited cell makes the row non-uniform and emits `.nonUniformRow`.
      **The recognizer never picks a majority shape** (decision D10).
- [ ] **GREEN** — implement.
- [ ] **Decide:** shape comparison needs cell positions to compute the offset, but `NodeFormula`
      references nodes, not cells. Resolve refs back through `cellToNode` — this is why
      uniformity lives with `SheetGrid` rather than in the model layer.
- [ ] Commit.

## Task 7 — Measure

- [ ] Extend `WhartonImportMeasurementTests` (or add a recognition peer) to report coverage and
      the non-uniform row count for the Wharton `ANSWER KEY`.
- [ ] Report the number. **It is a progress metric toward 100%, not a kill gate** — do not add an
      assertion that fails the build on a coverage threshold.
- [ ] Record the figure in the proposal's phasing table and `master_plan.md`.
- [ ] Commit.

---

## Done when

- [ ] All seven tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings, no overrides**, run with `--continue-on-failure`.
- [ ] CHANGELOG entry, including the `NodeFormula` source-breaking note from Task 1.
- [ ] Wharton coverage and non-uniform row count recorded.
- [ ] Move this file to `project/checklists/completed/`.

## Do NOT do in this phase

- Stage 3 and later: formula translation, lag decomposition, unit inference, `ModelDefinition`
  materialization, typed source writing.
- Dynamic-reference folding (`INDIRECT`/`ADDRESS`/`OFFSET`). Proposal §3 assigns it to Stage 3,
  Tier 1 only. Stage 2 owes it nothing but the ability to express a sheet named by data.
- `IF` *semantics*. Task 1 adds operators; D9 decides meaning, in Stage 3.
- `MonteCarloExtension`'s `case .function: return 0`. Still scheduled behind the upstream registry.
- Any interpretation inside `Import/`. If a task tempts you to put recognition there, the layer
  split is the thing being tested.
