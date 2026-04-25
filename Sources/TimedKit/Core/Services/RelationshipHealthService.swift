import Foundation
import Dependencies
import Supabase

/// Phase 6.04: Queries relationship health state for briefing and alert integration.
actor RelationshipHealthService {
    static let shared = RelationshipHealthService()

    @Dependency(\.supabaseClient) private var supabaseClient

    struct RelationshipAlert: Sendable {
        let nodeId: UUID
        let displayName: String
        let email: String
        let healthTrajectory: String
        let daysSinceContact: Int
        let healthScore: Double
    }

    /// Get relationships that are at risk or dormant (6.04)
    func getAtRiskRelationships() async -> [RelationshipAlert] {
        guard let client = supabaseClient.rawClient else { return [] }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return [] }

        do {
            let rows: [RelationshipRow] = try await client
                .from("relationships")
                .select("id, node_id, health_trajectory, health_score, last_contact_at, ona_nodes(id, display_name, email)")
                .eq("profile_id", value: executiveId.uuidString)
                .in("health_trajectory", values: ["at_risk", "dormant"])
                .order("health_score", ascending: true)
                .limit(20)
                .execute()
                .value

            return rows.compactMap { row -> RelationshipAlert? in
                guard let node = row.onaNodes else { return nil }
                let days: Int
                if let lastContact = row.lastContactAt {
                    days = Int(Date().timeIntervalSince(lastContact) / 86400)
                } else {
                    days = 999
                }
                return RelationshipAlert(
                    nodeId: row.nodeId,
                    displayName: node.displayName ?? node.email,
                    email: node.email,
                    healthTrajectory: row.healthTrajectory,
                    daysSinceContact: days,
                    healthScore: row.healthScore
                )
            }
        } catch {
            TimedLogger.dataStore.error("RelationshipHealthService: failed to fetch at-risk — \(error.localizedDescription)")
            return []
        }
    }

    /// Get contacts exceeding dormancy threshold (6.04)
    func getDormancyAlerts(threshold: Int = 30) async -> [RelationshipAlert] {
        guard let client = supabaseClient.rawClient else { return [] }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return [] }

        let cutoff = Calendar.current.date(byAdding: .day, value: -threshold, to: Date())!

        do {
            let rows: [RelationshipRow] = try await client
                .from("relationships")
                .select("id, node_id, health_trajectory, health_score, last_contact_at, ona_nodes(id, display_name, email)")
                .eq("profile_id", value: executiveId.uuidString)
                .lt("last_contact_at", value: cutoff.ISO8601Format())
                .order("last_contact_at", ascending: true)
                .limit(20)
                .execute()
                .value

            return rows.compactMap { row -> RelationshipAlert? in
                guard let node = row.onaNodes else { return nil }
                let days: Int
                if let lastContact = row.lastContactAt {
                    days = Int(Date().timeIntervalSince(lastContact) / 86400)
                } else {
                    days = 999
                }
                return RelationshipAlert(
                    nodeId: row.nodeId,
                    displayName: node.displayName ?? node.email,
                    email: node.email,
                    healthTrajectory: row.healthTrajectory,
                    daysSinceContact: days,
                    healthScore: row.healthScore
                )
            }
        } catch {
            TimedLogger.dataStore.error("RelationshipHealthService: failed to fetch dormancy alerts — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Supporting Types

    private struct RelationshipRow: Decodable, Sendable {
        let id: UUID
        let nodeId: UUID
        let healthTrajectory: String
        let healthScore: Double
        let lastContactAt: Date?
        let onaNodes: NodeInfo?

        enum CodingKeys: String, CodingKey {
            case id
            case nodeId = "node_id"
            case healthTrajectory = "health_trajectory"
            case healthScore = "health_score"
            case lastContactAt = "last_contact_at"
            case onaNodes = "ona_nodes"
        }
    }

    private struct NodeInfo: Decodable, Sendable {
        let id: UUID
        let displayName: String?
        let email: String

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case email
        }
    }
}
