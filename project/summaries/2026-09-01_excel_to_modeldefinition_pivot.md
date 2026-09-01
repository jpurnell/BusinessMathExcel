# Session Summary: Excel→ModelDefinition pivot, and the removal of BusinessMathDSL

**Date:** 2026-09-01
**Repos touched:** `BusinessMathExcel` (primary), `BusinessMath` (sibling at `../BusinessMath`)
**Outcome:** Two design proposals approved in substance. No implementation code written yet.
**Next action:** `BusinessMathExcel` Phase 1 — `ModelImporter` fixes (see §6).

---

## 1. What triggered this

A Hacker News post — orcaset's *"Agents still can't automate Excel"* — prompted a comparison
against this project. The comparison was useful but the conclusion was not the one expected:
orcaset has **no Excel code at all** (verified: `grep -rin "xlsx\|openpyxl\|excel" src/` returns
one comment; dependencies are `python-dateutil` only). It is a pure-Python modelling DSL that
abandons spreadsheets. It is not a competitor to this package.

What it *did* surface is that the article's central accusation — agents write cached values into
cells using an out-of-band evaluator that silently disagrees with Excel — describes a real defect
in this repo (§7), and that our import path was aimed at the wrong target.

## 2. The chain of findings (each verified against the working tree)

1. **`BusinessMathExcel`'s import path is a structural transcription, not a translation.**
   `ModelImporter.swift:57-61` labels every node by its cell address (`"B4"`), all in one section
   named `"Imported"`. `FormulaMapper` only counts function names into two `Set<String>`s.
2. **`BusinessMathDSL` was the assumed target — and it has zero consumers.**
   `grep -rl "import BusinessMathDSL"` across every sibling package returns only its own four
   test files plus its own README. No package declares it as a dependency.
3. **It duplicates core.** `Scenario` and `ScenarioAnalysis` exist in *both*
   `BusinessMathDSL/Scenario.swift` and `Simulation/MonteCarlo/ScenarioAnalysis.swift:113,167`.
   Valuation duplicates `Valuation/Equity/`. Core's versions are `Sendable`; **no DSL type is**,
   despite `StrictConcurrency` being enabled at `Package.swift:133-135`.
4. **`ModelDefinition` already ships and is the better target.**
   `Model Definition/ModelDefinition.swift:119` — named accounts, string formulas over
   `TimeSeries`, `requiredInputs()`, `evaluationOrder()`, `evaluate()`. Plus SCC cycle detection
   (`DependencyReport.swift:103`) and resolution (`CycleSolver.swift:234`,
   `IterativeCycleSolver`), landed in `87a717e` and written *for Excel migrants*. A workbook
   already **is** named accounts with formulas and cycles.
5. **`BusinessMathPro` has debt/sweep prior art we cannot reach.**
   `Treasury/CapitalStructureProjection.swift:199` does per-period interest and cash sweep, but
   `BusinessMathPro/Package.swift:40-43` shows Pro depends on BusinessMath — and
   `BusinessMathDSL`/core are *inside* BusinessMath. Using it would be a package cycle. Any
   shared debt primitive must live in core.
