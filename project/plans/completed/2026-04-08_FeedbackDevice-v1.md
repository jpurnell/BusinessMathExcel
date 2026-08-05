# Design Proposal: FeedbackDevice Protocol v1

**Status:** SHIPPED 2026-04-08
**Date:** 2026-04-08

## Implementation notes

- All 23 new tests passed; total **263 / 263**, zero warnings, zero forbidden patterns
- `FeedbackDevice.isConnected` is `var isConnected: Bool { get async }` — async getter so actor conformers (like `MockFeedbackDevice`) can vend an isolated stored property without crossing concurrency domains. Documented in the protocol.
- `FeedbackBroadcast.init` is `async` for the same reason — actor inits are nonisolated by default in Swift 6 and can't mutate isolated state. Async init lets the pump task be stored properly. Callers do `let broadcast = await FeedbackBroadcast(source: ...)`.
- `swift-async-algorithms` dependency added but the broadcast helper is built on top of standard `AsyncStream` + a single pump task. The dependency is in place for future operators (debounce, throttle, etc.) downstream code may need.
- `MockFeedbackDevice` declares `nonisolated let name`, `nonisolated let capabilities`, and `nonisolated let health` — three immutable properties that can satisfy the protocol synchronously. `isConnected` and `receivedUpdates` are actor-isolated and accessed via `await`.
- Integration test verifies the full chain: source → `FeedbackBroadcast` → 3 `MockFeedbackDevice`s rendered in parallel, all 3 receive the identical 10-update sequence.

## Resolved decisions

1. `health` as `AsyncStream<FeedbackHealth>` (push-when-events-happen, app subscribes)
2. Apple Watch can intentionally conform to both `BiofeedbackDevice` and `FeedbackDevice` (composition over inheritance)
3. `render` is one-shot per connect/disconnect cycle; documented as such
4. `swift-async-algorithms` added as a new SPM dependency
5. Edge SDK porting strategy: clean Swift port as `EdgeSDK-Swift` SPM package using the Python SDK's API as the spec; `BioFeedbackKit-EdgeBLE` adapter depends on it. The existing edge-SDK has no tests to port.
**References:**
- v5 §6.4 (coherence-to-tint mapping)
- v5 §10 (UI/UX, multimodal feedback)
- Conversation 2026-04-08 on input vs output device abstraction

---

## 1. Objective

Add a generalized output-device abstraction to BioFeedbackKit so the
same session can drive feedback through wildly different hardware
(Edge glasses, Apple Watch, Vision Pro, AirPods, future devices) via
swappable plug-in adapters that conform to a single protocol. Each
adapter lives in its own SPM package outside the core library; the
core just defines the protocol surface, the value types, the broadcast
helper, and a `MockFeedbackDevice` for testability.

This proposal mirrors the existing `BiofeedbackDevice` (input) plug-in
pattern: clean protocol in core, concrete adapters in per-device repos.

---

## 2. Scope

### In scope (this proposal — landing in BioFeedbackKit core)

| Type | Purpose |
|---|---|
| `FeedbackDevice` (protocol) | Output-device abstraction |
| `FeedbackUpdate` (struct) | Uniform per-update payload, fully `Codable` |
| `BreathingPhase` (enum) | Pacer state with `.idle` case |
| `FeedbackCapabilities` (OptionSet) | What modalities a device supports |
| `FeedbackHealth` (enum) | Soft-error / status events for the health stream |
| `FeedbackBroadcast` (actor) | Multi-cast helper for fanning a single stream to N devices |
| `MockFeedbackDevice` (actor) | Test fake that records everything it receives |
| New SPM dependency: `swift-async-algorithms` | For broadcast / multicast plumbing |

### NOT in scope (separate work, separate repos)

