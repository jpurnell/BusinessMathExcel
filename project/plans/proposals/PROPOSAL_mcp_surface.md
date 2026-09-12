# Design Proposal — the MCP surface

**Status:** proposal, 2026-09-11. Phase 0 (Design).
**Scope:** a new MCP server over BusinessMathExcel. Depends on the CLI's result types.

---

## 1. Objective

**Let someone ask for the answer in words.**

> *"Run the simulation in `2027-budget.xlsx` and tell me the 95th percentile of cash shortfall."*
>
> *"What feeds cell D47?"*
>
> *"Is there a circular reference in this model?"*

This is the delivery vehicle that dissolves the interface problem entirely. A practitioner who
will never install a CLI and cannot write Swift can still get the answer, and the conversational
frame suits an audience whose actual question is usually "is this model alright?" rather than any
specific command.

---

## 2. Why this is closer than it looks

BusinessMath already ships an MCP server with 200-odd tools. The pattern, the transport and the
deployment are all solved problems in this codebase — what is new is the Excel-facing surface and
the file handling of §4.

Everything the tools would call already exists: `ExcelRecognizer`, `ModelSurveyor`,
`InterpretedRun`, `WorkbookAudit`, `DependencyGraph`.

**Sequence it after the CLI**, not before. The CLI forces the result types to be complete and
serializable, and §3.3 of `PROPOSAL_command_line.md` already requires every command to emit JSON.
An MCP tool is then a thin adapter over a shape that has been exercised. Building MCP first means
designing those types twice.

---

## 3. The tool surface

Deliberately small. A large tool surface is a worse experience than a focused one, because the
model has to choose.

| Tool | Returns |
|---|---|
| `recognize_workbook` | accounts, periods, rollforwards, coverage, and *why* recognition stopped |
| `simulate_workbook` | per-output statistics, **the seed**, trial count, refusal reasons |
| `trace_cell` | the precedent or dependent subgraph of one cell, as text and as Mermaid |
| `audit_workbook` | circular references, consistency findings |

*(`describe_model` was proposed here and dropped — see §7.3. The question it answered, "what am I
even looking at", is real and is the reason somebody reaches for this surface at all; it is
better served by the assistant reasoning over `recognize_workbook`'s structured output than by a
tool returning prose no test can hold.)*

---

## 4. The hard part is files, not tools

MCP tools exchange JSON. Workbooks are binary, frequently 5–50 MB, and live on the caller's disk.
Three options, and the choice constrains deployment:

| | How | Cost |
|---|---|---|
| **Path-based** | the tool takes a filesystem path | only works when the server is local to the file — fine for Claude Code, useless for a hosted server |
| **Upload** | base64 in the call | blows the context window at these sizes; not viable |
| **Handle** | a separate ingest step returns an id; tools take the id | a session and a store, i.e. state |

**Proposed: path-based first**, explicitly scoped to a locally-run server. It is the smallest
thing that works, it matches how Claude Code already operates, and it defers the state question
to `PROPOSAL_hosted_service.md`, which has to answer it anyway for other reasons.

Say so plainly in the tool descriptions rather than letting a remote caller discover it.

---

## 5. The constraint the tools must respect

### 5.1 A run is not instant, and MCP calls are

10,000 trials on a real model takes time. Options are a lower default (1,000 trials, with the
count reported), or a start/poll pair. **Proposed: a lower default with an explicit `trials`
argument**, because a poll interface is a large complication for an audience that mostly wants one
number.

### 5.2 The seed must survive the conversation

Every simulation result includes the seed in its response, and `simulate_workbook` accepts one.
Otherwise the central claim — *you can reproduce this* — is lost precisely where it matters most,
in a chat transcript somebody will paste into a report.

### 5.3 Refusals must be legible to a model, not just to a person

When correlation is declared and unsupported, the response must say so in a form the assistant can
relay accurately — not an error string that gets paraphrased into "the simulation had a problem."
Structured: `refused`, a reason code, and the cells.

---

## 6. Work

| # | Item |
|---|---|
| 1 | Server scaffold, following BusinessMath's existing MCP server |
| 2 | `recognize_workbook`, `audit_workbook`, `trace_cell` — read-only, fast, no state |
| 3 | `simulate_workbook`, with seed in and out per §5.2 |
| 4 | `describe_model` |
| 5 | Path scoping and the safety note of §7.1 |

---

## 7. Open questions

1. **~~Restrict filesystem access?~~** **Decided 2026-09-11: a configured root, required at
   startup.** `--root ~/models`; any path outside it is refused. The server adds no capability the
   host session lacks, but these are confidential financial models and an implicit boundary is not
   a boundary. One flag turns it into a stated, auditable one.
2. **~~One server or two?~~** **Decided: a separate server.** Extending BusinessMath's would make
   BusinessMath depend on SwiftXLSX and SwiftExcelFunctions — inverting the family's dependency
   direction, which the architecture proposal exists to protect — and would add to an already
   200-tool surface. The cost accepted is a second install and a second config.
3. **~~Does `describe_model` belong here?~~** **Decided: dropped.** It was the most useful and the
   least testable thing on the surface — prose nothing can assert on, which would drift silently.
   The assistant can produce the same summary from `recognize_workbook`'s structured output, which
   *is* testable. Same answer for the reader, no untestable tool. The surface is now four.
