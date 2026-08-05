# Session Handover — BusinessMath v2.1.1 → v2.1.3 + narbis Pause

**Date:** 2026-04-06 → 2026-04-07
**Scope:** Three BusinessMath upstream releases shipped, narbis FrequencyDomainMetrics work paused at the right point to resume cleanly

---

## What this session was supposed to be

When the session started, we were working on narbis BioFeedbackKit's
`FrequencyDomainMetrics` v2 — the LF/HF HRV computation that closes out
the Signal layer. The first thing we did was design the proposal,
including a hand-rolled validation playground at
`project/plans/upcoming/FrequencyDomain-Playground.swift`.

## What it actually became

The playground exposed three issues that, in order, escalated the scope:

1. **Linear interpolation produces 33% HF amplitude error at realistic
   1 Hz HRV input** → established that we needed cubic spline
2. **BusinessMath had no `powerSpectralDensity` method** → BusinessMath
   v2.1.1 upstream work
3. **BusinessMath had no interpolation module at all** → BusinessMath
   v2.1.2 upstream work
4. **BusinessMath had ~17 `String(format:)` violations and 2 loose tests
   that v2.1.1/v2.1.2 work surfaced** → BusinessMath v2.1.3 hygiene
   release

Each escalation was deliberately surfaced and approved before proceeding,
not silently scoped in. The narbis FrequencyDomainMetrics work is now
paused at exactly the right point to resume — all the upstream pieces it
needs are shipped and the playground has empirically validated that the
new architecture solves the original problem.

---

## What's shipped (BusinessMath upstream)

