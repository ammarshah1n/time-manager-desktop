import Foundation

/// Phase 9.04: Engagement-gated prediction delivery.
/// Controls which prediction types surface based on system maturity + executive engagement.
/// KEY CHANGE: Engagement metrics replace calendar time. Language rules enforced.
struct PredictionGate: Sendable {

    struct SystemMaturity: Sendable {
        let daysActive: Int
        let morningOpenRate: Double          // 0.0-1.0
        let insightsInteracted: Int
        let confirmedSignatures: Int
        let briefingEngagementRate: Double   // 0.0-1.0
        let traitLibrarySize: Int
    }

    enum PredictionTier: Sendable, Comparable {
        case baseRate           // Days 3-14: "Based on your last [N] years..."
        case behaviouralHypothesis // Days 15-30: "I'm beginning to notice..."
        case softPrediction     // Months 2-3: "Patterns consistent with..."
        case firmPrediction     // Months 3-6: "The evidence suggests..."
        case highStakes         // Month 6+: "With high confidence..."
    }

    /// Determine the maximum prediction tier allowed given current maturity
    func maxAllowedTier(maturity: SystemMaturity) -> PredictionTier {
        // Month 6+: full trait library + high engagement → high-stakes
        if maturity.daysActive >= 180, maturity.traitLibrarySize >= 5, maturity.briefingEngagementRate >= 0.7 {
            return .highStakes
        }

        // Months 3-6: 5+ confirmed signatures + 70% engagement → firm predictions
        if maturity.daysActive >= 90, maturity.confirmedSignatures >= 5, maturity.briefingEngagementRate >= 0.7 {
            return .firmPrediction
        }

        // Months 2-3: 3+ confirmed signatures → soft predictions
        if maturity.daysActive >= 60, maturity.confirmedSignatures >= 3 {
            return .softPrediction
        }

        // Days 15-30: 60%+ morning open rate + 1+ insight interacted → behavioural hypotheses
        if maturity.daysActive >= 15, maturity.morningOpenRate >= 0.6, maturity.insightsInteracted >= 1 {
            return .behaviouralHypothesis
        }

        // Days 3-14: base rate only
        if maturity.daysActive >= 3 {
            return .baseRate
        }

        return .baseRate
    }

    /// Minimum confidence required for a prediction at a given tier
    func minimumConfidence(for tier: PredictionTier) -> Double {
        switch tier {
        case .baseRate: return 0.0
        case .behaviouralHypothesis: return 0.55
        case .softPrediction: return 0.65
        case .firmPrediction: return 0.75
        case .highStakes: return 0.85
        }
    }

    /// Language framing for a prediction tier
    func languagePrefix(for tier: PredictionTier) -> String {
        switch tier {
        case .baseRate:
            return "Based on your data"
        case .behaviouralHypothesis:
            return "I'm beginning to notice"
        case .softPrediction:
            return "Patterns consistent with"
        case .firmPrediction:
            return "The evidence suggests"
        case .highStakes:
            return "With high confidence"
        }
    }

    /// Filter predictions for delivery based on current maturity
    func filterForDelivery(
        predictions: [PredictionCandidate],
        maturity: SystemMaturity
    ) -> [PredictionCandidate] {
        let maxTier = maxAllowedTier(maturity: maturity)

        return predictions.filter { prediction in
            // Tier check
            guard prediction.tier <= maxTier else { return false }

            // Confidence check
            let minConfidence = minimumConfidence(for: prediction.tier)
            guard prediction.confidence >= minConfidence else { return false }

            return true
        }
    }

    struct PredictionCandidate: Sendable {
        let id: UUID
        let tier: PredictionTier
        let confidence: Double
        let predictedBehaviour: String
        let predictionType: String
    }
}
