# Session Handoff — 2026-09-04

Resume here. The previous handoff (2026-08-26, a dependency-resolution repair) is superseded and
its content lives in `project/summaries/` and the CHANGELOG.

---

## The next step, concretely

**Phase 9, Task 2 — derive the period axis from shape runs.**
Checklist: `project/checklists/CURRENT_RecognizerPhase9.md`. Design: proposal **§22**.

Task 1 shipped `ShapeRun` (`Sources/BusinessMathExcel/Recognition/ShapeRun.swift`), which finds
maximal runs of adjacent cells sharing one R1C1 shape. Task 2 turns those runs into an axis:

1. **RED** — the span the most runs agree on is the derived axis, with the agreeing count carried
   as the evidence for it.
2. **RED** — one run agreeing with itself is not evidence; below a floor, derive nothing.
3. **RED** — `PeriodAxis` uses the derived axis **only when header detection finds none**. Where a
   header axis exists it is kept: it is what a reader would do, and it carries Wharton.
4. **RED** — when both exist and disagree, keep the header axis and **report** the difference.
   Asserting the shape answer in general would be a guess, and on credit sheet `A` the two
   disagree in a way worth seeing.

Then Task 3 measures across all three corpora and closes the phase.

---

## Why this direction

A rule filled across a row is the same formula in every column. That is a fact about the
*formulas*, not the labels above them — so a timeline can be derived from a sheet's own arithmetic
rather than read off a header row that may be missing, wrong, or written in a convention nobody
anticipated.

Three independent measurements forced this:

| | Sheets with no timeline the recognizer can find |
|---|---|
| Corpus of 77 teaching/ops workbooks | **60 of 77** |
| GS credit model | 12 of 18 sheets pick the **wrong** one |
| CNBCU media model, 104 sheets | **100 of 104** |

A dependency graph builds on **all** of them. Measured before writing any code: Kelly's finds no
header axis but yields 6 runs agreeing on one span; credit sheet `A` picks a *column of five
cells* as its timeline while 16 runs agree on a span across. That second case is the argument —
header detection there does not fail quietly, it reads the whole sheet sideways and is confident.

Proposal **§21.4** records that Phase 8 was the last phase buildable on the old ordering:
improving what happens *after* "find the timeline" cannot help a model where that precondition
fails.

---

## The regression bar

**Wharton `ANSWER KEY`: 125 of 125 values matching the sheet's own cached figures.** Nothing may
move it. It is checked by
`WhartonImportMeasurementTests/testTheRecognizedModelAgreesWithTheSheetsOwnValues`.

Also holding: published IRR **24.67%** and MoM **3.01×** reproduce; recognition coverage 85% on
that sheet; the emitted Swift compiles (golden file built by the test target).

---

## State

| Repo | Tag | Notes |
|---|---|---|
| BusinessMathExcel (here) | `v0.7.0` | 547 tests, 45/45 checkers, 0/0 |
| SwiftXLSX | `v0.11.1` | pinned `exact: "0.11.1"` |
| BusinessMath | `v2.9.0` | pinned `exact: "2.9.0"` |

Working tree clean, all pushed. Phases 0–8 complete; Phase 9 Task 1 complete.

**Five upstream releases came out of this work**, three of them the same shape — information the
reader already understood with no way for a caller to reach it: SwiftXLSX 0.8.0 (named ranges),
0.9.0 (cell styles), 0.10.0 (formula + cached value), 0.11.0 (scoped dependency graph), 0.11.1
(a `$` marker is not a different cell). BusinessMath 2.8.0 (functions, `PeriodDriver`) and 2.9.0
(the typed layer).

---

## The corpora

None is checked in — teaching material and employer files, read locally, never committed.

```
BUSINESSMATHEXCEL_CORPUS="/path/one:/path/two" swift test --filter Corpus
```

Unset, `CorpusMeasurementTests` skips. Roots used so far:

