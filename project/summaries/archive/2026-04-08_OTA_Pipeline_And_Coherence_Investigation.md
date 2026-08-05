# Session Summary: OTA Pipeline + Real Coherence Algorithm Investigation

| Date | Phase | Status |
| :--- | :--- | :--- |
| 2026-04-07 → 2026-04-08 | Phase 2: Algorithm + OTA + Coherence Discovery | COMPLETED (3 features shipped) + BLOCKED (1 awaiting external input) |

## 1. Core Objective

Three threads, executed in sequence:

1. **Ship the Algorithm layer scaffolding** (`HRVAlgorithm` protocol, `CoreAlgorithm` MLR scoring, `AlgorithmConfig` Codable + bundled default) so the per-layer architecture from the Master Plan is in place
2. **Ship the OTA pipeline** (`ConfigStore` for on-device persistence, `ConfigFetcher` for remote fetch) so configs can flow from server → disk → algorithm without app updates
3. **Locate the real Narbis coherence algorithm** in the existing edge Flutter codebase, do gap analysis vs our Swift scaffolding, and produce a questions document for the algorithm's author before porting

## 2. Design Decisions

### Algorithm Layer

- **Decision:** `CoreAlgorithm` is a z-scored linear-combination scorer with a configurable `OutputTransform` (`.raw` / `.sigmoid` / `.linearClamped`)
- **Rationale:** Matches the structure produced by linear regression training (`MultipleLinearRegression` server-side); inference is direct array arithmetic with no BusinessMath dependency on-device
- **Alternatives considered:** Hand-rolling each algorithm variant in code (rejected — OTA story requires data-driven configuration)

- **Decision:** Algorithm layer is intentionally **BusinessMath-free**
- **Rationale:** Inference is small linear math; training (MLR) lives server-side. Keeping BusinessMath out of the on-device Algorithm directory keeps the dependency surface narrow and matches the "OTA via config, not code" decision.
- **Memorialized in:** `~/.claude/projects/.../memory/project_algorithm_layer_no_businessmath.md`

- **Decision:** `lfHfRatio` infinity → `1e6` sentinel substitution lives in `CoreAlgorithm`, not in `FrequencyDomainMetrics`
- **Rationale:** `FrequencyDomainMetrics.lfHfRatio` keeps its documented `.infinity` contract; the algorithm layer substitutes only when reading the value as a feature, so the Signal layer stays mathematically honest and the Algorithm layer stays JSON-safe

### ConfigStore

- **Decision:** Single-slot current + auto-promoted last-known-good (no explicit `promote()` method)
- **Rationale:** Every successful save earns LKG status when superseded. The promotion policy is implicit and YAGNI for v1; we can add an explicit `promoteToLKG()` if a real caller needs it.

- **Decision:** Store is a dumb pipe — does not know about `bundledDefault`
- **Rationale:** Caller composes the fallback ladder explicitly: `try await store.loadCurrent() ?? store.loadLastKnownGood() ?? .bundledDefault`. The fallback policy lives at the call site where it's visible.

- **Decision:** Default directory is `Application Support/Algorithm/` (Darwin) or `$XDG_DATA_HOME/Algorithm/` (Linux). The "BioFeedbackKit" name is **deliberately not** in the on-disk path.
- **Rationale:** User wants the package name obscured from disk inspection; cross-platform Apple + Linux requires platform branching anyway.

### ConfigFetcher

- **Decision:** Fetcher is a dumb pipe — does not call `ConfigStore.save(_:)`
- **Rationale:** Same composition philosophy as ConfigStore. Caller decides whether to save (and may want to log/diff first).

- **Decision:** Re-validate decoded payloads by feeding fields back through `AlgorithmConfig.init(...)`
- **Rationale:** The Codable path bypasses the throwing init. The fetcher is the first place a server bug can sneak shape errors into the system, so this is the right layer to catch them. Not the store's job.

- **Decision:** No retry, no signature verification, no monotonic-version enforcement in v1
- **Rationale:** Retry policy is genuinely a caller concern. Signatures need a key distribution story we don't have. Monotonic versioning is primarily a server-side concern. All three are reasonable v2 enhancements.

### Coherence Algorithm Discovery

- **Decision:** Stop and write a questions document for the algorithm's author **before** drafting a Swift port proposal
- **Rationale:** The shipping Dart code (`hrv_engine.dart`) differs in 4 material ways from the design doc (`HRV_COHERENCE_ADAPTATION.md`). Some differences look like bugs/drift, others may be deliberate calibration. Silently "improving" past calibration we don't understand would regress user-visible scores; faithfully copying drift would propagate bugs.

- **Decision:** Default plan if the author doesn't reply: **match Dart exactly except use cubic spline interpolation**
- **Rationale:** Cubic spline is empirically 10× more accurate in the HF band (~33% → 2.85% error on validated sine fixtures), free on iOS via Accelerate, and the design doc itself recommends it. Everything else stays as-is for behavioral continuity.

