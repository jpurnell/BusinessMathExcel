# Session Summary: ConnectView Wiring + Cross-Platform Portability

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-04-23 | ConnectView wiring + portability hardening | COMPLETED |

## 1. Core Objective

Fix the broken ConnectView-to-TrainingView device wiring so BLE devices can flow through to sessions, then audit and improve cross-platform portability for the Android port.

## 2. Design Decisions

- **PeripheralRegistry bridges value types to CBPeripheral.** `DiscoveredDevice` is Codable (no reference types), but device construction needs a live `CBPeripheral`. The registry maps UUIDs to opaque builder closures — scanners register closures that capture the peripheral, `deviceBuilder` looks them up at connect time. Lives in NarbisKit (no CoreBluetooth dependency).
- **SessionPersistence protocol over SwiftData.** Extracted from `SessionStore`'s 7 methods. SwiftData implementation stays as one conformer; `InMemorySessionStore` is the portable alternative for tests and Android bootstrap.
- **Firebase confirmed as cross-platform backend.** Not CloudKit (Apple-only). `FirebaseSessionStore: SessionPersistence` will sync `SessionSummary` (already Codable) to Firestore when implemented.
- **SessionOrchestrator accepts any BiofeedbackDevice.** Removed hardcoded `AppleWatchDevice` dependency. Now takes `inputDevice: any BiofeedbackDevice` + `outputDevice: (any FeedbackDevice)?`. Removed `import BioFeedbackKitHealthKit` from NarbisKit entirely.
- **Audio abstraction is not worth it.** Config is portable (`AudioFeedbackConfig`), engine is deeply AVFoundation. Android gets its own engine using Oboe reading the same config. No shared protocol needed.

## 3. Work Completed

### ConnectView Wiring (commit 7514b88)
- `PeripheralRegistry` — register/deregister/build input and output device builders
- `DeviceConnectViewModel.autoConnect(timeout:)` — skips ConnectView for remembered devices
- HomeView: `deviceBuilder` expanded for `.bluetoothLE` via registry lookup
- HomeView: `connectViewModel` lifted to `@State` (persists across sheet presentations)
- HomeView: SettingsView receives `connectViewModel` (fixes "Change Device" button)
- HomeView: sheet-to-fullScreenCover 300ms delay (fixes transition artifacts)
- 14 new tests (10 PeripheralRegistry + 2 BLE wiring + 2 autoConnect)

### SessionOrchestrator Portability (commit 657cbe6)
- `device: AppleWatchDevice` → `inputDevice: any BiofeedbackDevice & Sendable` + `outputDevice: (any FeedbackDevice & Sendable)?`
- `import BioFeedbackKitHealthKit` removed from NarbisKit Package.swift
- `SessionPersistence` protocol (8 methods) + `InMemorySessionStore` (portable)
- `SessionStore` conforms to `SessionPersistence`
- 6 new `InMemorySessionStore` tests

### Portability Hardening (commit 5d545e3)
- `SessionRecord` and `RFMeasurement` made `internal` (only `SessionStore` uses them)
- `narbisModelTypes` public array for SwiftData container setup
- `appleWatchAvailable` → `relayDeviceAvailable` (platform-neutral naming)
- `TrainingViewModel.start()` takes `SessionPersistence` instead of `ModelContext`
- `DiscoveryViewModel.start()` takes `SessionPersistence` instead of `ModelContext`
- `import SwiftData` removed from both ViewModels
- All `String(format:)` eliminated across NarbisKit + NarbisUI (7 occurrences)

### Design Proposals Written
5 design proposals drafted and saved to `project/plans/proposals/`:
1. **PROPOSAL_connectview_wiring.md** — APPROVED, implemented this session
2. **PROPOSAL_sound_design.md** — DRAFT, harmonics + envelope + pink noise
3. **PROPOSAL_ble_hr_scanner.md** — DRAFT, CoreBluetooth 0x180D scanner
4. **PROPOSAL_ble_edge_scanner.md** — DRAFT, CoreBluetooth 0x00FF scanner
5. **PROPOSAL_visionos_target.md** — DRAFT, thin shell + RealityKit immersive

