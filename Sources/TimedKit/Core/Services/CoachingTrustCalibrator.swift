import Foundation

/// Phase 8.05: Coaching trust calibration with 4-stage progression.
/// Gated on engagement metrics (not time alone). Rupture protocol on consecutive dismissals.
struct CoachingTrustCalibrator: Sendable {

    enum TrustStage: String, Sendable, Codable, Comparable {
        case establishment   // Days 1-30: intensity 2/10, positive/neutral only
        case calibration     // Days 30-90: intensity 4/10, mild discrepancy observations
        case workingAlliance // Days 90-180: intensity 6/10, avoidance patterns
        case deepObservation // Days 180+: intensity 8/10, full pattern surfacing (never 10/10)

        var maxIntensity: Int {
            switch self {
            case .establishment: return 2
            case .calibration: return 4
            case .workingAlliance: return 6
            case .deepObservation: return 8
            }
        }

        var allowedInsightTypes: [InsightType] {
            switch self {
            case .establishment:
                return [.positive, .neutral, .baseRate]
            case .calibration:
                return [.positive, .neutral, .baseRate, .mildDiscrepancy]
            case .workingAlliance:
                return [.positive, .neutral, .baseRate, .mildDiscrepancy, .avoidancePattern, .prediction]
            case .deepObservation:
                return [.positive, .neutral, .baseRate, .mildDiscrepancy, .avoidancePattern, .prediction, .deepPattern, .burnoutWarning]
            }
        }

        static func < (lhs: TrustStage, rhs: TrustStage) -> Bool {
            let order: [TrustStage] = [.establishment, .calibration, .workingAlliance, .deepObservation]
            let lhsIndex = order.firstIndex(of: lhs) ?? 0
            let rhsIndex = order.firstIndex(of: rhs) ?? 0
            return lhsIndex < rhsIndex
        }
    }

    enum InsightType: Sendable {
        case positive
        case neutral
        case baseRate
        case mildDiscrepancy
        case avoidancePattern
        case prediction
        case deepPattern
        case burnoutWarning
    }

    struct TrustState: Sendable, Codable {
        var currentStage: TrustStage
        var daysActive: Int
        var morningOpenRate: Double           // 0.0-1.0
        var insightsInteracted: Int
        var confirmedSignatures: Int
        var consecutiveDismissals: Int
        var briefingEngagementRate: Double    // 0.0-1.0
        var lastStageChange: Date?
    }

    // MARK: - Stage Progression

    /// Evaluate whether the executive should progress to the next trust stage
    func evaluateProgression(state: TrustState) -> TrustStage {
        var stage = state.currentStage

        // Check for rupture first (8.05)
        if state.consecutiveDismissals >= 3 {
            stage = demoteStage(stage)
            return stage
        }

        // Progression gates (engagement-based, not time-only)
        switch state.currentStage {
        case .establishment:
            // → calibration: 30+ days AND 60%+ open rate AND 1+ insight interacted
            if state.daysActive >= 30, state.morningOpenRate >= 0.6, state.insightsInteracted >= 1 {
                stage = .calibration
            }
        case .calibration:
            // → workingAlliance: 90+ days AND 70%+ engagement AND 3+ confirmed signatures
            if state.daysActive >= 90, state.briefingEngagementRate >= 0.7, state.confirmedSignatures >= 3 {
                stage = .workingAlliance
            }
        case .workingAlliance:
            // → deepObservation: 180+ days AND 70%+ engagement AND 5+ confirmed signatures
            if state.daysActive >= 180, state.briefingEngagementRate >= 0.7, state.confirmedSignatures >= 5 {
                stage = .deepObservation
            }
        case .deepObservation:
            break // Terminal stage (never 10/10)
        }

        return stage
    }

    /// Check if an insight type is allowed at the current trust stage
    func isInsightAllowed(_ type: InsightType, at stage: TrustStage) -> Bool {
        stage.allowedInsightTypes.contains(type)
    }

    /// Clamp insight intensity to the current stage maximum
    func clampIntensity(_ intensity: Int, at stage: TrustStage) -> Int {
        min(intensity, stage.maxIntensity)
    }

    // MARK: - Rupture Protocol

    /// Drop one stage on 3+ consecutive dismissals
    private func demoteStage(_ stage: TrustStage) -> TrustStage {
        switch stage {
        case .establishment: return .establishment
        case .calibration: return .establishment
        case .workingAlliance: return .calibration
        case .deepObservation: return .workingAlliance
        }
    }
}
