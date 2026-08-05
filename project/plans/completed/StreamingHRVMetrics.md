# Design Proposal: Streaming HRVMetrics

**Status:** DRAFT v1 — awaiting user approval

---

## 1. Objective

Lift the materialized `HRVMetrics(window:)` initializer into a streaming
`AsyncSequence` operator so that BioFeedbackKit can compute HRV metrics
continuously from a live device stream, emitting one `HRVMetrics` value per
time window.

This is the piece that unlocks end-to-end pipeline validation: a `MockDevice`
(or real adapter) at one end → cleaned samples → rolling HRV metrics → ready
to feed into the Algorithm layer.

**Master Plan Reference:** Phase 1 — Signal Pipeline (the streaming variant of
the materialized work that just shipped).

**Approved fast-follow plan:** §12 of `project/plans/upcoming/SignalLayer-RRBuffer-HRVMetrics.md`. This proposal is the formal Design-First TDD treatment of that sketch.

---

## 2. Proposed Architecture

**New Files:**
- `Sources/BioFeedbackKit/Signal/AsyncHRVMetricsSequence.swift`
- `Tests/BioFeedbackKitTests/StreamingHRVMetricsTests.swift`

**Modified Files:** none (purely additive)

**Pipeline position:**

```
[Devices]  AsyncSequence<BioSample>                                   ← MockDevice or BLE adapter
    │
    ▼
[Signal]   .filtered(by: rrBuffer)                                    ← existing operator
    │
    ▼
[Signal]   .hrvMetrics(window: .seconds(300), every: .seconds(1))     ← THIS PROPOSAL
    │
    ▼
[Algorithm] (next layer, separate proposal)
```

The new operator wraps each `BioSample` in BusinessMath's `Timestamped<BioSample>`
using the **sample's existing timestamp** (not iteration time — critical for
deterministic replay), passes it through BusinessMath's
`slidingWindow(duration:stride:)`, and for each emitted window builds an
`HRVMetrics` via the existing materialized initializer.

---

## 3. API Surface

```swift
extension AsyncSequence where Element == BioSample {
    /// Computes HRV metrics over time windows of cleaned RR samples.
    ///
    /// - Parameters:
    ///   - window: The time span of each window.
    ///   - stride: How often a new window is emitted. Defaults to `window`
    ///             (tumbling, non-overlapping). Pass a smaller value for
    ///             sliding behavior — e.g. `window: .seconds(300), every: .seconds(1)`
    ///             for a 5-minute window updating every second.
    ///   - pnnThreshold: Threshold in milliseconds for the pNN metric. Defaults to 50.0.
    /// - Returns: An `AsyncSequence` of `HRVMetrics`. Windows containing fewer
    ///            than 2 samples are silently skipped (the device dropped out
    ///            for that interval); the next valid window resumes metrics.
    public func hrvMetrics(
        window: Duration,
        every stride: Duration? = nil,
        pnnThreshold: Double = 50.0
    ) -> AsyncHRVMetricsSequence<Self>
}

public struct AsyncHRVMetricsSequence<Base: AsyncSequence>: AsyncSequence
where Base.Element == BioSample, Base: Sendable {
    public typealias Element = HRVMetrics

    public func makeAsyncIterator() -> AsyncIterator

    public struct AsyncIterator: AsyncIteratorProtocol {
        public mutating func next() async throws -> HRVMetrics?
    }
}
```

**Behavior of `stride`:**
- `nil` (default) → tumbling windows. Equivalent to `stride == window`.
- Anything else → sliding windows of `window` duration, emitted every `stride`.
- BusinessMath's `slidingWindow(duration:stride:)` already degenerates to
  tumbling when `stride == duration`, so internally we always call sliding
  with `stride ?? window`.

**Behavior on sparse windows:**
- A window with 0 or 1 samples is silently skipped (the underlying
  `HRVMetrics(window:)` would throw `insufficientSamples`; we catch and skip).
- Rationale: a streaming consumer wants a clean stream of valid metrics, not
  an exception every time the BLE link dropped a beat. The next valid window
  resumes output naturally.

---

## 4. MCP Schema

Not directly applicable — this is an operator on an `AsyncSequence`, not a
function with serializable inputs/outputs. The downstream consumers
(`HRVMetrics`) already have their schema documented.

---

## 5. Constraints & Compliance

- **Concurrency:** `AsyncHRVMetricsSequence` is `Sendable` when its `Base` is `Sendable`. The iterator holds the BusinessMath sliding-window iterator and forwards.
- **Determinism:** The operator uses each `BioSample.timestamp` as the canonical time for windowing — **not** wall-clock at iteration. This is what makes deterministic replay possible: a `MockDevice` with pre-stamped samples produces identical metrics regardless of how fast the test runs.
- **Safety:** No force unwraps. `insufficientSamples` errors from `HRVMetrics.init` are caught and the window is skipped — all other errors propagate.
- **Swift 6:** Strict concurrency compliant.

---

## 6. Backend Abstraction

Not applicable. The hot path is delegated to BusinessMath's existing windowing
operator. Any future optimization (see §12) is internal to this operator.

---

## 7. Dependencies

**Internal:**
- `Sources/BioFeedbackKit/Signal/HRVMetrics.swift` (the materialized initializer)
- `Sources/BioFeedbackKit/Devices/BioSample.swift` (input element type)

**External (BusinessMath):**
- `Timestamped<V>` — wraps `BioSample` with its own timestamp, not iteration time
- `slidingWindow(duration:stride:)` — the heavy lifting
- For tests: `AsyncValueStream<BioSample>` — deterministic source

---

## 8. Test Strategy

**Test Categories:**

