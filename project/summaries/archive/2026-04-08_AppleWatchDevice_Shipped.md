# Session Summary: AppleWatchDevice — First Dual-Conformance Adapter

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-04-08 (late) | Phase 3 | COMPLETED — third SPM package shipped |

## 1. Core Objective

Ship `BioFeedbackKit-HealthKit` as the third sibling SPM package and
the **first dual-conformance device adapter** in the workspace.
`AppleWatchDevice` conforms to BOTH `BiofeedbackDevice` (input via
HealthKit heartbeat-series → raw RR) AND `FeedbackDevice` (output via
display-state vending + haptic transitions) on top of a single
HealthKit + watchOS connection lifecycle.

This validates the architectural intent of `Device` as a base protocol
with two refinements: a single physical device can act as both input
and output with one shared lifecycle.

## 2. Design Decisions

- **Decision:** Single `BioFeedbackKit-HealthKit` package covers both input and output, not two separate packages.
- **Rationale:** Apple Watch is one device with one connection. Splitting into separate packages would force the consuming app to manage two adapter instances pointing at the same hardware. Combined keeps the lifecycle in one place.

- **Decision:** `HealthStore` protocol abstraction with `MockHealthStore` test fake.
- **Rationale:** Mirrors the `PolarApi` pattern from `BioFeedbackKit-Polar`. Bridge layer is fully testable on macOS without HealthKit, WatchKit, or real watch hardware. Surfaces only what `AppleWatchDevice` needs — `RRSample`, not `HKHeartbeatSeriesSample`.

- **Decision:** `displayState: AsyncStream<AppleWatchDisplayState>` for view binding instead of Combine, an `@Observable` reference, or a delegate.
- **Rationale:** Most portable. Consistent with the rest of the library. The watchOS view consumes via `.task { for await state in device.displayState { ... } }`. No Combine dependency, no shared mutable reference, no SwiftUI imports in the adapter.

- **Decision:** Live-workout semantics required for HR streaming.
- **Rationale:** It's the only path for low-latency HR data on Apple Watch. Background queries don't deliver fast enough for biofeedback.

- **Decision:** Lazy `requestAuthorization()` from inside `connect()`, not eagerly at construction.
- **Rationale:** The user gets the permission prompt when they actually start a session, not when the app launches. Better UX.

- **Decision:** Watch device name is extracted from `HKDevice` metadata on the **first** received heartbeat sample. The name is `"Apple Watch"` until then. Subsequent samples don't overwrite.
- **Rationale:** User asked for the watch name on screen. HealthKit doesn't expose it directly except via per-sample `HKDevice` metadata. The "first sample wins" rule is simple and correct — the watch's name doesn't change mid-session.

- **Decision:** Phase-transition haptics fire on **kind change** (`.idle → .inhale`, `.inhale → .exhale`), NOT on progress changes within the same phase.
- **Rationale:** A breath cycle has 4 transitions but ~50 progress updates. Haptics on every progress update would buzz constantly. Implemented via a private `BreathingPhaseKind` enum that strips associated values.

- **Decision:** Library refactor — `Device.name` changed from `var name: String { get }` to `var name: String { get async }`.
- **Rationale:** Required so actor-based adapters can vend a mutable stored name. Polar uses an immutable nonisolated `let`; AppleWatchDevice needs the name to update when HealthKit metadata arrives. The async getter is the clean Swift 6 idiom.

- **Decision:** `HKHealthStoreAdapter` (real HealthKit wrapper) and `WKInterfaceDeviceHapticPlayer` (real watchOS haptic) are deferred to a follow-up session.
- **Rationale:** Same pattern as Polar — bridge layer ships fully tested on macOS without platform-specific dependencies; production wrappers ship later with hardware integration tests.

- **Decision:** `MockHealthStore` uses `NSLock.withLock { }` instead of `lock()` / `unlock()`.
- **Rationale:** Swift 6 strict concurrency makes `unlock()` unavailable from async contexts. `withLock` is the safe pattern. Caught at first GREEN attempt.

