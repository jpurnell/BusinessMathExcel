# Design Proposal: CoherenceAlgorithm v1 — HRV Coherence Scoring

**Status:** SHIPPED 2026-04-08
**Date:** 2026-04-08

## Notes from implementation

- All 10 approval-checklist items addressed
- API surface refactored mid-design: `CoherenceScorer` takes pre-computed `FrequencyDomainMetrics` rather than raw `Collection<BioSample>`. Cleaner separation of Signal layer (data) from Algorithm layer (judgment). Cubic-vs-linear interpolation lives in `CoherenceConfig`, not in algorithm variants.
- Result: only **one** v5 algorithm (`CoherenceAlgorithm`), plus `LegacyCoherenceAlgorithm` for the Dart port. The cubic/linear A/B comes from passing different `FrequencyDomainMetrics` instances.
- `ConfigStore` and `ConfigFetcher` were generified to `<Config: ValidatableConfig>` so `CoherenceConfig` could be persisted/fetched the same way as `AlgorithmConfig`. Existing 140 tests stayed green throughout the refactor.
- Static factory renamed from `v5Default` to `bundledDefault` to match `AlgorithmConfig.bundledDefault`.
- **Calibration finding:** A pure 60s 0.10 Hz sine through the v5 §6.3 pipeline produces ~52% coherence, not 100%. Hann main lobe width = 4/T = 0.067 Hz; the ±0.015 Hz integration window only captures ~half. Real-world coherence numbers will be 30–60% for "in the zone" users. Documented in tests.
- **Legacy formula finding:** `LegacyCoherenceAlgorithm` saturates the 0–100 clamp on essentially any clean-peak input due to a dimensional mismatch in `peakRatio = peakPower / band-integrated-total` (units: `1/Hz`). This is faithful to `hrv_engine.dart` — both versions saturate the same way. Worth flagging if the legacy mode is ever exposed to users.
- 184 / 184 tests passing, zero compiler warnings, zero forbidden patterns.
**References:**
- `project/plans/QUESTIONS/2026-04-08_v5_TechReq_Parity_Analysis.md`
- `project/plans/QUESTIONS/2026-04-08_Coherence_Algorithm_Questions.md`
- `narbis-edge-mvp-tech-req-v5.docx` §6.3 (canonical algorithm spec)

---

## 1. Objective

Implement the HRV coherence algorithm in Swift, following v5 §6.3 as
the canonical spec, with three runtime-selectable variants:

| Variant | Spec | Default? |
|---|---|---|
| `CoherenceAlgorithmCubic` | v5 §6.3 + cubic-spline resample | ✅ default |
| `CoherenceAlgorithmLinear` | v5 §6.3 exact, linear resample | A/B reference |
| `LegacyCoherenceAlgorithm` | Faithful Dart `hrv_engine.dart` port | Debug only (no existing users to preserve) |

All three implement a new `CoherenceScorer` protocol. Stateful EMA
smoothing lives in a separate `StreamingCoherenceEngine` actor.

---

## 2. Scope

### 2.1 In scope

| Type | Purpose |
|---|---|
| `CoherenceScorer` (protocol) | Per-window scorer interface; returns `CoherenceResult` |
| `CoherenceResult` (struct) | Rich output: coherence, peakFrequency, breathingRate, rmssd, lfPower, hfPower, lfHfRatio |
| `CoherenceConfig` (struct) | Algorithm hyperparameters (band edges, window half-width, etc.) |
| `CoherenceAlgorithmCubic` (struct) | Default impl: v5 §6.3 with cubic spline |
| `CoherenceAlgorithmLinear` (struct) | v5 §6.3 exact, linear interpolation |
| `LegacyCoherenceAlgorithm` (struct) | Dart `hrv_engine.dart` port |
| `StreamingCoherenceEngine` (actor) | EMA smoothing across windows + 30s warmup gate |

### 2.2 NOT in scope

| Deferred | Why |
|---|---|
| Coherence-to-tint mapping curves | Belongs in app layer (Feedback). Math helpers can come later. |
| Adaptive sensitivity (HIGH/MEDIUM/LOW) | Belongs in app layer (training profile / RF history) |
| Discovery protocol orchestration | App layer state machine |
| Synthetic respiratory-modulated RR generator | Separate small library addition; not blocking |
| RF stability analysis (SD over recent history) | App layer concern; trivial math |

---

## 3. The math (v5 §6.3 canonical)

**Per-window scoring (stateless):**

