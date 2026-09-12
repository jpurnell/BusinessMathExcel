# Session Handoff — 2026-09-10

Resume here. Last session's handoff opened with *"nothing is blocking"*. **That is no longer
true**, and the one blocking item is dated rather than vague: this repo stops resolving the next
time SwiftExcelFunctions is tagged.

Everything else is finished, green, and committed.

---

## 1. The next step, concretely — and it is not optional

**Loosen this repo's BusinessMath pin before bumping SwiftExcelFunctions.**

```
Package.swift:13   .package(url: ".../BusinessMath", exact: "2.15.0")
```

| | requires BusinessMath at | resolves? |
|---|---|---|
| this repo | `exact: "2.15.0"` | — |
| SwiftExcelFunctions **v0.7.1** (what we pin) | `from: "2.11.0"` | ✅ satisfied by 2.15.0 |
| SwiftExcelFunctions **`main`** (unreleased) | `.upToNextMinor(from: "3.0.0-alpha.3")` | ❌ unsatisfiable |

`exact: "2.15.0"` cannot satisfy `>= 3.0.0-alpha.3`. Today's build is fine because we resolve
v0.7.1, whose manifest still asks for `from: "2.11.0"`. The moment SwiftExcelFunctions cuts a
release carrying the bond block, this repo fails to resolve.

**Do not try to fix it by loosening this repo's pin alone — that was tried on 2026-09-10 and
does not resolve.** SwiftExcelFunctions v0.7.1, the release we pin, itself requires BusinessMath
`< 3.0.0`, so no pin this repo can write satisfies both that and `>= 3.0.0-alpha.3`. Both forms
fail:

```
exact: "3.0.0-alpha.3"                    → conflicts with swiftexcelfunctions 0.7.1
.upToNextMinor(from: "3.0.0-alpha.3")     → same, reported as an empty prerelease range
```

**The order is forced:**

1. SwiftExcelFunctions cuts a release requiring the BusinessMath 3.0.0 line. *(Justin said one
   is coming — this is the trigger.)*
2. **One commit here** bumping *both* pins: SwiftExcelFunctions to the new release, and
   BusinessMath from `exact: "2.15.0"` to `.upToNextMinor(from: "3.0.0-alpha.N")`.
3. `swift build && swift test` — the 572 tests here have never run against BusinessMath 3.0.0,
   which removed `sampleSize` among other things. Budget for that rather than assuming additive.

The prerelease range form matters: SwiftPM will not resolve a prerelease through a range whose
lower bound is not itself one, so a plain `from: "3.0.0"` sees no alpha at all.

This is the failure `CLAUDE.md`'s own "Why the pins are loose" section describes, arriving on
schedule. That reasoning was applied to SwiftExcelCore and never carried across to BusinessMath,
which is the same shared-package situation one dependency over.

**Do this, then verify with `swift build && swift test` here, then tag SwiftExcelFunctions.**

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
