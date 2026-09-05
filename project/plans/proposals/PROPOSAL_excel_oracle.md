# Proposal — The Excel oracle

**Status:** **Approved and built, 2026-09-05.** Shipped in SwiftExcelFunctions `0.5.0`+ as
`ExcelOracleTests` and `MicrosoftSpecificationTests`.
**Spans:** SwiftExcelFunctions (the harness), SwiftXLSX and SwiftExcelCore (fixes it finds)
**Filed here** because the corpus lives here and the harness reads it, though the code belongs
in SwiftExcelFunctions where the evaluator is.

---

## 1. Objective

**Objective:** Check every formula we can evaluate against the value Excel itself recorded for
it, and make that check routine rather than occasional.

**Master Plan Reference:** SwiftExcelFunctions master plan, Roadmap — *"The gate that is not
corpus-shaped: for any function, evaluating it must agree with the value Excel itself recorded.
Excel stores a cached result for every formula cell, so a workbook is a test oracle. That check
works on files nobody has seen, which is the difference between fitting a corpus and being
correct."*

That paragraph has been in the plan since the package was created and has never been built. This
proposal builds it.

---

## 2. Motivation

### What just happened

BusinessMath found that `DayCountConvention.thirty360` was missing the NASD February rule.
`YEARFRAC(2020-02-29, 2020-12-31)` answers 302/360 where Excel answers 301/360.

Neither side's tests could have caught it, and both sides' explanations are the same. Theirs:
*"the convention had only ever been checked against its own definition, never against a
spreadsheet."* Ours, from `BusinessMathBindingTests`:

```swift
/// 2026-01-01 to 2026-07-01 is half a year on a 30/360 basis: six months of
/// thirty days each, over 360.
XCTAssertEqual(try number("YEARFRAC", [start, end, .number(0)]), 0.5, accuracy: 0.001)
```

Clean dates, no month ends, no February — and the expected value derived from a reading of the
convention rather than from a spreadsheet. **Two implementations reasoning from one definition
agree with each other and are both wrong.** That is not a testing gap that more tests of the same
kind will close.

The bug was found in minutes once a cached value was compared. We hold roughly **549,000
formulas**, each carrying Excel's own answer, and check none of them.

### What "faithful to Excel" has to mean

Excel is the specification, including where it disagrees with a standard. `YEARFRAC(…, 1)` is not
ISDA ACT/ACT and must not be: a caller who writes basis 1 is asking what their spreadsheet says.

Where Excel and a published standard differ, **both are made available and each is named for what
it is.** The precedent is already set — BusinessMath now ships `actualActual` (the spreadsheet's
rule) alongside `isdaActualActual` (the standard), and the plain name went to the spreadsheet
because a caller arriving from one should not have to know there are two.

So a disagreement this harness finds has exactly three dispositions:

1. **Our bug.** Fix it.
2. **Excel doing something surprising but documented.** Match it, and record why in the function's
   doc comment so nobody "fixes" it back.
3. **Excel departing from a standard.** Match Excel under the Excel-facing name, and expose the
   standard beside it under a name that says which standard. Never silently pick one.

Category 3 is a callout, not a correction. The harness makes it visible; it does not decide.

---

## 3. Proposed Architecture

### New files

- `SwiftExcelFunctions/Tests/SwiftExcelFunctionsTests/ExcelOracleTests.swift` — the harness.
- `SwiftExcelFunctions/Tests/SwiftExcelFunctionsTests/OracleReport.swift` — classification and
  reporting types.
- `SwiftExcelFunctions/project/decisions/architecture_decisions.md` — the ADR from §11.

### Where it lives, and why not the gate

In **SwiftExcelFunctions' test target**, which already takes SwiftXLSX as a test-only dependency
for exactly this kind of seam. It is **not** a quality-gate checker:

- It needs private workbooks. The gate must pass on a clean checkout, and these files are
  teaching material and employer models that are not in the repository and never will be.
- It is a *measurement*, not a pass/fail. The first useful output is a number that goes down over
  time, not a boolean.

It runs under an environment variable, like the corpus tests already do, and skips without one.

### Shape

```
workbook ─► DependencyGraph.evaluationOrder ─► evaluate each formula
                                                     │
                                        compare to its cached <v>
                                                     │
                              classify ─► agree / differs / refused / threw
                                                     │
                                    attribute to the first cell in the chain
```

---

## 4. API Surface

