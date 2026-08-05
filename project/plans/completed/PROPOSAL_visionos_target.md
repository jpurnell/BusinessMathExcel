# Design Proposal: visionOS / Vision Pro App Target

**Status:** COMPLETED (v1 implemented 2026-04-24/25, breathing sphere + passthrough tint + watch relay)
**Date:** 2026-04-23 (revised 2026-04-24)
**Scope:** `narbis-vision/` app shell, RealityKit breathing sphere, passthrough tint feedback, VisionFeedbackDevice actor
**Depends on:** NarbisKit, NarbisUI, BioFeedbackKit (all declare `.visionOS(.v1)`)

---

## 1. Objective

Stand up a sovereign visionOS app with two visual feedback modes:

1. **Breathing Sphere** — a RealityKit sphere in mixed reality that expands on inhale, contracts on exhale, and changes color/glow intensity with coherence. The user sees it floating in their real space.
2. **Passthrough Tint** — the entire passthrough darkens/lightens based on coherence, replicating the Edge glasses behavior. Clear when coherent, dim when not.

Both modes use the existing audio engine (binaural beats carry over unchanged). Simulation input for v1 — no hardware required.

**Out of scope for this proposal:** Full immersive coherence environment (particle fields, mandala patterns, environment-reactive spaces). That's a separate design proposal for a future session.

---

## 2. Architecture

### 2.1 Directory Structure

```
narbis-vision/
├── NarbisVision.xcodeproj
├── NarbisVision/
│   ├── NarbisVisionApp.swift       # @main, WindowGroup + ImmersiveSpace
│   ├── VisionDeviceFactory.swift    # Simulation for v1
│   ├── VisionFeedbackDevice.swift   # FeedbackDevice: sphere + tint + audio
│   ├── BreathingSphere.swift        # RealityKit entity: scale + color
│   ├── PassthroughTintView.swift    # ImmersiveSpace with dimming
│   └── ImmersiveTrainingView.swift  # RealityView wrapping sphere + tint
```

~6 files. Thin shell, all logic in shared packages.

### 2.2 New Types

**`VisionFeedbackDevice`** — actor conforming to `FeedbackDevice`. Owns the breathing sphere entity and tint state. Delegates audio to the existing `AudioFeedbackEngine`.

**`BreathingSphere`** — `@MainActor` class wrapping a RealityKit `ModelEntity` (sphere). On each `FeedbackUpdate`:
- **Scale** pulses with breathing phase: `1.0` at exhale end → `1.3` at inhale peak
- **Color** maps coherence to the same red/yellow/green as `CoherenceRing`
- **Emissive intensity** increases with coherence — the sphere glows brighter as coherence rises

**`PassthroughTintView`** — controls a `SurroundingsEffect` or full-screen overlay in the immersive space. Maps coherence 0-100 to opacity 0.6-0.0 (fully dim at 0%, fully clear at 100%). Uses `TintMapper` from BioFeedbackKit for consistency with Edge glasses behavior.

### 2.3 Visualization Modes

```swift
enum VisionFeedbackMode: String, Sendable, Codable, CaseIterable {
    case breathingSphere    // Floating sphere in mixed reality
    case passthroughTint    // Darken/lighten passthrough (glasses equivalent)
    case both               // Sphere + tint together (default)
}
```

User selects in Settings. Default is `.both`.

---

## 3. Scene Lifecycle

```swift
@main
struct NarbisVisionApp: App {
    @State private var settings = NarbisSettings()
    @State private var immersionStyle: ImmersionStyle = .mixed

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView(
                    settings: settings,
                    inputDeviceFactory: { makeInputDevice(settings: settings) },
                    outputDeviceFactory: { makeOutputDevice(settings: settings) }
                )
            }
        }

        ImmersiveSpace(id: "training") {
            ImmersiveTrainingView()
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed)
    }
}
```

**Flow:**
1. User launches → `HomeView` in a window
2. Start Training → `TrainingView` in window + `openImmersiveSpace("training")`
3. Breathing sphere appears floating at eye level, ~1m away
4. Passthrough dims/clears with coherence
5. Session ends → `dismissImmersiveSpace`, `ResultsView` in window

---

## 4. Breathing Sphere Details

### Entity Hierarchy

```swift
@MainActor
final class BreathingSphere {
    let root: Entity
    private let sphere: ModelEntity
    private var currentColor: SimpleMaterial.Color = .red

    init() {
        sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.15),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        sphere.position = [0, 1.5, -1.0] // Eye level, 1m away
        root = Entity()
        root.addChild(sphere)
    }

    func apply(_ update: FeedbackUpdate) {
        // Scale from breathing phase
        let breathScale: Float
        switch update.breathingPhase {
        case .inhale(let p): breathScale = 1.0 + Float(p) * 0.3
        case .exhale(let p): breathScale = 1.3 - Float(p) * 0.3
        case .holdIn: breathScale = 1.3
        case .holdOut, .idle: breathScale = 1.0
        }
        sphere.scale = [breathScale, breathScale, breathScale]

        // Color from coherence (matches CoherenceRing)
        let color = coherenceColor(update.coherence)
        var material = SimpleMaterial(color: color, isMetallic: false)
        // Emissive glow scales with coherence
        material.color.tint = color
        sphere.model?.materials = [material]
    }

    private func coherenceColor(_ coherence: Double) -> SimpleMaterial.Color {
        if coherence < 30 { return .red }
        if coherence < 60 { return .yellow }
        return .green
    }
}
```

