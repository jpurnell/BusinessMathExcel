# Test Fixtures

## Wharton-LBO-Practice-Model.xlsx

The reference workbook for import-fidelity and recognizer-coverage measurement.
Published by Penn Career Services as the "LBO Practice Model".

It is **not checked in** — it is third-party educational material, and vendoring it
here would redistribute it. Fetch it before running the measurement tests:

```sh
curl -sSL -o Tests/Fixtures/Wharton-LBO-Practice-Model.xlsx \
  "https://cdn.uconnectlabs.com/wp-content/uploads/sites/74/2023/08/Career-Services-LBO-Example-Jun23_vFF-1.xlsx"
```

Expected `sha256`: `bd6c774ed74ffd868d9886c4cb9170dab2065a57ec5364e8ce6d01fcfc9bcd63`

Tests that need it skip when it is absent, so the suite stays green without it.

**Why this workbook.** Its published results — IRR 24.67%, MoM 3.01 — are reproduced
independently by orcaset's `examples/paper-lbo`, giving a second source for the
numbers. `ANSWER KEY!C64` carries the cached IRR, so the file identifies itself.

## The corpus

`Wharton-LBO-Practice-Model.xlsx` is a **fixture**: every recognition rule was measured against
it. 85% coverage there says how well the rules fit the file they were fitted to — which is worth
knowing, and is not evidence of generality. The first unseen workbook tried against it recovered
18%.

`CorpusMeasurementTests` is the **control**. Point it at directories of real workbooks and it
reports what recognition and the dependency graph each recover:

```
BUSINESSMATHEXCEL_CORPUS="/path/one:/path/two" swift test --filter Corpus
```

Unset, every test in it skips. Nothing in the corpus is checked in: it is teaching material and
employer files, read locally and never committed. Point the variable at your own workbooks — the
measurement is about whichever files you have, not about a particular set.

It takes a couple of minutes over a large corpus, which is the other reason it is opt-in.

**What it asserts, and what it only reports.** It asserts one thing: a sheet holding formulas
yields a dependency graph. That is the claim the graph projection rests on — *what does this cell
read* is answerable from any sheet, without first deciding what kind of model it is. Everything
else is printed, deliberately: a coverage threshold here would be tuned to whatever corpus is
configured, and the fixture already demonstrates where that leads.
