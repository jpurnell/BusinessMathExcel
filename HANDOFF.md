# Session Handoff — 2026-09-12

Resume here. **The 2026-09-10 handoff's blocking item is resolved, and a larger one was found and
also resolved.** Nothing is blocking now.

---

## 1. What happened on 2026-09-12

A provenance audit found third-party material published in git history. Both findings verified
directly rather than taken on report, and both are now removed.

| Repo | Problem | Treatment | Verified |
|---|---|---|---|
| SwiftXLSX | an unrelated client's confidential hardware documentation | deleted & recreated | fresh clone: 2 refs, 0 client paths, 194 KiB |
| BusinessMathExcel | same | deleted & recreated | fresh clone: 2 refs, 0 client paths, 488 KiB |
| BusinessMath | ~90 MB of copyrighted books | `filter-repo`, surgical | fresh clone: 0 book paths, 0 refs reaching the commit, 141 → 61 MiB |

The runbook is [`proposals/PROPOSAL_history_remediation.md`](proposals/PROPOSAL_history_remediation.md),
corrected in place as the operation taught it things — §B1a, §B1b and §B1c are all findings from
execution, not design.

**Current versions, all pins moved together:**

```
SwiftZIP  0.6.0  ·  SwiftExcelCore  0.8.0  ·  SwiftXLSX  0.25.0
SwiftExcelFunctions  0.9.3  ·  BusinessMath  3.0.0-alpha.4  ·  BusinessMathExcel  0.9.0
```

`Apache 2.0` for the first three, `AGPLv3 + commercial` for the last three.

### The three things that nearly went wrong

Each was caught by verification or by a peer session, not by the plan:

1. **62 GPG-signed commits** make `filter-repo` move 95 of 108 tags rather than 20 — so the
   rewritten tags must **never** be pushed. `--mirror` or `--tags` would have moved 88 version
   numbers onto new SHAs and broken SwiftPM fingerprints on every machine that had resolved them.
2. **`main` and tags are not all the refs.** BusinessMath was declared done while three feature
   branches still carried the books. Verify with `git for-each-ref --contains <commit>` on a
   **fresh clone** — every local signal was green while the remote was still dirty.
3. **`git fetch` prunes neither branches nor tags.** A clone that fetched before a rewrite still
   holds the deleted tags, and one `git push --tags` resurrects everything.

---

## 1a. If you have another clone anywhere

**Both halves, not just the reset:**

```bash
git fetch --prune --prune-tags origin && git reset --hard origin/main
```

Applies to any machine, cloud session, or CI with a persistent workspace that fetched before
2026-09-12. Checked on this machine and clean; **not verifiable elsewhere.**

---

## 1b. Still outstanding

- **GitHub unreferenced objects for BusinessMath.** It was force-pushed rather than recreated, so
  the removed blobs remain retrievable by direct SHA until a support request expires them.
  SwiftXLSX and BusinessMathExcel do not have this problem — deletion destroyed their object
  stores.
- **Licence detection** reads "pending" on all six. The files are correct on the remotes.
- **Contribution terms.** Sole authorship is what makes the dual licence possible; a DCO or CLA is
  needed before the first outside PR, and retrofitting one is painful.
- The roadmap's work — correlation, graph export, CLI — is untouched and unchanged. See
  [`ROADMAP.md`](ROADMAP.md).

---

## 2. State

| Repo | Tag | Unpushed | Working tree | Tests | Gate |
|---|---|---|---|---|---|
| BusinessMath | `v3.0.0-alpha.3` | **4** | clean | 7,639 | 45/45, 0/0 |
| SwiftExcelFunctions | `v0.7.1` | **5+** | MinLP active | 1,110 | 45/45, 0/0 |
| BusinessMathExcel | `v0.7.0` | 0 | this session's docs | 568 | 45/45, 0/0 |

**Nothing is pushed.** BusinessMath's four include two from another session, one of them a
breaking change (`feat(solvers)!: timeLimit is Duration?`). SwiftExcelFunctions' five include
MinLP's ETS work, and **they were mid-edit at last check** — do not touch that repo's working
tree without asking them.

Coverage: **283 of Excel's 519** documented worksheet functions (from 261), **107 of Frontline's
113 distribution rows**.

---

## 3. Ripe, not urgent

1. **Bessel implementation.** Justin is doing this. Two Excel cells are still unrun and **block
   the first guard clause**: `=BESSELJ(-1.5,1)` and `=BESSELI(-1.5,1)`. Even orders cannot
   discriminate parity from absolute value — see the proposal's §3.1, which got this wrong first
   time. §5.2 is where the time goes.
