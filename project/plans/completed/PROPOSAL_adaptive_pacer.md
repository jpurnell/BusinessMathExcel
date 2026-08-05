# Design Proposal: Adaptive Breathing Pacer

**Status:** COMPLETED (implemented 2026-04-24, commit 696114b)
**Date:** 2026-04-24
**Scope:** BioFeedbackKit (new `AdaptivePacer`), NarbisKit (TrainingViewModel integration), NarbisUI (visual feedback)
**Depends on:** StreamingCoherenceEngine (delivers `CoherenceResult.breathingRate`), BreathingPacer (current fixed-rate pacer), Discovery protocols (Lehrer/Fisher/SmartStart for initial RF)

---

## 1. Objective

The current `BreathingPacer` runs at a fixed rate for the entire session (typically 6.0 bpm from settings or the last discovery result). The user follows the visual breathing circle and tries to match it. But there's no feedback loop from the user's *actual* breathing (detected via FFT peak in the RR signal) back to the pacer.

This proposal adds an `AdaptivePacer` that:
1. **Starts at the user's natural breathing rate** (detected from RR intervals in the first 30 seconds)
2. **Gradually guides toward the resonance frequency** (their optimal RF from discovery, or 6.0 bpm default)
3. **Responds to coherence** — slows the guidance rate when coherence is high (don't fix what's working), speeds up when coherence drops
4. **Never jumps** — rate changes are smooth, max 0.1 bpm per breath cycle

**Why this matters:** Users often can't immediately match a 6.0 bpm pacer if their resting breathing rate is 12-15 bpm. The adaptive pacer meets them where they are and walks them down, which is both more comfortable and produces better coherence scores during the descent.

**Master Plan Reference:** Phase 4, training mode quality — adaptive pacing mentioned in v5 spec as a follow-on to fixed-rate training.

---

## 2. Background: What We Already Have

### Detected Breathing Rate
`StreamingCoherenceEngine` already computes the user's actual breathing rate on every sample via FFT peak detection in the [0.04, 0.26) Hz band. `CoherenceResult.breathingRate` = `peakFrequency × 60`. This is now surfaced in the dev overlay (commit 0a8dba5).

### Discovery Protocols
`LehrerDiscovery`, `FisherSweepDiscovery`, and `SmartStartDiscovery` find the user's individual resonance frequency (RF) via stepped/swept breathing rate tests. The RF is persisted via `SessionPersistence.saveRF()` and loaded as `settings.breathingRate` on next session.

### Fixed Pacer
`BreathingPacer` is a pure value type: given a rate and elapsed time, it returns the current phase. It has no state, no mutation, no awareness of coherence or detected rate.

---

## 3. Proposed Architecture

### New Type: `AdaptivePacer`

An actor (not a struct) because it maintains mutable state — the current effective breathing rate. It wraps the existing `BreathingPacer` concept but adjusts the rate over time.

```swift
public actor AdaptivePacer {
    /// Target breathing rate — the resonance frequency we're guiding toward.
    private let targetRate: Double
    /// Current effective breathing rate — what the visual circle actually shows.
    private(set) var currentRate: Double
    /// Maximum rate change per breath cycle (bpm).
    private let maxStepSize: Double
    /// Minimum seconds between rate adjustments.
    private let adjustmentInterval: Double

    private var lastAdjustment: ContinuousClock.Instant?
    private let inhaleRatio: Double

    public init(
        initialRate: Double? = nil,
        targetRate: Double = 6.0,
        inhaleRatio: Double = 0.4,
        maxStepSize: Double = 0.1,
        adjustmentInterval: Double = 10.0
    )

    /// Update the pacer based on latest coherence result.
    /// Call this on every `CoherenceResult` from the engine.
    public func update(
        detectedRate: Double,
        coherence: Double
    )

    /// Returns the current breathing phase for the given elapsed time.
    /// Accounts for smooth rate transitions.
    public func currentPhase(at elapsed: Duration) -> BreathingPhase
}
```

