# Session Summary: SettingsPersistence, Ambient Binaural Pad, Project Cleanup

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-04-23 | Non-feature housekeeping + sound design feature | COMPLETED |

## 1. Core Objective

Three independent workstreams: (1) extract SettingsPersistence protocol for cross-platform portability, (2) transform the audio engine from a bare sine oscillator into a warm ambient meditation pad, (3) clean up old standalone watch project.

## 2. Design Decisions

- **SettingsPersistence mirrors SessionPersistence pattern.** Protocol + InMemorySettingsStore (tests/Android) + UserDefaultsSettingsStore (production). NarbisSettings accepts `any SettingsPersistence` via DI. Backward-compatible `init(defaults:)` convenience init preserved.
- **Engine does the sound design, users don't.** No harmonic richness slider in main UI. Coherence-driven adaptive harmonics are the default behavior. Only an advanced toggle (`adaptiveHarmonics`) for power users.
- **Band-passed pink noise for warmth.** Standard pink noise has too much high-frequency hiss. One-pole LowPassFilter at 800 Hz produces a warm "room tone" cushion. Reference: "639 Hz Heart Chakra Patterns" by Binaural Frequencies.
- **SessionStore move to app layer deferred.** The SessionPersistence protocol abstraction already solves the portability problem. Physical file relocation is churn for minimal gain.
- **Firebase deferred.** Not needed until BLE training loop works end-to-end on hardware. Auth/subscriptions/payments scoped as future design session (stub in IDEAS/).
- **NarbisWatchKit relocated, not deleted.** The agent found the iOS watch target still references NarbisWatchKit as a local SPM package. Moved to project root as a sibling to NarbisKit/NarbisUI. Package.swift dependency paths updated from `../../` to `../`.

## 3. Work Completed

### SettingsPersistence Protocol (commit ac0819f)
- `SettingsPersistence` protocol with get/set for 13 settings properties
- `InMemorySettingsStore` — test/Android conformer with spec defaults
- `UserDefaultsSettingsStore` — extracted persistence logic, namespaced keys, Key enum
- `NarbisSettings` refactored to accept `any SettingsPersistence`
- 15 new tests (SettingsPersistenceTests), 6 updated tests (NarbisSettingsTests)

### Old Watch Project Cleanup (commit ac0819f)
- `narbis-watch/NarbisWatch/` (standalone xcodeproj) — deleted
- `narbis-watch/NarbisWatchKit/` — relocated to project root
- Xcode project reference updated to `../../NarbisWatchKit`
- Package.swift paths fixed from `../../BioFeedbackKit` to `../BioFeedbackKit` (commit 81cc580)

### Ambient Binaural Pad (commit 640ea18)
- `EnvelopeSmoother` — one-pole exponential filter, 50ms attack / 100ms release
- `PinkNoiseGenerator` — Voss-McCartney, 16 octave rows, tuple-backed (zero heap allocation)
- `LowPassFilter` — one-pole, 800 Hz cutoff for warm cushion texture
- `generateSample(phase:harmonicRichness:)` — static testable method, 2nd/3rd partials, normalized
- `AudioFeedbackConfig` — added `harmonicRichness` (0.7), `ambientVolume` (0.25), `adaptiveHarmonics` (true); default volume lowered 0.3 → 0.15; backward-compatible Codable
- `AudioState` — coherenceRichness, baseRichness, ambientVolume, adaptiveHarmonics
- Render callback: harmonics + envelope smoothing + filtered ambient pad
- `update()`: coherence-driven richness modulation when adaptive
- `adaptiveHarmonics` persisted in SettingsPersistence, toggle in SettingsView
- 28 new tests across 6 suites (SoundDesignTests.swift)

### Additional Fixes
- All `specifier:` format strings replaced with `.formatted()` across NarbisUI (SettingsView, DiscoveryView, HomeView, SessionHistoryView)
- Flaky `InMemorySessionStore.currentRF` test fixed (timing issue with `max(by:)` on same-millisecond dates → use `.last`)

### Proposal Housekeeping
- `PROPOSAL_connectview_wiring.md` — status updated to COMPLETED, moved to `COMPLETED/`
- `PROPOSAL_sound_design.md` — status updated to COMPLETED, moved to `COMPLETED/`
- `IDEA_auth_subscriptions_payments.md` — created in new `IDEAS/` directory
- Master plan updated with new completed items and test count

## 4. Quality Gate

| Check | Status |
| :--- | :--- |
| NarbisKit build | Zero errors, zero warnings |
| NarbisUI build | Zero errors, zero warnings |
| NarbisKit tests (136) | All passing |
| NarbisUI tests (3) | All passing |
| `String(format:)` audit | Zero occurrences |
| `specifier:` audit | Zero occurrences in NarbisUI |
| NarbisWatchKit SPM resolve + build | Passing |

## 5. Project State Updates

- [x] `master_plan.md` updated (new completed items, test count 139, last-updated date)
- [x] Completed proposals moved to `project/plans/completed/`
- [x] No active CURRENT_*.md checklists (between features)

## 6. Next Session Handover

### Design Proposals Ready for Review
1. **BLE HR Scanner** (`PROPOSALS/PROPOSAL_ble_hr_scanner.md`) — CoreBluetooth 0x180D for Polar H10 + generic HR monitors. Tester has hardware. Plugs into PeripheralRegistry.
2. **BLE Edge Scanner** (`PROPOSALS/PROPOSAL_ble_edge_scanner.md`) — CoreBluetooth 0x00FF for Edge glasses. Tester has hardware.
3. **Vision Pro target** (`PROPOSALS/PROPOSAL_visionos_target.md`) — simulator-first, RealityKit coherence scene.

### Recommended Priority
1. **BLE HR Scanner** — tester has Polar hardware, directly enables real training sessions
2. **BLE Edge Scanner** — tester has Edge glasses, completes the canonical Polar+Edge flow
3. **Auth/subscriptions/payments** — design session (stub in `IDEAS/`)
4. **Vision Pro** — lowest urgency

### Pending Non-Feature Work
- [ ] Auth/subscriptions/payments design session (stub in IDEAS/)
- [ ] Firebase backend (`FirebaseSessionStore: SessionPersistence`) — deferred until BLE loop complete

### Context Loss Warning
- **NarbisWatchKit** now lives at project root (`/narbis/NarbisWatchKit/`), NOT in `narbis-watch/`. Its Package.swift points to `../BioFeedbackKit` (one level up to project root, then into sibling package).
- **SettingsPersistence** has 13 properties (12 original + `adaptiveHarmonics`). When adding new settings, update the protocol, both stores, and NarbisSettings.
- **AudioFeedbackConfig** now has 10 properties. Old persisted JSON without `harmonicRichness`/`ambientVolume`/`adaptiveHarmonics` decodes with safe defaults via `decodeIfPresent`.
- **Render thread types** (`EnvelopeSmoother`, `PinkNoiseGenerator`, `LowPassFilter`) are `internal` structs in `AudioFeedbackEngine.swift`. They are NOT private — tests access them via `@testable import`.
- **`specifier:` is gone** from NarbisUI. Use `.formatted()` for all numeric display formatting.

---

**Session Duration:** ~2 hours
**AI Model Used:** Claude Opus 4.6 (1M context)

### Metrics

| Metric | Before | After |
|--------|--------|-------|
| Test count (NarbisKit) | 108 | 136 |
| Test count (NarbisUI) | 3 | 3 |
| Test suites | 15 | 21 |
| NarbisKit warnings | 0 | 0 |
| Proposals (DRAFT) | 4 | 3 |
| Proposals (COMPLETED) | 1 | 2 |
