# Session Summary: CoherenceAlgorithm v1 Shipped

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-04-08 | Phase 2: Algorithm + Coherence | COMPLETED |

## 1. Core Objective

Ship the HRV coherence scoring layer in Swift, following v5 §6.3 of
the Narbis Edge MVP technical requirements as canonical, with a
faithful Dart-engine port (`LegacyCoherenceAlgorithm`) available as a
selectable alternative. Generify `ConfigStore` and `ConfigFetcher`
along the way so `CoherenceConfig` and `AlgorithmConfig` share the
same OTA infrastructure.

## 2. Design Decisions

- **Decision:** `CoherenceScorer` consumes pre-computed `FrequencyDomainMetrics` rather than raw `BioSample` collections.
- **Rationale:** Cleaner separation between Signal layer (data) and Algorithm layer (judgment). Same `FrequencyDomainMetrics` can be fed to multiple scorers without re-FFT. Cubic-vs-linear A/B comparison happens at the Signal layer where it belongs, not inside scorer variants.
- **Alternatives considered:** Original draft had each scorer take raw samples and run its own FFT. User pushed back: "the coherence algorithm consumes the output of an HRV Algorithm, is that correct?" — and that reframing led to the cleaner architecture.

- **Decision:** `CoherenceConfig` carries `interpolation` and `detrend` as runtime-switchable settings.
- **Rationale:** User wants live A/B switching of cubic vs linear without rebuilding. Both knobs are part of the OTA-updatable config rather than init-time constants. Enables side-by-side comparison in the same app session.

- **Decision:** Generify `ConfigStore<Config: ValidatableConfig>` and `ConfigFetcher<Config: ValidatableConfig>`. Migrate `AlgorithmConfig` to the generic versions.
- **Rationale:** User said "no hardcoding, make it a ConfigStore" for `CoherenceConfig`. Rather than duplicating store/fetcher code, generification gives both config types the same persistence/fetch infrastructure.

- **Decision:** `CoherenceScorer` is a separate protocol from `HRVAlgorithm`, no shared parent.
- **Rationale:** Different output shapes (`CoherenceResult` vs `CoherenceScore`), different use cases (heuristic shipping today vs future MLR scaffolding). Cousins, not siblings. Forcing them under one protocol would either pollute the output type or require lossy translation.

- **Decision:** EMA initial value = 0 (matches Dart `hrv_engine.dart`).
- **Rationale:** The 30s warmup gate hides the startup transient from users; by the time scores are visible, the EMA has converged.

- **Decision:** Stateful smoothing lives in `StreamingCoherenceEngine` actor; per-window scorers are pure functions.
- **Rationale:** Mirrors the existing `HRVMetrics` / `StreamingHRVMetrics` split. Per-window scoring stays testable in isolation.

- **Decision:** Static factory named `bundledDefault` (not `v5Default`).
- **Rationale:** Consistency with `AlgorithmConfig.bundledDefault`. User: "long term, that will be confusing."

- **Decision:** Default detrend = off across all variants.
- **Rationale:** v5 §6.3 doesn't specify detrend; the Dart engine adds it but the v5 spec is canonical. Detrend is available as a setting for users who want the Dart-faithful behavior.

## 3. Work Completed

### Design Proposal
- [x] `CoherenceAlgorithm-v1.md` drafted, refined through 6 messages of architectural conversation
- [x] All 10 approval checklist items addressed
- [x] All 5 open questions in §8 resolved with user input
- [x] Moved from `UPCOMING/` → `COMPLETED/2026-04-08_CoherenceAlgorithm-v1.md`
- [x] Status flipped from DRAFT to SHIPPED with implementation notes

### Tests Written (RED phase)
- [x] 33 new tests across 3 stages:
  - Stage 1 (generification refactor): 0 new tests, 151 existing must stay green
  - Stage 2 (FrequencyDomainMetrics extension): 5 new tests for `interpolation` and `preprocessing` parameters
  - Stage 3 (coherence algorithm): 28 new tests covering CoherenceConfig, CoherenceResult, CoherenceAlgorithm (v5), LegacyCoherenceAlgorithm, StreamingCoherenceEngine, ConfigStore<CoherenceConfig>, and the gap-coverage tests

