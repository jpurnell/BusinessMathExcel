# Design Proposal: Feedback Helpers v1

**Status:** SHIPPED 2026-04-08
**Date:** 2026-04-08

## Implementation notes
- All 30 tests passed on first GREEN attempt
- TintMapper field naming switched from `min`/`max` (numerical) to `clear`/`dark` + `narrow`/`wide` (visual outcome) per user feedback — much clearer reading
- All three helpers are `Codable` so they can be persisted via `ConfigStore<T>` if the app needs runtime tuning
- AdaptiveSensitivity multiplier values (HIGH=1.0, MEDIUM=0.66, LOW=0.5) are stored properties on the struct, not enum constants — OTA-updatable per the cross-platform mandate
- 230 / 230 tests total passing, zero warnings, zero forbidden patterns
**References:**
- v5 §6.4 (coherence-to-tint mapping, adaptive feedback sensitivity)
- v5 §7.3 (Smart Start RF stability analysis)

---

## 1. Objective

Three small pure-math helpers that the future Swift narbis Edge app
will consume but that belong in the cross-platform library because
they're shared with any consuming app (iOS, Android via Kotlin
interop, etc.):

1. **`TintMapper`** — converts a coherence score (0–100) into a
   `(center, amplitude)` pair that drives glasses lens brightness
2. **`AdaptiveSensitivity`** — classifies a user's recent training
   history into HIGH/MEDIUM/LOW sensitivity levels
3. **`RFStabilityAnalyzer`** — computes the stability of recent
   resonance-frequency measurements for Smart Start

All three are pure value types, fully deterministic, no I/O, no state.
Each is consumed by a different orchestration layer in the app
(Feedback for tint, Training session for sensitivity, Smart Start for
RF stability) — but the math is identical across platforms, so it
lives in BioFeedbackKit.

---

## 2. Scope

### In scope
- `TintMapper` (struct + curve enum + output type)
- `AdaptiveSensitivity` (struct + level enum)
- `RFStabilityAnalyzer` (struct + result enum)
- A new `Sources/BioFeedbackKit/Feedback/` directory to hold them
- One unified test suite covering all three

### NOT in scope
- The actual BLE side of glasses control (`OpacityController`, command
  encoding for `0xA2`/`0xA3`) — that's app layer
- Discovery protocol orchestration / state machines — that's app layer
- Real-time tint smoothing across frames — that's app layer
- Persistent training history storage — that's app layer (or
  `ConfigStore<TrainingHistory>` if we choose to use the existing
  infrastructure)

---

## 3. Math

### 3.1 TintMapper (v5 §6.4)

The Edge glasses firmware handles breathing oscillation natively at
~50 Hz via the `0xA3` command. The app modulates the **brightness cap**
(via `0xA2`) based on coherence, which effectively controls the
*amplitude* of the firmware's oscillation. The *center* of the
oscillation depends on min/max tint settings.

Two values are derived from coherence:

```
coherence ∈ [0, 100]
normalized = coherence / 100         // 0..1

center    = lerp(maxCenter, minCenter, curve(normalized))
amplitude = lerp(maxAmplitude, minAmplitude, curve(normalized))
```

Where `curve` is a configurable shaping function:
- **`.linear`** — identity (no shaping)
- **`.sigmoid`** — `1 / (1 + exp(-k × (x - 0.5)))` with `k = 8` for a
  reasonable S-curve in [0, 1]
- **`.easeOut`** — `1 - (1 - x)²`, gives gentle reward early
- **`.easeIn`** — `x²`, requires high coherence for big rewards

**Reward direction (v5 §6.4):**
- High coherence → bright (lower center, narrower amplitude — *world stays clear*)
- Low coherence → dim (higher center, wider amplitude — *world dims with strong cycles*)

So `minCenter` corresponds to the highest-coherence state and
`maxCenter` to the lowest. (`min` here means "smallest tint value =
brightest"; `max` means "largest tint value = darkest". Documented
clearly in DocC.)

### 3.2 AdaptiveSensitivity (v5 §6.4)

```
classify(sessionCount, avgCoherence):
  if sessionCount < 5  || avgCoherence < 40:  → .high
  if avgCoherence < 60:                       → .medium
  otherwise:                                  → .low
```

The thresholds (5 sessions, 40%, 60%) are v5 defaults; we expose them
as parameters for tunability without baking them into a constant.

