# Design Proposal — the read-only grid

**Status:** proposal, 2026-09-11. Phase 0 (Design).
**Scope:** BusinessMathExcel — an HTML serializer. **Explicitly not a spreadsheet application.**

---

## 1. Objective

**Show a workbook in the shape a practitioner recognises, where there is no Excel to hand them.**

Three places need this and none of them can receive an `.xlsx`: the marketing site, a service's
report page, and an MCP or chat response. In every other case
`PROPOSAL_annotated_writeback.md` is the better answer — give them back their own file.

---

## 2. The line, stated once: **no editing**

This is the whole proposal. Everything else is detail.

| Read-only rendering | What editing would additionally require |
|---|---|
| values, formatted | recalculation on change |
| formula on hover | dependency invalidation and ordering |
| A1 addressing | selection model, ranges, fill handle |
| colour coding | undo/redo stack |
| annotations | clipboard semantics, formatting UI, column resize |

The left column is a few hundred lines. The right column is Excel, which has had thirty-eight
years and an enormous team, and which the practitioner **already has open**. Building toward it
serves no user and consumes the project.

**A keystroke is the boundary.** The moment the grid accepts one, this proposal has been
abandoned and a different one is needed.

---

## 3. What it renders

The same annotation vocabulary as the write-back proposal, so a reader who has seen one recognises
the other:

- cell values, right-aligned numerics with `tabular-nums`, formats respected where the reader
  models them
- the **formula on hover**, which is the thing a grid can do that a printout cannot
- fills: uncertain input, output, circular reference, residue
- the sheet tab strip, when there is more than one sheet
- row and column headers, frozen, so A1 addressing works as the eye expects

Self-contained output: inline CSS, no external requests, no scripts beyond hover behaviour. That
is a hard requirement for artifact and email contexts, and a good discipline everywhere else.

---

## 4. Size is the practical problem

A corpus workbook reaches hundreds of thousands of populated cells. Rendering all of them as DOM
is not viable.

Proposed, in order of preference:

1. **Render the used range of one sheet at a time**, with a cell budget (default ~20,000).
2. **Over budget: render a window** around a named anchor — the cells the caller cared about,
   plus context — and say what was omitted.
3. **Never silently truncate.** A grid that stops at row 1,000 without saying so is a lie in the
   most convincing possible format.

Virtualised scrolling is the obvious escalation and is deferred: it needs script, which cuts
against §3's self-contained requirement, and the anchored window covers the real use cases.

---

## 5. Work

| # | Item |
|---|---|
| 1 | `HTMLGridRenderer` — one sheet, used range, values and headers |
| 2 | Formula-on-hover, from the reader's stored formulas |
| 3 | The annotation vocabulary, shared with the write-back annotator |
| 4 | Budget and anchored window, per §4 |
| 5 | Multi-sheet tab strip |

---

## 6. Test strategy

- **Golden HTML** for a fixture workbook.
- **Self-containment**: assert the output contains no `http://`, `https://` or `src=` reference.
  It is one regex and it protects the requirement that actually gets broken by accident.
- **Budget behaviour**: over-budget input produces the omission notice, and the notice states real
  numbers.
- **Escaping**: a cell containing `<script>` renders as text. Spreadsheets contain anything.

---

## 7. Open questions

1. **~~Number formatting?~~** **Checked 2026-09-11, and it is the largest item here.** SwiftXLSX
   stores and round-trips format codes but has **no formatter** — the grid can learn that C4 is
   `0.0%` and still cannot render `42.1%`. **Decided: a common subset now, with a designed path to
   full coverage**, specified in `SwiftXLSX/project/plans/proposals/PROPOSAL_number_formats.md`.

   The decision that matters there is architectural rather than scoping: **parse the whole
   grammar, implement a subset of the semantics.** A subset reached by matching known code strings
   is a rewrite when it is extended; a subset reached by a real parser is a fill-in. The order of
   work comes from a corpus census rather than taste, and the invariant *no format code is ever
   silently wrong* is what makes shipping partial coverage honest.

2. **~~Tab strip in v1?~~** **Decided: deferred.** One sheet at a time, caller-named. All three
   consumers in §1 are showing a specific sheet for a specific reason.

3. **~~Does this belong in this package?~~** **Decided: split.** The **formatter** goes to
   SwiftXLSX, which already owns styles and where every consumer benefits. The **grid** stays
   here, because it renders recognition annotations that only this package knows about.
