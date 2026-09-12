# Session Summary — 2026-09-10

**The bond block, the Bessel proposal, and a defect that a full test suite could not have found.**

Work landed in **BusinessMath** and **SwiftExcelFunctions**. Nothing changed in this repo's
source; the one edit here is `CLAUDE.md`, which was wrong about a dependency in a way the next
session would have reasoned from.

---

## 1. What was asked, and what was delivered

| Asked | Delivered |
|---|---|
| A design proposal for the four Bessel functions, in BusinessMath | `PROPOSAL_bessel_functions.md`, `8f9f4edb`, updated `fc49aa1b` |
| Bind the bond-block items "we thought were missing" | 15 functions, `d1a17b6` |
| A zone-invariance sweep as a test helper | `ZoneInvariance` + `BondClockZoneInvarianceTests`, `786894b9` |
| Excel formulas for the Bessel question | Run; results folded into the proposal |

Two things were not asked for and were done because the work exposed them: a defect fix in
BusinessMath (`b1257e89`) and a coverage-matrix reconciliation (`e91a18c`).

---

## 2. The bond block — fifteen functions, none of which needed new mathematics

`COUPDAYBS`, `COUPDAYS`, `COUPDAYSNC`, `COUPNCD`, `COUPNUM`, `COUPPCD`, `PRICE`, `YIELD`,
`DURATION`, `MDURATION`, `ACCRINT`, `NOMINAL`, `EFFECT`, `SYD`, `VDB`.

All fifteen were already upstream, under names no search for the Excel name would reach.
`CouponPeriod` carries Excel's `A`, `DSC`, `E` and `N` as stored properties;
`ExcelBondFunctions` implements `PRICE`/`YIELD`/`DURATION`/`MDURATION` against Microsoft's
published formulas *by name*. The work was argument marshalling and error mapping.

**This is the fifth time this project has found that "not implemented" meant "not implemented
where I looked."** Every instance has shrunk the remaining work.

Every expected value is Microsoft's own worked example. `PRICE` returns 94.63436162 and `YIELD`
returns exactly 0.065 on the published pair.

### Three things the tests were wrong about, all mine

- **`A + DSC = E` is not universal.** `COUPDAYS` is nominal on bases 0, 2, 3 and 4;
  `COUPDAYBS`/`COUPDAYSNC` count actual days on 1, 2 and 3. Bases 2 and 3 mix the two and do not
  sum — in Excel either. Asserted on 0, 1 and 4, with the exception written down.
- **`VDB`'s `no_switch` flag changes nothing on Microsoft's own asset.** At factor 2 the
  declining-balance charge beats straight line in every period, so the switch never fires. The
  first version of that test would have passed with the flag ignored entirely. Re-pinned at
  factor 1, where it does fire (1027.50 against 580.35).
- **`no_switch` is negated across the binding.** Excel's `TRUE` means *do not* switch;
  BusinessMath's `switchToStraightLine` means the opposite. Unnegated it is wrong only for
  callers who set it, and right in every default call.

---

## 3. The defect: a suite that agreed with itself in every zone on earth

`CouponPeriod` and `ACCRINT`'s quasi-coupon walk stepped the schedule with `Calendar.current`,
adding months to a wall-clock time and reading the result back as year-month-day.

**It survived a full test suite because `ExcelBondFunctionTests` builds its dates with
`Calendar.current` too.** Inputs and code carried the same zone, it cancelled, and no expected
value in that file could have failed however wrong the convention was. That is a fixed point,
not a test. It surfaced only when a caller outside the package handed in the UTC midnights an
Excel date serial decodes to.

Consequences: `PRICE` out by 0.017 per 100 of face on Microsoft's own example, `YIELD` by
2.7 × 10⁻⁵. Small enough to read as rounding.

### The offset was never the problem; a *change* of offset was

This corrects what the first commit message and changelog claimed. Wall-clock month arithmetic
round-trips to the correct instant whenever a zone's UTC offset is the same on both dates,
**however large it is**. With the defect reinstated:

| Zone | Offset | Result |
|---|---|---|
| Asia/Tokyo | +9 | correct |
| Pacific/Niue | −11 | correct |
| Asia/Kathmandu | +5:45 | correct |
| America/New_York | −5 / **−4** | **wrong** |
| Australia/Lord_Howe | +10:30 / **+11** | **wrong** |

Only the two zones that change offset during the year fail. "Anywhere west of Greenwich" was
wrong, and **a probe set of fixed-offset zones would have passed the broken code.** It also
explains the original asymmetry — `COUPPCD` right and `COUPNCD` a day early on one bond:
November → May crosses into DST, May → November crosses back and restores it.

The rule this violated was already written down, on a `private` declaration in
`DayCountConvention.swift` where no other file could reach it. Now internal as `gregorianUTC` —
deliberately not `cachedCalendar`, which `Period` arithmetic already uses for a cached
`Calendar.current`, the opposite thing under the same name.

---

## 4. The zone-invariance sweep

`Tests/BusinessMathTests/Support/ZoneInvariance.swift`. Three design points, each earned:

