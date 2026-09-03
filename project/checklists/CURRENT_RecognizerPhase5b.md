# Phase 5b — Unit Inference

Design: `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` §18.
Needs **SwiftXLSX 0.9.0** (`Worksheet.style(at:)`), released 2026-09-02.

`TypedSourceWriter` stays gated on `TypedModelAuthoring.md` Phase 3 upstream and is **not** in
this checklist.

**Gate: every `$` account is money, every `%` account is a proportion, nothing formatted
`General` is given a unit, and the unitless count is reported rather than minimised.**

---

## Task 1 — Formats reach recognition

- [x] **RED** — `ModelImporter.ImportResult` carries each cell's number format string.
- [x] **RED** — `SheetGrid` carries it, so the stages that interpret can see it.
- [x] A workbook with no styles yields no formats and no diagnostics.
- [x] Commit.

## Task 2 — Dimension from format

- [x] **RED** — `"$"#,##0` and `[$$-409]* #,##0.0` are money; `0.0%` is a proportion;
      `0.00"x"` is a multiple, hence `ratio`; `"Year"\ #` is duration; `General` is nothing.
- [x] **RED** — a `%` inside a literal — `"100% owned"` — is not a proportion.
- [x] Commit.

## Task 3 — The label sharpens, and never invents

- [x] **RED** — a proportion labelled `Interest Rate` is `rate`; one labelled `EBITDA margin` is
      `ratio`; one labelled `Debt` is `ratio`, because where both fit the weaker claim wins.
- [x] **RED** — a label alone, with no format, gives **no** unit. The label is a modifier of
      evidence, not evidence.
- [x] **RED** — cells in one account stating different dimensions give `unitConflict` and no unit.
- [x] Commit.

## Task 4 — Through the recognizer, and measured

- [ ] **RED** — `RecognizedAccount.unit` is populated; an account whose cells state nothing gets
      `nil` and `unitInferenceFailed` at `info`, not `warning`.
- [ ] Report on Wharton: accounts by unit, and how many are unitless.
- [ ] Check every `$`-formatted account came out money and every `%` one a proportion. If any did
      not, name it.
- [ ] The 125-of-125 agreement must not move.
- [ ] Record in the proposal's phasing table and `master_plan.md`. Commit.

---

## Done when

- [ ] All four tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all`.
- [ ] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [ ] Move this file to `project/checklists/completed/`.
