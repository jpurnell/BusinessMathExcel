# Session Handoff — 2026-09-04 (afternoon)

Resume here. The previous handoff (2026-09-04 morning, Phase 9 Task 2) is superseded: Phase 9 is
complete and closed. Its content lives in `project/checklists/completed/RecognizerPhase9.md` and
proposal §22.

---

## The next step, concretely

**Design the graph.** Proposal **§23** is the reorientation and §23.7 lists the four questions it
leaves open. Nothing is built against it yet, and nothing should be until those are settled
against real files.

The goal, restated: take an **arbitrary** spreadsheet, model the relationships between its cells —
references and formulas — as a graph, hold that graph as the intermediate structure, and from it
re-emit both a working spreadsheet and Swift that can be enhanced or used in another application.
Decoration (labels, colours, headings, layout) is a separate concern for later.

### The four open questions — §23.7

1. **Node granularity.** Cell-level is faithful and gives 568,203 nodes for one workbook.
   Compression is not cosmetic; it decides whether emitted Swift is usable. In the graph, or in a
   projection over it?
2. **What round-trip identity means.** Formulas and computed values, explicitly not decoration.
   Worth writing as a contract before building to it.
3. **Cycles.** Wharton holds 39 at cell level. A faithful graph must *represent* them;
   recognition currently refuses them. A posture change, not a feature.
4. **What emitted Swift looks like** from an arbitrary graph rather than a `ModelDefinition`, and
   what of the typed layer (§19) still applies when there are no units to infer.

### Orientation

- **`DependencyGraph` already ships in SwiftXLSX** and answers every structural question the goal
  needs: `allCells`, `evaluationOrder`, `inputs`, `outputs`, `precedents(of:)`, `dependents(of:)`,
  `allDependents(of:)`, `isAcyclic`, `cycles`. Constructible from a sheet or a whole workbook,
  with an optional filter for what counts as a quantity. **Look here before building anything.**
- **The gate that follows cannot be fitted to a corpus** (§23.6): read any workbook → build the
  graph → re-emit → the formulas evaluate to what the original evaluated to. Checkable on files
  nobody has seen. This is the strongest reason for the change and should be the phase's gate.
- **`ExcelRecognizer.swift:201`** is the line that makes the current path an interpreter:
  `guard let axis else { return ...recognizedCells: 0 }`. No timeline, no output.
- **`ShapeRun` is reused, repositioned** — graph compression rather than a precondition. Sixteen
  cells sharing one R1C1 shape are one relationship instantiated sixteen times.
- **`ExcelModel`** (the outbound DAG) is already the shape an inbound graph should meet. The round
  trip closes there.

---

## Why this direction

Phase 9 met its gate and found its ceiling in the same measurement.

| | Before (`8f354c8`) | After |
|---|---|---|
| Workbooks with a recognizable timeline | 19 of 79 | **56 of 79** |
| Sheets with an axis | 67 of 674 | **297 of 674** |
| Accounts recovered by recognition | 839 | **4,894** |
| Nodes recovered by the dependency graph | 781,867 | 781,867 |

Deriving structure from arithmetic rather than labels recovered **5.8× more model** from the same
files. And the last row did not move, because it never depended on any of this — the dependency
graph builds on all 674 sheets while recognition reaches 297.

Two results say the ceiling is structural rather than a tuning problem:

- **The media model gained 61 timelines and 6 accounts** (13 → 74 sheets with an axis, 34 → 40
  accounts). The axis was never what stood in its way.
- **377 of 674 sheets still return exactly zero**, because the recognizer bails to an empty model
  without an axis.

§23.4 names precisely where this work fitted itself to the corpus rather than to an argument —
annual-only periods, a disagreement rule narrowed because the fixture complained, a floor of three
chosen from two sheets. Each is defensible locally. The problem is that the *schema* — periods ×
accounts, one rule per account, carries between periods — is itself read off financial models, and
an arbitrary spreadsheet is not one.

---

## The regression bar

**Wharton `ANSWER KEY`: 125 of 125 values matching the sheet's own cached figures.** Nothing may
move it. Checked by
`WhartonImportMeasurementTests/testTheRecognizedModelAgreesWithTheSheetsOwnValues`.

Also holding: coverage 85% (238 of 279 cells), published IRR **24.67%** and MoM **3.01×**
reproduce, and the emitted Swift compiles (golden file built by the test target).

---

## State

| Repo | Tag | Notes |
|---|---|---|
| BusinessMathExcel (here) | `v0.7.0` + 3 commits | 558 tests, 45/45 checkers, 0/0 |
| SwiftXLSX | `v0.11.1` | pinned `exact: "0.11.1"` |
| BusinessMath | `v2.9.0` | pinned `exact: "2.9.0"` |

