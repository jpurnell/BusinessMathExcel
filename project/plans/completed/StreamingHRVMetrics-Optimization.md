# Design Proposal: Streaming HRVMetrics — Rolling Optimization Pass

**Status:** DRAFT — held for future activation. Not yet approved.

> **Trigger condition:** Activate this proposal when profiling shows the naive
> streaming `hrvMetrics(window:every:)` operator is the bottleneck for live
> sessions. Specifically, when sliding-window emit cadence × window sample
> count × per-window cost exceeds the device's frame budget.

---

## 1. Objective

Replace the naive "materialize each window, hand to `HRVMetrics(window:)`"
implementation of the streaming HRV operator with a rolling-statistics
implementation that reuses partial sums across overlapping windows.

For a 5-minute window updating every second on 1 Hz data, the naive version
recomputes ~300 samples worth of math 300 times for ~99% overlapping data.
A rolling implementation does O(1) work per stride boundary instead of O(n).

**Master Plan Reference:** Phase 1 — Signal Pipeline (optimization of the
streaming variant).

**Predecessor:** `project/plans/upcoming/StreamingHRVMetrics.md` v1.

---

## 2. Proposed Architecture

**Modified files:**
- `Sources/BioFeedbackKit/Signal/AsyncHRVMetricsSequence.swift` (replace inner loop)

**Possibly new files:**
- `Sources/BioFeedbackKit/Signal/RollingHRVAccumulator.swift` (new helper if rolling state grows complex enough to warrant extraction)

**No public API change.** This is purely an internal swap. The existing tests
from the v1 proposal must continue to pass without modification.

---

## 3. API Surface

No changes. The public surface remains:

```swift
extension AsyncSequence where Element == BioSample {
    public func hrvMetrics(
        window: Duration,
        every stride: Duration? = nil,
        pnnThreshold: Double = 50.0
    ) -> AsyncHRVMetricsSequence<Self>
}
```

---

## 4. Implementation Strategy

### 4.1 What to roll

| Metric | Naive cost per window | Rolling state | Update cost |
|---|---|---|---|
| `meanRR` | O(n) sum + divide | running sum, count | O(1) on add/remove |
| `sdnn` | O(n) sum of squared deviations | running sum, sum-of-squares | O(1) using `Σ(x²) − (Σx)²/n` form |
| `rmssd` | O(n) successive diff RMS | running sum of squared diffs | O(1), but care needed at window boundaries |
| `pnn` | O(n) count of |diff| > threshold | running count of exceeding diffs | O(1) |
| `sampleCount` | O(n) | running count | O(1) |

The hard part is **diffs at window edges**: when a sample falls off the back of
the window, the diff between it and its successor is no longer in the window
(possibly), and a new diff appears at the front. We need to maintain a running
count of diffs and a running sum of squared diffs that correctly reflect only
the diffs whose **both endpoints** lie in the current window.

### 4.2 BusinessMath operators to evaluate

The §12 sketch in the predecessor proposal called out:

- `rollingSuccessiveDifferenceRMS(window:)` — likely directly applicable
- `rollingThresholdExceedanceRate(window:, threshold:)` — likely directly applicable for pnn

**Open question:** Do these operate on count-based windows or time-based windows?
The streaming operator uses time-based windows. If BusinessMath's rolling ops are
count-based, we need either:
- A wrapper that converts time-based windows to count windows per stride boundary (defeats the purpose), OR
- An upstream contribution to BusinessMath adding time-based rolling variants

**Plan:** Read the actual BusinessMath signatures during the design refinement
before this proposal is approved.

### 4.3 Boundary handling

When samples enter or leave the window, the rolling state must update consistently:

```
Sample slides off front:
  - Decrement sampleCount
  - Subtract rrInterval from runningSum
  - Subtract rrInterval² from runningSumSquares
  - If the sample had a successor still in the window:
      - Subtract that diff from runningDiffSumSquares
      - Decrement runningDiffCount
      - If |diff| > pnnThreshold, decrement runningExceedingCount
  - The sample's predecessor's diff is unchanged (predecessor already gone)

Sample slides on at back:
  - Increment sampleCount
  - Add rrInterval to runningSum, rrInterval² to runningSumSquares
  - Compute diff against the previous in-window sample (if any):
      - Add diff² to runningDiffSumSquares
      - Increment runningDiffCount
      - If |diff| > pnnThreshold, increment runningExceedingCount
```

