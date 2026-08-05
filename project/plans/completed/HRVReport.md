# Design Proposal: HRVReport — Unified Time + Frequency Domain Snapshot

**Status:** DRAFT — held for future activation. Not yet approved.

> **Trigger condition:** Activate this proposal when the Algorithm layer
> begins consuming HRV metrics. The unified report becomes the canonical
> input shape to `HRVAlgorithm`, replacing the current "two separate value
> types" pattern.

---

## 1. Objective

Combine the outputs of `HRVMetrics` (time-domain) and `FrequencyDomainMetrics`
(frequency-domain) into a single immutable value type, `HRVReport`, that
represents the **complete HRV picture for one analysis window**. This is the
input the Algorithm layer's scorer will accept.

Today the two metric types live independently because their compute paths,
window length requirements, and failure modes differ. That separation is
right for *computation*. But once the Algorithm layer takes them as inputs,
working with two separate values forces every downstream consumer to plumb
both, version-tag both, serialize both, and handle the cross-product of edge
cases. A unified report is the natural abstraction at that boundary.

---

## 2. Proposed Architecture

**New Files:**
- `Sources/BioFeedbackKit/Signal/HRVReport.swift` (the unified value type)
- `Tests/BioFeedbackKitTests/HRVReportTests.swift`

**Modified files:**
- (Possibly) `Sources/BioFeedbackKit/Signal/HRVMetrics.swift` — add a `report(joining:)` convenience method
- (Possibly) `Sources/BioFeedbackKit/Signal/FrequencyDomainMetrics.swift` — same

**Module placement:** `Signal/`. The report is the highest layer of the Signal
module — it depends on both `HRVMetrics` and `FrequencyDomainMetrics`.

---

## 3. API Surface

```swift
public struct HRVReport: Sendable, Equatable {

    /// Time-domain metrics for this window.
    public let timeDomain: HRVMetrics

    /// Frequency-domain metrics for this window. May be `nil` for windows
    /// that were too short for frequency analysis (< 25 seconds).
    public let frequencyDomain: FrequencyDomainMetrics?

    /// The window's start instant (timestamp of the first sample).
    public let windowStart: ContinuousClock.Instant

    /// The window's end instant (timestamp of the last sample).
    public let windowEnd: ContinuousClock.Instant

    /// Convenience: window duration as `windowEnd - windowStart`.
    public var windowDuration: Duration

    /// Combines a time-domain and frequency-domain result over the same window.
    public init(
        timeDomain: HRVMetrics,
        frequencyDomain: FrequencyDomainMetrics?,
        windowStart: ContinuousClock.Instant,
        windowEnd: ContinuousClock.Instant
    )

    /// Computes the full report from a window of samples in one call.
    ///
    /// Convenience initializer that runs `HRVMetrics(window:)` and, if the
    /// window is long enough, `FrequencyDomainMetrics(window:)` as well.
    /// Frequency-domain failures due to short windows are caught and reported
    /// as `frequencyDomain = nil`; other errors propagate.
    ///
    /// - Throws: `SignalError.insufficientSamples` if the time-domain
    ///   computation can't run (< 2 samples). All other errors propagate
    ///   from the underlying metric computations.
    public init<C: Collection>(
        window: C,
        pnnThreshold: Double = 50.0,
        resampleRate: Double = 4.0,
        interpolation: any InterpolationStrategy = LinearInterpolation(),
        windowFunction: any WindowFunction = HannWindow(),
        fftBackend: any FFTBackend = FFTBackendSelector.selectBackend()
    ) throws where C.Element == BioSample
}
```

### Codable / version tagging

The Algorithm layer will need to persist reports for telemetry/replay. The
report should be `Codable` and include a config-version field once
`AlgorithmConfig` exists:

```swift
extension HRVReport: Codable {
    public enum CodingKeys: String, CodingKey {
        case timeDomain, frequencyDomain, windowStart, windowEnd
    }
}
```

The version-tagging discussion is **out of scope** for this proposal but
documented as a deferred decision in §10.

---

## 4. The streaming variant

Once `StreamingHRVMetrics` and `StreamingFrequencyDomainMetrics` (the
yet-to-be-proposed analog) both exist, a streaming `HRVReport` operator
becomes natural:

```swift
extension AsyncSequence where Element == BioSample, Self: Sendable {
    func hrvReport(
        window: Duration,
        every stride: Duration? = nil,
        pnnThreshold: Double = 50.0,
        resampleRate: Double = 4.0
    ) -> AsyncHRVReportSequence<Self>
}
```

Implementation strategy: zip the two underlying streaming operators by window
boundary. The hard part is making sure the windows line up identically — both
operators need to share the same windowing implementation, which they will
because they both go through BusinessMath's `tumblingWindow` /
`slidingWindow`.

**Streaming HRVReport will get its own design proposal.**

---

## 5. Constraints & Compliance

- **Concurrency:** `HRVReport` is an immutable Sendable, Equatable, Codable value type.
- **Composability:** Built atop existing `HRVMetrics` and `FrequencyDomainMetrics`. No reimplementation.
- **Failure model:** Time-domain failures propagate (those are real errors). Frequency-domain "window too short" failures resolve to `frequencyDomain = nil` (graceful degradation for short windows).

---

## 6. Test Strategy

- **Construction equivalence:** building an `HRVReport` from a window matches the result of building `HRVMetrics` and `FrequencyDomainMetrics` separately on the same window.
- **Short window:** windows < 25 seconds produce a report with `frequencyDomain = nil` but a valid `timeDomain`.
- **Time-domain failure propagation:** windows < 2 samples throw `insufficientSamples`.
- **Codable round-trip:** encode a report to JSON, decode it back, assert equality.

---

## 7. Dependencies

**Internal:**
- `Signal/HRVMetrics.swift`
- `Signal/FrequencyDomainMetrics.swift`
- `Signal/InterpolationStrategy.swift`
- `Signal/WindowFunction.swift`
- `Devices/BioSample.swift`

**External:** none beyond what `HRVMetrics` and `FrequencyDomainMetrics` already pull in.

---

## 8. Open Questions

1. **Should `HRVReport` be `Codable` from v1, or added later?**
   - **Recommendation:** Codable from v1. The Algorithm layer will need it almost immediately for session persistence and telemetry.

2. **Should the report carry a version tag (config version, library version)?**
   - **Recommendation:** Defer until `AlgorithmConfig` exists. Adding it now would make the type depend on something that doesn't exist yet. Add it in the same PR as `AlgorithmConfig`.

3. **Should the report's failure model be "all-or-nothing" (throw if either component fails) or "graceful degradation" (frequency = nil on short window, throw only on time-domain failure)?**
   - **Recommendation:** Graceful degradation. The whole point of the unified report is to give downstream consumers ONE input shape. If time-domain is computable, the report is meaningful.

4. **Should `HRVReport` be `Comparable` by some natural order (e.g. windowStart)?**
   - **Recommendation:** No. Equatable is enough. Sorting reports by time is a downstream concern.

---

## 9. Activation Checklist

Before this proposal moves from holding to active:

- [ ] `FrequencyDomainMetrics` v2 has shipped and is stable
- [ ] Algorithm layer design proposal is in flight or about to start
- [ ] User confirms the unified report is the right input shape for `HRVAlgorithm`
- [ ] User approves Codable from v1
- [ ] User confirms version-tagging defer

---

**Last Updated:** 2026-04-06
