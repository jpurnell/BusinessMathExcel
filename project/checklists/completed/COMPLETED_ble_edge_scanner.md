# Implementation Checklist: CoreBluetooth Scanner for Edge Glasses

**Proposal:** `project/plans/proposals/PROPOSAL_ble_edge_scanner.md`  
**Status:** READY FOR ON-DEVICE BLE TEST — all blockers resolved, launch verified sub-second  
**Started:** 2026-04-30  

---

## All Blockers Resolved

### RESOLVED: App Launch Hang (2026-05-04)
- [x] Launch logging confirmed: 0.557s init, 0.087s HomeView ready (~0.65s total)
- [x] Root cause: @State mutation during body evaluation + main-thread SwiftData queries
- [x] Fix: VM creation moved to .task, SwiftData queries run in Task.detached
- [x] "Modifying state during view update" warning eliminated
- [x] App interactive well within 2 seconds

### RESOLVED: PeripheralRegistry Mismatch (2026-05-04)
- [x] HomeView now takes `peripheralRegistry` as injected `let` (not `@State`)
- [x] NarbisIOSApp passes its single registry to both EdgeBLEScanner and HomeView
- [x] Scanner and VM now share the same registry instance

### RESOLVED: Edge Glasses Not Appearing in BLE Scan (2026-05-04)
- [x] Confirmed advertising name is `Narbis_Edge` via nRF Connect
- [x] Added `"Narbis_Edge"` as first entry in `edgeNamePrefixes`
- [x] Set `discoveryMode = false` — only Edge devices shown
- [x] BLE-only devices don't appear in system Bluetooth settings (expected behavior)

---

## Completed Phases

### Phase 1: PeripheralRegistry — COMPLETE
- [x] `PeripheralRegistry` class with register/build/deregister for inputs and outputs
- [x] Tests: register, build, deregister, clear, replace, nonexistent (10 tests)
- [x] Wired into DeviceConnectViewModel's deviceBuilder
- [x] HomeView.buildDevice uses registry for BLE transport

### Phase 2: CBEdgePeripheral + CoreBluetoothGlassesConnector — COMPLETE
- [x] `CBEdgePeripheral: EdgePeripheral` — wraps CBPeripheral + CBCharacteristic
- [x] Write-with-response via CheckedContinuation
- [x] CBPeripheralDelegate for didWriteValueFor callback
- [x] `CoreBluetoothGlassesConnector: GlassesConnector` actor
- [x] Own CBCentralManager per connector (avoids delegate conflict with scanner)
- [x] connect() → awaitPoweredOn + retrievePeripherals + connect + discoverService + discoverCharacteristic
- [x] disconnect() → cancelPeripheralConnection
- [x] Connection timeout (15 seconds) via TaskGroup race
- [x] Map CB errors to GlassesConnectorError cases
- [x] CBDelegateProxy (NSObject) bridges CB callbacks → async continuations

### Phase 3: EdgeBLEScanner — COMPLETE (code written, on-device unverified)
- [x] `EdgeBLEScanner: DeviceScanning` — owns lazy CBCentralManager
- [x] Yield DiscoveredDevice with `.output` role on didDiscover
- [x] Register OutputBuilder in PeripheralRegistry on discovery (with TintMapper)
- [x] Deduplicate by peripheral UUID
- [x] Handle centralManagerDidUpdateState (poweredOff, unauthorized)
- [x] stopScan cleans up
- [x] os.Logger diagnostics
- [x] Removed name-nil filter (unnamed devices now shown)
- [x] Service UUID detection from advertisement data

### Phase 4: HomeView + App Shell Wiring — COMPLETE (code written, on-device unverified)
- [x] Add `inputScanner` + `outputScanner` params to HomeView init (default: NoOpScanner)
- [x] NoOpScanner promoted to `public` for default parameter access
- [x] `prepareConnectViewModel()` uses injected scanners
- [x] NarbisIOSApp creates EdgeBLEScanner (scanner owns its own CBCentralManager)
- [x] NarbisIOSApp passes scanner to HomeView as outputScanner
- [x] Enable output section in ConnectViewConfig (`showOutputSection: true`)
- [x] Add `NSBluetoothAlwaysUsageDescription` to Info.plist
- [x] Add `bluetooth-central` to UIBackgroundModes
- [x] Backward-compatible: watchOS/visionOS use default NoOpScanner
- [x] All 484 existing tests pass (348 + 136)

### Phase 4.5: configureSession Protocol Addition — COMPLETE (code, untested on device)
- [x] `FeedbackDevice.configureSession(breathingRate:duration:)` with default no-op
- [x] `EdgeGlassesDevice.configureSession()` delegates to `startSession()`
- [x] `TrainingViewModel` calls `configureSession()` between connect() and render()

### Phase 5: Xcode Project Configuration — COMPLETE (user configured)
- [x] Add `EdgeSDK-Swift` as local package to Xcode project
- [x] Add `BioFeedbackKit-EdgeBLE` as local package to Xcode project
- [x] Link `EdgeSDK`, `BioFeedbackKitEdgeBLE` frameworks to NarbisIOS target
- [x] Add BLE/*.swift files to NarbisIOS target membership
- [ ] Build in Xcode — resolve any remaining import issues

### Phase 6: Reconnection + Polish (deferred)
- [ ] `retrievePeripherals` for fast reconnect to known Edge
- [ ] Bluetooth-off / unauthorized banners in ConnectView
- [ ] RSSI-based signal strength indicator (nice-to-have)

### Phase 7: On-Device Integration Test
- [ ] Edge glasses appear in ConnectView output list
- [ ] Select Edge + Connect → BLE connection succeeds
- [ ] render() loop drives real lens tint changes during training
- [ ] "Always use this device" auto-reconnects on next launch
- [ ] Bluetooth-off shows appropriate guidance

---

**Last Updated:** 2026-05-04
