# Design Proposal: BusinessMath Upstream — Power Spectral Density (PSD)

**Status:** DRAFT v1 — awaiting user approval
**Target repo:** `github.com/jpurnell/BusinessMath` (upstream change)
**Blocks:** `FrequencyDomainMetrics.md` v2 in BioFeedbackKit

---

## 1. Objective

Add a normalized power spectral density (PSD) method to BusinessMath's
`FFTBackend` protocol so downstream consumers (BioFeedbackKit and others)
get physically meaningful spectral values directly from BusinessMath instead
of every consumer reinventing normalization.

The current `powerSpectrum(_:)` returns raw `|X[k]|²` from the FFT. Useful as
a primitive but every consumer that wants real units (variance/Hz, dB, ms²
for HRV) has to apply the same normalization steps. That's redundant and
error-prone — the normalization has subtle one-sided/two-sided and
zero-padding gotchas that are easy to get wrong.

---

## 2. Proposed Architecture

**Modified files (BusinessMath repo):**
- `Sources/BusinessMath/Streaming/FFTBackend.swift` — add new protocol method, default implementation
- `Tests/BusinessMathTests/Streaming/FFTBackendTests.swift` — new tests for PSD

**No breaking changes.** The existing `powerSpectrum(_:)` stays as-is.

---

## 3. API Surface

### Addition to `FFTBackend` protocol

```swift
public protocol FFTBackend: Sendable {

    /// Raw power spectrum |X[k]|² (existing — unchanged).
    func powerSpectrum(_ signal: [Double]) -> [Double]

    /// One-sided power spectral density in units²/Hz.
    ///
    /// The integral of the returned PSD over frequency equals the time-domain
    /// variance of the input signal (Parseval's theorem). For a zero-mean
    /// signal, this is the signal's variance distributed across frequency bins.
    ///
    /// **Normalization conventions:**
    /// - One-sided spectrum: bins `1..<N/2` are doubled; DC bin `0` and
    ///   Nyquist bin `N/2` are NOT doubled.
    /// - The normalization uses the **unpadded** signal length `M`, not the
    ///   internally zero-padded length `N`. This ensures the PSD integral
    ///   equals the time-domain variance regardless of padding.
    /// - No window function is applied. Callers that need windowing (Hann,
    ///   Hamming, etc.) must apply it to the signal before calling, and
    ///   compensate the result by dividing by the window's noise-equivalent
    ///   bandwidth `(1/M) · Σ w[m]²`.
    ///
    /// - Parameters:
    ///   - signal: Real-valued input signal. Apply mean removal and windowing
    ///     before calling. The signal will be internally zero-padded to the
    ///     next power of 2 for FFT.
    ///   - sampleRate: Sample rate in Hz. Must be positive.
    /// - Returns: PSD bins of length `N/2 + 1` where `N` is the padded length.
    ///   Returns an empty array for an empty signal or non-positive sample rate.
    func powerSpectralDensity(_ signal: [Double], sampleRate: Double) -> [Double]
}
```

### Default implementation (in extension)

```swift
extension FFTBackend {
    public func powerSpectralDensity(_ signal: [Double], sampleRate: Double) -> [Double] {
        guard signal.isEmpty == false, sampleRate > 0 else { return [] }

        let M = signal.count                    // unpadded length
        let raw = powerSpectrum(signal)         // length = N/2 + 1
        guard raw.isEmpty == false else { return [] }

        let nyquistBin = raw.count - 1          // index of Nyquist bin
        // Padded length: N = (raw.count - 1) * 2
        // (recoverable from output length, but we don't actually need N here
        // because normalization uses M, not N.)

        // For one-sided PSD whose integral over frequency equals time variance:
        //   PSD[k] = 2 · |X[k]|² / (M · fs)   for typical bins
        //   PSD[0] = |X[0]|² / (M · fs)       (DC, not doubled)
        //   PSD[N/2] = |X[N/2]|² / (M · fs)   (Nyquist, not doubled)
        let typicalFactor = 2.0 / (Double(M) * sampleRate)
        let edgeFactor = 1.0 / (Double(M) * sampleRate)

        var psd = [Double](repeating: 0.0, count: raw.count)
        psd[0] = raw[0] * edgeFactor
        if nyquistBin > 0 {
            psd[nyquistBin] = raw[nyquistBin] * edgeFactor
        }
        if nyquistBin > 1 {
            for k in 1..<nyquistBin {
                psd[k] = raw[k] * typicalFactor
            }
        }

        return psd
    }
}
```

The default implementation is shared by all backends (`PureSwiftFFTBackend`,
`AccelerateFFTBackend`). Backends *can* override for performance, but the
default is correct and stable.

---

## 4. Constraints & Compliance

- **Backward compatibility:** Existing `powerSpectrum(_:)` is unchanged. No
  consumer breaks.
- **Default implementation in extension:** all backends inherit it for free.
- **Concurrency:** Pure function. Sendable by composition.
- **Determinism:** Same signal + same sample rate → same PSD bins, exactly.
- **Safety:** Empty/invalid input returns empty array, never crashes.
- **Generics:** Concrete `Double` matches the existing `powerSpectrum` signature.

---

## 5. Test Strategy

**Reference truth: Parseval's theorem.**

The defining property of a correctly-normalized one-sided PSD is that its
integral over frequency equals the time-domain variance:

```
σ²(time) = Σ_k PSD[k] · Δf       where Δf = fs / N_padded
```

This is the strongest possible test: pick any signal, compute its variance,
compute its PSD, integrate, assert equality within numerical tolerance.

