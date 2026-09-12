# Session Summary — 2026-09-06

## The Excel oracle, and coverage from 72 functions to 160

Two things happened, and the first made the second measurable.

---

## 1. Excel's own cached values became the test

Every formula cell in a saved workbook carries the value Excel last computed for it. That is the
strongest oracle this project can have: produced by the specification itself, on 2,236 files
nobody wrote for us.

`ExcelOracleTests` now checks every formula we can evaluate against that value. The design
decision that made it usable: **precedents resolve to Excel's cached values, not to ours.** A
proposal had called cascade "the central design problem" — it does not arise, because each cell
is judged against Excel's inputs. One wrong cell is one finding rather than a hundred.

Agreement over 155,897 comparable cells:

| | |
|---|---|
| start of session | **46.6%** |
| whole-column references clipped to the sheet's data | 61.8% |
| absolute references keyed correctly | 62.8% |
| `NPV` accepting ranges; `_xll.`/`_xlfn.` resolved | 99.34% → 99.60% |
| lookups propagating errors; `XLOOKUP` | 99.62% |

### What the oracle found that reasoning did not

- **Absolute references resolved to nothing.** `CellRef.reference` renders `$D$66`, `value(at:)`
  keyed on it, and the store keyed on plain refs. Every absolute read came back empty. The
  `#DIV/0!` spike I had read as a cascade problem was this.
- **`HLOOKUP`'s 40 disagreements were not a lookup bug.** Every one was `ours #N/A, Excel #NAME?`
  — a lookup whose *key* was already an error. Answering `#N/A` says "looked and did not find"
  about a lookup that never happened.
- **`XIRR`: the finding was inverted.** We were 3.9e-8 from Excel. Evaluating `XNPV` at both
  rates: ours `2.18e-11`, Excel's `-0.00152`. **Ours is the root; Excel stopped early** — four
  times the accuracy Microsoft documents for itself. The tolerance band was widened only *after*
  establishing which answer was correct.

`MicrosoftSpecificationTests` (~105 tests) was built alongside it, taking the same rules from the
published reference so they run on a clean checkout without a corpus. Two suites that fail for
different reasons; a defect escaping both is rarer than one escaping either.

**ADR-001** records the rule they serve: Excel is the specification. Where Excel departs from a
published standard, match Excel under the Excel-facing name and expose the standard beside it,
named for the standard. The case that settled it: Excel's basis 1 is documented "actual/actual"
and is *not* ISDA ACT/ACT — a third of a percent apart on a real date pair.

---

## 2. Function coverage, and a matrix that had stopped telling the truth

Shipped this session: text and date functions chosen by corpus frequency (`SUBSTITUTE` at 230,092
calls, `FIND` at 102,168), the Foundation maths bridge, the BusinessMath statistics bridge,
`XLOOKUP`, `YEARFRAC` across every basis, `GETPIVOTDATA` refusing honestly, the legacy spellings,
and the Risk Solver markers.

Then the coverage matrix was checked and **163 of its rows were wrong.** It had not moved since
scaffolding, so it still described the pre-extraction package: 72 functions, every one attributed
to SwiftXLSX. For the document that scopes the work, that is the failure mode that matters — it
understates what exists and points effort at things already done.

It is now reconciled against `FunctionRegistry` itself, including the alias table. Of Excel's 519
documented functions: **160 have** (was 72), 57 bindable, 286 unreviewed.

`calls` and `books` were deliberately left alone and *marked* as unreconciled, because the recent
census disagrees with them and refreshing needs a full-corpus run that currently traps. Leaving
them unmarked would have been worse — they look current either way.

---

## Mistakes worth keeping

- **I predicted `VLOOKUP`'s failure mode three times and was wrong each time.** Writing a probe
  settled it in one run. The shaped-array work came from that probe, not from the reasoning.
- **The alias table's direction.** It reads `(alias, existing)` and was labelled
  `(modern, legacy)`. Four new entries silently did nothing. Renaming the fields was the fix.
- **Three census false positives, all from a Python shortcut** over raw XML: sheet names
  containing parentheses read as function calls, and `STDEV.S` reported missing — 2.2 million
  calls — because a grep for `name:` never saw the alias table. The Swift census walks the parsed
  AST and reads the real registry, so it cannot make either mistake.
- **I nearly wrote a remembered figure for `INTERCEPT`.** Computing gave 3.1667, not the 0.048387
  I had in mind. `SLOPE` agreeing on the same data is what confirmed the dataset was read right.

---

## State — everything green, everything pushed

| Repo | Tag | Tests | Gate |
|---|---|---|---|
| SwiftExcelCore | `v0.5.0` | 221 | 45/45, 0/0 |
| SwiftXLSX | `v0.22.0` + 1 | 771 | 45/45, 0/0 |
| SwiftExcelFunctions | `v0.5.0` + 16 | 782 | 45/45, 0/0 |
| BusinessMathExcel | `v0.7.0` + 37 | 568 | 45/45, 0/0 |

## Open, carried forward

1. **Two upstream BusinessMath day-count defects.** `thirty360` misses the NASD February rule
   (Excel 301/360, ours 302/360); `actual365`/`actual360`/`actualActual` gain an hour across a DST
   boundary. 2.11.0 shipped the new conventions but neither fix. These *are* the remaining corpus
   disagreements — 260 `IF`, 202 `YEARFRAC`, 142 `YEAR`, 140 `AND`, all the same two defects and
   their wrappers.
2. **The full-corpus census traps with signal 5.** The financial subtree (143 workbooks) runs
   clean. Unresolved, and it is what blocks refreshing the matrix's `calls`/`books`.
3. **`PsiOutput`'s arity.** Implemented `0…0` against 167 corpus calls all written `PsiOutput()`;
   the documented signature takes `cell_or_name, [instance], [PsiSixSigma]`. ADR-001 favours the
   published signature, but it changes what the function means.
4. **Nine Psi distributions** to bind when BusinessMath ships them. `PROPOSAL_psi_bindings.md`
   §7 holds the remaining questions: whether run-statistics (`PsiMean`, 23 workbooks) need a
   simulation engine, and what declarations like `PsiSenParam` evaluate to.
5. **Two releases are ripe** — SwiftExcelFunctions (16 commits) and BusinessMathExcel (37).
