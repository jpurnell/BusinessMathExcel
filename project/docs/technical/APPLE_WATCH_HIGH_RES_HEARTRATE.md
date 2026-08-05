# Apple Watch as a High-Resolution Heart Rate Sensor for Biofeedback

**Audience:** Technical stakeholders, clinical advisors, investors evaluating sensor fidelity  
**Date:** 2026-05-04 (revised)  
**Patent:** US 9,521,976 B2 — Claim 5 enumerates "heart rate" as a covered physiologic signal

---

## The Core Claim

The Apple Watch, when running an active HealthKit workout session, provides beat-to-beat heartbeat timestamps — not averaged BPM, but individual inter-beat intervals (RR intervals) suitable for real-time heart rate variability (HRV) analysis and biofeedback. Combined with a purpose-built signal processing pipeline, this data source is sufficient to drive the Narbis coherence-based biofeedback loop.

This document addresses the skepticism directly: how the data is acquired, what its limitations are, how the software compensates, and how it compares to the clinical-grade Polar H10 chest strap.

---

## 1. Two Modes of Heart Rate on Apple Watch

The Apple Watch has two fundamentally different heart rate modes. Conflating them is the source of most skepticism.

### Background Mode (Not Useful for Biofeedback)

- Samples heart rate every ~5–10 seconds
- Delivers averaged BPM via `HKQuantityType.heartRate`
- No beat-to-beat timing information
- Cannot compute HRV metrics (RMSSD, SDNN, coherence)
- This is what the Health app shows

### Workout Mode (The High-Resolution Path)

- Requires an active `HKWorkoutSession`
- Optical sensor runs continuously at elevated sampling rate
- Delivers **individual beat timestamps** via `HKHeartbeatSeriesSample`
- Each beat is reported with sub-second precision (`TimeInterval` offset from series start)
- RR intervals computed by differencing successive beat timestamps
- This is what Narbis uses

The API was introduced in watchOS 6 (WWDC 2019, Session 218) specifically to enable third-party HRV and biofeedback applications. Apple's design intent was explicit: the `HKHeartbeatSeriesQuery` callback includes a `precededByGap` flag indicating when the sensor lost tracking — acknowledging that beat-level data is the goal, not just averaged rate.

**In the Narbis codebase:** `RelayCoordinator` starts a `.mindAndBody` workout on the watch. `HKHealthStoreAdapter` runs an `HKAnchoredObjectQuery` on `HKSeriesType.heartbeat()`, then enumerates each beat via `HKHeartbeatSeriesQuery`. RR intervals are computed as `(beatTime - previousBeatTime) × 1000` milliseconds, filtered to the physiologic range of 300–1500 ms.

---

## 2. The Hardware: PPG vs ECG

### Apple Watch — Photoplethysmography (PPG)

The Apple Watch uses an optical sensor on the wrist:

| Spec | Detail |
|------|--------|
| **Sensor type** | Photoplethysmography (PPG) |
| **Green LEDs (~525 nm)** | Active measurement during workouts; strongly absorbed by hemoglobin |
| **Infrared LEDs (~940 nm)** | Background/resting measurement |
| **Red LEDs (~660 nm)** | SpO2 measurement (Series 6+) |
| **Photodiodes** | Multiple sensors on crystal back detect reflected light |
| **Raw sampling rate** | Not publicly disclosed; Apple states LEDs flash "hundreds of times per second" |
| **Beat timestamp resolution** | ~10 ms (centisecond); PPG pulse peak detection |
| **Sensor generation** | 3rd gen (Series 6–8), 4th gen (Series 9/10, Ultra 2) |

PPG measures blood volume changes in the wrist capillaries. Each heartbeat causes a pulse of blood that changes the light absorption pattern. The watch's signal processing algorithms identify the pulse peaks and report their timestamps.

### Polar H10 — Electrocardiography (ECG)

| Spec | Detail |
|------|--------|
| **Sensor type** | Single-lead ECG via chest strap electrodes |
| **ECG waveform sampling** | 130 Hz (via Polar BLE SDK) |
| **RR interval resolution** | 1/1024 second (~0.977 ms) |
| **RR delivery** | Per-beat via BLE, ~1 second latency |
| **R-peak detection** | QRS complex detection on electrical waveform |
| **Validation** | Equivalent to medical-grade ECG for HRV at rest and during exercise (Schaffarczyk et al., *Sensors* 2022) |