### Guidance Algorithm

```
On each CoherenceResult (roughly every 1-2 seconds):

1. If less than adjustmentInterval since last change → skip
2. Compute direction = sign(targetRate - currentRate)
3. Compute step:
   - If coherence > 60%: step = maxStepSize × 0.5  (slow — don't disrupt good state)
   - If coherence 30-60%: step = maxStepSize × 1.0  (normal guidance)
   - If coherence < 30%: step = maxStepSize × 0.25  (very slow — user is struggling)
4. newRate = currentRate + direction × step
5. Clamp to [4.5, 7.0] bpm (physiologic breathing range for coherence)
6. If |currentRate - targetRate| < 0.05 → snap to target
7. currentRate = newRate
```

**Key insight on the low-coherence case:** When coherence is low, the user isn't matching the current rate well. Changing the rate faster would make it worse. So we slow down guidance, giving them time to stabilize. This is counter-intuitive (you might think "they're not at target, go faster") but matches the Lehrer clinical protocol.

### Session Flow

```
0-30s:    Settling phase (no pacer visible, engine warming up)
30s:      Engine delivers first CoherenceResult with detectedRate
          AdaptivePacer.initialRate = detectedRate (e.g., 12.3 bpm)
30s-end:  Pacer visible, starting at 12.3 bpm
          Every ~10s: rate adjusts toward target (e.g., 6.0 bpm)
          ~5 min: rate converges on target if user can follow
          Remainder: fixed at target rate (same as current behavior)
```

### Phase Continuity

When the rate changes mid-breath, the circle can't jump. The `AdaptivePacer` must track accumulated phase and ensure the transition is smooth:

```swift
// Phase accumulator approach:
// Instead of computing phase from elapsed time alone,
// integrate phase continuously at the current rate.
// Rate changes only affect future phase accumulation.
accumulatedPhase += (currentRate / 60.0) × dt
let cyclePosition = accumulatedPhase.truncatingRemainder(dividingBy: 1.0)
// Map cyclePosition to inhale/exhale using inhaleRatio
```

This avoids the discontinuity that would occur if we recomputed `cycleDuration` mid-cycle.

---

## 4. Configuration

### NarbisSettings additions

```swift
/// Whether the pacer adapts to detected breathing rate (default: true).
var adaptivePacer: Bool { get set }
```

When false, the pacer runs at the fixed `breathingRate` setting (current behavior).

### AudioFeedbackConfig

If `trackBreathingRate` is true, the beat frequency already tracks the breathing rate. The adaptive pacer's `currentRate` should feed this — the binaural beat frequency matches the pacer rate, not a fixed config value.

---

## 5. UI Changes

### Training Screen
- No UI changes when adaptive pacer is active — the breathing circle just starts faster and gradually slows
- The rate change is imperceptible per-cycle (0.1 bpm max) — the user naturally follows without noticing

### Dev Overlay (already done)
- "Detected BR" shows the FFT-derived rate (what the user is actually doing)
- Add "Pacer Rate" showing the adaptive pacer's current effective rate
- Add "Target" showing the target RF

### Settings
- Toggle: "Adaptive pacing" (default on)
- When off, pacer uses fixed `breathingRate` as today

---

## 6. Integration with Discovery

If the user has a persisted RF from a discovery session, use it as `targetRate`. If no RF exists, use `6.0` bpm (the Lehrer default). This means:

- **New user, no discovery:** Pacer starts at their detected rate, guides to 6.0 bpm
- **User with RF 5.5 bpm:** Pacer starts at detected rate, guides to 5.5 bpm
- **User mid-discovery:** Adaptive pacer is disabled during discovery protocols (they have their own stepped/swept rate control)

---

## 7. Constraints and Compliance

