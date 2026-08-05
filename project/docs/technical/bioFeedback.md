# BioFeedbackKit — Claude Code Handoff

## Status

The BusinessMath upstream work is complete. All six streaming gaps identified in the
prior planning doc have been implemented:

- `Timestamped<T>` wrapper
- Time-based windowing (tumbling + sliding)
- `successiveDifferences()`, `rollingSuccessiveDifferenceRMS(window:)`
- `rollingThresholdExceedanceRate(window:, threshold:)`
- Multi-rate stream alignment (`.nearest` strategy)
- FFT streaming (`vDSP` on Darwin, pure-Swift fallback for Linux/Android)

**Next task: design and build BioFeedbackKit.**

-----

## What BioFeedbackKit Is

A cross-platform Swift library that ingests real-time biofeedback data from connected
devices (e.g. Polar H10 heart strap, EEG headband), processes it through an HRV
algorithm, and emits feedback signals to help users manage heart rate variability and
coherence state. It has an existing web app; this library underpins the native iOS,
watchOS, visionOS, and Android apps.

-----

## Core Architectural Decisions

**On-device sovereign.** The full algorithm runs locally. No server dependency for
core function. Sessions complete fully offline.

**OTA algorithm updates via config, not code.** Algorithm logic ships with the app.
A remote `AlgorithmConfig` struct (weights, thresholds) is fetched and persisted
locally — no App Store review required for algorithm improvements. Every synced
session carries the config version that produced it for clean training cohorts.

**Anonymization at the edge.** PII is stripped/hashed in the library before any
data leaves the device. The sync layer never sees identifiable data. Telemetry
collection is gated behind an explicit `TelemetryConsent` type.

**Swift 6 strict concurrency throughout.** BusinessMath’s streaming layer is already
Swift 6 compliant. BioFeedbackKit must match.

**Android via Swift 6.3 SDK.** The Swift core cross-compiles to Android as a shared
library. A thin Kotlin shell handles Activity lifecycle, permissions, and BLE — it
feeds raw RR intervals up to Swift via `swift-java` JNI. All algorithm logic is
pure Swift, shared verbatim across platforms.

-----

## Package Structure

```
BioFeedbackKit/
  Sources/BioFeedbackKit/
    Devices/
      BiofeedbackDevice.swift       ← Protocol: async stream of BioSample
      PolarAdapter.swift            ← Polar H10 / BLE adapter
      AppleWatchAdapter.swift       ← HealthKit / native HR
      BioSample.swift               ← Common timestamped sample type

    Signal/
      RRBuffer.swift                ← Sliding window buffer for incoming RR intervals
      HRVMetrics.swift              ← RMSSD, SDNN, pNN50 (wraps BusinessMath ops)
      FrequencyDomain.swift         ← LF/HF ratio (wraps BusinessMath FFT streaming)

    Algorithm/
      HRVAlgorithm.swift            ← Protocol: injectable, swappable
      CoreAlgorithm.swift           ← Ships with app; uses BusinessMath MLR
      AlgorithmConfig.swift         ← OTA-updatable weights/thresholds, Codable
      ConfigFetcher.swift           ← Remote fetch + local persistence

    Feedback/
      FeedbackEvent.swift           ← Semantic output: .increaseCoherence, .sustain, etc.
      FeedbackEmitter.swift         ← Translates algorithm output → FeedbackEvent stream

    Sync/
      TelemetryConsent.swift        ← Explicit consent model, gates all collection
      SessionRecord.swift           ← Anonymized session payload, version-tagged
      SyncPipeline.swift            ← Append-only local buffer → opportunistic upload
```

-----

## The Boundary: BusinessMath vs. BioFeedbackKit

BusinessMath owns the math. BioFeedbackKit owns the physiology and product logic.