### The Resolution Gap

| Metric | Polar H10 | Apple Watch |
|--------|-----------|-------------|
| **RR interval resolution** | ~1 ms | ~10 ms |
| **Beat detection method** | Electrical R-peak (sharp, unambiguous) | Optical pulse peak (broader, noisier) |
| **Motion resilience** | Chest contact maintained; minimal artifact | Wrist PPG highly susceptible to motion |
| **Data delivery** | Real-time per-beat over BLE | Batched series via HealthKit (variable latency) |
| **Data gaps** | Rare | Sensor-dependent; `precededByGap` flag when tracking lost |

The Polar H10 provides ~10× finer timing resolution. For a resting RMSSD of 60 ms, a ±10 ms jitter from PPG quantization introduces a ~16% error floor on individual measurements.

---

## 3. What the Validation Literature Actually Shows

### Two Studies, Two Labs — But Still a Thin Evidence Base

The published evidence base for Apple Watch HRV validation consists of **two primary studies** from **two independent research groups**:

1. **O'Grady et al. (2024)** — University College Dublin (UCD), Ireland. Validated Apple Watch SDNN against Polar H10 + Kubios HRV. 39 healthy adults, 14-day free-living protocol, 316 paired 5-minute morning Breathe app measurements. Authors: O'Grady, Lambe, Baldwin, Acheson, Doherty.
2. **Bonneval et al. (2025)** — UC San Diego (UCSD), USA. Validated Apple Watch RR intervals, NN intervals, and BPM against Biopac 3-lead ECG at 2000 Hz. 78 healthy adults (ages 20–75), 5 conditions (rest, deep breathing, post-walk, conversation, typing), in-lab controlled protocol. Authors: Bonneval, Wing, Sharp, Tristao Parra, Moran, LaCroix, Godino.

Additionally, **Lambe et al. (2026)** — a living systematic review from the same UCD group as O'Grady — surveyed 82 Apple Watch validation studies across 14 health metrics. Four of five authors overlap with O'Grady. The meta-analysis's HRV sheet contains exactly one row (O'Grady); Bonneval was not included (possibly published after the search window closed).

This is genuine independent corroboration — two labs on two continents — but it is still only two primary studies. Both used the **Breathe app** (not `HKHeartbeatSeriesQuery` workout-mode data), so neither directly validates the pathway Narbis uses. Narbis should be transparent about this.

### Heart Rate (BPM) — Good Agreement, Wide Individual Variance

The Lambe meta-analysis (82 studies, 430,052 participants) provides robust evidence for heart rate accuracy:

| Condition | Mean Bias | Limits of Agreement |
|-----------|-----------|---------------------|
| **All conditions** | -0.27 bpm [95% CI -0.72 to -0.17] | -7.19 to 6.64 bpm |
| **At rest** | 0.21 bpm | -8.14 to 8.56 bpm |
| **During exercise** | -0.63 bpm | -6.86 to 5.60 bpm |

Heart rate from Apple Watch is accurate on average, though the limits of agreement (±7–8 bpm) indicate that individual measurements can diverge meaningfully from criterion methods. Third-generation sensors (Series 6+) showed narrower LoA (-3.68 to 2.59) than earlier generations. Note that 56% of the 82 included studies were rated high risk of bias, and only 14% were low risk.

### HRV (SDNN) — Systematic Underestimation via Apple's Native Algorithm

O'Grady et al. (2024) validated Apple Watch Series 9 and Ultra 2 against Polar H10 + Kubios HRV in 39 healthy adults over 14 days (316 paired measurements, free-living conditions):

| Metric | Finding |
|--------|---------|
| **SDNN mean difference** | Apple Watch underestimates by **-8.31 ms** (95% CI: -11.04 to -5.59, p = 0.025) |
| **SDNN MAPE** | **28.88%** (95% CI: 26.18% to 31.57%) |
| **SDNN MAE** | **20.46 ms** (95% CI: 18.57 to 22.34 ms) |
| **Bland-Altman 95% LoA** | **-53.8 ms to +37.2 ms** |
| **Equivalence test (±10 ms)** | **Failed** — CI extended to -11.04, beyond the margin |
| **RHR mean difference** | **-0.08 bpm** (95% CI: -0.78 to 0.93) |
| **RHR MAPE** | **5.91%** (95% CI: 4.78% to 7.03%) |

