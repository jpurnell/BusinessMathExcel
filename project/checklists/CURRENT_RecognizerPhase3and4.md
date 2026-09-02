# CURRENT: Recognizer Phases 3 and 4 — translation, lag, and the cycle

**Started:** 2026-09-01
**Proposal:** `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` (§3, §4, §10)
**Depends on:** BusinessMath 2.8.0 — the function registry and `PeriodDriver`. Both shipped.

Phase 2 stopped at *which cells belong together*. This is *what they compute*.

**TDD per project rules: failing test first, minimum code, refactor. Commit at each green state.**

---

## Task 1 — Lag decomposition

The heart of Stage 3, and the reason the grammar could stay period-local. A reference's lag is
its offset along the axis from the cell being defined — mechanical, because `SheetGrid` knows
where every cell sits.

| Excel | Lag | Becomes |
|---|---|---|
| `D6 = C6*1.15` | 1 | a `Rollforward` plus a period-local formula |
| `D9 = D6-D7` | 0 | period-local, no rollforward |
| `D12 = C12+D10` | mixed | split: the prior term carries, the current term stays |
| `D5 = $B$2` | off-axis | a scalar input, constant across periods |

- [x] **RED** — a lag-0 formula translates with no rollforward.
- [x] **RED** — a lag-1 self-reference yields exactly one `Rollforward` and a period-local formula.
- [x] **RED** — a mixed formula splits, keeping both halves.
- [x] **RED** — a reference off the period axis becomes a scalar input, not a lagged one.
- [x] **RED** — **lag 2 or a forward reference emits `.unsupportedLag` and drops to residue.**
      Wharton needs neither, and guessing at them is exactly the plausible-wrong-answer this
      project refuses.
- [x] **GREEN** — implement. Commit.


**Decided while implementing.** A reference reaching back one period is rewritten to a distinct
`"<account> Opening"` account rather than to the account itself. An account cannot open at its
own close within a period — that is a self-reference the dependency graph would refuse, and
rightly. The carry is what relates the two, and it lives in the rollforward where it can be read.

A reach of two or more is refused with the arithmetic spelled out in the message: how many
periods it reaches, and by how much a model would be wrong if the reach were treated as one.

## Task 1b — The at-close column (added after measuring)

Not in the original plan, and found by checking the IRR before building on it.

Wharton's header row reads `D27 = "Closing"`, `E27 = 2023` … `J27 = 2028`, and its IRR range is
`D61:I61` — the transaction close plus five years. Column D holds values that belong to a series
but to **no period**: the equity cheque written at close.

Phase 2 anchored binding on the period axis, deliberately, and that decision stands — it
dissolved the blank-run question and handles the label-gap-values layout every model uses. But it
assumes every value in a series sits in a period column, and an at-close column breaks that.
Bound to period columns alone, the equity row is `[0, 0, 0, 0, 240.98]` with no investment in it,
and a return computed from that is not merely wrong but plausible.

- [x] `PeriodAxis.Anchor` — position, label, and the heading cell it came from.
- [x] **The discriminator is what lies below the heading, not the heading itself.** A label column
      holds words; an anchor column holds money. Matching on vocabulary (`Closing`, `At Close`,
      `Initial`) would be a guess and would grow a phantom period out of any sheet whose row
      labels happen to sit against the timeline.
- [x] A heading that parses as a year is a period, not an anchor — it would already be on the axis.
- [x] `LabeledSeries.anchorCell`, kept **out** of `cells` so the period alignment Phase 2 promised
      is untouched. A consumer that needs the at-close value prepends it knowingly.
- [x] **Verified end to end: IRR 24.67% and MoM 3.01**, reached through recognition rather than by
      reading the sheet's cached answer.
- [x] Commit.

## Task 2 — Formula translation

`NodeFormula` to a string the upstream `FormulaEvaluator` will actually parse.