## 4. Quality Gate

| Check | Status |
| :--- | :--- |
| NarbisKit (92 tests) | All passing |
| NarbisUI (3 tests) | All passing |
| NarbisKit build | Zero errors, zero warnings |
| NarbisUI build | Zero errors, zero warnings |
| `String(format:)` audit | Zero occurrences remaining |
| SwiftData surface area | 3 files (SessionStore + 2 internal models) |

## 5. Portability Scorecard

| Package | Portable | Notes |
| :--- | :--- | :--- |
| BioFeedbackKit | 100% (49 files) | Entire algorithm/signal/feedback core |
| EdgeSDK-Swift | 100% (4 files) | Glasses byte protocol |
| BioFeedbackKit-Polar | 100% (3 files) | HR parsing + device adapter |
| BioFeedbackKit-EdgeBLE | 100% (2 files) | Glasses adapter (protocol-based) |
| BioFeedbackKit-HealthKit | 83% (5/6) | Only HKHealthStoreAdapter is Apple-specific |
| NarbisKit | 83% (19/23) | SwiftData persistence + gated WC/AVFoundation |
| NarbisUI | 0% (0/21) | All SwiftUI — expected, Compose rewrite for Android |

**Overall: 76% of codebase (82/108 files) ports directly to Android with zero changes.**

## 6. Next Session Handover

### Design Proposals Ready for Review
1. **Sound design** — harmonics, envelope smoothing, pink noise ambient pad. User said raw sine is "not calming."
2. **BLE HR scanner** — CoreBluetooth 0x180D for Polar H10 + generic HR monitors. Reuses `HRPayloadParser`.
3. **BLE Edge scanner** — CoreBluetooth 0x00FF for Edge glasses. 3 new types: `CBEdgePeripheral`, `CoreBluetoothGlassesConnector`, `EdgeBLEScanner`.
4. **Vision Pro target** — simulator-first, RealityKit coherence scene, `VisionFeedbackDevice` actor.

### Recommended Priority
1. **BLE HR scanner** — tester has Polar hardware, plugs directly into PeripheralRegistry
2. **BLE Edge scanner** — tester has Edge glasses
3. **Sound design** — independent, can parallelize with BLE work
4. **Vision Pro** — lowest urgency, simulator-first

### Pending Non-Feature Work
- [ ] NarbisSettings `UserDefaults` → `SettingsPersistence` protocol (moderate, deferred)
- [ ] Move SessionStore + models to app layer (hard, optional — currently acceptable)
- [ ] Firebase backend (`FirebaseSessionStore: SessionPersistence`)
- [ ] Delete old standalone watch project files (cleanup)

### TestFlight Bug Fixed (commit 7115f59)
Phone froze on second watch relay session. Root cause: `WatchRelayDevice.disconnect()` could throw (preventing `stopRelay` from reaching watch), and `WatchRelayBridge.activeDevice` held a stale reference. Fix: disconnect is now best-effort, HomeView cleans up old device before creating new one, connect() checks cancellation during reachability polling.

### Context Loss Warning
- **PeripheralRegistry** lives in `NarbisKit/Sources/NarbisKit/Connect/PeripheralRegistry.swift`. When BLE scanners are implemented, they call `registry.registerInput(peripheralId) { /* closure capturing CBPeripheral */ }`.
- **NoOpScanner** is still the placeholder in HomeView. Replace with real scanners when BLE proposals are implemented.
- **`relayDeviceAvailable`** replaced `appleWatchAvailable` — update any references in watch code if needed (watch code has its own copy).
- **`narbisModelTypes`** is the public constant for SwiftData container setup — use it instead of referencing `SessionRecord.self` or `RFMeasurement.self` (now internal).
- **TrainingViewModel and DiscoveryViewModel** now take `persistence: any SessionPersistence` — NOT `modelContext: ModelContext`. NarbisUI views create `SessionStore(context: modelContext)` and pass it as the protocol type.

---

**Session Duration:** ~3 hours
**AI Model Used:** Claude Opus 4.6 (1M context)
