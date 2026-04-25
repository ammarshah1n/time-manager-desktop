import Foundation

/// Phase 7.04: Bayesian Online Change Point Detection (BOCPD)
/// Detects structural changes in behavioural time series at 3 levels: signal, pattern, trait.
/// Uses student-t predictive probability with hazard rate 1/250.
///
/// Change point probability > 0.7 → 14-day quarantine.
/// CDI (Change Detection Index) >= 0.65 → genuine change, version the trait.
/// CDI < 0.65 → transient, log as episodic.
struct BOCPDDetector: Sendable {

    /// Configuration for the detector
    struct Config: Sendable {
        var hazardRate: Double = 1.0 / 250.0
        var changepointThreshold: Double = 0.7
        var quarantineDays: Int = 14
        var cdiThreshold: Double = 0.65
    }

    /// Result of a changepoint analysis
    struct ChangePointResult: Sendable {
        let isChangepoint: Bool
        let probability: Double
        let runLength: Int
        let cdi: Double?
        let recommendation: ChangeRecommendation
    }

    enum ChangeRecommendation: Sendable {
        case noChange
        case quarantine(days: Int)
        case genuineChange
        case transientEpisode
    }

    /// CDI (Change Detection Index) components
    struct CDIComponents: Sendable {
        let magnitude: Double      // 0.40 weight — how big is the shift
        let consistency: Double    // 0.35 weight — how consistent across observations
        let crossLevelConcordance: Double  // 0.25 weight — does it show at multiple tiers
    }

    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Online Detection

    /// Run BOCPD on a time series of observations.
    /// Returns the changepoint probability for the most recent observation.
    func detectChangepoint(observations: [Double]) -> ChangePointResult {
        guard observations.count >= 10 else {
            return ChangePointResult(isChangepoint: false, probability: 0, runLength: observations.count, cdi: nil, recommendation: .noChange)
        }

        let n = observations.count

        // Run length probabilities: r[i] = probability that current run length is i
        var runLengthProbs = [Double](repeating: 0, count: n + 1)
        runLengthProbs[0] = 1.0

        // Sufficient statistics for student-t predictive
        var sumX = [Double](repeating: 0, count: n + 1)
        var sumX2 = [Double](repeating: 0, count: n + 1)
        var counts = [Int](repeating: 0, count: n + 1)

        // Prior parameters for student-t
        let mu0 = observations.prefix(min(20, n)).reduce(0, +) / Double(min(20, n))
        let kappa0 = 1.0
        let alpha0 = 1.0
        let beta0 = 1.0

        var maxChangepointProb = 0.0

        for t in 0..<n {
            let x = observations[t]
            var newRunLengthProbs = [Double](repeating: 0, count: t + 2)

            // Growth probabilities
            for r in 0...t {
                let predictiveProb = studentTPredictive(
                    x: x, n: counts[r], sumX: sumX[r], sumX2: sumX2[r],
                    mu0: mu0, kappa0: kappa0, alpha0: alpha0, beta0: beta0
                )
                let growthProb = runLengthProbs[r] * predictiveProb * (1.0 - config.hazardRate)
                let changepointProb = runLengthProbs[r] * predictiveProb * config.hazardRate

                newRunLengthProbs[r + 1] += growthProb
                newRunLengthProbs[0] += changepointProb
            }

            // Normalize
            let total = newRunLengthProbs.reduce(0, +)
            if total > 0 {
                for i in 0..<newRunLengthProbs.count {
                    newRunLengthProbs[i] /= total
                }
            }

            // Update sufficient statistics
            for r in stride(from: t, through: 0, by: -1) {
                sumX[r + 1] = sumX[r] + x
                sumX2[r + 1] = sumX2[r] + x * x
                counts[r + 1] = counts[r] + 1
            }
            sumX[0] = 0
            sumX2[0] = 0
            counts[0] = 0

            runLengthProbs = newRunLengthProbs
            maxChangepointProb = newRunLengthProbs[0]
        }

        // Find most probable run length
        var maxRL = 0
        var maxRLProb = 0.0
        for (i, p) in runLengthProbs.enumerated() {
            if p > maxRLProb {
                maxRLProb = p
                maxRL = i
            }
        }

        let isChangepoint = maxChangepointProb > config.changepointThreshold

        if isChangepoint {
            return ChangePointResult(
                isChangepoint: true,
                probability: maxChangepointProb,
                runLength: maxRL,
                cdi: nil,
                recommendation: .quarantine(days: config.quarantineDays)
            )
        }

        return ChangePointResult(
            isChangepoint: false,
            probability: maxChangepointProb,
            runLength: maxRL,
            cdi: nil,
            recommendation: .noChange
        )
    }