## 3. Work Completed

### Algorithm Layer (shipped 2026-04-07)

**Design Proposal:** `project/plans/completed/2026-04-07_AlgorithmLayer-v1.md` — APPROVED with 6 open questions resolved

**Tests Written (RED phase):** 23 tests in `Tests/BioFeedbackKitTests/AlgorithmTests.swift`
- CoherenceScore construction, equality, Codable
- AlgorithmConfig validation (mismatched weights, zero/negative stdDev)
- Codable JSON roundtrip for all 3 OutputTransform variants
- CoreAlgorithm math correctness (single-feature, z-scored, two-feature combinations, intercept addition)
- Output transforms (sigmoid 0/+/-, linearClamped within/below/above)
- Frequency-domain nil handling, lfHfRatio sentinel substitution
- Bundled default lock-in
- Unknown feature errors
- End-to-end integration

**Implementation (GREEN phase):**
- Files created:
  - `Sources/BioFeedbackKit/Algorithm/AlgorithmError.swift`
  - `Sources/BioFeedbackKit/Algorithm/AlgorithmConfig.swift` (config + FeatureSpec + FeatureSource + OutputTransform + bundledDefault)
  - `Sources/BioFeedbackKit/Algorithm/HRVAlgorithm.swift` (protocol + CoherenceScore)
  - `Sources/BioFeedbackKit/Algorithm/CoreAlgorithm.swift` (concrete implementation)
- All 23 tests passed on first GREEN attempt

**Documentation:** DocC `///` on every public symbol covering the inference pipeline, OTA-update story, sentinel rationale, placeholder caveat

### ConfigStore (shipped 2026-04-07)

**Design Proposal:** `project/plans/completed/2026-04-07_ConfigStore-v1.md` — APPROVED with 4 open questions resolved

**Tests Written (RED phase):** 19 tests in `Tests/BioFeedbackKitTests/ConfigStoreTests.swift`
- Behavioral tests parameterized over both impls via `runOnBothStores` helper
- Save semantics (1, 2, 3 saves; LKG promotion correctness)
- Roundtrip preservation (bundled default + all 3 OutputTransform variants)
- clear() semantics
- FileConfigStore-specific: directory creation, file paths, human-readable JSON, corrupt-file handling, isolation between corrupt LKG and current, two stores at same dir
- Startup-ladder integration tests

**Implementation (GREEN phase):**
- Files created:
  - `Sources/BioFeedbackKit/Algorithm/ConfigStore.swift` (protocol + ConfigStoreError)
  - `Sources/BioFeedbackKit/Algorithm/InMemoryConfigStore.swift` (actor)
  - `Sources/BioFeedbackKit/Algorithm/FileConfigStore.swift` (atomic temp-file + rename writes, platform-branched default base directory)

### ConfigFetcher (shipped 2026-04-07)

**Design Proposal:** `project/plans/completed/2026-04-07_ConfigFetcher-v1.md` — APPROVED with 7 open questions resolved up front

**Tests Written (RED phase):** 20 tests in `Tests/BioFeedbackKitTests/ConfigFetcherTests.swift`
- `FakeTransport` actor records every request and replays canned responses
- Request construction (5 tests): version query param, empty version, bearer token header, no-token header absence, Accept header
- Response handling (8 tests): 200, 304, 401, 403, 404, 500, 503, unexpected 201
- Decode + validation (5 tests): garbage body, wrong shape, mismatched weights, non-positive stdDev, bundledDefault roundtrip
- Transport failure wrapping (1 test)
- End-to-end integration with InMemoryConfigStore (1 test)

**Implementation (GREEN phase):**
- Files created:
  - `Sources/BioFeedbackKit/Algorithm/Transport.swift` (protocol + URLSessionTransport, with FoundationNetworking import for Linux)
  - `Sources/BioFeedbackKit/Algorithm/ConfigFetcher.swift` (protocol + ConfigFetchResult + ConfigFetcherError)
  - `Sources/BioFeedbackKit/Algorithm/RemoteConfigFetcher.swift` (concrete impl)

### Coherence Algorithm Investigation (2026-04-08)

**Discovery work:**
- Located the actual shipping algorithm at `firstPass/edge-main/app/lib/core/domain/hrv/hrv_engine.dart` (10 KB)
- Read companion files: `hrv_types.dart` (CoherenceResult, HRVConfig), `hrv.dart` (barrel)
- Read the design doc at `firstPass/edge-main/dna/technical/HRV_COHERENCE_ADAPTATION.md`
- Performed gap analysis against our existing `FrequencyDomainMetrics` Swift pipeline