| Item | Where it lives |
|---|---|
| `BioFeedbackKit-Polar` (Polar H10 input adapter) | New SPM package, depends on BioFeedbackKit + polar-ble-sdk |
| `BioFeedbackKit-EdgeBLE` (Edge glasses output adapter) | New SPM package, depends on BioFeedbackKit + EdgeSDK-Swift |
| `EdgeSDK-Swift` (clean Swift port of `dgvinc/edge-SDK`) | New SPM package, BLE/CoreBluetooth, no BioFeedbackKit dependency |
| `BioFeedbackKit-HealthKit` (Apple Watch input + output) | New SPM package |
| `narbis-edge-ios` (the actual iOS app) | New Xcode app target |
| Discovery state machines, training session orchestrator | App layer |

---

## 3. The pull model (locked)

The protocol uses **pull** semantics: each device receives an
`AsyncSequence<FeedbackUpdate>` and consumes it at its own pace.

Why pull beat push (decided in conversation):

1. **Multi-device fan-out is the dominant case.** A typical user
   session may drive Watch + AirPods + Vision Pro simultaneously.
   With push, a slow or glitching device blocks the others. With
   pull, each device runs in its own task, consumes at its own rate,
   and can't poison the others.

2. **Error tolerance lives where the error context lives — in the
   device.** A BLE dropout in the Edge glasses adapter knows that
   correct recovery is "wait one connection interval and retry the
   `0xA2` write." A SwiftUI screen renderer's idea of "transient
   error" is completely different. The caller can't write
   per-device retry logic; the device must own it. Pull naturally
   gives the device the iteration loop it needs to do that.

3. **Cancellation is structured.** Each device's `render` task is a
   child of the session's parent task. Cancelling the session
   cancels every device's render loop in one move via standard
   structured concurrency.

4. **Sessions are 30 minutes long.** A brief Watch hiccup mid-session
   should never ruin the whole experience. Pull lets the affected
   device internally recover while the others keep going.

---

## 4. API Surface

### 4.1 The protocol

```swift
public protocol FeedbackDevice: Sendable {
    /// Human-readable name for the device (e.g. "Edge Glasses").
    var name: String { get }

    /// What modalities the device can render.
    var capabilities: FeedbackCapabilities { get }

    /// Whether the device is currently connected and ready to render.
    var isConnected: Bool { get }

    /// Per-device health events for soft (recoverable) issues.
    /// Apps subscribe to surface "Watch reconnecting…" indicators
    /// in the UI without interrupting the session.
    ///
    /// The device emits `.nominal` on a clean state, `.degraded`
    /// when partial functionality is unavailable, `.recovering`
    /// during transient retry, and `.dropping` when it can't
    /// keep up with the input stream.
    var health: AsyncStream<FeedbackHealth> { get }

    /// Establishes a connection to the device.
    func connect() async throws

    /// Disconnects from the device.
    func disconnect() async throws

    /// Renders an async stream of feedback updates. The device
    /// consumes updates at its own pace and translates each into
    /// its supported modalities (per `capabilities`). Updates that
    /// reference unsupported modalities are silently no-ops.
    ///
    /// **Error contract:** the device is responsible for tolerating
    /// transient failures (BLE dropouts, render glitches, buffer
    /// underruns) without throwing. Soft errors are surfaced via
    /// the `health` stream so the UI can show status indicators
    /// without interrupting the session. Only unrecoverable failures
    /// (device permanently disconnected, hardware fault) should
    /// throw from `render`.
    ///
    /// `render` returns when:
    /// - the input stream ends naturally
    /// - the current task is cancelled
    /// - the device hits an unrecoverable error (then throws)
    func render<S: AsyncSequence>(_ updates: S) async throws
        where S.Element == FeedbackUpdate, S: Sendable
}
```

### 4.2 The payload

