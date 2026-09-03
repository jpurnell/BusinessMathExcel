# Phase 6 — What-If Tables

Design: `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` §20.

`DataTableBlock` has known *where* a table sits since Phase 5a, because a label beside one was
claiming its cells. This reads what it says.

**Gate: the `ANSWER KEY`'s IRR sensitivity table is recognized — both drivers named, both value
vectors read, 25 results in the right orientation, the measured output identified — and coverage
is reported with the table's cells counted.**

**Not in scope, and why.** The gate as originally written asked for a *recomputed* grid. That
needs the measured output, which on this sheet is `IRR(D61:I61)` — an aggregate over the whole
timeline, which a period-local `ModelDefinition` refuses by design — over the one row Phase 5a
recorded as beyond it. §20.2 records both. A partial recomputation would have to fake one.

---

## Task 1 — Reading the table

- [x] **RED** — `RecognizedSensitivity` carries the two drivers by **account name**, the two value
      vectors, the results grid, and the cell the measured formula lives in.
- [x] **RED** — `results[i][j]` is the value for `inputValues1[i]` and `inputValues2[j]`, matching
      `TwoWayScenarioSensitivityAnalysis` upstream. Orientation is the thing to get wrong here, so
      it gets an asymmetric fixture — a 2×3 grid, where a transpose cannot pass.
- [x] **RED** — a one-way table is not read as two-way; the file says which via `dt2D`, and
      guessing would produce a grid with one axis invented.
- [x] **RED** — a driver cell the sheet does not name resolves to its address, not to nothing.
- [x] Commit.

## Task 2 — Into the plan

- [x] **RED** — `RecognizedModel.sensitivities` holds them. A table is an analysis *of* the model,
      not an account: it sits beside the accounts, and `ModelMaterializer` ignores it.
- [x] **RED** — the table's cells count as recognized, so coverage reflects them.
- [x] **RED** — a sheet with no table yields none, and no diagnostics.
- [x] Commit.

## Task 3 — Mapping upstream

- [x] **RED** — `TwoWayScenarioSensitivityAnalysis` is built from a recognized table, with the
      values in the order that type documents.
- [x] Commit.

## Task 4 — Measure against Wharton

- [x] Report the recognized table: drivers, vectors, grid shape, measured output.
- [x] Report coverage with the table counted, against the 72% it was without.
- [x] Confirm the 125-of-125 agreement is unmoved — a table is not an account, so it must not be.
- [x] Name the recomputation blocker plainly; do not round it off.
- [x] Record in the proposal's phasing table and `master_plan.md`. Commit.

---

## Done when

- [x] All four tasks green, committed individually.
- [x] `swift build && swift test` clean.
- [x] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all`.
- [x] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [x] Move this file to `project/checklists/completed/`.
