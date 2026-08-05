# Design Proposal: Signal Layer — RRBuffer + HRVMetrics

**Status:** APPROVED — ready to move to UPCOMING/

**Revision history:**
- v1 (2026-04-06): initial draft
- v2 (2026-04-06): incorporated user feedback — Malik filter as default with PercentChange swap, generalized `pnn(threshold:)`, streaming fast-follow plan, full validation trace with sources, playground validation block
- v3 (2026-04-06): final — `MedianMalikFilter` confirmed default; `HRVMetrics.init` made generic over `Collection`; streaming fast-follow explicitly bound to Design-First TDD process

---

## 1. Objective

Build the first signal-processing stage of BioFeedbackKit: ingest a stream of
`BioSample` values, validate and filter them (ectopic beats, physiologically
implausible intervals), buffer them by time window, and expose canonical
time-domain HRV metrics (RMSSD, SDNN, pNN50).

This is the layer that converts raw heart-rate-monitor output into the
clinically meaningful values that the Algorithm layer will score against.

**Master Plan Reference:** Phase 1 — Signal Pipeline.

---

## 2. Proposed Architecture

**New Files:**
- `Sources/BioFeedbackKit/Signal/RRBuffer.swift`
- `Sources/BioFeedbackKit/Signal/HRVMetrics.swift`
- `Sources/BioFeedbackKit/Signal/SignalError.swift`
- `Tests/BioFeedbackKitTests/RRBufferTests.swift`
- `Tests/BioFeedbackKitTests/HRVMetricsTests.swift`

**Module Placement:** New `Signal/` directory under `Sources/BioFeedbackKit/`.

**Pipeline position:**

```
[Devices] BioSample stream
    │
    ▼
[Signal] RRBuffer.process(_:)         ← validates + filters ectopic beats
    │     emits cleaned BioSample
    ▼
[Signal] HRVMetrics(window:)          ← time-domain metrics over a window
    │
    ▼
[Algorithm]  (next layer, separate proposal)
```

---

## 3. API Surface

### EctopicFilter protocol

```swift
/// Strategy for rejecting physiologically implausible beats.
///
/// Implementations are stateful — they observe a running history of accepted
/// samples and decide whether each new sample should be accepted.
public protocol EctopicFilter: Sendable {
    /// Reset internal state (e.g. between sessions).
    mutating func reset()

    /// Accept or reject a new sample. Returns the sample if accepted, nil if rejected.
    mutating func accept(_ sample: BioSample) -> BioSample?
}
```

### MedianMalikFilter (default)

Robust median-based ectopic detector. Compares each new beat against the
median of the last N accepted beats; rejects if the relative deviation
exceeds the threshold.

```swift
public struct MedianMalikFilter: EctopicFilter {
    public let windowSize: Int      // default 5
    public let threshold: Double    // default 0.20 (20%)

    public init(windowSize: Int = 5, threshold: Double = 0.20)
    public mutating func reset()
    public mutating func accept(_ sample: BioSample) -> BioSample?
}
```

### PercentChangeFilter (alternative, hand-verifiable)

Classical Malik rule: rejects if relative change vs. the previous accepted
beat exceeds the threshold. Simpler — used in tests as a human-verifiable
ground truth comparator.

```swift
public struct PercentChangeFilter: EctopicFilter {
    public let threshold: Double    // default 0.20

    public init(threshold: Double = 0.20)
    public mutating func reset()
    public mutating func accept(_ sample: BioSample) -> BioSample?
}
```

### RRBuffer

Composes a physiologic-range gate with an `EctopicFilter` strategy.

```swift
public struct RRBuffer<Filter: EctopicFilter>: Sendable {
    /// Physiologically plausible RR interval range (ms).
    /// Default: 300...2000 (corresponds to 30–200 BPM).
    public let validRange: ClosedRange<Double>

    public var filter: Filter

    public init(
        validRange: ClosedRange<Double> = 300...2000,
        filter: Filter
    )

    /// Reset internal state (e.g. between sessions).
    public mutating func reset()

    /// Process a single sample. Returns the sample if it passes both the
    /// range gate and the ectopic filter; nil otherwise.
    public mutating func process(_ sample: BioSample) -> BioSample?
}

extension RRBuffer where Filter == MedianMalikFilter {
    /// Convenience initializer using the default robust filter.
    public init(validRange: ClosedRange<Double> = 300...2000)
}

extension AsyncSequence where Element == BioSample {
    /// Applies an RRBuffer filter to the stream, dropping rejected samples.
    public func filtered<F: EctopicFilter>(
        by buffer: RRBuffer<F>
    ) -> AsyncFilteredRRSequence<Self, F>
}
```