```swift
public struct FeedbackUpdate: Sendable, Equatable, Codable {
    /// Current coherence score in [0, 100].
    public let coherence: Double

    /// Current breathing pacer state. `.idle` if no pacing is active.
    public let breathingPhase: BreathingPhase

    /// Current heart rate in BPM, or nil if unknown.
    public let heartRate: Double?

    /// Adaptive sensitivity level driving reward intensity.
    public let sensitivity: SensitivityLevel

    /// When this update was generated.
    public let timestamp: Date

    public init(
        coherence: Double,
        breathingPhase: BreathingPhase,
        heartRate: Double?,
        sensitivity: SensitivityLevel,
        timestamp: Date
    )
}

public enum BreathingPhase: Sendable, Equatable, Codable {
    /// No pacing active (settling, post-session, simulation idle).
    case idle
    /// Inhale phase active. `progress` is 0...1 through the phase.
    case inhale(progress: Double)
    /// Hold-in phase active. `progress` is 0...1 through the phase.
    case holdIn(progress: Double)
    /// Exhale phase active. `progress` is 0...1 through the phase.
    case exhale(progress: Double)
    /// Hold-out phase active. `progress` is 0...1 through the phase.
    case holdOut(progress: Double)
}
```

### 4.3 Capabilities

```swift
public struct FeedbackCapabilities: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Visual modalities — lens tint, screen pixels, AR overlay.
    public static let visual            = FeedbackCapabilities(rawValue: 1 << 0)
    /// Haptic modalities — taps, vibration, AirPods crown clicks.
    public static let haptic            = FeedbackCapabilities(rawValue: 1 << 1)
    /// Audio modalities — tones, spatial audio, breathing chimes.
    public static let audio             = FeedbackCapabilities(rawValue: 1 << 2)
    /// Native breathing-pace rendering (firmware does its own oscillation).
    public static let breathingGuidance = FeedbackCapabilities(rawValue: 1 << 3)
    /// Live heart-rate display.
    public static let heartRateDisplay  = FeedbackCapabilities(rawValue: 1 << 4)
    /// Ambient/environmental rendering (hue lights, room speakers, etc.).
    public static let ambient           = FeedbackCapabilities(rawValue: 1 << 5)
}
```

### 4.4 Health channel

```swift
public enum FeedbackHealth: Sendable, Equatable, Codable {
    /// Device is operating normally.
    case nominal
    /// Partial functionality unavailable. `reason` is human-readable.
    case degraded(reason: String)
    /// Transient failure recovery in progress. `attempt` counts retries.
    case recovering(attempt: Int)
    /// Falling behind the input stream; dropping updates to catch up.
    case dropping(samples: Int)
}
```

### 4.5 Multi-cast broadcast

Pulls in `swift-async-algorithms` as a new dependency (cross-platform,
Apple-supported, well-maintained). Provides the primitives we need to
fan a single source into N independent subscribers without writing our
own pump.

