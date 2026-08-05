# Design Proposal: iOS Connect & Pairing Flow

**Status:** APPROVED  
**Date:** 2026-04-20  
**Scope:** NarbisKit + NarbisUI + iOS app shell + watchOS companion relay  

---

## Problem

The iOS app currently hardcodes `SimulationDevice` as its input. To become a working product, it needs:

1. Discover and pair BLE heart rate monitors (Polar H10, Peloton strap, any standard BLE HR service)
2. Surface Apple Watch as an input device (via HealthKit on iPhone — no WatchConnectivity needed)
3. Discover and pair Edge glasses as output device
4. Let the user select one input + optionally one output before starting a session
5. Gracefully fall back to simulation for development/demo

---

## Input Device Categories

| Source | Transport | Discovery | Pairing |
|--------|-----------|-----------|---------|
| Generic BLE HR strap (Polar, Peloton, Wahoo, etc.) | `.bluetoothLE` | CoreBluetooth scan for `0x180D` (Heart Rate Service) | System BLE pairing or bond-free |
| Apple Watch (paired to this iPhone) | `.watchConnectivity` | `WCSession.isSupported()` + `.isPaired` | No user pairing — system-level |
| Simulation | `.inProcess` | Always available | None |

### Apple Watch as iOS Input Device (WatchConnectivity Relay)

The Apple Watch acts as a **first-class biofeedback input** with the same responsiveness as a BLE HR strap (~50-100ms latency). This is achieved via a lightweight relay mode on the watch companion:

1. iOS app activates `WCSession` and sends a "start relay" message
2. Watch companion starts an `HKWorkoutSession` (`.mindAndBody`) to unlock real-time heartbeat data
3. Watch streams each RR interval to iOS via `WCSession.sendMessage(_:replyHandler:)` as it arrives
4. iOS wraps incoming messages as `BioSample` and feeds the standard `BiofeedbackDevice` protocol
5. Watch also **writes HRV data to HealthKit** (see HealthKit Write-Back below)

The user experience is identical to selecting a Polar strap — same latency, same fidelity, no perceptible difference. The watch still runs its own sovereign sessions when used standalone; relay mode is an additional capability activated only when the iOS app requests it.

#### HealthKit Write-Back (HRV Data Contribution)

During relay mode (and standalone sessions), the watch app must **write computed HRV data back to HealthKit**, not just read HR. This ensures Narbis appears as a data contributor in Health.app:

