# Proposal — The spreadsheet as a graph

**Status:** draft, 2026-09-04. The living design document for the direction taken after the
recognizer's ceiling was measured.

History lives in `PROPOSAL_excel_to_model_recognizer.md`, §23 of which records the turn and why it
was made. That document is the account of how we got here and is not maintained as a plan.

---

## 1. The goal

Take an **arbitrary** spreadsheet. Model the relationships between its cells — references and
formulas — as a graph. Hold that graph as the intermediate structure. From it, re-emit a working
spreadsheet, and emit Swift the compiler can check, so the model can be enhanced or used in some
other application.

Not necessarily with the same decoration. Labels, colours, headings and layout are a separate
concern and may come later. They are not what makes the thing a model.

The distinction that matters, and the one the previous direction got wrong:

| | Interpreter (what was built) | Translator (what this is) |
|---|---|---|
| Question | "Is this a financial model?" | "What does each cell read?" |
| Input | Sheets that fit a schema | Any sheet |
| When it does not understand | Returns nothing | Cannot arise — every formula has a dependency set |
| Failure mode | Fails closed, silently sized | None; fidelity is checkable |

## 2. Settled

Decided 2026-09-04, recorded at length in the recognizer proposal §23.7 and restated here as
conclusions.

1. **One node per cell. Compression is a projection, never a property of the graph.** Grouping
   cannot live in the graph because there is more than one valid grouping of the same graph —
   `Parameters → Decisions → Objective → Calculation` is one convention and other modellers use
   others. A projection can be wrong and discarded; a compressed node set would be a decision
   about what "one thing" is, made before anything is known.
2. **Identity is what the model computes, not where it sits.** Decoration is excluded
   deliberately.
3. **Cycles are represented, not refused.** Wharton holds 39 at cell level.
4. **Emission targets plain Swift primitives.** Grouping, naming and typing are later passes.
   §19's typed layer leaves the critical path.

   **Corrected 2026-09-04.** That last point was originally written as "the inbound path may not
   need BusinessMath at all", which is wrong. Foundation is enough to *represent* a graph;
   evaluating one is a different claim, and §4 is where it is worked out.

## 3. Measured before designing

- **`GraphPartition` already exists and works** (shipped 2026-09-04). Every cell takes a role from
  its edges alone: `parameter`, `objective`, `calculation`, `unreachable`. On Kelly's Roast Beef —
  a linear program with its structure written in column A and no timeline any header detector can
  find — the topology reproduced three of the modeller's four labelled blocks exactly, and the
  fourth as a parameter, which is what a decision variable is topologically. `solver_adj` in the
  file's defined names states the decisions outright, and `solver_opt` named the same objective
  cell the topology had already found.
- **The graph substrate reaches everything recognition cannot.** 781,867 nodes against 4,894
  accounts across 79 workbooks; 674 sheets against 297.
- **The existing export path is not a round trip.** `ModelExporter.export` assigns positions
  through a `LayoutStrategy`. That is correct for the outbound direction — build a model in Swift,
  produce a spreadsheet — and it means a re-emitted workbook does **not** reproduce the original's
  addresses. See §7.

---

## 4. Where the functions come from

A cell reading `=AVERAGE(B2:B10)` has to get `AVERAGE` from somewhere. Representing it needs
nothing — a name and a list of arguments is Foundation and a `String`. **Evaluating it is a
different claim**, and the earlier note that the inbound path might need no BusinessMath conflated
the two.

Measured across all three corpora — 589,199 function call sites — the answer is that they come
from four different places, and only one of them is a maths library.

| Source | Functions | Why it belongs there |
|---|---|---|
| **The evaluator itself** | `IF`, `IFERROR`, `ISERROR`, `ISNA`, `ISNUMBER` | Excel's error propagation and coercion rules. Not arithmetic; nobody outside a spreadsheet evaluator can supply them |
| **The graph** | `VLOOKUP`, `HLOOKUP`, `INDEX`, `MATCH`, `OFFSET`, `INDIRECT`, `ADDRESS`, `ROW` | These compute an *address* and read it. They are edge operations, and `OFFSET`/`INDIRECT` make edges dynamic |
| **Swift and Foundation** | `SUM`, `MIN`, `MAX`, `ABS`, `ROUND`, `SQRT`, `COUNT`, `YEAR`, `MONTH`, `DATE` | Primitives and calendar arithmetic |
| **BusinessMath** | `NPV`, `IRR`, `PMT`, `YEARFRAC`, `COVARIANCE.P`, and everything statistical or financial after them | Reimplementing these is the failure `FormulaEvaluator.Function`'s own documentation names: *"a second NPV that could disagree with the first"* |

