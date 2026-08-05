# Design Proposal: ConfigStore v1 — Local AlgorithmConfig Persistence

**Status:** APPROVED 2026-04-07 — moving to RED
**Date:** 2026-04-07

## Resolved decisions

1. Default location: `Application Support/Algorithm/` on Darwin, `$XDG_DATA_HOME/Algorithm/` (or `~/.local/share/Algorithm/`) on Linux. "BioFeedbackKit" name deliberately not in the path.
2. No bundle-ID subdirectory — cross-platform Apple + Linux library.
3. Protocol-based (`ConfigStore` protocol; `FileConfigStore` struct + `InMemoryConfigStore` actor).
4. No re-validation on save — trust the decoded shape; revalidation belongs in future `ConfigFetcher`.

---

## 1. Objective

Persist `AlgorithmConfig` to local storage so the app can load the
last-received config on launch instead of always falling back to
`bundledDefault`. Provide a single-slot "current" config plus an
auto-managed "last-known-good" rollback slot.

This is the on-device storage half of the OTA story. The network half
(`ConfigFetcher`) is a separate proposal.

---

## 2. Scope

### 2.1 In scope

| Type | Purpose |
|---|---|
| `ConfigStore` (protocol) | Async load/save/clear interface, injectable for testing |
| `FileConfigStore` (struct) | Production impl: JSON files in Application Support |
| `InMemoryConfigStore` (actor) | Test fake — no disk I/O |
| `ConfigStoreError` (enum) | I/O and decode errors |

### 2.2 NOT in scope

| Deferred | Why |
|---|---|
| `ConfigFetcher` | Network concern, separate proposal |
| Multi-version cache | Single slot is cleaner; rollback covered by last-known-good |
| Encryption | Configs aren't secrets — they're coefficients, not credentials |
| Migration between schema versions | `AlgorithmConfig.version` is data, not schema; if the Codable shape ever changes we'll add a migration proposal then |
| Default-config bootstrapping inside the store | Caller handles `nil` → `bundledDefault` fallback |

---

## 3. Behavior

### 3.1 Two slots

The store manages two files in the same directory:

- `current.json` — the most recently saved config
- `last-known-good.json` — the previous `current.json` (auto-promoted on save)

### 3.2 Save semantics (auto-promote)

`save(_:)` performs an atomic two-step:

1. If `current.json` exists, **rename** it to `last-known-good.json`
   (overwriting any prior LKG).
2. Write the new config to `current.json` via a temp-file + rename.

The rename in step 1 is the "auto-promote" — every successfully-saved
config becomes the LKG when it's superseded. This means:

- First save: only `current.json` exists, LKG is absent.
- Second save: previous current becomes LKG, new config becomes current.
- Nth save: same.

If step 1 succeeds but step 2 fails, the old current is gone but lives
on as LKG — caller can recover via `loadLastKnownGood()`.

### 3.3 Load semantics

- `loadCurrent()` returns the decoded `current.json`, or `nil` if absent.
- `loadLastKnownGood()` returns the decoded `last-known-good.json`, or `nil` if absent.
- Decode failures throw — they aren't silently `nil`. A corrupt file is
  a real bug worth surfacing, not a "fresh install" indistinguishable
  from a missing file.

### 3.4 Clear semantics

