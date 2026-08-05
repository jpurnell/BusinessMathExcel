# Design Proposal: SyntheticRRSource v1

**Status:** SHIPPED 2026-04-08
**Date:** 2026-04-08

## Implementation notes
- All 16 tests passed on first GREEN attempt
- Uses an internal LCG (MMIX constants) + Box-Muller for deterministic Gaussian noise; Box-Muller's `spare` value is cached so each call produces one fresh normal
- Avoids the LCG zero-state fixed point by mixing in a constant when `seed == 0`
- 200 / 200 tests total passing, zero warnings, zero forbidden patterns

---

## 1. Objective

A deterministic synthetic RR-interval generator that produces
physiologically realistic `BioSample` sequences with controllable
respiratory sinus arrhythmia modulation, additive noise, and a seed for
reproducibility. Used by:

- v5 §9 Simulation Mode (the future Swift Edge app's "no hardware" path)
- Library tests (richer than the hand-built sine fixtures we use today)
- Future demos that need to show coherence-responding-to-breathing
  without real hardware

This is the first of four small library helpers in the Option A
roadmap (synthetic RR → coherence-to-tint mapping → adaptive
sensitivity → RF stability analysis).

---

## 2. Scope

### In scope
- `SyntheticRRSource` value type with deterministic generation
- Two generation methods: by sample count, and by duration
- Configurable baseline RR, pacer frequency, RSA amplitude, noise stddev, seed
- Pure deterministic — same seed always produces the same output
- Cross-platform (no Darwin-only APIs)

### NOT in scope
- An async sequence variant (could come later if a real-time-pacing demo needs it)
- Multiple breathing-rate transitions in one source (e.g. discovery-protocol simulation)
- Ectopic beat injection
- Heart rate trends (slow drift) — could come later as another parameter

---

## 3. Math

For each successive beat:

```
RR_n = baselineRR + amplitude × sin(2π × pacerFrequency × t_n) + noise_n
t_{n+1} = t_n + RR_n / 1000   // RR in ms, t in seconds
```

Where:
- `t_0 = 0` (first beat at origin)
- `noise_n` is Gaussian-distributed with mean 0 and stddev `noiseStdDev`
- The Gaussian is generated via Box-Muller transform on a simple LCG
  (deterministic given `seed`)

The result is an irregularly-spaced sequence whose **RR intervals
oscillate at `pacerFrequency`** — exactly the shape that the coherence
pipeline expects to find a peak at.

---

## 4. API

```swift
public struct SyntheticRRSource: Sendable {
    /// Mean RR interval in milliseconds. Default 800 (75 BPM resting).
    public let baselineRR: Double

    /// Pacer (breathing) frequency in Hz. Default 0.10 Hz (6 bpm).
    public let pacerFrequency: Double

    /// RSA amplitude in milliseconds (peak deviation from baseline). Default 30.
    public let amplitude: Double

    /// Standard deviation of additive Gaussian noise in milliseconds. Default 5.
    public let noiseStdDev: Double

    /// Seed for the deterministic noise generator.
    public let seed: UInt64

    public init(
        baselineRR: Double = 800,
        pacerFrequency: Double = 0.10,
        amplitude: Double = 30,
        noiseStdDev: Double = 5,
        seed: UInt64 = 42
    )

    /// Generates exactly `count` samples starting from `origin`.
    public func generate(
        count: Int,
        origin: ContinuousClock.Instant
    ) -> [BioSample]

    /// Generates samples spanning approximately `seconds` of wall-clock
    /// time, starting from `origin`.
    public func generate(
        seconds: Double,
        origin: ContinuousClock.Instant
    ) -> [BioSample]
}
```

---

## 5. Constraints

- `Sendable` value type, no internal state
- No Darwin-only APIs
- No `String(format:)`, `try!`, force unwraps
- Deterministic: same `(seed, parameters)` → same output, always

---

## 6. Test Strategy (~15 tests)

1. **Determinism:** same seed → identical output
2. **Different seeds → different output**
3. **`count` parameter:** `generate(count: 100, ...)` returns exactly 100 samples
4. **`seconds` parameter:** spans approximately the requested wall-clock duration
5. **Baseline check:** mean of generated RR ≈ `baselineRR`
6. **Amplitude bounded:** observed range ≈ 2 × amplitude (loose tolerance for noise)
7. **Zero noise + zero amplitude:** all samples = baseline
8. **Zero noise, nonzero amplitude:** pure sine modulation, no randomness
9. **Zero amplitude, nonzero noise:** mean ≈ baseline, stddev ≈ noiseStdDev
10. **Pacer frequency in spectrum:** feed to `FrequencyDomainMetrics`, peak in coherence band ≈ `pacerFrequency`
11. **Pipeline integration — HRVMetrics:** generated samples produce valid `HRVMetrics` (no throw, sensible values)
12. **Pipeline integration — FrequencyDomainMetrics:** generated samples produce valid `FrequencyDomainMetrics`
13. **End-to-end with CoherenceAlgorithm:** synth → freqdomain → score → coherence > 0
14. **End-to-end with StreamingCoherenceEngine:** feed sample-by-sample, post-warmup get a result
15. **Different pacer rates produce different peakFrequency in the result** (5 bpm vs 7 bpm fixtures)

---

## 7. Files

| File | Purpose |
|---|---|
| `Sources/BioFeedbackKit/Devices/SyntheticRRSource.swift` | The generator |
| `Tests/BioFeedbackKitTests/SyntheticRRSourceTests.swift` | Tests |

Goes in `Devices/` since it's a `BioSample` source, not a Signal/Algorithm transform.

---

## 8. Open questions

None — recommendations baked into §3/§4 above. This is small enough
that a proposal-light approach is appropriate.

---

## 9. Approval

- [ ] Approve scope and API
- [ ] Approve test strategy
- [ ] Approve writing tests BEFORE implementation