```
1. Resample irregular RR series to uniform 4 Hz
   - cubic spline (CoherenceAlgorithmCubic)
   - linear (CoherenceAlgorithmLinear, LegacyCoherenceAlgorithm)
2. (Legacy only) Detrend: remove linear regression slope
3. Mean removal (DC kill)
4. Hann window
5. Real FFT → one-sided PSD
6. Find peak in coherence band [0.04, 0.26] Hz → (peakFreq, peakPower)
7. numerator   = integratePSD(peakFreq − 0.015, peakFreq + 0.015)
   denominator = integratePSD(0.04, 0.26)
   coherenceRatio = numerator / denominator
8. coherenceRaw = coherenceRatio × 100, clamped to [0, 100]
```

**Legacy variation (Dart `hrv_engine.dart` formula):**

```
7'. ratio = peakPower / integratePSD(0.04, 0.26)            // single bin
    freqBonus = max(0, 1 - |peakFreq - 0.10| / 0.05)         // triangular
    coherenceRaw = (0.7 × ratio + 0.3 × freqBonus) × 100
```

**Streaming smoothing (stateful, in `StreamingCoherenceEngine`):**

```
smoothed_t = 0.3 × raw_t + 0.7 × smoothed_{t-1}
```

`StreamingCoherenceEngine` maintains:
- The 60s RR buffer
- The last smoothed value (for EMA continuity)
- The 30s warmup gate (don't score until ≥30s of valid RR data)

The per-window scorers (the three `*CoherenceAlgorithm` structs) are
**stateless pure functions** that take a window and return a
`CoherenceResult`. The actor wraps one of them and applies smoothing.

---

## 4. API Surface

### 4.1 Output type

```swift
public struct CoherenceResult: Sendable, Equatable, Codable {
    /// Coherence score in [0, 100]. Raw (unsmoothed) when produced by a
    /// per-window scorer; smoothed when produced by `StreamingCoherenceEngine`.
    public let coherence: Double

    /// Frequency of the dominant peak in the coherence band, in Hz.
    /// Quantized to bin width (~0.0156 Hz at 60s @ 4 Hz padded to 256).
    public let peakFrequency: Double

    /// Estimated breathing rate in breaths per minute = peakFrequency × 60.
    public let breathingRate: Double

    /// Root mean square of successive differences over the same window, in ms.
    public let rmssd: Double

    /// LF band power (0.04–0.15 Hz), in ms².
    public let lfPower: Double

    /// HF band power (0.15–0.40 Hz), in ms².
    public let hfPower: Double

    /// LF/HF ratio. `.infinity` if `hfPower == 0`.
    public let lfHfRatio: Double
}
```

### 4.2 Configuration

```swift
public struct CoherenceConfig: Sendable, Equatable, Codable {
    /// Lower bound of the peak-search band (Hz). Default 0.04.
    public let peakBandLow: Double

    /// Upper bound of the peak-search band (Hz). Default 0.26.
    public let peakBandHigh: Double

    /// Half-width of the integration window around the peak (Hz). Default 0.015.
    public let peakWindowHalfWidth: Double

    /// Resample rate (Hz). Default 4.0.
    public let resampleRate: Double

    /// EMA smoothing factor for `StreamingCoherenceEngine`. Default 0.3.
    public let smoothingAlpha: Double

    /// Minimum window duration (s) before scoring is allowed. Default 30.
    public let minWindowSeconds: Double

    public static let v5Default: CoherenceConfig
}
```

### 4.3 Protocol

```swift
public protocol CoherenceScorer: Sendable {
    var config: CoherenceConfig { get }

    /// Score one window of cleaned RR samples. Pure function — no state.
    /// - Throws: `SignalError.insufficientSamples` or `.windowTooShort`
    ///   if the window doesn't meet the configured minimum.
    func score<C: Collection>(window: C) throws -> CoherenceResult
        where C.Element == BioSample
}
```

### 4.4 Three impls

```swift
public struct CoherenceAlgorithmCubic: CoherenceScorer {
    public let config: CoherenceConfig
    public init(config: CoherenceConfig = .v5Default)
}

public struct CoherenceAlgorithmLinear: CoherenceScorer {
    public let config: CoherenceConfig
    public init(config: CoherenceConfig = .v5Default)
}

public struct LegacyCoherenceAlgorithm: CoherenceScorer {
    public let config: CoherenceConfig
    public init(config: CoherenceConfig = .v5Default)
}
```

### 4.5 Streaming wrapper

```swift
public actor StreamingCoherenceEngine {
    public init(scorer: any CoherenceScorer)

    /// Add a sample. Returns a smoothed `CoherenceResult` once the
    /// 30s warmup is satisfied; returns `nil` until then.
    public func addSample(_ sample: BioSample) -> CoherenceResult?

    /// Reset internal state (buffer + smoothing history).
    public func reset()
}
```

The engine internally maintains an `RRBuffer`-style 60s window and
calls the scorer's `score(window:)` once per second (when the buffer
has changed materially). EMA smoothing wraps the scorer's raw output.

