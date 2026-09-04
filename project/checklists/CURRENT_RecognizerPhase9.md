# Phase 9 — The axis is a finding, not a precondition

Design: `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` §22.

A rule filled across a row is the same formula in every column. That is a fact about the
formulas, not about the labels above them — so a timeline can be *derived* from the sheet's own
arithmetic rather than read off a header row that may be missing, wrong, or written in a
convention nobody anticipated.

Measured before writing anything: Kelly's finds no header axis and yields 6 runs agreeing on one
span; credit sheet `A` picks a *column* of five cells as its timeline while 16 runs agree on
L–O.

**Gate: an axis is derived where header detection finds none, across all three corpora. Wharton's
125-of-125 does not move, and where header detection already succeeds, nothing changes.**

---

## Task 1 — Shape runs

- [x] **RED** — `ShapeRun` finds maximal runs of horizontally adjacent cells sharing one R1C1
      shape. A run of two is not a timeline; three is the smallest thing that can be one.
- [x] **RED** — a row whose formulas differ yields no run, and a row broken by a gap yields two.
- [x] **RED** — runs are found down columns as well as across rows, because a model may run
      either way and the sheet decides.
- [x] **RED** — an absolute reference does not break a run: `$B$3` is the same in every column,
      which is exactly what pinning means.
- [x] Commit.

## Task 2 — Deriving the axis

- [x] **RED** — the span the most runs agree on is the derived axis, with the count reported as
      the evidence for it.
- [x] **RED** — one run agreeing with itself is not evidence; below a floor, nothing is derived.
- [ ] **RED** — `PeriodAxis` uses it only when header detection finds nothing. Where a header axis
      exists it is kept, because it is what a reader would do and it carries Wharton.
- [ ] **RED** — when both exist and disagree, the header axis is kept and the difference is
      **reported**. Asserting the shape answer in general would be a guess, and on credit sheet
      `A` the two disagree in a way worth seeing.
- [ ] Commit.

## Task 3 — Measure

- [ ] Wharton: 125-of-125 unmoved, coverage unmoved. The regression bar.
- [ ] Corpus: how many of the 60 workbooks without a timeline now have one.
- [ ] Credit model and media model: coverage before and after.
- [ ] Record in the proposal and `master_plan.md`. Commit.

---

## Done when

- [ ] All three tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all`.
- [ ] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [ ] Move this file to `project/checklists/completed/`.