- **Heart Rate Variability (SDNN):** `HKQuantityType(.heartRateVariabilitySDNN)` — write periodically (e.g., per-minute SDNN from the coherence engine's RR buffer)
- **Workout metadata:** The `HKWorkoutSession` + `HKLiveWorkoutBuilder` already writes HR samples; ensure `builder.endCollection()` and `builder.finishWorkout()` are called so the workout appears in Health
- **Authorization:** Request `.write` for `heartRateVariabilitySDNN` in addition to existing `.read` permissions

This is a gap in the current implementation — we read HR data but never write HRV back. Both standalone watch sessions and relay-mode sessions should contribute.

---

## Output Device Categories

| Sink | Transport | Discovery | Pairing |
|------|-----------|-----------|---------|
| Edge glasses | `.bluetoothLE` | CoreBluetooth scan for Edge service UUID | BLE pairing |
| Screen-only | N/A | Always available | None |

---

## Architecture

### New Types (NarbisKit)

```swift
/// Represents a discovered device the user can select.
public struct DiscoveredDevice: Identifiable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let transport: ConnectionTransport
    public let role: DeviceRole  // .input, .output, .dual
    public let rssi: Int?        // BLE signal strength (nil for non-BLE)
}

public enum DeviceRole: String, Sendable, Codable {
    case input, output, dual
}

/// Persisted device preference for "Always use this device" flow.
public struct RememberedDevices: Codable, Sendable {
    public var input: DiscoveredDevice?
    public var output: DiscoveredDevice?
}

/// Manages BLE scanning + HealthKit availability for device selection.
@Observable @MainActor
public final class DeviceConnectViewModel {
    // Published state
    public private(set) var discoveredInputs: [DiscoveredDevice] = []
    public private(set) var discoveredOutputs: [DiscoveredDevice] = []
    public private(set) var selectedInput: DiscoveredDevice?
    public private(set) var selectedOutput: DiscoveredDevice?
    public private(set) var inputConnectionState: ConnectionState = .disconnected
    public private(set) var outputConnectionState: ConnectionState = .disconnected
    public private(set) var isScanning: Bool = false
    
    // Always-available options
    public var appleWatchAvailable: Bool  // true if HealthKit authorized + watch paired
    public var simulationAvailable: Bool  // true in dev builds or settings toggle
    
    // Remembered device preference
    public var alwaysUseThisDevice: Bool  // toggle in connect UI
    public var rememberedDevices: RememberedDevices?  // persisted in UserDefaults
    
    // Actions
    public func startScan()
    public func stopScan()
    public func selectInput(_ device: DiscoveredDevice)
    public func selectOutput(_ device: DiscoveredDevice)
    public func connect() async throws -> (input: any BiofeedbackDevice, output: (any FeedbackDevice)?)
    public func clearRemembered()  // "Change Device" in Settings
    
    /// Attempts auto-connect to remembered devices.
    /// Returns nil if no remembered devices or connection fails within timeout.
    public func autoConnect(timeout: Duration = .seconds(10)) async -> (input: any BiofeedbackDevice, output: (any FeedbackDevice)?)?
}
```

### New Types (App Layer — CoreBluetooth + WatchConnectivity)

```swift
/// Scans for BLE peripherals advertising Heart Rate Service (0x180D).
actor BLEHeartRateScanner {
    func discoveries() -> AsyncStream<DiscoveredDevice>
    func stop()
}

/// Scans for BLE peripherals advertising Edge glasses service UUID.
actor BLEEdgeScanner {
    func discoveries() -> AsyncStream<DiscoveredDevice>
    func stop()
}

/// Apple Watch as iOS input via WatchConnectivity relay.
/// Sub-second latency (~50-100ms). Activates relay mode on companion.
actor WatchRelayDevice: BiofeedbackDevice {
    // Transport: .watchConnectivity
    // connect() → sends "startRelay" to watch companion
    // sampleStream() → receives RR intervals via WCSession messages
    // disconnect() → sends "stopRelay", watch ends workout session
}
```

### Watch Companion Additions (watchOS app layer)

```swift
/// Lightweight relay mode activated by iOS app request.
/// Starts HKWorkoutSession, streams RR to iOS, writes HRV to HealthKit.
actor RelayCoordinator {
    func handleRelayRequest() async throws
    func stopRelay() async
    
    // Writes SDNN to HealthKit every 60s during relay
    private func writeHRVSample(sdnn: Double, at date: Date) async throws
}
```

### Factory Evolution

The current `InputDeviceFactory` / `OutputDeviceFactory` closures remain unchanged — they're still how `TrainingViewModel.start(...)` receives its devices. The new `DeviceConnectViewModel` produces these factories after the user selects and connects:

```swift
// After user selects devices on the Connect screen:
let inputFactory: InputDeviceFactory = { selectedPolarDevice }
let outputFactory: OutputDeviceFactory = { selectedEdgeDevice }

// Passed to TrainingView → TrainingViewModel.start(...)
```

---

## UI Flow

### First Use (no remembered devices)

```
HomeView
  └─ "Start Training" tap
       └─ ConnectView (new)
            ├─ Input Section
            │   ├─ [Apple Watch] (if available — shown first, no scan needed)
            │   ├─ [Scanning for BLE HR monitors...]
            │   │   ├─ "Polar H10 A1B2" (rssi: -45)
            │   │   ├─ "Peloton HR" (rssi: -62)
            │   │   └─ ...
            │   └─ [Simulation] (dev mode)
            │
            ├─ Output Section
            │   ├─ [Scanning for Edge glasses...]
            │   │   └─ "Narbis Edge" (rssi: -50)
            │   └─ [Screen Only] (always available)
            │
            ├─ [ ] Always use this device (toggle)
            │
            └─ "Connect & Start" button
                 ├─ Connects selected devices (shows connection state)
                 └─ On success → TrainingView with live factories
```

### Returning Use (remembered device set)

If "Always use this device" was toggled on, `HomeView` → "Start Training" skips the ConnectView entirely and auto-connects to the remembered input/output pair. If connection fails (device not found within ~10s), falls back to ConnectView with an error banner.

A "Change Device" option in Settings clears the remembered preference and returns to scan flow.

### Apple Watch Presentation

The Apple Watch input is **not** discovered via BLE scan — it appears as a permanent top-level option whenever HealthKit reports a paired watch. This distinguishes it visually from scanning-dependent BLE devices:

```
┌─────────────────────────────┐
│  INPUT DEVICE               │
│                             │
│  ● Apple Watch  ✓ Ready     │  ← First-class, no scan needed
│                             │
│  ─ Bluetooth Devices ───────│
│  ○ Polar H10       -45 dBm │  ← From BLE scan
│  ○ Peloton HR      -62 dBm │
│                             │
│  ─ Development ─────────────│
│  ○ Simulation               │  ← Dev mode only
└─────────────────────────────┘
```

---

## WatchConnectivity Relay Strategy

### iOS Side (`WatchRelayDevice`)

```
WCSession.sendMessage("startRelay") → watch
  ↓
Watch starts HKWorkoutSession + heartbeat stream
  ↓
Watch sends each RR interval via WCSession.sendMessage()  (~50-100ms)
  ↓
iOS WCSessionDelegate.session(_:didReceiveMessage:) 
  ↓
WatchRelayDevice yields BioSample on its AsyncThrowingStream
  ↓
Standard BiofeedbackDevice pipeline (same as Polar/any BLE strap)
```

### Watch Side (`RelayCoordinator`)

When iOS requests relay mode:
1. Start `HKWorkoutSession` (activity: `.mindAndBody`, location: `.indoor`)
2. Start `HKLiveWorkoutBuilder` — this writes the workout + HR to HealthKit automatically
3. Start `HKHeartbeatSeriesQuery` for beat-to-beat RR intervals
4. On each RR interval: `WCSession.default.sendMessage(["rr": rrMs, "ts": timestamp])`
5. Every 60 seconds: compute SDNN from accumulated RR buffer, write `HKQuantitySample` for `heartRateVariabilitySDNN`
6. On stop: `builder.endCollection()` → `builder.finishWorkout()` → end workout session

### HealthKit Write Permissions Required

Add `.write` authorization for:
- `HKQuantityType(.heartRateVariabilitySDNN)` — periodic SDNN samples
- `HKWorkoutType` — already handled by `HKLiveWorkoutBuilder`
- `HKQuantityType(.heartRate)` — already handled by workout builder

This applies to **both relay mode and standalone watch sessions** — the current watch app has the same gap (reads but doesn't write HRV).

### Sovereignty Preserved

| Mode | Watch behavior | iOS behavior |
|------|---------------|--------------|
| Standalone watch session | Full pipeline: HR → coherence → haptics | Not involved |
| iOS relay mode | Relay: HR → WatchConnectivity + HealthKit write | Full pipeline: HR → coherence → Edge glasses |
| iOS with BLE strap | Not involved | Full pipeline: HR → coherence → Edge glasses |

The watch never *depends* on the phone. Relay mode is an additional capability, not a requirement.

---

## Edge Output Strategy

The `EdgeSDK-Swift` + `BioFeedbackKit-EdgeBLE` packages provide the protocol bridge. What's missing is the **production CoreBluetooth adapter** that actually talks to hardware. For now:

1. **SimulatedEdgeDevice** — routes through the full `FeedbackDevice.render()` → `EdgeGlassesDevice` → byte encoding path, using a mock BLE peripheral that validates protocol encoding without hardware. The existing `GlassesSimulator` view in NarbisUI visualizes the output.
2. **CoreBluetoothEdgeAdapter** (deferred until hardware arrives) — discovers, connects, and wraps a real `CBPeripheral`

This validates the entire output pipeline (coherence → FeedbackUpdate → TintMapper → 0xA2 brightness bytes) end-to-end without needing physical glasses.

---

## Implementation Plan

### Phase 1: DiscoveredDevice model + DeviceConnectViewModel (NarbisKit)
- TDD: test discovered device list management, selection logic, state transitions
- Remembered device persistence + auto-connect logic
- Protocol-based scanner abstraction (no CoreBluetooth yet)

### Phase 2: ConnectView (NarbisUI)
- SwiftUI view driven by DeviceConnectViewModel
- Sections for input/output with selection + connection state
- "Always use this device" toggle
- "Change Device" option in SettingsView

### Phase 3: WatchConnectivity Relay (watch companion + iOS)
- Add `.watchConnectivity` case to `ConnectionTransport` enum in BioFeedbackKit
- `WatchRelayDevice: BiofeedbackDevice` on iOS — receives RR via WCSession messages
- `RelayCoordinator` on watch — starts workout, streams RR, writes HRV to HealthKit
- Message format: `["rr": Double, "ts": TimeInterval]` (milliseconds, epoch)
- TDD: mock WCSession, test message encoding/decoding, test HRV write cadence

### Phase 4: HealthKit HRV Write-Back (watch app — both modes)
- Write `heartRateVariabilitySDNN` every 60s during active sessions
- Request `.write` authorization for HRV quantity type
- Ensure `HKLiveWorkoutBuilder` finishes cleanly so workouts appear in Health
- Applies to standalone watch sessions too (existing gap)

### Phase 5: BLE Scanner implementations (iOS app layer)
- `BLEHeartRateScanner` — CoreBluetooth scan for `0x180D`
- `BLEEdgeScanner` — CoreBluetooth scan for Edge UUID
- Inject via protocol so NarbisKit stays platform-clean

### Phase 6: Integration
- Wire ConnectView into HomeView → Training flow
- Replace hardcoded SimulationDevice with user-selected device
- Auto-connect path for remembered devices
- Preserve simulation as dev toggle in Settings

---

## Resolved Questions

1. **Apple Watch as first-class input:** Uses WatchConnectivity relay with ~50-100ms latency (same as BLE strap). No compromise, no latency notes in UX.

2. **One input at a time** for v1. No multi-device cross-check.

3. **"Always use this device" toggle** — persists selection in UserDefaults. On next "Start Training", auto-connects without showing scan. Falls back to ConnectView on failure. "Change Device" in Settings clears preference.

4. **Edge simulation routes through full `FeedbackDevice.render()` path** — validates protocol encoding end-to-end. `GlassesSimulator` view visualizes the byte-level output.

5. **HealthKit HRV write-back:** Both relay mode and standalone watch sessions must write `heartRateVariabilitySDNN` samples to HealthKit. Current implementation only reads — this is a gap to fix.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| WatchConnectivity unreachable (watch out of range, powered off) | `WCSession.isReachable` check before connect; clear error state in UI; user falls back to BLE strap |
| Watch companion not installed | Check `WCSession.isWatchAppInstalled`; prompt user to install from iOS |
| WCSession message delivery during background | Use `transferUserInfo` as fallback for queued delivery; but primary path is foreground `sendMessage` |
| CoreBluetooth background restrictions | Request `bluetooth-central` background mode; handle state restoration |
| Edge glasses unavailable for testing | Full protocol-level simulation via EdgeSDK-Swift; defer hardware integration |
| BLE scan drains battery | Auto-stop scan after 30s or on selection; don't scan in background |
| HealthKit write permission denied | Graceful degradation — session still works, HRV just isn't written. Note in settings. |

---

## Success Criteria

- [ ] User can discover and select a BLE HR monitor from scan results
- [ ] User can select Apple Watch as input — first-class, sub-second latency via WatchConnectivity
- [ ] User can select Edge glasses as output (when available)
- [ ] Selected devices connect with visible state feedback
- [ ] "Always use this device" persists choice and auto-connects on next session
- [ ] Training session uses live device data (not simulation) when connected
- [ ] Watch writes HRV (SDNN) to HealthKit during both relay and standalone sessions
- [ ] Narbis appears as a data contributor in Health.app
- [ ] Simulation remains available as fallback
- [ ] All new code has tests (scanner protocols, ViewModel state, WCSession relay, HRV write)
- [ ] Zero compiler warnings, Swift 6 strict concurrency compliant