---

## 5. Required changes to `FrequencyDomainMetrics`

To support both cubic and linear resample variants without duplicating
the FFT pipeline, `FrequencyDomainMetrics.init` gains an additive
`interpolation` parameter:

```swift
public enum InterpolationMethod: Sendable {
    case cubicNatural   // current behavior, default
    case linear
}

public init<C: Collection>(
    window: C,
    resampleRate: Double = 4.0,
    interpolation: InterpolationMethod = .cubicNatural,
    fftBackend: any FFTBackend = FFTBackendSelector.selectBackend()
) throws where C.Element == BioSample
```

Default stays `.cubicNatural` so all existing callers and tests are unaffected.

Optional preprocessing parameter for the legacy detrend step:

```swift
public enum SpectralPreprocessing: Sendable {
    case meanRemoval    // current behavior, default
    case linearDetrend  // remove linear regression slope, then mean
}
```

Both new parameters are additive with defaults that match current
behavior. Existing tests stay green.

---

## 6. Constraints & Compliance

- **Concurrency:** All scorers `Sendable` value types. `StreamingCoherenceEngine` is an actor.
- **Cross-platform:** No platform-specific imports. FFT goes through `BusinessMath.FFTBackend` (Accelerate on Darwin, pure Swift fallback). Per the cross-platform mandate.
- **Safety:** No force unwraps, no `try!`, no `String(format:)`. Division-by-zero guarded (`hfPower == 0` → infinity sentinel; `denominator == 0` → coherence 0).
- **Determinism:** Per-window scoring is pure. Same `(window, config)` → same `CoherenceResult`.
- **DocC:** Every public symbol documented with reference to v5 §6.3 or `hrv_engine.dart` source.

---

## 7. Test Strategy

### 7.1 Per-window scorer tests (apply to all 3 impls via parameterization)

1. **Pure 0.10 Hz sine → coherence ≥ 90** (clean coherent fixture)
2. **Pure 0.30 Hz sine → coherence ≤ 20** (outside coherence band; should score low)
3. **White noise → coherence ≤ 20** (no organized peak)
4. **Two-sine LF+HF → moderate coherence with peak in LF**
5. **Constant RR → coherence handled gracefully (0 or NaN-free)**
6. **`peakFrequency` matches the synthetic input frequency within bin width**
7. **`breathingRate` = peakFrequency × 60**
8. **`rmssd`, `lfPower`, `hfPower`, `lfHfRatio` populated correctly**
9. **Window too short throws `windowTooShort`**
10. **Insufficient samples throws `insufficientSamples`**

### 7.2 Cubic-vs-linear comparison tests

11. **Same fixture under cubic and linear produces similar coherence (within ~5%)** — sanity check that both impls work
12. **HF-band fixtures: cubic produces higher coherence than linear** — documents the empirical accuracy advantage
13. **Determinism: scoring the same window twice produces identical results**

### 7.3 Legacy algorithm tests

14. **`LegacyCoherenceAlgorithm` uses single-bin numerator** — verify by constructing a fixture where the windowed-vs-single-bin distinction matters and asserting the legacy version produces a different (lower) coherence than the v5 versions
15. **Frequency bonus: pure 0.10 Hz sine produces higher legacy coherence than pure 0.16 Hz sine** — even controlling for ratio
16. **Detrend: linear-ramp + sine fixture produces same coherence under detrend as flat sine** (the detrend should kill the ramp)

### 7.4 StreamingCoherenceEngine tests

17. **Returns nil before 30s of data**
18. **First valid result equals `scorer.score(window:)` of the buffer at that moment** (no smoothing applied to first sample, since `last` is 0)

   Actually — clarification: standard EMA `smoothed = α×raw + (1-α)×last` with `last = 0` initially gives `smoothed = α×raw = 0.3×raw`, not `raw`. Need to decide: initialize `last = first raw` so the first sample passes through unchanged? Or accept the 0.3×raw startup transient?

   **Open question — see §8.**

19. **Subsequent samples: `result = α×raw + (1−α)×prev`** verify EMA math
20. **`reset()` clears buffer and smoothing**
21. **Replaying a fixture deterministically produces the same final smoothed value**