| Rule | Compliance |
|------|-----------|
| **No force unwraps** | No `!` in any new code |
| **Guard clauses** | Rate clamping uses guard + min/max |
| **Division safety** | `cycleDuration` guarded against zero rate |
| **Swift 6 concurrency** | `AdaptivePacer` is an actor — thread-safe by construction |
| **Render thread safety** | Pacer is not on the render thread; called from main actor |
| **os.Logger** | All rate adjustments logged at `.debug` level |

---

## 8. Test Strategy

### Unit Tests (BioFeedbackKit)

**Convergence:**
- Given initialRate=12.0, targetRate=6.0, maxStep=0.1: after sufficient updates, currentRate converges to 6.0
- Given initialRate=4.5, targetRate=6.0: converges upward

**Coherence modulation:**
- High coherence (80%): step size is halved — takes longer to converge
- Low coherence (20%): step size is quartered — even slower
- Medium coherence (50%): full step size

**Clamping:**
- Rate never goes below 4.5 or above 7.0 bpm

**Snap-to-target:**
- When |current - target| < 0.05, snaps exactly to target

**Adjustment interval:**
- Updates within adjustmentInterval are no-ops

**Phase continuity:**
- Rate change mid-cycle doesn't produce a phase jump
- Phase progresses monotonically

### Integration Tests (NarbisKit)

- TrainingViewModel with adaptive pacer enabled: `currentRate` changes over time
- TrainingViewModel with adaptive pacer disabled: `currentRate` stays fixed
- Audio beat frequency updates when adaptive rate changes

---

## 9. Implementation Plan

### Phase 1 — RED: Tests
Write failing tests for `AdaptivePacer` convergence, coherence modulation, clamping, phase continuity.

### Phase 2 — GREEN: AdaptivePacer
Implement `AdaptivePacer` actor in `BioFeedbackKit/Sources/BioFeedbackKit/Algorithm/`.

### Phase 3 — Integration
- Add `adaptivePacer` toggle to `SettingsPersistence` / `NarbisSettings`
- Wire `AdaptivePacer` into `TrainingViewModel` as alternative to `BreathingPacer`
- Feed `currentRate` to `AudioFeedbackEngine.setBeatFrequency()`
- Add "Pacer Rate" / "Target" to dev overlay

### Phase 4 — REFACTOR + Quality Gate
- Clean up, verify all tests pass
- Run LoggingAuditor

---

## 10. Open Questions

1. **Should the adaptive pacer be in BioFeedbackKit or NarbisKit?** It's algorithm-level (physiological guidance logic), which suggests BioFeedbackKit. But it also interacts with settings and UI, which suggests NarbisKit. Proposed: core `AdaptivePacer` in BioFeedbackKit, integration in NarbisKit.

2. **What if the detected breathing rate is unreliable?** During settling, the FFT peak may be noisy. Should we require a minimum coherence threshold before trusting the detected rate for initialization? Proposed: only set initialRate if coherence > 10% at first result.

3. **Should the adaptive pacer reset on discovery?** If the user runs a discovery session and gets a new RF, the adaptive pacer should pick it up as the new target. Proposed: yes, `targetRate` updates when settings change.

4. **Hold phases?** `BreathingPacer` has infrastructure for inhale → hold → exhale → hold but currently uses zero-duration holds. Should the adaptive pacer introduce holds as the rate slows? Some protocols (e.g., box breathing) use equal hold durations. Proposed: out of scope for v1, but the phase accumulator design supports it.

---

## 11. Out of Scope

- **Visual rate indicator** — showing the user "you're breathing at X, target is Y" as a UI element. This could be useful but is a separate design decision about how much information to expose.
- **Adaptive inhale ratio** — some users respond better to 35% inhale / 65% exhale vs the default 40/60. Could be auto-tuned but adds complexity.
- **Multi-session learning** — tracking the user's convergence speed across sessions to personalize the guidance curve. Requires server-side analytics.
