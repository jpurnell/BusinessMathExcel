# Design Proposal: narbis-watch v1 — Standalone watchOS App

**Status:** APPROVED 2026-04-09 — building
**Date:** 2026-04-09

---

## 1. Objective

Build the first narbis app target: a **standalone watchOS app** that
proves the full coherence pipeline end-to-end with zero external
devices. The user puts on their Apple Watch, launches the app, and
starts an HRV coherence training session entirely from the wrist.

This is the fastest path to a working demo because:
- Zero external BLE devices needed (no pairing, no connection screens)
- HealthKit is already abstracted via `BioFeedbackKit-HealthKit`
- The dual-conformance `AppleWatchDevice` already works as both input and output
- Testable on the watchOS simulator with mocked HealthKit data
- The most compelling pitch: "just your watch"

---

## 2. Scope

### In scope (v1 — full training experience on the wrist)
- New Xcode project with SPM dependencies: `narbis-watch/` at the workspace root
- **HealthKit authorization flow** — request HR + heartbeat-series access on first launch
- **`HKHealthStoreAdapter`** — real HealthKit wrapper (deferred from the adapter package work; ships now as part of the watchOS app)
- **Session orchestrator** — state machine driving: idle → discovery → settling → training → results
- **Discovery protocols** — all three (Lehrer stepped, Fisher sweep, Smart Start adaptive) are library types in `BioFeedbackKit/Discovery/`. The watch orchestrator drives them via the `AppleWatchDevice` sample stream.
- **Breathing pacer** — visual circle on screen that expands/contracts with the breathing phase; haptic taps on phase transitions (already in `AppleWatchDevice`)
- **Coherence dashboard** — live coherence ring (0–100%), current heart rate, current breathing rate, elapsed time
- **Results screen** — average coherence, peak coherence, time in zone, session duration
- **Settings** — resonance frequency (discovered via Smart Start, or manual override slider 4.5–7.0 bpm), session duration (10/15/20 min toggle), inhale ratio
- **Simulation mode** — first-class feature using `SimulationDevice` from BioFeedbackKit core. Toggle in Settings. Works on the simulator without HealthKit. Uses `SyntheticRRSource` to generate realistic HR data that responds to the pacer rate.
- **Local persistence** — session history + RF history stored on-watch via SwiftData. `SessionSummary` Codable struct is the cross-platform contract; SwiftData is the Apple-platform storage backend. RF history feeds the Smart Start adaptive system.

### NOT in scope (v1)
- Cloud sync (Firebase, CloudKit) — v1 is local-only
- iPhone companion app — per-platform sovereign, no relay
- Complications / widgets
- Audio cues (watch speaker is limited)
- Edge glasses integration from the watch (possible via BLE but adds complexity; defer)

---

## 3. The pipeline on the wrist

```
HealthKit (on-wrist HR sensor)
  └── AppleWatchDevice.sampleStream()
        └── AsyncThrowingStream<BioSample>
              ├── HRVMetrics (time domain)
              ├── FrequencyDomainMetrics (frequency domain)
              │
              └── CoherenceAlgorithm.score(timeDomain:frequencyDomain:)
                    └── CoherenceResult
                          │
                          ├── StreamingCoherenceEngine (EMA smoothing)
                          │     └── smoothed CoherenceResult
                          │
                          └── → FeedbackUpdate
                                │
                                └── AppleWatchDevice.render(stream:)
                                      ├── displayState → SwiftUI view
                                      └── haptic taps on phase transitions
```

Same pipeline as the iOS + glasses version, just different adapters at
each end. The math in the middle is identical.

---

## 4. App architecture

### 4.1 Session orchestrator

The session state machine drives the training experience. It's a
testable actor (not a SwiftUI view model) so the session logic can be
unit-tested without UI.

