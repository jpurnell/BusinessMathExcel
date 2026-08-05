# Design Proposal: Device Protocol Refactor v1

**Status:** APPROVED 2026-04-08 — moving to RED
**Date:** 2026-04-08

---

## 1. Objective

Pull the shared lifecycle of a connected hardware device — name,
transport identification, connection state stream, health stream,
reconnection policy, connect/disconnect — out of `BiofeedbackDevice`
(input) and `FeedbackDevice` (output) into a base `Device` protocol
that both refine. This eliminates duplication, lets a single physical
device (Apple Watch) conform to both subprotocols with a single
connection lifecycle, and makes connection-related concerns
first-class for app UIs (Connect screens, status indicators,
troubleshooting flows).

This is a small but architecturally important refactor that should
land **before** any concrete adapter packages ship on top of the
existing protocols.

---

## 2. Scope

### In scope
- New `Device` base protocol in `BioFeedbackKit/Devices/`
- `ConnectionTransport` enum (BLE, BLE classic, WiFi, USB, HealthKit, in-process, other)
- `ConnectionState` enum (disconnected, connecting, connected, reconnecting, failed)
- `ReconnectionPolicy` enum (delegated, standardRetry, none)
- `DeviceHealth` enum — renamed from `FeedbackHealth`, applies to both input and output
- `BiofeedbackDevice` refines `Device`, keeps `sampleStream()`
- `FeedbackDevice` refines `Device`, keeps `capabilities` + `render(stream:)`
- `MockDevice` (input) updated to conform to refined protocol
- `MockFeedbackDevice` (output) updated to conform to refined protocol
- Existing 263 tests must stay green

### NOT in scope
- A standard-retry implementation (the `.standardRetry` policy is declarative for now; the actual retry loop helper can ship later when a real consumer needs it)
- Reconnection orchestration in the library — the policy field tells callers what to expect; the actual reconnection happens in the adapter or in app code
- Any concrete adapter packages (Polar, EdgeBLE, HealthKit) — they come after this lands

---

## 3. The new shape

```swift
// MARK: - Base device protocol

public protocol Device: Sendable {
    /// Human-readable name (e.g. "Polar H10", "Edge Glasses").
    var name: String { get }

    /// What kind of transport this device uses. Lets app UIs render
    /// generic device lists with the right icons / labels.
    var transport: ConnectionTransport { get }

    /// Whether the device is currently connected and ready.
    var isConnected: Bool { get async }

    /// Stream of connection-lifecycle changes. Apps subscribe to
    /// surface "Reconnecting…" indicators in real time without
    /// polling `isConnected`.
    var connectionState: AsyncStream<ConnectionState> { get }

    /// Stream of soft-error / status events for in-session
    /// diagnostics. Devices push these as transient issues happen
    /// without throwing — only unrecoverable failures throw from
    /// stream/render methods.
    var health: AsyncStream<DeviceHealth> { get }

    /// How this device handles reconnection. Adapters with built-in
    /// auto-reconnect (like Polar) use `.delegated`. Adapters that
    /// need a manual retry loop use `.standardRetry(...)`. No-retry
    /// adapters use `.none`.
    var reconnectionPolicy: ReconnectionPolicy { get }

    /// Establishes a connection. Updates `connectionState` accordingly.
    func connect() async throws

    /// Disconnects from the device.
    func disconnect() async throws
}

// MARK: - Transport / state / policy / health enums

public enum ConnectionTransport: Sendable, Codable, Equatable {
    case bluetoothLE
    case bluetoothClassic
    case wifi
    case usb
    case healthKit       // process-internal, no transport
    case inProcess       // mocks, in-app simulators
    case other(String)
}

public enum ConnectionState: Sendable, Codable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)
}

public enum ReconnectionPolicy: Sendable, Codable, Equatable {
    /// Underlying SDK manages reconnection internally. Adapter just
    /// observes and forwards state via `connectionState`.
    case delegated
    /// Library applies an exponential-backoff retry loop with the
    /// given parameters. The actual retry helper is a future addition;
    /// for now this is declarative.
    case standardRetry(maxAttempts: Int, baseDelay: Duration)
    /// No reconnection. Caller handles drops manually.
    case none
}

public enum DeviceHealth: Sendable, Codable, Equatable {
    /// Device is operating normally.
    case nominal
    /// Partial functionality unavailable. `reason` is human-readable.
    case degraded(reason: String)
    /// Transient failure recovery in progress.
    case recovering(attempt: Int)
    /// Falling behind input/output stream; dropping samples to catch up.
    case dropping(samples: Int)
}

// MARK: - Refined input / output protocols

public protocol BiofeedbackDevice: Device {
    /// Returns an async stream of bio samples from the device.
    func sampleStream() async throws -> AsyncThrowingStream<BioSample, any Error>
}

public protocol FeedbackDevice: Device {
    /// What modalities this device can render.
    var capabilities: FeedbackCapabilities { get }

    /// Renders an async stream of feedback updates.
    func render<S: AsyncSequence>(_ updates: S) async throws
        where S.Element == FeedbackUpdate, S: Sendable
}
```