### Implementation (GREEN phase)
- Files created:
  - `Sources/BioFeedbackKit/Algorithm/CoherenceConfig.swift`
  - `Sources/BioFeedbackKit/Algorithm/CoherenceResult.swift`
  - `Sources/BioFeedbackKit/Algorithm/CoherenceScorer.swift`
  - `Sources/BioFeedbackKit/Algorithm/CoherenceAlgorithm.swift`
  - `Sources/BioFeedbackKit/Algorithm/LegacyCoherenceAlgorithm.swift`
  - `Sources/BioFeedbackKit/Algorithm/StreamingCoherenceEngine.swift`
  - `Tests/BioFeedbackKitTests/CoherenceAlgorithmTests.swift`
- Files modified:
  - `Sources/BioFeedbackKit/Algorithm/ConfigStore.swift` (added `ValidatableConfig` protocol; generified `ConfigStore<Config>`)
  - `Sources/BioFeedbackKit/Algorithm/InMemoryConfigStore.swift` (generified)
  - `Sources/BioFeedbackKit/Algorithm/FileConfigStore.swift` (generified, added `subdirectory:` convenience init)
  - `Sources/BioFeedbackKit/Algorithm/AlgorithmConfig.swift` (`ValidatableConfig` conformance)
  - `Sources/BioFeedbackKit/Algorithm/ConfigFetcher.swift` (generified `ConfigFetchResult<Config>`)
  - `Sources/BioFeedbackKit/Algorithm/RemoteConfigFetcher.swift` (generified, uses `ValidatableConfig.validated()`)
  - `Sources/BioFeedbackKit/Signal/FrequencyDomainMetrics.swift` (added `InterpolationMethod` and `SpectralPreprocessing` parameters)
  - `Tests/BioFeedbackKitTests/ConfigStoreTests.swift` (type parameter additions)
  - `Tests/BioFeedbackKitTests/ConfigFetcherTests.swift` (type parameter additions)

### Documentation
- [x] DocC `///` on every public symbol with reference to v5 §6.3 or `hrv_engine.dart` source
- [x] Inline comments document the cubic-vs-linear deviation rationale, the legacy dimensional issue, and the EMA startup behavior

## 4. Mandatory Quality Gate

| Check | Status |
| :--- | :--- |
| **build** | ✅ zero warnings |
| **test** | ✅ **184 / 184 passing** |
| **safety** | ✅ no `String(format:)`, `try!`, `as!`, `fatalError`, force unwraps |
| **doc-lint** | ✅ DocC on every public symbol |
| **doc-coverage** | ✅ |

**Test count progression this session:** 156 → 184 (+28).
**Total since project start:** 78 → 184 (+106).

## 5. Project State Updates

- [x] `project/plans/completed/2026-04-08_CoherenceAlgorithm-v1.md` (moved from UPCOMING/, status SHIPPED)
- [x] No active checklists in `project/checklists/CURRENT_*.md`
- [ ] `master_plan.md` could use a one-line update marking the coherence layer shipped (deferred — no architectural change)

## 6. Next Session Handover (Context Recovery)

### Immediate Starting Point

The HRV signal + algorithm core is now feature-complete for the v5 §6.3
spec. Next layer is **outside BioFeedbackKit proper** — it's app-layer
work that consumes the library. The biggest remaining items:

1. **Feedback layer** (`OpacityController`, glasses driver). Closes the loop from `CoherenceResult` to user-visible glasses opacity. Math helpers (sigmoid/linear curve, adaptive sensitivity HIGH/MEDIUM/LOW) can live in the library; the BLE side belongs in the app.
2. **Hardware adapters** (`PolarH10Adapter`, `EdgeGlassesAdapter`). BLE adapters that conform to the existing `Device` protocol. App-layer per the cross-platform mandate.
3. **Discovery protocol orchestration** (Lehrer stepped, Fisher sweep, Smart Start). State machines that drive the session through paced breathing rates and collect coherence per rate. App-layer.
4. **The Swift narbis Edge app target itself.** Doesn't yet exist as a separate target/codebase. Required to actually consume BioFeedbackKit.