- [x] **RED** — arithmetic, comparisons and calls round-trip through `FormulaEvaluator.tokenise`.
- [x] **RED** — a name with `&`, `/` or spaces survives via the bracketed form.
- [x] **RED** — **an unregistered function emits `.unregisteredFunction` and goes to residue.**
      It must **not** be dropped, and its value must **not** be replaced by the cell's cached
      number. Substituting a plausible figure for a formula we cannot evaluate is the precise
      failure this project exists to avoid.
- [x] **GREEN** — implement against the real registry, not a guess at it. Commit.


**Verified through the upstream parser, not against my own expectations.** Each translated string
is run back through `FormulaEvaluator.accountNames(in:)`, which parses it and throws if it cannot.
A translator checked only against what its author expected is a translator that agrees with
itself; this one has to satisfy the thing that will actually read its output.

That is also what proves the fix made upstream during 2.8.0 — a function name is no longer
reported as a required account, so `MIN(cash, debt)` reads two accounts rather than three.

The registry is consulted by `Function(rawValue:)` against the shipped enum rather than a list
copied into this file, so a name registered or withdrawn upstream moves this with it instead of
leaving the two to drift.

## Task 3 — Stage 4 assembly

- [ ] `RecognizedModel`: periods, accounts, residue — plain `Sendable` data, no construction.
- [ ] `RecognizedAccount`: name, formula or values, provenance. **Provenance is never empty.**
- [ ] `Residue`: what could not be translated, and why.
- [ ] **RED** — every account's provenance cells actually hold what the account claims.
- [ ] Commit.

## Task 4 — `ModelBuilder`

- [ ] Plan to `ModelDefinition`, **throwing**: recognition never throws, materialization does.
- [ ] **RED** — an unresolved reference, a duplicate account and an unparseable formula each
      throw a named error rather than producing a partial model.
- [ ] Commit.

## Task 5 — The golden path, end to end

- [ ] **RED** — the proposal's validation trace: `B6 = "Revenue"`, `C6 = 1000000`,
      `D6 = C6*1.15`, `E6 = D6*1.15` recognizes as one account, materializes, and evaluates to
      **1,000,000 / 1,150,000 / 1,322,500** — Excel's own numbers, not merely self-consistent.
- [ ] Commit.

## Task 6 — Phase 4: the circular sweep

- [ ] **RED** — a workbook with interest on an average balance recognizes, and its
      `dependencyReport()` names exactly one cycle containing interest and closing debt.
- [ ] **RED** — it converges under `PeriodDriver`, and **year-one interest on a 120 draw at 10%
      is 11.75**. Beginning-balance accrual gives 12.00, so this single number distinguishes a
      correct cyclic solve from a model that broke the cycle by timing.
- [ ] Commit.

## Task 7 — Measure against Wharton

- [ ] Report coverage after translation, alongside Phase 2's recognition figure.
- [ ] **The reference numbers: IRR 24.67%, MoM 3.01.** Report what we get. If they do not
      reproduce, say so plainly and say why — a number that nearly matches is worse than one
      that visibly does not.
- [ ] Record in the proposal's phasing table and `master_plan.md`. Commit.

---

## Done when

- [ ] All seven tasks green, committed individually.
- [ ] `swift build && swift test` clean.
- [ ] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all` — the default set omits five checkers, which is how a broken DocC
      example shipped through four clean gate runs upstream.
- [ ] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [ ] Move this file to `project/checklists/completed/`.

## Do NOT do in these phases

- **Unit inference and typed source writing** — Phase 5, gated on the typed layer, which is
  itself gated on an unmeasured compile-time budget and now resolved to `LineItem<U>`.
- **Data-table recognition** — Phase 6. `_DATATABLE` markers already carry the span and drivers.
- **Dynamic-reference folding** — Tier 1 only, and only if a fixture needs it.
- **Growing the function registry.** If a name is missing, that is a `.unregisteredFunction`
  diagnostic and a note for upstream, not a patch here.
