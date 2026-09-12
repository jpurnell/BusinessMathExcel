# Design Proposal — licensing the family

**Status:** proposal, 2026-09-11. Phase 0 (Design).
**Scope:** all five public repos — SwiftExcelCore, SwiftXLSX, SwiftExcelFunctions, BusinessMath,
BusinessMathExcel — plus the private SwiftZIP.
**Supersedes the licence choice in** `BusinessMath/project/plans/proposals/v3.0-DualLicensing.md`,
whose reasoning was sound when written and whose conclusion is now wrong for one specific reason
(§4).

---

## 1. The current state is the one state with no upside

Measured 2026-09-11 against GitHub:

| Repo | Visibility | `LICENSE` file | README says |
|---|---|---|---|
| BusinessMathExcel | **public** | **none** | "MIT" |
| BusinessMath | **public** | **none** | "MIT License - see [LICENSE](LICENSE)" — **the link is dead** |
| SwiftXLSX | **public** | **none** | "See LICENSE file." — **there isn't one** |
| SwiftExcelFunctions | **public** | **none** | nothing |
| SwiftExcelCore | **public** | **none** | nothing |
| SwiftZIP | private | none | — |

**No `LICENSE` file means all rights reserved.** Copyright is automatic; permission is not. So the
default position is that nobody may use, copy, modify or redistribute any of this.

Except that two READMEs say "MIT", which is plausibly an offer of a grant, and a third points at a
file that does not exist.

This is the worst of both worlds, and it is worth being precise about why:

- **It blocks the adopters worth having.** Any organisation with a legal function runs a licence
  scan. A public repo with no `LICENSE` fails it. The careful commercial adopter — exactly the one
  who would pay — cannot proceed.
- **It does not block the ones you would rather it did.** Someone who copies the code and points
  at the README's "MIT" has a real argument.
- **It cannot be fixed retroactively for what is already out.** Anything already taken under a
  visible "MIT" claim stays taken. Fixing this is about *going forward*, and every day it stays
  unfixed adds to what went out ambiguously.

**This should be fixed before the marketing site, and it is hours of work, not days.**

---

## 2. Objective

Two things at once, which is what dual licensing is for:

1. **Adoption** — anyone may read, evaluate, learn from and contribute to this.
2. **Revenue** — an organisation putting it inside a proprietary product or a hosted service pays.

The pricing anchor is not hypothetical. Analytic Solver Simulation is **$375/month, roughly $2,520
a year on the annual plan, per seat, Windows desktop**, with add-on engines at $3,750–$13,500 a
year. This stack does the simulation half of that without the seat, the platform, or the add-in.

---

## 3. Do not license the family uniformly

Copyleft may depend on permissive; permissive may not depend on copyleft. That asymmetry is a
strategy, not just a constraint — split the family along the line where the value actually sits.

| Layer | Proposed | Reasoning |
|---|---|---|
| **SwiftExcelCore** | **Apache 2.0** | vocabulary — `CellValue`, `CellRef`, `FormulaAST`. Nobody will ever pay for this, and everything else is more useful if it spreads. |
| **SwiftXLSX** | **Apache 2.0** | a reader/writer. Genuinely good, genuinely commodity; half a dozen exist in other languages. Permissive here is what makes the family adoptable. |
| **SwiftExcelFunctions** | **AGPLv3 + commercial** | 400 functions, 283 of Excel's 519, and **107 of Frontline's 113 distribution rows**. This is the part that replaces a paid product. |
| **BusinessMath** | **AGPLv3 + commercial** | the mathematics, 7,639 tests. Already the subject of `v3.0-DualLicensing.md`. |
| **BusinessMathExcel** | **AGPLv3 + commercial** | the recognizer and the simulation loop — the differentiated work. |

**Apache 2.0 rather than MIT for the permissive half**, for its explicit patent grant. MIT is
silent on patents, which is a question enterprise counsel asks and a reason a scan gets escalated.

Apache 2.0 is one-way compatible into GPLv3/AGPLv3, so the copyleft half may depend on the
permissive half. Verified for the external dependencies too: swift-numerics, swift-crypto,
swift-collections, swift-asn1 and swift-syntax are all Apache 2.0.

---

## 4. AGPLv3, not GPLv3 — and this is the correction

`v3.0-DualLicensing.md` §1 says:

> *"**Why GPLv3 (not AGPLv3):** BusinessMath is a library consumed via SPM, not a network service.
> GPLv3's distribution trigger is the correct fit."*