### 4.1 The period-local constraint

`FormulaEvaluator<Double>.Function` is BusinessMath's Excel-named registry and looks like the
obvious thing to call. It is not, and its own doc comment says why:

> Each function acts **period by period** … Aggregating down a column is a different operation and
> is **deliberately not expressible**: this grammar is period-local.

That is the right design for `ModelDefinition`, and it is the wrong shape for a graph, where
`AVERAGE(B2:B10)` aggregates *across cells* by definition. So the evaluator gets its own dispatch
over range arguments and **delegates to BusinessMath's canonical implementations** — the core
functions, which already take collections (`npvExcel(rate:cashFlows:)` takes cash flows) — rather
than to the period-local enum. The registry is the naming authority and the semantics reference;
it is not the call target.

### 4.2 What BusinessMath is missing, measured

Of the 296,762 calls whose formulas parse, BusinessMath's registry names **68%**. The named gaps
that are genuinely its space — statistical and financial, where a second implementation could
disagree with the first — are worth adding upstream rather than writing here:

| Function | Calls | Sheets |
|---|---|---|
| `YEARFRAC` | 3,425 | 9 | day-count conventions are bond maths, not calendar maths |
| `SUMPRODUCT` | 805 | 134 | the widest reach of any unregistered function |
| `COVARIANCE.P` | 124 | — | BusinessMath already computes covariance; this is a binding |

Everything else unregistered falls in the first three rows of the table above and should **not**
go upstream: error semantics belong to the evaluator, lookups belong to the graph.

---

## 5. The blocker in front of all of this

**53% of the corpus's formulas do not parse.**

`_RAW` is not an Excel function. It is SwiftXLSX's fallback when `FormulaParser.parse` fails,
keeping the text verbatim: `cells[ref] = (.formula(.function("_RAW", [.text(cleaned)])), …)`. It
occurs **292,437 times** against 549,059 formulas.

A formula with no structure yields no edges. This is the ceiling on any graph built from these
files, and it sits in front of every function question — a function you cannot parse is not a
function you are missing.

Grouped by cause, it is **five parser gaps**, not a long tail:

| Cause | Formulas | Example |
|---|---|---|
| **Omitted arguments** | ~126,000 | `IFERROR(B5/C5-1,)`, `ADDRESS($C27,AZ$3,1,,"Lease Revenue")` |
| **Defined name as an operand** | ~95,000 | `VLOOKUP("SS",Production_Supply,7,FALSE)`, `C36+days_per_week` |
| **Whole-column / whole-row ranges** | ~47,000 | `SUMIFS(Sheet2!$E:$E, …)`, `'Lease Revenue'!$2:$3` |
| **Prefixed function names** | ~22,800 | `_xll.PsiNormal(…)` (an @RISK add-in), `_xlfn.COVARIANCE.P(…)` |
| **Error literals** | 233 | `CB_DATA_!#REF!` |

That accounts for essentially all 292,437. None is exotic; all five are ordinary spreadsheet
syntax this parser has not been taught.

**They are upstream.** SwiftXLSX owns the parser, and five releases have already come out of this
work for defects found the same way. Fixing them is the highest-leverage thing available: it
roughly doubles the material any graph can be built from, and it does so before a single decision
about node granularity or evaluation matters.

---

## 6. Phase 10 — a faithful graph, and proof that it is faithful

### 6.1 What it delivers

1. A graph built from **any** workbook: every populated cell a node, every reference an edge, the
   formula kept as an expression over nodes rather than over addresses.
2. An **evaluator** over that graph.
3. A gate proving the two agree with the file.

### 6.2 Why an evaluator, and why now

Fidelity has to be checkable or the claim in §1 is decoration. But checking it by writing a
workbook and reading it back does not work: writing in memory caches no values, and re-emission
assigns new addresses, so there is nothing to compare *to* at the address level.