6. **Prior-period references are deliberately excluded, and documented twice.**
   `FormulaEvaluator.swift:119-124` ("no references to other periods") and
   `CycleSolver.swift:222-226` ("a cycle here is a cycle *within* one period… the roll-forward
   … stays the caller's loop"). This is a boundary drawn on purpose.
7. **Sensitivity tables already exist in core.**
   `Scenario Analysis/SensitivityAnalysis.swift:318` — `TwoWayScenarioSensitivityAnalysis` with
   `results: [[Double]]`, plus `runTwoWaySensitivity` (`:585`), one-way (`:142`), tornado (`:759`).
8. **`FormulaEvaluator` has no functions and no comparison operators.** Token set is
   `number`, `name`, `+ - * / ( )`. No `MIN`/`MAX` means no cash sweep; no `>`/`<` means no `IF`.

## 3. Decisions made (all user-approved)

| # | Decision |
|---|---|
| D1 | **Import target is `ModelDefinition`, not `BusinessMathDSL`.** |
| D2 | **Delete `BusinessMathDSL`.** Deprecate in next minor, remove in next major. User leans toward deleting ASAP; recommendation to keep the one-release deprecation stands but is the user's call. |
| D3 | **Migrate `Tier`/`TierComponents`/`LiquidationWaterfall` to core** — the only DSL piece with no core equivalent. |
| D4 | **`FormulaEvaluator` implements no financial mathematics.** Functions dispatch to canonical BusinessMath implementations. Core has **616 public functions**; the registry is a name-mapping exercise, not an implementation effort. |
| D5 | **`NPV` in formula text binds to `npvExcel`, not `npv`.** `NPV.swift:215-217` documents the one-period discounting difference. Pinned by a test asserting they differ. |
| D6 | **Cross-period carry is a `PeriodDriver`, not a grammar feature.** Prior-period refs inside the grammar would require moving the dependency graph from per-account to per-(account, period) — a rewrite of the evaluation core. |
| D7 | **Phantom-typed units** (`Money`, `Rate`, `Ratio`, `Duration`, `Condition`). Rate *basis* is a runtime value, not a second type parameter. |
| D8 | ~~**`IF` + comparison operators folded into Phase 2a.**~~ **Amended 2026-09-01** — pulled forward into `BusinessMathExcel` Phase 2 and off the upstream gate entirely. The bar D8 set was that this work waits on the function registry; it shipped earlier because comparison operators are operators rather than registry entries, and because a production credit model measured at 2982 `IF`s in 5011 formulas against Wharton's one. See `PROPOSAL_excel_to_model_recognizer.md` §15 Q0. |
| D9 | **Timeline conditionals become data.** "If the condition is answerable from the timeline alone, it is data; if it depends on a computed value, it is `IF`." Recognizer demotes period-testing `IF`s to indicator series. |
| D10 | **Hand-edited cells are a finding, not something to smooth over.** A non-uniform row emits `.nonUniformRow`; the recognizer never picks a majority shape. |
| D11 | **Target is 100% Wharton coverage.** 30% is an interim milestone, not a kill gate. |

**Amendments since this session.** D8 was amended on 2026-09-01 (see the row above). No other
decision in this table has changed. Amendments are recorded here rather than by editing the
original wording, so the register shows where the plan was wrong rather than reading as though it
was always right.

## 4. Dropped work (recorded so it is not silently lost)

**`CashFlowModel.freeCashFlow(year:)` returns `netIncome + depreciation` with no capex**
(`CashFlowModel.swift:223-230`), and feeds `DCFModel.calculateEnterpriseValue()` at
`DCFModel.swift:144` — overstating enterprise value by PV(capex). Originally scoped as an urgent
standalone fix.

**Dropped, because both types live inside `BusinessMathDSL` and the module is being deleted.**
Blast radius is entirely within the deleted module; zero consumers means no interim harm.
Deletion is the fix.

## 5. Current state

### Git

| Repo | Branch | State |
|---|---|---|
| `BusinessMathExcel` | `main` | Clean except: `.claude/settings.local.json` (M), and two **untracked** proposals in `project/plans/proposals/` |
| `BusinessMath` | `main` @ **`v2.7.0`** | Proposals committed in `76b538fe`; `TypedModelAuthoring.md` has **uncommitted** later edits (Part 2.5 rollforward, `IF`/conditionals, ADRs, phasing) |

**Nothing is committed in `BusinessMathExcel` yet.** Both proposals there are untracked files.

### Version note

`BusinessMath` is at `v2.7.0`. `BusinessMathDSL`, `Model Definition/`, and
`FormulaEvaluator.swift` are **byte-identical between `2.6.0` and `2.7.0`** (verified with
`git diff --stat`), so every finding above holds. `BusinessMathExcel` still pins
`exact: "2.2.1"` at `Package.swift:13`.

### The proposals

| Document | Repo | Status |
|---|---|---|
| `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` | Excel | **Live** |
| `project/plans/proposals/PROPOSAL_excel_to_dsl_recognizer.md` | Excel | Superseded — kept for its `ModelImporter` defect analysis |
| `project/plans/proposals/TypedModelAuthoring.md` | BusinessMath | **Live** |
| `project/plans/proposals/DSLExpressiveness.md` | BusinessMath | Superseded — kept for its prior-art audit |

## 6. Exact next step

**`BusinessMathExcel` Phase 1 — `ModelImporter` fixes.** Self-contained, depends on nothing
upstream, and unblocks the Phase 2 coverage measurement that shapes everything else.

Four defects, all in `Sources/BusinessMathExcel/Import/ModelImporter.swift`:

1. **`:161-165`** — `.cellRange` and `.power` collapse to `.text("UNSUPPORTED")`. Real workbooks
   are `SUM(D5:D16)` and `(1+r)^n`. Implement both.
2. **`convertAST` never receives `warnings`** — it is not even a parameter. Unsupported AST nodes
   vanish silently; warnings only fire for `.date`/`.error`/`.array` *cell types* at `:93`.
   Thread the array through and report every drop.
3. **`:29-32`** — `importWorkbook` takes `sheets.first`. Add multi-sheet import.
4. **`:92-93`** — `.array` cells are discarded as "Unsupported cell type". These are **Excel data
   tables** (`{=TABLE(r,c)}`) and are the detection signal for sensitivity-table recognition in
   Phase 6. At minimum, stop discarding them silently.

**TDD, per project rules.** Write the failing test first for each. Start with #2 — it is the
smallest and it makes #1's progress visible.

Expect two intended behavioural changes to existing callers (§7 of the live proposal):
`ModelImporterTests` asserts on the `"UNSUPPORTED"` sentinel, and `warnings` becomes non-empty
for workbooks that previously reported none.

## 7. Known defect not yet scheduled

`MonteCarloExtension.swift:164` — `case .function: return 0`, and `:141` — `case .text, .bool,
.range: return 0`. A Monte Carlo over any `DCFModelBuilder` output (`NPV`/`IRR` are
`.function` nodes, `DCFModelBuilder.swift:38-49`) silently produces a column of zeros, then
computes mean/stddev/percentiles from them. Only `.multiply` is covered by tests.

This is the same second-evaluator anti-pattern the orcaset article describes, in our own code.
Scheduled as a Future Direction in the live proposal (route it through the function registry once
that exists), not as immediate work.

## 8. Open questions for the user

1. **D2 timing** — deprecate-then-remove across two releases, or delete `BusinessMathDSL`
   outright now? User leaned toward ASAP; recommendation is the one-release deprecation.
2. **Compile-time budget number** for the phantom-unit overload set
   (`TypedModelAuthoring.md` §15 Q5). Needs measuring on the worked example before its Phase 3
   can be gated. If it fails, the documented fallback is runtime unit validation.
3. **Unit inference default on or off** in recognizer v1 (`PROPOSAL_excel_to_model_recognizer.md`
   §15 Q5) — a wrong inferred unit becomes a compile error in generated source.

## 9. Reference targets

- **Wharton LBO Practice Model** (Penn Career Services, public): **IRR 24.67%**, **MoM 3.01**.
  Independently reproduced by orcaset's `examples/paper-lbo`, giving a second source.
- **Year-1 interest = 11.75** on a 120 draw at 10% with full sweep. This is the *average-balance*
  figure; beginning-balance gives 12.00. One number distinguishes a correct cyclic solve from a
  model that quietly broke the cycle by timing.
- **`Revenue.swift:29-36`** documents `Base(1_000_000)` + `GrowthRate(0.15)` → year 2
  `1,150,000`, year 3 `1,322,500` (for non-regression during DSL removal).

## 10. Recovery checklist

1. `git status` in **both** repos; the `BusinessMath` `TypedModelAuthoring.md` edits are
   uncommitted and the `BusinessMathExcel` proposals are untracked.
2. Read `project/plans/proposals/PROPOSAL_excel_to_model_recognizer.md` — §3 (architecture),
   §10 (test strategy), and the phasing table at the end.
3. Read `../BusinessMath/project/plans/proposals/TypedModelAuthoring.md` — Part 2 (registry),
   Part 2.5 (`PeriodDriver`), §12 (adversarial review).
4. Commit the proposals if wanted, then start §6 Phase 1 under TDD.
