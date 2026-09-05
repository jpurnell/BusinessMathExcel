# Session Handoff — 2026-09-05

Resume here. Shaped arrays shipped across all four packages; the previous handoff's next step
(bind the remaining functions, measure YEARFRAC's basis) is done.

---

## The next step, concretely

**Measure what range sizes the corpus actually passes to a lookup**, then confirm or move
`CellMatrix.maximumCells`.

This is the one thing the shaped-arrays work left undone, and it is named in the proposal's own
adversarial review as the most likely place the change regresses something. Reading a range now
keeps its blanks, so a sparse range costs what its *rectangle* costs rather than what its
contents do. A range that used to be cheap because it was mostly empty is now proportional to its
area, and above 262,144 cells `matrix(in:)` refuses and the formula answers `#VALUE!`.

The bound was chosen by reasoning — a whole column is 1,048,576 and must be refused, a whole row
is 16,384 and must not be — not by measurement. Nothing in 2,153 tests hits it. Whether a real
workbook does is unknown.

```
BUSINESSMATHEXCEL_CORPUS="<roots>" swift test --filter Corpus
```

Corpus roots are not recorded anywhere (the workbooks are private). One is
`~/Documents/Tuck/Academic/2012-2013/3. Spring/pdm/4. Long Acre/`; the Hulu model with the only
known `TRANSPOSE` formulas is `~/Documents/Career/Hulu/News Vertical/Originals/`.

---

## State — everything green, everything pushed

| Repo | Tag | Tests | Gate |
|---|---|---|---|
| SwiftExcelCore | `v0.3.0` | 198 | 45/45, 0/0 |
| SwiftXLSX | `v0.15.0` | 743 | 45/45, 0/0 |
| SwiftExcelFunctions | `v0.3.0` | 646 | 45/45, 0/0 |
| BusinessMathExcel | `v0.7.0` + 3 | 566 | 45/45, 0/0 |

### Where the numbers are

- **Corpus formulas that parse: 99.997%** — 17 unparsed of 549,059, from 292,437 at the start.
- **Corpus function calls the registry can answer: 99.93%** — 869,307 of 869,908.
- Remaining outside the Psi family: none. `XIRR` and `TRANSPOSE` both shipped.

---

## What 0.3.0 changed, and why it matters more than it looks

`CellValue.array` carries a `CellMatrix` — a rectangle that knows its own `rows` and `columns`,
with empty cells kept as `.blank` in place. It began as "can we do TRANSPOSE" and turned into a
correctness fix, because three shipped functions were guessing dimensions the type could not
state:

| | Excel | Before |
|---|---|---|
| `VLOOKUP("b", A1:D3, 3, FALSE)` | `"b3"` | `#N/A` |
| `HLOOKUP` on a four-row table | `"b3"` | `"a4"` |
| `INDEX(block, 2, 1)` | `4` | `2` |
| `INDEX(A1:A4, 3)` with `A2` empty | `30` | `40` |
| out-of-bounds index, ×3 | `#REF!` | `#N/A` |

VLOOKUP is the corpus's most-called function at 87,773 calls. It inferred its table width by
testing which divisors came out even — safe at `col_index_num = 2`, which is why it survived.

Full reasoning, including what implementation found that the proposal missed, is in
`project/plans/proposals/PROPOSAL_shaped_arrays.md`.

---

## What is waiting on the BusinessMath session

**Two day-count conventions, now known to be low value.** `YEARFRAC` is bound for Excel's bases
0, 2 and 3. BusinessMath lacks actual/actual (basis 1) and European 30/360 (basis 4). Measured
since: **all 3,425 corpus `YEARFRAC` calls pass two arguments**, so every one takes basis 0,
which exists. Both missing bases answer `#NUM!` and are reached by nothing. When they land,
switch the two branches in `BuiltinBindingFunctions.yearfrac`.

**Their generator advice was taken.** `SeededRandomSource` is now generic over the stdlib's
`RandomNumberGenerator`, merely defaulting to `DeterministicRNG`, so nothing of theirs can move
under us. `RANDBETWEEN` draws an unbiased integer via `next(upperBound:)` instead of scaling a
double across the span.

**BusinessMath is read-only from here.** SwiftExcelFunctions pins it `exact: "2.9.0"` from
GitHub, so that session's working tree cannot affect this build — and nothing in this session has
ever written to their repo. Keep it that way while they are working.

The Psi distributions are the only block left outside the registry.

---

## The family, and why it is shaped this way

```
SwiftExcelCore  ←  SwiftXLSX            syntax and storage
       ↑        ←  SwiftExcelFunctions  semantics  →  BusinessMath
                        ↑
                BusinessMathExcel        model translation
```

Full reasoning in `project/plans/proposals/PROPOSAL_swift_excel_architecture.md`. The short version:
SwiftXLSX held four things that change for four different reasons, and the function library was one
of them.

Function groups are **Logic, DateTime, Navigation**, plus Math, Stats, Text, Aggregation, Array
and Bindings. Logic rather than Branching: only three of its fourteen functions branch, and the rest
are operators and predicates that feed one.

---

## Decisions worth not relitigating

- **Excel's randomisation is not imitated**, because it cannot be — Excel exposes no seed, so there
  is no sequence to match. Only the contract is observable. The package supplies *no* randomness;
  the caller passes a source, and without one `RAND()` answers `#VALUE!`. Deterministic by
  construction rather than by justification. One divergence: with a seeded source `RAND()` stops
  being volatile.
- **A rectangle states its own shape.** `CellValue.array` carries a `CellMatrix`, and a range
  read keeps its blanks in place. Do not "tidy" the blanks away: their absence is what made
  `INDEX` count past the end of its own range, and what made `COUNTBLANK` unwritable. The
  deprecated `values(in:)` still filters them, and still should.
- **Spilling is deliberately absent.** Evaluation yields one value per cell. `TRANSPOSE` is
  correct nested inside another formula and has nowhere to go on its own — which means the one
  corpus workbook using it still will not evaluate. That is known, and judged not worth the
  change to the evaluator's contract for a single function.
- **References never became values.** `CellValue` has no `.reference` case and does not need one:
  measured across 549,059 formulas, reference functions nest inside one another **zero** times.
  `OFFSET` is always three arguments, so it names one cell and returns a value.
- **An omitted argument is `FormulaAST.missing`**, not 0 and not `""` — both are values a formula
  could have supplied deliberately. It evaluates to `.blank`, so each function applies its own
  default. `ADDRESS(r, c, 1, , "Sheet")` is 20,978 corpus calls that depend on this.
- **Whole-column ranges are ordinary ranges** over Excel's grid, needing no new AST case — but
  `DependencyGraph` intersects any range over 4,096 cells with the cells that exist, or `$B:$G`
  would expand to 6.3 million addresses.

---

## How to work here

`CLAUDE.md` governs. Strict TDD, commit at each green, quality gate `--check all
--continue-on-failure` with errors and warnings **counted** rather than read off the verdict line.

Mistakes from this session worth not repeating:

- **Look before building.** A 519-row coverage matrix was built against BusinessMath's 21-name
  registry before anyone checked whether SwiftXLSX had its own. It had 73.
- **Never move a published tag.** `v0.11.0` was retagged in place after being consumed and broke
  SwiftPM's fingerprint downstream.
- **Measure the baseline, do not quote it.** Two figures quoted from memory into a proposal were
  wrong when finally checked.
- **Do not write test fixtures from memory.** Eight date tests failed on a serial number invented
  rather than confirmed; 2026-09-04 is 46269, not 46265. The implementation was never at fault.
- **Assert membership, not counts.** `all.count == 6` says something changed without saying what,
  and fails identically whether a function arrived or went missing.
- **`--no-verify` hides things.** A skipped hook left the SwiftXLSX DocC catalogue advertising
  eleven functions the package no longer had.
- **The gate's justification comments go on the line directly above the declaration**, not above
  the property they explain.
- **Predict, then run it.** Three guesses about how VLOOKUP failed were wrong — a 3-column table
  recovers, and `col_index_num = 2` is inherently safe whatever width is assumed. Only writing
  the probe found the real shape of the bug, and then found two more nobody had predicted.
- **A coverage number is not a correctness number.** The registry answered 99.93% of corpus calls
  while three of its functions returned wrong values. Registered and wrong scores identically to
  registered and right.