```swift
public actor SessionOrchestrator {
    public enum Phase: Sendable, Equatable {
        case idle
        case settling(elapsed: Duration)    // 30s, resting HR measured
        case training(elapsed: Duration)    // active coherence feedback
        case results(summary: SessionSummary)
    }

    public init(
        device: AppleWatchDevice,
        scorer: any CoherenceScorer,
        config: CoherenceConfig,
        sessionDuration: Duration,
        breathingRate: Double
    )

    /// Starts the full session flow: connect → settle → train → results.
    public func start() async throws

    /// Cancels the active session and moves to results (partial).
    public func stop() async throws

    /// Current phase. SwiftUI observes this via an AsyncStream.
    public var phase: AsyncStream<Phase> { get }
}
```

The orchestrator:
1. Calls `device.connect()` (HealthKit auth + workout start)
2. Enters settling phase — collects RR for 30s, measures resting HR
3. Enters training phase — builds `StreamingCoherenceEngine`, starts the `render` loop, generates `FeedbackUpdate`s from each `CoherenceResult` with the breathing pacer's current phase
4. After `sessionDuration` elapses, enters results phase — computes `SessionSummary` from the collected scores
5. Calls `device.disconnect()`

### 4.2 Breathing pacer

A standalone `BreathingPacer` that tracks where we are in the 4-phase
breath cycle at any given moment:

```swift
public actor BreathingPacer {
    public init(breathingRate: Double, inhaleRatio: Double = 0.4)

    /// Returns the current breathing phase + progress, computed from
    /// the session's elapsed time. Called once per coherence update
    /// to populate `FeedbackUpdate.breathingPhase`.
    public func currentPhase(sessionElapsed: Duration) -> BreathingPhase
}
```

Pure time-based math: given the breathing rate and the session's elapsed
time, compute which phase we're in and how far through it. No state
beyond the configuration.

### 4.3 Session summary

```swift
public struct SessionSummary: Sendable, Codable, Equatable {
    public let startDate: Date
    public let duration: Duration
    public let averageCoherence: Double
    public let peakCoherence: Double
    public let timeInZone: Duration     // seconds above 50% coherence
    public let restingHeartRate: Double  // BPM during settling
    public let breathingRate: Double     // configured RF
    public let coherenceTimeSeries: [Double]  // sampled at 1 Hz
}
```

### 4.4 SwiftUI views

| Screen | What it shows |
|---|---|
| **Home** | "Start Training" button, last session summary, settings gear |
| **Training** | Breathing circle (expands/contracts), coherence ring, HR, breathing rate, elapsed time, phase label |
| **Results** | Average/peak coherence, time in zone, duration, coherence-over-time chart, "Done" button |
| **Settings** | RF (manual slider 4.5–7.0 bpm), duration toggle (10/15/20 min), inhale ratio slider |

The views are pure SwiftUI consuming `SessionOrchestrator.phase` and
`AppleWatchDevice.displayState`. No business logic in the views.

---

## 5. Dependencies

```swift
// narbis-watch/Package.swift (or Xcode project)
dependencies: [
    .package(path: "../BioFeedbackKit"),
    .package(path: "../BioFeedbackKit-HealthKit"),
]
```

That's it. Two packages. Everything else is watchOS system frameworks
(HealthKit, WatchKit, SwiftUI).

---

## 6. Constraints

- **watchOS 10+** — minimum deployment target (matches BioFeedbackKit)
- **Standalone** — no iPhone companion, no WatchConnectivity
- **HealthKit workout session required** — for live HR streaming
- **Background workout** — the session should survive wrist-down / screen-off (workout sessions already do this on watchOS)
- **Swift 6 strict concurrency** throughout
- **No `String(format:)`, `try!`, `as!`, `fatalError`**

---

## 7. Test strategy

### Testable layers (unit tests, ~25 tests)

The `SessionOrchestrator`, `BreathingPacer`, and `SessionSummary` are
all testable without a real watch or HealthKit — they consume
`MockHealthStore` via the existing `AppleWatchDevice` bridge layer.

