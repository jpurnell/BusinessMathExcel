# Phase 8 — A model spans sheets

Measured on a 104-sheet media model: `Paid Cost - Data` feeds `Paid Cost - Input+Calc`, metric by
metric, and `… - Data` sheets feed a `Division Quarterly` consolidation. Cross-sheet edges are
**0.78% of 8.4M edges** and carry the model's entire architecture — lose them and you have 104
disconnected arithmetic islands.

Recognition today is per-sheet and names accounts bare. Two sheets with a `Revenue` row produce
two accounts called `Revenue`, and `validateUnits()` would report them as one account meaning two
things. That is a correctness defect on any multi-sheet workbook, not only a generality gap.

**Gate: a workbook whose data and calculations live on different sheets is recognized as one
model, and the Wharton 125-of-125 does not move.**

---

## Task 1 — An account knows its sheet

- [x] **RED** — `RecognizedAccount.sheet` carries where the account was read from. Provenance,
      always correct, never ambiguous — separate from the *name*, which is a modelling choice.
- [x] **RED** — single-sheet recognition is unchanged: names stay bare, and Wharton's 125-of-125
      holds. Qualifying every name would be noise on the common case and would rewrite every
      account on a sheet that has no ambiguity at all.
- [x] Commit.

## Task 2 — Recognizing a workbook

- [x] **RED** — `ExcelRecognizer.recognize(workbook:)` returns one `RecognizedModel` over every
      sheet that has a timeline, rather than one result per sheet.
- [x] **RED** — a name appearing on two sheets is qualified `Sheet!Name` on **both**, and reported
      as `duplicateAccountName`. Qualifying only the second would make which sheet got the bare
      name depend on workbook order.
- [x] **RED** — a name appearing on one sheet stays bare, so a workbook that happens to have
      several sheets reads no differently from one that does not.
- [x] **RED** — a sheet with no axis contributes nothing and is not an error. A page of prose in a
      workbook is not a failure of the workbook.
- [x] Commit.

## Task 3 — A reference crossing a sheet

- [ ] **RED** — `.sheetRef` resolves to the account it names on the other sheet, rather than being
      refused as a construct the translator cannot express.
- [ ] **RED** — a reference to a sheet not in the model is still refused, with the sheet named.
- [ ] **RED** — the `X - Data` → `X - Input+Calc` shape is recovered on a fixture built to that
      convention: the calculation sheet's accounts read the data sheet's.
- [ ] Commit.

## Task 4 — Measure

- [ ] Wharton: 125-of-125 unmoved, coverage unmoved. This is the regression bar.
- [ ] Corpus: how many workbooks now recognize across sheets that did not.
- [ ] The media model: does it recognize as one model, and how long does it take? 347 seconds to
      build its graph is already a standing problem; record whether this makes it worse.
- [ ] Record in the proposal and `master_plan.md`. Commit.

---

## Done when

- [ ] All four tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all`.
- [ ] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [ ] Move this file to `project/checklists/completed/`.
