# Design Proposal: Devices Layer (Retroactive)

> **Note:** This design document was created retroactively. The Devices layer was
> scaffolded before the Design-First TDD workflow was established for this project.
> Tests were written after implementation. Documented here for completeness.

---

## 1. Objective

Establish the input contract for BioFeedbackKit — a common sample type and device
protocol that all hardware adapters conform to.

**Master Plan Reference:** Foundation layer — required before Signal, Algorithm, or Feedback.

## 2. Proposed Architecture

**New Files:**
- `Sources/BioFeedbackKit/Devices/BioSample.swift`
- `Sources/BioFeedbackKit/Devices/BiofeedbackDevice.swift`
- `Sources/BioFeedbackKit/Devices/MockDevice.swift`
- `Tests/BioFeedbackKitTests/DeviceTests.swift`

**Module Placement:** Devices/ (new module layer within BioFeedbackKit)

## 3. API Surface

```swift
public struct BioSample: Sendable, Equatable {
    public let rrInterval: Double                      // milliseconds
    public let timestamp: ContinuousClock.Instant
    public init(rrInterval: Double, timestamp: ContinuousClock.Instant = .now)
    public var heartRate: Double? { get }               // derived, nil if rrInterval <= 0
}

public protocol BiofeedbackDevice: Sendable {
    var name: String { get }
    var isConnected: Bool { get }
    func connect() async throws
    func disconnect() async throws
    func sampleStream() async throws -> AsyncThrowingStream<BioSample, any Error>
}

public final class MockDevice: BiofeedbackDevice, @unchecked Sendable {
    public init(name: String = "MockDevice", samples: [BioSample])
    public convenience init(name: String = "MockDevice", rrIntervals: [Double])
}
```

## 4. Constraints & Compliance

- **Concurrency:** BioSample is Sendable (immutable value type). BiofeedbackDevice requires Sendable.
- **Safety:** No force unwraps. heartRate guards against zero/negative RR intervals.
- **Swift 6:** Strict concurrency compliant.

## 5. Dependencies

**Internal:** None (foundation layer)
**External:** BusinessMath (package dependency, but Devices layer doesn't use it directly yet)

## 6. Test Coverage

- BioSample: heart rate derivation, zero/negative safety, equatable conformance
- MockDevice: streaming order, not-connected error, connect/disconnect state, naming, protocol conformance
- **10 tests, all passing**

## 7. Status

**Completed:** 2026-04-06
**Process deviation:** Code-first instead of Design-First TDD. Corrected going forward.

---

**Last Updated:** 2026-04-06
