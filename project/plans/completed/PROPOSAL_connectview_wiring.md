# Design Proposal: ConnectView-to-TrainingView Device Wiring

**Status:** COMPLETED (implemented 2026-04-23, commit 7514b88)  
**Date:** 2026-04-23  
**Scope:** NarbisUI (ConnectView, HomeView, TrainingView), NarbisKit (DeviceConnectViewModel, DeviceFactory), iOS app shell  
**Depends on:** DESIGN_PROPOSAL_ios_connect_pairing.md (APPROVED)

---

## Problem

ConnectView currently works for Apple Watch relay and Simulation, but BLE device selection is broken. A user who discovers a Polar H10 or Edge glasses via BLE scanning cannot wire those devices through to TrainingView. The `deviceBuilder` closure lacks a `.bluetoothLE` path, the output device is always nil, and `CBPeripheral` references are lost between discovery and device construction.

---

## Current State Analysis

### What Works
- **`DiscoveredDevice`** value type (NarbisKit/Connect/) — id, name, transport, role, rssi. Codable, Sendable, Equatable. Fully tested.
- **`DeviceScanning`** protocol — `startScan() -> AsyncStream<DiscoveredDevice>` + `stopScan()`
- **`DeviceConnectViewModel`** — `@Observable @MainActor`, manages scan state, selection, remembered-device persistence. Has injected `deviceBuilder` closure. Fully tested (11 tests).
- **`ConnectView`** — SwiftUI Form with input section (Apple Watch, BLE, Simulation), output section (Edge, Screen Only), "Always use this device" toggle, "Connect & Start" button. Takes `onConnected` callback.
- **`WatchRelayDevice`** — actor conforming to `BiofeedbackDevice`, receives RR intervals via WCSession.
- **`InputDeviceFactory` / `OutputDeviceFactory`** typealiases in NarbisKit/DeviceFactory.swift
- **`TrainingView`** accepts `InputDeviceFactory` and `OutputDeviceFactory` closures, passes them to `TrainingViewModel.start()`

### Current Data Flow
```
HomeView [Start Training]
  --> .sheet: ConnectView(DeviceConnectViewModel(NoOpScanner, NoOpScanner, deviceBuilder))
      --> User selects Apple Watch or Simulation (only real options)
      --> "Connect & Start"
      --> viewModel.connect() calls deviceBuilder(selectedInput, selectedOutput)
      --> buildDevice() switches on transport:
            .watchConnectivity -> WatchRelayDevice
            default -> SimulationDevice
      --> Returns (input: device, output: nil)
      --> onConnected fires
      --> HomeView captures device as factory closures
      --> isConnecting = false, isTraining = true
  --> .fullScreenCover: TrainingView(inputDeviceFactory, outputDeviceFactory)
      --> TrainingViewModel.start() calls factories
      --> Session runs
```

### 8 Specific Issues

1. **NoOpScanner placeholder.** HomeView creates `DeviceConnectViewModel` with `NoOpScanner()` — yields zero BLE devices. No real scanning happens.

2. **`deviceBuilder` only handles two transports.** Switches on `.watchConnectivity` (returns `WatchRelayDevice`) and `default` (returns `SimulationDevice`). No `.bluetoothLE` case — selecting a Polar H10 produces a SimulationDevice.

3. **Output device is always nil.** The `deviceBuilder` returns `(input: device, output: nil)` unconditionally. `ConnectViewConfig` sets `showOutputSection: false`.

4. **CBPeripheral reference not threaded through.** `DiscoveredDevice` is a value type (Codable) — stores UUID but not `CBPeripheral`. When `deviceBuilder` receives a `DiscoveredDevice` with `.bluetoothLE` transport, it cannot look up the corresponding peripheral to construct a `PolarDevice` or `EdgeGlassesDevice`.

5. **No auto-connect for remembered devices.** `DeviceConnectViewModel` stores `RememberedDevices` and `alwaysUseThisDevice` in UserDefaults, but HomeView never checks these to skip ConnectView.

