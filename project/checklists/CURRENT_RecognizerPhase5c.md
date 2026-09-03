# Phase 5c — `TypedSourceWriter`

Design: `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` §19.
Needs **BusinessMath 2.9.0** (`ModelUnit`, `LineItem<U>`, `Expr<U>`, `validateUnits()`), pinned
2026-09-03.

A recognized workbook can already be materialized and run. That is right for a tool and wrong for
a person, who wants to read what the sheet said, keep it in version control, and have a compiler
check it.

**Gate: the `ANSWER KEY` emits source that compiles, and evaluating it reproduces the same 125
values the plan does.**

---

## Task 1 — The recognizer carries its expression tree

A rendered formula is lossy, and `FormulaEvaluator.Node` is internal upstream, so the structure
cannot be recovered by parsing. Writing a parser for our own output would be the fourth instance
this session of recovering by inference something we knew for certain a moment earlier.

- [x] **RED** — `RecognizedExpression` covers what `LagDecomposition` builds: account reference,
      number, binary operator, comparison, function call, negation.
- [x] **RED** — the formula string is *rendered from the tree*, and every existing formula test
      still passes unchanged. That equivalence is the whole safety argument for the refactor, so
      it is not a new test — it is the 471 that already exist.
- [x] **RED** — `RecognizedAccount` carries the tree alongside its formula.
- [x] The Wharton 125-of-125 agreement is unmoved.
- [x] Commit.

## Task 2 — Emitting typed source

- [ ] **RED** — an account whose cells stated a unit emits `LineItem<Money>` / `Expr` operators.
- [ ] **RED** — every declaration carries `// <sheet>!<cell>` provenance, naming the anchor where
      an account has several cells.
- [ ] **RED** — an account with no unit emits the **string API**, because `LineItem<U>` has no
      untyped form and picking a unit would be inventing one.
- [ ] **RED** — an expression mixing a typed and an untyped operand emits untyped *whole*, rather
      than half-cast into something that would not compile.
- [ ] **RED** — inputs, rollforwards and periods are emitted, so the file is a runnable model
      rather than a fragment.
- [ ] Commit.

## Task 3 — The emitted source compiles and agrees

- [ ] **RED** — a golden file, checked in and compiled as part of the test target, matches the
      writer's output for a small fixture. Divergence fails the test; the golden compiles and runs
      because it is ordinary source in the package.
- [ ] **RED** — evaluating the golden reproduces the same numbers as materializing the plan.
- [ ] No `Process`: the safety checker refuses an unbounded spawn, and it is right to.
- [ ] Commit.

## Task 4 — Measure against Wharton

- [ ] Emit the `ANSWER KEY`. Report accounts emitted typed vs untyped, and the unit breakdown.
- [ ] Confirm the emitted source compiles and evaluates to the same 125 values.
- [ ] If any account cannot be emitted at all, name it and say why.
- [ ] Record in the proposal's phasing table and `master_plan.md`. Commit.

---

## Done when

- [ ] All four tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all`.
- [ ] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [ ] Move this file to `project/checklists/completed/`.
