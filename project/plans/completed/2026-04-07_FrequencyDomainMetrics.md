# Design Proposal: Frequency-Domain HRV Metrics (LF/HF)

**Status:** APPROVED v3 — ready for RED phase

**Cross-repo dependencies (all SHIPPED):**
- **BusinessMath v2.1.1** — `powerSpectralDensity(_:sampleRate:)` + Accelerate 4× fix
- **BusinessMath v2.1.2** — `Vector1D`, `Interpolator` protocol, `CubicSplineInterpolator(boundary: .natural)` (Kubios HRV standard)
- **BusinessMath v2.1.3** + **v2.1.4** — hygiene cleanups
- **narbis `Package.swift`** now depends on `from: "2.1.4"`. 58/58 existing tests pass (55 prior + 3 BusinessMath integration smoke tests).

**Revision history:**
- v1 (2026-04-06): initial draft
- v2 (2026-04-06): user feedback — add VLF, protocol-based interpolation/windowing, injectable FFT backend, depend on BusinessMath upstream PSD method, keep streaming separate
- **v3 (2026-04-07):** simplified per upstream interpolation module shipping. Drop the local `InterpolationStrategy` protocol and `LinearInterpolation` default — use `BusinessMath.CubicSplineInterpolator(boundary: .natural)` directly. Drop the local `WindowFunction` protocol — hardcode Hann window inline as a private helper (Hann is the universal HRV standard; no compelling case for alternatives in this domain; future window choice is BioFeedbackKit v2 work). Net: smaller public API surface, fewer types to design and test, less BioFeedbackKit code, more value flowing from upstream. Same physiological behavior, same accuracy, same outputs.

---

## 1. Objective

Compute frequency-domain heart rate variability metrics — LF power, HF power,
and LF/HF ratio — from a window of cleaned RR-interval samples. This closes
out the Signal layer's metric set and gives the Algorithm layer the full
picture (time-domain + frequency-domain) it needs to score coherence state.

**Master Plan Reference:** Phase 1 — Signal Pipeline (the last leaf).

**Reference standard:** Task Force of the European Society of Cardiology and
the North American Society of Pacing and Electrophysiology (1996), *Heart
rate variability: Standards of measurement, physiological interpretation, and
clinical use*, Circulation 93(5), §3.2 Frequency Domain Methods. The same
paper that defined RMSSD/SDNN/pNN50 for us in the previous proposal also
defines the LF and HF bands and their interpretation.

---

## 2. Proposed Architecture

**New Files:**
- `Sources/BioFeedbackKit/Signal/FrequencyDomainMetrics.swift` (the value type + initializer + private Hann window helper)
- `Tests/BioFeedbackKitTests/FrequencyDomainMetricsTests.swift`

**Modified files:**
- `Sources/BioFeedbackKit/Signal/SignalError.swift` — add `windowTooShort(requiredSeconds:gotSeconds:)` and `nonMonotonicTimestamps`

**Module placement:** Same `Signal/` directory as `HRVMetrics`.

**v3 simplification (vs v2):** the local `InterpolationStrategy` and
`WindowFunction` protocols and their default implementations are GONE.
All resampling now goes through `BusinessMath.CubicSplineInterpolator`
with the natural boundary condition (Kubios HRV standard). Window
function is hardcoded to Hann inside `FrequencyDomainMetrics.swift` as a
private helper — Hann is the universal HRV standard and there's no
compelling case for alternatives in this domain. Future window-choice
flexibility (if anyone ever asks) is BioFeedbackKit v2 work via an
additive overload, same pattern BusinessMath used for
`generateRandomReturns(count:mean:stdDev:using:)` in v2.1.4.

Validation playground at `project/plans/upcoming/FrequencyDomain-Playground.swift`
already exists and is verified — it uses linear interpolation in v1 and
cubic spline in v2 (added during the BusinessMath upstream investigation).
Cubic spline reduced HF amplitude error from 33% to 2.85% on the 1 Hz
fixtures. Those numbers are the empirical justification for v3 hardcoding
cubic spline.

---

## 3. API Surface

