# Roadmap — from library to product

**Last updated:** 2026-09-11
**Status:** the sequencing document for the seven design proposals written 2026-09-10/11.
**Supersedes nothing.** `project/master_plan.md` remains the architecture record; this is the
order of work and the reasoning behind the order.

---

## 1. What changed, and why there is a roadmap at all

Until now the work has been a library, sequenced by what the mathematics needed next. Two things
moved that.

**The audience is practitioners, not Swift developers.** Risk and finance people who inherited a
model they cannot reproduce. They do not run `swift package add`, which means *every capability
built so far is currently unreachable by the people it is for*.

**The simulation loop closed.** A workbook built with Risk Solver can now be read, surveyed, run
with seeded reproducible trials, and have its statistics answered — without the add-in, on a Mac.
Risk Solver Simulation is **$375/month, roughly $2,520 a year on the annual plan, per seat,
Windows desktop**. That is no longer a library feature; it is a product thesis.

So the roadmap has one organising question: **what has to exist before a practitioner can use
this on a Tuesday, and before a marketing site would be telling the truth?**

---

## 2. The order

| # | Work | Proposal | Repo | Size | Blocked by |
|---|---|---|---|---|---|
| **1** | **Correlated inputs** | [`PROPOSAL_correlated_inputs.md`](../../../BusinessMath/project/plans/proposals/excel-coverage/PROPOSAL_correlated_inputs.md) | BusinessMath **+** SwiftExcelFunctions | medium | — |
| **2** | **Graph export** | [`PROPOSAL_graph_export.md`](proposals/PROPOSAL_graph_export.md) | BusinessMathExcel | small | — |
| **3** | **Command line** | [`PROPOSAL_command_line.md`](proposals/PROPOSAL_command_line.md) | BusinessMathExcel | medium | — (2 improves it) |
| **4a** | **Results-only workbook** | [`PROPOSAL_annotated_writeback.md`](proposals/PROPOSAL_annotated_writeback.md) §4.1 | BusinessMathExcel | small | — ships today |
| **4b** | *In-place* annotation | same | **SwiftXLSX** then BusinessMathExcel | medium | surgical save **+** note-writing, both unimplemented |
| **5** | **MCP surface** | [`PROPOSAL_mcp_surface.md`](proposals/PROPOSAL_mcp_surface.md) | new server | small | **3** |
| **6** | **Read-only grid** | [`PROPOSAL_html_grid.md`](proposals/PROPOSAL_html_grid.md) | BusinessMathExcel **+ SwiftXLSX** | small | [number formats](../../../SwiftXLSX/project/plans/proposals/PROPOSAL_number_formats.md) |
| **7** | **Hosted service** | [`PROPOSAL_hosted_service.md`](proposals/PROPOSAL_hosted_service.md) | deployment | small code, large ops | **3** |

**Before any of it: history remediation.** A provenance audit on 2026-09-11 found third-party
material published in git history — an unrelated client's confidential hardware documentation in
SwiftXLSX and BusinessMathExcel, and ~90 MB of copyrighted books tracked in BusinessMath. Both
verified directly. [`PROPOSAL_history_remediation.md`](proposals/PROPOSAL_history_remediation.md)
is the runbook: delete-and-recreate for the two four-month-old repos with no stars or forks,
surgical path excision for BusinessMath, whose 1,022 commits and 13 stars are worth preserving and
whose problem is confined to 20 of 108 tags. **Nothing has been executed.**

**Licensing sits outside and above all of it.** All five repos are public with **no `LICENSE`
file**, while two READMEs claim MIT and a third links to a file that does not exist. That is the
one state with no upside: it blocks the commercial adopter who runs a licence scan, and does not
block the one who copies and points at the README. It is hours of work and it should precede the
marketing site. See [`PROPOSAL_licensing.md`](proposals/PROPOSAL_licensing.md), which also corrects
`v3.0-DualLicensing.md`'s GPLv3 choice to **AGPLv3** — GPL's copyleft triggers on distribution, so
a competitor hosting this as a service would owe nothing, which is precisely the deployment the
roadmap is aiming at.

Two further items sit outside the numbering and should be done **immediately**, because both are
small and both protect claims that will be made before the work they protect is finished:

- **Refuse correlated models** rather than run them uncorrelated — `PROPOSAL_correlated_inputs.md`
  §9. A few lines. Today a model with `PsiCorrMatrix` runs and quietly understates tail risk.
- **The cross-platform determinism test** — `PROPOSAL_hosted_service.md` §4. Same seed, macOS and
  Linux, byte-identical. It guards the central marketing claim and nothing else guards it.

And one defect that is not a roadmap item at all: **SwiftXLSX is public and depends on the private
`jpurnell/SwiftZIP`**, so nobody outside can build it. True today, independent of licensing.
`PROPOSAL_licensing.md` §7.

---

## 3. Why this order

### 1 is first because it is a credibility gap, not a feature gap

Everything downstream markets a simulator. A simulator that ignores declared correlation
**understates the probability that several things go wrong at once**, which is the entire question
a risk model is asked. And it does it silently — an unimplemented distribution is `#NAME?` and the
reader stops; an ignored `PsiCorrMatrix` is a plausible number.

Anyone with a risk background correlates two inputs within ten minutes of evaluating this. Shipping
a CLI first means shipping a demo that fails the first real test.

