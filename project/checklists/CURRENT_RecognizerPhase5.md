# Phase 5 — Block Detection

Design: `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` §17.

A sheet is not one grid with one timeline. The `ANSWER KEY` holds three label/value tables side
by side above the model, and their value columns land in the timeline's columns — `D` is both
the at-close anchor and the left table's values; `H` is both 2026 and the middle table's values.
Two defects compound from that, and neither fix is worth anything alone.

**Gate: the `ANSWER KEY` materializes and runs.** Or it names the row that stopped it.

`UnitInference` and `TypedSourceWriter` follow in a separate checklist. `TypedSourceWriter`
still waits on `TypedModelAuthoring.md` Phase 3; block detection waits on nothing.

---

## Task 1 — Rule 1: a value belongs to its nearest label

- [x] **RED** — a row with two labels and two values binds each value to the label on its own
      left: `B9` owns nothing across the axis when `F9` stands between it and `H9`.
- [x] **RED** — a model row is untouched: `B30` with values in `E30:J30` and no text between
      still binds all six.
- [x] **RED** — the `ANSWER KEY`'s non-uniform count falls from 7 to 1. The six that go are the
      assumptions collision; the one that stays is `Debt (B58)`, which is genuinely irregular.
- [x] Commit.

## Task 2 — Rule 2: the timeline governs its own block

- [x] **RED** — a label above the axis heading with one value off the timeline is a **scalar**,
      not a series with an anchor and no periods. `Revenue growth` is `0.10`.
- [x] **RED** — the anchor column carries no at-close meaning outside the block: `D9` is
      `2023 Revenue`'s value, not its at-close figure.
- [x] **RED** — inside the block the anchor still means at close: `D61` is still the equity
      cheque, and IRR is still 24.67%. This is the regression that matters most.
- [x] **RED** — a scalar whose value is a *formula* stays derived: `Total Purchase Price` is
      `Entry EBITDA * Purchase Multiple`, not `200`.
- [x] Commit.

## Task 2b — What Rules 1 and 2 revealed

Added 2026-09-02, after Task 2. Block detection landed and moved the blocker forward; the sheet
still does not run, and none of what stops it now is block detection. Recorded here rather than
folded silently into another task, because the design did not predict any of it.

- [ ] **`SUM` over a vertical cell range.** `E47 = SUM(E42:E46)`, `E52 = SUM(E50:E51)`,
      `E61 = SUM(E57:E60)` — sums of *accounts within one period*. Entirely expressible as
      `[EBITDA] + [Less: Taxes] + …`; simply not expressed. Three model rows plus the
      `Total Sources` / `Total Uses` assumptions. This is the largest single gap.
- [ ] **The named range `Circ`.** `E36 = E54 * -1 * Circ` — the model's circularity switch, a
      named range rather than a cell. `NodeFormula` has no case for one. Decide: resolve named
      ranges to their targets, or refuse with a diagnostic of its own. It gates `Less: Interest`,
      which gates `EBT`.
- [ ] **The sensitivity grid in columns N onward.** Rows 5–11 extend past the assumption tables
      into a What-If grid whose headings sit on different rows, so seven labels own several
      values and are refused as `ambiguousAssumption` — the same class of collision Rule 1 fixed
      for series, one block further right. Phase 6 owns the grid itself; this is only about not
      letting it swallow the assumptions beside it.

## Task 3 — Scalars through materialization

- [ ] **RED** — a scalar becomes an input holding its value in every period, so a formula
      referencing it resolves. `% growth` finds `Revenue growth`.
- [ ] **RED** — a derived scalar becomes a definition, not an input, and is not mistaken for a
      period series.
- [ ] Commit.

## Task 4 — Measure against Wharton

- [ ] Report recognition coverage, accounts, residue, and **whether the sheet materializes and
      runs**, alongside the Phase 3–4 figures.
- [ ] If it runs, check what it produces against the sheet's own cached values and say how far
      it agrees. A model that runs and disagrees is worse than one that refuses.
- [ ] If it does not run, name the row and why — plainly, not rounded off.
- [ ] IRR 24.67% and MoM 3.01 must still reproduce.
- [ ] Record in the proposal's phasing table and `master_plan.md`. Commit.

---

## Done when

- [ ] All four tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all`.
- [ ] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [ ] Move this file to `project/checklists/completed/`.
