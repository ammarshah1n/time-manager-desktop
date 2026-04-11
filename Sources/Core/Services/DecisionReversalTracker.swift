import Foundation
import Dependencies
import Supabase

/// Phase 9.03: Decision reversal tracking via 4-state HMM.
/// Committed → Consolidating → Wavering → Reversing
/// Features: time-to-decision, post-decision info seeking, new sources, same-source revisits.
/// Healthy reconsideration (new sources) vs vacillation (reprocessing).
actor DecisionReversalTracker {
    static let shared = DecisionReversalTracker()

    @Dependency(\.supabaseClient) private var supabaseClient

    // MARK: - Types

    enum DecisionState: String, Sendable, Codable {
        case committed      // Decision made, moving forward
        case consolidating  // Gathering confirming information
        case wavering       // Mixed signals — seeking new info AND revisiting old
        case reversing      // Strong reversal signals
    }

    struct DecisionTrack: Sendable {
        let decisionId: UUID
        let domain: String
        let currentState: DecisionState
        let daysSinceDecision: Int
        let newSourceCount: Int       // Healthy reconsideration
        let sameSourceRevisits: Int   // Vacillation signal
        let infoSeekingRate: Double   // Post-decision information seeking frequency
        let isHealthyReconsideration: Bool
        let predictedWindow: String   // "T+4 to T+14 days"
    }

    // MARK: - Detection

    /// Track active decisions and their reversal trajectories (9.03)
    func trackDecisions() async -> [DecisionTrack] {
        guard let client = supabaseClient.rawClient else { return [] }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return [] }

        do {
            // Fetch active decision tracking entries
            let rows: [DecisionRow] = try await client
                .from("decision_tracking")
                .select("id, domain, decision_state, decided_at, new_source_count, same_source_revisits, info_seeking_rate")
                .eq("profile_id", value: executiveId.uuidString)
                .in("decision_state", values: ["committed", "consolidating", "wavering"])
                .order("decided_at", ascending: false)
                .limit(20)
                .execute()
                .value

            return rows.map { row in
                let daysSince: Int
                if let decidedAt = ISO8601DateFormatter().date(from: row.decidedAt) {
                    daysSince = Int(Date().timeIntervalSince(decidedAt) / 86400)
                } else {
                    daysSince = 0
                }

                let state = DecisionState(rawValue: row.decisionState) ?? .committed
                let newSources = row.newSourceCount ?? 0
                let revisits = row.sameSourceRevisits ?? 0

                // Healthy reconsideration: new sources > revisits
                let isHealthy = newSources > revisits

                return DecisionTrack(
                    decisionId: row.id,
                    domain: row.domain,
                    currentState: state,
                    daysSinceDecision: daysSince,
                    newSourceCount: newSources,
                    sameSourceRevisits: revisits,
                    infoSeekingRate: row.infoSeekingRate ?? 0,
                    isHealthyReconsideration: isHealthy,
                    predictedWindow: "T+4 to T+14 days"
                )
            }
        } catch {
            TimedLogger.dataStore.error("DecisionReversalTracker: failed — \(error.localizedDescription)")
            return []
        }
    }

    /// Classify decision state using HMM transition model (9.03)
    func classifyState(
        daysSinceDecision: Int,
        newSources: Int,
        sameSourceRevisits: Int,
        infoSeekingRate: Double
    ) -> DecisionState {
        // Simplified HMM — rule-based initially, upgrade to Cox+HMM with data

        // T+0 to T+3: always committed (too early to judge)
        if daysSinceDecision < 4 { return .committed }

        // High info seeking + mostly new sources → consolidating (healthy)
        if infoSeekingRate > 0.5 && newSources > sameSourceRevisits * 2 {
            return .consolidating
        }

        // High info seeking + mostly same sources → wavering
        if infoSeekingRate > 0.5 && sameSourceRevisits >= newSources {
            return .wavering
        }

        // Very high revisits + declining new sources → reversing
        if sameSourceRevisits > 5 && newSources == 0 && daysSinceDecision > 7 {
            return .reversing
        }

        // Low info seeking → committed (moved on)
        if infoSeekingRate < 0.2 { return .committed }

        return .consolidating
    }

    /// Update a decision's state in the database
    func updateDecisionState(decisionId: UUID, newState: DecisionState) async {
        guard let client = supabaseClient.rawClient else { return }

        struct StateUpdate: Encodable {
            let decision_state: String
            let updated_at: String
        }
        try? await client
            .from("decision_tracking")
            .update(StateUpdate(decision_state: newState.rawValue, updated_at: Date().ISO8601Format()))
            .eq("id", value: decisionId.uuidString)
            .execute()
    }

    // MARK: - Supporting Types

    private struct DecisionRow: Decodable, Sendable {
        let id: UUID
        let domain: String
        let decisionState: String
        let decidedAt: String
        let newSourceCount: Int?
        let sameSourceRevisits: Int?
        let infoSeekingRate: Double?

        enum CodingKeys: String, CodingKey {
            case id, domain
            case decisionState = "decision_state"
            case decidedAt = "decided_at"
            case newSourceCount = "new_source_count"
            case sameSourceRevisits = "same_source_revisits"
            case infoSeekingRate = "info_seeking_rate"
        }
    }
}
