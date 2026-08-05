# Design Proposal: Discovery Protocols v1

**Status:** APPROVED 2026-04-09 — moving to RED (updated with audit feedback)
**Date:** 2026-04-09
**References:** v5 §7 (Discovery Modes), ~/desktop/discoveryProtocolsAudit.md

---

## 1. Objective

Implement the three resonance-frequency discovery protocols from v5
§7 as library-level types in `BioFeedbackKit/Discovery/`. These are
testable state machines that drive a breathing pacer through a
sequence of rates, collect coherence at each rate, and select the
winning frequency. They consume the existing `CoherenceAlgorithm`
pipeline and are consumed by every app target (watchOS, iOS, visionOS).

---

## 2. The three protocols (per v5 §7)

### 2.1 Classic Lehrer Stepped (v5 §7.1)

Tests 5 fixed breathing rates with extended measurement windows.
Gold standard, used in hundreds of clinical studies.

```
Rates: 5.0, 5.5, 6.0, 6.5, 7.0 bpm
Per rate: 10s ramp → 50s settle → 120s measurement
15s transition between rates (except after last)
30s initial settling (no pacing)
Total: ~18 minutes
Result: rate with highest mean coherence = RF
```

### 2.2 Fisher Sliding Sweep (v5 §7.2)

Continuous sweep across the resonance range. Finer frequency resolution.

```
Range: 6.75 → 4.25 bpm (descending)
Duration: 12 minutes
30s settling + 10s ramp into sweep start
Coherence binned at 0.25 bpm resolution (10 bins)
Total: ~15 minutes
Result: bin with highest mean coherence = RF
```

### 2.3 Smart Start (v5 §7.3)

Adaptive system that picks the fastest path based on session history.

```
No sessions       → full sliding sweep (~15 min)
1–2 sessions      → narrow sweep ±1.0 bpm around last RF (~8 min)
3+ stable (SD<0.3) → quick-confirm: 60s at predicted RF → training
3+ variable        → narrow-confirm: 2-min sweep ±1.0 bpm → training
```

Uses `RFStabilityAnalyzer` (already shipped) for the SD check.

---

## 3. Architecture

Each discovery protocol is a **testable actor** that:

1. Takes a `CoherenceScorer` + `CoherenceConfig` + a data source
   (the sample stream from any `BiofeedbackDevice`)
2. Drives the breathing pacer through its rate sequence
3. At each rate, builds `FrequencyDomainMetrics` + `HRVMetrics` from
   the accumulated window and calls the scorer
4. Collects `(rate, meanCoherence)` pairs
5. Returns a `DiscoveryResult` with the winning RF + the full
   coherence-per-rate profile

The protocols do NOT own the device connection or the feedback
rendering. They receive pre-connected sample streams and emit
`DiscoveryEvent`s that the app's session orchestrator translates
into breathing commands (for glasses) or on-screen pacer state
(for watch).

```swift
public protocol DiscoveryProtocol: Sendable {
    /// Run the discovery, consuming samples from the given stream
    /// and emitting events as the protocol progresses.
    func run<S: AsyncSequence>(
        samples: S,
        events: AsyncStream<DiscoveryEvent>.Continuation
    ) async throws -> DiscoveryResult
        where S.Element == BioSample, S: Sendable
}

public struct DiscoveryResult: Sendable, Codable, Equatable {
    /// The discovered resonance frequency in bpm.
    public let resonanceFrequency: Double
    /// Mean coherence at each tested rate.
    public let coherenceProfile: [RateCoherence]
    /// Total discovery duration.
    public let duration: Duration
    /// Which protocol was used.
    public let method: DiscoveryMethod
}

public struct RateCoherence: Sendable, Codable, Equatable {
    public let rate: Double    // bpm
    public let coherence: Double  // mean coherence during measurement
}

public enum DiscoveryMethod: String, Sendable, Codable {
    case lehrerStepped
    case fisherSweep
    case smartStart
}

public enum DiscoveryEvent: Sendable, Equatable {
    /// The current target breathing rate has changed.
    case rateChanged(bpm: Double)
    /// The protocol phase has changed.
    case phaseChanged(DiscoveryPhase)
    /// A coherence measurement was collected for a rate.
    case measurementCollected(rate: Double, coherence: Double)
    /// Progress through the overall protocol (0...1).
    case progress(Double)
}

public enum DiscoveryPhase: String, Sendable, Codable, Equatable {
    case settling
    case ramping
    case measuring
    case transitioning
    case complete
}
```