It is also cheaper than it looks: a Gaussian copula is `CorrelatedNormals` followed by `normalCDF`,
and every distribution is already bound through a `quantile(u)`. Most of it exists.

### 2 before 3 because it is days, and it is the best thing to show

The graph already exists in `RecognizedModel`; the work is two text serializers. It produces the
one asset nothing else can — **a picture of a spreadsheet's actual shape** — including the `t−1`
rollforward edges that no spreadsheet view can draw at all.

It is also the cheapest item on the list, so it should not queue behind a medium one.

### 3 is the hinge

The CLI is where the project stops being a library. Two things depend on it directly (5, 7) and it
forces the result types to be complete and serialisable, which those two need anyway. Building MCP
or a service first means designing those types twice.

Within it, `check` is the single highest-leverage command: it is the first time a spreadsheet can
fail a build, which is the claim that makes practitioners lean forward.

### 4 and 6 are the two answers to "show me the spreadsheet"

They are not alternatives; they serve different contexts.

- **4 (write-back)** wins wherever the practitioner has Excel — which is almost always. They get
  *their own file back*, annotated, opened in the tool they already use.
- **6 (grid)** is only for contexts that cannot receive a file: the site, a service report, a chat
  response.

4 carries a real risk and 6 carries a real temptation. The risk: a read-modify-write that loses
pivot tables or charts hands back a **damaged file**, which is worse than handing back nothing.
That is why `PROPOSAL_annotated_writeback.md` §4.1 makes a fidelity census the blocking first task.
The temptation: 6 becoming an editable spreadsheet. §5 below.

### 5 and 7 are delivery, not capability

Both are adapters over 3. 5 is the one most likely to make somebody sit up — *"ask for the answer
in words"* — and BusinessMath already ships an MCP server, so the pattern is solved. 7 is mostly
operations, and its CI-action form avoids every hard question because the workbook never leaves the
customer's repository.

---

## 4. What each unlocks for the practitioner

Mapped so the ordering can be checked against benefit rather than tidiness.

| Practitioner benefit | Delivered by |
|---|---|
| *You can prove a number* — seed in, same numbers out, forever | already true; **surfaced** by 3, guarded by the determinism test |
| *A changed number means a changed model* | 3 |
| *The model outlives the analyst and the licence* | already true; **reachable** via 3 and 5 |
| *The model gets a build status* | 3 (`check`), then 7 |
| *Review is not gated by a licence* | 3, 5 |
| *You can see the shape of your model* | 2 |
| *You get your spreadsheet back with the answers in it* | 4 |
| *Correlated risks behave like correlated risks* | **1** |

---

## 5. Explicitly not doing

Recorded so these stay decisions rather than drifting into scope.

- **An editable spreadsheet.** The line is a keystroke. Read-only rendering is a view; accepting
  input means recalculation, invalidation, undo, selection, clipboard and formatting — that is
  Excel, which the practitioner already has open. See `PROPOSAL_html_grid.md` §2.
- **Our own graph renderer.** DOT and Mermaid reach GraphViz, Gephi, GitHub, Notion, VS Code and
  Claude artifacts for the cost of two serializers. A renderer buys nothing until *interaction* is
  wanted — drill, filter, scrub a simulation — and that is a product of its own.
- **An Excel add-in.** It would require the platform the whole pitch is about leaving, and it
  cannot deliver the reproducibility, CI or no-licence benefits, which are the actual argument.
- **Iman–Conover, for now.** The distribution-free correlation method is post-hoc by construction
  and would turn a streaming trial loop into a two-pass one. Recorded as the fallback for tail
  dependence. `PROPOSAL_correlated_inputs.md` §5.3.
- **A hosted upload endpoint, before someone asks for it by name.** Retention of a confidential
  financial model is a commitment, not a setting.

---

## 6. What would change this order

- **The Linux answer.** `.github/workflows/linux.yml` asks it — manual trigger, Swift 6.2/6.3/latest
  on `ubuntu-latest`. A green result unblocks items 7 and the container story; a red one is a work
  item nobody has scoped.
- **Recognition coverage improving materially.** It returns zero on **377 of 674 corpus sheets**.
  The graph (2) and everything named-account-shaped is worth roughly twice as much at twice the
  coverage, and that work is tracked in `PROPOSAL_spreadsheet_graph.md` rather than here.
- **A real user with a real workbook.** Any of 4, 5 or 7 would jump the queue for someone holding
  a model they need read. The order above is what to do absent that; a named user beats it.
- **The fidelity census failing badly.** If a read-modify-write cannot preserve real workbooks, 4
  changes shape — results land in a new file rather than an annotated copy — and drops in value
  enough to move below 6.

---

## 7. Where the site fits

The marketing site is not on this list, deliberately. It should be written **after 2 and 3**:

- **2** gives it the picture, live rather than a screenshot, because Mermaid renders natively.
- **3** gives it a terminal transcript, which is the shortest honest demonstration of every claim.

Before those, the site would describe capabilities its reader cannot reach — which is the exact
problem this roadmap exists to fix.

The site must also carry the gaps, and they belong here so they are not quietly dropped when the
copy is written: **283 of Excel's 519 functions**; recognition at 85% on *one well-behaved
teaching workbook* and zero on 377 of 674 corpus sheets; the consistency checker opt-in because it
produced 249 findings across 33% of six workbooks; pre-1.0 throughout. The audience audits things
for a living. Visible limits are the credibility.
