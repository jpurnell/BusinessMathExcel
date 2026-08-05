# Design Proposal: SimulationDevice v1

**Status:** APPROVED 2026-04-09 — moving to RED
**Date:** 2026-04-09

---

## 1. Objective

Library-level dual-conformance simulation device that every app target
can use for demo mode, simulator testing, and development. Uses
`SyntheticRRSource` internally and responds to the pacer rate so that
coherence naturally rises when the "user" follows the breathing guide.

Lives in BioFeedbackKit core — no platform dependencies, no adapter
package, usable everywhere.

---

## 2. The coupling model

Real user: pacer guides breathing → breathing modulates HR → HR
sensor picks it up → coherence algorithm detects the rhythm → feedback.

Simulation: `render()` receives `FeedbackUpdate` with a breathing
phase → the device updates its internal pacer frequency → the next
generated RR samples oscillate at that frequency → coherence rises.

This creates the same feedback loop synthetically. When the pacer is
active, the simulation produces high coherence. When idle, it produces
baseline noise. Exactly what v5 §9 specifies.

---

## 3. API

```swift
public actor SimulationDevice: BiofeedbackDevice, FeedbackDevice {
    // Device
    public nonisolated let name: String
    public nonisolated let transport: ConnectionTransport = .inProcess
    public nonisolated let reconnectionPolicy: ReconnectionPolicy = .none
    public var isConnected: Bool { get async }
    public nonisolated let connectionState: AsyncStream<ConnectionState>
    public nonisolated let health: AsyncStream<DeviceHealth>

    // BiofeedbackDevice
    public func sampleStream() async throws -> AsyncThrowingStream<BioSample, any Error>

    // FeedbackDevice
    public nonisolated let capabilities: FeedbackCapabilities = [.visual, .haptic, .heartRateDisplay]
    public nonisolated let displayState: AsyncStream<SimulationDisplayState>
    public func render<S: AsyncSequence>(_ updates: S) async throws
        where S.Element == FeedbackUpdate, S: Sendable

    // Configuration
    public init(
        name: String = "Simulation",
        baselineRR: Double = 800,    // ms
        amplitude: Double = 30,       // ms RSA
        noiseStdDev: Double = 5,      // ms
        defaultPacerFrequency: Double = 0.10,  // Hz (6 bpm)
        seed: UInt64 = 42
    )

    /// Updates the internal pacer frequency. Called by render() when
    /// breathing phase changes, or directly for testing.
    public func setPacerFrequency(_ hz: Double)
}
```

The sample stream generates one BioSample per ~baselineRR ms using
the CURRENT pacer frequency. When `render()` receives updates with
a non-idle breathing phase, it extracts the implied breathing rate
and calls `setPacerFrequency(...)`.

---

## 4. Test strategy (~15 tests)

- Init produces disconnected state
- connect() flips isConnected
- sampleStream() before connect throws
- sampleStream() yields BioSamples at roughly the expected rate
- BioSample.rrInterval is near baselineRR ± amplitude
- Deterministic: same seed → same first N samples (before any pacer change)
- setPacerFrequency() changes the modulation (feed samples into FrequencyDomainMetrics, check peak shifts)
- render() emits to displayState
- render() with inhale phase triggers pacer frequency update
- Dual conformance: usable as both any BiofeedbackDevice and any FeedbackDevice
- Full pipeline: sampleStream → HRVMetrics + FrequencyDomain → CoherenceAlgorithm → score is non-trivial