6. **SettingsView "Change Device" disconnected.** SettingsView accepts an optional `DeviceConnectViewModel` but HomeView doesn't pass one.

7. **DeviceConnectViewModel recreated per sheet.** Constructed inside `.sheet(isPresented:)` modifier — destroyed and recreated each open, can't be shared with SettingsView.

8. **Sheet-to-fullScreenCover transition timing.** HomeView sets `isConnecting = false` and `isTraining = true` synchronously in `onConnected`. May cause visual artifacts.

---

## Proposed Design

### 1. PeripheralRegistry — Bridge Value Types to CBPeripheral

The core wiring gap: `DiscoveredDevice` (Codable value type) cannot hold a `CBPeripheral` (reference type, not Codable). Introduce a registry that maps UUIDs to builder closures.

```swift
// NarbisKit/Connect/PeripheralRegistry.swift
@MainActor
public final class PeripheralRegistry: Observable {
    public typealias DeviceBuilder = @MainActor @Sendable () -> (any BiofeedbackDevice & Sendable)?
    public typealias OutputBuilder = @MainActor @Sendable () -> (any FeedbackDevice & Sendable)?
    
    private var inputBuilders: [UUID: DeviceBuilder] = [:]
    private var outputBuilders: [UUID: OutputBuilder] = [:]
    
    /// Scanner registers a builder when it discovers a peripheral
    public func registerInput(_ id: UUID, builder: @escaping DeviceBuilder) {
        inputBuilders[id] = builder
    }
    
    public func registerOutput(_ id: UUID, builder: @escaping OutputBuilder) {
        outputBuilders[id] = builder
    }
    
    /// deviceBuilder looks up by DiscoveredDevice.id
    public func buildInput(for id: UUID) -> (any BiofeedbackDevice & Sendable)? {
        inputBuilders[id]?()
    }
    
    public func buildOutput(for id: UUID) -> (any FeedbackDevice & Sendable)? {
        outputBuilders[id]?()
    }
    
    /// Scanners deregister when peripheral disconnects or goes out of range
    public func deregisterInput(_ id: UUID) { inputBuilders.removeValue(forKey: id) }
    public func deregisterOutput(_ id: UUID) { outputBuilders.removeValue(forKey: id) }
    public func clear() { inputBuilders.removeAll(); outputBuilders.removeAll() }
}
```

**Flow:** BLE scanner discovers peripheral → creates `DiscoveredDevice` (value type) for UI + registers builder closure (captures `CBPeripheral`) in registry. `deviceBuilder` calls `registry.buildInput(for: device.id)`.

### 2. Lift DeviceConnectViewModel to HomeView @State

```swift
// HomeView changes
@State private var connectViewModel: DeviceConnectViewModel

init() {
    let registry = PeripheralRegistry()
    _connectViewModel = State(initialValue: DeviceConnectViewModel(
        inputScanner: hrScanner,      // Real BLE scanner (or NoOp until implemented)
        outputScanner: edgeScanner,   // Real BLE scanner (or NoOp until implemented)
        deviceBuilder: { input, output in
            Self.buildDevice(input: input, output: output, registry: registry)
        }
    ))
}
```

This fixes issues #6 (SettingsView can share it) and #7 (persists across sheet presentations).

### 3. Expand deviceBuilder for BLE

```swift
static func buildDevice(
    input: DiscoveredDevice?,
    output: DiscoveredDevice?,
    registry: PeripheralRegistry
) -> (input: any BiofeedbackDevice & Sendable, output: (any FeedbackDevice & Sendable)?) {
    // Input
    let inputDevice: any BiofeedbackDevice & Sendable
    switch input?.transport {
    case .watchConnectivity:
        inputDevice = WatchRelayDevice()
    case .bluetoothLE:
        if let id = input?.id, let device = registry.buildInput(for: id) {
            inputDevice = device
        } else {
            inputDevice = SimulationDevice()  // Fallback
        }
    default:
        inputDevice = SimulationDevice()
    }
    
    // Output
    var outputDevice: (any FeedbackDevice & Sendable)? = nil
    if let output, output.transport == .bluetoothLE,
       let device = registry.buildOutput(for: output.id) {
        outputDevice = device
    }
    
    return (inputDevice, outputDevice)
}
```

