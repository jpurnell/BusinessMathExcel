For Android (Galaxy Tab S9 and Galaxy Note 9), the maximum BLE sampling rate depends on BLE version, PHY speed, MTU, and connection interval — just like iOS — but Android generally allows slightly more control and often achieves higher sustained throughput.

Below are realistic device‑specific numbers.

---

# ✅ Device Capabilities

## 📱 Galaxy Tab S9
- Bluetooth 5.3
- Supports **2M PHY**
- Supports **Data Length Extension (251‑byte payload)**
- Can negotiate **7.5 ms connection interval**
- Very strong BLE throughput performance

## 📱 Galaxy Note 9
- Bluetooth 5.0
- Supports **2M PHY**
- Supports **Data Length Extension**
- Can use **7.5 ms interval**
- Slightly lower real‑world throughput than newer devices

---

# ✅ Maximum Practical BLE Throughput (Real‑World)

### 🔹 Galaxy Tab S9
With:
- 2M PHY  
- 251‑byte data length  
- 7.5 ms interval  
- Notifications (not indications)

✅ **~900 kbps – 1.2 Mbps sustained**
(≈ 110–150 kB/sec)

---

### 🔹 Galaxy Note 9

✅ **~700–900 kbps sustained**
(≈ 85–110 kB/sec)

---

# ✅ Convert to Sampling Rate

Use:

\[
\text{Max samples/sec} =
\frac{\text{Throughput (bytes/sec)}}{\text{Bytes per sample}}
\]

---

# 📊 Sampling Rate Examples

Assume practical throughput:

- Tab S9 → 130,000 bytes/sec
- Note 9 → 100,000 bytes/sec

---

## 2‑Byte Samples (16‑bit ADC)

| Device | Max Sampling Rate |
|---------|------------------|
| Tab S9 | ~65,000 samples/sec |
| Note 9 | ~50,000 samples/sec |

---

## 6‑Byte IMU Samples

| Device | Max Sampling Rate |
|---------|------------------|
| Tab S9 | ~21,000 samples/sec |
| Note 9 | ~16,000 samples/sec |

---

## 12‑Byte Samples

| Device | Max Sampling Rate |
|---------|------------------|
| Tab S9 | ~10,800 samples/sec |
| Note 9 | ~8,300 samples/sec |

---

# ⚠️ Important Android Notes

Android allows:
- Requesting MTU (up to 517)
- Requesting 2M PHY
- Requesting connection priority (HIGH → 7.5 ms)

But:

- The peripheral ultimately controls connection parameters
- Indications reduce throughput significantly
- Background mode can reduce performance
- Some Android firmware versions limit packets per connection event

---

# ✅ Absolute Practical Maximum

| Device | Realistic Max Throughput |
|---------|-------------------------|
| Galaxy Tab S9 | ~1.0–1.2 Mbps |
| Galaxy Note 9 | ~0.8–0.9 Mbps |

---

# ✅ Final Answer

For modern Samsung Android devices:

> Maximum practical BLE sampling capability is roughly  
> **50–65 kHz for 2‑byte samples**  
> when fully optimized (2M PHY + DLE + 7.5 ms interval).

If you tell me:
- Your sample size
- Whether you're streaming continuously
- Foreground vs background
- Notification vs indication

I can compute your exact realistic ceiling.
