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