### Removed in v3

The `InterpolationStrategy` protocol and `WindowFunction` protocol that
v2 specified are GONE from BioFeedbackKit. Cubic spline interpolation
now lives in BusinessMath (`CubicSplineInterpolator`); Hann windowing is
a private helper inside `FrequencyDomainMetrics.swift`.

This makes the public surface meaningfully smaller:
- 3 protocols → 0 protocols
- 2 default implementations → 0 default implementations
- 6 source files → 1 source file
- 6 test files → 1 test file

### WindowFunction protocol

```swift
### FrequencyDomainMetrics

```swift
import BusinessMath

public struct FrequencyDomainMetrics: Sendable, Equatable {

    /// Number of input BioSamples that fed into the computation.
    public let inputSampleCount: Int

    /// Number of samples after resampling onto the uniform grid.
    public let resampledSampleCount: Int

    /// Time span covered by the input samples (last.timestamp − first.timestamp).
    public let windowDuration: Duration

    /// Resampling rate in Hz.
    public let resampleRate: Double

    /// Power in the VLF band (0.003–0.04 Hz), in ms². `nil` when the input
    /// window is shorter than 333 seconds (1 / 0.003 Hz, the VLF resolution
    /// floor). Sessions ≥ 5.5 minutes will populate this; shorter windows
    /// physically cannot resolve VLF and report `nil` rather than a noisy value.
    public let vlfPower: Double?

    /// Power in the LF band (0.04–0.15 Hz), in ms².
    public let lfPower: Double

    /// Power in the HF band (0.15–0.40 Hz), in ms².
    public let hfPower: Double

    /// Total power across all reported bands (LF + HF, plus VLF if present), in ms².
    public let totalPower: Double

    /// LF/HF ratio. Returns `.infinity` if `hfPower == 0`.
    public let lfHfRatio: Double

    /// Normalized LF power = lfPower / (lfPower + hfPower). 0...1.
    public let lfNormalized: Double

    /// Normalized HF power = hfPower / (lfPower + hfPower). 0...1.
    public let hfNormalized: Double