### 7.5 Reference fixture cross-check

22. **Hand-built RR fixture from a known coherence breath pattern produces a reasonable score** — sanity check end-to-end

### 7.6 New `FrequencyDomainMetrics` parameter tests

23. **`interpolation: .linear` produces different LF/HF values than `.cubicNatural` on the same input** (proves the parameter is wired)
24. **`preprocessing: .linearDetrend` removes a synthetic linear trend** (compare to flat input)
25. **All 3 existing FrequencyDomainMetrics tests still pass with new defaults**

---

## 8. Open Questions

### 8.1 EMA initial value

Standard EMA: `smoothed_t = α × raw_t + (1−α) × smoothed_{t−1}` with
`smoothed_0 = ?`. Three options:

- **`smoothed_0 = 0`** — what the Dart engine does (`_lastCoherence = 0`
  in init). The first reading is `0.3 × raw`, ramping up over ~10
  samples. Clean math but visible startup transient.
- **`smoothed_0 = raw_0`** — first reading equals raw. No transient,
  but the EMA "history" effectively starts at the first reading.
- **No smoothing until we have N readings, then start fresh** — most
  conservative.

**Recommendation:** Match the Dart engine — `smoothed_0 = 0`. The 30s
warmup gate already hides the startup transient from users (no scores
shown until ≥30s of data anyway, so by the time the user sees the
first score it's already 30 EMA-iterations in).

### 8.2 Should `CoherenceScorer` and `HRVAlgorithm` share a parent protocol?

No. They have fundamentally different output shapes and use cases.
`CoreAlgorithm` (HRVAlgorithm) is the MLR scaffolding for future
trained models; `*CoherenceAlgorithm` (CoherenceScorer) is the
heuristic algorithm shipping today. They're cousins, not siblings.
Two protocols, no shared parent.

### 8.3 Where does breath rate come from for non-coherent windows?

When the peak finder returns `(0, 0)` (no peak found in band, e.g. on
constant RR), `peakFrequency = 0` and `breathingRate = 0`. Document
this as "no breath rate detected" rather than synthesizing a value.

### 8.4 `LegacyCoherenceAlgorithm` detrend on/off?

The Dart engine does linear-regression detrend. Should the legacy
Swift port match? **Yes** — faithful port means matching the detrend.
Use the new `preprocessing: .linearDetrend` parameter on
`FrequencyDomainMetrics`.

### 8.5 Where does `CoherenceConfig` get persisted?

Same OTA path as `AlgorithmConfig`? Different store? Or just hardcoded
defaults for v1?

**Recommendation:** Hardcoded `v5Default` for v1. The OTA story for
`CoherenceConfig` is a v2 concern; the `ConfigStore`/`ConfigFetcher`
infrastructure already exists and could be reused, but adding it now
is YAGNI. The defaults are well-defined by v5 §6.3.

---

## 9. Files to Add

| File | Purpose |
|---|---|
| `Sources/BioFeedbackKit/Algorithm/CoherenceResult.swift` | Output value type |
| `Sources/BioFeedbackKit/Algorithm/CoherenceConfig.swift` | Hyperparameters |
| `Sources/BioFeedbackKit/Algorithm/CoherenceScorer.swift` | Protocol |
| `Sources/BioFeedbackKit/Algorithm/CoherenceAlgorithmCubic.swift` | Default impl |
| `Sources/BioFeedbackKit/Algorithm/CoherenceAlgorithmLinear.swift` | v5 exact impl |
| `Sources/BioFeedbackKit/Algorithm/LegacyCoherenceAlgorithm.swift` | Dart port |
| `Sources/BioFeedbackKit/Algorithm/StreamingCoherenceEngine.swift` | Stateful actor |
| `Tests/BioFeedbackKitTests/CoherenceAlgorithmTests.swift` | All tests in one suite |

Plus modifications to:
- `Sources/BioFeedbackKit/Signal/FrequencyDomainMetrics.swift` (add `interpolation` and `preprocessing` parameters; default to current behavior)

---

## 10. Approval Checklist

- [ ] User approves the v1 scope (3 algorithm variants + protocol + streaming engine)
- [ ] User approves the API surface in §4
- [ ] User approves modifying `FrequencyDomainMetrics` to add `interpolation` and `preprocessing` parameters (additive, defaults preserve existing behavior)
- [ ] User approves the new `CoherenceScorer` protocol separate from `HRVAlgorithm`
- [ ] User answers the 5 open questions in §8 (or accepts recommendations)
- [ ] User approves the test strategy
- [ ] User approves writing tests BEFORE implementation