**Findings (the four material gaps):**
1. **Cubic spline vs linear resample.** Our Swift pipeline uses cubic spline (Kubios standard) — empirically ~10× more accurate in HF (~2.85% vs ~33% error on validated sine fixtures). Dart uses linear.
2. **`totalPower` denominator.** Dart code integrates over the coherence band [0.04, 0.26] only. Design doc described full spectrum (vlf+lf+hf). Different interpretations produce dramatically different scores for the same physiology.
3. **Frequency bonus shape.** Dart code uses triangular falloff (`max(0, 1 - |peakFreq - 0.10| / 0.05)`) — hard zero at ±0.05 Hz of 0.10 Hz, creating a "cliff" for users not breathing at 6 bpm. Design doc described gaussian (`exp(-distance × 5)`).
4. **Six design-doc components missing from the code:** bandwidth penalty, dominance bonus, ZLMA smoothing, rolling-max normalization, auto-adjust toward target, VLF band tracking.

**Documents produced:**
- `project/plans/QUESTIONS/2026-04-08_Coherence_Algorithm_Questions.md` — full write-up with trade-offs, recommendations, and TL;DR table for the algorithm's author
- `project/plans/QUESTIONS/2026-04-08_Coherence_Algorithm_CoverMessage.md` — email-length and Slack-length cover messages pointing at the full doc

## 4. Mandatory Quality Gate

