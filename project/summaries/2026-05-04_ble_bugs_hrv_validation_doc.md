# Session Summary: BLE Bug Fixes + HRV Validation Document

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-05-04 | BLE on-device testing + Apple Watch HRV validation research | IN PROGRESS |

## 1. Core Objectives

1. Resolve three bugs found during on-device BLE testing (launch hang, stop button, continuation leak)
2. Revise the Apple Watch HRV validation document with proper source-paper review
3. Clean up documentation and folder structure

## 2. What Was Completed

### 2.1 On-Device Bug Fixes (3 of 3 resolved)

**Launch hang — RESOLVED.** User confirmed sub-second launch: 0.557s init, 0.087s HomeView ready (~0.65s total). The prior 45-second hang was caused by `@State` mutation during body evaluation and main-thread SwiftData queries. Fix: VM creation moved to `.task`, SwiftData queries run in `Task.detached`.

**Stop button unresponsive after error — RESOLVED.** The error catch block in `TrainingViewModel.start()` didn't set `sessionSummary`, leaving the fullScreenCover stuck (view only transitions to ResultsView when `sessionSummary != nil`). Fix: error handler now creates a partial `SessionSummary` and sets `isPartialSession = true`, same as the cancellation path.
- File: `NarbisKit/Sources/NarbisKit/Session/TrainingViewModel.swift`

**Continuation leak from double-connect — RESOLVED.** Two-part fix:
1. `EdgeGlassesDevice.swift`: Added `_isConnecting` flag to prevent actor-reentrancy double-connect. Guard checks both `_isConnected` and `_isConnecting`.
2. `CoreBluetoothGlassesConnector.swift`: Added stale continuation cleanup in `awaitConnection()` — if `connectionContinuation` is already set when a new connection attempt arrives, the old one is resumed with an error before being replaced.

### 2.2 Blockers Resolved (from prior session)

**PeripheralRegistry mismatch — RESOLVED (prior session).** HomeView now takes `peripheralRegistry` as injected `let` (not `@State`). NarbisIOSApp passes its single registry to both EdgeBLEScanner and HomeView.

**Edge glasses not appearing in BLE scan — RESOLVED (prior session).** Confirmed advertising name is `Narbis_Edge` via nRF Connect. Added `"Narbis_Edge"` as first entry in `edgeNamePrefixes`. Set `discoveryMode = false`.

### 2.3 Apple Watch HRV Validation Document — Major Revision

**File:** `project/docs/technical/APPLE_WATCH_HIGH_RES_HEARTRATE.md`