**That was true when it was written and is now wrong**, because the roadmap has since put a hosted
service on it — `PROPOSAL_hosted_service.md`, roadmap item 7 — and the practitioner argument leans
on running the model anywhere, including as a service.

GPLv3's copyleft obligations trigger on **distribution**. A competitor who takes this, stands it up
as a SaaS, and never ships a binary to anyone **distributes nothing and therefore owes nothing** —
not the source, not a fee. That is the ASP loophole, and closing it is the entire reason AGPLv3
exists: its §13 extends the obligation to users interacting with the software **over a network**.

For a product whose most valuable deployment is a hosted one, **GPLv3 leaves the crown jewels
unprotected.** The correction is small and the consequence is not.

### 4.1 The objection, and why it does not apply here

AGPL is unpopular with enterprises, and some ban it outright. That is usually an argument against
it — and here it is the *mechanism*. The commercial licence exists precisely for the organisation
whose policy forbids AGPL. A licence nobody objects to is a licence nobody pays to escape.

The population that matters is not put off: a bank replacing a $2,520-a-seat add-in will not
publish its model pipeline, so it buys a commercial licence. That is the transaction.

---

## 5. What has to be true for the commercial half to work

1. **Sole authorship.** `v3.0-DualLicensing.md` records it, and it is the thing that makes this
   possible at all — dual licensing requires holding all the rights. **The moment a second
   contributor lands, a CLA or DCO becomes a prerequisite**, and retrofitting one is painful.
   Whatever else is decided, get the contribution terms in place before the first outside PR.
2. **Provenance is clean.** No code copied from a licence-incompatible source. Worth one honest
   pass, particularly over anything transcribed from published algorithms.
3. **The private dependency is resolved.** §7.
4. **A `LICENSING.md` that a non-lawyer can act on** — the three-line version of "free if you
   publish, paid if you do not, here is who to email".

---

## 6. Work

| # | Item | Urgency |
|---|---|---|
| 1 | `LICENSE` in all six repos, and READMEs corrected to match | **immediate** — the current state has no upside |
| 2 | `LICENSING.md` in each copyleft repo, with the commercial route named | immediate |
| 3 | Contribution terms (DCO or CLA) before any external PR | before the site drives traffic |
| 4 | Provenance pass, §5.2 | before first commercial sale |
| 5 | Decide the commercial price and shape | with the marketing site |
| 6 | SwiftZIP, §7 | **immediate** — it is broken today, licence aside |

---

## 7. SwiftZIP is a working problem, not only a licensing one

**SwiftXLSX is public and depends on `jpurnell/SwiftZIP`, which is private.** Anybody who clones
SwiftXLSX cannot resolve it, cannot build it, and gets a 404 that reads like a missing package
rather than a missing permission.

That is true today, independent of any licensing decision, and it quietly makes a public package
unusable by the public it was published to. Three ways out:

| Option | Consequence |
|---|---|
| Make SwiftZIP public, Apache 2.0 | simplest; it is plumbing, and matches §3's treatment of the layer it serves |
| Vendor it into SwiftXLSX | removes a dependency, duplicates the code, and inherits its maintenance |
| Keep SwiftXLSX private too | coherent, and gives up the adoption the permissive half exists to buy |

**Recommend making it public under Apache 2.0.** It is a zip reader; it is not the moat, and it is
currently breaking the one repo whose whole job is to be easy to adopt.

---

## 8. Open questions

1. **Does anything already published under the "MIT" README claim need honouring explicitly?**
   Legally the exposure is limited and unavoidable; the question is whether to say so plainly in
   `LICENSING.md` — e.g. that versions tagged before the licence change remain usable under the
   terms then stated. Saying it costs nothing and buys goodwill with anyone who acted in good
   faith.
2. **Commercial price and shape.** Per-seat mirrors the incumbent and invites the same comparison;
   per-deployment or per-organisation matches the actual value, which is that a seat is no longer
   the unit. Out of scope here and squarely a question for the marketing site.
3. **Where does the Pro tier sit?** `v3.0-DualLicensing.md` proposes BusinessMathPro as a separate
   closed tier. That is orthogonal to this and should not be conflated with the dual licence —
   open core and dual licensing are different revenue mechanisms and it is worth being explicit
   about running both.
4. **Fresh repo or relicense in place?** `v3.0-DualLicensing.md` argues for a fresh repository to
   get clean history. That reasoning was about BusinessMath alone; across five repos the cost is
   five times higher and the benefit is the same clean-history story a `LICENSE` commit plus a
   clear `LICENSING.md` mostly delivers. Leaning relicense-in-place, but it is genuinely arguable.
