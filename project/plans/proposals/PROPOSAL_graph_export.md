# Design Proposal — emitting the model graph

**Status:** proposal, 2026-09-11. Phase 0 (Design).
**Scope:** BusinessMathExcel. Two serializers and a subgraph extractor.
**Relationship to `PROPOSAL_spreadsheet_graph.md`:** that document is about the graph as the
*internal* structure — what the recognizer builds and re-emits from. This is about handing that
graph to a **human**. Different concerns; neither replaces the other.

---

## 1. Objective

**Let someone see the shape of their spreadsheet.**

```
$ xlsheet graph model.xlsx --format dot  | dot -Tsvg > model.svg
$ xlsheet graph model.xlsx --format mermaid                 # renders in GitHub, Notion, Claude
$ xlsheet graph model.xlsx --trace D47                      # only what feeds D47
```

Nobody has ever seen theirs. That is the entire pitch, and it is unusually cheap to deliver
because the graph already exists — `RecognizedModel` holds it, and `DependencyGraph` holds the
cell-level one.

---

## 2. The decision that makes or breaks this: which graph

There are two, they serve different purposes, and conflating them produces something useless.

| | **Model graph** | **Cell graph** |
|---|---|---|
| Source | `RecognizedModel.accounts` | `SwiftExcelCore.DependencyGraph` |
| Node count, Wharton | **46** | ~280 populated |
| Node count, a real credit model | tens | **hundreds of thousands** |
| Legible whole? | yes | **never** |
| Works on what fraction of sheets? | **44%** — 297 of 674 | 100% |

**Rendering a whole cell graph is a mistake.** GraphViz will lay out 800,000 nodes into a black
disc and the practitioner will learn nothing. So:

- **Model graph — render whole.** This is the picture. Forty-six nodes is something a CFO reads.
- **Cell graph — render only a scoped subgraph.** Never the whole thing; see §5.

That split is also honest about coverage. Recognition returns zero on **377 of 674 corpus
sheets**, so the beautiful picture is available less than half the time. §5 is the feature that
works everywhere, and it may matter more day to day.

---

## 3. What the model graph contains

`RecognizedModel` already carries everything needed. Nothing has to be computed.

**Nodes** — one per `RecognizedAccount`, which has `name`, `formula`, `expression`, `values`,
`unit`, `provenance: [CellRef]` and `sheet`. Classified:

| Class | Test | Rendering |
|---|---|---|
| input | `expression == nil`, has `values` | distinct fill |
| uncertain input | provenance cell carries a `Psi*` call | **its own class** — this is the risk model |
| formula | has an `expression` | default |
| output | marked `PsiOutput`, or nothing depends on it | distinct shape |
| residue | from `RecognizedModel.residue` | greyed, labelled with its `DiagnosticCode` |

Including **residue** is deliberate. What the recognizer *failed* to read is information, and a
diagram that silently omits it tells the reader their model is simpler than it is.

**Edges** — from each account's `RecognizedExpression`, which exposes `accounts: [String]`. So an
edge is (account, each account its expression names). No traversal to invent.

**And the edge a spreadsheet cannot draw.** `RecognizedModel.rollforwards` carries
`RecognizedRollforward(opening:closing:seedCell:seed:)` — closing balance *t* depends on opening
balance *t*, which is closing balance *t−1*. That is a dependency on the previous period's
version of a cell, and **no spreadsheet view can show it**, because the arrow points backwards in
time rather than across the sheet.

Render it as a distinct edge style labelled `t−1`. It is the single most compelling thing on the
diagram and the clearest demonstration that this is a model view rather than a picture of a grid.

**Clusters** — `subgraph cluster_<sheet>` from `RecognizedAccount.sheet`. The model's own
structure, not a layout accident.

---

## 4. Two serializers, no renderer

**DOT** (`graphviz.org/doc/info/lang.html`) for the power tools — GraphViz, Gephi, Cytoscape.
Clusters, edge styles, `rank=same` for the period axis.

**Mermaid** for everywhere a human already reads. It renders natively in GitHub, GitLab, Notion,
Obsidian, VS Code, and Claude artifacts — so the marketing site's diagrams are **live rather than
screenshots, with no infrastructure at all.** Same graph walk; a second `Emitter` conformance.

**Do not build a renderer.** It buys nothing until interaction is wanted — click to drill, filter,
scrub a simulation across trials — and that is a product rather than a feature. Recorded here so
the decision is deliberate rather than deferred by accident.

### 4.1 Escaping is where this will actually break

Both formats have reserved characters and account names come from spreadsheet labels, which
contain anything: quotes, braces, newlines, `-->`, non-ASCII, and the empty string.

- DOT: quote every identifier, escape `"` and `\`.
- Mermaid: `[]{}()"|;` and `-->` all break the parse inside a node label.