### Test cases

1. **Parseval — zero-mean white noise.** Generate 1024 zero-mean random
   doubles. Time variance = `Σx²/N`. Compute PSD. Assert
   `Σ PSD · Δf ≈ time variance` within `1e-9` relative tolerance.

2. **Parseval — pure sine wave.** `x(t) = A · sin(2π · f₀ · t)` over `M`
   samples at `fs`. Time variance = `A²/2`. Verify integral matches.
   This case is sensitive to whether `f₀` lands on a bin boundary; pick
   `f₀ = 4 Hz, fs = 64 Hz, M = 64` so the bin is integer.

3. **Bin spacing correctness.** Verify the returned PSD has length `N/2 + 1`
   where `N = nextPowerOf2(M)`.

4. **DC bin not doubled.** Pure DC signal `x = [c, c, c, ...]`. After mean
   removal it's all zeros, so PSD is all zeros — but verify the unmodified
   case has the DC bin scaled by `1/(M·fs)` not `2/(M·fs)`.

5. **Nyquist bin not doubled.** Construct a signal whose only frequency
   content is at exactly the Nyquist frequency (alternating `+1, -1, +1,
   -1, ...`). Verify the Nyquist bin is scaled by the edge factor.

6. **Zero-padding equivalence.** A signal of length 100 (padded to 128) and
   a signal of length 128 (no padding) both representing the same underlying
   continuous-time signal should produce PSDs whose integrals match within
   numerical tolerance. This is the test that proves we're using `M` not `N`
   for normalization.

7. **Empty input → empty output.** Smoke test.

8. **Non-positive sample rate → empty output.** Smoke test.

9. **Backend equivalence.** `PureSwiftFFTBackend` and (on Darwin)
   `AccelerateFFTBackend` should produce PSDs that agree to within `1e-9`
   relative tolerance on the same input.

### Validation block

A standalone playground at `BusinessMath/Tests/Validation/PSD-Playground.swift`
that prints the test case values and the analytic expected values for human
verification before tests are written. Same pattern we used for the Signal
Layer.

---

## 6. Open Questions

1. **Should we also expose a two-sided PSD?**
   - **Recommendation:** No, not in this PR. One-sided is what 99% of
     real-valued signal analysis wants. Add `powerSpectralDensityTwoSided`
     later if a real consumer needs it.

2. **Should we expose a method that returns PSD bins paired with their
   frequencies (to avoid every caller computing `Δf` themselves)?**
   - **Recommendation:** Yes, as a small additional convenience. See §7.

3. **Should the new method know about windowing internally (Hann, Hamming)?**
   - **Recommendation:** No. Separation of concerns. The caller applies the
     window and knows the compensation factor. BusinessMath stays focused on
     the spectral primitive.

4. **Should this proposal also add an `Sendable` constraint or any other
   correctness improvements while we're touching the file?**
   - **Recommendation:** No. Keep this PR focused. Other improvements get
     separate proposals.

---

## 7. Convenience Addition (recommended)

In addition to the protocol method, add a free function or extension method
that returns frequencies alongside bins:

```swift
public struct PSDBin: Sendable, Equatable {
    public let frequency: Double  // Hz
    public let power: Double      // units²/Hz
}

extension FFTBackend {
    /// PSD with each bin labeled by its center frequency.
    public func powerSpectralDensityBins(
        _ signal: [Double],
        sampleRate: Double
    ) -> [PSDBin] {
        let psd = powerSpectralDensity(signal, sampleRate: sampleRate)
        guard psd.isEmpty == false else { return [] }
        let N = (psd.count - 1) * 2
        let deltaF = sampleRate / Double(N)
        return psd.enumerated().map { idx, value in
            PSDBin(frequency: Double(idx) * deltaF, power: value)
        }
    }
}
```

This makes downstream band-integration trivial:

```swift
let bins = backend.powerSpectralDensityBins(signal, sampleRate: 4.0)
let lfPower = bins
    .filter { $0.frequency >= 0.04 && $0.frequency < 0.15 }
    .reduce(0) { $0 + $1.power } * deltaF
```

---

## 8. Workflow / Cross-Repo Coordination

This is upstream work in BusinessMath, not BioFeedbackKit. The execution
workflow:

1. User approves this proposal
2. Clone or open BusinessMath repo for development
3. Follow BusinessMath's own dev guidelines (which are the same as ours):
   design proposal in BusinessMath repo → RED → GREEN → REFACTOR → DOCUMENT → VERIFY
4. Push the change to a branch
5. Update narbis `BioFeedbackKit/Package.swift` to depend on that branch
6. Resume `FrequencyDomainMetrics` v2 implementation against the new API

**Question for the user:** where is BusinessMath checked out for development?
The current narbis dependency uses `branch: "main"` which fetches into
`.build/checkouts/` (read-only — modifications would be lost on re-resolve).
We need a writable working copy.

---

## Approval Checklist

- [ ] User approves the new `powerSpectralDensity(_:sampleRate:)` method as a protocol addition with a default implementation
- [ ] User approves using the **unpadded** length `M` for normalization (not the padded `N`)
- [ ] User approves the convenience `powerSpectralDensityBins(_:sampleRate:)` extension and `PSDBin` value type
- [ ] User approves "no windowing inside BusinessMath; caller's responsibility" decision
- [ ] User approves Parseval-based test strategy
- [ ] User specifies where BusinessMath dev clone lives so I can begin implementation

---

**Last Updated:** 2026-04-06
