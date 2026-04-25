import Foundation
import Dependencies
import Supabase

/// Phase 6.05: Detects relationship disengagement patterns.
/// RDI (Relationship Disengagement Index) + SWS (Selective Withdrawal Score).
actor DisengagementDetector {
    static let shared = DisengagementDetector()

    @Dependency(\.supabaseClient) private var supabaseClient

    enum DisengagementSignal: Sendable {
        case emailLatencySpike(contact: String, zScore: Double)
        case calendarRescheduling(contact: String, count: Int)
        case contactFrequencyDecline(contact: String, declinePercent: Double)
    }

    struct DisengagementFlag: Sendable {
        let nodeId: UUID
        let displayName: String
        let signals: [DisengagementSignal]
        let rdiScore: Double
        let isSelectiveWithdrawal: Bool
    }

    /// Detect contacts showing disengagement patterns (6.05)
    func detectDisengagement() async -> [DisengagementFlag] {
        guard let client = supabaseClient.rawClient else { return [] }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return [] }

        do {
            // Find nodes with declining health
            let nodes: [NodeRow] = try await client
                .from("ona_nodes")
                .select("id, email, display_name")
                .eq("profile_id", value: executiveId.uuidString)
                .lt("relationship_health_score", value: 40)
                .limit(30)
                .execute()
                .value

            var flags: [DisengagementFlag] = []

            for node in nodes {
                let rdi = await computeRDI(for: node.id)
                guard rdi > 0.6 else { continue }

                var signals: [DisengagementSignal] = []

                // Check for specific signal types
                if rdi > 0.7 {
                    let name = node.displayName ?? node.email
                    signals.append(.contactFrequencyDecline(contact: name, declinePercent: rdi * 100))
                }

                let flag = DisengagementFlag(
                    nodeId: node.id,
                    displayName: node.displayName ?? node.email,
                    signals: signals,
                    rdiScore: rdi,
                    isSelectiveWithdrawal: false // SWS requires cross-contact comparison
                )
                flags.append(flag)
            }

            let flagCount = flags.count
            if flagCount > 0 {
                TimedLogger.dataStore.info("DisengagementDetector: \(flagCount) disengagement flags detected")
            }
            return flags
        } catch {
            TimedLogger.dataStore.error("DisengagementDetector: detection failed — \(error.localizedDescription)")
            return []
        }
    }

    /// Compute Relationship Disengagement Index for a contact node (6.05)
    /// Weights: response_rate_decline (0.25), latency_increase (0.25),
    ///          initiated_decline (0.20), cc_inclusion_decline (0.15), meeting_decline (0.15)
    func computeRDI(for nodeId: UUID) async -> Double {
        guard let client = supabaseClient.rawClient else { return 0 }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return 0 }

        let now = Date()
        let twelveWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: now)!
        let twentyFourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -24, to: now)!

        do {
            // Recent period edges (last 12 weeks)
            let recentEdges: [EdgeRow] = try await client
                .from("ona_edges")
                .select("direction, response_latency_seconds, is_initiated, recipient_position, edge_timestamp")
                .eq("profile_id", value: executiveId.uuidString)
                .or("from_node_id.eq.\(nodeId.uuidString),to_node_id.eq.\(nodeId.uuidString)")
                .gte("edge_timestamp", value: twelveWeeksAgo.ISO8601Format())
                .execute()
                .value

            // Baseline period edges (12-24 weeks ago)
            let baselineEdges: [EdgeRow] = try await client
                .from("ona_edges")
                .select("direction, response_latency_seconds, is_initiated, recipient_position, edge_timestamp")
                .eq("profile_id", value: executiveId.uuidString)
                .or("from_node_id.eq.\(nodeId.uuidString),to_node_id.eq.\(nodeId.uuidString)")
                .gte("edge_timestamp", value: twentyFourWeeksAgo.ISO8601Format())
                .lt("edge_timestamp", value: twelveWeeksAgo.ISO8601Format())
                .execute()
                .value

            // Need minimum baseline
            guard baselineEdges.count >= 5 else { return 0 }

            // 1. Response rate decline (0.25)
            let baselineReceived = Double(baselineEdges.filter { $0.direction == "received" }.count)
            let recentReceived = Double(recentEdges.filter { $0.direction == "received" }.count)
            let responseRateDecline = baselineReceived > 0
                ? max(0, (baselineReceived - recentReceived) / baselineReceived)
                : 0

            // 2. Latency increase (0.25)
            let baselineLatencies = baselineEdges.compactMap(\.responseLatencySeconds).filter { $0 > 0 }
            let recentLatencies = recentEdges.compactMap(\.responseLatencySeconds).filter { $0 > 0 }
            let baselineAvgLatency = baselineLatencies.isEmpty ? 0 : baselineLatencies.reduce(0, +) / Double(baselineLatencies.count)
            let recentAvgLatency = recentLatencies.isEmpty ? 0 : recentLatencies.reduce(0, +) / Double(recentLatencies.count)
            let latencyIncrease = baselineAvgLatency > 0
                ? min(1.0, max(0, (recentAvgLatency - baselineAvgLatency) / baselineAvgLatency))
                : 0

            // 3. Initiated contact decline (0.20)
            let baselineInitiated = Double(baselineEdges.filter(\.isInitiated).count)
            let recentInitiated = Double(recentEdges.filter(\.isInitiated).count)
            let initiatedDecline = baselineInitiated > 0
                ? max(0, (baselineInitiated - recentInitiated) / baselineInitiated)
                : 0

            // 4. CC inclusion decline (0.15)
            let baselineCC = Double(baselineEdges.filter { $0.recipientPosition == "cc" }.count)
            let recentCC = Double(recentEdges.filter { $0.recipientPosition == "cc" }.count)
            let ccDecline = baselineCC > 0
                ? max(0, (baselineCC - recentCC) / baselineCC)
                : 0

            // 5. Meeting participation decline (0.15) — approximated from calendar edges
            // For now use overall volume as proxy
            let baselineTotal = Double(baselineEdges.count)
            let recentTotal = Double(recentEdges.count)
            let volumeDecline = baselineTotal > 0
                ? max(0, (baselineTotal - recentTotal) / baselineTotal)
                : 0

            let rdi = responseRateDecline * 0.25
                + latencyIncrease * 0.25
                + initiatedDecline * 0.20
                + ccDecline * 0.15
                + volumeDecline * 0.15

            return min(1.0, max(0, rdi))
        } catch {
            TimedLogger.dataStore.error("DisengagementDetector: RDI computation failed — \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Supporting Types

    private struct NodeRow: Decodable, Sendable {
        let id: UUID
        let email: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id, email
            case displayName = "display_name"
        }
    }

    private struct EdgeRow: Decodable, Sendable {
        let direction: String
        let responseLatencySeconds: Double?
        let isInitiated: Bool
        let recipientPosition: String?
        let edgeTimestamp: String

        enum CodingKeys: String, CodingKey {
            case direction
            case responseLatencySeconds = "response_latency_seconds"
            case isInitiated = "is_initiated"
            case recipientPosition = "recipient_position"
            case edgeTimestamp = "edge_timestamp"
        }
    }
}
