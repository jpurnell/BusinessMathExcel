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

- [x] `RecognizedModel`: periods, accounts, residue — plain `Sendable` data, no construction.
- [x] `RecognizedAccount`: name, formula or values, provenance. **Provenance is never empty.**
- [x] `Residue`: what could not be translated, and why.
- [x] **RED** — every account's provenance cells actually hold what the account claims.
- [x] Commit.


**Two lag defects that only running the real sheet would have shown.**

`Beginning = End` — a within-period circle the workbook does not contain. Its formula is
`E50 = D52`, reaching into the at-close column, which the lag rule treated as off-axis and so as
a scalar. The at-close column *is* the period before the first, and a first-period formula
reaching into it is a carry seeded there — which is what the column is for.

Fixing that alone over-corrected: `Interest Expense` became
`AVERAGE(End, Beginning) * [Interest Rate Opening]`, turning a rate into a balance that carries.
The sheet says which is which, and it is the `$`: `E50 = D52` fills across and therefore means
*last period*, while `$D$8` does not move and therefore means *this rate*. A pinned reference is
an assumption regardless of where it points. That is the same `$` distinction that decided
formula uniformity in Phase 2, arriving from a completely different direction.

## Task 4 — `ModelBuilder`

- [x] Plan to `ModelDefinition`, **throwing**: recognition never throws, materialization does.
- [x] **RED** — an unresolved reference, a duplicate account and an unparseable formula each
      throw a named error rather than producing a partial model.
- [x] Commit.


**Named `ModelMaterializer`, not `ModelBuilder`.** `BusinessMath` already exports a public
`ModelBuilder` for its fluent API, and this package imports it. Two types with one name is a
collision waiting for whoever writes the next `import`. Caught before writing rather than at the
first build — which is the second time a name the proposal chose was already taken in core, after
`Account<U>`. The proposal was written without checking core's namespace, and anything else it
names should be checked before it is typed.

**The seed moved onto the plan.** A rollforward's opening value is resolved during recognition,
where the grid is at hand, rather than during materialization. A builder that had to be handed
the grid to finish reading the plan would not be working from a plan.

## Task 5 — The golden path, end to end

- [x] **RED** — the proposal's validation trace: `B6 = "Revenue"`, `C6 = 1000000`,
      `D6 = C6*1.15`, `E6 = D6*1.15` recognizes as one account, materializes, and evaluates to
      **1,000,000 / 1,150,000 / 1,322,500** — Excel's own numbers, not merely self-consistent.
- [x] Commit.

## Task 6 — Phase 4: the circular sweep

- [x] **RED** — a workbook with interest on an average balance recognizes, and its
      `dependencyReport()` names exactly one cycle containing interest and closing debt.
- [x] **RED** — it converges under `PeriodDriver`, and **year-one interest on a 120 draw at 10%
      is 11.75**. Beginning-balance accrual gives 12.00, so this single number distinguishes a
      correct cyclic solve from a model that broke the cycle by timing.
- [x] Commit.

## Task 7 — Measure against Wharton

- [x] Report coverage after translation, alongside Phase 2's recognition figure.
- [x] **The reference numbers: IRR 24.67%, MoM 3.01.** Report what we get. If they do not
      reproduce, say so plainly and say why — a number that nearly matches is worse than one
      that visibly does not.
- [x] Record in the proposal's phasing table and `master_plan.md`. Commit.

**Measured 2026-09-02.** IRR **24.67%** and MoM **3.01** both reproduce through
recognition, unchanged. `ANSWER KEY` recognition coverage 70% (196 of 279), and after
translation: 21 accounts, 3 rollforwards, 12 residue. The sheet does **not** materialize —
rows 3–11 are two side-by-side assumption tables whose value column H is also the 2026
period column, so `Revenue growth` reads as `10%` in D11 and `SUM(H9:H10)` in H11 and is
refused as non-uniform; `% growth` then cannot resolve. Six of the seven non-uniform rows
are that one overlap. Said plainly rather than rounded off: Phases 3 and 4 made recognized
cells runnable, and did not recognize more of them.

---

## Done when

- [x] All seven tasks green, committed individually.
- [x] `swift build && swift test` clean.
- [x] **Quality gate 0 errors / 0 warnings**, counted rather than read off the verdict line, and
      run with `--check all` — the default set omits five checkers, which is how a broken DocC
      example shipped through four clean gate runs upstream.
- [x] CHANGELOG; `master_plan.md` reconciled; capability map reviewed.
- [x] Move this file to `project/checklists/completed/`.

## Do NOT do in these phases

- **Unit inference and typed source writing** — Phase 5, gated on the typed layer, which is
  itself gated on an unmeasured compile-time budget and now resolved to `LineItem<U>`.
- **Data-table recognition** — Phase 6. `_DATATABLE` markers already carry the span and drivers.
- **Dynamic-reference folding** — Tier 1 only, and only if a fixture needs it.
- **Growing the function registry.** If a name is missing, that is a `.unregisteredFunction`
  diagnostic and a note for upstream, not a patch here.