- `~/Documents/Tuck/Academic/2011-2012/1. Fall/1.1 Fall A/DECSCI/Class Models`
- `~/Documents/Tuck/Academic/2012-2013/1. Fall/AO/Models`
- `~/Documents/Tuck/Academic/2012-2013/3. Spring/pdm`

Individually useful, referenced by path in tests that skip when absent:

- **Wharton LBO Practice Model** — `Tests/Fixtures/`, gitignored. The fixture, with a published
  answer key. See `Tests/Fixtures/README.md`.
- **GS credit model** — `~/Documents/Career/GS/Credit/USA Standard Model 08-08-01.xlsx`. 18
  sheets, 5 near-identical scenarios.
- **Kelly's Roast Beef** — in the DECSCI folder. A bond cash-matching LP; the cleanest example of
  a non-time-series model, with `Parameters` / `Decision Variables` / `Objective Function` /
  `Calculation` blocks labelled in column A.
- **CNBCU media model** — `~/Documents/Career/CNBCU/Projects/2. xfinity.com/2.0 xfinity.com –
  Sample Excel/Digital Media 4.6.5ß.xlsx`. 104 sheets, 568,203 cells. The `X - Data` /
  `X - Input+Calc` convention, metric by metric.

The corpus takes ~2 minutes; the media model takes ~65s to recognize and ~347s to graph.

---

## Known limitations, recorded deliberately

Each is named where it was found, with assertions that fail if it is ever fixed — so none can
quietly outlive its cause.

- **Terminal-event rows.** A row holding literals until its final period and then a formula cannot
  be stated by a model with one rule per account. `Equity of PE Firm` is the one account Wharton
  still drops. (§17.7)
- **Time aggregates.** `IRR`, `NPV`, `MoM` reduce a whole timeline; a `ModelDefinition` is
  period-local by design. This is why Phase 6 cannot recompute a sensitivity grid. (§20.2, §20.7)
- **No typed `sum` upstream.** BusinessMath's typed layer has `min`, `max`, `abs`; six of the
  twenty untyped definitions in emitted source are `SUM` or `AVERAGE`. (§19.7)
- **Rows below the axis, off the period columns** — `MOM` and `IRR` in Wharton's column C. The
  same shape Rule 2 fixed *above* the axis. (§20.6)
- **Graph performance.** 347s to build the media model's graph. Not yet investigated.

---

## How to work here

`CLAUDE.md` governs. In short: strict TDD (RED → GREEN → commit at each green); quality gate
`--check all --continue-on-failure`, **counting** errors and warnings rather than reading the
verdict line; doc housekeeping in the same commit; no temp probe files left in
`Tests/BusinessMathExcelTests/` (the gate catches them, but only after they have wasted a run).

Two mistakes made this session, worth not repeating:

- **Look before building.** A dependency graph was hand-rolled before checking that SwiftXLSX
  already shipped one, and a canonicaliser was nearly duplicated before `FormulaUniformity`'s was
  shared instead.
- **Never move a published tag.** `v0.11.0` was retagged in place after being consumed, which is
  exactly what `CLAUDE.md` warns breaks SwiftPM's trust-on-first-use fingerprint downstream. It
  was restored and the fix released as `v0.11.1`.

---

## Where this is all heading

`ShapeRun` is the first piece of a **`ModelGraph`** — the projection from a spreadsheet's
cell-level dependency graph to a model-level one. Once the axis is derived rather than assumed,
the rest follows:

- collapse a run into **one account across periods**
- turn a run's reference to its own left neighbour into a **carry**
- reduce cell-level cycles to model-level ones — Wharton's **39 → 1**

The outbound direction has always been graph → layout → grid (`ExcelModel` is a DAG; a
`LayoutStrategy` assigns cells at export). The inbound direction went grid → accounts × periods,
skipping the graph. Making the inbound path admit the same middle is the whole of the current
work, and proposal §22 is where it is written down.