Working tree clean. Phases 0–9 complete. **Not yet tagged** — §23 is a change of goal, so the next
release should probably follow the first graph work rather than precede it.

Recent commits:

- `0023b0b` docs: close Phase 9 on measurement, and reorient on what it found
- `4482b69` feat(recognize): an axis derived where the headings say nothing
- `7add795` feat(recognize): the span the sheet's own arithmetic agrees on

---

## The corpora

None is checked in — teaching material and employer files, read locally, never committed.

```
BUSINESSMATHEXCEL_CORPUS="/path/one:/path/two" swift test --filter Corpus
```

Unset, `CorpusMeasurementTests` skips. `testReportsWhatTheCorpusRecovers` now reports the axis
provenance split (read / derived / disagreeing) per workbook, which is what made §22.6 measurable.
Roots used so far:

- `~/Documents/Tuck/Academic/2011-2012/1. Fall/1.1 Fall A/DECSCI/Class Models`
- `~/Documents/Tuck/Academic/2012-2013/1. Fall/AO/Models`
- `~/Documents/Tuck/Academic/2012-2013/3. Spring/pdm`

Individually useful, referenced by path in tests that skip when absent:

- **Wharton LBO Practice Model** — `Tests/Fixtures/`, gitignored. The fixture, with a published
  answer key. See `Tests/Fixtures/README.md`.
- **GS credit model** — `~/Documents/Career/GS/Credit/USA Standard Model 08-08-01.xlsx`. 18
  sheets, 5 near-identical scenarios. 12 of them report `derivedAxisDiffers`.
- **Kelly's Roast Beef** — in the DECSCI folder. A bond cash-matching LP; the cleanest example of
  a non-time-series model.
- **CNBCU media model** — `~/Documents/Career/CNBCU/Projects/2. xfinity.com/2.0 xfinity.com –
  Sample Excel/Digital Media 4.6.5ß.xlsx`. 104 sheets, 568,203 cells. The workbook that shows the
  ceiling.

**Measuring a single workbook:** copy it to a scratch directory and point
`BUSINESSMATHEXCEL_CORPUS` at that directory — the walker takes directories, not files. To measure
a *baseline*, `git worktree add <scratch> <commit>` and run the same test there; the corpus paths
are environment-supplied, so both runs read identical inputs.

The corpus takes ~2.5 minutes; the media model adds ~7 more.

---

## Known limitations, recorded deliberately

Each is named where it was found, with assertions that fail if it is ever fixed.

- **Terminal-event rows.** A row holding literals until its final period and then a formula cannot
  be stated by a model with one rule per account. `Equity of PE Firm` is the one account Wharton
  still drops. (§17.7)
- **Time aggregates.** `IRR`, `NPV`, `MoM` reduce a whole timeline; a `ModelDefinition` is
  period-local by design. Why Phase 6 cannot recompute a sensitivity grid. (§20.2, §20.7)
- **No typed `sum` upstream.** BusinessMath's typed layer has `min`, `max`, `abs`; six of the
  twenty untyped definitions in emitted source are `SUM` or `AVERAGE`. (§19.7)
- **Rows below the axis, off the period columns** — `MOM` and `IRR` in Wharton's column C. (§20.6)
- **A derived axis costs one line.** It is placed on the line above its first agreeing run,
  because that line is the boundary later stages read the sheet against. That line is scanned by
  neither stage and becomes residue, and on a derived sheet it may hold real figures. (§22.3)
- **Graph performance.** 347s to build the media model's graph. Not yet investigated, and it
  matters more now than it did.

---

## How to work here

`CLAUDE.md` governs. In short: strict TDD (RED → GREEN → commit at each green); quality gate
`--check all --continue-on-failure`, **counting** errors and warnings rather than reading the
verdict line; doc housekeeping in the same commit; no temp probe files left in
`Tests/BusinessMathExcelTests/`.

Mistakes worth not repeating, from this session and the last:

- **Look before building.** A dependency graph was hand-rolled before checking that SwiftXLSX
  already shipped one. That same `DependencyGraph` is now the substrate for §23 — the cost of not
  looking compounds.
- **Never move a published tag.** `v0.11.0` was retagged in place after being consumed, which
  breaks SwiftPM's trust-on-first-use fingerprint downstream. Fixed as `v0.11.1`.
- **Measure the baseline, do not quote it.** §22.6's before column is a real run at `8f354c8`
  because the accounts figure had never been recorded. Two numbers quoted from memory into §21.3
  turned out wrong when checked — the media model's "100 of 104" is 91 of 104 when measured.
- **A test that changes what an existing test means is a bug in the test.** Widening a shared
  helper to include grid diagnostics quietly broke an assertion about *which stage* reports a
  missing axis. Add a second helper instead.
