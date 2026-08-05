# Design Proposal: Ambient Binaural Pad Sound Design

**Status:** COMPLETED (implemented 2026-04-23, commit 640ea18)
**Date:** 2026-04-23 (revised 2026-04-23)
**Scope:** NarbisKit (AudioFeedbackEngine, AudioFeedbackConfig, SettingsPersistence), NarbisUI (SettingsView)
**Depends on:** Binaural beats audio engine (committed 71387a0), SettingsPersistence protocol (committed ac0819f)
**Reference:** [639 Hz Heart Chakra Patterns — Binaural Frequencies](https://music.apple.com/us/album/639-hz-heart-chakra-patterns/1564771351?i=1564771500)

---

## 1. Objective

Transform the audio engine from a clinical sine oscillator into a warm, ambient meditation pad. The reference track demonstrates the target aesthetic: a continuous, cushion-like wash of sound with the binaural beat embedded inside it — not a raw tone sitting in silence.

**Design philosophy:** The engine does the sound design. Users turn audio on/off and set volume. They don't need to understand harmonics, noise filters, or envelope curves. Coherence-driven modulation is the default behavior — higher coherence produces a richer, warmer tone as positive reinforcement.

### Current Deficiencies

| Issue | Root Cause | Impact |
|-------|-----------|--------|
| Harsh, clinical tone | Single `sin()` per channel | Users remove headphones |
| Abrupt volume jumps | Instant `state.volume =` assignment | Audible clicks/pops |
| Too loud default | `volume: 0.3` is jarring | First-run experience is unpleasant |
| `harmonicRichness` computed but unused | `ambientParameters(for:)` returns it; render path ignores it | Dead code path |
| No ambient texture | Binaural beat only — silence between beats | Less immersive than competitors |
| Flat sound regardless of coherence | No feedback loop from algorithm to audio character | Missed reinforcement opportunity |
| `specifier:` format string in SettingsView | `Text("Beat: \(settings.beatFrequency, specifier: "%.1f")` | Fragile pattern |

---

## 2. Proposed Architecture

### Design Decisions

1. **Coherence-driven harmonics are the default.** The render loop auto-modulates harmonic richness based on the coherence level passed into `update()`. Higher coherence = warmer, richer pad. An advanced setting (`adaptiveHarmonics`) lets power users disable this and fix richness at a base level.

2. **Band-passed pink noise for warmth.** Standard pink noise has too much high-frequency hiss. We apply a simple one-pole low-pass filter (cutoff ~800 Hz) to roll off the highs, producing a warm "room tone" or "cushion" underneath the binaural tone.

3. **No sound-design sliders in main UI.** The main audio section has: on/off toggle, volume slider, carrier preset buttons, beat frequency slider, breathing rate tracking toggle. No harmonic richness slider. The advanced section exposes the adaptive harmonics toggle only.

4. **Lower default volume (0.15).** The pad-style sound fills more of the spectrum, so it can be quieter and still feel present.

5. **Envelope smoother eliminates clicks.** A one-pole exponential filter smooths all volume transitions (breathing modulation, coherence changes, start/stop). Attack 50ms, release 100ms.

### Modified Files

| File | Changes |
|------|---------|
| `AudioFeedbackEngine.swift` | Add `PinkNoiseGenerator`, `EnvelopeSmoother`, `LowPassFilter`; harmonics in render loop; coherence-driven richness; filtered ambient pad |
| `AudioFeedbackConfig.swift` | Add `harmonicRichness`, `ambientVolume`, `adaptiveHarmonics` properties; lower default volume to 0.15 |
| `SettingsPersistence.swift` | Add `adaptiveHarmonics: Bool` property |
| `InMemorySettingsStore` | Add `adaptiveHarmonics` with default `true` |
| `UserDefaultsSettingsStore.swift` | Add `adaptiveHarmonics` persistence |
| `NarbisSettings.swift` | Add `adaptiveHarmonics` property with didSet |
| `SettingsView.swift` | Add adaptive harmonics toggle in advanced section; fix specifier string |
| `AudioFeedbackEngineTests.swift` | Add harmonic, envelope, pink noise, low-pass, and config tests |
| `SettingsPersistenceTests.swift` | Add `adaptiveHarmonics` default test |

### New Internal Types (private, in AudioFeedbackEngine.swift)

| Type | Purpose |
|------|---------|
| `PinkNoiseGenerator` | Voss-McCartney pink noise, tuple-backed (zero allocation) |
| `EnvelopeSmoother` | One-pole exponential filter for volume transitions |
| `LowPassFilter` | One-pole low-pass for ambient noise warmth (~800 Hz cutoff) |

---

## 3. API Surface

### AudioFeedbackConfig additions

```swift
public struct AudioFeedbackConfig: Sendable, Codable, Equatable {
    // ... existing properties (carrierFrequency, beatFrequency, trackBreathingRate,
    //     volume, toneEnabled, chimesEnabled, breathingModulation) ...

    /// Base harmonic richness (0-1). 0 = pure sine, 1 = warm with 2nd/3rd partials.
    /// When `adaptiveHarmonics` is true (default), coherence modulates richness
    /// between 0 and this value. Default: 0.7.
    public let harmonicRichness: Double

    /// Ambient pad volume relative to master (0-1). Default: 0.25.
    /// The ambient pad is band-passed pink noise providing a warm "cushion"
    /// beneath the binaural tone.
    public let ambientVolume: Double

    /// Whether harmonic richness auto-modulates from coherence.
    /// True (default): higher coherence = richer, warmer tone.
    /// False: richness fixed at `harmonicRichness`.
    public let adaptiveHarmonics: Bool
}
```

**Volume change:** Default `volume` drops from 0.3 to 0.15.

### Render loop (pseudocode)

```swift
for frame in 0..<Int(frameCount) {
    // 1. Smooth volume envelope (eliminates clicks)
    let vol = smoother.process(target: audioState.volume * audioState.masterVolume)

    // 2. Compute effective richness
    let richness = audioState.adaptiveHarmonics
        ? audioState.coherenceRichness  // set by update() from coherence
        : audioState.baseRichness

    // 3. Fundamental + harmonics (normalized so peak <= 1.0)
    let normFactor = 1.0 / (1.0 + 0.5 * richness + 0.25 * richness)
    let fundamental = sin(phase * 2π)
    let second = sin(phase * 4π) * 0.5 * richness
    let third = sin(phase * 6π) * 0.25 * richness
    let tone = (fundamental + second + third) * normFactor * vol

    // 4. Warm ambient pad: pink noise → low-pass filter
    let rawNoise = pinkNoise.next()
    let warmNoise = lowPass.process(rawNoise)
    let ambient = warmNoise * audioState.ambientVolume * audioState.masterVolume

    // 5. Mix
    leftBuf[frame] = Float(toneL + ambient)
    rightBuf[frame] = Float(toneR + ambient)
}
```

### PinkNoiseGenerator (private, zero-allocation)

```swift
/// Voss-McCartney pink noise generator.
/// Tuple-backed storage — no heap allocation. Safe for render thread.
private struct PinkNoiseGenerator {
    private var rows: (Double, Double, Double, Double, /* ... 16 total */)
    private var runningSum: Double = 0
    private var index: UInt32 = 0
    private var seed: UInt64

    init(seed: UInt64 = 0x12345678) { ... }

    /// Returns next pink noise sample in [-1, 1]. O(1) amortized.
    mutating func next() -> Double { ... }
}
```

### LowPassFilter (private)

```swift
/// One-pole low-pass filter for warming up pink noise.
/// Rolls off highs above cutoff frequency for a cushion-like texture.
private struct LowPassFilter {
    private let coefficient: Double
    private var previous: Double = 0

    /// - Parameters:
    ///   - cutoffHz: Cutoff frequency. Default 800 Hz.
    ///   - sampleRate: Audio sample rate.
    init(cutoffHz: Double = 800, sampleRate: Double) {
        // coefficient = exp(-2π * cutoff / sampleRate)
        guard sampleRate > 0 else {
            self.coefficient = 0
            return
        }
        self.coefficient = exp(-2.0 * .pi * cutoffHz / sampleRate)
    }

    mutating func process(_ input: Double) -> Double {
        previous = coefficient * previous + (1.0 - coefficient) * input
        return previous
    }
}
```

### EnvelopeSmoother (private)

```swift
/// One-pole exponential smoother for click-free volume transitions.
private struct EnvelopeSmoother {
    private let attackCoeff: Double
    private let releaseCoeff: Double
    private var current: Double = 0

    init(attackMs: Double = 50, releaseMs: Double = 100, sampleRate: Double) {
        guard sampleRate > 0 else {
            self.attackCoeff = 0
            self.releaseCoeff = 0
            return
        }
        self.attackCoeff = exp(-1000.0 / (attackMs * sampleRate))
        self.releaseCoeff = exp(-1000.0 / (releaseMs * sampleRate))
    }

    mutating func process(target: Double) -> Double {
        let coeff = target > current ? attackCoeff : releaseCoeff
        current = coeff * current + (1.0 - coeff) * target
        return current
    }
}
```

---

## 4. Settings Changes

### SettingsPersistence protocol

Add one property:

```swift
/// Whether harmonic richness auto-modulates from coherence (default: true).
var adaptiveHarmonics: Bool { get set }
```

### NarbisSettings

Add `adaptiveHarmonics: Bool` with `didSet` write-through to store. Default `true`.

### SettingsView

**Main audio section** — unchanged except fixing the specifier string:
```swift
// Before (fragile):
Text("Beat: \(settings.beatFrequency, specifier: "%.1f") Hz (\(beatLabel))")
// After:
Text("Beat: \(settings.beatFrequency.formatted(.number.precision(.fractionLength(1)))) Hz (\(beatLabel))")
```

**Advanced section** — add toggle:
```swift
Toggle("Adaptive harmonics", isOn: $settings.adaptiveHarmonics)
    .font(.caption)
```

---

## 5. Constraints and Compliance

| Rule | Compliance |
|------|-----------|
| **No force unwraps** | No `!` in any new code |
| **Guard clauses** | sampleRate checked > 0 |
| **Division safety** | Normalization factor uses constant denominator (1 + 0.5r + 0.25r), r ∈ [0,1] so always > 0 |
| **Swift 6 concurrency** | `AudioState` remains `@unchecked Sendable`. New structs are value types on AudioState |
| **Render thread safety** | Zero heap allocations. PinkNoiseGenerator is tuple-backed. All math is scalar Double/Float |
| **String(format:) ban** | Fix existing specifier pattern in SettingsView |

---

## 6. Test Strategy

### Harmonic generation (pure computation, no AVFoundation)

Extract `static func generateSample(phase: Double, harmonicRichness: Double) -> Double` for testability.

- `harmonicRichness = 0` → output equals `sin(phase * 2π)` (pure sine)
- `harmonicRichness = 1` → output includes 2nd partial at 0.5x and 3rd at 0.25x, normalized
- Peak amplitude never exceeds 1.0 across all richness values
- Richness scales linearly

### Envelope smoother

- Step 0→1: settles within 1% after expected number of samples (verify time constant)
- Step 1→0: release is slower than attack
- Constant input: output equals input after settling
- Zero sample rate: no crash, returns safe default

### Pink noise generator

- Deterministic: same seed → identical first 1000 samples
- Range: all samples in [-1, 1] over 100,000 iterations
- No allocation: PinkNoiseGenerator is a value type with tuple storage

### Low-pass filter

- Passes DC (constant input → same constant output after settling)
- Attenuates high frequencies (alternating +1/-1 at Nyquist → output amplitude < 0.1)
- Zero sample rate: no crash

### Config

- New `AudioFeedbackConfig.default` has `volume: 0.15`, `harmonicRichness: 0.7`, `ambientVolume: 0.25`, `adaptiveHarmonics: true`
- Codable round-trip preserves all new fields
- Backward compatibility: decoding old JSON without new fields uses defaults

### Settings persistence

- `InMemorySettingsStore` default `adaptiveHarmonics` is `true`
- Setting and reading `adaptiveHarmonics` round-trips correctly

### Reference truth

| Computation | Value | Source |
|-------------|-------|--------|
| Attack coefficient (50ms, 44100 Hz) | `exp(-1000/(50*44100))` ≈ 0.999548 | Wolfram Alpha |
| Low-pass coefficient (800 Hz, 44100 Hz) | `exp(-2π*800/44100)` ≈ 0.892399 | Wolfram Alpha |
| Harmonic normalization (richness=1) | `1/(1+0.5+0.25)` = 0.571429 | Arithmetic |

---

## 7. Implementation Plan

### Phase 1 — RED: Pure computation tests

Write failing tests for `generateSample`, `EnvelopeSmoother`, `PinkNoiseGenerator`, `LowPassFilter`, updated `AudioFeedbackConfig` defaults, and Codable backward compatibility.

### Phase 2 — GREEN: Implement components

1. Add `PinkNoiseGenerator`, `EnvelopeSmoother`, `LowPassFilter` structs
2. Add `generateSample(phase:harmonicRichness:)` static method
3. Add new properties to `AudioFeedbackConfig` with backward-compatible `init(from:)`
4. Update `AudioState` with new fields (coherenceRichness, baseRichness, ambientVolume, adaptiveHarmonics)
5. Update render callback: harmonics + envelope + filtered ambient pad
6. Update `update()`: set `coherenceRichness` from coherence when adaptive
7. Lower default volume to 0.15
8. All RED tests pass

### Phase 3 — Settings + UI

1. Add `adaptiveHarmonics` to `SettingsPersistence`, `InMemorySettingsStore`, `UserDefaultsSettingsStore`, `NarbisSettings`
2. Add toggle in SettingsView advanced section
3. Fix specifier string in SettingsView
4. Add settings persistence test

### Phase 4 — REFACTOR + Quality Gate

1. Clean up render callback for readability
2. Run full test suite — all tests pass
3. Zero warnings, zero forbidden patterns

---

## 8. Out of Scope

- **Nature sounds** (rain, ocean) — separate proposal, requires bundled audio assets
- **Harmonic richness slider** — deliberately omitted; engine does the sound design
- **Stereo ambient spread** — mono pink noise to both channels (simpler, more natural room tone)