```swift
import AsyncAlgorithms

/// Broadcasts a single source `AsyncSequence<FeedbackUpdate>` to any
/// number of subscriber streams. Each subscriber sees the same
/// updates independently — a slow subscriber doesn't block fast ones,
/// and a subscriber that errors doesn't poison the others.
///
/// Built on top of `swift-async-algorithms` for the multicast plumbing.
///
/// Example:
/// ```swift
/// let broadcast = FeedbackBroadcast(source: engine.feedbackUpdates)
/// async let w = watch.render(broadcast.subscribe())
/// async let a = airpods.render(broadcast.subscribe())
/// async let v = visionPro.render(broadcast.subscribe())
/// try await (w, a, v)
/// ```
public actor FeedbackBroadcast {
    public init<S: AsyncSequence>(source: S)
        where S.Element == FeedbackUpdate, S: Sendable

    /// Returns a new subscriber stream. Each subscriber receives every
    /// update emitted by the source after subscription.
    public func subscribe() -> AsyncStream<FeedbackUpdate>

    /// Stops broadcasting and finishes all subscriber streams.
    public func finish()
}
```

The actor internally:
- Maintains a list of subscriber `AsyncStream<FeedbackUpdate>.Continuation`s
- Runs a single pump task that iterates the source and yields each
  update to every continuation
- Cleans up continuations when subscribers terminate
- Finishes everything cleanly on `finish()` or source exhaustion

### 4.6 MockFeedbackDevice

```swift
public actor MockFeedbackDevice: FeedbackDevice {
    public let name: String
    public let capabilities: FeedbackCapabilities
    public private(set) var isConnected: Bool = false
    public private(set) var receivedUpdates: [FeedbackUpdate] = []
    public nonisolated let health: AsyncStream<FeedbackHealth>

    public init(
        name: String = "Mock",
        capabilities: FeedbackCapabilities = [.visual, .haptic, .audio,
                                              .breathingGuidance, .heartRateDisplay]
    )

    public func connect() async throws
    public func disconnect() async throws
    public func render<S: AsyncSequence>(_ updates: S) async throws
        where S.Element == FeedbackUpdate, S: Sendable
}
```

The mock records every update it receives and exposes them via
`receivedUpdates`. Used in tests to verify that streaming flows
through the broadcast → device path correctly.

---

## 5. Constraints & Compliance

- Cross-platform — no Darwin-only APIs in core, no `CoreBluetooth`,
  no `HealthKit`. The protocol surface compiles on Linux.
- All types `Sendable`. `MockFeedbackDevice` and `FeedbackBroadcast`
  are actors.
- `Codable` on `FeedbackUpdate`, `BreathingPhase`, `FeedbackCapabilities`,
  `FeedbackHealth` — for telemetry/replay.
- No `String(format:)`, `try!`, `as!`, `fatalError`, force unwraps.
- Swift 6 strict concurrency throughout.
- New dependency: `swift-async-algorithms` (Apple, cross-platform,
  permissively licensed).

---

## 6. Test Strategy

### 6.1 Value type tests (~15)

| Test | What |
|---|---|
| `FeedbackUpdate` Codable JSON roundtrip | Encode + decode → equal |
| `FeedbackUpdate` Equatable | Identical inputs compare equal |
| `BreathingPhase.idle` Codable | Survives JSON |
| `BreathingPhase.inhale(progress:)` Codable | Associated value preserved |
| `BreathingPhase` all five cases Codable | Enum cases roundtrip |
| `FeedbackCapabilities` OptionSet algebra | union/intersection/contains work |
| `FeedbackCapabilities` Codable | Bitmask survives JSON |
| `FeedbackHealth.nominal` Codable | |
| `FeedbackHealth.degraded(reason:)` Codable | Associated value preserved |
| `FeedbackHealth.recovering(attempt:)` Codable | |
| `FeedbackHealth.dropping(samples:)` Codable | |
| `FeedbackUpdate` with optional `heartRate = nil` Codable | nil survives |

### 6.2 MockFeedbackDevice tests (~8)

| Test | What |
|---|---|
| Initial state: not connected, no recorded updates | |
| connect() flips isConnected | |
| disconnect() flips back | |
| render an empty AsyncStream → completes immediately, no recorded updates | |
| render a 3-update stream → records all 3 in order | |
| Cancellation: render a long stream, cancel parent task → render returns | |
| Two parallel renders into the same mock fail safely (or document behavior) | |
| `health` stream emits `.nominal` on connect | |

### 6.3 FeedbackBroadcast tests (~8)

| Test | What |
|---|---|
| Single subscriber: receives all updates from source | |
| Two subscribers: both receive every update | |
| Subscriber added before pump starts: receives full sequence | |
| Subscriber added after some updates: receives only subsequent updates | |
| Slow subscriber doesn't block fast subscriber | |
| Subscriber cancellation: other subscribers continue receiving | |
| `finish()` closes all subscriber streams | |
| Source exhaustion finishes all subscribers naturally | |

### 6.4 Integration test (~3)

| Test | What |
|---|---|
| Build SyntheticRRSource → StreamingCoherenceEngine → FeedbackBroadcast → 3 MockFeedbackDevices, verify all 3 mocks receive identical update sequences | |
| Apply a fan-out to two mocks where one has different capabilities, verify both still receive every update (capability check is the device's responsibility) | |
| End-to-end with one mock that throws on the 5th update — verify the broadcast continues delivering to other subscribers (mock isolation) | |

Total estimated: ~34 tests.

---

## 7. Files to Add

| File | Purpose |
|---|---|
| `Sources/BioFeedbackKit/Feedback/FeedbackDevice.swift` | Protocol |
| `Sources/BioFeedbackKit/Feedback/FeedbackUpdate.swift` | Payload + BreathingPhase |
| `Sources/BioFeedbackKit/Feedback/FeedbackCapabilities.swift` | OptionSet |
| `Sources/BioFeedbackKit/Feedback/FeedbackHealth.swift` | Health enum |
| `Sources/BioFeedbackKit/Feedback/FeedbackBroadcast.swift` | Multicast actor |
| `Sources/BioFeedbackKit/Feedback/MockFeedbackDevice.swift` | Test fake |
| `Tests/BioFeedbackKitTests/FeedbackDeviceTests.swift` | All ~34 tests |

Plus:

| File | Change |
|---|---|
| `Package.swift` | Add `swift-async-algorithms` dependency |

---

## 8. Open Questions

### 8.1 `health` as `AsyncStream` or property?

I went with `var health: AsyncStream<FeedbackHealth>` so the device
can push events as they happen and the app can subscribe. Alternative:
`var currentHealth: FeedbackHealth { get }` (poll) or a delegate
callback. The async-stream version is most consistent with the rest
of the library and gives the app a backpressure-aware subscription.

**Recommendation:** keep as `AsyncStream`.

### 8.2 Can a single device implement BOTH `BiofeedbackDevice` and `FeedbackDevice`?

Yes, by design. Apple Watch is the obvious case — its adapter
struct/actor conforms to both protocols, exposing the same physical
hardware connection as both an input source and an output sink. The
protocols are deliberately independent so this composition just works.

**No question, just confirming the design intent.**

### 8.3 Should `render` be a one-shot, or can a device be re-rendered?

Currently `render` is implicitly one-shot per `connect()` cycle:
disconnect → connect → render again. Multi-render in parallel on the
same device is undefined behavior (a device might handle it, might
not). Documentation should call this out.

**Recommendation:** document as "one render at a time per device,
re-render after disconnect/connect cycle." Don't add API for parallel
renders without a real use case.

### 8.4 `swift-async-algorithms` dependency

This adds one transitive dependency to BioFeedbackKit (currently:
just BusinessMath). It's Apple-maintained, cross-platform, and stable.

**Recommendation:** approve.

### 8.5 Edge SDK porting strategy

The user has confirmed: write a clean Swift implementation of the
`dgvinc/edge-SDK` BLE protocol as its own SPM package
(`EdgeSDK-Swift`), then have `BioFeedbackKit-EdgeBLE` depend on it
and conform an `EdgeGlassesDevice` to `FeedbackDevice` on top. This
keeps the BLE wire protocol layer reusable for non-BioFeedbackKit
consumers.

**Note for the next session:** `EdgeSDK-Swift` and
`BioFeedbackKit-EdgeBLE` are both new repos that come *after* this
proposal lands. They're not part of this PR.

---

## 9. Approval Checklist

- [ ] Approve scope (one library proposal, six new files in core, one new dependency)
- [ ] Approve the protocol surface in §4
- [ ] Approve the pull model with health-channel + internal recovery
- [ ] Approve `swift-async-algorithms` dependency
- [ ] Approve test strategy (~34 tests)
- [ ] Approve the per-device-adapter-as-separate-package architecture
- [ ] Acknowledge: Polar adapter, Edge BLE library, Edge adapter, app target are all separate repos created in subsequent sessions
- [ ] Approve writing tests BEFORE implementation