|Lives in BioFeedbackKit                            |Why                                             |
|---------------------------------------------------|------------------------------------------------|
|Named HRV metrics (RMSSD, SDNN, pNN50)             |The 50ms threshold in pNN50 is anatomy, not math|
|LF/HF band definitions (0.04–0.15 Hz, 0.15–0.40 Hz)|Physiological convention                        |
|`CoherenceScorer`                                  |Domain algorithm, not general math              |
|`AlgorithmConfig` + OTA fetch                      |Product concern                                 |
|`BiofeedbackDevice` protocol + adapters            |Hardware abstraction                            |
|`FeedbackEvent` emission                           |Product concern                                 |
|Anonymized telemetry sync                          |Product concern                                 |

-----

## How BioFeedbackKit Uses BusinessMath

|BioFeedbackKit component          |BusinessMath feature                                                                                      |
|----------------------------------|----------------------------------------------------------------------------------------------------------|
|`RRBuffer` → `HRVMetrics`         |`Timestamped<T>`, time-based windowing, `rollingSuccessiveDifferenceRMS`, `rollingThresholdExceedanceRate`|
|`FrequencyDomain`                 |FFT streaming, `vDSP` backend                                                                             |
|Multi-sensor fusion (HRV + motion)|Multi-rate stream alignment                                                                               |
|`CoherenceScorer`                 |`MultipleLinearRegression`                                                                                |
|`ConfigOptimizer` (server-side)   |GPU-accelerated genetic algorithms                                                                        |
|Session trend / longitudinal view |`TimeSeries`, seasonal decomposition, forecasting                                                         |
|Algorithm A/B validation          |Hypothesis testing                                                                                        |
|Artifact / noise detection        |CUSUM, composite anomaly scoring                                                                          |

-----

## HRV Signal Pipeline (runtime flow)

```
Device (BLE / HealthKit)
  └── AsyncSequence of raw RR intervals (ms)
        └── .timestamped()
              └── RRBuffer (validates, filters ectopic beats)
                    ├── .window(duration: .seconds(300))
                    │     ├── HRVMetrics.rmssd()       → time-domain
                    │     ├── HRVMetrics.sdnn()
                    │     ├── HRVMetrics.pnn50()
                    │     └── FrequencyDomain.lfhfRatio()  → frequency-domain
                    │
                    └── CoreAlgorithm (MLR over metrics + AlgorithmConfig weights)
                          └── FeedbackEmitter
                                └── AsyncSequence<FeedbackEvent>
                                      └── App UI / haptics / audio cues
```

-----

## Suggested Build Order

1. **`BioSample` + `BiofeedbackDevice` protocol** — establishes the input contract
1. **`RRBuffer` + `HRVMetrics`** — core signal layer; unit-testable in isolation using `AsyncValueStream` from BusinessMath
1. **`FrequencyDomain`** — LF/HF wrapping the BusinessMath FFT operator
1. **`HRVAlgorithm` protocol + `CoreAlgorithm`** — wires metrics into MLR scorer
1. **`AlgorithmConfig` + `ConfigFetcher`** — OTA config fetch + local persistence
1. **`FeedbackEvent` + `FeedbackEmitter`** — output layer
1. **`TelemetryConsent` + `SyncPipeline`** — telemetry, last because it needs the full session shape
1. **`PolarAdapter` + `AppleWatchAdapter`** — hardware adapters, can mock for all prior steps

-----

## Key Testing Notes

- Steps 1–6 can be tested entirely with `AsyncValueStream([...])` from BusinessMath
  as a mock device — no hardware required
- `AlgorithmConfig` should have a local fixture file for tests; do not hit a real
  endpoint in CI
- All streaming tests should avoid wall-clock timing (use count-based windows in
  tests where possible); time-based window tests should use injected clocks
- The `HRVAlgorithm` protocol exists specifically to make the algorithm swappable
  in tests

-----

## Repository

**BusinessMath** (upstream dependency, changes already merged):
`https://github.com/jpurnell/BusinessMath`
Swift 6.0+, iOS 14+ / macOS 13+ / watchOS 7+ / visionOS 1+ / Linux

**BioFeedbackKit:** New package, not yet created.
Minimum targets: iOS 16+, watchOS 9+, visionOS 1+, macOS 13+, Linux (Android)
