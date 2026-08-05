# Design Proposal: Algorithm Layer v1 — HRV Coherence Scoring

**Status:** APPROVED 2026-04-07 — open questions resolved, ready for RED

## Resolved decisions (2026-04-07)

1. **Output transform default:** `.sigmoid`. Stored on `AlgorithmConfig`, so swappable via OTA config update without code changes.
2. **LF/HF ratio sentinel:** `1e6` hardcoded in v1.
3. **Frequency-domain features when nil:** treat as 0 with documented caveat.
4. **Feature naming:** bare names + `FeatureSource` enum.
5. **`CoherenceScore: Codable`:** yes.
6. **`CoherenceScore.timestamp`:** instant `score(...)` was called (default `.now`, explicit override for tests).

---

## 1. Objective

Build the Algorithm layer that scores cleaned HRV metrics (time-domain
+ frequency-domain) into a coherence value, gated by an
**OTA-updatable configuration** so the algorithm itself can be improved
without shipping app updates.

This is the layer where the patented work lives. The v1 proposal scopes
the **scaffolding**: the protocol shape, the config data structure, the
inference math, the validation, the test harness. The actual feature
set, weights, and output transform shipped with production apps will
come from the user's training pipeline (server-side, separate concern)
and load via `AlgorithmConfig`. v1 ships with placeholder defaults that
demonstrate the math but don't represent real trained coefficients.

**Master Plan Reference:** Phase 2 — Algorithm + Feedback.

---

## 2. Scope

### 2.1 In scope (v1)

| Type | Purpose |
|---|---|
| `HRVAlgorithm` (protocol) | Injectable, swappable algorithm interface |
| `CoreAlgorithm` (struct) | Default implementation: linear combination of normalized HRV features per `AlgorithmConfig` |
| `AlgorithmConfig` (struct, Codable) | Versioned bundle of features + weights + intercept + output transform |
| `FeatureSpec` (struct, Codable) | Single feature definition: name, source, normalization |
| `FeatureSource` (enum) | `.timeDomain` or `.frequencyDomain` — which Signal layer type to read from |
| `OutputTransform` (enum, Codable) | `.raw`, `.sigmoid`, `.linearClamped(min:max:)` |
| `CoherenceScore` (struct) | Algorithm output: value + config version + timestamp |
| `AlgorithmError` (enum) | Construction-time validation errors (mismatched weights, zero stdDev, unknown feature, etc.) |
| **`AlgorithmConfig.bundledDefault`** (static) | A reasonable starter config for testing and demos. **Placeholder weights** — not trained against real data. |

### 2.2 Explicitly NOT in scope (deferred)

| Deferred | Why | Where it goes |
|---|---|---|
| `ConfigFetcher` (remote fetch) | Network concern, separate from algorithm math | Future proposal |
| `ConfigStore` (local persistence) | I/O concern, separate from algorithm math | Future proposal |
| Streaming algorithm operator | Pattern is clear (`.coherenceScores(window:every:)`) but needs its own TDD cycle | Future proposal |
| `HRVReport` unified type | Algorithm v1 takes `HRVMetrics` and `FrequencyDomainMetrics?` as separate parameters; HRVReport is a downstream convenience that becomes useful when telemetry/persistence ships | Future proposal (held draft already exists) |
| Server-side training (`ConfigOptimizer` / GA) | Out of scope for the on-device library | Separate project |
| Multiple algorithm variants (e.g., neural network) | The protocol exists specifically to enable swap-in later | Future proposal when needed |

### 2.3 Why v1 doesn't need HRVReport

The held `HRVReport` proposal proposed unifying `HRVMetrics` and
`FrequencyDomainMetrics` into a single value type. That's a real win
**when telemetry/persistence land**, because downstream consumers want
to log "the full HRV picture for a window" as one object.