### RR Interval Accuracy — Excellent at Rest, Degrades with Activity (Bonneval et al. 2025)

Bonneval et al. validated raw RR intervals and derived metrics from Apple Watch Series 8 against Biopac 3-lead ECG (2000 Hz reference) in 78 healthy adults across five conditions. Data was exported from HealthKit via "Export All Health Data" → `HeartRateVariabilityMetadataList`, which provides beat-to-beat intervals at centisecond resolution.

**Key findings at rest (the condition most relevant to Narbis):**

| Metric | Bias | SD | MAPE | Lin's CCC |
|--------|------|----|------|-----------|
| **RR intervals** | -1.67 ms | 20.77 ms | **1.15%** | **0.991** |
| **NN intervals** | 3.11 ms | 21.33 ms | **31.41%** | 0.737 |
| **BPM** | 0.37 bpm | — | **1.16%** | **0.993** |

**The RR vs NN divergence is the most important finding for Narbis.** Raw beat-to-beat timing (RR intervals) is highly accurate at rest — 1.15% MAPE with near-perfect concordance (CCC 0.991). But NN intervals — the subset remaining after ectopic beat filtering — diverge dramatically (MAPE 31.41%, CCC 0.737). This means Apple's ectopic filtering algorithm and the ECG reference's ectopic filtering algorithm make very different decisions about which beats to exclude. Since Narbis applies its own ectopic filter (MedianMalikFilter, Stage 2 of the pipeline), the raw RR accuracy is the more relevant metric.

**Reliability concerns:**

| Condition | Data failure rate |
|-----------|-------------------|
| Rest | 2.56% |
| Deep breathing | 7.69% |
| Post-walk | 12.82% |
| Conversation | **43.59%** |
| Typing | 25.64% |

The Apple Watch frequently failed to capture data during non-rest conditions. Rest — the condition Narbis uses — had the lowest failure rate, but 2.56% still means roughly 1 in 40 sessions may not yield data.

**Age-related accuracy:** The 70–75 age group produced 73% of RR outliers and 84% of NN outliers despite being a small fraction of participants. PPG accuracy degrades with age, likely due to reduced peripheral blood flow and skin changes.

**Post-walk BPM:** MAPE rises to 6.46% immediately after walking, consistent with residual motion artifact and hemodynamic settling. This confirms that rest is the appropriate condition for PPG-based HRV biofeedback.

### What Both Studies Actually Measured (and Didn't)

Both O'Grady and Bonneval used **Apple's Breathe app** as the watch-side measurement tool. O'Grady had participants perform simultaneous 5-minute morning recordings using Breathe and Kubios HRV (Polar H10), reading SDNN from the Health database. Bonneval used Breathe's 5-minute guided breathing session, exporting the full beat-to-beat data via "Export All Health Data."

This means both studies validated a **proprietary black box**:

```
PPG sensor → [Apple's undocumented peak detection] →
  [Apple's undocumented artifact rejection] →
    [Apple's undocumented SDNN algorithm] →
      Health database SDNN value
```

Apple does not document:
- How the Breathe app's SDNN is computed (window length, overlap, NN vs RR intervals)
- What artifact rejection is applied before SDNN calculation
- Whether the beat timestamps in `HKHeartbeatSeriesQuery` are the same as those used internally for SDNN
- Whether the Breathe app uses a different PPG processing pipeline than workout-mode beat detection

**Narbis uses a fundamentally different pathway:**

```
PPG sensor → HKHeartbeatSeriesQuery (workout mode) →
  [raw beat timestamps] → WatchConnectivity relay →
    [Narbis 6-stage pipeline] → spectral coherence score
```

The -8.31 ms SDNN underestimation could reflect PPG timing jitter (which would also affect our pipeline), Apple's SDNN algorithm being conservative (which would not affect us), or the Breathe app's specific measurement conditions (guided slow breathing vs our free-running workout session). We cannot decompose the error source from the published data.

### The Biofeedback Nuance

For clinical HRV research — comparing population norms, detecting pathology, epidemiological stratification — the Apple Watch's SDNN accuracy is insufficient. O'Grady's equivalence test failed, the MAPE is nearly 29%, and the limits of agreement span 91 ms. Bonneval's NN interval MAPE of 31.41% tells the same story from a different direction.

But for **intra-session biofeedback**, the relevant question is different: when the user's HRV coherence genuinely changes, does the Apple Watch detect that change?