There is a better ground truth already in the file. **Excel stores the value it computed for every
formula cell**, and SwiftXLSX has read those since 0.10.0. So:

> Build the graph from a workbook, evaluate it, and compare each node's computed value against the
> value Excel itself recorded for that cell.

That is a round-trip proof that needs no round trip. It also tests the thing that actually
matters — that the graph *means* what the sheet means — rather than that a file survives a
save-and-load.

And the evaluator is not scaffolding. Emitted Swift is an evaluator; writing one against the graph
is the first half of §1's second promise, not a test fixture.

### 6.3 The gate

**For every workbook in the three corpora, every node whose cell carries a cached value evaluates
to that value.** Reported as a proportion, with every disagreement named.

This is the gate §23.6 argued for, and its virtue is that **it cannot be fitted**. A coverage
number is a statement about the corpus it was measured on. This is a statement about arithmetic,
checkable on files nobody has seen, including files that do not exist yet.

It will not be 100% on the first run, and the failures are the point: every one names a function,
a reference form, or a value type the graph does not yet carry. That list is the phase's real
output.

### 6.4 Tasks

**Task 0 — the parser, upstream.** Five gaps in SwiftXLSX's `FormulaParser` (§5) leave 53% of the
corpus unstructured. Closing them roughly doubles the material a graph can be built from, and no
decision inside this phase matters more than that. Ordered by reach: omitted arguments, defined
names as operands, whole-column and whole-row ranges, `_xlfn.`/`_xll.` prefixed names, error
literals.

**Task 1 — the graph.** A `CellGraph` (name provisional) built from a workbook: nodes for
populated cells, edges from references, formulas held as expressions over node identities.
Cross-sheet included. Nothing refused; anything not understood is carried as an opaque node with
the reason, so it can be counted rather than lost.

**Nothing is refused at build time.** A function the evaluator cannot compute is still *in* the
graph — the structure of a call is known even when its meaning is not. Refusal moves from
graph-construction to evaluation, where it becomes a reported gap rather than a dropped cell.
That separation is what lets §6.3's gate produce a function roadmap instead of a silence.

**Task 2 — the evaluator.** Evaluate in dependency order. Cycles are represented, so they must be
*handled* — at minimum detected and reported as unevaluated rather than hung on; iterative
solution is a later question and should not be smuggled in here.

**Task 3 — measure against cached values.** Wharton first, then the corpus, credit and media
models. Publish the proportion and the full list of what disagreed and why.

**Task 4 — what the failures say.** The list from Task 3 becomes the roadmap. It is the first
roadmap in this project derived from arithmetic rather than from reading workbooks and guessing.

### 6.5 What Phase 10 does not do

- **No re-emission.** A faithful graph proven against cached values is the precondition; writing
  it back out is Phase 11.
- **No Swift emission.** Same reason.
- **No compression, no grouping, no naming.** Projections come after there is something to project
  from. `ShapeRun` waits.
- **No iterative cycle solving.** Represented and reported, not resolved.
- **Nothing removed from the recognizer.** It keeps working and keeps its measurements. Whether it
  becomes a projection over the graph is a question for after the graph exists.

### 6.6 The risk worth naming

**347 seconds** to build the media model's dependency graph today. If everything reads through a
cell-level graph, that is the floor for every operation on that workbook. 568,203 nodes should not
cost 347s, which suggests an algorithmic problem in construction rather than an inherent cost.

Task 3 will run head-first into it. Measure the cause before reaching for compression as the cure
— compression is a projection, and using it to paper over a construction cost would put it back in
the substrate where §2 says it must not go.

---

## 7. A note on what "round trip" means

The phrase is used loosely and should not be. Three different claims hide in it:

| Claim | Preserved | Status |
|---|---|---|
| **Byte fidelity** | the file | not a goal, and not desirable |
| **Address fidelity** | which cell holds what | **not a goal** — `ModelExporter` lays out afresh |
| **Computational fidelity** | what the model computes | **the goal**, and Phase 10's gate |

A re-emitted workbook may put a value in a different cell than the original did. As long as every
formula is rewired consistently and the computed results agree, it is the same model — which is
precisely the claim that decoration is separable from structure.
