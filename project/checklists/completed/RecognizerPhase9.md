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
- [x] **RED** — `PeriodAxis` uses it only when header detection finds nothing. Where a header axis
      exists it is kept, because it is what a reader would do and it carries Wharton.
- [x] **RED** — when both exist and disagree, the header axis is kept and the difference is
      **reported**. Asserting the shape answer in general would be a guess, and on credit sheet
      `A` the two disagree in a way worth seeing.
- [x] Commit.

**Settled while building, against the sheets rather than in the abstract:**

- **Ordinal periods, counted from one.** A derived axis has no headings, so it synthesises
  positions rather than reading whatever text sits above the span. From one, not zero:
  `Period.year(0)` does not survive Foundation's Gregorian era boundary and comes back equal to
  `Period.year(1)`, which would collapse the first two periods of every derived axis into one.
  Proposal §22.3.
- **`axisLine` for a derived axis is the line above the first agreeing run** — the boundary later
  stages read the sheet against. It costs that one line, which may hold figures rather than
  headings and becomes residue. Measure the cost in Task 3.
- **Disagreement means the shape span reaches *outside* the heading span**, not merely differs
  from it. The first rule reported any difference and immediately fired on the Wharton ANSWER KEY:
  headings across 5–10, seventeen runs agreeing on 5–9, because the exit year is computed its own
  way. A run span inside the heading span is the same timeline with an end of its own — that is
  corroboration, not contradiction.
- **A tie derives nothing**, and **headings that read equally well both ways are not rescued** by
  shape evidence. Both are the same refusal: a sheet that made two claims and was not believed is
  not settled by quietly consulting a third source.

## Task 3 — Measure

- [x] Wharton: 125-of-125 unmoved, coverage unmoved. The regression bar. **279 cells, 238
      recognized (85%), 125 agreeing / 0 disagreeing.**
- [x] Corpus: how many of the 60 workbooks without a timeline now have one. **37 of them.**
      Workbooks with a timeline 19 → 56 of 79; sheets with an axis 67 → 297 of 674; accounts
      recovered **839 → 4,894**.
- [x] Credit model and media model: coverage before and after. **Credit 17 → 18 of 18 sheets,
      accounts unchanged at 326, and 12 sheets report the disagreement — the same twelve §21.4
      had already identified by another route. Media 13 → 74 of 104 sheets, accounts 34 → 40.**
- [x] Record in the proposal and `master_plan.md`. Commit.

The before column is a real run of the same test at `8f354c8` in a throwaway worktree, not a
figure quoted from the handoff — the accounts baseline had never been recorded, and §22.6 exists
to keep such numbers honest.

**What it also said.** The media model gained sixty-one timelines and six accounts, so the axis
was never what stood in its way; 377 of 674 sheets still return zero because `ExcelRecognizer`
bails to an empty model without one; and the dependency graph recovers 781,867 nodes from the same
files, unchanged, because it never depended on any of this. Recorded as §22.6 and §22.7, and the
reorientation that follows from it as **§23**.

---

## Done when

- [x] All three tasks green, committed individually.
- [x] `swift build && swift test` clean.
- [x] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all`.
- [x] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [x] Move this file to `project/checklists/completed/`.
