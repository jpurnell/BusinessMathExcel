# TestFlight Release Notes — May 21, 2026

**Build:** Post May 14 TestFlight

---

**What's New (since May 14)**

**Tint Response Controls**
User-controllable lens feedback curve — adjust how aggressively the glasses respond to your coherence level. Settings > Tint Response:
- **Floor** — How dark lenses get at worst coherence
- **Ceiling** — How clear lenses get at best coherence
- **Oscillation** — How much the lenses pulse when unfocused
- **Presets** — Subtle, Default, Strong, Max
- Live curve preview and lens gradient strip show your settings visually

**Polar H10 Support**
- Dual-mode discovery: each Polar device shows both a standard "(BLE)" entry and a "(Polar SDK)" entry in the scan list
- **Polar Admin Mode** (Settings > Polar H10 > Polar Admin): battery, firmware, disk info, live HR/ECG/PPI streaming, exercise control, offline recordings, training sessions, device settings, factory reset

**Heart Rate Monitor BLE**
- New standard BLE heart rate connector — works with any BLE HR strap (Garmin, Wahoo, etc.), not just Polar

**Edge Glasses BLE**
- Hardened connection handling and disconnect cleanup
- Improved status notification reliability

**Apple Watch / WatchRelay**
- HealthKit adapter improvements
- Relay message versioning for forward compatibility

---

**What to Test**

1. **Tint Response** — Open Settings > Tint Response. Drag the Floor slider to 255 and Ceiling to 0 — the curve should show full range. Try each preset (Subtle through Max) and verify the curve and lens strip update. Start a session with Edge glasses and confirm the tint feels more pronounced on Strong or Max vs Subtle.

2. **Tint Presets in Practice** — Run a short session on Default, then change to Strong and run another. The difference in lens darkness at low coherence should be obvious.

3. **Polar H10 Discovery** — Scan for HR monitors. A Polar H10 should show two entries: "(BLE)" and "(Polar SDK)". Pair with each in separate sessions and compare how the signal feels.

4. **Polar Admin** — After discovering a Polar H10, go to Settings > Polar H10 > Polar Admin. Verify device info loads (battery, firmware, serial). Toggle the HR stream and confirm live data appears.

5. **Non-Polar HR Straps** — If you have a Garmin/Wahoo/other BLE HR strap, verify it appears in the scan list and works as an input device.

6. **Edge Glasses** — Verify pairing and tint feedback work. Check Glasses Admin still connects on demand from Settings.

7. **Apple Watch Relay** — Start a comparison session (strap + watch). Verify watch relays HR data to phone.

8. **Settings Persistence** — Change tint response settings, kill the app, relaunch. Verify your settings are preserved.

9. **General Stability** — Onboarding, session start/stop, breathing pacer, audio feedback.

**Known Limitations**
- Tint response changes take effect on next app launch (not mid-session)
- Polar Admin requires scanning for the H10 first
- BLE vs Polar SDK comparison is manual — run sessions with each and compare

---

**Pending:** Apple Watch IBI (inter-beat interval) relay integration