Two findings are encouraging:

1. **O'Grady:** RHR differences did not significantly impact HRV differences (B = 0.36, p = 0.156), suggesting HRV measurement errors are not driven by heart rate errors but by the inherent limitations of PPG timing.
2. **Bonneval:** Raw RR intervals at rest have 1.15% MAPE and CCC 0.991 — near-perfect concordance with ECG. The 31.41% NN MAPE comes from ectopic filtering disagreements, not timing error. Since Narbis applies its own ectopic filter (MedianMalikFilter), the raw RR accuracy is the more relevant metric for our pipeline.

For a biofeedback loop where the user's own score at time T is compared to their own score at time T-1, what matters is **sensitivity to change within a session**, not absolute accuracy across devices. Bonneval's RR data strengthens the case that the raw timing signal is good enough — but within-session change sensitivity has not been directly tested in the literature.

---

## 4. How the Software Compensates

The Narbis signal processing pipeline implements six stages of filtering and compensation between the raw Apple Watch beat stream and the final coherence score. Each stage addresses a specific limitation of PPG-derived data.

### Stage 1: Physiologic Range Gate

**File:** `BioFeedbackKit/Signal/RRBuffer.swift`

```
Valid range: 300–2000 ms (30–200 BPM)
Reject: any RR interval outside this range → nil
```

**What it compensates:** Gross PPG artifacts — dropped beats that appear as abnormally long intervals, or noise spikes that appear as impossibly short intervals. These are more common with PPG than ECG because optical peak detection occasionally locks onto motion artifacts or skips a weak pulse.

**Why it runs first:** The range gate executes *before* the ectopic filter, preventing out-of-range artifacts from corrupting the filter's running state.

### Stage 2: Ectopic Beat Rejection (MedianMalikFilter)

**File:** `BioFeedbackKit/Signal/EctopicFilter.swift`, `MedianMalikFilter`

```
Window size:  5 recent accepted RR intervals
Threshold:    20% deviation from median
Reference:    median(last 5 accepted RRs) — not the previous single beat
Rejection:    does NOT update the window (rejected beats are invisible to future decisions)
```

**Algorithm:**
1. Maintain a sliding window of the last 5 *accepted* RR intervals
2. For each new RR interval, compute `delta = |RR_new - median(window)| / median(window)`
3. If `delta > 0.20`: reject (return nil), do not add to window
4. If `delta ≤ 0.20`: accept, add to window, trim to 5

**What it compensates:** Ectopic beats (premature atrial/ventricular contractions) and PPG-specific artifacts where the optical sensor briefly misidentifies a pulse peak, producing an anomalous short-then-long RR pair.

**Why median, not previous beat:** A simpler filter (compare to the single previous beat) is vulnerable to **artifact chains** — if one bad beat gets through, it shifts the reference and subsequent good beats get rejected. The median of 5 is robust to isolated outliers. This is critical for PPG data where artifacts tend to cluster. The design follows the European Society of Cardiology Task Force guidelines (1996, Circulation 93(5), §3.1–3.2).

### Stage 3: Cubic Spline Resampling (Irregular → Uniform Grid)

**File:** `BioFeedbackKit/Signal/FrequencyDomainMetrics.swift`

```
Method:       Cubic spline interpolation (natural boundary conditions)
Output rate:  4.0 Hz uniform grid
Standard:     Kubios HRV (the research gold standard for HRV software)
```

**What it compensates:** Heart beats are inherently irregular — that's the whole point of HRV. But FFT requires a uniformly-sampled signal. PPG makes this worse because data gaps (flagged by `precededByGap`) create additional irregularity.

**Why cubic, not linear:** Empirical validation in the codebase shows cubic spline interpolation reduces HF band amplitude error from **33% (linear) to 2.85% (cubic)**. Linear interpolation acts as a low-pass filter that attenuates the high-frequency variability that the coherence algorithm depends on. This is a 10× accuracy improvement from a single algorithmic choice.

### Stage 4: Spectral Preprocessing

**File:** `BioFeedbackKit/Signal/FrequencyDomainMetrics.swift`

```
Step 1:  Mean removal (subtract DC component)
Step 2:  Optional linear detrending (removes slow baseline drift)
Step 3:  Hann windowing with noise-equivalent bandwidth correction
```