```swift
/// One cell's verdict.
struct OracleFinding {
    enum Outcome {
        case agreed
        case differed(ours: CellValue, excel: CellValue)
        case refused(ExcelError)          // we answered an error, Excel had a value
        case threw(String)
        case inherited(from: CellAddress) // differs only because a precedent did
    }
    let cell: CellAddress
    let formula: FormulaAST
    let outcome: Outcome
}

/// What a run found, aggregated for reading.
struct OracleReport {
    let comparable: Int
    let agreed: Int
    var agreement: Double { comparable == 0 ? 1 : Double(agreed) / Double(comparable) }

    /// Root causes only — findings whose precedents all agreed.
    let roots: [OracleFinding]

    /// Roots grouped by the functions their formulas call, which is what turns a
    /// list of cells into a list of things to fix.
    let byFunction: [String: Int]
}
```

---

## 5. MCP Schema

N/A for the harness itself: it is a test target, not an API, and nothing calls it over MCP.

The **report** is worth a schema, because "which functions disagree with Excel, and how often" is
exactly the question an assistant should be able to ask:

```json
{
  "comparable": 15791,
  "agreed": 9915,
  "agreement": 0.628,
  "byFunction": { "YEARFRAC": 12, "SUMPRODUCT": 13 },
  "roots": [
    {
      "cell": {"sheet": "Assumptions", "ref": "H113"},
      "outcome": "differed",
      "ours": {"kind": "number", "value": 0.025},
      "excel": {"kind": "number", "value": 0.08959009469153514}
    }
  ]
}
```

- `agreement` (number): `agreed / comparable`, 0–1.
- `byFunction` (object): function name → count of root findings whose formula calls it.
- `roots[].outcome` (string), exhaustively: `"agreed"`, `"differed"`, `"refused"`, `"threw"`,
  `"inherited"`.

---

## 6. Constraints & Compliance

**Concurrency:** the report types are immutable value types of `Sendable` members. The harness is
single-threaded; parallelising it is a later question and needs the graph to be partitioned first.

**Determinism:** volatile functions (`RAND`, `RANDBETWEEN`, `NOW`, `TODAY`) can never agree with a
cached value and must be excluded by name, not by tolerance. This package supplies no randomness
unless given a source, so `RAND()` answers `#VALUE!` here and would otherwise show up as a
permanent, meaningless failure.

**Safety:** no force unwraps; a workbook that fails to open is skipped and counted, not fatal.

**Bounded:** `matrix(in:)` clips grid-spanning ranges to the sheet's data (SwiftExcelCore 0.4.0),
so a whole-column reference costs what the sheet costs. Evaluating a 568,000-cell workbook is
still the largest thing this project does and needs a per-workbook time budget.

**Privacy:** the workbooks are private. The harness prints cell references, formulas and values,
which **is** their content — so its output must not be committed. Only aggregate numbers go into
commit messages or docs.

---

## 7. Source & API Compatibility

**Breaking changes:** none. This is a new test file.

**Incremental adoption:** yes, and required. The harness is useful at 60% agreement; it does not
need to reach 100% to earn its place, and it never will reach 100% while volatile functions and
float formatting exist.

**What it will cause:** fixes in three packages, each following the normal release path. The two
already identified in §12 are in SwiftXLSX and are source-compatible.

---

## 8. Backend Abstraction

N/A. The work is dominated by XML parsing and dictionary lookups, not arithmetic.

---

## 9. Dependencies

**Internal:** `FormulaEvaluator`, `WorkbookValueProvider`, `Workbook.namedRanges`,
`DependencyGraph.evaluationOrder` — all of which exist.

**External:** none. SwiftXLSX is already a test-only dependency of this target.

---

## 10. Test Strategy

**Reference truth:** Excel's own cached `<v>` for each formula cell. This is the strongest oracle
available to the project — it was produced by the specification itself, on files nobody wrote for
us.

**Measured baseline.** Three corpus workbooks, 15,791 comparable cells, before any of this is
built:

| | cells |
|---|---|
| agree | 9,915 |
| differ | 2,670 |
| we answered an error where Excel had a value | 3,161 |
| evaluation threw | 45 |
| Excel itself cached an error | 3,174 |
| **agreement** | **62.8%** |

Of the errors we produce: `#NUM!` 1,664, `#DIV/0!` 1,314, `#REF!` 135, `#VALUE!` 48.

**Categories the harness must separate**, in the order they matter:

- *Root vs inherited.* See §12 — without this the count is meaningless.
- *Volatile.* Excluded by function name.
- *Float agreement.* Relative tolerance, not absolute: Excel stores `0.060000000000000005` and
  `-1.1224406979409424e-239`. A fixed epsilon is wrong at both ends.
- *Type coercion.* Excel caches booleans as `0`/`1` and blanks as absent. `blank` vs `number(0)`
  agrees; `text("NA")` vs `number(0)` does not.
- *Unimplemented functions.* Counted separately from wrong answers — a missing function is a
  known gap, a wrong answer is a defect.

