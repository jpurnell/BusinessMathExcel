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
   §19's typed layer leaves the critical path, and with it the reason the inbound path depends on
   BusinessMath at all.

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
  addresses. See §5.

---

## 4. Phase 10 — a faithful graph, and proof that it is faithful

### 4.1 What it delivers

1. A graph built from **any** workbook: every populated cell a node, every reference an edge, the
   formula kept as an expression over nodes rather than over addresses.
2. An **evaluator** over that graph.
3. A gate proving the two agree with the file.

### 4.2 Why an evaluator, and why now

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

### 4.3 The gate

**For every workbook in the three corpora, every node whose cell carries a cached value evaluates
to that value.** Reported as a proportion, with every disagreement named.

This is the gate §23.6 argued for, and its virtue is that **it cannot be fitted**. A coverage
number is a statement about the corpus it was measured on. This is a statement about arithmetic,
checkable on files nobody has seen, including files that do not exist yet.

It will not be 100% on the first run, and the failures are the point: every one names a function,
a reference form, or a value type the graph does not yet carry. That list is the phase's real
output.

### 4.4 Tasks

**Task 1 — the graph.** A `CellGraph` (name provisional) built from a workbook: nodes for
populated cells, edges from references, formulas held as expressions over node identities.
Cross-sheet included. Nothing refused; anything not understood is carried as an opaque node with
the reason, so it can be counted rather than lost.

**Task 2 — the evaluator.** Evaluate in dependency order. Cycles are represented, so they must be
*handled* — at minimum detected and reported as unevaluated rather than hung on; iterative
solution is a later question and should not be smuggled in here.

**Task 3 — measure against cached values.** Wharton first, then the corpus, credit and media
models. Publish the proportion and the full list of what disagreed and why.

**Task 4 — what the failures say.** The list from Task 3 becomes the roadmap. It is the first
roadmap in this project derived from arithmetic rather than from reading workbooks and guessing.

### 4.5 What Phase 10 does not do

- **No re-emission.** A faithful graph proven against cached values is the precondition; writing
  it back out is Phase 11.
- **No Swift emission.** Same reason.
- **No compression, no grouping, no naming.** Projections come after there is something to project
  from. `ShapeRun` waits.
- **No iterative cycle solving.** Represented and reported, not resolved.
- **Nothing removed from the recognizer.** It keeps working and keeps its measurements. Whether it
  becomes a projection over the graph is a question for after the graph exists.

### 4.6 The risk worth naming

**347 seconds** to build the media model's dependency graph today. If everything reads through a
cell-level graph, that is the floor for every operation on that workbook. 568,203 nodes should not
cost 347s, which suggests an algorithmic problem in construction rather than an inherent cost.

Task 3 will run head-first into it. Measure the cause before reaching for compression as the cure
— compression is a projection, and using it to paper over a construction cost would put it back in
the substrate where §2 says it must not go.

---

## 5. A note on what "round trip" means

The phrase is used loosely and should not be. Three different claims hide in it:

| Claim | Preserved | Status |
|---|---|---|
| **Byte fidelity** | the file | not a goal, and not desirable |
| **Address fidelity** | which cell holds what | **not a goal** — `ModelExporter` lays out afresh |
| **Computational fidelity** | what the model computes | **the goal**, and Phase 10's gate |

A re-emitted workbook may put a value in a different cell than the original did. As long as every
formula is rewired consistently and the computed results agree, it is the same model — which is
precisely the claim that decoration is separable from structure.
