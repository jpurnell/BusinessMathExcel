# Design Proposal: ConfigFetcher v1 — Remote AlgorithmConfig Fetch

**Status:** APPROVED 2026-04-07 — moving to RED
**Date:** 2026-04-07

## Resolved decisions

1. **Transport:** `Transport` protocol wrapping `URLSession`. Production impl `URLSessionTransport`, test impl `FakeTransport`.
2. **Auth:** Optional bearer token at fetcher construction. No token = unauthenticated request (dev/test endpoints).
3. **Conditional fetch:** Caller passes the current config's `version` as a query param; server returns 200 with new config or 304 with empty body. No ETag handling in v1.
4. **Validation on receive:** Decode succeeds + re-run `AlgorithmConfig.init` shape checks (the Codable path bypasses init). No signature verification in v1, no monotonic-version enforcement.
5. **Save policy:** Fetcher returns the config; caller decides whether to save it via `ConfigStore.save(_:)`. Dumb pipe.
6. **Retry:** None in v1. One method, one attempt, throw on failure. Caller handles retry policy at the app level.
7. **JSON shape:** Bare `AlgorithmConfig` JSON body (the same shape `FileConfigStore` already writes).

---

## 1. Objective

Fetch a new `AlgorithmConfig` from a remote URL, validate it, and
return it to the caller. Pairs with `ConfigStore` to complete the OTA
update path:

```
ConfigFetcher.fetch(currentVersion:) → AlgorithmConfig?
                                         ↓
                                  ConfigStore.save(_:)
```

`ConfigFetcher` is independent of `AlgorithmConfig`'s actual
coefficients — it can ship and be tested before the real Narbis
algorithm is ported from the TypeScript reference.

---

## 2. Scope

### 2.1 In scope

| Type | Purpose |
|---|---|
| `Transport` (protocol) | Async HTTP boundary, injectable for tests |
| `URLSessionTransport` (struct) | Production impl wrapping `URLSession` |
| `ConfigFetcher` (protocol) | Async fetch interface |
| `RemoteConfigFetcher` (struct) | Production impl: builds the request, decodes, validates |
| `ConfigFetcherError` (enum) | Network, decode, validation, and HTTP-status errors |
| `ConfigFetchResult` (enum) | `.updated(AlgorithmConfig)` or `.notModified` |

### 2.2 NOT in scope

| Deferred | Why |
|---|---|
| Signature verification (Ed25519 etc.) | Requires key distribution; v2 once a server exists |
| Monotonic version enforcement | Server-side concern primarily; v2 if needed |
| Retry / backoff policy | Opinionated; lives at the app level |
| ETag / Last-Modified handling | Version-query is enough for v1 |
| Background fetch / scheduling | App-level concern |
| Auth refresh / OAuth flows | Caller passes the token; how the token is obtained is out of scope |
| Multi-endpoint fallback | One URL, one attempt |
| Telemetry / metrics | Separate layer |

---

## 3. Behavior

### 3.1 Request

`fetch(currentVersion:)` issues a `GET` to the configured URL with:

- Query parameter `?version=<currentVersion>` — the version string the
  caller currently has loaded. Used by the server to decide whether to
  return a new config or `304 Not Modified`.
- `Authorization: Bearer <token>` header **if** a bearer token was
  provided at fetcher construction. Omitted otherwise.
- `Accept: application/json` header.

Callers that have no current config (fresh install) pass an empty
string or a sentinel like `"none"` — server policy decides.

### 3.2 Response handling

| HTTP status | Behavior |
|---|---|
| `200 OK` | Decode body as `AlgorithmConfig`, re-validate shape, return `.updated(config)` |
| `304 Not Modified` | Return `.notModified` |
| `401`, `403` | Throw `ConfigFetcherError.unauthorized(status:)` |
| Any other 4xx | Throw `ConfigFetcherError.clientError(status:)` |
| Any 5xx | Throw `ConfigFetcherError.serverError(status:)` |
| Transport failure | Throw `ConfigFetcherError.transportFailed(underlying:)` |
| Decode failure | Throw `ConfigFetcherError.decodeFailed(underlying:)` |
| Validation failure | Throw `ConfigFetcherError.validationFailed(underlying:)` |

### 3.3 Validation on receive

Decoded `AlgorithmConfig` instances bypass the throwing initializer
(Codable populates properties directly). The fetcher re-runs the shape
checks by feeding the decoded values back into the throwing init:

```swift
let decoded = try decoder.decode(AlgorithmConfig.self, from: data)
let validated = try AlgorithmConfig(
    version: decoded.version,
    createdAt: decoded.createdAt,
    features: decoded.features,
    weights: decoded.weights,
    intercept: decoded.intercept,
    outputTransform: decoded.outputTransform
)
return .updated(validated)
```

Any `AlgorithmError` thrown there gets wrapped as
`ConfigFetcherError.validationFailed(underlying:)`. The fetcher does
not do feature-name lookup (that's `CoreAlgorithm`'s job at construction
time) — only shape validation.

### 3.4 Caller pattern

```swift
let store: any ConfigStore = try FileConfigStore()
let fetcher: any ConfigFetcher = RemoteConfigFetcher(
    url: URL(string: "https://api.example.com/algorithm-config")!,
    bearerToken: "..."
)

// At app launch or on a schedule:
let current = try await store.loadCurrent() ?? .bundledDefault
do {
    let result = try await fetcher.fetch(currentVersion: current.version)
    switch result {
    case .updated(let newConfig):
        try await store.save(newConfig)
    case .notModified:
        break
    }
} catch {
    // Log; keep running on the existing config
}
```