But for the algorithm itself, the math just needs:
- `timeDomain: HRVMetrics`
- `frequencyDomain: FrequencyDomainMetrics?` (optional because short windows can't compute it)

Two parameters is fine. When `HRVReport` ships later, the Algorithm
layer can grow an additional convenience method `score(report: HRVReport)`
without breaking the existing API. Pure additive evolution.

---

## 3. The math

`CoreAlgorithm` evaluates a linear combination of z-score-normalized
HRV features:

```
raw_score = intercept + Σ_i w_i * (feature_i - μ_i) / σ_i

final_score = outputTransform(raw_score)
```

Where:
- `feature_i` is a single numeric metric extracted from `HRVMetrics` or `FrequencyDomainMetrics` per the `FeatureSpec`
- `μ_i` and `σ_i` are the training-set mean and stdDev for z-scoring
- `w_i` is the linear coefficient (from training)
- `intercept` is the linear model intercept (from training)
- `outputTransform` shapes the raw score into a usable range

**Why this shape:** matches the structure produced by linear regression
training (BusinessMath's `MultipleLinearRegression`, used server-side).
The weights and intercept come directly out of a fit. The z-score
normalization makes the model robust to feature-scale differences and
matches standard ML practice. The output transform decouples "what the
linear model outputs" from "what we want users to see" — a sigmoid
gives a bounded [0, 1] coherence score, linear clamping gives a
custom range, raw passes the score through unchanged.

**Inference vs. training:** v1 only does inference. Training happens
server-side and writes its results into an `AlgorithmConfig`. The
device never trains; it loads a config and runs the inference math.
This matches the "OTA algorithm updates via config, not code" decision
in the Master Plan.

**No BusinessMath dependency in the Algorithm layer.** Inference is
direct array arithmetic — `Σ w_i * x_i` is a 5-line loop, no Vector
type required. BusinessMath stays a Signal-layer dependency only.
(Server-side training uses BusinessMath; that's a separate codebase.)

---

## 4. API Surface

### 4.1 Core types

```swift
import Foundation

// MARK: - Algorithm output

public struct CoherenceScore: Sendable, Equatable {
    /// The score value, in the range determined by the algorithm's
    /// output transform (e.g. [0, 1] for sigmoid).
    public let value: Double

    /// The version identifier of the AlgorithmConfig that produced
    /// this score. Used to tag persisted sessions for clean training
    /// cohorts (per the Master Plan).
    public let configVersion: String

    /// When this score was computed.
    public let timestamp: ContinuousClock.Instant

    public init(
        value: Double,
        configVersion: String,
        timestamp: ContinuousClock.Instant = .now
    )
}

// MARK: - Algorithm protocol

public protocol HRVAlgorithm: Sendable {
    /// Compute a coherence score from a window's HRV metrics.
    ///
    /// - Parameters:
    ///   - timeDomain: Time-domain HRV metrics from `HRVMetrics`.
    ///   - frequencyDomain: Frequency-domain HRV metrics from
    ///     `FrequencyDomainMetrics`. May be `nil` for short windows
    ///     (< 25 s) where frequency-domain computation is not possible.
    ///     Algorithms that depend on frequency-domain features should
    ///     decide how to handle the nil case (e.g. fall back to a
    ///     time-domain-only sub-model, or refuse to score and surface
    ///     a sentinel value).
    func score(
        timeDomain: HRVMetrics,
        frequencyDomain: FrequencyDomainMetrics?
    ) -> CoherenceScore
}

// MARK: - Algorithm errors (construction-time only)

public enum AlgorithmError: Error, Sendable, Equatable {
    /// `weights.count` did not match `features.count`.
    case mismatchedWeightsAndFeatures(featuresCount: Int, weightsCount: Int)
    /// A `FeatureSpec.stdDev` was 0 or negative — would cause division by zero.
    case nonPositiveStdDev(featureName: String, value: Double)
    /// A `FeatureSpec.name` did not match any known metric on the
    /// supported source type.
    case unknownFeature(featureName: String, source: FeatureSource)
}
```

### 4.2 AlgorithmConfig + supporting types

```swift
public struct AlgorithmConfig: Sendable, Codable, Equatable {
    /// Version identifier (e.g. "1.0.0"). Persisted with each session
    /// so training cohorts stay clean across config updates.
    public let version: String

    /// Wall-clock timestamp when this config was generated by the
    /// training pipeline. Stored as ISO-8601 in JSON.
    public let createdAt: Date

    /// Ordered list of features the algorithm consumes. Order matters —
    /// `weights[i]` is the coefficient for `features[i]`.
    public let features: [FeatureSpec]

    /// Linear-model coefficients, one per feature.
    public let weights: [Double]

    /// Linear-model intercept.
    public let intercept: Double

    /// How the raw linear score is shaped before being returned.
    public let outputTransform: OutputTransform

    public init(
        version: String,
        createdAt: Date,
        features: [FeatureSpec],
        weights: [Double],
        intercept: Double,
        outputTransform: OutputTransform
    ) throws

    /// A reasonable starter configuration for testing and demos.
    /// **Placeholder weights — not trained against real data.** Production
    /// apps should load a real config via the (future) `ConfigFetcher`.
    public static let bundledDefault: AlgorithmConfig
}

public struct FeatureSpec: Sendable, Codable, Equatable {
    /// Identifier for the metric this feature reads. Must match one of
    /// the supported names per its `source` (see CoreAlgorithm.swift
    /// for the canonical list).
    public let name: String

    /// Which Signal-layer type to read this feature from.
    public let source: FeatureSource

    /// Training-set mean for z-score normalization.
    public let mean: Double

    /// Training-set standard deviation for z-score normalization.
    /// Must be > 0.
    public let stdDev: Double
}

public enum FeatureSource: String, Sendable, Codable {
    case timeDomain
    case frequencyDomain
}

public enum OutputTransform: Sendable, Codable, Equatable {
    /// Pass the raw linear score through unchanged.
    case raw
    /// Apply a sigmoid: 1 / (1 + exp(-rawScore)). Output range (0, 1).
    case sigmoid
    /// Linear clamp the raw score into the given range. Out-of-range
    /// values are clipped to the bounds.
    case linearClamped(min: Double, max: Double)
}
```

### 4.3 CoreAlgorithm

```swift
public struct CoreAlgorithm: HRVAlgorithm {
    public let config: AlgorithmConfig

    public init(config: AlgorithmConfig) throws

    public func score(
        timeDomain: HRVMetrics,
        frequencyDomain: FrequencyDomainMetrics?
    ) -> CoherenceScore
}
```

### 4.4 Supported features (v1 starter set)

The v1 implementation supports these feature names. New names can be
added in future versions; existing names can never be renamed (would
break older configs).

**`source: .timeDomain`** (read from `HRVMetrics`):
- `meanRR` — mean NN interval
- `rmssd` — root mean square of successive differences
- `sdnn` — standard deviation of NN intervals
- `pnn` — proportion of successive differences exceeding `pnnThreshold`

**`source: .frequencyDomain`** (read from `FrequencyDomainMetrics`):
- `vlfPower` — VLF band power (uses 0 if `vlfPower == nil`, with caveat documented)
- `lfPower` — LF band power
- `hfPower` — HF band power
- `totalPower` — sum of populated bands
- `lfHfRatio` — LF/HF ratio (uses a sentinel of `1e6` instead of `.infinity` when `hfPower == 0`)
- `lfNormalized` — normalized LF
- `hfNormalized` — normalized HF

The list is mechanical — `CoreAlgorithm` has a switch statement that
maps each name to a property access. Adding a feature in v2 means
adding a case to that switch. The error path
`AlgorithmError.unknownFeature` covers configs that reference
unsupported names.

---

## 5. The bundled default config

`AlgorithmConfig.bundledDefault` is a placeholder for v1. It exists so:
- Tests can construct a `CoreAlgorithm` without inventing config values
- Demos and integration code have a working algorithm to show
- Production apps that ship without a remote config still have a
  reasonable fallback (a "demo mode")

The default config is **NOT** trained on real data. It uses:
- 4 features: `rmssd`, `sdnn`, `lfHfRatio`, `hfNormalized`
- Hand-picked weights that produce reasonable-looking scores on
  synthetic test fixtures
- Intercept of 0
- `outputTransform: .sigmoid` (output in (0, 1))
- `version: "default-v1"`

The proposal does NOT specify the exact weight values. The
implementation will pick something defensible (small, signed, mostly
non-zero) and the unit tests will lock those exact values in so they
become the documented default. **Real production weights come from
the user's training pipeline and load via the future ConfigFetcher.**

---

## 6. Constraints & Compliance

- **Concurrency:** All types are immutable `Sendable` value types. `CoreAlgorithm` is `Sendable` because it stores only an `AlgorithmConfig` (which is itself `Sendable`).
- **Determinism:** Pure function. Same `(timeDomain, frequencyDomain, config)` → same `CoherenceScore.value` exactly. The `timestamp` field on `CoherenceScore` is the only non-deterministic piece, and it's intentional — it's clock-stamped, not part of the math.
- **Safety:** No force unwraps. Division-by-zero guarded at config-construction time (`AlgorithmError.nonPositiveStdDev`). LF/HF ratio handled via the documented `1e6` sentinel for the inference path (the `.infinity` value from `FrequencyDomainMetrics` would propagate through arithmetic and break Codable persistence — sentinel is finite and JSON-safe).
- **No `String(format:)`** — uses `value.number(N)` for any string formatting in DocC examples.
- **Codable:** `AlgorithmConfig`, `FeatureSpec`, `FeatureSource`, `OutputTransform` are all `Codable` for OTA fetch and local persistence. JSON roundtrip is part of the test suite.
- **Swift 6:** Strict concurrency compliant.

---

## 7. Test Strategy

### 7.1 Unit tests for each type

| Type | Tests |
|---|---|
| `CoherenceScore` | Construction, equality, default-timestamp init |
| `FeatureSpec` | Codable JSON roundtrip, equality |
| `FeatureSource` | Codable as raw string, equality |
| `OutputTransform` | Codable for each case, equality |
| `AlgorithmConfig` | Construction validation (mismatched counts, zero stdDev), Codable JSON roundtrip including all OutputTransform variants, the bundled default loads cleanly |
| `CoreAlgorithm` | Construction validation, score computation on hand-built configs and synthetic metrics |

### 7.2 CoreAlgorithm scoring tests

These are the math-correctness tests that lock down the inference path:

1. **Single-feature linear:** A config with one feature `rmssd`, weight 1.0, intercept 0, transform `.raw`, mean 0, stdDev 1. Score should equal the raw RMSSD value of the input metrics.
2. **Single-feature z-scored:** Same but with mean 50, stdDev 10. Score for RMSSD=70 should be `(70-50)/10 = 2.0`.
3. **Two-feature combination:** Config with `rmssd` (weight 1) and `sdnn` (weight 0.5). Score for known inputs should equal `1*z(rmssd) + 0.5*z(sdnn)`.
4. **Intercept added:** Same as above but with intercept 5. Verify the intercept is added, not multiplied or applied to features.
5. **Sigmoid transform:** Raw score 0 → 0.5. Raw score +∞ → ~1.0. Raw score -∞ → ~0.0.
6. **Linear clamp transform:** Raw score 0.3, transform `.linearClamped(min: 0, max: 1)` → 0.3. Raw score -0.5 → 0. Raw score 1.5 → 1.
7. **Frequency-domain feature with nil:** Config references `lfPower` but the input `frequencyDomain` is `nil`. Behavior: feature value treated as 0 (with a documented caveat). Verify the math still produces a finite score.
8. **LF/HF ratio sentinel:** When `frequencyDomain.hfPower == 0`, the underlying `lfHfRatio` is `.infinity`. The inference path substitutes `1e6` to avoid Codable / arithmetic issues. Verify the substitution and that the score stays finite.
9. **Config version is propagated:** The score's `configVersion` field equals the `config.version` it was scored against.
10. **Bundled default produces reasonable scores:** Construct `CoreAlgorithm(config: .bundledDefault)`, feed it the primary HRV fixtures from existing tests, verify the output is finite and within the configured transform's range. **Lock the exact value with a hand-computed assertion** so any future change to the default weights is caught.

### 7.3 Validation tests

1. **Mismatched weights count throws:** `features.count = 4`, `weights.count = 3` → `mismatchedWeightsAndFeatures`.
2. **Zero stdDev throws:** Any `FeatureSpec` with `stdDev <= 0` → `nonPositiveStdDev`.
3. **Unknown feature name throws:** Feature `foo` with `source: .timeDomain` → `unknownFeature`.
4. **Unknown frequency-domain feature throws:** Feature `foo` with `source: .frequencyDomain` → `unknownFeature`.

### 7.4 Codable tests

1. **JSON roundtrip — bundled default:** Encode and decode the bundled default; the result equals the original.
2. **JSON roundtrip — custom config:** Build a config with each `OutputTransform` variant, roundtrip each.
3. **Forward compat — unknown field ignored:** Add an unknown JSON key; decode ignores it and succeeds. (Not strictly required but worth confirming.)
4. **Backward compat — required fields enforced:** Strip a required field (e.g. `weights`); decode fails with `DecodingError`. (Negative test.)

### 7.5 Integration test

A single end-to-end test that:
1. Builds a small fixture of `BioSample` values (the existing two-sine 60s fixture from `FrequencyDomainMetricsTests`)
2. Runs them through `HRVMetrics` → time-domain metrics
3. Runs them through `FrequencyDomainMetrics` → frequency-domain metrics
4. Constructs `CoreAlgorithm(config: .bundledDefault)`
5. Calls `score(timeDomain:frequencyDomain:)`
6. Verifies the returned `CoherenceScore` is finite, in range, and tagged with the right config version

This is the smoke test that the layers compose end-to-end.

### Reference truth

For the math-correctness tests (§7.2.1–6), the reference values are
trivially computable by hand from the input metrics, weights, and
transforms. No external library or playground needed — the formulas
are simple enough to verify in a comment next to each assertion.

For the bundled-default lock-in test (§7.2.10), the reference value is
**whatever the implementation produces on first run**. We capture it
as a constant in the test. Any future change that moves it requires
the test author to update the constant deliberately, which catches
accidental changes to the default weights.

---

## 8. Files to add

| File | Purpose |
|---|---|
| `Sources/BioFeedbackKit/Algorithm/HRVAlgorithm.swift` | Protocol + `CoherenceScore` |
| `Sources/BioFeedbackKit/Algorithm/AlgorithmConfig.swift` | Config + FeatureSpec + FeatureSource + OutputTransform + bundled default |
| `Sources/BioFeedbackKit/Algorithm/CoreAlgorithm.swift` | Concrete implementation |
| `Sources/BioFeedbackKit/Algorithm/AlgorithmError.swift` | Validation errors |
| `Tests/BioFeedbackKitTests/AlgorithmTests.swift` | All algorithm-layer tests in one suite (per the Signal-layer test-file convention) |

Module placement: new `Algorithm/` directory under `Sources/BioFeedbackKit/`,
matching the `Signal/` and `Devices/` directory structure.

---

## 9. Open Questions

These are the items I need your input on before drafting the v2 / RED phase.

### 9.1 Output transform default

Three options for `bundledDefault.outputTransform`:

- **`.sigmoid`** — bounded (0, 1), smooth, intuitive for "coherence percentage" UIs. Standard ML output for binary-classification-style models.
- **`.linearClamped(min: 0, max: 1)`** — bounded [0, 1] but with hard edges. More predictable for product UIs that draw progress bars.
- **`.raw`** — unbounded signed score. Maximum information, but the consumer has to interpret. Useful if downstream wants to apply its own normalization.

**Recommendation:** `.sigmoid` for the bundled default. It's the standard, gives consumers a bounded value, and matches typical biofeedback visualizations.

### 9.2 LF/HF ratio sentinel value

When `hfPower == 0`, `FrequencyDomainMetrics.lfHfRatio` is `.infinity`.
That value can't survive Codable, can't be multiplied by a weight
without producing NaN, and breaks every downstream consumer.

The cleanest fix is the inference layer substituting a large finite
sentinel (e.g. `1e6`) when reading the ratio. Three sentinel options:

- **`1e6`** — round, clearly large, well below `Double.greatestFiniteMagnitude`
- **`Double.greatestFiniteMagnitude`** — the technically-largest finite value; awkward in arithmetic
- **A configurable cap in `AlgorithmConfig`** — most flexible, but adds API surface for v1

**Recommendation:** `1e6` hardcoded for v1. Make it configurable in a
future release if anyone hits the cap.

### 9.3 Frequency-domain features when `frequencyDomain == nil`

Three options:

- **Treat as 0 with documented caveat** — the simplest. If the algorithm references `lfPower` and there's no frequency-domain data, it sees 0. Documented as "be careful: this may distort the score on short windows."
- **Refuse to score, return a sentinel or throw** — safest. Forces the caller to either provide frequency-domain data or use a time-domain-only config.
- **Have CoreAlgorithm auto-fall-back to a "time-domain-only" sub-config** — most ergonomic but adds significant complexity to v1.

**Recommendation:** Option 1 (treat as 0 with caveat) for v1. Document
clearly that the bundled default config assumes frequency-domain is
present. Production configs should ship two flavors — long-window with
freq features, short-window with time-only features — and the consumer
picks based on window length.

### 9.4 Feature name "namespace"

Should features be referenced by bare names (`"rmssd"`) or namespaced
(`"timeDomain.rmssd"`)? Namespacing adds clarity but is verbose. Bare
names with a `source` field (as proposed) keeps each FeatureSpec
self-describing without string-parsing.

**Recommendation:** Bare names + source field. As proposed in §4.2.

### 9.5 Should `CoherenceScore` be `Codable`?

For v1, `CoherenceScore` doesn't need to persist — that's the Sync
layer's job. But making it `Codable` is one extra line and lets
downstream consumers serialize scores for telemetry/replay.

**Recommendation:** Yes, `Codable`. Cheap and useful.

### 9.6 What does the `CoherenceScore.timestamp` represent?

Two possibilities:
- The instant `score(...)` was called
- The instant the underlying HRV metrics were measured (which would require passing it in)

**Recommendation:** Instant `score(...)` was called (default `= .now`),
with an explicit override parameter for testing. The metrics-time
information lives in the metrics objects themselves and the consumer
can correlate.

---

## 10. Constraints Compliance Checklist

- [ ] No force unwraps in any production code
- [ ] All public APIs documented with DocC `///`
- [ ] No `String(format:)` anywhere
- [ ] Sendable conformance verified (compile-time)
- [ ] Codable JSON roundtrip verified for all persistable types
- [ ] Validation errors thrown only at construction time, never during scoring
- [ ] Zero compiler warnings on `swift build`
- [ ] Quality gate clean

---

## 11. Approval Checklist

- [ ] User approves the v1 scope (scaffolding only — actual weights/features come from production training)
- [ ] User approves NOT shipping HRVReport, ConfigFetcher, ConfigStore, or streaming variant in v1
- [ ] User approves the API surface in §4
- [ ] User approves the feature name set in §4.4 (8 total: 4 time-domain + 7 frequency-domain — one can be removed if too many)
- [ ] User approves the math shape in §3 (z-scored linear combination + output transform)
- [ ] User approves the bundled default approach (placeholder weights with a lock-in test)
- [ ] User answers the 6 open questions in §9 (or accepts my recommendations)
- [ ] User approves writing the test suite BEFORE the implementation (RED phase first)

---

## 12. References

- Master Plan, "Architecture / Key Types" — `HRVAlgorithm`, `CoreAlgorithm`, `AlgorithmConfig`, `ConfigFetcher` listed as planned types
- Master Plan, "Core Architectural Decisions" — "OTA algorithm updates via config, not code"
- BusinessMath `MultipleLinearRegression` — used **server-side** to fit the weights that ship in `AlgorithmConfig`. Inference (this proposal) does not depend on it.
- 1996 Task Force HRV paper — defines the metrics this algorithm consumes
- Currently shipped Signal layer types: `HRVMetrics` (time domain), `FrequencyDomainMetrics` (frequency domain) — these are the algorithm's inputs

---

**Last Updated:** 2026-04-07