    /// Computes frequency-domain HRV metrics from a window of samples.
    ///
    /// Pipeline:
    /// 1. Convert each `BioSample` to a `(time, rrInterval)` pair using
    ///    `BioSample.timestamp` for the time axis (seconds from the first
    ///    sample's timestamp).
    /// 2. Build a `BusinessMath.CubicSplineInterpolator` over the irregular
    ///    series with the **natural** boundary condition (Kubios HRV standard).
    /// 3. Sample the spline at uniform `resampleRate` Hz from the first
    ///    timestamp to the last to produce a uniform-grid signal.
    /// 4. Subtract the mean.
    /// 5. Apply a Hann window (private helper inside this file).
    /// 6. Compute one-sided PSD via `fftBackend.powerSpectralDensity(_:sampleRate:)`,
    ///    compensating for the Hann window's noise-equivalent bandwidth.
    /// 7. Integrate the PSD over VLF (if window ≥ 333 s), LF, and HF bands.
    ///
    /// **Why cubic spline (not linear):** the validation playground at
    /// `project/plans/upcoming/FrequencyDomain-Playground.swift`
    /// empirically showed cubic spline reduces HF amplitude error from 33%
    /// (linear) to 2.85% on the 1 Hz HRV fixtures. Cubic spline with the
    /// natural boundary condition is also the Kubios HRV standard. Future
    /// flexibility (PCHIP, Akima, etc.) could be added via an additive
    /// overload in BioFeedbackKit v2 if anyone asks; the underlying
    /// BusinessMath methods are all available.
    ///
    /// **Why Hann (hardcoded):** Hann is the universal HRV standard for
    /// frequency-domain analysis. There's no compelling case for alternatives
    /// in this domain, so it lives as a private helper inside this file.
    /// Future window-function flexibility would also be a v2 additive overload.
    ///
    /// - Parameters:
    ///   - window: Cleaned RR samples. Must span at least 25 seconds (the
    ///     reciprocal of the LF lower bound, 0.04 Hz) and contain at least
    ///     4 samples. To populate `vlfPower`, the span must be ≥ 333 seconds.
    ///   - resampleRate: Target uniform sample rate in Hz. Defaults to 4.0,
    ///     the standard for HRV frequency analysis.
    ///   - fftBackend: FFT implementation. Defaults to
    ///     `FFTBackendSelector.selectBackend()`, which picks vDSP on Darwin
    ///     and pure Swift everywhere else.
    /// - Throws:
    ///   - `SignalError.insufficientSamples` if fewer than 4 samples.
    ///   - `SignalError.windowTooShort` if the input span is < 25 seconds.
    ///   - `SignalError.nonMonotonicTimestamps` if timestamps aren't strictly increasing.
    public init<C: Collection>(
        window: C,
        resampleRate: Double = 4.0,
        fftBackend: any FFTBackend = FFTBackendSelector.selectBackend()
    ) throws where C.Element == BioSample
}
```

**New error cases** (added to `SignalError`):

```swift
public enum SignalError: Error, Sendable, Equatable {
    case insufficientSamples(required: Int, got: Int)
    case windowTooShort(requiredSeconds: Double, gotSeconds: Double)         // NEW in v3
    case nonMonotonicTimestamps                                              // NEW in v3
}
```

**Why `FrequencyDomainMetrics` is still `Sendable, Equatable`:** it stores
only the output fields (all `Double`/`Double?`/`Int`/`Duration`, all
`Sendable`/`Equatable`). The `fftBackend` parameter is consumed at
initialization time and discarded. The cubic spline is constructed and
used internally, never stored.

---

## 4. The hairy bits — surfaced upfront

### 4.1 Resampling strategy

RR intervals are irregularly spaced (one value per beat). FFT requires uniform
sampling. Standard practice in HRV analysis:

- Treat each BioSample as a `(timestamp, rrInterval)` data point.
- Build a continuous function via cubic spline interpolation with the
  natural boundary condition.
- Sample that function uniformly at `resampleRate` Hz starting at the first
  timestamp and ending at the last.

**Decision (v3): cubic spline via `BusinessMath.CubicSplineInterpolator`
with `.natural` boundary condition.**

This is the Kubios HRV standard and is the recommendation of the 1996
Task Force paper. It's also empirically justified — the validation
playground at `project/plans/upcoming/FrequencyDomain-Playground.swift`
shows cubic spline reduces HF amplitude error from 33% (linear) to 2.85%
on the 1 Hz HRV fixtures, with LF and VLF errors essentially at machine
precision (0.05% and 0.001% respectively).

**Why not the local protocol from v2:** when v2 was written, BusinessMath
didn't have an interpolation module. The local `InterpolationStrategy`
protocol was a placeholder for the missing upstream functionality. As of
BusinessMath v2.1.2 (shipped 2026-04-07) the upstream module exists with
all 10 1D interpolation methods including the cubic spline we want, so
the local protocol is redundant. v3 deletes it and uses the upstream
type directly.

**Implementation sketch:**

```swift
import BusinessMath

// Inside FrequencyDomainMetrics.init:
let pairs = window.map { sample -> (Double, Double) in
    let secondsFromStart = Double(
        Duration(sample.timestamp - window.first!.timestamp).components.seconds
    ) + ... // nanoseconds bit
    return (secondsFromStart, sample.rrInterval)
}
let xs = pairs.map { $0.0 }
let ys = pairs.map { $0.1 }
let spline = try CubicSplineInterpolator(xs: xs, ys: ys, boundary: .natural)