**What it compensates:**
- **Mean removal:** Prevents the DC component from dominating the spectrum
- **Linear detrending (optional):** PPG hardware exhibits slow baseline drift from temperature changes, sensor repositioning, and vasoconstriction. Removing the linear trend prevents this from contaminating the VLF/LF bands
- **Hann windowing:** Reduces spectral leakage from the finite observation window. The noise-equivalent bandwidth correction recovers the true power that windowing attenuates, per standard practice

### Stage 5: Warmup Gate

**File:** `BioFeedbackKit/Algorithm/StreamingCoherenceEngine.swift`

```
Minimum window:  30 seconds of data before any score is emitted
Buffer size:     60-second rolling window
```

**What it compensates:** The first few seconds of PPG data are the noisiest — the sensor is settling, the user is adjusting the watch, the baseline is unstable. The 30-second warmup ensures the first coherence score presented to the user is computed from a stable, well-populated buffer.

### Stage 6: Exponential Moving Average (EMA) Smoothing

**File:** `BioFeedbackKit/Algorithm/StreamingCoherenceEngine.swift`

```
Formula:       smoothed_t = α × raw_t + (1 − α) × smoothed_{t-1}
Default α:     0.3 (user-adjustable via "Responsive ↔ Smooth" slider)
```

**What it compensates:** Beat-to-beat coherence scores are inherently noisy — even with perfect ECG data, the PSD estimate from a 60-second window has limited frequency resolution. With PPG's additional timing jitter, the raw coherence score fluctuates more than the user's actual physiologic state. EMA smoothing tracks the trend while damping the noise.

**The user controls the tradeoff:** α = 1.0 gives raw (no smoothing, instant response but jittery). α = 0.1 gives heavy smoothing (stable number but slow to respond). The default 0.3 balances responsiveness with stability.

---

## 5. The Complete Pipeline: Raw Heartbeat to Coherence Score

```
Apple Watch PPG Sensor
    │
    │  HKHeartbeatSeriesSample (workout mode)
    │  Individual beat timestamps, ~10 ms resolution
    │  precededByGap flag for lost tracking
    │
    ▼
WatchConnectivity Relay → iPhone
    │
    ▼
┌─────────────────────────────────────────────────────┐
│ STAGE 1: Range Gate                                  │
│ Reject RR < 300 ms or > 2000 ms                     │
│ (eliminates gross artifacts)                         │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│ STAGE 2: MedianMalikFilter                           │
│ Reject if |RR - median(last 5)| / median > 20%      │
│ (eliminates ectopic beats and PPG peak errors)       │
└────────────────────┬────────────────────────────────┘
                     │
                     │  Cleaned RR stream → 60-second rolling buffer
                     │
┌────────────────────▼────────────────────────────────┐
│ STAGE 3: Cubic Spline Resampling                     │
│ Irregular beats → 4.0 Hz uniform grid                │
│ (2.85% HF error vs 33% with linear interpolation)   │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│ STAGE 4: Spectral Preprocessing                      │
│ Mean removal → Hann window → FFT → PSD              │
│ Band integration: LF [0.04–0.15), HF [0.15–0.40)   │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│ STAGE 5: Coherence Scoring                           │
│ Peak power / total band power × 100                  │
│ (warmup gate: no score until ≥ 30s of data)         │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│ STAGE 6: EMA Smoothing                               │
│ smoothed = 0.3 × raw + 0.7 × previous               │
│ (user-adjustable responsiveness)                     │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
              CoherenceResult
         (drives lens opacity feedback)
```

---

## 6. Apple Watch vs Polar H10: Honest Comparison

| Dimension | Polar H10 | Apple Watch | Impact on Biofeedback |
|-----------|-----------|-------------|----------------------|
| **RR resolution** | ~1 ms | ~10 ms | Apple Watch has higher noise floor; compensated by EMA smoothing |
| **Motion tolerance** | Excellent (chest contact) | Poor (wrist PPG) | Narbis sessions are seated/resting, minimizing this |
| **Data gaps** | Rare | Occasional; flagged by `precededByGap` | Gaps break continuity; cubic spline bridges short gaps |
| **Delivery latency** | Per-beat, ~1s | Batched, variable | Slightly delayed feedback; acceptable for ~1 Hz update rate |
| **Wearability** | Chest strap (less convenient) | Already on wrist | Dramatically lower friction for daily use |
| **Setup** | Wet electrodes, position strap | Already wearing it | Zero-effort for existing Apple Watch users |
| **HRV accuracy** | Research-grade reference | SDNN underestimates by ~8 ms (native); raw RR 1.15% MAPE at rest (Bonneval); third-party pipeline untested | Relative trends likely preserved; absolute values less reliable |
| **Coherence sensitivity** | Gold standard | Sufficient for intra-session feedback (theoretical; not yet validated) | User's own baseline is the reference, not population norms |

