# Design Proposal — the command line

**Status:** proposal, 2026-09-11. Phase 0 (Design).
**Scope:** BusinessMathExcel — a new `executableTarget`. The repo is library-only today.
**Why here:** this is the only package that sees the whole stack — SwiftXLSX for the file,
SwiftExcelFunctions for evaluation and simulation, BusinessMath for the mathematics, and its own
recognizer. Nothing below it can host this.

---

## 1. Objective

**Give a practitioner something they can run on Tuesday.**

Every capability this project has is currently reachable only by writing Swift. For an audience
of risk and finance practitioners that is the same as not shipping it. The CLI is not a
convenience wrapper; it is the first delivery vehicle that matches the audience.

```
$ xlsheet run model.xlsx --trials 10000 --seed 4217
  Revenue growth      P5  2.1%   P50  4.8%   P95  7.9%
  Cash shortfall      P5  £0.0m  P50  £1.2m  P95  £4.3m
  seed 4217 · 10,000 trials · 3 uncertain inputs · 2 outputs
```

---

## 2. The command surface

Five verbs. Each maps to a capability that already exists.

| Command | Does | Built on |
|---|---|---|
| `recognize` | recover accounts, periods, rollforwards; report coverage | `ExcelRecognizer` |
| `run` | find uncertain inputs, run seeded trials, report statistics | `ModelSurveyor` + `InterpretedRun` |
| `graph` | emit DOT/Mermaid, or trace one cell | `PROPOSAL_graph_export.md` |
| `audit` | circular references, consistency | `WorkbookAudit` |
| `check` | assert on outputs; **exit non-zero when an assertion fails** | `run` + a predicate file |

### 2.1 `check` is the one that matters

The other four report. `check` turns a workbook into a test:

```yaml
# checks.yaml
- output: "Cash shortfall"
  p95: { max: 4_000_000 }
- output: "DSCR"
  p5:  { min: 1.2 }
- coverage: { min: 0.8 }
```

```
$ xlsheet check model.xlsx --checks checks.yaml --seed 4217
  ✓ Cash shortfall P95 £3.4m ≤ £4.0m
  ✗ DSCR P5 1.08 < 1.20
  exit 1
```

That is the whole "your financial model gets a build status" claim, and it is a few hundred lines
on top of `run`. **Nothing else on the roadmap converts a practitioner as directly**, because it
is the first time a spreadsheet can fail a build.

---

## 3. Decisions that are expensive to change

### 3.1 The seed is always reported, never hidden

A run without an explicit `--seed` picks one and **prints it**, in the human output and in the
JSON. Never silent, never a fixed default that looks like a choice.

This is the product's central claim — that a number can be reproduced — and a CLI that lets you
run without knowing your seed has already broken it. The cost of getting this wrong is not a bug
report; it is a practitioner who cannot reproduce their own result and concludes the tool is as
unaccountable as the one they left.

### 3.2 Exit codes are a taxonomy, not a boolean

CI consumes these, so they are API:

| Code | Meaning |
|---|---|
| 0 | ran, all checks passed |
| 1 | ran, a check failed — the expected "your model regressed" |
| 2 | could not run: not simulable, no uncertain inputs, correlation declared but unsupported |
| 3 | could not read: corrupt file, unsupported feature |
| 4 | usage error |

Distinguishing 1 from 2 is the important one. *"Your model got worse"* and *"I could not evaluate
your model"* must never share an exit code, or a build that silently stopped checking looks green.

### 3.3 Every command takes `--json`

Human output is for reading; JSON is for the service, the MCP surface, and anyone's script. Both
come from the same result type — the human renderer formats the JSON model, never the reverse, so
they cannot drift.

### 3.4 Never write to the input

`run` and `audit` are read-only. Write-back is an explicit `--out`, per
`PROPOSAL_annotated_writeback.md`. A tool that modifies the workbook it was pointed at will be
used exactly once.

---

## 4. What it must refuse

Refusals are a feature here and should be loud, because the alternative is a confident wrong
number:

- **Correlation declared but unimplemented** — `PsiCorrMatrix` present. Exit 2, naming the cells.
  See `PROPOSAL_correlated_inputs.md` §9; this is the same refusal, surfaced.
- **No uncertain inputs** — a workbook with none is not a simulation. Exit 2 rather than
  reporting a degenerate distribution.
- **Recognition returned nothing** — 377 of 674 corpus sheets do this. `recognize` should say
  *why*, from `Residue.reason`, not print an empty model.

---

## 5. Naming

`xlsheet` is used throughout as a placeholder. It should be decided before the first release,
because it ends up in every screenshot, every CI config and the marketing site.

Constraints worth respecting: short, not already taken on Homebrew, and not implying Microsoft
endorsement. `xlsx` is taken by several tools; `sheet` is generic.

---

## 6. Work

| # | Item |
|---|---|
| 1 | `executableTarget`, argument parsing (swift-argument-parser), the result/render split of §3.3 |
| 2 | `recognize` and `audit` — the two that need nothing new |
| 3 | `run`, with seed reporting per §3.1 and refusals per §4 |
| 4 | `graph`, once `PROPOSAL_graph_export.md` lands |
| 5 | `check` — the predicate file format, evaluation, exit codes |
| 6 | Distribution: Homebrew formula, and a notarized binary if it is to run on other people's Macs |

---

## 7. Test strategy

- **Golden output** for each command on a fixture workbook, human and JSON.
- **Exit codes asserted explicitly**, one test per row of §3.2 — they are API and will be depended
  on by CI configs we never see.
- **Same seed, same stdout.** The strongest end-to-end test available: run twice, diff the JSON,
  require byte equality. It exercises the reproducibility claim through the whole stack rather
  than at the sampler.
- **The refusals of §4 each have a test**, because a refusal that silently stops refusing is how
  a green build stops meaning anything.

---

## 8. Open questions

1. **~~Predicate format?~~** **Decided 2026-09-11: a sidecar YAML file.** It diffs cleanly and is
   reviewable in a pull request, which is the whole point of `check` — a changed threshold must be
   visible to whoever approves it. A `_checks` sheet inside the workbook was the alternative and
   was rejected for exactly that reason: `.xlsx` diffs are opaque, so a loosened covenant limit
   would pass review unseen. The cost accepted is a second file that can drift from the model;
   §8.1a is how that is mitigated.
2. **~~By name or by cell?~~** **Decided: accept both, prefer names, and report which matched.**
   Names come from recognition and survive a row insertion; cells are precise and break silently.
   Reporting the match is what stops an assertion that has quietly stopped testing anything.
3. **~~Progress reporting?~~** **Decided: stderr, only when stdout is a TTY.** Keeps stdout
   pipeable, which `--json` depends on.
4. **The tool name** is deferred; `xlsheet` is a placeholder throughout and must be settled before
   the first tagged release, since it lands in every screenshot, CI config and Homebrew formula.

---

## 8.1a Guarding the sidecar against drift

The accepted cost of a separate checks file is that it can silently stop matching the model —
an output gets renamed, the assertion no longer binds, and the build stays green while testing
nothing. That is the same class of failure as a test that cannot fail, and it needs the same
treatment.

**Proposed: an assertion that matches nothing is an error, not a skip.** Exit 2 — *"could not
evaluate"* — naming the output it looked for and listing the outputs that exist. Never exit 0.

A `--strict` mode can go further and require every model output to be covered by at least one
assertion, which is the spreadsheet equivalent of a coverage floor.