Quality gate is run via `swift build` + `swift test` for now (the project's `quality-gate` CLI is not yet wired in for narbis specifically; it lives upstream in BusinessMath tooling).

| Check | Status |
| :--- | :--- |
| **build** | ✅ zero warnings |
| **test** | ✅ **140 / 140 passing** |
| **safety** | ✅ no `String(format:)`, no `try!`, no `as!`, no `fatalError`, no force unwraps |
| **doc-lint** | ✅ DocC `///` on every public symbol |
| **doc-coverage** | ✅ |

**Test count progression:**
- Start of session: 78 tests (Devices, Signal/RRBuffer, HRVMetrics, StreamingHRVMetrics, FrequencyDomainMetrics)
- After Algorithm: 78 + 23 = 101
- After ConfigStore: 101 + 19 = 120
- After ConfigFetcher: 120 + 20 = **140**

## 5. Project State Updates

- ✅ Three proposals moved from `PROPOSALS/` (or `UPCOMING/`) → `COMPLETED/`:
  - `2026-04-07_AlgorithmLayer-v1.md`
  - `2026-04-07_ConfigStore-v1.md`
  - `2026-04-07_ConfigFetcher-v1.md`
- ✅ Three per-feature session summaries written:
  - `2026-04-07_AlgorithmLayer_v1_Shipped.md`
  - `2026-04-07_ConfigStore_v1_Shipped.md`
  - `2026-04-07_ConfigFetcher_v1_Shipped.md`
- ✅ New `QUESTIONS/` subdirectory created under `project/plans/` for outbound design questions
- ✅ Memory: `project_algorithm_layer_no_businessmath.md` added with index entry in `MEMORY.md`
- ⚠️ `master_plan.md` not updated this session — the architectural shape was already roughly described there; only the OTA-pipeline status moved from "planned" to "shipped." Worth a one-line update next session.

## 6. Next Session Handover (Context Recovery)

### Immediate Starting Point

**Two paths, depending on whether the algorithm author has replied:**

**Path A — Author has replied (or default plan accepted):**
1. Read `project/plans/QUESTIONS/2026-04-08_Coherence_Algorithm_Questions.md` and apply the answers to the design constraints
2. Draft `project/plans/proposals/CoherenceAlgorithm-v1.md` describing the Swift port. Key shape:
   - New struct `CoherenceAlgorithm: HRVAlgorithm` (sibling to `CoreAlgorithm`)
   - New value type `CoherenceResult` mirroring the Dart shape: `coherence`, `peakFrequency`, `breathingRate`, `rmssd`, `lfPower`, `hfPower`, `lfHfRatio`
   - New `CoherenceConfig` value type (sibling to `AlgorithmConfig`) carrying the 7 hyperparameters from `HRVConfig.dart`
   - **Need to extend `FrequencyDomainMetrics`** to expose its raw PSD bins (currently only band-integrated power is public). Additive change, doesn't break existing consumers.
   - Per-window scoring is stateless; smoothing state lives in a separate `StreamingCoherenceEngine` actor (mirrors `StreamingHRVMetrics` split)
   - Add a linear detrend step (slope removal) to the coherence path; existing `FrequencyDomainMetrics` does mean removal only
3. RED → GREEN → REFACTOR → DOCUMENT → VERIFY per the standard workflow

**Path B — Author has not replied and we want to keep moving:**
1. Apply the default plan (match Dart exactly except cubic spline) and proceed as Path A
2. Document in the proposal that any changes to the agreed defaults require re-running tests against the Dart engine's reference outputs

### Pending Tasks

- [ ] Receive answers (or accept default) from coherence algorithm author
- [ ] Draft `CoherenceAlgorithm-v1.md` proposal
- [ ] Extend `FrequencyDomainMetrics` to expose PSD bins (additive)
- [ ] Implement `CoherenceAlgorithm` (per-window, stateless)
- [ ] Implement `StreamingCoherenceEngine` (actor, holds EMA state + buffer)
- [ ] Implement `CoherenceResult` value type
- [ ] Reference-fixture tests: identical inputs through Dart engine and Swift port should produce identical outputs (modulo the cubic-spline deviation)
- [ ] Decide whether to also port `_BusinessMathSmokeTest`-style sanity check that uses real Polar fixtures
- [ ] Update `master_plan.md` to mark Algorithm + OTA as shipped

### Blockers

- **Blocker:** Coherence algorithm author input on the 4 questions in `2026-04-08_Coherence_Algorithm_Questions.md`
- **Dependency:** Author availability
- **Workaround:** Default plan documented in the questions doc and in this handover. If the author doesn't reply within a reasonable window, proceed with the default and update the proposal once we hear back.

The Algorithm layer's `bundledDefault` is still a placeholder (4 hand-picked features with arbitrary weights). It will be **replaced or supplemented** by the coherence algorithm work — they aren't the same shape, so the right move is keeping `CoreAlgorithm` for future trained MLR models and adding `CoherenceAlgorithm` as the second `HRVAlgorithm` impl for the heuristic shipping algorithm.

### Context Loss Warning

- **The Algorithm layer is BusinessMath-free by design.** Inference is direct array arithmetic. Training (MLR) lives server-side. Don't import BusinessMath into `Sources/BioFeedbackKit/Algorithm/`. This is captured in a memory entry.
- **`CoreAlgorithm` is the WRONG shape for the real Narbis coherence algorithm.** Don't try to express the heuristic (peak finding + frequency bonus + EMA smoothing) as `AlgorithmConfig.features/weights`. The protocol exists specifically so a second impl can ship alongside it.
- **`ConfigStore` does NOT know about `bundledDefault`.** The fallback ladder lives at the call site. Don't add a "default fallback" to the store.
- **`ConfigFetcher` does NOT call `ConfigStore.save(_:)`.** They're composed at the call site. Don't add a `fetchAndSave` convenience without a real consumer asking for it.
- **The default on-disk path is `Algorithm/`, NOT `BioFeedbackKit/Algorithm/`.** The library name is deliberately obscured.
- **`CoherenceScore.timestamp` is a `Date`, not a `ContinuousClock.Instant`.** `Date` is `Codable`, `Instant` is not. Don't switch back.
- **Our Swift `FrequencyDomainMetrics` is mathematically more accurate than the Dart `HRVEngine`** (cubic spline vs linear interpolation). When porting, use cubic spline by default. The empirical comparison is documented in the questions doc.
- **The Dart `totalPower` is integrated over the coherence band [0.04, 0.26], NOT the full spectrum.** This may be a bug or a deliberate calibration — the questions doc asks. Don't silently "fix" it to full-spectrum without confirming.

---

## Metrics

| Metric | Before | After |
|--------|--------|-------|
| Test count | 78 | **140** |
| Files in `Sources/BioFeedbackKit/Algorithm/` | 0 | 10 |
| Proposals in `COMPLETED/` for this session | 2 | 5 |
| OTA pipeline status | not started | **shipped (both halves)** |
| Coherence algorithm clarity | unknown | **gap analysis complete; 4 questions outstanding** |

---

## Layer Status After This Session

| Layer | Status |
|---|---|
| Devices (BioSample, MockDevice) | ✅ shipped |
| Signal/RRBuffer + filters | ✅ shipped |
| Signal/HRVMetrics | ✅ shipped |
| Signal/StreamingHRVMetrics | ✅ shipped |
| Signal/FrequencyDomainMetrics | ✅ shipped |
| Algorithm/HRVAlgorithm + CoreAlgorithm (MLR scaffold) | ✅ shipped |
| Algorithm/ConfigStore (file + in-memory) | ✅ shipped |
| Algorithm/ConfigFetcher (URLSession + fake transport) | ✅ shipped |
| Algorithm/CoherenceAlgorithm (real Narbis algorithm) | ⏳ blocked on author input; default plan ready |
| Streaming/CoherenceEngine (stateful wrapper) | ⏳ depends on CoherenceAlgorithm |
| Feedback layer (OpacityController, glasses driver) | ⏳ not started |
| Hardware adapters (PolarH10, AppleWatch) | ⏳ not started |

---

**Session Duration:** Multi-day (2026-04-07 evening → 2026-04-08 day)
**AI Model Used:** Claude Opus 4.6 (1M context)