`FeedbackHealth` is **renamed to `DeviceHealth`** since it now applies
to both input and output devices. The cases stay the same; only the
type name changes. This is a breaking rename for the day-old
`FeedbackDevice` work but no real consumers exist yet.

---

## 4. Migration of existing types

| Existing type | What changes |
|---|---|
| `BiofeedbackDevice` | Now refines `Device`. Removes `var name: String { get }`, `var isConnected: Bool { get }`, `connect()`, `disconnect()` from its own surface (inherited from `Device`). Adds `transport`, `connectionState`, `health`, `reconnectionPolicy` via the base. |
| `FeedbackDevice` | Now refines `Device`. Removes `name`, `isConnected`, `connect()`, `disconnect()`, `health` from its own surface. Keeps `capabilities` + `render`. |
| `FeedbackHealth` | Renamed to `DeviceHealth`. Cases unchanged. |
| `MockDevice` (input) | Adds `transport: .inProcess`, `connectionState` stream, `health` stream, `reconnectionPolicy: .none`. |
| `MockFeedbackDevice` (output) | Adds `transport: .inProcess`, `connectionState` stream, `reconnectionPolicy: .none`. `health` stream stays (already had it). Drops `FeedbackHealth` references in favor of `DeviceHealth`. |

---

## 5. Test impact

Estimated changes:
- `DeviceTests.swift` (existing) — 5 tests touched to add transport/state assertions
- `FeedbackDeviceTests.swift` (existing) — ~3 tests touched to use `DeviceHealth` instead of `FeedbackHealth`
- New tests (~12) for the new types:
  - `ConnectionTransport` Codable roundtrip (1)
  - `ConnectionState` Codable for all cases including associated values (3)
  - `ReconnectionPolicy` Codable for all cases (3)
  - `DeviceHealth` Codable for all cases (4)
  - `MockDevice` exposes `transport == .inProcess` (1)
  - `MockDevice` `connectionState` stream emits `.connected` after connect (1)
  - `MockDevice` `connectionState` stream emits `.disconnected` after disconnect (1)
  - `MockFeedbackDevice` parallel tests for the new properties (3)

Net: ~263 → ~275 tests, no test regressions.

---

## 6. Files to add / modify

| File | Change |
|---|---|
| `Sources/BioFeedbackKit/Devices/Device.swift` | NEW — base protocol |
| `Sources/BioFeedbackKit/Devices/ConnectionTransport.swift` | NEW |
| `Sources/BioFeedbackKit/Devices/ConnectionState.swift` | NEW |
| `Sources/BioFeedbackKit/Devices/ReconnectionPolicy.swift` | NEW |
| `Sources/BioFeedbackKit/Devices/DeviceHealth.swift` | NEW (replaces FeedbackHealth.swift) |
| `Sources/BioFeedbackKit/Devices/BiofeedbackDevice.swift` | Refine Device |
| `Sources/BioFeedbackKit/Devices/MockDevice.swift` | Add new properties |
| `Sources/BioFeedbackKit/Feedback/FeedbackDevice.swift` | Refine Device |
| `Sources/BioFeedbackKit/Feedback/FeedbackHealth.swift` | DELETE — replaced by DeviceHealth |
| `Sources/BioFeedbackKit/Feedback/MockFeedbackDevice.swift` | Add new properties, switch FeedbackHealth → DeviceHealth |
| `Tests/BioFeedbackKitTests/DeviceTests.swift` | Add tests for new properties |
| `Tests/BioFeedbackKitTests/FeedbackDeviceTests.swift` | Switch FeedbackHealth → DeviceHealth in existing tests |
| `Tests/BioFeedbackKitTests/DeviceProtocolTests.swift` | NEW — tests for the new types |

---

## 7. Constraints

- All existing 263 tests must stay green
- Cross-platform — no Darwin-only APIs
- No `String(format:)`, `try!`, `as!`, `fatalError`, force unwraps
- All new types `Sendable`, `Equatable`, and `Codable` where appropriate
- Swift 6 strict concurrency throughout