### Pending Tasks

- [ ] Decide whether next work is library-layer (small math helpers for the Feedback layer) or app-layer (start the Swift Edge app target)
- [ ] Optional: send the questions doc to Devon as a heads-up (not blocking — internal decisions made)
- [ ] Optional: write a small `CoherenceConfig.bundledDefault` integration test that exercises the full pipeline through `StreamingCoherenceEngine` end-to-end with realistic synthetic data

### Blockers

None. The library is in a clean shippable state.

### Context Loss Warning

- **`CoherenceScorer` consumes pre-computed `FrequencyDomainMetrics`, NOT raw `BioSample` collections.** The Signal layer produces data; the Algorithm layer applies judgment. Don't refactor to put the FFT inside the scorer — it's intentionally outside.
- **`CoherenceAlgorithm` (v5) and `LegacyCoherenceAlgorithm` (Dart-faithful) are siblings, not a default + variant.** Both implement `CoherenceScorer`. Both produce `CoherenceResult`. The app picks at runtime.
- **The legacy algorithm saturates the 0–100 clamp on clean-peak inputs due to a dimensional issue in `peakRatio = peakPower / band-integrated-total`.** This is faithful to `hrv_engine.dart`. Don't "fix" it — the regression tests lock the saturation. If we ever ship legacy mode user-facing, flag this to Devon.
- **The v5 spec produces ~52% coherence on a perfect 60s 0.10 Hz sine** due to Hann main lobe width vs ±0.015 Hz integration window. This is correct behavior; real users will see numbers in the 30–60% range when "in the zone." Don't try to push it higher without changing the spec.
- **`ConfigStore<T>` and `ConfigFetcher<T>` are generic over `ValidatableConfig`.** Both `AlgorithmConfig` and `CoherenceConfig` use the same infrastructure. New config types should also conform to `ValidatableConfig`.
- **Static factories are named `bundledDefault`** on both config types, not `v5Default` or anything algorithm-specific.
- **`StreamingCoherenceEngine` is an actor** with stateful EMA + 60s rolling buffer + 30s warmup gate. The per-window scorers are pure structs.

---

## Metrics

| Metric | Before | After |
|--------|--------|-------|
| Test count | 156 | **184** |
| Files in `Sources/BioFeedbackKit/Algorithm/` | 10 | **16** |
| Coherence algorithm variants | 0 | 2 (`CoherenceAlgorithm`, `LegacyCoherenceAlgorithm`) |
| Config types in `ConfigStore` | 1 (`AlgorithmConfig`) | **2** (`AlgorithmConfig`, `CoherenceConfig`) |
| Layer status | Algorithm scaffold + OTA only | Algorithm + Signal + Coherence + OTA all complete |

## Layer Status After This Session

| Layer | Status |
|---|---|
| Devices (BioSample, MockDevice) | ✅ shipped |
| Signal/RRBuffer + filters | ✅ shipped |
| Signal/HRVMetrics | ✅ shipped |
| Signal/StreamingHRVMetrics | ✅ shipped |
| Signal/FrequencyDomainMetrics (with PSD bins, peak finder, integration helper, cubic/linear, mean/detrend) | ✅ shipped |
| Algorithm/HRVAlgorithm + CoreAlgorithm (MLR scaffold) | ✅ shipped |
| **Algorithm/CoherenceScorer + CoherenceAlgorithm (v5) + LegacyCoherenceAlgorithm** | ✅ **shipped this session** |
| **Algorithm/StreamingCoherenceEngine** | ✅ **shipped this session** |
| Algorithm/ConfigStore<T> (generic, supports AlgorithmConfig + CoherenceConfig) | ✅ shipped (generified this session) |
| Algorithm/ConfigFetcher<T> (generic) | ✅ shipped (generified this session) |
| Feedback layer (OpacityController, glasses driver) | ⏳ not started (app layer) |
| Hardware adapters (PolarH10, EdgeGlasses) | ⏳ not started (app layer) |
| Discovery protocols (Lehrer / Fisher / Smart Start) | ⏳ not started (app layer) |
| Swift narbis Edge app target | ⏳ not started |
