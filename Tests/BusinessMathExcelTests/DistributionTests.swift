import Foundation
import Testing
@testable import BusinessMathExcel

@Suite struct DistributionTests {

    // MARK: - Uniform

    @Test func uniformSamplesInRange() {
        let dist = Distribution.uniform(min: 10, max: 20)
        var rng = makeRNG()

        for _ in 0..<100 {
            let value = dist.sample(using: &rng)
            #expect(value >= 10)
            #expect(value <= 20)
        }
    }

    // MARK: - Normal

    @Test func normalMeanApproximation() {
        let dist = Distribution.normal(mean: 50, stdDev: 5)
        var rng = makeRNG()

        var sum = 0.0
        let n = 10_000
        for _ in 0..<n {
            sum += dist.sample(using: &rng)
        }
        let mean = sum / Double(n)
        #expect(abs(mean - 50) <= 1.0)
    }

    // MARK: - Triangular

    @Test func triangularSamplesInRange() {
        let dist = Distribution.triangular(min: 0, mode: 5, max: 10)
        var rng = makeRNG()

        for _ in 0..<100 {
            let value = dist.sample(using: &rng)
            #expect(value >= 0)
            #expect(value <= 10)
        }
    }

    @Test func triangularDegenerateRange() {
        let dist = Distribution.triangular(min: 5, mode: 5, max: 5)
        var rng = makeRNG()
        let value = dist.sample(using: &rng)
        #expect(abs(value - 5) <= 0.01)
    }

    // MARK: - Lognormal

    @Test func lognormalAlwaysPositive() {
        let dist = Distribution.lognormal(mu: 0, sigma: 1)
        var rng = makeRNG()

        for _ in 0..<100 {
            let value = dist.sample(using: &rng)
            #expect(value > 0)
        }
    }

    // MARK: - Determinism

    @Test func deterministicWithSameRNG() {
        var rng1 = makeRNG()
        var rng2 = makeRNG()
        let dist = Distribution.normal(mean: 0, stdDev: 1)

        let v1 = dist.sample(using: &rng1)
        let v2 = dist.sample(using: &rng2)
        #expect(abs(v1 - v2) <= 1e-10)
    }

    // MARK: - Helpers

    private func makeRNG() -> some RandomNumberGenerator {
        SeededTestRNG(seed: 12345)
    }
}

private struct SeededTestRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
