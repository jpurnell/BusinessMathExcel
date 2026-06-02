import Foundation

/// A probability distribution for Monte Carlo input variation.
public enum Distribution: Sendable, Equatable {

    /// Normal (Gaussian) distribution with the given mean and standard deviation.
    case normal(mean: Double, stdDev: Double)

    /// Uniform distribution between min and max.
    case uniform(min: Double, max: Double)

    /// Triangular distribution with min, mode (most likely), and max.
    case triangular(min: Double, mode: Double, max: Double)

    /// Log-normal distribution with the given mu and sigma of the underlying normal.
    case lognormal(mu: Double, sigma: Double)

    /// Generates a random sample from this distribution.
    ///
    /// - Parameter generator: A random number generator.
    /// - Returns: A sampled value.
    public func sample<G: RandomNumberGenerator>(using generator: inout G) -> Double {
        switch self {
        case .normal(let mean, let stdDev):
            return sampleNormal(mean: mean, stdDev: stdDev, using: &generator)

        case .uniform(let min, let max):
            return Double.random(in: min...max, using: &generator)

        case .triangular(let min, let mode, let max):
            return sampleTriangular(min: min, mode: mode, max: max, using: &generator)

        case .lognormal(let mu, let sigma):
            let normal = sampleNormal(mean: mu, stdDev: sigma, using: &generator)
            return exp(normal)
        }
    }

    private func sampleNormal<G: RandomNumberGenerator>(
        mean: Double,
        stdDev: Double,
        using generator: inout G
    ) -> Double {
        let u1 = Double.random(in: Double.leastNonzeroMagnitude...1, using: &generator)
        let u2 = Double.random(in: 0...1, using: &generator)
        let z = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        return mean + stdDev * z
    }

    private func sampleTriangular<G: RandomNumberGenerator>(
        min: Double,
        mode: Double,
        max: Double,
        using generator: inout G
    ) -> Double {
        let range = max - min
        guard range > 0 else { return min }
        let f = (mode - min) / range
        let u = Double.random(in: 0...1, using: &generator)
        if u < f {
            return min + (range * f * u).squareRoot()
        } else {
            return max - (range * (1 - f) * (1 - u)).squareRoot()
        }
    }
}