### v2.1.1 — Power Spectral Density
- **Tag:** `v2.1.1`
- **Release:** https://github.com/jpurnell/BusinessMath/releases/tag/v2.1.1
- **PR:** #5
- New: `FFTBackend.powerSpectralDensity(_:sampleRate:)`, `PSDBin`, `powerSpectralDensityBins(_:sampleRate:)`
- Fixed: pre-existing 4× scaling bug in `AccelerateFFTBackend.powerSpectrum` (uncovered by the new PSD tests; `vDSP_fft_zripD` returns scaled output that wasn't being compensated)
- 12 new tests, 4720 → 4720 unchanged baseline (the new tests added to the count when v2.1.2 landed)

### v2.1.2 — 1D Interpolation Module
- **Tag:** `v2.1.2`
- **Release:** https://github.com/jpurnell/BusinessMath/releases/tag/v2.1.2
- **PR:** #6
- New: `Vector1D<T>` (completing the vector type family), single `Interpolator` protocol with `Point: VectorSpace` and `Value: Sendable`, `ExtrapolationPolicy<T>`, `InterpolationError`
- Ten 1D scalar interpolators: `NearestNeighbor`, `PreviousValue`, `NextValue`, `Linear`, `CubicSpline` (with 4 boundary conditions: `.natural`, `.notAKnot`, `.clamped`, `.periodic`), `PCHIP`, `Akima` (with `modified: Bool = true` for makima), `CatmullRom` (with `tension: T = 0`), `BSpline` (degrees 1..5), `BarycentricLagrange`
- Ten matching `Vector*` flavors for vector-valued output
- 97 new tests across 11 suites, total **4817 / 4817** passing
- Architecture decisions in `Instruction Set/development-guidelines/rules/10_ARCHITECTURE_DECISIONS.md`: ADR-001 through ADR-004
- Bugs caught by the validation playground BEFORE any package code: NextValue at-knot bug, CatmullRom default tension wrong (0.5 → 0)
- Bug caught during test execution: PreviousValue at last-knot returning ys[n-2]
- Bug caught by CI release-build: cubic spline expression too complex for Swift type checker, fixed by intermediate `let` bindings

### v2.1.3 — Dev-Hygiene Cleanup
- **Tag:** `v2.1.3`
- **Release:** https://github.com/jpurnell/BusinessMath/releases/tag/v2.1.3
- **PR:** #7
- All 17 `String(format:)` violations in `Sources/` and `Tests/` removed
- Flaky `PortfolioUtilitiesTests.Random returns are within reasonable range` fixed via `TestSupport.SeededRNG`
- `accelerateMatchesPureSwift` tightened from peak-bin-only to bin-for-bin at `1e-9`
- `parsevalsTheorem` tightened from `0.5..2.0` ratio to `1e-12`
- 4817 / 4817 still passing, no API changes

---

## What's shipped (narbis local)

### Validation playground for FrequencyDomainMetrics
- `project/plans/upcoming/FrequencyDomain-Playground.swift`
- Standalone, hand-rolled, no BusinessMath dependency
- Both linear and cubic spline implementations side-by-side
- Empirical results on 60s HRV-style fixtures with sampling at 1 Hz:

| Band | Linear error | Cubic error | Improvement |
|---|---|---|---|
| LF (0.10 Hz, 60s) | 6.0% | **0.05%** | ~115× |
| HF (0.25 Hz, 60s) | 32.6% | **2.85%** | ~11× |
| VLF (0.01 Hz, 600s) | 0.06% | **0.001%** | ~60× |

This was the empirical justification for going through the full
BusinessMath interpolation upstream work.

### Process artifacts memorialized
- `project/plans/upcoming/FrequencyDomainMetrics.md` (proposal v2, approved, awaiting v3 amendment)
- `project/checklists/CURRENT_FrequencyDomainMetrics.md` (updated with v2.1.2 dependency notes)
- Personal memories saved to narbis memory dir:
  - `feedback_design_first_tdd.md`
  - `feedback_streaming_followups_need_tdd.md`
  - `feedback_no_silent_design_deviation.md`
  - `feedback_no_string_format.md` (from this session)

### development-guidelines update (canonical + narbis local)
- `/Users/jpurnell/.../Tools/development-guidelines/rules/coding_rules.md` updated:
  - `String(format:)` added to the prominent Forbidden Patterns table at line 78
  - §3.7 strengthened with the actual diagnostic stack-trace fingerprint (`__CFStringAppendFormatCore` / SIGSEGV exit 139)
  - Mechanical grep recipe for quality-gate enforcement
  - Specific failure mode (`%s` + Swift String) documented
- narbis local copy synced

### quality-gate-swift design proposal filed
- `/Users/jpurnell/.../Tools/quality-gate-swift/project/plans/upcoming/StringFormatDetection.md`
- Detailed spec for adding `c-style-format-string` detection to the existing `SafetyAuditor` module
- 18 specified tests, ~310 LoC estimate
- Ready for an implementing instance to pick up cold and execute

---

## Where narbis FrequencyDomainMetrics is paused

**Pause point:** the v2 proposal's Approval Checklist is fully approved
EXCEPT it still defines a BioFeedbackKit-local `InterpolationStrategy`
protocol with `LinearInterpolation` as default. That section needs a v3
amendment that:

1. Replaces the local `InterpolationStrategy` protocol with direct use of
   `BusinessMath.CubicSplineInterpolator<Double>` (boundary `.natural`,
   the Kubios HRV standard)
2. Drops the local `LinearInterpolation` and `WindowFunction` protocols
   from BioFeedbackKit's surface (they were temporary fillers for the
   absence of upstream interpolation; they're now redundant)
3. Updates the API surface section: `FrequencyDomainMetrics.init` no
   longer takes an `interpolation:` parameter, just uses cubic spline by
   default
4. Updates the test plan: dropped fixtures that test the local
   `InterpolationStrategy` (the BusinessMath upstream tests already cover
   that); the FrequencyDomainMetrics tests just verify the end-to-end
   pipeline produces correct LF/HF values

**Resume sequence:**

1. Bump `narbis/BioFeedbackKit/Package.swift` from `BusinessMath` `from: "2.1.1"` to `from: "2.1.3"` (or whatever the latest is when this resumes)
2. Run `swift test` to confirm the existing 55 tests still pass against the new BusinessMath version
3. Amend `project/plans/upcoming/FrequencyDomainMetrics.md` to v3 per the bullets above
4. Get user approval on the v3 amendment
5. Begin RED phase: write `Tests/BioFeedbackKitTests/FrequencyDomainMetricsTests.swift` per the proposal's test strategy
6. GREEN phase: implement `Sources/BioFeedbackKit/Signal/FrequencyDomainMetrics.swift` using `BusinessMath.CubicSplineInterpolator`
7. REFACTOR / DOCUMENT / VERIFY
8. Session summary

---

## Pending follow-ups (lower priority)

These are issues found during BusinessMath work that don't block narbis
but should be addressed:

1. **`Examples/` directory in BusinessMath** still has ~50 `String(format:)`
   violations in `MultipleLinearRegressionExample.swift` and
   `LinearRegressionConvenienceExample.swift`. Not in CI so they don't
   fail anything, but the format-string detection check can't fully
   ship until they're cleaned. Worth a v2.1.4 patch.

2. **`generateRandomReturns(count:mean:stdDev:)`** in
   `Sources/BusinessMath/Portfolio/PortfolioUtilities.swift` still uses
   unseeded `Double.random(in:)`, violating the deterministic-randomness
   rule. The flaky test fix bypassed this by inlining Box-Muller; the
   function itself needs a `using generator: inout some RandomNumberGenerator`
   overload. Additive public API → could ship as v2.1.4 or v2.2.

3. **5 separate test files define their own local `SeededRNG` struct**
   instead of using `TestSupport.SeededRNG`. Worth consolidating in a
   v2.1.4 patch.

4. **The `quality-gate-swift` SafetyAuditor `c-style-format-string`
   detection** still needs to be implemented by another instance.
   Proposal is filed and complete; just needs execution.

---

## Process learnings (from feedback memories)

These were memorialized as personal feedback memories during the session:

- **Design-First TDD is mandatory** — even when the user is in a hurry, even when the change feels small. Caught after I scaffolded the Devices layer code-first early in narbis.
- **Fast-follow features still require full TDD process** — no shortcuts because something is "next."
- **Never silently deviate from an approved design** — caught after I hand-rolled HRVMetrics math when the proposal said to use BusinessMath ops.
- **Never use `String(format:)`** — banned pattern; `%s` with Swift String causes SIGSEGV. Caught after I crashed the FrequencyDomain playground with this exact pattern. The rule existed in `coding_rules.md` but was buried; this session strengthened it and added the fingerprint.

---

## Quality Gate Last Run

- **BusinessMath v2.1.3:** 4817 / 4817 tests passing on macOS 15 + Ubuntu 24.04. Zero compiler warnings. Zero forbidden patterns in `Sources/` or `Tests/`.
- **narbis BioFeedbackKit:** 55 / 55 tests passing against BusinessMath v2.1.1 (last sync). Zero compiler warnings. Will need a re-run after the dependency bump to v2.1.3.

---

## Immediate Next Step (this session)

Per user direction at handover: clean up the three follow-up issues
above as a single **BusinessMath v2.1.4** release:

1. Examples/ format-string cleanup
2. `generateRandomReturns` seeded overload
3. SeededRNG consolidation across 5 test files

Then end the session.
