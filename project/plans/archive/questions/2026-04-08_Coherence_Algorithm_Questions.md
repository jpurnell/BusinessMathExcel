# HRV Coherence Algorithm — Heads-Up Before Swift Port

**Date:** 2026-04-08
**From:** Swift port team (narbis BioFeedbackKit)
**Re:** `narbis-edge-mvp-tech-req-v5.docx` §6.3 + `app/lib/core/domain/hrv/hrv_engine.dart`
**Status:** RESOLVED — all questions answered internally (2026-04-08). No existing users → default everyone to `CoherenceAlgorithmCubic`. Legacy mode is debug/comparison only, not a user-facing fallback. This doc is kept as a record of the decisions made and may still be sent to Devon as a heads-up about the algorithm port shape.

> **Note:** This document supersedes an earlier draft from earlier the same day.
> The earlier draft compared `hrv_engine.dart` to the older
> `HRV_COHERENCE_ADAPTATION.md` design doc and asked you to disambiguate.
> Receiving v5 of the tech req resolved most of those questions; this
> merged version reflects what we've decided internally and surfaces only
> the one item we still want your input on.

---

## TL;DR

We're porting the HRV coherence algorithm into a Swift package
(`BioFeedbackKit`) that will be the math/signal core for the upcoming
Swift-native narbis Edge app (and eventually a Kotlin/Android app via a
shared Swift core). We've **adopted v5 §6.3 as canonical**. The Swift
port will ship **three** coherence algorithm variants behind a single
protocol so the app can pick one at runtime:

| Variant | Spec | Purpose |
|---|---|---|
| **`CoherenceAlgorithmCubic`** (default) | v5 §6.3 exact, **except** cubic-spline resample | Mathematically best — ~10× more accurate in HF on validated sine fixtures |
| **`CoherenceAlgorithmLinear`** | v5 §6.3 exact, linear resample | Matches v5 spec to the letter; A/B comparison against the cubic version |
| **`LegacyCoherenceAlgorithm`** | Faithful port of `hrv_engine.dart` | Continuity for users who've already trained against the shipping Flutter app |

All three implement the same `HRVAlgorithm` protocol. App picks one at
runtime — defaults to cubic; users with prior Dart-engine training history
can opt into legacy.

We have **one open question for you**, in §3 below.

---

## 1. What we found in your source material

Three different specs, all describing "the Narbis coherence algorithm,"
all disagreeing in material ways:

| Step | **v5 doc §6.3 (newest)** | **`hrv_engine.dart` (shipping)** | **Old design doc** |
|---|---|---|---|
| Buffer | 60s | 60s | 60s |
| Min wait | 30s | 60 samples | 60 beats |
| Resample | linear → 4 Hz | linear → 4 Hz | cubic spline → 4 Hz |
| Detrend | not specified | linear regression slope removal | not specified |
| Window | Hanning | Hann | Hann |
| FFT | yes | real, padded to next pow2 | yes |
| Peak band | [0.04, 0.26] Hz | [0.04, 0.26] Hz | [0.04, 0.26] Hz |
| **Numerator** | **window integral over `[peakFreq ± 0.015]` Hz** | **single peak bin** | single bin |
| Denominator | total power in [0.04, 0.26] | total power in [0.04, 0.26] | full spectrum |
| Frequency bonus | none | `(0.7×ratio + 0.3×triangular(peakFreq, 0.10))` | gaussian × bandwidth × dominance |
| Smoothing | EMA α=0.3, 1Hz | EMA α=0.3 | ZLMA |
| Rolling-max norm | not specified | not implemented | yes |

**Our reading:** v5 is the canonical spec. The Dart engine has two
likely-unintended deviations from v5 — single-bin numerator (vs
windowed integral) and the `0.7 × ratio + 0.3 × bonus` formula — that
look like an earlier developer taking shortcuts rather than deliberate
calibration choices. We're treating v5 §6.3 as the source of truth and
shipping the Dart engine port as a continuity option only.

---

## 2. Decisions we've already made internally

You don't need to confirm these — we're proceeding on them. Listing
them so you know what's coming.

### 2.1 v5 §6.3 is canonical

Numerator = `integral(psd, peakFreq - 0.015, peakFreq + 0.015)`.
Denominator = `integral(psd, 0.04, 0.26)`. No frequency bonus. EMA α=0.3
smoothing at 1 Hz update rate. 30 s warmup gate.

### 2.2 Cubic spline is offered alongside linear

Our existing Swift `FrequencyDomainMetrics` pipeline uses cubic spline
interpolation (Kubios HRV standard) for the 4 Hz resample. On validated
sine-wave fixtures, cubic produces ~2.85% HF power error vs ~33% under
linear. The accuracy difference is large and free on iOS via Accelerate.

We didn't want to silently override v5's "linear" specification, so we're
shipping **both**:

- `CoherenceAlgorithmCubic` — the default, cubic spline for the resample
  step, everything else exact v5
- `CoherenceAlgorithmLinear` — exact v5 to the letter

This gives us a clean A/B comparison in the same app under the same
test fixtures, and lets us validate empirically whether the cubic
deviation matters for actual user-facing scores or only matters for the
synthetic fixtures.

### 2.3 Legacy mode exists