| Test | What |
|---|---|
| **BreathingPacer**: 6 bpm at t=0 → `.inhale(progress: 0)` | |
| **BreathingPacer**: 6 bpm at t=2s → `.inhale(progress: 0.5)` (4s inhale) | |
| **BreathingPacer**: 6 bpm at t=4s → `.exhale(progress: 0)` | |
| **BreathingPacer**: 6 bpm at t=10s → `.inhale(progress: 0)` (next cycle) | |
| **BreathingPacer**: custom inhaleRatio honored | |
| **SessionSummary**: averageCoherence computed correctly from array | |
| **SessionSummary**: peakCoherence is max of array | |
| **SessionSummary**: timeInZone counts samples above 50% | |
| **SessionSummary**: Codable roundtrip | |
| **SessionOrchestrator**: start() → settling → training → results | |
| **SessionOrchestrator**: phase stream emits all transitions | |
| **SessionOrchestrator**: stop() mid-training → partial results | |
| **SessionOrchestrator**: settling lasts 30s then transitions | |
| **SessionOrchestrator**: training lasts configured duration | |
| **SessionOrchestrator**: coherence pipeline produces non-trivial scores on synthetic data | |
| More as we discover edge cases during implementation | |

### Integration test (1 big test)

Feed `SyntheticRRSource` data through the full orchestrator pipeline
(HealthKit mock → coherence → feedback updates → display state)
and verify that the resulting `SessionSummary` has sensible numbers.
This is the "the whole pipeline works on the wrist" test.

### SwiftUI previews

Views are tested visually via Xcode previews with mock data. No
snapshot testing in v1 — that's overhead we can add later if the UI
stabilizes.

---

## 8. Files to add

```
narbis-watch/
├── Package.swift (or Xcode project)
├── Sources/
│   ├── NarbisWatchApp.swift            — @main App
│   ├── Session/
│   │   ├── SessionOrchestrator.swift   — state machine
│   │   ├── BreathingPacer.swift        — pure time-based pacer
│   │   └── SessionSummary.swift        — result value type
│   ├── Views/
│   │   ├── HomeView.swift
│   │   ├── TrainingView.swift
│   │   ├── ResultsView.swift
│   │   ├── SettingsView.swift
│   │   └── Components/
│   │       ├── CoherenceRing.swift     — ring chart component
│   │       └── BreathingCircle.swift   — expanding/contracting circle
│   └── Persistence/
│       └── SessionStore.swift          — local session history
├── Tests/
│   └── NarbisWatchTests/
│       ├── BreathingPacerTests.swift
│       ├── SessionSummaryTests.swift
│       ├── SessionOrchestratorTests.swift
│       └── IntegrationTests.swift
└── Assets/
    └── Assets.xcassets
```

---

## 9. Resolved decisions (from earlier conversation)

1. **Xcode project with SPM dependencies.** Testable logic (orchestrator, pacer, summary) in a local Swift package inside the project. App target imports both the local package and BioFeedbackKit dependencies.
2. **`HKHealthStoreAdapter` ships as part of this work.** Lives in `BioFeedbackKit-HealthKit`, gated by `#if canImport(HealthKit)`.
3. **Simulation mode is a first-class feature** using `SimulationDevice` from BioFeedbackKit core. Toggle in Settings. Works on simulator.
4. **SwiftData for Apple persistence.** `SessionSummary` Codable struct is the cross-platform contract; SwiftData is the Apple storage backend. Android gets its own persistence via Kotlin later.
5. **Discovery protocols are IN scope.** Smart Start is the default mode. Lehrer and Fisher available manually. All three are library types in `BioFeedbackKit/Discovery/` — the app orchestrator just drives them.
6. **Per-platform sovereign.** No iPhone companion, no WatchConnectivity. The watch runs the full pipeline independently.

---

## 10. Approval checklist

- [ ] Approve scope (standalone watchOS, discovery included, simulation mode, SwiftData persistence)
- [ ] Approve session orchestrator shape in §4.1 (now includes discovery flow)
- [ ] Approve breathing pacer shape in §4.2
- [ ] Approve view structure in §4.4
- [ ] Approve that `HKHealthStoreAdapter` ships as part of this work
- [ ] Approve writing tests BEFORE implementation for testable layers