Three rounds of revision after reading the actual source papers (O'Grady et al. 2024, Lambe et al. 2026, Bonneval et al. 2025):

**Round 1:** Corrected hallucinated citations (Stone et al. → O'Grady et al., Gilgen-Ammann → Schaffarczyk). Added "What O'Grady Actually Measured" section showing Breathe app black-box vs Narbis pipeline. Added three specific validation gaps.

**Round 2:** Identified that O'Grady and Lambe share 4 of 5 authors (same UCD lab). Changed "Two Independent Studies" to "One Research Group, One Study." Updated validation opportunity from "second" to "first new" study.

**Round 3 (this session):** Incorporated Bonneval et al. (2025) — Sensors 25(8):2380, UCSD — as a genuinely independent second validation study. Key additions:
- Section header updated to "Two Studies, Two Labs — But Still a Thin Evidence Base"
- New subsection with Bonneval's Table 5 data: RR at rest 1.15% MAPE (CCC 0.991) vs NN at rest 31.41% MAPE — the RR vs NN divergence is the key finding for Narbis since we do our own ectopic filtering
- Data failure rates by condition (2.56% at rest, 43.59% during conversation)
- Age-related accuracy concerns (70-75 age group had 73% of RR outliers)
- Updated biofeedback nuance section citing both studies
- Updated validation gaps to reflect strengthened (but still thin) evidence base
- Full reference entry with DOI and PMID

### 2.4 Development-Guidelines Cleanup

Removed from `project/plans/`:
- `#Architecture_embeddedUML.md#` — emacs swap file
- `Architecture_embeddedUML.md` — intermediate version (815 lines, superseded)
- `ARCHITECTURE_apple_watch_ios_edge.md` — duplicate of `project/docs/technical/` version
- `diagrams/` directory — duplicate of `project/docs/technical/diagrams/`

Canonical locations:
- Architecture doc with embedded SVGs → `project/docs/technical/ARCHITECTURE_apple_watch_ios_edge.md`
- PlantUML sources + rendered SVGs → `project/docs/technical/diagrams/`
- HRV validation paper → `project/docs/technical/APPLE_WATCH_HIGH_RES_HEARTRATE.md`
- Patent PDF → `project/library/Patent/US9521976.pdf`

### 2.5 Implementation Checklist Updated

**File:** `project/checklists/CURRENT_ble_edge_scanner.md`

Updated from "BLOCKED on two issues" to "READY FOR ON-DEVICE BLE TEST — all blockers resolved, launch verified sub-second." All three blocker sections marked resolved with details.

## 3. Quality Gate

Not run — changes span code + documentation. Code changes are uncommitted.

| Check | Status |
| :--- | :--- |
| **build** | SPM builds clean. Xcode untested this session. |
| **test** | 484 tests pass (348 + 136) — verified prior session |
| **safety** | Not run |
| **doc-lint** | Not run |

## 4. Active Project Strands

### Strand A: BLE Edge Glasses End-to-End (PRIMARY)
**Status:** All code written, all blockers resolved. Needs Phase 7 on-device integration test.
**Checklist:** `project/checklists/CURRENT_ble_edge_scanner.md`
**What remains:**
- [ ] Build in Xcode — verify no remaining import issues
- [ ] Phase 7: Edge glasses appear in ConnectView output list
- [ ] Phase 7: Select Edge + Connect → BLE connection succeeds
- [ ] Phase 7: `render()` loop drives real lens tint changes during training
- [ ] Phase 7: "Always use this device" auto-reconnects on next launch
- [ ] Phase 7: Bluetooth-off shows appropriate guidance
- [ ] Phase 6 (deferred): `retrievePeripherals` fast reconnect, RSSI indicator, BT-off banners

### Strand B: Apple Watch HRV Validation Paper
**Status:** Document revised with all three source papers properly characterized. Ready for stakeholder/advisor review.
**File:** `project/docs/technical/APPLE_WATCH_HIGH_RES_HEARTRATE.md`
**What remains:**
- [ ] Stakeholder review of the document
- [ ] Decision on whether to pursue the validation study protocol described in the document
- [ ] If pursuing: design detailed study protocol (n, inclusion criteria, session parameters, analysis plan)

### Strand C: Audio Binaural Beats
**Status:** Implemented and working on-device. Proposal exists, no open tasks.
**Proposal:** `project/plans/proposals/PROPOSAL_audio_preview.md`
**What remains:**
- [ ] Audio preview UI (proposed but not implemented)

### Strand D: visionOS Target
**Status:** Functional with breathing sphere + passthrough tint in immersive space. Multiple bug fixes landed (sphere animation, debug windows, color changes). On TestFlight.
**What remains:**
- [ ] Multi-modal feedback refinement (visual + audio in immersive space)
- [ ] Performance testing on actual Vision Pro hardware

### Strand E: Firebase Backend
**Status:** Not started. Scoped for after BLE loop is complete.
**What remains:**
- [ ] Design proposal for auth, session sync, subscriptions
- [ ] Depends on Strand A completion

### Strand F: Meta Glasses Assessment
**Status:** Assessed and deferred. DAT SDK v0.6.0 is camera-input only, no output APIs.
**File:** `project/plans/proposals/PROPOSAL_meta_glasses.md`
**What remains:**
- [ ] Monitor Meta developer portal for display/lens control APIs in future SDK versions

## 5. Uncommitted Changes (Main Repo)

### Modified files:
| File | Change |
|------|--------|
| `BioFeedbackKit-EdgeBLE/.../EdgeGlassesDevice.swift` | `_isConnecting` flag to prevent actor-reentrancy double-connect |
| `BioFeedbackKit/.../FeedbackDevice.swift` | `configureSession()` protocol addition |
| `NarbisKit/.../NarbisLog.swift` | `NarbisLog.launch` logger |
| `NarbisKit/.../TrainingViewModel.swift` | Error handler sets `sessionSummary` + `isPartialSession` |
| `NarbisUI/.../HomeView.swift` | State mutation fix, background SwiftData queries, launch logging |
| `narbis-ios/.../project.pbxproj` | Xcode project config for EdgeSDK + BLE files |
| `narbis-ios/.../NarbisWatch Watch App.xcscheme` | Watch scheme updates |
| `narbis-ios/.../xcschememanagement.plist` | Scheme management |
| `narbis-ios/.../Info.plist` | BLE permissions |
| `narbis-ios/.../NarbisIOSApp.swift` | EdgeBLEScanner wiring, launch logging, registry injection |

### Untracked files:
| File | Purpose |
|------|---------|
| `narbis-ios/.../BLE/CBEdgePeripheral.swift` | CBPeripheral wrapper conforming to EdgePeripheral |
| `narbis-ios/.../BLE/CoreBluetoothGlassesConnector.swift` | BLE connection manager with async/await bridge |
| `narbis-ios/.../BLE/EdgeBLEScanner.swift` | CoreBluetooth scanner for Edge glasses discovery |
| `narbis-ios/.../Packages/` | Local package references (RealityKitContent for visionOS) |

---

**Session Duration:** ~4 hours  
**AI Model Used:** Claude Opus 4.6