`LegacyCoherenceAlgorithm` is a faithful Swift port of `hrv_engine.dart`:

- Linear resample (matches Dart)
- Linear-regression detrend (matches Dart)
- Single-bin numerator (matches Dart's bug-or-shortcut)
- `0.7 × ratio + 0.3 × triangular(peakFreq, 0.10, ±0.05)` formula (matches Dart)
- EMA α=0.3 smoothing
- Same `CoherenceResult` side outputs (breathingRate, rmssd, lf/hf, etc.)

It exists so that any user whose training history was built against the
Dart engine can keep getting the same scores until they actively choose
to switch.

### 2.4 Other library-layer items already shipped

For context — the Swift `BioFeedbackKit` package already covers most of
v5 §6.3 *outside* the coherence math itself:

- 60 s rolling buffer ✅
- Range filter (300–1500 ms) ✅
- Two ectopic-rejection filters (`MedianMalikFilter` and `PercentChangeFilter`),
  both stronger than v5's "consider 20% delta" suggestion ✅
- 4 Hz resample (cubic) ✅
- Hann window ✅
- FFT via Accelerate (vDSP) on Darwin, pure-Swift fallback elsewhere ✅
- LF/HF/VLF band integration (we also compute VLF, which v5 §6.3 omits) ✅
- RMSSD, SDNN, pNN50 ✅
- Streaming variants for time-domain HRV ✅

The remaining work for the coherence algorithm is small: expose PSD
bins from `FrequencyDomainMetrics`, add a peak-finder + windowed-integral
helper, write the three `*CoherenceAlgorithm` variants, and add a
stateful `StreamingCoherenceEngine` actor for the EMA smoothing across
calls.

---

## 3. The one question for you

**Are there existing users who have built up training history against
the shipping Dart engine, whose scores we'd materially disrupt by
switching them to the v5 algorithm?**

Specifically:

- If yes — we'll default new users to `CoherenceAlgorithmCubic` and
  default existing users (those with non-empty session history) to
  `LegacyCoherenceAlgorithm`, with an opt-in path to switch. Their old
  scores stay comparable to their new scores.
- If no — we'll default everyone to `CoherenceAlgorithmCubic` and the
  legacy mode is just a debug/comparison tool, not a user-facing fallback.

The reason this matters: the Dart engine's single-bin numerator and
frequency bonus produce systematically different scores from v5's
windowed-integral pure-ratio formula. A user who was getting "85%
coherence" on a good session in the Flutter app may see "62% coherence"
on the same physiology under v5. That's not a regression — v5 is more
correct — but it can feel like one to a user who was using the score as
a personal benchmark.

If you want, we can also generate a translation table between the two
scales so existing users can mentally calibrate ("your old 85 ≈ your
new 62") without losing their progress narrative. Easy to do once we
have both Swift implementations working side-by-side against the same
RR fixtures.

---

## 4. Other things we noticed but aren't blocking

These are observations, not questions — we'll handle them per the v5
spec unless you say otherwise:

- **Peak frequency quantization.** With 60 s @ 4 Hz padded to 256 points,
  bin width is `4/256 ≈ 0.0156 Hz`. The reported `peakFrequency` is
  therefore quantized to ~0.94 bpm steps. The ±0.015 Hz window numerator
  is roughly ±1 bin wide at this resolution, which means it's almost
  always integrating 3 bins (peak ± 1). Worth noting because it makes
  the `peakFrequency × 60 = breathingRate` value look "blocky" — but
  the coherence score itself is fine.

- **VLF tracking.** v5 §6.3 doesn't compute VLF, but our existing
  `FrequencyDomainMetrics` does. We'll keep VLF available as a side
  output even though the coherence algorithm doesn't use it — costs
  nothing and is useful for telemetry.

- **30 s warmup gate.** v5 says "minimum 30 seconds of valid RR data
  required before first coherence computation." Our existing code checks
  sample count, not wall-clock seconds. We'll add an explicit duration
  check on the coherence path.

- **Synthetic RR generator.** v5 §9 (simulation mode) needs synthetic RR
  intervals with realistic respiratory sinus arrhythmia driven by the
  current pacer rate. We'll add this as a `SyntheticRRSource` in the
  library — useful for tests too. Existing `MockDevice` only plays back
  fixtures.

- **Coherence-to-tint mapping.** v5 §6.4 specifies the math for tinting
  (smooth interpolation between min/max, optional sigmoid curve, adaptive
  sensitivity). The math will live in the library; the BLE side
  (sending `0xA2` brightness commands to the glasses) will live in the
  Swift app's Edge glasses adapter, not the library.

---

## TL;DR for skim

| # | Item | Status |
|---|---|---|
| 1 | v5 §6.3 is canonical | ✅ decided internally |
| 2 | Numerator = ±0.015 Hz window | ✅ matches v5, no question |
| 3 | No frequency bonus | ✅ matches v5, no question |
| 4 | Ship cubic + linear + legacy variants | ✅ decided internally |
| 5 | Default new users to cubic | ✅ decided internally |
| 6 | **Default existing users to legacy or cubic?** | ⚠️ **needs your call** |
| 7 | Cubic deviates from v5's "linear" but is mathematically better | FYI — both versions ship |

The only open question is item 6. Everything else is locked.

Thanks!
