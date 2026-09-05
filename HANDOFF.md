# Session Handoff — 2026-09-05

Resume here. The previous handoff (Phase 9 → the graph reorientation) is superseded; its content
is in `project/plans/proposals/PROPOSAL_spreadsheet_graph.md` §23 and the checklists.

---

## The next step, concretely

**Bind the remaining functions, and measure YEARFRAC's basis first.**

The morning's work is bindings — the BusinessMath session has been implementing distributions and
sampling overnight, and each one that lands is a name SwiftExcelFunctions can now reach.

**Do this before anything else** (about ten minutes, and it may save someone a day):

```
BUSINESSMATHEXCEL_CORPUS="<roots>" swift test --filter testHowTheReferenceFunctionsAreCalled
```

Add `YEARFRAC` to that test's function list first. It reports call arities, and the question is
**which basis the corpus's 3,425 YEARFRAC calls use**. If they are all basis 0 the two missing
day-count conventions are not urgent at all; if they are basis 1, they are the single most
valuable thing on the list.

---

## State — everything green, everything pushed

| Repo | Tag | Tests | Gate |
|---|---|---|---|
| SwiftExcelCore | `v0.2.0` | 170 | 45/45, 0/0 |
| SwiftXLSX | `v0.14.0` | 743 | 45/45, 0/0 |
| SwiftExcelFunctions | `v0.2.0` + 6 commits | 613 | 45/45, 0/0 |
| BusinessMathExcel | — | 566 | 45/45, 0/0 |

SwiftExcelFunctions is **unreleased since 0.2.0** — six commits of function work waiting for a
`0.3.0` tag whenever it suits.

### Where the numbers are

- **Corpus formulas that parse: 99.997%** — 17 unparsed of 549,059, from 292,437 at the start.
- **Corpus function calls the registry can answer: 99.93%** — 869,307 of 869,908.
- Remaining outside the Psi family: `XIRR` (2 calls), `TRANSPOSE` (1 call).

---

## What is waiting on the BusinessMath session

Two messages sent, neither blocking, both worth checking for a reply.

1. **Two day-count conventions.** `YEARFRAC` is bound for Excel's bases 0, 2 and 3.
   BusinessMath lacks actual/actual (basis 1) and European 30/360 (basis 4), which Justin called
   an oversight to fix upstream rather than work around here. Both return `#NUM!` today, and both
   are additive enum cases — when they land, switch the two branches in
   `BuiltinBindingFunctions.yearfrac` and delete the note.

2. **Whether `DeterministicRNG` is the supported public entry point** for a seeded stream, or an
   implementation detail. `SeededRandomSource` binds to it; redirecting is easy.

**BusinessMath is read-only from here.** SwiftExcelFunctions pins it `exact: "2.9.0"` from GitHub,
so that session's working tree cannot affect this build — and nothing in this session has ever
written to their repo. Keep it that way while they are working.

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

Function groups are **Logic, DateTime, Navigation**, plus Math, Stats, Text, Aggregation and
Bindings. Logic rather than Branching: only three of its fourteen functions branch, and the rest
are operators and predicates that feed one.

---

## Decisions worth not relitigating

- **Excel's randomisation is not imitated**, because it cannot be — Excel exposes no seed, so there
  is no sequence to match. Only the contract is observable. The package supplies *no* randomness;
  the caller passes a source, and without one `RAND()` answers `#VALUE!`. Deterministic by
  construction rather than by justification. One divergence: with a seeded source `RAND()` stops
  being volatile.
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