### When to Use Which

**Polar H10:** Clinical validation studies, research protocols requiring SDNN/RMSSD accuracy within ±5 ms, users who need maximum signal quality, professional biofeedback practitioners. The Polar H10's equivalence to medical-grade ECG for all linear HRV metrics is well-established (Schaffarczyk et al. 2022).

**Apple Watch:** Daily consumer biofeedback, habit formation, users who won't wear a chest strap, initial product adoption before graduating to dedicated hardware. The iOS app supports both — the `BiofeedbackDevice` protocol abstracts the input source, so the coherence pipeline is identical regardless of sensor.

### What We Don't Know Yet — and the Validation Opportunity

Bonneval's RR interval data (1.15% MAPE at rest, CCC 0.991) is encouraging for Narbis — it suggests the raw beat timing is excellent when the user is still. But three specific gaps remain, each of which Narbis is positioned to address:

**Gap 1: No validation of `HKHeartbeatSeriesQuery` beat timestamps during a workout session.**
Both O'Grady and Bonneval used the Breathe app. Bonneval exported beat-to-beat data from the Health database — the closest to raw timestamps — but the Breathe app may use a different PPG processing pipeline than workout-mode recording. No study has validated the beat timestamps that third-party apps receive via `HKHeartbeatSeriesQuery` during an active `HKWorkoutSession`. These may or may not match the accuracy Bonneval measured.

**Gap 2: No validation of spectral coherence from wrist PPG.**
Both studies report time-domain metrics (SDNN, RMSSD, RR accuracy). Spectral coherence — the ratio of peak power to total power in the LF band — is a different metric with different sensitivity to timing jitter. Bonneval's 1.15% RR MAPE suggests the raw timing is good enough, but no one has verified that spectral coherence computed from PPG-derived RR intervals matches ECG-derived coherence.

**Gap 3: No within-session change sensitivity validation.**
The biofeedback use case does not require absolute accuracy — it requires that real changes in the user's physiology produce detectable changes in the score. Bonneval showed excellent concordance for aggregate RR intervals, but neither study measured responsiveness to within-session changes.

**The opportunity:** Narbis already has the infrastructure to close all three gaps simultaneously. The iOS app runs both Apple Watch (via WatchConnectivity relay) and Polar H10 (via BLE) through the identical `BiofeedbackDevice → StreamingCoherenceEngine` pipeline. A validation study protocol would be:

1. Record simultaneously from both devices during 15-minute biofeedback sessions
2. Compare raw RR intervals (Gap 1), spectral coherence scores (Gap 2), and within-session coherence trajectories (Gap 3)
3. Use Bland-Altman analysis following the same Tipton & Shuster methodology as Lambe et al.

This would produce the **third** Apple Watch HRV validation study in the literature and the **first** to validate raw workout-mode beat timestamps for real-time spectral coherence biofeedback. Given that the Lambe meta-analysis is a living review updated yearly, a Narbis validation study would be incorporated into its next update — providing visibility within the leading research framework.

---

## 7. Key References

### Primary Validation Studies

1. O'Grady B, Lambe R, Baldwin M, Acheson T, Doherty C. "The Validity of Apple Watch Series 9 and Ultra 2 for Serial Measurements of Heart Rate Variability and Resting Heart Rate." *Sensors* 24(19):6220, 2024. DOI: 10.3390/s24196220
   - **Lab:** University College Dublin (UCD), Ireland.
   - **What it validates:** Apple's native SDNN output (via Breathe app, read from Health database) vs Polar H10 + Kubios HRV. Free-living, 14-day protocol, 39 healthy adults, 316 paired 5-minute morning measurements.
   - **Key finding:** SDNN underestimated by 8.31 ms (MAPE 28.88%). RHR accurate (-0.08 bpm, MAPE 5.91%). Equivalence within ±10 ms not achieved.
   - **Limitation for Narbis:** Validates Apple's proprietary end-to-end SDNN algorithm, not the raw beat timestamps from `HKHeartbeatSeriesQuery` that third-party apps use. The Breathe app's SDNN computation is undocumented — we cannot determine how much of the -8.31 ms bias originates from PPG hardware timing vs Apple's software processing.