**Validation trace.** The harness itself needs a test, and there is a ready-made one:
`Long Acre Team 2013 Probabilistic All.xlsx / Lease Renewal!L77` is
`YEARFRAC(2020-02-29, 2020-12-31)`, Excel caches `0.83611111111111114`, and we answer
`0.8388888888888889`. A harness that does not report that cell is broken. It becomes the
harness's own fixture, and it will flip to agreeing when BusinessMath 2.11.0 lands — which also
tests that the harness notices a fix, not only a break.

---

## 11. Architecture Decision Review

**ADR check:**
- [x] Reviewed — `SwiftExcelFunctions/project/decisions/` is empty (`.gitkeep`).
- [x] Supersedes an existing ADR? No.
- [x] Amends one? No, but it **operationalises** a roadmap line that has been decorative since
      the package was created.
- [x] New ADR required? **Yes.**

**New ADR draft:**
- **Title:** Excel is the specification; standards are exposed beside it, never instead of it
- **Category:** testing
- **Key decision:** Correctness is agreement with the value Excel recorded, measured against real
  workbooks. Where Excel departs from a published standard, we match Excel under the Excel-facing
  name and expose the standard under a name that says which standard — as
  `actualActual` / `isdaActualActual` already does.

---

## 12. Adversarial Review

**Strongest case for a different approach.**
Write more unit tests, but from Microsoft's published algorithms rather than from reasoning, and
skip the harness. It is cheaper, it produces small readable tests, and it would have caught the
February bug — the NASD rule is documented. A reviewer would be right that the harness is a large
apparatus for a problem a careful reading of the spec also solves.

The counter is coverage and honesty. There are 519 documented functions, each with edge cases we
would have to think of; the harness tests the ones real models actually use, on inputs real people
actually wrote, without anyone imagining them. The February date was not a case anyone would have
invented — it arrived because a lease happened to start on a leap day.

**Where this design is most likely wrong: cascade.**
A wrong cell poisons everything downstream, so a raw disagreement count is not a defect count. The
baseline shows this directly: fixing reference resolution moved agreement 46.6% → 61.8%, and then
resolving named ranges moved it to 62.8% **while `#DIV/0!` rose from 79 to 1,314** — more formulas
evaluated, and inherited wrongness from upstream. 2,670 disagreements might be twenty root causes.

Mitigated by evaluating in `DependencyGraph.evaluationOrder` and marking a finding `inherited`
when any precedent already differs. If that attribution is wrong, every number this harness
produces is wrong, so it is the part to build first and test hardest.

**What an experienced critic would say.**
"You are proposing to measure against files you cannot commit, in a check that cannot run in CI,
producing a percentage that will be dominated by your own harness's bugs for the first month."

All true, and the baseline already demonstrates the last part: my first two measurements were
wrong because the probe passed an empty name resolver and did not resolve formula references. We
proceed because the alternative is the status quo, in which a shipped function was a day out for
four months and only an unrelated session's reference workbook found it.

---

## 13. Alternatives Considered

**Alternative 1 — spec-derived unit tests, no harness.**
- *Advantage:* cheap, readable, runs in CI, no private files.
- *Disadvantage:* tests only the cases someone thought of; the February case was not one.
- *Why not preferred:* it is the same method that failed, executed more carefully. Worth doing
  *as well*, not instead.

**Alternative 2 — generate a reference workbook and compare, as BusinessMath did.**
- *Advantage:* committable, small, CI-friendly, and it worked for them.
- *Disadvantage:* requires a spreadsheet application to produce the values, so it cannot be
  regenerated automatically, and it tests the cases we choose — which is Alternative 1 with extra
  steps.
- *Why not preferred:* complementary. Their grid found the bug because they thought to include
  month ends. Ours would find it because a real lease started on one.

**Alternative 3 — make it a quality-gate checker.**
- *Advantage:* nothing rots; a regression fails the build.
- *Disadvantage:* the gate must pass on a clean checkout, and these workbooks cannot be committed.
  A checker that silently skips is worse than no checker, because it reports green.
- *Why rejected:* run it as a measurement, and only promote a specific finding into a normal
  regression test once it has a small reproducible fixture — as `testTheFebruaryEndOfMonthRule`
  already does.

---

## 14. Future Directions

- **A committed fixture set** distilled from findings: each root cause reduced to a two-cell
  workbook that *can* be committed, which would let a subset run in the gate.
- **Function-level scoring** — agreement per function, so the coverage matrix gains a "verified
  against Excel" column beside "implemented".
- **Bidirectional check:** write a workbook, reopen it, evaluate, and compare to what we intended
  — which would have caught the cached-error loss without an integration test.
