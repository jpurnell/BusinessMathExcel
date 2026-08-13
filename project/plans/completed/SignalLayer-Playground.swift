// SignalLayer-Playground.swift
//
// Drop this into a Swift Playground (or run with `swift SignalLayer-Playground.swift`)
// to verify the HRV metric formulas BEFORE any tests or implementation are written.
//
// Reference: Task Force of the European Society of Cardiology and the North American
// Society of Pacing and Electrophysiology. (1996). "Heart rate variability: Standards
// of measurement, physiological interpretation, and clinical use." Circulation, 93(5),
// 1043–1065. Section 3.1, Time Domain Methods.
//
// All formulas are implemented by hand (no BusinessMath dependency) so the values
// printed here serve as an independent ground truth for the test fixtures in
// HRVMetricsTests.

import Foundation

// MARK: - Primary fixture

let rr: [Double] = [800, 820, 790, 810, 830, 805]

print("=== Primary fixture ===")
print("RR intervals (ms):", rr)
print("n =", rr.count)
print()

// MARK: - Successive differences

let diffs = zip(rr.dropFirst(), rr).map { $0 - $1 }
print("Successive diffs (ms):", diffs)
// Expected: [20.0, -30.0, 20.0, 20.0, -25.0]
print()

// MARK: - RMSSD

let squared = diffs.map { $0 * $0 }
let meanOfSquared = squared.reduce(0, +) / Double(squared.count)
let rmssd = meanOfSquared.squareRoot()
print("Squared diffs:", squared)
print("Mean of squared diffs:", meanOfSquared)
print("RMSSD (ms):", rmssd)
// Expected: 23.345235059857504
print()

// MARK: - Mean NN

let meanRR = rr.reduce(0, +) / Double(rr.count)
print("Mean NN (ms):", meanRR)
// Expected: 809.1666666666666
print()

// MARK: - SDNN (sample stdev, n-1 denominator)

let squaredDeviations = rr.map { ($0 - meanRR) * ($0 - meanRR) }
let sampleVariance = squaredDeviations.reduce(0, +) / Double(rr.count - 1)
let sdnn = sampleVariance.squareRoot()
print("Squared deviations:", squaredDeviations)
print("Sample variance:", sampleVariance)
print("SDNN (ms):", sdnn)
// Expected: 14.288690166235207
print()

// MARK: - pNN50 (n-1 denominator, strict greater than 50)

let exceeding50 = diffs.filter { abs($0) > 50 }.count
let pnn50 = Double(exceeding50) / Double(diffs.count)
print("Diffs exceeding 50 ms (strict):", exceeding50)
print("pNN50:", pnn50)
// Expected: 0.0
print()

// MARK: - Secondary fixtures

func summarize(_ label: String, _ values: [Double], threshold: Double = 50.0) {
    print("=== \(label) ===")
    print("RR:", values)
    let d = zip(values.dropFirst(), values).map { $0 - $1 }
    let sq = d.map { $0 * $0 }
    let r = (sq.reduce(0, +) / Double(max(sq.count, 1))).squareRoot()
    let m = values.reduce(0, +) / Double(values.count)
    let sdv = values.map { ($0 - m) * ($0 - m) }
    let s = (sdv.reduce(0, +) / Double(max(values.count - 1, 1))).squareRoot()
    let p = Double(d.filter { abs($0) > threshold }.count) / Double(max(d.count, 1))
    print("  RMSSD:", r)
    print("  Mean NN:", m)
    print("  SDNN:", s)
    print("  pNN(\(threshold)):", p)
    print()
}

summarize("All-70ms-jumps (pNN50 should be 1.0)",
          [800, 870, 800, 870, 800, 870])

summarize("All-50ms-jumps (pNN50 should be 0.0 — strict >)",
          [800, 850, 800, 850, 800, 850])

summarize("Constant intervals (RMSSD=0, SDNN=0, pNN=0)",
          [800, 800, 800, 800])