### HRVMetrics

A pure value type computed from a window of cleaned `BioSample` values. All
calculations delegate to BusinessMath where possible.

```swift
public struct HRVMetrics: Sendable, Equatable {
    public let sampleCount: Int
    public let meanRR: Double             // ms
    public let rmssd: Double              // ms — root mean square of successive differences
    public let sdnn: Double               // ms — standard deviation of NN intervals (sample, n-1)
    public let pnn: Double                // proportion of |successive diffs| > pnnThreshold (0...1)
    public let pnnThreshold: Double       // ms; default 50.0 → pNN50

    /// Computes HRV metrics from a window of samples.
    ///
    /// Generic over any `Collection` of `BioSample` so that callers can pass
    /// `Array`, `ArraySlice`, `Deque`, or BusinessMath's `RingBuffer` without
    /// copying. This is the same shape that the streaming sliding-window
    /// pipeline will produce.
    ///
    /// - Parameters:
    ///   - window: Cleaned RR samples. Must contain at least 2 elements.
    ///   - pnnThreshold: Threshold in milliseconds for the pNN metric. Defaults to 50.0
    ///                   (canonical pNN50). Pass 20.0 for pNN20, 30.0 for pNN30, etc.
    /// - Throws: `SignalError.insufficientSamples` if fewer than 2 samples provided.
    public init<C: Collection>(
        window: C,
        pnnThreshold: Double = 50.0
    ) throws where C.Element == BioSample
}
```

**pNN denominator decision:** v1 uses `n−1` (count of successive differences) as the
denominator, matching modern tools (Kubios, HRV Analysis). The original Task Force
1996 paper used `n` (count of NN intervals) — the difference is small and we document
the choice in the DocC.

### SignalError

```swift
public enum SignalError: Error, Sendable, Equatable {
    case insufficientSamples(required: Int, got: Int)
}
```

---

## 4. MCP Schema

**Tool Description:** Compute HRV metrics from a window of RR intervals.

```json
{
  "rrIntervals": [800, 820, 790, 810, 830, 805],
  "validRange": {"min": 300, "max": 2000},
  "ectopicThreshold": 0.20
}
```

**Parameter Types:**
- `rrIntervals` (array of numbers): RR intervals in milliseconds. Length ≥ 2 after filtering.
- `validRange` (object, optional): Physiologically plausible bounds. Defaults to {300, 2000}.
- `ectopicThreshold` (number, optional): Relative-change rejection threshold. Default 0.20.

**Returns:**
```json
{
  "sampleCount": 6,
  "meanRR": 809.17,
  "rmssd": 18.71,
  "sdnn": 14.29,
  "pnn50": 0.0
}
```

---

## 5. Constraints & Compliance

- **Concurrency:** RRBuffer and HRVMetrics are immutable Sendable value types.
- **Determinism:** Pure functions of input. No clocks, no I/O.
- **Safety:** No force unwraps. Division-by-zero guarded in mean/sdnn calculations. `pnn50` returns 0 when fewer than 2 successive differences exist.
- **Generics:** Concrete `Double` for now — physiological data is naturally `Double`. Can be generalized later if needed.
- **Swift 6:** Strict concurrency compliant.

---

## 6. Backend Abstraction

Not needed at this layer. RMSSD, SDNN, and pNN50 are O(n) over windows that
are typically 60–300 samples. No GPU/Accelerate needed yet.

The frequency-domain layer (`FrequencyDomain.swift`, separate proposal) will use
BusinessMath's vDSP-backed FFT.

---

## 7. Dependencies

**Internal:**
- `Devices/BioSample.swift` (input type)

**External (BusinessMath):**
- `successiveDifferences()` — for RMSSD numerator
- `rollingSuccessiveDifferenceRMS(window:)` — alternative streaming path (may use in v2)
- `mean()`, `stdDev()` (sample stdev) — for meanRR and SDNN
- `rollingThresholdExceedanceRate(window:, threshold:)` — for pNN50 in streaming context

**Note:** v1 of HRVMetrics computes from a fully-materialized `[BioSample]` window.
A streaming variant can come later when we wire up the windowing pipeline.

---

## 8. Test Strategy

**Test Categories:**

### RRBuffer
- **Golden path:** Sequence of normal RR intervals all pass through unchanged
- **Out-of-range rejection:** RR < 300ms or > 2000ms is dropped
- **Ectopic beat rejection:** Sample > 20% different from previous is dropped
- **First sample:** Always accepted (no previous to compare to)
- **Custom thresholds:** validRange and ectopicThreshold are honored
- **AsyncSequence integration:** `.filtered(by:)` works on a MockDevice stream