---

## 4. Implementations

### 4.1 LehrerDiscovery

```swift
public actor LehrerDiscovery: DiscoveryProtocol {
    public let rates: [Double]          // default [5.0, 5.5, 6.0, 6.5, 7.0]
    public let settlingSeconds: Double  // 30
    public let rampSeconds: Double      // 10
    public let settleSeconds: Double    // 50
    public let measureSeconds: Double   // 120
    public let transitionSeconds: Double // 15
    public let scorer: any CoherenceScorer
    public let config: CoherenceConfig

    public init(scorer: any CoherenceScorer, config: CoherenceConfig)
    public func run<S>(samples: S, events: ...) async throws -> DiscoveryResult
}
```

### 4.2 FisherSweepDiscovery

```swift
public actor FisherSweepDiscovery: DiscoveryProtocol {
    public let startRate: Double        // 6.75
    public let endRate: Double          // 4.25
    public let sweepSeconds: Double     // 720 (12 min)
    public let settlingSeconds: Double  // 30
    public let rampSeconds: Double      // 10
    public let binWidth: Double         // 0.25 bpm
    public let scorer: any CoherenceScorer
    public let config: CoherenceConfig

    public init(scorer: any CoherenceScorer, config: CoherenceConfig)
    public func run<S>(samples: S, events: ...) async throws -> DiscoveryResult
}
```

### 4.3 SmartStartDiscovery

```swift
public actor SmartStartDiscovery: DiscoveryProtocol {
    public let rfHistory: [Double]       // prior RF measurements
    public let analyzer: RFStabilityAnalyzer
    public let scorer: any CoherenceScorer
    public let config: CoherenceConfig
    public let quickConfirmThreshold: Double  // 40% coherence
    public let quickConfirmSeconds: Double    // 60

    public init(
        rfHistory: [Double],
        scorer: any CoherenceScorer,
        config: CoherenceConfig,
        analyzer: RFStabilityAnalyzer = RFStabilityAnalyzer()
    )
    public func run<S>(samples: S, events: ...) async throws -> DiscoveryResult
}
```

Smart Start internally delegates to `FisherSweepDiscovery` (full or narrow) or runs its own quick-confirm loop based on the stability analysis.

---

## 4a. Clock injection (per audit)

Discovery protocols are generic over `Clock` so tests can inject a
`TestClock` that advances instantly:

```swift
public actor LehrerDiscovery<C: Clock>: DiscoveryProtocol where C.Duration == Duration {
    private let clock: C
    // ...
}
```

Production creates `LehrerDiscovery(clock: ContinuousClock(), ...)`.
Tests create `LehrerDiscovery(clock: TestClock(), ...)` where
`TestClock.sleep(for:)` is a no-op (or records the requested duration
for assertion). This eliminates real-time waiting from test execution
and makes timing assertions exact, not approximate.

```swift
/// A clock that advances instantly. sleep() is a no-op. now() returns
/// a tracked value that advances by the duration requested in each
/// sleep() call, so timing-dependent logic behaves deterministically.
public actor TestClock: Clock {
    public typealias Duration = Swift.Duration
    public struct Instant: InstantProtocol {
        public var offset: Duration
        // ...
    }
    private var _now: Instant = Instant(offset: .zero)
    public var now: Instant { get async { _now } }
    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        // Advance virtual time instantly
        _now = deadline
    }
}
```

## 4b. Tie-breaking rule (per audit)

When two or more rates produce identical mean coherence, the protocol
selects the rate **closest to 6.0 bpm** (the most common resonance
frequency). If still tied, the lower rate wins. This rule is
documented, deterministic, and tested.

## 4c. NaN / edge value handling (per audit)

If the scorer returns NaN or non-finite coherence for a rate, that
rate is treated as coherence = 0 for selection purposes. A
`DeviceHealth.degraded(reason: "NaN coherence at X bpm")` event
is emitted so the app can surface it if desired. This is defensive
against corrupted sensor data without crashing the discovery.