// Sample at uniform 4 Hz grid from t=0 to t=lastTimestamp
let duration = xs.last! - xs.first!
let nResampled = Int(floor(duration * resampleRate)) + 1
let dt = 1.0 / resampleRate
let resampled = (0..<nResampled).map { i in spline(Double(i) * dt) }
```

(Real implementation will guard the timestamp arithmetic, validate
inputs, etc. The above is just to show how `BusinessMath.CubicSplineInterpolator`
slots in.)

### 4.2 Detrending

Subtract the mean from the resampled signal before windowing. The mean is the
DC component and would dominate the spectrum if left in. For v1 we do **only
mean removal** — not linear detrending. Mean removal is sufficient when the
window is short enough that the underlying RR mean is stable.

### 4.3 Windowing

Apply a **Hann window** to reduce spectral leakage:
```
w[n] = 0.5 * (1 - cos(2π·n / (N-1)))    for n = 0..N-1
```

The Hann window attenuates signal energy. We compensate by dividing the final
power spectrum by the window's "noise bandwidth correction factor":
```
windowPower = Σ w[n]²
correction = windowPower / N
```

Power values must be divided by `correction` to recover the true signal power.

**Implementation (v3):** the Hann window is a private helper inside
`FrequencyDomainMetrics.swift` — about 5 lines of code, no abstraction
layer. Hann is the universal HRV standard; if anyone ever needs Hamming
or Blackman the right answer is a BioFeedbackKit v2 additive overload,
not a protocol with one impl.

### 4.4 Normalization to physical units (ms²)

**BusinessMath's `powerSpectralDensity(_:sampleRate:)` (v2.1.1) handles
all the gnarly normalization** — one-sided PSD with correct M-vs-N (unpadded
length) normalization, DC and Nyquist bin handling, Parseval correctness
verified at machine precision in BusinessMath's own test suite.

BioFeedbackKit only needs to:
1. Apply the window-function compensation factor (the PSD method does NOT
   know about windowing — that's the caller's job).
2. Sum PSD bins over each band, multiply by `Δf` to integrate.

```swift
// Pseudo-code inside FrequencyDomainMetrics.init
import BusinessMath

let resampled = /* via CubicSplineInterpolator — see §4.1 */
let mean = resampled.reduce(0, +) / Double(resampled.count)
let zeroMean = resampled.map { $0 - mean }

// Hann window (private helper)
let n = zeroMean.count
let window = (0..<n).map { i in
    0.5 * (1.0 - cos(2.0 * .pi * Double(i) / Double(n - 1)))
}
let windowed = zip(zeroMean, window).map(*)
let windowPower = window.reduce(0) { $0 + $1 * $1 } / Double(n)

// BusinessMath upstream call — returns one-sided PSD in (ms)²/Hz
let psd = fftBackend.powerSpectralDensity(windowed, sampleRate: resampleRate)
let deltaF = resampleRate / Double((psd.count - 1) * 2)