The sensitivity level produces a multiplier on the `TintMapper`'s
output range — `.high` = wide range (small coherence changes → big
tint shifts), `.low` = narrow range (need larger coherence gains for
the same reward). This is a separate function: `multiplier(for: level)
-> Double`.

### 3.3 RFStabilityAnalyzer (v5 §7.3)

```
analyze(rfHistory: [Double], threshold: Double = 0.3):
  if history.count < 2:  → .insufficientData
  let sd = stddev(history)
  if sd < threshold:     → .stable(sd: sd)
  else:                  → .variable(sd: sd)
```

The 0.3 bpm threshold and the use of standard deviation are v5
defaults. We expose threshold as a parameter and document the
0.3 default.

---

## 4. API

### 4.1 TintMapper

```swift
public enum TintCurve: String, Sendable, Codable, Equatable {
    case linear
    case sigmoid
    case easeOut
    case easeIn
}

public struct TintOutput: Sendable, Equatable {
    /// Center value for the breathing oscillation. Bigger = darker.
    /// In the same units as `minCenter`/`maxCenter` (typically 0–255).
    public let center: Double
    /// Half-width of the breathing oscillation. Bigger = wider swing.
    public let amplitude: Double
}

public struct TintMapper: Sendable, Equatable {
    /// The center value at maximum coherence (brightest baseline).
    public let minCenter: Double
    /// The center value at zero coherence (darkest baseline).
    public let maxCenter: Double
    /// The amplitude at maximum coherence (narrowest oscillation).
    public let minAmplitude: Double
    /// The amplitude at zero coherence (widest oscillation).
    public let maxAmplitude: Double
    /// Shaping curve applied to the normalized coherence before lerp.
    public let curve: TintCurve

    public init(
        minCenter: Double,
        maxCenter: Double,
        minAmplitude: Double,
        maxAmplitude: Double,
        curve: TintCurve = .linear
    )

    /// Maps a coherence score in [0, 100] to a tint output.
    public func map(coherence: Double) -> TintOutput
}
```

### 4.2 AdaptiveSensitivity

```swift
public enum SensitivityLevel: String, Sendable, Codable, Equatable {
    case high     // < 5 sessions or avg coherence < 40 — wide reward
    case medium   // avg coherence 40–60
    case low      // avg coherence > 60 — narrow reward, raises the bar
}

public struct AdaptiveSensitivity: Sendable, Equatable {
    /// Session count threshold below which the user is treated as new.
    /// Default 5 (v5 §6.4).
    public let newcomerSessionThreshold: Int
    /// Coherence threshold (0–100) for HIGH sensitivity. Default 40.
    public let lowCoherenceThreshold: Double
    /// Coherence threshold (0–100) for MEDIUM/LOW boundary. Default 60.
    public let mediumCoherenceThreshold: Double

    public init(
        newcomerSessionThreshold: Int = 5,
        lowCoherenceThreshold: Double = 40,
        mediumCoherenceThreshold: Double = 60
    )

    /// Classifies a user's recent training history.
    public func classify(
        sessionCount: Int,
        averageCoherence: Double
    ) -> SensitivityLevel

    /// Returns the tint-range multiplier for a given sensitivity level.
    /// HIGH = 1.0 (full range), MEDIUM = 0.66, LOW = 0.5 — small
    /// coherence changes produce smaller tint swings as the user
    /// progresses.
    public func multiplier(for level: SensitivityLevel) -> Double
}
```

### 4.3 RFStabilityAnalyzer

```swift
public enum RFStability: Sendable, Equatable {
    /// Fewer than 2 RF measurements; can't compute SD.
    case insufficientData
    /// SD < threshold — RF is stable across recent sessions.
    case stable(sd: Double)
    /// SD ≥ threshold — RF is shifting; needs reconfirmation.
    case variable(sd: Double)
}

public struct RFStabilityAnalyzer: Sendable, Equatable {
    /// SD threshold (bpm) below which RF is considered stable.
    /// Default 0.3 (v5 §7.3).
    public let stabilityThreshold: Double

    public init(stabilityThreshold: Double = 0.3)

    /// Analyzes a series of recent RF measurements (in bpm).
    public func analyze(rfHistory: [Double]) -> RFStability
}
```

---

## 5. Constraints

- Pure value types, all `Sendable` and `Equatable`
- `Codable` where it makes sense (curves, levels, multipliers — useful
  if any of these end up in `ConfigStore` later)
- Cross-platform — no Darwin-only APIs
- No `String(format:)`, `try!`, force unwraps, etc.
- DocC on every public symbol with v5 spec references

