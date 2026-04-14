import Foundation
import Dependencies
import Supabase

/// Phase 8.01-8.02: Real-time alert system with 5-dimension multiplicative scoring.
/// Any zero dimension kills the alert. Hard cap: 3/day, 60-min minimum gap.
actor AlertEngine {
    static let shared = AlertEngine()

    @Dependency(\.supabaseClient) private var supabaseClient

    // MARK: - Types

    struct AlertCandidate: Sendable {
        let source: String
        let title: String
        let body: String
        let rawSalience: Double
        let rawConfidence: Double
        let timeSensitivity: Double
        let rawActionability: Double
    }

    struct ScoredAlert: Sendable {
        let candidate: AlertCandidate
        let compositeScore: Double
        let salience: Double
        let confidence: Double
        let timeSensitivity: Double
        let actionability: Double
        let cognitiveStatePermit: Double
    }

    enum AlertDecision: Sendable {
        case interrupt(ScoredAlert)
        case holdForBriefing(ScoredAlert)
        case discard
    }

    // MARK: - State (8.02)

    private var alertsDeliveredToday: [Date] = []
    private var lastAlertTime: Date?
    private var recentActionabilityRates: [Bool] = [] // Rolling 20-alert window

    private let maxAlertsPerDay = 3
    private let minimumGapSeconds: TimeInterval = 3600 // 60 minutes
    private let interruptThreshold = 0.5
    private let holdThreshold = 0.2

    // MARK: - Scoring (8.01)

    /// Score an alert candidate using 5-dimension multiplicative formula
    func scoreAlert(_ candidate: AlertCandidate, cognitivePermit: Double) -> AlertDecision {
        // 5 dimensions — any zero kills the alert
        let salience = candidate.rawSalience
        let confidence = candidate.rawConfidence
        let timeSensitivity = candidate.timeSensitivity
        let actionability = candidate.rawActionability
        let cognitiveStatePermit = cognitivePermit

        let composite = salience * confidence * timeSensitivity * actionability * cognitiveStatePermit

        let scored = ScoredAlert(
            candidate: candidate,
            compositeScore: composite,
            salience: salience,
            confidence: confidence,
            timeSensitivity: timeSensitivity,
            actionability: actionability,
            cognitiveStatePermit: cognitiveStatePermit
        )

        // Frequency management (8.02)
        if !canDeliverAlert() {
            if composite > holdThreshold {
                return .holdForBriefing(scored)
            }
            return .discard
        }

        // Adaptive threshold from actionability history (8.02)
        let effectiveThreshold = adjustedInterruptThreshold()

        if composite > effectiveThreshold {
            return .interrupt(scored)
        } else if composite > holdThreshold {
            return .holdForBriefing(scored)
        }
        return .discard
    }

    /// Record that an alert was delivered
    func recordDelivery(wasActionable: Bool) {
        let now = Date()
        alertsDeliveredToday.append(now)
        lastAlertTime = now

        recentActionabilityRates.append(wasActionable)
        if recentActionabilityRates.count > 20 {
            recentActionabilityRates.removeFirst()
        }

        // Prune old daily entries
        let startOfDay = Calendar.current.startOfDay(for: now)
        alertsDeliveredToday = alertsDeliveredToday.filter { $0 >= startOfDay }
    }

    // MARK: - Frequency Management (8.02)

    private func canDeliverAlert() -> Bool {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        // Hard cap: 3/day
        let todayCount = alertsDeliveredToday.filter { $0 >= startOfDay }.count
        if todayCount >= maxAlertsPerDay { return false }

        // Minimum gap: 60 minutes
        if let last = lastAlertTime, now.timeIntervalSince(last) < minimumGapSeconds {
            return false
        }

        return true
    }

    /// Raise threshold 30% if actionability rate drops below 60%
    private func adjustedInterruptThreshold() -> Double {
        guard recentActionabilityRates.count >= 5 else { return interruptThreshold }

        let actionableCount = recentActionabilityRates.filter { $0 }.count
        let rate = Double(actionableCount) / Double(recentActionabilityRates.count)

        if rate < 0.6 {
            return interruptThreshold * 1.3
        }
        return interruptThreshold
    }

    /// Today's remaining alert budget
    var remainingAlertBudget: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayCount = alertsDeliveredToday.filter { $0 >= startOfDay }.count
        return max(0, maxAlertsPerDay - todayCount)
    }

    // MARK: - Dual-Scoring Integration (v3-05 research)

    /// RT score thresholds from research:
    /// >= 0.90: alert immediately, no batch gate
    /// 0.80-0.89: alert with "Preliminary" label
    /// 0.75-0.79: queue for batch confirmation only
    /// < 0.75: no alert
    static let rtAlertImmediate = 0.90
    static let rtAlertPreliminary = 0.80
    static let rtAlertBatchGate = 0.75

    /// Evaluate an observation's RT score and determine alert action.
    /// Called by Tier0Writer after RT scoring completes.
    func evaluateRTScore(
        observationId: UUID,
        rtScore: Double,
        source: String,
        summary: String?,
        hasUpcomingDeadline: Bool = false
    ) -> AlertDecision {
        // Deadline modifier: lower threshold by 0.10 within 48h of deadline
        let effectiveScore = hasUpcomingDeadline ? rtScore + 0.10 : rtScore

        if effectiveScore >= Self.rtAlertImmediate {
            let candidate = AlertCandidate(
                source: source,
                title: "High-importance signal detected",
                body: summary ?? "An observation scored \(String(format: "%.0f%%", rtScore * 100)) importance",
                rawSalience: rtScore,
                rawConfidence: 0.85,
                timeSensitivity: 0.9,
                rawActionability: 0.7
            )
            return scoreAlert(candidate, cognitivePermit: 1.0)
        } else if effectiveScore >= Self.rtAlertPreliminary {
            let candidate = AlertCandidate(
                source: source,
                title: "Signal flagged (preliminary)",
                body: (summary ?? "Observation") + " — awaiting batch confirmation",
                rawSalience: rtScore,
                rawConfidence: 0.7,
                timeSensitivity: 0.7,
                rawActionability: 0.6
            )
            return scoreAlert(candidate, cognitivePermit: 1.0)
        }
        // Below preliminary threshold: no alert, batch scoring will handle
        return .discard
    }
}