### Visual Feel

The sphere should feel organic, not mechanical:
- Scale transitions use the same ease-in-ease-out curve as `BreathingCircle`
- Color transitions are gradual (not snapping at 30/60 thresholds)
- At high coherence, the sphere has a soft glow aura
- At low coherence, the sphere is matte and dim

---

## 5. Passthrough Tint Details

The passthrough dimming replicates Edge glasses behavior in mixed reality:

```swift
struct PassthroughTintView: View {
    let coherence: Double

    var body: some View {
        // Full-space dark overlay, opacity inversely proportional to coherence
        Color.black
            .opacity(tintOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var tintOpacity: Double {
        // 0% coherence → 0.5 opacity (dim), 100% → 0.0 (clear)
        max(0, 0.5 * (1.0 - coherence / 100.0))
    }
}
```

This is simpler than the Edge glasses `TintMapper` (no center/amplitude math) because we're directly controlling opacity, not byte-level brightness commands. But the *behavior* is the same: higher coherence = clearer vision.

---

## 6. Input Device (v1: Simulation Only)

```swift
@MainActor
func makeInputDevice(settings: NarbisSettings) -> any BiofeedbackDevice & Sendable {
    SimulationDevice(
        baselineRR: 800,
        amplitude: 30,
        noiseStdDev: 5,
        defaultPacerFrequency: settings.breathingRate / 60.0
    )
}
```

Real BLE input (Polar H10) is Phase 2. Watch relay is Phase 3. Simulation unblocks all visual/audio development.

---

## 7. Constraints and Compliance

| Rule | Compliance |
|------|-----------|
| No force unwraps | All optionals use guard |
| Swift 6 concurrency | `VisionFeedbackDevice` is an actor, `BreathingSphere` is `@MainActor` |
| os.Logger | All lifecycle events logged via `NarbisLog` |
| Per-platform sovereign | Full pipeline runs on Vision Pro independently |
| Thin shell | ~6 files, all logic in shared packages |

---

## 8. Test Strategy

### Unit Tests
- `BreathingSphere.apply()` with coherence 0/50/100 → verify scale and color
- `BreathingSphere.apply()` with inhale/exhale → verify scale range [1.0, 1.3]
- `VisionFeedbackDevice` connect/disconnect lifecycle
- `VisionFeedbackDevice` capabilities include `.visual` and `.audio`
- `PassthroughTintView` opacity mapping: 0% → 0.5, 100% → 0.0

### Integration
- Full pipeline: SimulationDevice → CoherenceEngine → FeedbackBroadcast → VisionFeedbackDevice → verify sphere state updates

### Simulator
- All Phase 1 work runs in visionOS Simulator
- No hardware required

---

## 9. Implementation Plan

### Phase 1: Simulator Shell + Breathing Sphere + Tint (this session)

1. Create `narbis-vision/` Xcode project
2. `NarbisVisionApp.swift` — scene with WindowGroup + ImmersiveSpace
3. `BreathingSphere.swift` — RealityKit entity with scale/color
4. `PassthroughTintView.swift` — coherence-driven dimming
5. `ImmersiveTrainingView.swift` — RealityView wrapping both
6. `VisionFeedbackDevice.swift` — FeedbackDevice conformance
7. Wire into `HomeView` → `TrainingView` → immersive space flow
8. Tests for sphere behavior and tint mapping

### Phase 2: BLE Input + Visual Polish (requires hardware)
- Polar H10 BLE integration
- Smooth color gradients (not threshold steps)
- Emissive glow shader for high coherence
- Ornament controls during immersive session

### Phase 3: Full Immersive Environment (separate proposal)
- Particle fields responding to coherence
- Environment-reactive spaces (fog, light, geometry)
- Multiple visualization styles (ocean, forest, geometric)
- Full immersion mode (`.full` instead of `.mixed`)

---

## 10. Open Questions

1. **Minimum visionOS version:** `.v1` or `.v2`? v2 has better `SurroundingsEffect` for passthrough dimming. If v1, we use the overlay approach.

2. **Sphere position:** Fixed at eye level 1m away, or should it track hand position / gaze? Fixed is simpler and less distracting for meditation. Proposed: fixed for v1.

3. **Passthrough dimming cap:** Max 50% opacity? Or should deep low-coherence go darker? 50% preserves safety (user can still see surroundings). Proposed: cap at 50%.

4. **Settings UI:** Add `VisionFeedbackMode` picker in SettingsView (`.breathingSphere` / `.passthroughTint` / `.both`). Should this be in the shared SettingsView with `#if os(visionOS)` or in a visionOS-only settings extension?