---

## 5. Test strategy (~50 tests)

### DiscoveryResult + supporting types (~5)
- Codable roundtrip for `DiscoveryResult`, `RateCoherence`, `DiscoveryMethod`
- `DiscoveryEvent` equality

### LehrerDiscovery (~10)
- Returns exactly 5 rate-coherence pairs for the default rate set
- Winning rate has the highest mean coherence
- Events fire in order: settling → (ramp → settle → measure) × 5 → complete
- `rateChanged` events match the rate set
- Progress goes from 0 to 1
- Custom rate set honored
- Duration is approximately 18 minutes' worth of samples

### FisherSweepDiscovery (~8)
- Returns coherence profile with correct bin count (~10 bins for 2.5 bpm range at 0.25 width)
- Winning bin has the highest mean coherence
- Events fire: settling → ramping → measuring (continuous) → complete
- Rate changes are continuous (descending from 6.75 to 4.25)
- Custom sweep range honored

### SmartStartDiscovery (~12)
- Empty rfHistory → runs full sweep, produces DiscoveryResult with method `.smartStart`
- 1 prior session → narrow sweep ±1.0 bpm around last RF
- 3+ sessions, stable RF → quick-confirm path (60s at predicted RF)
- 3+ sessions, variable RF → narrow-confirm path (2-min sweep)
- Quick-confirm succeeds (coherence > 40% within 60s) → returns predicted RF
- Quick-confirm fails (coherence stays low) → falls back to narrow-confirm
- RF stability analyzer integration: SD < 0.3 → stable path, SD ≥ 0.3 → variable path

All tests use `SyntheticRRSource` to generate deterministic RR data at
known breathing rates and `TestClock` for instant time advancement.

### Cancellation tests (per audit) (~5)
- Lehrer: cancel during settling → throws CancellationError, no `.complete` emitted
- Lehrer: cancel during measurement → no partial coherence emitted, no additional rateChanged
- Fisher: cancel mid-sweep → throws CancellationError, partial result NOT emitted
- SmartStart: cancel during quick-confirm → CancellationError
- SmartStart: cancel during delegated sweep → cancellation propagates to child

### Early termination tests (~2)
- Sample stream ends mid-protocol → `run()` throws meaningful error (not hang)
- Empty sample stream (0 samples) → throws immediately

### Numerical robustness tests (~4)
- All-zero coherence across all rates → deterministic winner (closest to 6.0 bpm)
- All-equal coherence → same tie-breaking rule (closest to 6.0, then lower wins)
- NaN coherence at one rate → treated as 0, other rates unaffected
- Extremely small coherence values (1e-9) → sorting does not crash

### Progress invariant tests (~2)
- Progress is monotonically non-decreasing
- Progress is bounded [0, 1], ends exactly at 1.0

### Fisher bin boundary tests (~2)
- Sample at exact bin boundary (e.g. 5.25 bpm with 0.25 width) → consistent bin assignment
- Correct bin count for arbitrary sweep ranges

### SmartStart behavioral guarantees (per audit) (~3)
- Quick-confirm emits exactly one `rateChanged` event
- Narrow sweep range is exactly ±1.0 bpm from predicted RF
- DiscoveryResult.method is always `.smartStart` even when delegated internally to Fisher

---

## 6. Files

```
Sources/BioFeedbackKit/Discovery/
├── DiscoveryProtocol.swift           — protocol + result + event types
├── TestClock.swift                   — virtual clock for testing (public, reusable)
├── LehrerDiscovery.swift             — classic stepped
├── FisherSweepDiscovery.swift        — continuous sweep
└── SmartStartDiscovery.swift         — adaptive

Tests/BioFeedbackKitTests/
└── DiscoveryProtocolTests.swift      — all ~35 tests
```

---

## 7. Constraints

- Library-level, cross-platform (no platform dependencies)
- Consumes pre-connected sample streams, does NOT own device lifecycle
- Emits `DiscoveryEvent`s for the app's session orchestrator to translate into breathing commands / UI state
- Testable with `SyntheticRRSource` — no real hardware needed
- All types `Sendable`, `Codable` where appropriate