2. Bonneval B, Wing D, Sharp E, Tristao Parra I, Moran K, LaCroix AZ, Godino JG. "Assessment of Heart Rate, Heart Rate Variability, and Inter-beat Interval Measured with Apple Watch in Comparison with a Reference Device: A Cross-Sectional Validation Study in Free-Living Conditions." *Sensors* 25(8):2380, 2025. DOI: 10.3390/s25082380. PMID: 40285070.
   - **Lab:** UC San Diego (UCSD), USA — independent from the UCD group.
   - **What it validates:** Raw RR intervals, NN intervals, and BPM from Apple Watch Series 8 (via Breathe app, exported via "Export All Health Data" → `HeartRateVariabilityMetadataList`) vs Biopac 3-lead ECG at 2000 Hz. In-lab protocol, 78 healthy adults (ages 20–75), 5 conditions (rest, deep breathing, post-walk rest, conversation, typing).
   - **Key finding for Narbis:** RR intervals at rest: bias -1.67 ms, MAPE 1.15%, Lin's CCC 0.991. NN intervals at rest: MAPE 31.41%, CCC 0.737 — the divergence comes from ectopic filtering disagreements, not raw timing error. Since Narbis applies its own ectopic filter (MedianMalikFilter), the raw RR accuracy is the relevant metric.
   - **Reliability concern:** Apple Watch failed to capture data in 2.56% of rest sessions, rising to 43.59% during conversation. The 70–75 age group produced 73% of RR outliers and 84% of NN outliers.
   - **Limitation for Narbis:** Also uses the Breathe app, not `HKHeartbeatSeriesQuery` in workout mode. The centisecond-resolution exported data may come from the same underlying beat timestamps Narbis uses, but this has not been confirmed.

### Systematic Review (UCD Research Group)

3. Lambe R, Baldwin M, O'Grady B, Schumann M, Caulfield B, Doherty C. "The accuracy of Apple Watch measurements: a living systematic review and meta-analysis." *npj Digital Medicine* 9:63, 2026. DOI: 10.1038/s41746-025-02238-1
   - Four of five authors overlap with O'Grady et al. — same research group, not independent.
   - **What it covers:** 82 studies, 430,052 participants, 14 health metrics from Apple Watch Series 1 through Series 9/Ultra 2. Analysis code publicly available at github.com/rorylambe/applewatch-systematicreview.
   - **Key finding for HR:** Pooled mean bias -0.27 bpm (LoA -7.19 to 6.64). Third-gen sensors show narrower LoA (-3.68 to 2.59).
   - **Key finding for HRV:** Only 1 study (O'Grady et al.) included — Bonneval not in the dataset (likely published after the search window closed). HRV remains a major gap in the meta-analysis.
   - **56% of included studies rated high risk of bias.** Designed as a living review with yearly updates — Bonneval should appear in the next update.

### Polar H10 Reference Standard

4. Schaffarczyk M, Rogers B, Reer R, Gronwald T. "Validity of the Polar H10 Sensor for Heart Rate Variability Analysis during Resting State and Incremental Exercise in Recreational Men and Women." *Sensors* 22(17):6536, 2022. DOI: 10.3390/s22176536
   - Establishes Polar H10 as equivalent to medical-grade ECG for HRV analysis at rest and during incremental exercise.

### Standards

5. Task Force of ESC/NASPE. "Heart rate variability: Standards of measurement, physiological interpretation, and clinical use." *Circulation* 93(5):1043–1065, 1996.

### Apple Documentation

6. Apple. "Heart Rate, Calorimetry, and Activity on Apple Watch." White paper, November 2024.

7. Apple. `HKHeartbeatSeriesQuery` documentation. developer.apple.com/documentation/healthkit/hkheartbeatseriesquery

8. Apple. WWDC 2019 Session 218: "Exploring New Data Representations in HealthKit."

### Patent

9. Greco D. US Patent 9,521,976 B2. "Method and Apparatus for Encouraging Physiological Change Through Physiological Control of Wearable Auditory and Visual Interruption Device." 2016. Claim 5 covers heart rate as a physiologic signal source.