### HRVMetrics
- **Golden path:** Known input → expected RMSSD/SDNN/pNN50
- **Two-sample minimum:** 1-sample window throws insufficientSamples
- **Constant intervals:** All RRs equal → RMSSD = 0, SDNN = 0, pNN50 = 0
- **Symmetric jitter:** Predictable ±20ms alternating pattern → known RMSSD
- **pNN50 boundary:** Differences exactly at 50ms → not counted (strictly greater)
- **Empty case:** 0 samples → throws insufficientSamples

**Reference Truth:**
- **RMSSD validation:** Hand-computed from a 6-sample fixture, cross-checked against
  the formula `sqrt(mean(diff(rr)^2))` from Task Force of ESC/NASPE (1996),
  *Heart rate variability: Standards of measurement, physiological interpretation,
  and clinical use*, Circulation 93(5).
- **SDNN validation:** Sample standard deviation, cross-checked against BusinessMath's
  `stdDev` on the same fixture.
- **pNN50 validation:** Hand-counted from same fixture.

**Validation Trace:**
```
Fixture: [800, 820, 790, 810, 830, 805] ms
Successive diffs: [+20, -30, +20, +20, -25]
Squared diffs: [400, 900, 400, 400, 625]
Mean of squared diffs: 545
RMSSD: sqrt(545) ≈ 23.345 ms
Mean RR: 809.1667 ms
SDNN (sample): ≈ 14.289 ms
pNN50: 0/5 = 0.0 (no diff exceeds 50ms)
```

These exact values become the golden-path test assertions.

---

## 9. Architecture Decision Review

- [x] Reviewed: no prior ADRs in this project yet
- [x] Does not supersede or amend any existing ADR
- [ ] **New ADR candidate:** "RRBuffer is stateless from caller's perspective; ectopic detection uses previous-sample reference, not running mean." Worth recording if you want decisions tracked. Defer until ADR file is established.

---

## 10. Resolved Questions

1. **Ectopic detection:** RESOLVED — `EctopicFilter` protocol with two impls. Default is `MedianMalikFilter` (window=5, threshold=20%). `PercentChangeFilter` available as a hand-verifiable comparator. **One sub-question still open** — see §10a below.

2. **Window type:** RESOLVED — generic `<C: Collection> where C.Element == BioSample` from v1. Interop with BusinessMath buffers (`RingBuffer`, `Deque`) and slice-based windowing without copying.

3. **Streaming HRVMetrics:** RESOLVED — wait, but with concrete fast-follow plan (see §12).

4. **pNN generalization:** RESOLVED — single field `pnn` with `pnnThreshold` parameter, default 50.0 ms → behaves as canonical pNN50.

## 10a. Resolved: Malik variant

**Decision:** `MedianMalikFilter` (median of last 5 accepted beats, ±20% threshold) is
the default. `PercentChangeFilter` ships alongside as the simpler hand-verifiable
comparator.

---

## 10b. Reference Truth & Validation Trace

**Source (canonical):**
> Task Force of the European Society of Cardiology and the North American Society of
> Pacing and Electrophysiology. (1996). "Heart rate variability: Standards of measurement,
> physiological interpretation, and clinical use." *Circulation*, 93(5), 1043–1065.

This paper defines all three time-domain metrics in §3.1. Formulas:

- **Mean NN:** arithmetic mean of all NN intervals
- **SDNN:** sample standard deviation (`n−1` denominator)
- **RMSSD:** √(mean of squared successive differences)
- **pNN50:** count of |successive diffs| > 50 ms / count of differences (we use `n−1`,
  not `n`, matching modern tools)

**Primary fixture:** `[800, 820, 790, 810, 830, 805]` ms (n = 6)

```
Successive diffs (NN[i+1] − NN[i]):
  820 − 800 = +20
  790 − 820 = −30
  810 − 790 = +20
  830 − 810 = +20
  805 − 830 = −25
diffs = [+20, −30, +20, +20, −25]   (count = 5)

RMSSD:
  squared diffs = [400, 900, 400, 400, 625]
  sum           = 2725
  mean          = 545
  RMSSD         = √545 ≈ 23.345235 ms

Mean NN:
  sum  = 4855
  mean = 4855 / 6 = 809.166667 ms

SDNN (sample, n−1):
  deviations from 809.1667:
    −9.1667, +10.8333, −19.1667, +0.8333, +20.8333, −4.1667
  squared deviations:
    84.0278, 117.3611, 367.3611, 0.6944, 434.0278, 17.3611
  sum     = 1020.8333
  variance = 1020.8333 / 5 = 204.1667
  SDNN     = √204.1667 ≈ 14.288690 ms

pNN50:
  |diffs| = [20, 30, 20, 20, 25]
  count > 50: 0
  pNN50 = 0 / 5 = 0.0
```