// Compensate for windowing and integrate
func bandPower(low: Double, high: Double) -> Double {
    var p = 0.0
    for (k, value) in psd.enumerated() {
        let f = Double(k) * deltaF
        if f >= low && f < high {
            p += value
        }
    }
    return (p * deltaF) / windowPower
}
```

This is much smaller than the v1 sketch because all the FFT, padding,
DC/Nyquist, and PSD-normalization concerns live in BusinessMath where
they're tested in isolation against Parseval's theorem.

### 4.5 Band edge bin assignment

When a frequency bin's center falls exactly on a band boundary (e.g. exactly
0.15 Hz between LF and HF), which band does it belong to? Convention used here:
- Bin belongs to band `[lo, hi)` if `lo ≤ bin_freq < hi`
- VLF: `0.003 ≤ f < 0.04`
- LF: `0.04 ≤ f < 0.15`
- HF: `0.15 ≤ f < 0.40`

A bin at exactly 0.15 Hz goes to HF. A bin at exactly 0.04 Hz goes to LF. A
bin at exactly 0.003 Hz goes to VLF. Documented in DocC.

### 4.6 Minimum window length & VLF eligibility

There are two distinct thresholds:

| Threshold | Value | What it gates |
|---|---|---|
| **Hard floor** | 25 s | The lowest frequency the operator computes at all (LF lower bound = 0.04 Hz, so `1/0.04 = 25 s`). Below this, throw `windowTooShort`. |
| **VLF eligibility** | 333 s | Required to resolve the VLF lower bound (0.003 Hz). Below this, `vlfPower = nil`. The call still succeeds. |

Documented that windows of < 5 minutes are noisy for LF/HF and the 1996 Task
Force recommends 5 minutes for short-term LF/HF analysis. For meaningful VLF,
the literature recommends ≥ 5 minutes minimum, and ideally much longer.

This two-threshold design lets the operator be useful across a wide range of
window sizes while never silently producing meaningless VLF values.

### 4.7 Minimum sample count

After resampling at `resampleRate` Hz over a window of duration `T` seconds,
we get `floor(T * resampleRate) + 1` samples. For `T = 25s` and `fs = 4 Hz`,
that's 101 samples, padded to 128 for FFT. Plenty of bins.

The input must contain at least **4 samples** to make linear interpolation
sensible. Fewer than 4 throws `insufficientSamples`.

---

## 5. Constraints & Compliance

- **Concurrency:** `FrequencyDomainMetrics` is an immutable Sendable value type.
- **Determinism:** Pure function of input. No clocks, no I/O.
- **Safety:** No force unwraps. Division-by-zero guarded in normalization (HF=0 → ratio = .infinity, documented). Resampling guards against zero or non-monotonic timestamps.
- **Generics:** Generic over `Collection<BioSample>` (matches HRVMetrics).
- **Swift 6:** Strict concurrency compliant.

---

## 6. Backend Abstraction

Uses BusinessMath's existing FFT backend protocol via the public
`fftBackend:` parameter. `FFTBackendSelector.selectBackend()` is the
default and chooses vDSP on Darwin (fast) and pure Swift everywhere
else (portable). Users can inject a specific backend for tests or
specialized cases.

---

## 7. Dependencies

**Internal:**
- `Devices/BioSample.swift`
- `Signal/SignalError.swift` (extending with two new cases — added in v3)

**External (BusinessMath ≥ 2.1.4 — all SHIPPED):**
- `FFTBackend` protocol + `FFTBackendSelector.selectBackend()` (v2.1.0+)
- `FFTBackend.powerSpectralDensity(_:sampleRate:)` (v2.1.1)
- `Vector1D<T>` (v2.1.2)
- `CubicSplineInterpolator<T>` with `BoundaryCondition.natural` (v2.1.2)

**Cross-repo state:** narbis `Package.swift` is on `from: "2.1.4"`. All 58
existing tests pass. A small smoke test file at
`Tests/BioFeedbackKitTests/_BusinessMathSmokeTest.swift` confirms the
three upstream types we depend on are visible from BioFeedbackKit.
Delete that file once `FrequencyDomainMetrics` ships and uses the
upstream types directly.

---

## 8. Test Strategy

### Reference truth: synthetic sine waves with hand-computed expected power

For a pure sine wave `x(t) = A · sin(2π · f₀ · t)`, the time-domain variance is
`A²/2`. If `f₀` falls exactly on an FFT bin and the resampling preserves the
signal exactly, all of that power should land in the bin containing `f₀`.

**Primary fixture (LF + HF):**
```
Two superimposed sine waves over 60 seconds:
  x(t) = 50 · sin(2π · 0.10 · t) + 30 · sin(2π · 0.25 · t)

Sampling: 4 Hz → N = 240, padded to 256
LF (0.04..0.15): contains 0.10 Hz → expected power ≈ 50²/2 = 1250 ms²
HF (0.15..0.40): contains 0.25 Hz → expected power ≈ 30²/2 = 450 ms²
LF/HF ratio expected ≈ 1250 / 450 ≈ 2.7778
VLF: nil (window < 333s)
```

**Long-window fixture (VLF + LF + HF):**
```
Three superimposed sine waves over 600 seconds (10 minutes):
  x(t) = 80 · sin(2π · 0.01 · t) + 50 · sin(2π · 0.10 · t) + 30 · sin(2π · 0.25 · t)