### Golden path
- **Single window covers all samples:** feed the primary fixture `[800, 820, 790, 810, 830, 805]` ms with 1-second spacing into a 10-second window. Expect exactly one `HRVMetrics` output identical to the materialized version on the same fixture.

### Tumbling windows
- **Two non-overlapping windows:** feed 6 samples spaced 1 second apart, window=3s, stride=nil (→ tumbling). Expect 2 `HRVMetrics` outputs covering [t0..t3) and [t3..t6) respectively.
- **Per-window metrics correct:** verify the metrics in each tumbling window match what `HRVMetrics(window:)` produces on those exact sub-fixtures.

### Sliding windows
- **Stride < window produces overlapping outputs:** window=3s, stride=1s on 6 1-second-spaced samples → expect 4 outputs (windows starting at t0, t1, t2, t3).
- **Stride == window degenerates to tumbling:** window=3s, every=3s should produce the same output count as the tumbling test.

### Sparse / edge cases
- **Window with single sample is skipped:** feed one isolated sample inside an otherwise empty window region → no `HRVMetrics` emitted for that window.
- **Empty stream → empty output:** input is `AsyncValueStream([])` → iterator returns nil immediately, zero metrics emitted.
- **Sample-count threshold:** a window with exactly 2 samples produces an `HRVMetrics` (boundary verified).

### Composition
- **Pre-filter chain works end-to-end:** `MockDevice` → `.filtered(by: RRBuffer())` → `.hrvMetrics(window:)` produces the same metrics as the filtered samples handed directly to `HRVMetrics(window:)`.

### Parameter propagation
- **`pnnThreshold` propagates:** stream produces `HRVMetrics` with `pnnThreshold` matching the operator argument.

**Reference Truth:**
- The golden-path single-window test compares output **exactly** against `HRVMetrics(window: samples)` on the same array. This means we don't need new ground-truth values — the materialized version IS the ground truth, and the streaming variant must produce identical results.
- Per-window tumbling tests use the same approach: take the slice of samples that fall in each window and compare to `HRVMetrics(window: slice)`.

This is the cleanest possible validation strategy because the materialized
version is already validated against the 1996 Task Force formulas via the
playground.

**Determinism in tests:**
All tests use a fixed origin `let origin = ContinuousClock.now` captured once,
then construct sample timestamps as `origin.advanced(by: .seconds(i))`. This
makes window membership purely a function of the relative offsets — no
wall-clock dependency.

---

## 9. Architecture Decision Review

- [x] Reviewed existing proposals — no ADR conflicts
- [ ] **New ADR candidate:** "Streaming HRV operators use the BioSample's own timestamp for windowing, not iteration time, to enable deterministic replay." Worth recording when we establish the ADR file. Defer for now.

---

## 10. Open Questions

1. **Sparse-window behavior — skip vs. emit zero-filled vs. throw?**
   - **Recommendation:** Skip silently. A zero-filled `HRVMetrics` would be misleading (downstream might treat it as "calm" when in fact the device dropped). Throwing pollutes the stream. Skipping is the cleanest signal of "no data for this interval."

2. **Should we expose tumbling and sliding as two separate methods, or one method with optional stride?**
   - **Recommendation:** One method with optional stride. `every: nil` is unambiguous and matches how BusinessMath models it (sliding with `stride == duration` IS tumbling).

3. **Should we cache the most recent metrics for late subscribers?**
   - **Recommendation:** No. Out of scope for v1. AsyncSequence's pull semantics mean each consumer gets its own iterator with its own state. Late subscribers just see metrics from when they start iterating.

4. **What about an injected RRBuffer for convenience (`.hrvMetrics(filteredBy: rrBuffer, window:)`)?**
   - **Recommendation:** No. Composition via `.filtered(by:).hrvMetrics(...)` is cleaner and more orthogonal. Users who don't want filtering shouldn't pay for it.

---

## 11. Documentation Strategy

**Documentation Type:** API Docs Only

**Complexity threshold:**
- Combines 3+ APIs? Yes (AsyncSequence operator, Timestamped wrapping, sliding window, materialized HRVMetrics)
- 50+ lines of explanation? Maybe
- Theory/background? No — this is pure plumbing on top of already-documented physiology

**Decision:** API docs for v1. The "how to use this in a real app" article belongs at the Algorithm/Feedback layer, where the full pipeline lives.

---

## 12. Optimization Pass (NOT in v1)

The naive implementation materializes each window as `[BioSample]` and hands
it to `HRVMetrics(window:)`. For large windows with small strides
(e.g. 5-minute window updating every second on 1 Hz data), this means
recomputing 300 samples worth of math 300 times for ~99% overlap.

**Optimization sketch (separate future proposal):**
- Use BusinessMath's `rollingSuccessiveDifferenceRMS(window:)` and `rollingThresholdExceedanceRate(window:, threshold:)` so RMSSD and pNN don't recompute from scratch every window.
- `mean` and `stdDev` would need rolling variants — check if BusinessMath has them, if not, this proposal would need to add them upstream.
- Profile first. The naive version may be fast enough for the live use case (5-minute window over 300–500 samples is sub-millisecond on modern hardware).

**This optimization will require its own design proposal and full TDD cycle.**

---

## Approval Checklist

- [ ] User approves objective and scope
- [ ] User approves single-method-with-optional-stride API
- [ ] User approves "skip sparse windows silently" semantics
- [ ] User approves "use BioSample.timestamp not iteration time" decision
- [ ] User approves test strategy of comparing streaming output against materialized output

---

**Next step after approval:** Move to `UPCOMING/`, create implementation checklist, write failing tests against `MockDevice` + `AsyncValueStream`, then implement.

**Last Updated:** 2026-04-06
