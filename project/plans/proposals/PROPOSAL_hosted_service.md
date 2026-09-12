# Design Proposal — the hosted service

**Status:** proposal, 2026-09-11. Phase 0 (Design) — and **deliberately the thinnest document
here.**
**Scope:** deployment of the existing capabilities. Almost no new computation.

---

## 1. Objective

**Run somebody's model when they push it.**

```yaml
# .github/workflows/model.yml
- uses: <org>/xlsheet-action@v1
  with:
    workbook: models/2027-budget.xlsx
    checks:   models/checks.yaml
    seed:     4217
```

The model reruns on every change, the build fails when a covenant breaks, and the result is
attached to the pull request. That is benefit 4 of the practitioner list — *the model gets a build
status* — delivered where the practitioner's team already works.

---

## 2. Why this is last, and why the document is short

**There is very little new code here.** A service is the CLI, in a container, behind an HTTP
endpoint or a CI action. Every hard question it raises is an operations question:

| Question | Not answerable from the code |
|---|---|
| Who is allowed to run what? | auth, tenancy |
| How long are workbooks kept? | a financial model is confidential; retention is a *commitment*, not a setting |
| What does a 10,000-trial run cost? | needs measurement the CLI will produce |
| What happens to a model that takes four minutes? | queueing, timeouts |
| Where does it run? | the existing deployment target is roseclub.org |

**Designing this before the CLI has users would be guessing at all five.** The CLI answers the
cost question as a byproduct of existing, and the retention question properly belongs to whoever
first wants to upload a real model — which is a conversation, not a design decision.

---

## 3. The two shapes, and which to do first

### 3.1 A CI action — recommended first

The workbook is already in the customer's repository; nothing is uploaded, nothing is retained,
and the confidentiality question does not arise. It is a container that runs `xlsheet check` and
annotates the pull request.

**Almost all of the value, almost none of the operational surface.** It is also the most credible
demonstration of the whole thesis: a spreadsheet, in version control, with a build status.

### 3.2 A hosted endpoint — later, and only on demand

Upload a workbook, get a report. This is where retention, tenancy, auth and cost all become real,
and it should not be built until somebody has asked for it by name.

---

## 4. The one thing worth deciding early

**Determinism must survive the container.** A run in CI has to produce the same numbers as a run
on the analyst's laptop, or the build status means nothing and the central claim is dead.

That is mostly already true — the sampler takes every bit from a caller-supplied `RandomSource`,
and nothing reaches for system entropy — but it should be *asserted* rather than assumed, because
the failure would be silent and discovered late. Proposed: a cross-platform reproducibility test
running the same seed on macOS and Linux and requiring byte-identical output.

That test is worth adding **now**, ahead of any service work, because it protects a claim the
marketing site will make long before the service exists.

---

## 5. Work

| # | Item |
|---|---|
| 1 | The cross-platform determinism test of §4 — do this early, independent of everything else |
| 2 | Linux build of the CLI, and whatever that surfaces |
| 3 | Container image |
| 4 | CI action wrapper, PR annotation |
| 5 | *(deferred)* hosted endpoint, once someone asks |

---

## 6. Open questions

1. **Does the stack build and pass on Linux?** Unknown. BusinessMath pulls swift-crypto,
   swift-asn1 and SwiftDeterminism; SwiftXLSX is Foundation-only. Worth finding out cheaply,
   because it gates items 2–4 entirely and the answer may be "already fine."
2. **What is the licensing model?** The whole pitch is a per-seat product replaced by something
   that is not per-seat. If a service is sold, that decision arrives whether or not anyone has
   made it. Out of scope here, in scope for the marketing site.
3. **PR annotation format.** A comment, a check run, or a job summary. Check runs are the most
   native and the most work.
