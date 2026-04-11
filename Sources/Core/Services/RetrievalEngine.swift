import Foundation

struct RetrievalEngine: Sendable {
    private let recencyHalfLife: TimeInterval = 5.8 * 86400
    private let retrievalFloor: Double = 0.15

    func score(
        candidates: [(id: UUID, tier: Int, content: String, occurredAt: Date, importanceScore: Double, cosineSimilarity: Double)],
        intent: RetrievalIntent,
        referenceDate: Date = Date()
    ) -> [RetrievalResult] {
        let weights = intentWeights(for: intent)

        return candidates.compactMap { candidate in
            let recency = exp(-log(2) * referenceDate.timeIntervalSince(candidate.occurredAt) / recencyHalfLife)
            let importance = candidate.importanceScore
            let relevance = max(0, candidate.cosineSimilarity)
            let daysDiff = abs(referenceDate.timeIntervalSince(candidate.occurredAt)) / 86400
            let temporalProximity = 1.0 / (1.0 + daysDiff / 7.0)
            let tierBoost = tierBoostValue(for: candidate.tier)

            let composite =
                weights.recency * recency +
                weights.importance * importance +
                weights.relevance * relevance +
                weights.temporalProximity * temporalProximity +
                weights.tierBoost * tierBoost

            guard composite >= retrievalFloor else { return nil }

            return RetrievalResult(
                id: candidate.id,
                tier: candidate.tier,
                content: candidate.content,
                compositeScore: composite,
                scores: RetrievalScores(
                    recency: recency,
                    importance: importance,
                    relevance: relevance,
                    temporalProximity: temporalProximity,
                    tierBoost: tierBoost
                )
            )
        }
        .sorted { $0.compositeScore > $1.compositeScore }
    }

    private struct Weights {
        let recency: Double
        let importance: Double
        let relevance: Double
        let temporalProximity: Double
        let tierBoost: Double
    }

    private func intentWeights(for intent: RetrievalIntent) -> Weights {
        switch intent {
        case .what:
            return Weights(recency: 0.15, importance: 0.25, relevance: 0.35, temporalProximity: 0.10, tierBoost: 0.15)
        case .when:
            return Weights(recency: 0.10, importance: 0.15, relevance: 0.20, temporalProximity: 0.40, tierBoost: 0.15)
        case .why:
            return Weights(recency: 0.10, importance: 0.20, relevance: 0.30, temporalProximity: 0.10, tierBoost: 0.30)
        case .pattern:
            return Weights(recency: 0.05, importance: 0.20, relevance: 0.30, temporalProximity: 0.15, tierBoost: 0.30)
        case .change:
            return Weights(recency: 0.30, importance: 0.20, relevance: 0.25, temporalProximity: 0.15, tierBoost: 0.10)
        }
    }

    private func tierBoostValue(for tier: Int) -> Double {
        switch tier {
        case 3: return 1.0
        case 2: return 0.8
        case 1: return 0.6
        case 0: return 0.4
        default: return 0.2
        }
    }
}