Sampling: 4 Hz → N = 2400, padded to 4096
VLF (0.003..0.04): contains 0.01 Hz → expected power ≈ 80²/2 = 3200 ms²
LF: 1250 ms²
HF: 450 ms²
```

The test feeds these as BioSamples (with rrInterval = mean ± sine, so the
non-stationarity gets resampled and analyzed). The implementation ought to
produce LF and HF powers within ~5% of the analytic values — Hann windowing
introduces some leakage and the bin-mapping isn't perfectly clean.

**Secondary fixtures:**
- **Pure LF only:** `x(t) = 50 · sin(2π · 0.10 · t)` → HF power should be near zero, LF/HF should be very large
- **Pure HF only:** `x(t) = 30 · sin(2π · 0.25 · t)` → LF power should be near zero, LF/HF should be near zero
- **Constant (DC only):** all RR intervals identical → both LF and HF should be near zero (numerical noise)
- **Short window VLF nil:** 60s window → `vlfPower == nil` even on the long-window fixture's signal
- **Long window VLF populated:** 600s window with the long-window fixture → `vlfPower` within 5% of 3200 ms²
- **Window too short:** 10s of data → throws `windowTooShort`
- **Too few samples:** 3 BioSamples → throws `insufficientSamples`
- **Non-monotonic timestamps:** out-of-order BioSample → throws `nonMonotonicTimestamps`
- **Generic Collection:** ArraySlice path
- **Custom resampleRate:** 8 Hz instead of 4 Hz, verify result is similar (within tolerance)
- **HF=0 edge case:** verify `lfHfRatio == .infinity` and doesn't crash
- **Custom FFTBackend:** inject `PureSwiftFFTBackend()` explicitly and verify it produces the same result as the auto-selected backend within tolerance

**v3 dropped from v2's test plan:**
- ~~Custom InterpolationStrategy stub~~ — no protocol to test; BusinessMath's `CubicSplineInterpolator` is tested in BusinessMath's own suite (13 tests in `CubicSplineTests.swift`)
- ~~Custom WindowFunction stub~~ — no protocol; Hann window is a private helper, tested implicitly via the integration tests
- ~~InterpolationStrategy unit tests~~ — see above
- ~~WindowFunction unit tests~~ — Hann is a 5-line private helper; sanity-checked implicitly when the integration tests pass

### Test tolerances

Frequency-domain calculations have inherent inaccuracy from windowing
and resampling. The validation block establishes the expected analytic
values; tests use a relative tolerance of **5%** for LF, HF, and the
LF/HF ratio. **HF specifically may approach but not exceed 3%** based
on the playground's empirical measurements (cubic spline + Hann window
on the 1 Hz HRV fixtures). VLF should be within 0.1% on the long-window
fixture (essentially machine precision).

### Validation block

A standalone playground already exists at
`project/plans/upcoming/FrequencyDomain-Playground.swift` and
has been verified to run. It contains both linear and cubic spline
implementations side-by-side, generates the primary and long-window
fixtures, and prints LF/HF/VLF values for comparison against the
analytic expected powers. The cubic spline output values (the ones
v3 will use) are the canonical test assertions.

Empirically measured values (from the playground, with cubic spline):

| Fixture | Band | Analytic | Cubic value | Relative error |
|---|---|---|---|---|
| 60s LF+HF | LF | 1250 | ~1249.4 | 0.05% |
| 60s LF+HF | HF | 450 | ~437.2 | 2.85% |
| 600s VLF+LF+HF | VLF | 3200 | ~3200.0 | 0.001% |
| 600s VLF+LF+HF | LF | 1250 | ~1249.4 | 0.05% |
| 600s VLF+LF+HF | HF | 450 | ~437.1 | 2.87% |

These are the values the package implementation must reproduce when
fed the same fixtures.

---

## 9. Architecture Decision Review

- [x] Reviewed: no prior ADRs in this project yet
- [ ] **New ADR candidates** (defer to ADR file establishment):
  - "FrequencyDomainMetrics uses linear interpolation in v1; cubic spline reserved for v2"
  - "Hann windowing is hardcoded; configurable window functions are a future enhancement"
  - "Bin-edge convention: half-open `[lo, hi)` band intervals"

---

## 10. Resolved Questions

1. **VLF in v1?** RESOLVED — **YES**. Sessions are 30+ minutes; users training HRV control benefit from VLF over those time horizons. Reported as `Double?`, `nil` when window < 333s.

2. **FFT backend injectable?** RESOLVED — **YES**. Init parameter with `FFTBackendSelector.selectBackend()` as default. Lets callers swap via settings or for tests.

3. **Interpolation strategy?** RESOLVED **(v3)** — **use BusinessMath's `CubicSplineInterpolator(boundary: .natural)` directly.** No local protocol. v2's local `InterpolationStrategy` was a placeholder for the missing upstream functionality, which now ships in BusinessMath v2.1.2. Cubic spline with natural BC is the Kubios HRV standard and reduces HF amplitude error from 33% (linear) to 2.85% on the playground HRV fixtures.

4. **Window function strategy?** RESOLVED **(v3)** — **hardcoded Hann inline as a private helper.** No local protocol. Hann is the universal HRV standard; alternatives (Hamming, Blackman) aren't used in this domain. Future flexibility is a v2 additive overload, same pattern as BusinessMath's `generateRandomReturns(using:)` overload added in v2.1.4.

5. **Detrending strategy?** RESOLVED — mean removal happens unconditionally inside the init. Higher-order detrending (linear) would be a future enhancement; v1 just does mean removal.

6. **Streaming variant — bundle or separate?** RESOLVED — **separate proposal**. Same pattern as `StreamingHRVMetrics`.

7. **Unified `HRVReport` type?** RESOLVED — **separate detailed proposal, drafted and held**. See `HRVReport.md` in PROPOSALS/. Not for activation until Algorithm layer needs it.

---

## 11. Documentation Strategy

**Documentation Type:** API Docs Only

**Complexity threshold:**
- Combines 3+ APIs? Yes (resampling, windowing, FFT, band integration)
- 50+ lines of explanation? Yes — the normalization math alone needs ~30 lines
- Theory/background? Yes, but defer the narrative article to a project-level "HRV Frequency Domain Primer" alongside the time-domain primer once the Algorithm layer ships

**Decision:** API docs for v1 with thorough DocC including the normalization
formulas and the band-edge convention. Defer the narrative article.

---

## 12. Streaming Variant — Held for Future Proposal

A streaming variant is the natural follow-up, identical in shape to
`StreamingHRVMetrics`:

```swift
extension AsyncSequence where Element == BioSample, Self: Sendable {
    func frequencyDomainMetrics(
        window: Duration,
        every stride: Duration? = nil,
        resampleRate: Double = 4.0
    ) -> AsyncFrequencyDomainMetricsSequence<Self>
}
```

Same windowing dispatch (`tumblingWindow` for `nil` stride, `slidingWindow`
otherwise), same skip-on-error semantics. **It will get its own design
proposal and full TDD cycle when v1 ships and the Algorithm layer needs it.**

---

## Approval Checklist (v3)

All v2 items below are still good unless a `→ v3:` annotation says otherwise.

- [x] VLF as `Double?`, populated only when window ≥ 333 s
- [x] Field names and the LF/HF=0 → `.infinity` convention
- [x] Test fixtures (LF+HF primary, VLF+LF+HF long-window) and 5% tolerance for LF/HF/ratio
- [x] Band-edge convention `[lo, hi)`
- [x] Dependency on BusinessMath PSD method (shipped in v2.1.1)
- [x] Validation playground exists and runs (verified during the v2.1.2 work)
- [x] BusinessMath dev clone location confirmed (`Tools/Playgrounds/Math/BusinessMath/`)
- [ ] **→ v3:** User approves dropping the local `InterpolationStrategy` protocol and using `BusinessMath.CubicSplineInterpolator(boundary: .natural)` directly
- [ ] **→ v3:** User approves dropping the local `WindowFunction` protocol and hardcoding Hann as a private helper
- [ ] **→ v3:** User approves the simplified API: `FrequencyDomainMetrics.init(window:resampleRate:fftBackend:)` — no `interpolation:` or `windowFunction:` parameters
- [ ] **→ v3:** User approves the dropped test fixtures (no `InterpolationStrategy` stub test, no `WindowFunction` unit tests)

---

**Last Updated:** 2026-04-07 (v3)