`clear()` removes both files (used by tests and a hypothetical "reset
algorithm" user action). Missing files are not an error.

### 3.5 Caller's startup pattern

```swift
let store: any ConfigStore = try FileConfigStore()
let active: AlgorithmConfig
do {
    active = try await store.loadCurrent()
        ?? store.loadLastKnownGood()
        ?? .bundledDefault
} catch {
    // Corrupt current.json — try LKG, then bundled
    active = (try? await store.loadLastKnownGood()) ?? .bundledDefault
}
let algo = try CoreAlgorithm(config: active)
```

The store stays a dumb pipe; the fallback ladder lives at the call site
where it's visible.

---

## 4. API Surface

```swift
import Foundation

public protocol ConfigStore: Sendable {
    /// Returns the most recently saved config, or `nil` if none has
    /// ever been saved.
    /// - Throws: ``ConfigStoreError/decodeFailed(underlying:)`` if the
    ///   stored file exists but cannot be decoded.
    func loadCurrent() async throws -> AlgorithmConfig?

    /// Returns the previously-current config (auto-promoted on the
    /// most recent `save`), or `nil` if `save` has been called fewer
    /// than twice.
    func loadLastKnownGood() async throws -> AlgorithmConfig?

    /// Saves a config as the new current. The previous current (if any)
    /// is auto-promoted to last-known-good.
    func save(_ config: AlgorithmConfig) async throws

    /// Removes both current and last-known-good slots. Missing files
    /// are not an error.
    func clear() async throws
}

public enum ConfigStoreError: Error, Sendable {
    /// The directory could not be created or accessed.
    case directoryUnavailable(path: String, underlying: Error)
    /// A file existed but could not be decoded as `AlgorithmConfig`.
    case decodeFailed(path: String, underlying: Error)
    /// A write operation failed (encode, temp-file write, or rename).
    case writeFailed(path: String, underlying: Error)
}
```

### 4.1 FileConfigStore

```swift
public struct FileConfigStore: ConfigStore {
    /// Directory in which `current.json` and `last-known-good.json` live.
    public let directory: URL

    /// Creates a store rooted at the given directory. Creates the
    /// directory if it doesn't exist.
    public init(directory: URL) throws

    /// Convenience: creates a store at
    /// `Application Support/BioFeedbackKit/AlgorithmConfig/`.
    public init() throws
}
```

JSON encoding uses `JSONEncoder` with `.sortedKeys` and
`.prettyPrinted` (so on-disk diffs are reviewable during development)
and `.iso8601` date strategy. Decoding mirrors.

Atomic write strategy: encode to a temp file in the same directory
(`current.json.tmp.<uuid>`), `fsync`, then `FileManager.replaceItem` to
the final name. This is the standard POSIX-safe pattern and survives
power-loss between steps.

### 4.2 InMemoryConfigStore

```swift
public actor InMemoryConfigStore: ConfigStore {
    public init()
    // protocol methods backed by two `AlgorithmConfig?` ivars
}
```

Actor-based so it's safe to share across tests without locks.

---

## 5. Constraints & Compliance

- **Concurrency:** Protocol is `Sendable`. `FileConfigStore` is a value
  type with no mutable state (it just holds a `URL`). `InMemoryConfigStore`
  is an actor.
- **Safety:** No force unwraps. All I/O errors mapped to `ConfigStoreError`
  with the underlying error attached.
- **No `String(format:)`** anywhere.
- **Atomic writes:** Temp-file + `replaceItem` for both slots. The
  rename in the auto-promote step is also atomic.
- **Swift 6:** Strict concurrency compliant.

---

## 6. Test Strategy

### 6.1 Behavioral tests (run against both `FileConfigStore` and `InMemoryConfigStore`)

Parameterized over the protocol so the same test body covers both impls:

1. **Empty store: loadCurrent returns nil**
2. **Empty store: loadLastKnownGood returns nil**
3. **After one save: loadCurrent returns it, LKG is nil**
4. **After two saves: loadCurrent returns the second, LKG returns the first**
5. **After three saves: loadCurrent returns the third, LKG returns the second** (verifies LKG is "previous", not "first")
6. **Roundtrip preserves all fields** — save bundledDefault, load, assert equality
7. **Roundtrip preserves all OutputTransform variants** — `.raw`, `.sigmoid`, `.linearClamped(min:max:)`
8. **clear() removes both slots** — save twice, clear, both loads return nil
9. **clear() on empty store does not throw**
10. **Save then clear then save: LKG is nil after the second save** (clear actually wiped state)

### 6.2 FileConfigStore-specific tests

11. **Custom directory is created if missing**
12. **Files land at the expected paths** (`<dir>/current.json`, `<dir>/last-known-good.json`)
13. **JSON on disk is human-readable** — load the raw bytes, decode as `[String: Any]`, assert `version` key exists
14. **Corrupt current.json throws decodeFailed** — write garbage to the file, assert throw
15. **Corrupt LKG does not affect loadCurrent** — write valid current + garbage LKG, loadCurrent succeeds
16. **Two FileConfigStores at the same directory see each other's writes** — store A saves, store B loads, equality holds (verifies no in-memory caching)

### 6.3 Integration test

17. **Startup ladder: missing → bundledDefault** — empty store + the fallback pattern from §3.5 produces `bundledDefault`
18. **Startup ladder: corrupt current → LKG used** — save valid config, save valid second config, corrupt current.json on disk, fallback pattern returns the LKG (the first config)

---

## 7. Files to add

| File | Purpose |
|---|---|
| `Sources/BioFeedbackKit/Algorithm/ConfigStore.swift` | Protocol + `ConfigStoreError` |
| `Sources/BioFeedbackKit/Algorithm/FileConfigStore.swift` | JSON file impl |
| `Sources/BioFeedbackKit/Algorithm/InMemoryConfigStore.swift` | Test actor |
| `Tests/BioFeedbackKitTests/ConfigStoreTests.swift` | All tests in one suite |

Module placement: `Algorithm/` directory alongside the existing
`AlgorithmConfig.swift`. Tests use `FileManager.default.temporaryDirectory`
for `FileConfigStore` instances and clean up in test teardown.

---

## 8. Open Questions

### 8.1 Where does `FileConfigStore()` (the no-arg convenience) put its files?

Three options:

- **`Application Support/BioFeedbackKit/AlgorithmConfig/`** — standard for app data, not user-visible, persists across launches, excluded from iCloud by default. **Recommended.**
- **`Caches/...`** — wrong semantically; the OS may purge it.
- **`Documents/...`** — wrong; user-visible in the Files app, would clutter the user's namespace.

**Recommendation:** Application Support.

### 8.2 Bundle ID subdirectory?

Application Support is per-app already on iOS, but on macOS multiple
apps share the directory. Should the path include the bundle ID?

- **No** — iOS-only library, Application Support is already isolated.
- **Yes, defensive** — `Application Support/<bundleID>/BioFeedbackKit/AlgorithmConfig/` works on both iOS and macOS without surprises.

**Recommendation:** No bundle-ID subdirectory in v1. BioFeedbackKit is
iOS-targeted; if a macOS host app ever ships, it can pass an explicit
`directory:` to the designated init.

### 8.3 Should `ConfigStore` be an actor instead of a protocol?

A protocol is more flexible (multiple impls, easier mocking) but means
each impl decides its own concurrency story. An `actor`-based design
would centralize the locking but make the in-memory test fake awkward.

**Recommendation:** Protocol. `FileConfigStore` is stateless (a `URL`
holder), `InMemoryConfigStore` is an actor. Best of both.

### 8.4 Should `save` validate the config before writing?

`AlgorithmConfig.init` already validates shape (mismatched weights,
non-positive stdDev). A config that came in via Codable bypasses that
validation — the decoded properties are populated directly.

Two options:

- **Trust the decoded shape** — if it round-tripped through JSON, it
  was valid when written. Save without re-validating.
- **Re-validate on save** — call a hypothetical `AlgorithmConfig.validate()`
  before writing.

**Recommendation:** Trust the shape for v1. We can add a `validate()`
helper to `AlgorithmConfig` later if `ConfigFetcher` needs it for
incoming network payloads — that's the right layer for "did the server
send us garbage" checks, not the store.

---

## 9. Approval Checklist

- [ ] User approves the v1 scope (single-slot + auto-promoted LKG, no fetcher, no encryption)
- [ ] User approves the API surface in §4
- [ ] User approves auto-promote-on-save semantics (no explicit `promoteToLKG`)
- [ ] User approves the caller-side fallback ladder pattern (§3.5) instead of store-side defaulting
- [ ] User approves the 4 open questions in §8 (or amends)
- [ ] User approves writing tests BEFORE implementation

---

## 10. References

- Algorithm layer proposal: `project/plans/completed/2026-04-07_AlgorithmLayer-v1.md` — defines `AlgorithmConfig` (the type this store persists)
- Master Plan: "OTA algorithm updates via config, not code"
- Apple File System Programming Guide: Application Support directory conventions