**Propose: node IDs are opaque and generated (`n0`, `n1`, …), never derived from the name; the
name appears only as an escaped label.** That decouples identity from text entirely, and it is
expensive to change later because every edge references the ID.

Test with a deliberately hostile account name. One will exist in the corpus.

---

## 5. Tracing: the feature that works on every workbook

> **"Show me everything that feeds D47."**

Precedent tracing. Auditors do it by hand with Excel's arrows, one hop at a time, and it is
miserable. A transitive-ancestors subgraph is typically 10–40 nodes, renders beautifully, and
needs **no recognition at all** — just `DependencyGraph`, which works on 100% of workbooks.

```
xlsheet graph model.xlsx --trace D47              # ancestors: what feeds it
xlsheet graph model.xlsx --trace D47 --forward    # descendants: what it breaks
xlsheet graph model.xlsx --trace D47 --depth 3
```

`--forward` answers "if I change this, what moves?", which is the question before every edit to a
model nobody understands.

Propose a **node budget** (default ~300) with a clear refusal rather than a hairball: *"1,847
cells feed D47; re-run with --depth or --max-nodes."* A diagram too dense to read is worse than
an error, because the reader believes they looked.

---

## 6. Work

| # | Item |
|---|---|
| 1 | `ModelGraph` — the neutral structure: nodes, edges, clusters, classes. Built from `RecognizedModel`; holds no formatting. |
| 2 | `GraphEmitter` protocol, with `DOTEmitter` and `MermaidEmitter` conformances |
| 3 | Escaping, per §4.1, with hostile-input tests |
| 4 | `CellGraph.trace(from:direction:depth:maxNodes:)` over `DependencyGraph` |
| 5 | Circular references rendered red, from `WorkbookAudit`'s existing checker |

Items 1–3 are the model graph; 4 is independent and shippable on its own.

---

## 7. Test strategy

- **Golden files** for DOT and Mermaid on a small fixture model — exact text, since both are
  formats other programs parse.
- **Parse-back**: Mermaid and DOT output must survive an actual parser. If no Swift parser is
  handy, at minimum assert the escaping invariants (no unescaped reserved characters in labels).
- **Wharton, whole**: 46 accounts in, 46 nodes out, no orphans, every edge's endpoints present.
- **Trace bounds**: `--depth 1` on a known cell yields exactly its direct precedents.
- **Hostile names**: an account called `A "B" --> C{}` round-trips into a valid document.

---

## 8. Open questions

1. **~~Does the model graph want periods?~~** **Decided 2026-09-11: accounts by default, with
   opt-in period drill-down for a named account.** See §8.1 — the two-scheme risk this raises is
   designed out rather than accepted.
2. **~~Is `sheet` the right cluster?~~** **Decided: cluster only when there is more than one
   sheet.** On a single-sheet model, one box around the whole diagram says nothing.
3. **~~Residue by default?~~** **Decided: on, with `--hide-residue`.** What recognition missed is
   information, and the failure mode of hiding it is a reader who believes the model is simpler
   than it is — likely rather than hypothetical, given recognition returns zero on 377 of 674
   corpus sheets. Rendered greyed, in a dashed cluster, labelled with its `DiagnosticCode`.

---

## 8.1 One identity scheme, not two

Drill-down is the more capable choice and it carries a real hazard: *two* node-identity schemes to
keep consistent, in a place where identity propagates into every edge and both serializers. §4.1
already fixes generated IDs for escaping reasons; this compounds it.

**Design it out by making the period optional rather than making a second scheme:**

```swift
struct NodeKey: Hashable {
    let account: String
    let period: Period?      // nil = the account across all periods
}
```

- **Default view** — every node is `(account, nil)`. Exactly the collapsed graph.
- **`--expand Revenue`** — that one account's nodes become `(Revenue, p)` for each period; every
  other account stays `(account, nil)`.

One scheme, one escaping path, one edge type, one emitter. The views differ in which keys are
*generated*, not in what a key is.

It also makes the `t−1` rollforward edge the **same relation at two zoom levels**, which is the
part worth getting right:

| View | Edge |
|---|---|
| collapsed | `(Closing, nil) → (Closing, nil)`, self-loop styled `t−1` |
| expanded | `(Closing, p−1) → (Closing, p)`, a plain edge |

The self-loop is not a degenerate case to special-case away; it is the honest collapsed rendering
of a period-to-period dependency, and it is the one edge a spreadsheet view can never draw.

**Invariant worth a test:** collapsing an expanded graph — mapping every `(a, p)` to `(a, nil)`
and deduplicating — must yield exactly the default graph. If it does not, the two views disagree
about the model, which is the failure this section exists to prevent.