---

## 6. Test Strategy (~30 tests)

### TintMapper (~12 tests)
1. Linear curve: coherence 0 → maxCenter, coherence 100 → minCenter
2. Linear curve: coherence 50 → midpoint of (maxCenter, minCenter)
3. Sigmoid curve: coherence 50 → midpoint (sigmoid is symmetric around 0.5)
4. Sigmoid curve: coherence 0 → ~maxCenter (just barely above), coherence 100 → ~minCenter
5. EaseIn vs EaseOut produce different intermediate values for same coherence
6. Amplitude direction: max coherence → minAmplitude, zero → maxAmplitude
7. Linear amplitude midpoint
8. Coherence < 0 clamps to 0 (i.e. produces maxCenter / maxAmplitude)
9. Coherence > 100 clamps to 100
10. Codable JSON roundtrip for `TintCurve` enum
11. Equatable: identical mappers compare equal
12. Default curve is `.linear`

### AdaptiveSensitivity (~10 tests)
13. < 5 sessions → HIGH regardless of coherence
14. 5 sessions, avgCoherence 30 → HIGH (low coherence)
15. 5 sessions, avgCoherence 50 → MEDIUM
16. 5 sessions, avgCoherence 70 → LOW
17. Custom thresholds honored (e.g. newcomer threshold = 10)
18. Boundary: avgCoherence == 40 → MEDIUM (40 is not < 40)
19. Boundary: avgCoherence == 60 → LOW (60 is not < 60)
20. Multiplier: HIGH > MEDIUM > LOW (1.0 / 0.66 / 0.5)
21. Codable JSON roundtrip for `SensitivityLevel`
22. Equatable

### RFStabilityAnalyzer (~8 tests)
23. Empty history → `.insufficientData`
24. Single-element history → `.insufficientData`
25. Two-element stable history (e.g. [6.0, 6.1]) → `.stable`
26. Two-element variable history (e.g. [5.5, 6.5]) → `.variable`
27. SD math: known stddev returned in `.stable(sd:)` payload
28. Custom threshold (e.g. 0.5) accepts wider variance as stable
29. All-equal history → SD 0 → `.stable(sd: 0)`
30. Real-world fixture: 5 sessions oscillating around 6.0 → `.stable`

---

## 7. Files

| File | Purpose |
|---|---|
| `Sources/BioFeedbackKit/Feedback/TintMapper.swift` | Coherence → tint math |
| `Sources/BioFeedbackKit/Feedback/AdaptiveSensitivity.swift` | Session history → sensitivity level |
| `Sources/BioFeedbackKit/Feedback/RFStabilityAnalyzer.swift` | RF history → stability classification |
| `Tests/BioFeedbackKitTests/FeedbackHelpersTests.swift` | All ~30 tests in one suite |

New `Feedback/` subdirectory under `Sources/BioFeedbackKit/`. This is
the math layer of feedback; the BLE/UI layer (OpacityController, glasses
driver, screens) lives in the app.

---

## 8. Open Questions

### 8.1 Tint center direction — `min` = brightest or `min` = numerically smallest?

v5 specifies tint as 0 (clear) to 255 (dark). So "min tint" = 0 = clear
= bright. "Max tint" = 255 = dark. The convention is:
- `minCenter` = brightest = applied at max coherence
- `maxCenter` = darkest = applied at zero coherence

This is what the proposal codifies. Confirm naming feels right.

### 8.2 Multiplier values for sensitivity levels

I picked HIGH=1.0, MEDIUM=0.66, LOW=0.5 as defaults. v5 §6.4 says:
- HIGH: small coherence changes produce big tint shifts
- LOW: requires larger gains for same reward

The multiplier scales the tint *range* (max − min). HIGH = full range,
LOW = compressed range. The exact MEDIUM/LOW values are guesses; we
can tune later if real users hit them.

### 8.3 Should `AdaptiveSensitivity.multiplier(for:)` be on the level enum directly or on the analyzer struct?

Method-on-struct keeps the multiplier values configurable in the
future; method-on-enum is simpler. I lean **struct method** because
we'll likely want to OTA-update those values once we have real users.

---

## 9. Approval

- [ ] Approve scope (3 helpers, 1 directory, 1 test file)
- [ ] Approve API surface in §4
- [ ] Approve test strategy (~30 tests)
- [ ] Resolve / accept the 3 open questions in §8
- [ ] Approve writing tests BEFORE implementation