### 4.4 Numerical stability

Rolling sums lose precision over long sessions due to accumulated floating-point
error, especially for `Σ(x²) − (Σx)²/n` form of variance which is famously
unstable. Mitigations:

- **Periodic recomputation:** every K windows (e.g. K=60), recompute the running
  state from scratch by replaying the current window. K is tunable.
- **Welford's online algorithm** for variance instead of the naive sum-of-squares
  form. Welford is numerically stable and updates in O(1).
- **Kahan summation** for the running sums (BusinessMath already uses Kahan for
  its `mean` function — check if there's a Kahan-compensated running-sum helper).

**Decision:** Use Welford for variance, Kahan for the diff sums. Periodic
recomputation as a defense-in-depth backstop with K=600 (10 minutes at 1 Hz).

---

## 5. Constraints & Compliance

- **Concurrency:** No new isolation issues. Internal state lives in the iterator (already mutating).
- **Determinism:** Output values must match the naive version to within `1e−9` ms across the full v1 test suite.
- **Backward compatibility:** Public API unchanged.
- **Swift 6:** Strict concurrency.

---

## 6. Test Strategy

The optimization MUST pass the existing v1 streaming test suite **unchanged**.
That suite already compares streaming output against materialized output for
identical inputs, which is the strongest possible equivalence check.

**Additional tests required for the rolling implementation:**

- **Numerical stability over long sessions:** synthesize 10,000 samples with
  realistic RR variance, run through both naive and rolling implementations,
  assert per-window equivalence within `1e−9` ms.
- **Periodic recomputation kicks in correctly:** verify that the K-window
  refresh actually fires and produces a value identical to a from-scratch
  computation.
- **Edge case — window emptied entirely:** verify state resets cleanly when a
  long device dropout causes the window to drain.
- **Edge case — single sample window persists:** verify correct skip behavior
  when only one sample remains in the rolling state.
- **Stress / property test:** randomized samples, randomized strides, assert
  rolling output matches naive output across N random configurations.
- **Benchmark:** measure ops/sec for window=300s, stride=1s, on 1 Hz data.
  Establish baseline (naive) and target (rolling) and assert the speedup is
  meaningful (≥10×).

---

## 7. Dependencies

**Internal:** v1 streaming HRV operator (`AsyncHRVMetricsSequence`)
**External (BusinessMath):** TBD — need to verify the exact signatures of
`rollingSuccessiveDifferenceRMS` and `rollingThresholdExceedanceRate`. May
require an upstream contribution if those operators are count-based only.

---

## 8. Open Questions

1. **Are BusinessMath's rolling ops time-based or count-based?** Determines
   whether we can wire them in directly or need an upstream PR first.

2. **Welford's algorithm vs. Kahan-compensated naive sum?** Welford is more
   stable; naive + Kahan is simpler. Pick after a stability test on a
   representative session length.

3. **Periodic recomputation interval (K):** every 60 windows? 600? Make it
   configurable on the operator? Probably not configurable — pick a sane
   default.

4. **Should this optimization be opt-in via a parameter, or replace the naive
   path wholesale?** Wholesale means simpler API; opt-in lets us A/B easily.
   **Recommendation:** wholesale, with the v1 test suite as the equivalence
   gate.

---

## 9. Activation Checklist

Before this proposal moves from holding to active:

- [ ] v1 streaming HRV operator shipped and stable
- [ ] Profiling data shows naive operator is a measurable bottleneck for the
      target use case (live 5-minute sliding window updating every second)
- [ ] BusinessMath rolling-op signatures verified
- [ ] Open questions §8.1 and §8.2 resolved
- [ ] User approval to begin RED phase

---

**Last Updated:** 2026-04-06
