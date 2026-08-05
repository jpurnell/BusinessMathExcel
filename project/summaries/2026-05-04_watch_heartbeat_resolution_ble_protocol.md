# Session Summary — 2026-05-04 (continued)

## Focus

1. Apple Watch heartbeat series investigation — definitive resolution
2. Resolution-adaptive coherence pipeline design
3. BLE protocol update review (Edge glasses + Earclip Path B)

## Previous Session Context

Prior session (same day, earlier) covered BLE bugs, HRV validation, and initial heartbeat series troubleshooting. This session continued the heartbeat series investigation to a definitive conclusion.

## Completed

### Apple Watch Heartbeat Series — Definitive Finding

Systematically eliminated every possible cause of `HKHeartbeatSeriesSample` not appearing during third-party workout sessions:

| Hypothesis | Tested | Result |
|---|---|---|
| Authorization missing | Auth status = 2 (already granted) | Not the cause |
| Orphaned workout race | Moved to awaited async recovery | Not the cause |
| Session/builder delegates not set | Confirmed active via callbacks | Not the cause |
| Wrong workout type | Tested `.mindAndBody`, `.other` | No difference |
| Builder not collecting | Confirmed: HR collected at ~0.2 Hz | Not the cause |
| HRV SDNN query | Added anchored query | 0 samples received |
| Mindful session trigger | Wrote `HKCategoryTypeIdentifier.mindfulSession` | Saved but no effect |
| Relaxed heartbeat series predicate | Used -60s start, no `.strictStartDate` | Still 0 samples |
| Session too short | Ran full 10-minute session (123 HR samples) | Still 0 heartbeat series |

**Conclusion:** Apple Watch does NOT generate `HKHeartbeatSeriesSample` for third-party workout sessions. Period.

**Evidence from Welltory (leading HRV app):** They read **historical** heartbeat series from Apple's own Breathe/Mindfulness app, not real-time data. Their help docs confirm measurements come from "calm moments" auto-detected by the watch or from manual Breathe sessions (3-5 minutes minimum).

**WWDC 2019 "Exploring New Data Representations in HealthKit":** The `HKHeartbeatSeriesBuilder` API is designed for apps with **their own sensor** providing beat timestamps. Apple Watch's system generates heartbeat series internally (for HRV SDNN computation) but does not expose real-time beat timestamps to third-party apps.

**What third-party apps actually get:** `HKQuantityType.heartRate` at ~0.2 Hz (one averaged BPM every ~5 seconds). This IS the data channel. The Apple Watch relay produced 123 samples in ~600 seconds of training with coherence = 65.77%.

### Code Changes Made

**`HKHealthStoreAdapter.swift`:**
- Added `hrvQuery: HKAnchoredObjectQuery?` — anchored query for `HRV SDNN` during workout
- Added `processHRVSamples()` — logs SDNN samples and probes for associated heartbeat series
- Added `queryHeartbeatSeriesInWindow()` — targeted sample query when SDNN arrives
- Added `mindfulSession` to auth request (read + write)
- Writes `HKCategorySample(.mindfulSession)` at workout start
- Relaxed heartbeat series predicate (60s earlier, no strict start)
- Activity type set to `.mindAndBody` (semantic alignment)
- Properly resets `hrvSampleCount` in cleanup paths

### Resolution-Adaptive Coherence Proposal

Saved to `project/plans/proposals/PROPOSAL_resolution_adaptive_coherence.md`.

Key design decisions:
- **No algorithm rewrite** — existing cubic spline + FFT pipeline is mathematically sound
- **Config preset selection** based on auto-detected input resolution (median inter-sample interval)
- Low-res config: resample 1 Hz, 90s min window, 180s buffer, peak band capped at 0.1 Hz, heavier smoothing
- Pacer capped at 5.5 BPM for watch (below 0.1 Hz Nyquist)
- New `confidence` field on `CoherenceResult`

### BLE Protocol Review

Read full `bluetooth-protocol.md` (1299 lines) documenting the Path B architecture update:
- **Earclip** — new BLE-only PPG sensor with IBI, SQI, RAW_PPG, and CONFIG characteristics
- **Edge dual-role** — now acts as BLE central connecting to earclip AND peripheral for iOS
- **New opcodes** — 0xC1 (forget earclip), 0xC3 (relay config), 0xC4 (toggle raw PPG)
- **New status frames** — 0xF4-0xF7 for relayed earclip data
- **PEER_ROLE** — per-connection conn-update profile on earclip
- **Config struct** — shrank from 56 to 48 bytes (config_version 3)

Design proposal for BLE integration saved separately.

## Key Decisions

1. **Apple Watch provides 0.2 Hz averaged HR — this is the ceiling for third-party apps.** No further investigation of heartbeat series is warranted.
2. **Coherence pipeline will be resolution-adaptive** rather than device-specific. The engine detects input quality and adjusts parameters automatically.
3. **Three input tiers exist:** Polar H10 / Earclip (high-res, ~1 Hz), Apple Watch (low-res, ~0.2 Hz). The Earclip joins the high-res tier.

## Git Status

Working changes in:
- `BioFeedbackKit-HealthKit/Sources/BioFeedbackKitHealthKit/HKHealthStoreAdapter.swift` — HRV query, mindful session, relaxed predicates
- `NarbisKit/Sources/NarbisKit/Session/TrainingViewModel.swift` — output connect non-fatal
- Various other files from prior session

Not yet committed (exploratory/diagnostic changes mixed with production fixes).

## Next Steps

1. **BLE Protocol Update** — Design and implement earclip + Path B Edge support
   - Earclip as high-res input device (true IBI at ~1 Hz)
   - Edge relay frames (0xF4-0xF7) for single-connection architecture
   - This is the highest priority — it unlocks production-quality input on iOS
2. **Resolution-Adaptive Coherence** — Implement after earclip integration proves the dual-resolution need
3. **Clean up HK diagnostic code** — The HRV SDNN query and mindful session write can stay (harmless) or be removed; the heartbeat series investigation is complete