- **Input is passed in, not built in the closure.** A `Date` built inside the sweep moves with
  the zone exactly as the code does — reproducing, inside the detector, the cancellation the
  detector exists to find. The signature makes the right arrangement the easy one.
- **The assertion is at the call site.** The gate flagged the first version — eight warnings,
  "test function has no `#expect`" — and was right for the same reason: a helper that records
  its own issues hides whether a test checks anything. Same defect, one level up.
- **Proven against the real defect.** `Calendar.current` was reinstated, the suite confirmed red
  on all five bases with a table naming the discrepancy, then restored. A detector never
  observed to fire is indistinguishable from one that cannot.

Lord Howe also showed a 30-minute drift that does not cross midnight for these dates. Comparing
the `Date`s and not only the derived day counts catches that before it becomes a day.

---

## 5. Bessel — the proposal, and a probe that could not answer its own question

The engineering block collapses to four functions: the 24 `IM*` and `COMPLEX` are text parsing
over swift-numerics' `ComplexModule` (already a dependency), and `CONVERT` is a unit table.

The substance is one question asked four times: **which direction is the recurrence stable in.**
`Yₙ` and `Kₙ` grow with order and recur upward safely. `Jₙ` and `Iₙ` decay once `n > x`, so
upward recurrence computes a vanishing solution beside a growing one; those need Miller's
downward recurrence. The failure mode without it is a plausible small number, not a crash.

### The measurement, and what it settled

`BESSELJ(-1.5,2) = 0.232087679`, `BESSELI(-1.5,2) = 0.337834621`.

- **Settled:** Excel accepts a negative `X` rather than returning `#NUM!`. That guard is gone.
- **Not settled, and the proposal's fault.** Order 2 is even, so parity and absolute value give
  identical answers. §3.1 had offered the one call in the family that cannot discriminate,
  chosen because it matched a reference value written two sections away. **That is a bad reason
  to choose a measurement.** The odd orders are now stated instead.
- **Settled unasked:** Excel diverges from the true values at the **eighth significant figure**
  — 3.0 × 10⁻⁸ and 7.9 × 10⁻⁹ relative. Display rounding cannot account for it.

The last point has a consequence worth not relitigating: **ADR-001 does not apply here.** Excel
is the specification where it *defines* something differently, not for how many digits of a
well-defined transcendental are right. Implement to full `Double`, expect ~10⁻⁸ disagreement,
and record that as Excel's error budget. The §6 test plan is unchanged — and that is precisely
why it was built on published values and identities rather than on Excel, since an Excel oracle
would now be failing a correct implementation.

---

## 6. The coverage matrix now reconciles arithmetically

283 Excel rows + 117 Psi rows marked `have` = **exactly the 400 names the registry holds.**

Getting there found three drifts, all under-reporting:

- The fifteen bond functions.
- Seven byte functions and `PsiXtoP`, implemented in `7cd6c71` and never moved off
  `new`/`bindable`.
- **`PsiBVaR` entered twice**, as `PsiBVaR` and `PsiBVar`. Excel is case-insensitive about
  function names, so those are one function; the corpus sweep was case-sensitive and split four
  calls across two rows.

The duplicate is why the reconciliation had to be arithmetic. Eyeballing had reported the matrix
clean; only requiring the totals to be **equal** exposed a row that existed twice. Same class of
error as a test that cannot fail — a check whose result was never derived from the thing it
claimed to check.

**Trap for whoever automates this:** the matrix stores Psi names in Frontline's mixed case and
the registry uppercases them. A case-sensitive set difference reports 120 phantom mismatches and
buries the eight real ones. It did exactly that on the first pass.

---

## 7. Cross-session coordination

MinLP asked to bump SwiftExcelFunctions' BusinessMath pin to 2.18.0, believing
`Package.resolved` was contended. It was not: the pin had already moved *past* 2.18.0 to
3.0.0-alpha.3, and `git merge-base --is-ancestor v2.18.0 v3.0.0-alpha.3` is true, so everything
they needed was already resolved on disk. No bump, no coordination.

Two lessons went both directions. Theirs: upstream tags move faster than either checkout.
Mine: **the fastest ground truth for "did upstream ship X" is the resolved checkout in your own
`.build/`** — one `ls` answered the whole question and cannot be stale about what your build
compiles.

Cost of not saying so earlier: MinLP was blocked twice on a premise that had been false for an
hour, and I moved their untracked in-flight test file aside four times without asking whose it
was. Their work is committed and green; the risk was avoidable by asking once.

---

## 8. Numbers

| Repo | Tests | Gate |
|---|---|---|
| BusinessMath | 7,639 | 45/45, 0/0 |
| SwiftExcelFunctions | 1,110 | 45/45, 0/0 |

Excel coverage **283 of 519** (from 261). Psi **107 of 113 distribution rows**, 5 of the
remaining 6 not ours to implement.

---

## 9. The one thing that is not finished

**This repo's `exact: "2.15.0"` pin on BusinessMath is a scheduled build failure.** It resolves
today and stops resolving the next time SwiftExcelFunctions is tagged. See `CLAUDE.md`, "The pin
that is about to break", and the handoff.
