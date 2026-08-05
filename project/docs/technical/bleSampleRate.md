There is no single fixed “maximum sampling rate” on iOS. It depends on BLE link parameters and how much data you send per sample.

Here’s what actually limits you.

---

# ✅ iOS BLE Limits (Central ↔ Peripheral)

## 1️⃣ Minimum Connection Interval
- Minimum allowed by spec: **7.5 ms**
- iOS typically allows **7.5–15 ms** in high‑performance scenarios
- 7.5 ms → **133 connection events per second**

---

## 2️⃣ Maximum Practical Throughput on Modern iPhones

With:
- BLE 4.2+ (Data Length Extension enabled)
- 251‑byte packet length
- 2M PHY (BLE 5)
- 7.5 ms connection interval
- Notifications (not indications)

### ✅ Real‑world sustained throughput:
**~700–900 kbps**
(≈ 85–110 kB/sec)

Theoretical maximum is higher (~1.3 Mbps), but iOS does not reach that in practice.

---

# ✅ Convert Throughput to Sampling Rate

Use:

\[
\text{Max samples/sec} = \frac{\text{Throughput (bytes/sec)}}{\text{Bytes per sample}}
\]

Assume ~100,000 bytes/sec practical ceiling.

---

### Example 1: 2‑byte samples (16‑bit ADC)

\[
100,000 / 2 = 50,000 \text{ samples/sec}
\]

✅ ~50 kHz max

---

### Example 2: 6‑byte IMU sample

\[
100,000 / 6 ≈ 16,600 \text{ samples/sec}
\]

✅ ~16 kHz max

---

### Example 3: 12‑byte sensor packet

\[
100,000 / 12 ≈ 8,300 \text{ samples/sec}
\]

✅ ~8 kHz max

---

# ⚠️ If You Do NOT Use DLE (20‑byte MTU)

Older/legacy configuration:

- ~100–150 kbps
- ~12–18 kB/sec

Then:

2‑byte samples → ~7–9 kHz max

---

# 🚨 Important iOS Behavior

- iOS may increase connection interval dynamically
- Background mode drastically reduces throughput
- Indications cut throughput roughly in half
- iOS limits packets per connection event internally
- You cannot force exact parameters from the app side

---

# ✅ Practical Answer

On modern iPhones:

> **Maximum practical BLE data rate: ~800 kbps**
>  
> Equivalent to roughly:
> - **50 kHz for 2‑byte samples**
> - **16 kHz for 6‑byte samples**
> - **8 kHz for 12‑byte samples**

If you tell me:
- Bytes per sample
- iPhone model
- Whether you're using DLE + 2M PHY
- Foreground or background mode

I can compute a more precise real‑world limit for your case.