## 3. Work Completed

### Design Proposal
- [x] `BioFeedbackKit-HealthKit/project/plans/completed/2026-04-08_AppleWatchDevice-v1.md` (drafted, marked APPROVED, then SHIPPED with implementation notes)

### New SPM package: BioFeedbackKit-HealthKit

**Files created:**
- `Package.swift` (depends on BioFeedbackKit only — no HealthKit dependency yet)
- `Sources/BioFeedbackKitHealthKit/HealthStore.swift` (protocol + RRSample value type)
- `Sources/BioFeedbackKitHealthKit/HapticPlayer.swift` (protocol + BioFeedbackHaptic enum)
- `Sources/BioFeedbackKitHealthKit/AppleWatchError.swift` (errors)
- `Sources/BioFeedbackKitHealthKit/AppleWatchDisplayState.swift` (view-binding state, no SwiftUI types)
- `Sources/BioFeedbackKitHealthKit/AppleWatchDevice.swift` (the dual-conformance actor)
- `Tests/BioFeedbackKitHealthKitTests/MockHealthStore.swift` (test fake using `NSLock.withLock`)
- `Tests/BioFeedbackKitHealthKitTests/MockHapticPlayer.swift` (records every haptic)
- `Tests/BioFeedbackKitHealthKitTests/AppleWatchDeviceTests.swift` (24 tests)

### BioFeedbackKit core refactor (one small change)

- `Sources/BioFeedbackKit/Devices/Device.swift` — `var name: String { get async }` (was sync)
- All 278 existing core tests stayed green
- All 22 Polar tests stayed green (PolarDevice uses `nonisolated let name`, which still satisfies the async getter)

## 4. Mandatory Quality Gate

| Check | Result |
| :--- | :--- |
| `swift build` (BioFeedbackKit) | ✅ zero warnings |
| `swift test` (BioFeedbackKit) | ✅ **278 / 278 passing** |
| `swift build` (BioFeedbackKit-Polar) | ✅ zero warnings |
| `swift test` (BioFeedbackKit-Polar) | ✅ **22 / 22 passing** |
| `swift build` (BioFeedbackKit-HealthKit) | ✅ zero warnings |
| `swift test` (BioFeedbackKit-HealthKit) | ✅ **24 / 24 passing** |
| Safety (no `String(format:)`, `try!`, `as!`, `fatalError`, force unwraps) | ✅ |
| Doc coverage (DocC on all public symbols) | ✅ |

**Workspace total:** 324 / 324 tests passing across 3 SPM packages.

## 5. Project State Updates

- [x] `BioFeedbackKit-HealthKit/project/plans/completed/2026-04-08_AppleWatchDevice-v1.md`
- [x] `master_plan.md` — added Polar + HealthKit packages to "What's Working" with the dual-conformance milestone, bumped test count to 324/324, refreshed timestamp

## 6. Next Session Handover

### Immediate Starting Point

Three out of four planned device adapter packages are scoped:

| Package | State |
|---|---|
| BioFeedbackKit-Polar | ✅ bridge shipped |
| BioFeedbackKit-HealthKit | ✅ bridge shipped (this session) |
| BioFeedbackKit-EdgeBLE | ⏳ next |
| (the actual narbis-edge-ios app) | ⏳ |

The next move is the Edge glasses adapter, which is a 2-step build:

1. **`EdgeSDK-Swift`** — clean Swift port of the dgvinc/edge-SDK Python API for the glasses BLE protocol. Stand-alone SPM package, depends only on CoreBluetooth (or our own protocol abstraction over CoreBluetooth for testability). Implements the v5 §5.2 byte protocol (`0xA1` strobe, `0xA2` brightness, `0xA3` 4-phase breathing, `0xA4` duration, `0xA5` static, `0xA6` resume, `0xA7` sleep, plus single-byte direct opacity). High-level API mirrors the Python SDK's clean asyncio interface.
2. **`BioFeedbackKit-EdgeBLE`** — adapter package that depends on BioFeedbackKit + EdgeSDK-Swift. Conforms `EdgeGlassesDevice: FeedbackDevice` on top of EdgeSDK-Swift's session API.

