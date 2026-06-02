import XCTest
@testable import BusinessMathExcel

final class DistributionTests: XCTestCase {

    // MARK: - Uniform

    func testUniformSamplesInRange() {
        let dist = Distribution.uniform(min: 10, max: 20)
        var rng = makeRNG()

        for _ in 0..<100 {
            let value = dist.sample(using: &rng)
            XCTAssertGreaterThanOrEqual(value, 10)
            XCTAssertLessThanOrEqual(value, 20)
        }
    }

    // MARK: - Normal

    func testNormalMeanApproximation() {
        let dist = Distribution.normal(mean: 50, stdDev: 5)
        var rng = makeRNG()

        var sum = 0.0
        let n = 10_000
        for _ in 0..<n {
            sum += dist.sample(using: &rng)
        }
        let mean = sum / Double(n)
        XCTAssertEqual(mean, 50, accuracy: 1.0)
    }

    // MARK: - Triangular

    func testTriangularSamplesInRange() {
        let dist = Distribution.triangular(min: 0, mode: 5, max: 10)
        var rng = makeRNG()

        for _ in 0..<100 {
            let value = dist.sample(using: &rng)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 10)
        }
    }

    func testTriangularDegenerateRange() {
        let dist = Distribution.triangular(min: 5, mode: 5, max: 5)
        var rng = makeRNG()
        let value = dist.sample(using: &rng)
        XCTAssertEqual(value, 5, accuracy: 0.01)
    }

    // MARK: - Lognormal

    func testLognormalAlwaysPositive() {
        let dist = Distribution.lognormal(mu: 0, sigma: 1)
        var rng = makeRNG()

        for _ in 0..<100 {
            let value = dist.sample(using: &rng)
            XCTAssertGreaterThan(value, 0)
        }
    }

    // MARK: - Determinism

    func testDeterministicWithSameRNG() {
        var rng1 = makeRNG()
        var rng2 = makeRNG()
        let dist = Distribution.normal(mean: 0, stdDev: 1)

        let v1 = dist.sample(using: &rng1)
        let v2 = dist.sample(using: &rng2)
        XCTAssertEqual(v1, v2, accuracy: 1e-10)
    }

    // MARK: - System RNG

    func testSystemRNGProducesValues() {
        let dist = Distribution.uniform(min: 0, max: 1)
        let value = dist.sample()
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThanOrEqual(value, 1)
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
