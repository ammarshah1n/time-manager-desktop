import Foundation

/// Composite Cognitive Load Index (CCLI)
/// Combines: keystroke IKI + error rate + app switch frequency + email latency shifts
/// 5-minute rolling windows. Personal calibration over first 2 weeks.
actor CognitiveLoadIndex {
    static let shared = CognitiveLoadIndex()

    private var baselineMeanIKI: Double?
    private var baselineStdIKI: Double?
    private var baselineAppSwitchRate: Double?
    private var baselineBackspaceRate: Double?

    private var recentIKIs: [Double] = []
    private var recentAppSwitchRates: [Double] = []
    private var recentBackspaceRates: [Double] = []

    private let calibrationSampleCount = 200 // ~14 days of 5-min windows at 8h/day

    /// Record a keystroke window aggregate and compute CCLI
    func recordKeystrokeWindow(
        meanIKI: Double,
        backspaceRate: Double,
        wpm: Double,
        at timestamp: Date
    ) async -> Double? {
        recentIKIs.append(meanIKI)
        recentBackspaceRates.append(backspaceRate)

        // During calibration period, accumulate baseline
        if recentIKIs.count <= calibrationSampleCount {
            if recentIKIs.count == calibrationSampleCount {
                calibrateBaseline()
            }
            return nil // No CCLI during calibration
        }

        return computeCCLI(meanIKI: meanIKI, backspaceRate: backspaceRate)
    }

    /// Record app switch frequency for composite scoring
    func recordAppSwitchRate(_ rate: Double) {
        recentAppSwitchRates.append(rate)
        if recentAppSwitchRates.count > 500 {
            recentAppSwitchRates.removeFirst(recentAppSwitchRates.count - 500)
        }
    }

    private func calibrateBaseline() {
        baselineMeanIKI = recentIKIs.mean
        baselineStdIKI = recentIKIs.standardDeviation
        baselineBackspaceRate = recentBackspaceRates.mean
        baselineAppSwitchRate = recentAppSwitchRates.isEmpty ? nil : recentAppSwitchRates.mean

        let logMean = self.baselineMeanIKI ?? 0
        let logStd = self.baselineStdIKI ?? 0
        let logBackspace = self.baselineBackspaceRate ?? 0
        TimedLogger.dataStore.info(
            "CCLI calibrated: meanIKI=\(logMean)ms, stdIKI=\(logStd)ms, backspaceRate=\(logBackspace)"
        )
    }

    private func computeCCLI(meanIKI: Double, backspaceRate: Double) -> Double {
        guard let baseMean = baselineMeanIKI,
              let baseStd = baselineStdIKI, baseStd > 0,
              let baseBackspace = baselineBackspaceRate
        else { return 0.5 }

        // Z-scores (higher = more cognitive load)
        let ikiZ = (meanIKI - baseMean) / baseStd
        let backspaceZ = baseBackspace > 0 ? (backspaceRate - baseBackspace) / max(baseBackspace * 0.5, 0.01) : 0

        let appSwitchZ: Double
        if let baseSwitch = baselineAppSwitchRate, baseSwitch > 0, let latestSwitch = recentAppSwitchRates.last {
            appSwitchZ = (latestSwitch - baseSwitch) / max(baseSwitch * 0.5, 0.1)
        } else {
            appSwitchZ = 0
        }

        // Weighted composite (0.0 = low load, 1.0 = high load)
        let rawScore = 0.40 * ikiZ + 0.30 * backspaceZ + 0.30 * appSwitchZ
        return max(0, min(1, 0.5 + rawScore * 0.15)) // Sigmoid-like clamping around 0.5
    }
}

// Array statistics helpers
private extension Array where Element == Double {
    var mean: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let avg = mean
        let variance = reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(count - 1)
        return variance.squareRoot()
    }
}