### 4. Auto-Connect for Remembered Devices

```swift
// HomeView: "Start Training" button action
func handleStartTraining() {
    if connectViewModel.alwaysUseThisDevice,
       let remembered = connectViewModel.rememberedDevices {
        // Try auto-connect without showing ConnectView
        Task {
            if let devices = await connectViewModel.autoConnect(timeout: .seconds(10)) {
                startSession(input: devices.input, output: devices.output)
            } else {
                // Fall back to showing ConnectView
                isConnecting = true
            }
        }
    } else {
        isConnecting = true
    }
}
```

### 5. Fix Sheet-to-FullScreenCover Transition

```swift
// In onConnected callback:
isConnecting = false
// Delay fullScreenCover to next runloop after sheet dismiss completes
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(300))
    isTraining = true
}
```

### 6. Enable Output Section

Set `ConnectViewConfig.showOutputSection = true` when Edge scanner is available. Start with `false` until BLE Edge scanner proposal is implemented.

---

## Navigation Architecture (Unchanged)

The current architecture is correct:
- **Sheet** for ConnectView (modal device selection)
- **fullScreenCover** for TrainingView (immersive session)
- **NavigationStack** inside ConnectView for drill-down (device details, etc.)

No changes needed to navigation pattern.

---

## Dependencies

| This Proposal | Depends On |
|---------------|------------|
| PeripheralRegistry | None — can implement now |
| BLE input path | PROPOSAL_ble_hr_scanner.md (scanner registers builders) |
| BLE output path | PROPOSAL_ble_edge_scanner.md (scanner registers builders) |
| Auto-connect | Remembered devices already stored; needs scanner cooperation |

**Key insight:** PeripheralRegistry + deviceBuilder expansion can be implemented NOW with the existing NoOpScanners. When real BLE scanners land, they just call `registry.registerInput/Output()` during discovery. Zero changes to wiring code.

---

## Testing Strategy

### Unit Tests (NarbisKitTests)
- `PeripheralRegistryTests`: register/deregister/build/clear
- `DeviceConnectViewModel` expanded: `.bluetoothLE` transport → calls registry
- `DeviceConnectViewModel`: auto-connect with remembered devices
- `DeviceConnectViewModel`: auto-connect timeout falls back

### Integration Tests
- ConnectView → select simulation → TrainingView receives SimulationDevice
- ConnectView → select watch → TrainingView receives WatchRelayDevice
- ConnectView → select BLE (mock) → TrainingView receives mock BiofeedbackDevice from registry

### UI Tests (manual on device)
- Sheet → select → dismiss → fullScreenCover transition is clean
- "Always use this device" → next launch skips ConnectView
- SettingsView "Change Device" opens ConnectView with current selection

---

## Success Criteria

1. Any `DiscoveredDevice` with `.bluetoothLE` transport can be wired through to TrainingView via PeripheralRegistry
2. Output device (Edge glasses) flows through to TrainingView when selected
3. "Always use this device" auto-connects on subsequent launches
4. DeviceConnectViewModel persists across sheet presentations
5. SettingsView can access same DeviceConnectViewModel
6. All 8 identified issues resolved

---

## Open Questions (RESOLVED)

1. **Should PeripheralRegistry live in NarbisKit or app layer?** **RESOLVED: NarbisKit.** No CoreBluetooth types — opaque closures only.
2. **Auto-connect timeout duration?** **RESOLVED: 10 seconds.** Show a spinner.
3. **What happens if remembered device is out of range?** **RESOLVED: Fall back to ConnectView** with info banner: "Couldn't find [device name]. Select a device."