- **Sharing the harness with BusinessMath**, whose `bindable` list is the same "computed but never
  compared" category from the other side.

---

## 15. Open Questions — answered

1. **Is `inherited` attribution reliable enough to report root counts?**
   **The question dissolved.** Precedents resolve to *Excel's* cached values, not to ours, so
   every formula is judged against ground-truth inputs and each disagreement is a root by
   construction. There is no cascade to attribute. §12 was wrong to call this the central design
   problem — the `#DIV/0!` surge that suggested cascade was the absolute-reference bug below.

2. **What tolerance counts as agreement?**
   Relative `1e-9` with an absolute floor of `1e-12`. Excel stores about fifteen significant
   digits and a `Double` carries seventeen, so the relative bound is far looser than rounding
   noise and far tighter than any real disagreement — those are whole units apart. The floor
   handles comparison against exact zero, where a relative test is undefined, and the numerical
   dust real models leave: the corpus holds a cached `-1.1224406979409424e-239`, a zero that took
   a long route, and calling it different from zero would be true and useless.

3. **How is an error on both sides treated?** Agreement. A model full of `#DIV/0!` is a model
   whose author left it that way, and reproducing that is the job. 2,723 cells in the first run.

4. **Where does the corpus path live?** **Not** `.quality-gate.yml` — that file is the gate
   binary's own schema and rejected the key outright: *"sets 1 key this version does not
   recognise… advisory in this release and will become an error."* Borrowing a config file works
   right up until its owner validates it. The roots live in a sibling `.excel-corpus`.

5. **Per workbook or per sheet?** Per workbook, and the whole sweep is **opt-in**. A plain
   `swift test` picking up the roots ran past ten minutes before the gate was involved, and the
   gate runs `swift test`. `BUSINESSMATHEXCEL_ORACLE=1` or `BUSINESSMATHEXCEL_CORPUS` enables it.

### A sixth, which the corpus answered rather than asked

**Risk Solver's `Psi*` values are not oracles.** They are Monte Carlo: a cached
`PsiTriangular(…)` is one sample from one run, and `PsiMean(…)` a statistic *of* that run, with
no published seed. Nothing reproduces them. Counting them as disagreements would hold the
agreement number down by something no work could fix, which is the fastest way to make a
measurement worth ignoring — so they are excluded alongside the volatile functions.

What those cells *can* give is structural and is reproducible: which functions appear, with how
many arguments, in what shapes. That feeds the binding signatures. The values cannot be matched
and the implementation specification has to be the guide, exactly as the master plan's "Known
traps" section already assumes.

---

## What building it found

Three defects, none of them on anyone's list, all found by comparing against Excel rather than
against ourselves:

- **Every absolute reference resolved to an empty cell.** `CellRef.reference` renders the `$`
  markers and `Worksheet.value(at:)` keyed the store with it, while the store is keyed by the
  plain reference the file writes. `=D22/$D$66` answered `#DIV/0!`, silently. SwiftXLSX 0.22.0.
- **`NPV(rate, B4:B8)` answered `#VALUE!`.** Every argument went through `requireNumber`, so any
  range failed — and two of Microsoft's own three worked examples use a range. 126 corpus cells.
- **`actual365` and `actual360` gain an hour across a daylight-saving boundary**, because they
  measure elapsed time through a local-zone calendar rather than counting civil days. Invisible
  in UTC, invisible without DST, and `thirty360` is unaffected. Upstream in BusinessMath.

**Agreement after the first two: 99.34%**, over 30 workbooks and 156,176 comparable cells. The
62.8% baseline in §10 was mostly the harness's own defects, which is what §12 predicted and the
reason that section's warning was worth writing even though its diagnosis was wrong.

## 16. Documentation Strategy

**Documentation type:** Narrative article required.

- Combines 3+ APIs? **Yes** — evaluator, dependency graph, workbook reader.
- 50+ lines to explain? **Yes** — cascade attribution alone needs a worked example.
- Needs background? **Yes** — why a cached value is an oracle, and why agreement will never be
  100%, both need saying once so the number is not misread as a grade.

**Article name:** `MeasuringAgainstExcel.md`, in SwiftExcelFunctions' DocC catalogue.

---

## Approval

- [x] §15 Q1 answered — dissolved rather than decided; there is no cascade to attribute
- [x] Tolerance rule decided (§15 Q2) — relative 1e-9, floor 1e-12
- [ ] ADR drafted into `SwiftExcelFunctions/project/decisions/`
- [x] Agreed that the harness is a measurement, not a gate checker
- [x] **Belt and suspenders**: `MicrosoftSpecificationTests` runs in the gate, from the published
      reference, so the work can be inspected without running a sweep against private files. It
      found the `NPV` and daylight-saving defects on the day it was written.