The user said this should be done as two repos: a clean SDK port plus the BioFeedbackKit adapter on top.

### Pending Tasks (in order)

1. **`EdgeSDK-Swift` package** — clean Swift port of the Python SDK API. Bridge layer (protocol abstraction over CoreBluetooth + mock) ships first; real CoreBluetooth wrapper deferred until hardware is in hand.
2. **`BioFeedbackKit-EdgeBLE` package** — adapter conforming `EdgeGlassesDevice: FeedbackDevice` on top of EdgeSDK-Swift.
3. **Hardware-wrapper follow-ups** — `PolarBleApiAdapter`, `HKHealthStoreAdapter`, `WKInterfaceDeviceHapticPlayer`, EdgeSDK-Swift's CoreBluetooth wrapper. All bottlenecked on real hardware in hand.
4. **`narbis-edge-ios`** — the actual iOS app target depending on all adapter packages.

### Blockers

None for the bridge layers. Production hardware wrappers are bottlenecked on real devices.

### Context Loss Warning

- **`Device.name` is now `{ get async }`.** Don't switch back to sync. Actor-based adapters (AppleWatchDevice) need it.
- **`AppleWatchDevice` is the first dual-conformance adapter.** It conforms to BOTH `BiofeedbackDevice` AND `FeedbackDevice`. One `connect()` provisions both directions; one `disconnect()` tears them down. Don't refactor to two separate types.
- **`MockHealthStore` uses `NSLock.withLock { }`**, not raw `lock()` / `unlock()`. Swift 6 makes `unlock()` unavailable from async. Same fix applies to any new mock that uses NSLock from async methods.
- **HealthKit production wrapper is deferred.** The bridge ships fully testable on macOS. Don't try to add HealthKit imports to the bridge — gate them behind `#if canImport(HealthKit)` if/when added.
- **Watch name discovery is "first non-nil deviceName wins."** A `nameDetectedFromSample` flag prevents overwriting. Don't relax this — the watch's name doesn't change mid-session and overwriting would cause the UI to flicker.
- **Phase-transition haptics use the `BreathingPhaseKind` private enum** to strip associated values. Don't compare `BreathingPhase` directly — `inhale(0.1) != inhale(0.5)` and you'd fire a haptic on every progress update.
- **`AppleWatchDisplayState` carries data only**, no SwiftUI types. The watchOS view is responsible for binding this to its own observable state.

---

## Metrics

| Metric | Start of session | After session |
|--------|-----------------|---------------|
| BioFeedbackKit core tests | 278 | 278 (1 protocol refactor, no test count change) |
| BioFeedbackKit-Polar tests | 22 | 22 |
| BioFeedbackKit-HealthKit tests | 0 | **24** |
| Workspace total tests | 300 | **324** |
| SPM packages | 2 | **3** |
| Concrete device adapters | 1 (Polar, input only) | **2** (+ AppleWatch dual) |
| Dual-conformance adapters | 0 | **1** |

## Layer Status After This Session

| Layer | Status |
|---|---|
| BioFeedbackKit core (everything) | ✅ |
| BioFeedbackKit-Polar (PolarDevice covering H10/H9/OH1/Verity Sense) | ✅ bridge shipped |
| **BioFeedbackKit-HealthKit (AppleWatchDevice dual-conformance)** | ✅ **bridge shipped this session** |
| BioFeedbackKit-Polar real SDK wrapper | ⏳ hardware-bottlenecked |
| BioFeedbackKit-HealthKit real wrappers | ⏳ hardware-bottlenecked |
| **EdgeSDK-Swift (clean port of Python SDK API)** | ⏳ **next session** |
| BioFeedbackKit-EdgeBLE adapter | ⏳ next |
| narbis-edge-ios app target | ⏳ |
