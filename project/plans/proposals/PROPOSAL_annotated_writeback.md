# Design Proposal — the workbook, with the answers in it

**Status:** proposal, 2026-09-11. Phase 0 (Design).
**Scope:** BusinessMathExcel, over SwiftXLSX's existing writer.

---

## 1. Objective

**Hand the practitioner back their own spreadsheet, annotated.**

```
$ xlsheet run model.xlsx --trials 10000 --seed 4217 --out model-results.xlsx
```

They open it in Excel, Numbers or Sheets — whatever they already use — and see: the uncertain
inputs highlighted, each commented with its distribution; the outputs highlighted; a results
sheet with percentiles; any circular reference flagged red.

That is what Risk Solver does after a run. Doing it without the add-in, on a Mac, from a command
line, is the product.

---

## 2. Why this instead of building a viewer

The instinct when the audience is practitioners is to build a spreadsheet view so they can see
the model "in the format they naturally understand." But **they already have that format open on
another monitor.** What they lack is not a grid; it is the annotation layer.

This is also far cheaper than it looks, because the machinery exists:

- SwiftXLSX has `CellStyle` with `Fill`, and already defines `CellStyle.input` as solid yellow
- the reader and writer are bidirectional and already round-trip real workbooks
- `ModelSurveyor` already returns which cells are uncertain and which are outputs
- `InterpretedRun` already returns per-trial values per output

So the work is a layer that decides *what* to mark, not one that learns how to mark it.

---

## 3. What gets written

| Annotation | Source | Form |
|---|---|---|
| Uncertain input | `ModelSurveyor` survey | fill + comment naming the distribution and its parameters |
| Output | `PsiOutput` cells | distinct fill |
| Statistics | `InterpretedRun.outputs` | a new `Simulation Results` sheet: P5/P50/P95, mean, σ, CVaR |
| Run provenance | the run | **seed, trial count, tool version, timestamp** — on the results sheet |
| Circular reference | `WorkbookAudit` | red fill on the cells in the cycle |
| Unmodelled property | survey residue | comment, so what was *not* handled is visible |

The provenance row is not decoration. It is the difference between a results sheet someone can
reproduce and one they have to trust.

---

## 4. The three risks, in order

### 4.1 Round-trip fidelity — the one that can sink this

A read-modify-write must not lose what the reader does not model. Real workbooks carry pivot
tables, charts, conditional formatting, data validation, defined names, macros, merged cells and
frozen panes. If SwiftXLSX drops any of those, **we hand back a damaged file** — and that is far
worse than handing back nothing, because the damage may not be noticed for weeks.

**This is already answered, and the answer is bad.** `SwiftXLSX/project/plans/proposals/`
`PROPOSAL_surgical_save.md` (2026-09-08, ready for RED, **unimplemented**) opens with it:

> *"Today `Workbook(xlsxData: d).save()` is data loss, and it is silent."*

`save()` regenerates the archive from seven part types, so everything else — charts, themes,
conditional formatting, macros, pivot tables — is dropped. A read-modify-write today would hand
back a **damaged file**, exactly as feared, and quietly.

So the census proposed here is redundant; the finding exists. What it changes is the dependency:
**annotated write-back requires surgical save**, and surgical save is a second unimplemented
SwiftXLSX item alongside note-writing (§8).

That is a lot of upstream work before a practitioner sees an annotated workbook, which makes the
fallback in the next paragraph the sensible first delivery rather than a contingency.

**Proposed first delivery: a results-only workbook.** Write a *new* file containing the
simulation results, the cell inventory and the provenance row, referencing the source workbook by
name and annotating nothing in place. It needs neither surgical save nor note-writing, because it
creates a file rather than editing one — so it ships on today's SwiftXLSX, carries zero risk of
damaging anyone's model, and delivers most of the practitioner value ("the answers, in a
spreadsheet") immediately.

Annotation *in place* then becomes a later upgrade gated on the two SwiftXLSX items, rather than
the thing that blocks any delivery at all.

### 4.2 Never in place

`--out` is required; there is no in-place mode, not even behind a flag. A practitioner's model is
often the only copy and frequently unversioned.

### 4.3 Idempotence

Running twice must not produce two results sheets or double-commented cells. Propose a marker —
a defined name or a known sheet name — that the writer detects and replaces rather than appends.

---

## 5. Work

| # | Item |
|---|---|
| 1 | **Results-only workbook** — ships on today's SwiftXLSX, per §4.1. This is the first delivery. |
| 1a | *(upstream, SwiftXLSX)* surgical save — gates in-place annotation |
| 1b | *(upstream, SwiftXLSX)* note-writing — gates hover-to-see distributions |
| 2 | `WorkbookAnnotator` — takes a survey, a run, and audit findings; produces an annotation plan |
| 3 | The style vocabulary — fills and comments, extending `CellStyle` |
| 4 | The results sheet, including provenance |
| 5 | Idempotence marker and replace-rather-append |

---

## 6. Test strategy

- **Fidelity**: the §4.1 census, kept as a regression test rather than run once.
- **Idempotence**: annotate twice, assert the second output equals the first.
- **Opens cleanly**: the produced file must load in the reader without diagnostics — necessary,
  not sufficient, since the real oracle is Excel itself.
- **Provenance round-trips**: the seed written into the results sheet, fed back to `run`,
  reproduces the same statistics. That closes the loop the whole product claims.

---

## 7. Open questions

1. **~~Comments or notes?~~** **Checked 2026-09-11: SwiftXLSX supports neither.** There is no
   comment or chart code in the package at all, so §3's "fill + comment" was specifying something
   that does not exist. **Decided: add note-writing to SwiftXLSX first** — see §8 below, which is
   now a dependency of this proposal rather than a detail of it.
2. **~~A chart for the histogram?~~** **Confirmed out of reach.** No chart support exists. Deferred
   cleanly; the results sheet carries the numbers.
3. **~~Keep the `Psi*` formulas?~~** **Decided: keep them unchanged**, with base case and
   statistics on the results sheet. The file stays *the model* and can be re-run. The accepted
   cost is that those cells still read `#NAME?` when opened in plain Excel — which is honest:
   the workbook genuinely does depend on functions Excel does not have, and papering over that
   with base-case values would hand back a file that looks complete and simulates nothing.

---

## 8. New dependency — note-writing in SwiftXLSX

This is now the blocking item alongside the fidelity census, and it lives in a different repo.

### 8.1 Legacy notes, not threaded comments

Excel has two mechanisms and only one is right here:

| | Storage | Read by |
|---|---|---|
| **Legacy note** | `xl/comments1.xml` + `xl/drawings/vmlDrawing1.vml` + relationships | Excel, **Numbers, Google Sheets** |
| Threaded comment | `xl/threadedComments/*.xml` + a persons list | Excel only — **and still needs a legacy comment as fallback** |

**Legacy notes.** They are the portable form, they are what every other tool writes, and the
modern mechanism requires them as a fallback anyway. The VML is unpleasant but well-trodden.

### 8.2 It widens the fidelity census rather than duplicating it

§4.1's read-write-diff already covers comments implicitly — a workbook that *arrives* with notes
must not lose them. Now that we also *write* them, the census gains a specific assertion rather
than a general one, which is an improvement: a named check beats an aggregate diff nobody reads.

### 8.3 Sequencing consequence

`PROPOSAL_hosted_service.md`-style honesty applies: this pushes item 4 later in the roadmap, and
that should be visible rather than absorbed. The write-back cannot ship before SwiftXLSX can
write a note, and SwiftXLSX cannot be changed without its own release. Recorded in `ROADMAP.md`.
