# Session Summary: Edge Protocol v5 + Session Robustness

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-05-06 | Edge protocol update + session hardening | COMPLETE |

## 1. Core Objectives

1. Update EdgeSDK to match Devon's authoritative bluetooth-protocol.md
2. Add 0xFF03 status stream across all layers (EdgeSDK → CoreBluetooth → BioFeedbackKit)
3. Harden session lifecycle (watchdog, best-effort output, relay retries)

## 2. What Was Completed

### 2.1 Edge Protocol v5 — All 4 Phases Complete

**Phase 1: EdgeSDK command layer**
- Rewrote `EdgeCommandEncoder` — removed legacy 0xA1/0xA3/0xA6(resume), added breathing 0xB0–0xB5, strobe 0xA6/0xAB/0xAC, PPG program 0xB7, difficulty 0xB8, adaptive pacer 0xB9, factory reset 0xBF, earclip relay 0xC1/0xC4
- Rewrote `EdgeGlassesController` — new `startBreathe()`, `startStrobe()`, preset sessions, status state tracking
- Added `EdgeTypes.swift` (BreatheWaveform, PPGProgram, CoherenceDifficulty)
- Added `EdgeStatusFrame.swift` + `EdgeStatusParser.swift` — typed parsing for 0xF0–0xF7
- 78 EdgeSDK tests passing (up from 32)

**Phase 2: EdgePeripheral + status stream**
- Extended `EdgePeripheral` protocol with `statusNotifications: AsyncStream<Data>`
- Updated `MockEdgePeripheral` with `injectStatus()` + `finishStatus()`
- `EdgeGlassesController.statusFrames` computed property parses raw data into typed frames
- `processStatusFrame()` updates `latestHealth` and `earclipLinked` state

**Phase 3: CoreBluetooth layer (iOS)**
- `CBEdgePeripheral` now accepts optional 0xFF03 status characteristic, subscribes to notifications, surfaces via AsyncStream
- `CoreBluetoothGlassesConnector` discovers ALL characteristics on 0x00FF (not just 0xFF01), finds both command and status chars
- Logs whether 0xFF03 was found

**Phase 4: EdgeGlassesDevice integration**
- `startSession()` uses new breathing opcodes (0xB0 mode + 0xB1 BPM + 0xB2 ratio)
- Background `statusMonitorTask` iterates `controller.statusFrames`, yields `.degraded` health when `bleSendErrors > 10`
- Status monitor cancelled on disconnect

### 2.2 Session Robustness Hardening

- **Best-effort output connect** — TrainingViewModel connects input first (required), then output as best-effort. Session continues input-only if Edge BLE fails.
- **Sample watchdog** — Disconnects input after 60s of silence (initial) then 30s (recurring). Covers HealthKit warmup delay and mid-session relay death.
- **Relay retries** — `sendMessageWithReply` with retry+backoff for reliable WCSession start handshake.
- **HealthKit adapter** — Conforms directly to workout session/builder delegates, adds HRV query, structured logging via os.Logger.

## 3. Commits

| Hash | Description |
| :--- | :--- |
| `f34325c` | Update EdgeSDK to match Devon's v5 firmware BLE protocol (14 files, +1311/−429) |
| `90bf05a` | Harden session lifecycle: watchdog, best-effort output, relay retries (11 files, +523/−122) |

## 4. Test Results

- EdgeSDK: 78 tests in 4 suites — all passing
- BioFeedbackKit: 366 tests in 27 suites — all passing

## 5. What Remains

### Immediate (next session)
- **On-device BLE test** with actual Edge glasses — verify new opcodes work on hardware
- **On-device test** with watch + iOS apps — verify session robustness changes

### Near-term
- Wire adaptive pacer (`0xB9`) + coherence difficulty (`0xB8`) into NarbisKit session setup based on user settings
- UI confidence indicator — surface coherence confidence in training HUD
- PPG stream parsing (0xFF04) — when earclip arrives

### Future
- Earclip integration (Path B relay) — proposal exists, hardware coming soon
- OTA firmware update protocol (0xA8–0xAA, 0xAD)
- Auth/subscriptions/payments design session
- Firebase backend integration

## 6. Architecture Reference

```
FeedbackUpdate → TintMapper → EdgeGlassesController → EdgePeripheral → BLE → glasses
                                     ↑ statusFrames
                              EdgeStatusParser ← 0xFF03 ← CBEdgePeripheral
                                     ↓
                              EdgeGlassesDevice.health stream
```

## 7. Key Files Modified

| File | Changes |
| :--- | :--- |
| `EdgeSDK-Swift/Sources/EdgeSDK/EdgeCommandEncoder.swift` | Full rewrite — all opcodes |
| `EdgeSDK-Swift/Sources/EdgeSDK/EdgeGlassesController.swift` | Full rewrite — new API surface |
| `EdgeSDK-Swift/Sources/EdgeSDK/EdgePeripheral.swift` | Added statusNotifications |
| `EdgeSDK-Swift/Sources/EdgeSDK/EdgeTypes.swift` | NEW — enums |
| `EdgeSDK-Swift/Sources/EdgeSDK/EdgeStatusFrame.swift` | NEW — typed status frames |
| `EdgeSDK-Swift/Sources/EdgeSDK/EdgeStatusParser.swift` | NEW — 0xFF03 parser |
| `BioFeedbackKit-EdgeBLE/.../EdgeGlassesDevice.swift` | Status monitor, new opcodes |
| `narbis-ios/.../CBEdgePeripheral.swift` | 0xFF03 subscription |
| `narbis-ios/.../CoreBluetoothGlassesConnector.swift` | Discover all chars |
| `NarbisKit/.../TrainingViewModel.swift` | Watchdog, best-effort output |
| `NarbisKit/.../WatchRelayDevice.swift` | Retry+backoff connect |
| `BioFeedbackKit-HealthKit/.../HKHealthStoreAdapter.swift` | Delegate conformance, HRV query |