2. **Releases.** SwiftExcelFunctions is 5+ past `v0.7.1` with the bond block and ETS bindings;
   BusinessMathExcel is well past `v0.7.0`. Gated on item 1 above for SwiftExcelFunctions.
3. **BusinessMath's adversarial test pass** is in flight. The zone-invariance sweep is built for
   it — see below.
4. **The corpus census still traps with signal 5**, so the matrix's `calls`/`books` columns stay
   unreconciled. The `books` column actually counts **sheets**; renaming it is recorded in
   BusinessMath's `excel-coverage/README.md` and should happen when the sweep is next run.

---

## 4. For the adversarial test pass

`BusinessMathTests/Support/ZoneInvariance.swift` runs a computation under six time zones and
reports whether the answer moved. Use it like this:

```swift
let sweep = try ZoneInvariance.sweep(input: bond) { bond in ... }   // input built OUTSIDE
#expect(sweep.isInvariant, "\(sweep)")
```

**The pattern it exists to catch: a test that builds its inputs the same way the code reads
them.** Such a suite is a fixed point — no expected value in it can fail, however wrong the
convention is. That is how the coupon-grid defect survived.

Sites still on `Calendar.current` that decompose a result as year-month-day, worth pointing it
at:

| Site | Walks |
|---|---|
| `BondPricing.swift:193`, `:855` | `cashFlowSchedule` on two bond types — the same month loop that was just fixed |
| `CreditSpreadModel.swift:477–503` | four sites |
| `DebtInstrument.swift:217`, `LeaseAccounting.swift:502` | payment schedules |
| `TimeSeriesOperations.swift:322–336`, `TimeSeriesAnalytics.swift:175` | |
| `Period.swift:17`, `PeriodArithmetic.swift:56` | `private let cachedCalendar = Calendar.current` |

Three cautions:

- **The discriminator is not "uses `Calendar.current`"** but *"reads the result back as
  year-month-day."* Measuring elapsed time is fine. `FiscalCalendar` may genuinely want the
  user's calendar — that one is a judgement call, not a defect.
- **Keep at least two DST zones in any derived probe set.** A fixed-offset set passes the broken
  code; only offset *changes* break wall-clock arithmetic.
- **The sweep cannot see the two `cachedCalendar` sites.** A file-scope `let` resolves once at
  first touch and never re-reads the default, so the sweep reports them invariant while their
  answer actually depends on test *ordering*. Worse than zone dependence, and findable only by
  reading. Recorded on the type as `cachedCalendarSites`.

---

## 5. Decisions worth not relitigating

- **ADR-001 does not govern Excel's precision.** Excel is the specification where it *defines*
  something differently — a day count, a sign convention — not for how many digits of a
  well-defined transcendental are right. Measured: Excel's Bessel functions carry ~10⁻⁸ relative
  error. Implement to full `Double` and record the gap as Excel's budget, not ours.
- **`.upToNextMinor` over `exact:` for shared packages.** Two `exact:` pins on one shared
  package deadlock the moment they differ. Item 1 is the live instance.
- **Excel's `COUPDAYS` is nominal on bases 0, 2, 3 and 4** while `COUPDAYBS`/`COUPDAYSNC` count
  actual days on 1, 2 and 3, so the three do not sum on bases 2 and 3 — in Excel either. Do not
  "fix" that.
- **`VDB`'s `no_switch` is negated** across the binding, and Microsoft's own example cannot test
  it: at factor 2 the switch never fires.
- **The coverage matrix reconciles arithmetically**, 283 + 117 = 400 registered. Keep it that
  way; comparing by eye missed a row entered twice. Compare **case-insensitively** — the matrix
  uses Frontline's mixed case, the registry uppercases.

---

## 6. How to work here

- **Two other sessions are active on this machine.** MinLP is in SwiftExcelFunctions
  (`ETSArguments`, `BuiltinForecastETS`); another is in BusinessMath's tests. Commit with
  **explicit paths**, never `git add -A`, and ask before moving a file you did not create.
- **The gate builds the working tree, not the index.** It cannot tell you a commit is good.
- **Count the gate's errors and warnings**; do not read the verdict line. Use
  `--continue-on-failure --no-cache`, or a cached checker will report a file it never examined.
- **Never suppress a gate finding.** The `// silent:` escape the logging auditor offers is an
  override; restructure instead. Moving `CouponPeriod`'s construction into the
  `CellValue`-returning closure removed the finding *and* produced better code.
- **"Not there" usually means "not there where I looked."** Six times this project, now
  including all fifteen bond functions. Keyword probes find free functions and miss methods on
  types — `CouponPeriod` carried all six `COUP*` as properties.