The fetcher does not call the store. The caller composes the two.

---

## 4. API Surface

```swift
import Foundation

// MARK: - Transport boundary

public protocol Transport: Sendable {
    /// Performs a GET request and returns the response data + status code.
    /// - Throws: Any underlying network error from the implementation.
    func get(url: URL, headers: [String: String]) async throws -> (Data, Int)
}

public struct URLSessionTransport: Transport {
    public let session: URLSession
    public init(session: URLSession = .shared)
    public func get(url: URL, headers: [String: String]) async throws -> (Data, Int)
}

// MARK: - Fetch result

public enum ConfigFetchResult: Sendable, Equatable {
    case updated(AlgorithmConfig)
    case notModified
}

// MARK: - Errors

public enum ConfigFetcherError: Error, Sendable {
    case transportFailed(underlying: Error)
    case unauthorized(status: Int)
    case clientError(status: Int)
    case serverError(status: Int)
    case unexpectedStatus(status: Int)
    case decodeFailed(underlying: Error)
    case validationFailed(underlying: Error)
    case malformedURL
}

// MARK: - Fetcher protocol

public protocol ConfigFetcher: Sendable {
    /// Fetches a config from the remote endpoint.
    /// - Parameter currentVersion: The version string of the config the
    ///   caller currently has loaded. Sent as a query param for
    ///   conditional fetch.
    /// - Returns: `.updated(config)` if the server returned a new config,
    ///   `.notModified` if the server returned 304.
    func fetch(currentVersion: String) async throws -> ConfigFetchResult
}

// MARK: - Production impl

public struct RemoteConfigFetcher: ConfigFetcher {
    public let url: URL
    public let bearerToken: String?
    public let transport: any Transport

    public init(
        url: URL,
        bearerToken: String? = nil,
        transport: any Transport = URLSessionTransport()
    )
}
```

---

## 5. Constraints & Compliance

- **Concurrency:** All types `Sendable`. `RemoteConfigFetcher` is a value type.
- **Safety:** No force unwraps. All HTTP statuses mapped explicitly. URL construction goes through `URLComponents` so a malformed input throws `malformedURL` rather than crashing.
- **No `String(format:)`** anywhere.
- **Swift 6:** Strict concurrency compliant.
- **No retry:** A single attempt. Throws bubble up.
- **No global state:** No shared singletons. The transport is injected.

---

## 6. Test Strategy

Tests use a `FakeTransport` actor that records the requests it receives
and returns canned `(Data, Int)` tuples. No real network I/O.

### 6.1 Request construction

1. **GET URL contains version query parameter** — fetch with `currentVersion: "v1"`, assert recorded URL has `?version=v1`
2. **Empty currentVersion is forwarded** — fetch with `""`, assert query param is present and empty
3. **Bearer token sets Authorization header** — fetcher constructed with token, assert recorded headers contain `Authorization: Bearer <token>`
4. **No bearer token = no Authorization header** — fetcher constructed without token, assert no Authorization header
5. **Accept: application/json header always set**

### 6.2 Response handling

6. **200 with valid config returns .updated** — assert decoded config equals canned config
7. **304 returns .notModified**
8. **401 throws unauthorized**
9. **403 throws unauthorized**
10. **404 throws clientError**
11. **500 throws serverError**
12. **503 throws serverError**
13. **Unexpected status (e.g. 201) throws unexpectedStatus**

### 6.3 Decode + validation

14. **Garbage body throws decodeFailed**
15. **Valid JSON of wrong shape throws decodeFailed** (e.g. missing required field)
16. **Decoded config with mismatched weights/features throws validationFailed** — encode a hand-built dict with `features: [a, b]`, `weights: [1.0]`, assert validationFailed
17. **Decoded config with non-positive stdDev throws validationFailed**
18. **Roundtrip: encode bundledDefault → fake transport returns those bytes → decoded result equals bundledDefault**

### 6.4 Transport failures

19. **Transport throws → fetcher throws transportFailed wrapping it**

### 6.5 Integration

20. **End-to-end with InMemoryConfigStore:** caller pattern from §3.4 using FakeTransport returning a fresh config — store ends up holding the new config. Then second fetch returns 304 — store is unchanged.

---

## 7. Files to add

| File | Purpose |
|---|---|
| `Sources/BioFeedbackKit/Algorithm/Transport.swift` | Protocol + `URLSessionTransport` |
| `Sources/BioFeedbackKit/Algorithm/ConfigFetcher.swift` | Protocol + `ConfigFetchResult` + `ConfigFetcherError` |
| `Sources/BioFeedbackKit/Algorithm/RemoteConfigFetcher.swift` | Concrete impl |
| `Tests/BioFeedbackKitTests/ConfigFetcherTests.swift` | All tests + `FakeTransport` actor |

Module placement: `Algorithm/` directory alongside existing files.

---

## 8. Approval Checklist

- [x] Scope, transport, auth, conditional fetch, validation, save policy, retry, JSON shape — all confirmed
- [ ] User approves writing tests BEFORE implementation

---

## 9. References

- ConfigStore proposal: `project/plans/completed/2026-04-07_ConfigStore-v1.md`
- Algorithm layer proposal: `project/plans/completed/2026-04-07_AlgorithmLayer-v1.md`
- Master Plan: "OTA algorithm updates via config, not code"
