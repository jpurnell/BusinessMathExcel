# Parity Analysis: narbis Edge MVP v5 vs BioFeedbackKit Swift Port

**Date:** 2026-04-08
**Source doc:** `/Users/jpurnell/Downloads/narbis-edge-mvp-tech-req-v5.docx` ("Narbis Edge MVP — Mobile Application Technical Requirements", April 2026, v5.0, by Devon Greco)
**Purpose:** Confirm what BioFeedbackKit already covers, what's app-layer vs library-layer, and how the v5 HRV algorithm spec compares to the shipping Dart engine and our Swift pipeline.

---

## TL;DR

1. **The Swift port targets a different layer than the v5 doc.** The v5 doc is a *whole-app* spec (Flutter, Firebase, BLE, UI, OTA, discovery protocols, screens). BioFeedbackKit is the *signal-processing + algorithm library* that such an app would consume. The Swift narbis app is a separate codebase that doesn't yet exist; this doc clarifies which v5 sections belong in the library and which belong in the future app.
2. **There are now THREE different coherence algorithms in flight:** the v5 spec, the shipping `hrv_engine.dart`, and the design doc `HRV_COHERENCE_ADAPTATION.md`. They all disagree. The v5 spec is the most recent and has Devon's name on it, so it's probably the canonical answer — but we should confirm.
3. **Plan: ship our cubic-spline pipeline as the default (it's measurably more accurate)**, **and** ship a faithful Swift port of the v5 spec as a selectable alternative (`LegacyCoherenceAlgorithm` or similar). Both implement the existing `HRVAlgorithm` protocol.
4. **The four open questions in `2026-04-08_Coherence_Algorithm_Questions.md` remain valid** but the v5 doc answers some of them and contradicts others. See §3 below.

---

## 1. Scope Mapping: what belongs where

The v5 doc specifies a complete Flutter app. BioFeedbackKit is a Swift package that handles the signal-processing and algorithm math. Several v5 sections are app-layer concerns that BioFeedbackKit will *enable* but not *implement*.

| v5 Section | What it specifies | BioFeedbackKit scope? | Status |
|---|---|---|---|
| §1 Executive Summary | Product vision, beachhead market | App layer | n/a |
| §2 Why Flutter/Dart | Tech stack rationale | App layer | n/a (Swift instead) |
| §2.3 Firebase backend | Auth, Firestore, Analytics, Crashlytics | App layer | n/a |
| §3.1 Data Flow | Dual BLE topology | Both — adapter abstractions in lib, concrete adapters in app | ⏳ partial |
| §3.2 Firmware-native breathing | 0xA3 command lifecycle | App layer (BLE adapter) | ⏳ not started |
| §3.3 Tech Stack | Riverpod, Hive, fl_chart | App layer | n/a |
| §4 Polar H10 BLE | Standard HR Service parsing | App layer (Devices/PolarH10Adapter) | ⏳ not started — `MockDevice` exists, real adapter doesn't |
| §5 Edge glasses BLE | Custom GATT, command protocol | App layer (Devices/EdgeGlassesAdapter) | ⏳ not started |
| §5.6 OTA firmware | BLE chunked upload to ESP32 | App layer | ⏳ not started |
| **§6 HRV Coherence Engine** | **The algorithm math** | **BioFeedbackKit core** | **⚠️ see §3 below** |
| §6.1 Overview | Coherence concept | Library docs | ✅ |
| §6.2 Existing validated code | Pointers to Dart modules | Reference only | n/a |
| **§6.3 Signal Processing Pipeline** | **The actual algorithm** | **BioFeedbackKit core** | **⚠️ see §3** |
| §6.4 Coherence-to-tint mapping | Scoring → opacity | App layer (Feedback layer) | ⏳ not started |
| §6.4 Adaptive feedback sensitivity | HIGH/MEDIUM/LOW levels | App layer (training profile) | ⏳ not started |
| §7 Discovery Modes | Lehrer / Fisher / Smart Start protocols | App layer (session orchestration) | ⏳ not started |
| §8 Training Mode | Session timeline, on-screen UI | App layer | ⏳ not started |
| §9 Simulation Mode | Synthetic RR generator | Mostly library — `MockDevice` already exists | ⚠️ partial |
| §10 UI / UX | Screens, design system, settings | App layer | ⏳ not started |
| §11 Target Devices | iOS 14+ / Android 7+ | App layer | n/a (iOS 17+ probably for Swift) |
| §12.1 Performance | <100ms latency, 1Hz coherence | Both — library can hit this trivially | ✅ |
| §12.2 Background | iOS BLE background mode | App layer | n/a |
| §12.3 Error Handling | BLE disconnect/reconnect | App layer | ⏳ not started |
| §12.4 Offline-first | Local cache + sync | App layer | n/a |
| §13 Deliverables | Phase plan | App layer | n/a |

### Summary

**Library-layer items** (in BioFeedbackKit scope, what we should be tracking):
- ✅ Time-domain HRV metrics (RMSSD, SDNN, pNN50) — shipped
- ✅ Frequency-domain metrics (VLF/LF/HF) — shipped
- ✅ Algorithm protocol + scoring scaffold — shipped
- ✅ Config OTA pipeline (store + fetcher) — shipped
- ⚠️ **HRV coherence algorithm** — see §3 below
- ⏳ Streaming variants of the above (StreamingFrequencyDomain, StreamingCoherence)
- ⏳ Device protocol abstractions (BioSample, MockDevice — shipped; real adapters don't belong in the library, only the protocol)

**Hybrid items** (library provides primitives, app composes them):
- §3.1 Data Flow: library provides `Device` protocol; app implements `PolarH10Device` and `EdgeGlassesDevice`
- §9 Simulation Mode: library provides `MockDevice` and synthetic-RR generator helpers; app provides the toggle/UI

**App-layer items** (NOT in BioFeedbackKit scope, would live in a separate Swift app target):
- All BLE concrete adapters (Polar H10, Edge glasses)
- All UI (Connect, Mode Select, Discovery, Training, Results, Settings)
- Firebase / CloudKit / persistence backend
- Discovery protocol orchestration (Lehrer stepped, Fisher sweep, Smart Start state machine)
- Training session state machine
- Adaptive learning system (RF history, sensitivity levels — though the *math* could be in the library)
- OTA glasses firmware updates
- Coherence-to-tint mapping curve (the *math* could be in the library; the *application* lives in the app)

**Open question for the user:** Is the goal to ship a Swift native app that replaces the Flutter app, or to ship BioFeedbackKit as a library that an existing Flutter/iOS hybrid can consume? The answer changes the scope significantly. For now this doc assumes the former (Swift native app needs both library and app code).

---

## 2. BioFeedbackKit Library Status vs v5 Library-Layer Requirements

This is the table that matters for "are we feature-complete for the math/signal layer?"

| v5 Requirement | BioFeedbackKit Status | Notes |
|---|---|---|
| RR rolling buffer (60s) | ✅ shipped | `RRBuffer` |
| RR range filter (300–1500ms) | ✅ shipped | `RangeGate` |
| 20% delta filter (ectopic rejection) | ✅ shipped | `PercentChangeFilter` and `MedianMalikFilter` (we have two algorithms; v5 only specifies one) |
| Resample to uniform 4 Hz | ✅ shipped | Used by `FrequencyDomainMetrics`; **we use cubic spline (Kubios standard), v5 says linear** |
| Hanning window | ✅ shipped | Hann window in `FrequencyDomainMetrics` |
| FFT (real-valued, radix-2) | ✅ shipped | Via `BusinessMath.FFTBackend` (Accelerate/vDSP on Darwin, pure Swift fallback) |
| PSD computation | ✅ shipped | Parseval-correct in BusinessMath; verified in tests |
| LF / HF / VLF band integration | ✅ shipped | `FrequencyDomainMetrics` |
| Peak finding in coherence band [0.04, 0.26] | ❌ not shipped | Need to expose PSD bins from `FrequencyDomainMetrics` (additive) |
| **Coherence ratio = peakWindowPower / bandTotalPower** | ❌ not shipped | New work — `CoherenceAlgorithm` |
| **EMA smoothing α=0.3** | ❌ not shipped | Goes in `StreamingCoherenceEngine` (stateful) |
| RMSSD (real-time) | ✅ shipped | `HRVMetrics.rmssd` |
| SDNN | ✅ shipped | `HRVMetrics.sdnn` |
| pNN50 | ✅ shipped | `HRVMetrics.pnn` (configurable threshold, defaults to 50ms) |
| Poincaré (SD1/SD2) | ❌ not shipped | Mentioned in v5 §6.2 as part of the validated JS pipeline; not in v5 §6.3 mandatory pipeline |
| Sample entropy | ❌ not shipped | Same — listed in §6.2 but not mandatory in §6.3 |
| DFA (Detrended Fluctuation Analysis) | ❌ not shipped | Same |
| Min 30s valid RR before first compute | ⚠️ partial | We require minSamples (4 for HRV, etc.) but not specifically 30s wall-clock — easy add |
| Synthetic RR generator (for sim mode) | ⚠️ partial | `MockDevice` plays back fixtures; doesn't generate respiratory-modulated synthetic RR |
| `Device` protocol for BLE adapters | ✅ shipped | BLE-specific adapters live in app layer |
| Device protocol abstractions consumable by Polar H10 and Edge glasses | ✅ shipped | `BioSample`, `MockDevice` — real adapters are app-layer |
| Coherence-to-tint mapping math | ❌ not shipped | Could be a library helper; v5 mentions "linear, sigmoid, etc. should be tunable" — we already have `OutputTransform` for this exact pattern |

### Library-scope verdict

**BioFeedbackKit covers ~80% of the v5 library-layer math.** The remaining 20% is:

1. **Peak finding + coherence ratio + EMA smoothing** (the actual coherence algorithm) — this is the `CoherenceAlgorithm` work we already scoped
2. **Poincaré / sample entropy / DFA** — listed in v5 §6.2 as part of the broader validated pipeline but NOT in §6.3's mandatory steps. Defer until needed.
3. **Synthetic RR generator with respiratory modulation** — currently `MockDevice` only plays fixtures. v5 §9 wants a synthetic source that responds to a pacer rate. Small addition, useful for tests too.
4. **30s warmup gate** — trivial addition to `CoherenceAlgorithm`'s precondition checks.

Nothing major is missing. Most of the remaining work is composition and the coherence algorithm itself.

---

## 3. The Three Coherence Algorithms

This is the most important finding. There are now three different specifications of "the Narbis coherence algorithm" in the source material, and they disagree.

### 3.1 Side-by-side comparison

| Step | v5 doc §6.3 (newest) | hrv_engine.dart (shipping) | HRV_COHERENCE_ADAPTATION.md (oldest) |
|---|---|---|---|
| Buffer | 60s | 60s | 60s |
| Range filter | 300–1500 ms | not in code | yes |
| Delta filter | "consider 20% delta" | not implemented | not specified |
| Min data before compute | **30 s** | 60 samples (~60s @ 60bpm) | 60 beats |
| Resample | linear → 4 Hz | linear → 4 Hz | **cubic spline** → 4 Hz |
| Detrend | not mentioned | **linear regression slope removal** | not mentioned |
| Window | Hanning | Hann | Hann |
| FFT | yes | real, padded to next pow2 | yes |
| Peak detection band | [0.04, 0.26] Hz | [0.04, 0.26] Hz | [0.04, 0.26] Hz |
| **Coherence numerator** | **power within ±0.015 Hz of peak** (window integral) | `peakPower` (single bin) | `peakPower` |
| **Coherence denominator** | total power in [0.04, 0.26] | total power in [0.04, 0.26] | full spectrum (vlf+lf+hf) |
| **Frequency bonus** | not in v5 | `0.3 × triangular(peakFreq, 0.10, 0.05)` | `gaussian(peakFreq, 0.10)` |
| Combined formula | `coherenceRatio × 100` | `(0.7×ratio + 0.3×bonus) × 100` | `ratio × bandwidth × dominance × 100` |
| Smoothing | EMA α=0.3, 1Hz update | EMA α=0.3 | ZLMA |
| Rolling-max normalization | not specified | not implemented | yes (15s window) |
| Auto-adjust toward target | not specified | not implemented | yes (70%) |
| Output | "0–100 normalized" | clamped 0–100 | clamped 0–100 |
| Side outputs | not specified | breathingRate, rmssd, lfPower, hfPower, lfHfRatio | breathingRate, lf/hf ratio, HR |

### 3.2 Key disagreements

**Numerator definition** (the most consequential difference):
- **v5:** integrate the PSD over `[peakFreq − 0.015, peakFreq + 0.015]` Hz — a small *window* around the peak
- **Dart engine:** just `psd[peakBin]` — a single bin's power
- These produce very different scores. v5's windowed numerator captures the full energy of a slightly-spread peak; the Dart single-bin version severely underweights peaks that aren't perfectly centered on a bin.

**Frequency bonus:**
- **v5:** doesn't have one. Pure ratio.
- **Dart engine:** `(0.7 × ratio + 0.3 × triangular)` — the triangular bonus rewards being near 0.10 Hz
- These produce very different scores at non-resonant frequencies. The v5 version is purer; the Dart version adds an explicit "you're breathing at 6 bpm" reward.

**Resample interpolation:**
- **v5:** linear (matches Dart)
- **Dart engine:** linear
- **Old design doc:** cubic spline (Kubios standard)
- **Our Swift `FrequencyDomainMetrics`:** cubic spline (validated 10× more accurate in HF on sine fixtures)

### 3.3 Which one is canonical?

Best guess: **the v5 doc**, because:
- It's the most recent (April 2026, this conversation)
- It's the formal requirements doc with Devon's name on it
- It's what Devon will hand to a developer to build against
- The Dart engine has a `freqBonus` formula that doesn't appear in any spec — it looks like an undocumented in-engine experiment

Worst case: the v5 doc is what Devon *wishes* the code did, the Dart engine is what *actually shipped*, and athletes have been using the Dart version. In which case porting to v5 would change user-visible scores from what they're used to.

**This is the single most important question to clarify with Devon before we lock anything in.**

### 3.4 How this updates `2026-04-08_Coherence_Algorithm_Questions.md`

The previous questions doc was based on comparing the Dart engine to the older `HRV_COHERENCE_ADAPTATION.md`. The v5 doc gives us a third reference that:

| Q# | Previous question | v5 says | Updated status |
|---|---|---|---|
| 1 | Cubic vs linear resample? | linear | **Still open** — v5 says linear, our Swift port is cubic and demonstrably more accurate. Worth asking if we can override v5 with cubic. |
| 2 | totalPower = coherence-band or full spectrum? | **coherence-band** (matches Dart) | **Resolved** — coherence-band is correct per v5 |
| 3 | Frequency bonus shape? | **no bonus at all** in v5 | **New question** — v5 has no frequency bonus; Dart engine has one. Which is shipping? Should we include it in the Swift port? |
| 4 | 6 missing design-doc components? | v5 also drops bandwidth, dominance, ZLMA, rolling-max, auto-adjust, VLF tracking. Confirms they're not shipping. | **Resolved** — none of these ship in v5 |
| New | Numerator: peak bin or ±0.015 Hz window? | **±0.015 Hz window** | **New question** — Dart engine uses single bin, v5 says window. Almost certainly the v5 version is right (the windowed integral is the textbook coherence definition). The Dart engine looks like a bug. |
| New | Min wait before scoring | 30s wall-clock | **Easy add** to whatever we ship |
| New | Delta filter for ectopics | "consider 20%" | **We already have two ectopic filters**, both better than a fixed 20% delta |

### 3.5 Recommended Swift implementation strategy

Given three disagreeing specs, the cleanest approach:

1. **`CoherenceAlgorithm`** (the default) — implements the v5 spec exactly, **except** uses cubic spline interpolation. Document the cubic-spline deviation as an explicit, justified improvement (with the empirical 10× HF accuracy improvement as the citation).

2. **`LegacyCoherenceAlgorithm`** (selectable alternative) — faithful Swift port of `hrv_engine.dart`. Linear resample, single-bin numerator, frequency bonus, EMA smoothing, detrend. For users who already trained against the Dart engine and want continuity. Document it clearly as "matches the Flutter Edge app (April 2026)."

3. Both implement `HRVAlgorithm` protocol. App picks one at runtime based on user preference or training history. Default new users get the cubic-spline v5 version; existing Flutter Edge users get the legacy version until they actively switch.

4. Down the road, a `LegacyCoherenceAlgorithm.linearResample()` ↔ `cubicResample()` toggle would let us A/B the interpolation method without cloning the whole class. Trivial — interpolation is one line.

This gives us:
- The mathematically better algorithm as default (our Swift version)
- The faithful Dart port as a compatibility option
- A clean A/B story for the cubic vs linear question
- The v5 spec as the canonical reference, with one explicit deviation

**This matches the user's stated preference: "have our better algo and offer the one in the document as an option."**

---

## 4. Updated questions for Devon

The previous questions doc (`2026-04-08_Coherence_Algorithm_Questions.md`) is partially superseded by the v5 doc. Updated set:

1. **Is v5 §6.3 the canonical spec, or is the shipping `hrv_engine.dart` what's actually live with users?** If they disagree, which one should the Swift port match?

2. **The numerator question:** v5 says "power within ±0.015 Hz of peak" (windowed integral), Dart engine says `peakPower` (single bin). Which is intended? (Our read: v5 is right, Dart is a bug.)

3. **The frequency bonus question:** v5 has no bonus, Dart engine has `0.3 × triangular(peakFreq, 0.10)`. Which should we ship? (Our read: v5 is right, the bonus was an undocumented engine experiment.)

4. **Resample interpolation:** v5 says linear. Our Swift `FrequencyDomainMetrics` uses cubic spline (Kubios standard, ~10× more accurate in HF on validated sine fixtures, free on iOS via Accelerate). **Permission to deviate from v5 here?** We'd document it as a justified improvement.

5. **Should we ship a "legacy mode" that matches `hrv_engine.dart` exactly** for users who've already trained against it? This is the user's preferred plan; just confirming it's not stepping on toes.

6. **Will there be a "v6" doc that resolves the v5 ↔ Dart engine drift?** If a reconciled version is coming, we may want to wait for it before locking the legacy port.

---

## 5. Library-layer roadmap implications

If the goal is to support a Swift native narbis Edge app that matches v5's feature set, BioFeedbackKit needs the following work in priority order:

### Already shipped ✅
- Devices, RRBuffer, ectopic filters, HRVMetrics, StreamingHRVMetrics, FrequencyDomainMetrics, Algorithm scaffold, ConfigStore, ConfigFetcher

### Next up (gated on Devon's answers above) ⏳
1. Extend `FrequencyDomainMetrics` to expose PSD bins (additive, doesn't break consumers)
2. `CoherenceAlgorithm` (v5-faithful with cubic-spline deviation) — the default
3. `LegacyCoherenceAlgorithm` (Dart-faithful) — the selectable alternative
4. `StreamingCoherenceEngine` actor — wraps either coherence algorithm with EMA smoothing and the 30s warmup gate
5. Synthetic respiratory-modulated RR generator — useful for v5 §9 simulation mode and our own tests

### Library-layer items not yet started (lower priority) ⏳
6. Coherence-to-tint mapping helper (curve options: linear, sigmoid, custom). The math is small; lives in library, the *application* of it lives in the app
7. RF stability analysis helper (compute SD over recent RF history) — small math util, not blocked on anything
8. Adaptive sensitivity computation helper (rolling avg coherence → HIGH/MEDIUM/LOW level) — small math util

### Out of scope for BioFeedbackKit (app-layer concerns)
- All BLE adapters (Polar H10, Edge glasses), all UI, Firebase/CloudKit integration, OTA, discovery protocol orchestration, training session state machines, screens, settings persistence

---

## 6. Recommendations

### Immediate
1. **Send Devon the updated questions** (§4 of this doc, possibly merged into the existing `2026-04-08_Coherence_Algorithm_Questions.md`). The numerator question and the v5-vs-Dart-engine question are the most important.
2. **Don't write code yet for `CoherenceAlgorithm`.** Wait for at least the numerator answer — it changes the math.
3. **Do extend `FrequencyDomainMetrics` to expose PSD bins now.** This is additive, useful for `CoherenceAlgorithm` regardless of which version we end up shipping, and doesn't depend on any of Devon's answers. Small TDD cycle.

### Short-term (after Devon replies)
4. Draft `CoherenceAlgorithm-v1.md` proposal with both impls (default + legacy) and the cubic-spline deviation documented
5. RED → GREEN → REFACTOR → SHIP

### Medium-term (toward product)
6. Begin scoping the Swift narbis Edge app as a separate target/codebase. BioFeedbackKit becomes its dependency. Start with the Connect screen and Polar H10 adapter — most of the rest follows from there.
7. Hardware adapters (`PolarH10Device`, `EdgeGlassesDevice`) live in the app, not in BioFeedbackKit, but they implement BioFeedbackKit's `Device` protocol.

### Open question for the user (Justin)
- **Are we building a Swift native narbis Edge app**, with BioFeedbackKit as its math/signal core? Or is BioFeedbackKit a standalone library with no specific consumer app yet? The answer changes how aggressively we should pursue the app-layer items in §5.
- **Should we merge the v5 questions into the existing `2026-04-08_Coherence_Algorithm_Questions.md` doc**, or send them as a follow-up? The previous doc went out with assumptions that the v5 doc partially overrides; a merge would be cleaner.

---

## 7. Bottom line

- **Library scope:** ~80% complete vs v5 library-layer requirements. The main gap is the coherence algorithm itself, which we've already scoped and is now blocked on which spec to follow.
- **Algorithm:** Three disagreeing specs in the wild. The v5 doc is most likely canonical. The cleanest path forward is to ship our cubic-spline-based version as the default and a faithful Dart-engine port as the legacy alternative — exactly what the user proposed.
- **App scope:** Most of v5 (BLE, UI, Firebase, discovery protocols, training, settings, OTA) is app-layer work that doesn't belong in BioFeedbackKit. If we're building a Swift native app, that's a separate (large) effort.
- **Next concrete step:** Get Devon's answers on the 6 questions in §4, then unblock the `CoherenceAlgorithm` work.
