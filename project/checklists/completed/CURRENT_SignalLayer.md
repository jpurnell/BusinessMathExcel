# Implementation Checklist: Signal Layer (RRBuffer + HRVMetrics)

**Proposal:** `project/plans/upcoming/SignalLayer-RRBuffer-HRVMetrics.md` (v3, APPROVED)
**Validation Playground:** `project/plans/upcoming/SignalLayer-Playground.swift` (verified)

---

## Current Phase: COMPLETE — ready for next proposal

**Final status:** 46 tests passing (10 prior + 36 new), zero warnings, zero forbidden patterns.

### 0. Design Proposal ✅
- [x] Objective documented
- [x] Architecture proposed (EctopicFilter protocol, RRBuffer, HRVMetrics)
- [x] API surface sketched
- [x] Constraints compliance verified (Sendable, Swift 6 strict, no force unwraps)
- [x] Dependencies identified (BusinessMath only)
- [x] Test strategy outlined
- [x] Open questions resolved (Malik = MedianMalikFilter default; window = generic Collection; pNN threshold = 50.0 ms; n−1 denominator)
- [x] Proposal approved by user
- [x] Validation playground runs and matches hand-computed expected values

### 1. RED — Failing Tests First

**Test files to create (must compile and FAIL before any implementation):**

#### `Tests/BioFeedbackKitTests/EctopicFilterTests.swift`
- [x]`PercentChangeFilter`: first sample always accepted
- [x]`PercentChangeFilter`: sample within 20% of previous accepted
- [x]`PercentChangeFilter`: sample exceeding 20% rejected
- [x]`PercentChangeFilter`: custom threshold honored
- [x]`PercentChangeFilter`: `reset()` clears state
- [x]`MedianMalikFilter`: first 5 samples bootstrap from previous-sample comparison
- [x]`MedianMalikFilter`: established window — sample within 20% of running median accepted
- [x]`MedianMalikFilter`: established window — sample exceeding 20% of running median rejected
- [x]`MedianMalikFilter`: bursty artifact (one bad beat) does not corrupt subsequent comparisons (this is the whole point of using median)
- [x]`MedianMalikFilter`: custom windowSize honored
- [x]`MedianMalikFilter`: `reset()` clears state

#### `Tests/BioFeedbackKitTests/RRBufferTests.swift`
- [x]Range gate: RR < 300ms rejected
- [x]Range gate: RR > 2000ms rejected
- [x]Range gate: custom range honored
- [x]Composition: range gate runs before ectopic filter
- [x]Convenience init produces a `MedianMalikFilter`-backed buffer
- [x]`process(_:)` returns nil for rejected samples
- [x]`reset()` clears the underlying filter
- [x]`AsyncSequence.filtered(by:)` drops rejected samples (use MockDevice as source)

#### `Tests/BioFeedbackKitTests/HRVMetricsTests.swift`
- [x]**Golden path (primary fixture):** `[800, 820, 790, 810, 830, 805]` →
  - `meanRR ≈ 809.166667`
  - `rmssd ≈ 23.345235`
  - `sdnn ≈ 14.288690`
  - `pnn = 0.0`
  - `pnnThreshold = 50.0`
  - `sampleCount = 6`
- [x]**All-70ms-jumps fixture:** `[800, 870, 800, 870, 800, 870]` → `pnn = 1.0`, `rmssd = 70.0`
- [x]**Boundary fixture (50 ms exact):** `[800, 850, 800, 850, 800, 850]` → `pnn = 0.0` (strict `>`)
- [x]**Constant fixture:** `[800, 800, 800, 800]` → `rmssd = 0`, `sdnn = 0`, `pnn = 0`
- [x]**Insufficient samples:** 0-sample window throws `SignalError.insufficientSamples`
- [x]**Insufficient samples:** 1-sample window throws `SignalError.insufficientSamples`
- [x]**Custom pnnThreshold:** primary fixture with `pnnThreshold = 20.0` → `pnn` matches hand-counted (diffs > 20 ms: |−30|, |−25| = 2/5 = 0.4)
- [x]**Generic Collection — ArraySlice:** pass `samples[1..<5]`, verify computation
- [x]**Generic Collection — Array:** baseline path
- [x]**Equatable:** two HRVMetrics with identical fields are equal

**Run RED:**
```bash
cd BioFeedbackKit && swift test --filter "Signal" 2>&1
# Expected: tests fail to compile (types don't exist yet) — that's the RED state
```

### 2. GREEN — Minimum Implementation
- [x]`Sources/BioFeedbackKit/Signal/SignalError.swift`
- [x]`Sources/BioFeedbackKit/Signal/EctopicFilter.swift` (protocol + `PercentChangeFilter` + `MedianMalikFilter`)
- [x]`Sources/BioFeedbackKit/Signal/RRBuffer.swift`
- [x]`Sources/BioFeedbackKit/Signal/HRVMetrics.swift`
- [x]`Sources/BioFeedbackKit/Signal/AsyncFilteredRRSequence.swift`
- [x]All Signal tests PASS

### 3. REFACTOR
- [x]Remove duplication
- [x]Improve naming
- [x]**Safety audit:** no `!`, `as!`, `try!`, `fatalError`, `while true` in new code
- [x]All tests still green

### 4. DOCUMENT
- [x]DocC `///` on every public symbol
- [x]Document n−1 pNN denominator choice with citation
- [x]Document MedianMalikFilter algorithm with citation
- [x]Usage example in HRVMetrics doc

### 5. VERIFY (Zero Warnings Gate)
- [x]`swift build` zero warnings
- [x]`swift test` all pass
- [x]No forbidden patterns
- [x]Public API doc coverage 100%

---

## Notes

- The validation playground at `UPCOMING/SignalLayer-Playground.swift` produced the
  exact `Double` values used in the golden-path assertions. Re-run it any time the
  test fixtures are modified.
- BusinessMath operators wired in: `mean`, `stdDev` (sample), `successiveDifferences`.
  `rollingSuccessiveDifferenceRMS` and `rollingThresholdExceedanceRate` are reserved
  for the streaming fast-follow.

---

**Last Updated:** 2026-04-06