**Secondary fixtures for full coverage:**

| Fixture | Purpose | Expected pNN50 |
|---------|---------|----------------|
| `[800, 870, 800, 870, 800, 870]` | Every diff = 70 ms (>50) | 1.0 (5/5) |
| `[800, 850, 800, 850, 800, 850]` | Every diff = 50 ms exactly | 0.0 (strict `>`) |
| `[800, 800, 800, 800]` | Constant intervals | RMSSD=0, SDNN=0, pNN=0 |

## 10c. Playground Validation Block

A self-contained `.swift` file will be committed at
`project/plans/proposals/SignalLayer-Playground.swift` containing the
fixture, the expected values from §10b, and a hand-rolled implementation of the
formulas (independent of BusinessMath) so the user can run it in a Swift Playground
and verify the math before any tests or code touch the package.

Sketch:

```swift
// Playground: validate HRV metrics fixture
import Foundation

let rr: [Double] = [800, 820, 790, 810, 830, 805]

// Successive differences
let diffs = zip(rr.dropFirst(), rr).map { $0 - $1 }
print("diffs:", diffs)
// → [20.0, -30.0, 20.0, 20.0, -25.0]

// RMSSD
let squared = diffs.map { $0 * $0 }
let rmssd = (squared.reduce(0, +) / Double(squared.count)).squareRoot()
print("RMSSD:", rmssd)
// → 23.345235059857504

// Mean NN
let meanRR = rr.reduce(0, +) / Double(rr.count)
print("Mean NN:", meanRR)
// → 809.1666666666666

// SDNN (sample, n-1)
let sqDevs = rr.map { ($0 - meanRR) * ($0 - meanRR) }
let sdnn = (sqDevs.reduce(0, +) / Double(rr.count - 1)).squareRoot()
print("SDNN:", sdnn)
// → 14.288690166235207

// pNN50 (n-1 denominator, strict greater than 50)
let exceeding = diffs.filter { abs($0) > 50 }.count
let pnn50 = Double(exceeding) / Double(diffs.count)
print("pNN50:", pnn50)
// → 0.0
```

These printed values are the exact assertions for the golden-path tests.

## 12. Streaming HRVMetrics — Fast-Follow Plan

After RRBuffer + HRVMetrics ships, the immediate next feature is a streaming
variant. **It MUST follow the same Design-First TDD process as everything else
in this project** — design proposal → user approval → failing tests → minimum
implementation → refactor → docs → quality gate. No shortcuts because it's a
"fast follow."

Sketch of the plan to be expanded into a full proposal:

1. **API:** `extension AsyncSequence where Element == BioSample { func hrvMetrics(window: Duration, stride: Duration) -> some AsyncSequence<HRVMetrics> }`
2. **Backbone:** wrap each `BioSample` in BusinessMath's `Timestamped<BioSample>`, then use BusinessMath's `.slidingWindow(duration:stride:)` operator.
3. **First implementation:** materialize each window as a slice/array, hand to existing generic `HRVMetrics(window:)`. Trivially correct, validates the pipeline end-to-end.
4. **Optimization pass:** swap inner loop to use BusinessMath's `rollingSuccessiveDifferenceRMS(window:)` and `rollingThresholdExceedanceRate(window:, threshold:)` so RMSSD and pNN don't recompute from scratch every window.
5. **Tests:** use `AsyncValueStream([BioSample])` from BusinessMath as the source — no hardware, no clocks, fully deterministic.

This gets its own design proposal once §1–§11 land.

## 11. Documentation Strategy

**Documentation Type:** API Docs Only (for now)

**Complexity Threshold Check:**
- Combines 3+ APIs? No (RRBuffer + HRVMetrics, plus BusinessMath helpers)
- Explanation requires 50+ lines? Borderline — HRV concepts deserve background
- Needs theory/background? Yes, but defer to a project-level "HRV Primer" article when the full pipeline lands

**Decision:** API docs for v1. Write `HRVPrimer.md` narrative when the Algorithm layer ships.

---

## Approval Checklist

- [ ] User approves objective and scope
- [ ] User approves API surface
- [ ] User approves open-question recommendations
- [ ] User approves test fixtures and reference truth

---

**Next step after approval:** Move this file to `project/plans/upcoming/`, create the implementation checklist in `project/checklists/`, then write failing tests (RED phase) before any implementation code.

**Last Updated:** 2026-04-06