    // MARK: - CDI Computation

    /// Compute Change Detection Index after quarantine period.
    /// CDI = magnitude (0.40) + consistency (0.35) + cross-level concordance (0.25)
    func computeCDI(components: CDIComponents) -> (score: Double, recommendation: ChangeRecommendation) {
        let cdi = components.magnitude * 0.40
            + components.consistency * 0.35
            + components.crossLevelConcordance * 0.25

        let recommendation: ChangeRecommendation
        if cdi >= config.cdiThreshold {
            recommendation = .genuineChange
        } else {
            recommendation = .transientEpisode
        }

        return (cdi, recommendation)
    }

    /// Compute magnitude from pre/post changepoint distributions
    func computeMagnitude(preSeries: [Double], postSeries: [Double]) -> Double {
        guard !preSeries.isEmpty, !postSeries.isEmpty else { return 0 }

        let preMean = preSeries.reduce(0, +) / Double(preSeries.count)
        let postMean = postSeries.reduce(0, +) / Double(postSeries.count)

        let preVar = preSeries.map { ($0 - preMean) * ($0 - preMean) }.reduce(0, +) / Double(preSeries.count)
        let postVar = postSeries.map { ($0 - postMean) * ($0 - postMean) }.reduce(0, +) / Double(postSeries.count)

        let pooledStd = sqrt((preVar + postVar) / 2.0)
        guard pooledStd > 0 else { return 0 }

        // Cohen's d_z (within-person effect size)
        let cohenD = abs(postMean - preMean) / pooledStd

        // Normalize to 0-1 range (d >= 0.5 is medium effect, mapped to ~0.5+)
        return min(1.0, cohenD / 2.0)
    }

    /// Compute consistency from observation-level agreement
    func computeConsistency(observations: [Bool]) -> Double {
        guard !observations.isEmpty else { return 0 }
        let agreeing = observations.filter { $0 }.count
        return Double(agreeing) / Double(observations.count)
    }

    // MARK: - Student-t Predictive

    /// Student-t predictive probability for Normal-Inverse-Gamma conjugate model
    private func studentTPredictive(
        x: Double, n: Int, sumX: Double, sumX2: Double,
        mu0: Double, kappa0: Double, alpha0: Double, beta0: Double
    ) -> Double {
        let kappaN = kappa0 + Double(n)
        let alphaN = alpha0 + Double(n) / 2.0
        let muN = (kappa0 * mu0 + sumX) / kappaN
        let betaN = beta0 + 0.5 * (sumX2 - sumX * sumX / max(1, Double(n)))
            + 0.5 * kappa0 * Double(n) * (mu0 - sumX / max(1, Double(n))) * (mu0 - sumX / max(1, Double(n))) / kappaN

        let nu = 2.0 * alphaN
        let sigma2 = betaN * (kappaN + 1.0) / (alphaN * kappaN)

        guard sigma2 > 0 else { return 1e-10 }

        // Student-t PDF — broken into sub-expressions for Swift type-checker
        let z: Double = (x - muN) * (x - muN) / sigma2
        let term1: Double = lgamma((nu + 1.0) / 2.0)
        let term2: Double = lgamma(nu / 2.0)
        let term3: Double = 0.5 * log(nu * Double.pi * sigma2)
        let term4: Double = ((nu + 1.0) / 2.0) * log(1.0 + z / nu)
        let logProb: Double = term1 - term2 - term3 - term4

        return max(1e-300, exp(logProb))
    }
}
