import Foundation
import Dependencies
import Supabase

/// Phase 6.02: Builds ONA graph from email observations.
/// Processes Tier 0 email observations into ona_nodes + ona_edges.
actor ONAGraphBuilder {
    static let shared = ONAGraphBuilder()

    @Dependency(\.supabaseClient) private var supabaseClient

    /// Process an email observation into ONA graph
    func processEmailObservation(_ obs: Tier0Observation) async {
        guard let client = supabaseClient.rawClient else { return }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }

        // Extract email metadata from raw_data
        guard let rawData = obs.rawData else { return }
        let senderEmail = rawData["sender_email"]?.value as? String
        let senderName = rawData["sender_name"]?.value as? String
        let recipientEmails = rawData["recipient_emails"]?.value as? [String] ?? []
        let isSent = obs.eventType == "email.sent" || obs.eventType == "email.response_sent"
        let responseLatency = rawData["response_time_sec"]?.value as? Double
        let threadId = rawData["thread_id"]?.value as? String
        let threadDepth = rawData["thread_depth"]?.value as? Int
        let hasAttachment = rawData["has_attachment"]?.value as? Bool ?? false
        let messageGraphId = rawData["message_graph_id"]?.value as? String

        do {
            if isSent {
                // Executive sent → upsert recipients as nodes, create edges
                for recipientEmail in recipientEmails {
                    let nodeId = try await upsertNode(
                        client: client, profileId: executiveId,
                        email: recipientEmail, displayName: nil,
                        isSent: true
                    )

                    try await insertEdge(
                        client: client, profileId: executiveId,
                        fromNodeId: nodeId, toNodeId: nodeId,
                        direction: "sent", timestamp: obs.occurredAt,
                        responseLatency: responseLatency,
                        threadId: threadId, threadDepth: threadDepth,
                        recipientPosition: "to", isInitiated: threadDepth == nil || threadDepth == 0,
                        hasAttachment: hasAttachment, messageGraphId: messageGraphId
                    )
                }
            } else if let senderEmail {
                // Executive received → upsert sender as node, create edge
                let nodeId = try await upsertNode(
                    client: client, profileId: executiveId,
                    email: senderEmail, displayName: senderName,
                    isSent: false
                )

                try await insertEdge(
                    client: client, profileId: executiveId,
                    fromNodeId: nodeId, toNodeId: nodeId,
                    direction: "received", timestamp: obs.occurredAt,
                    responseLatency: responseLatency,
                    threadId: threadId, threadDepth: threadDepth,
                    recipientPosition: "to", isInitiated: false,
                    hasAttachment: hasAttachment, messageGraphId: messageGraphId
                )
            }
        } catch {
            TimedLogger.dataStore.error("ONAGraphBuilder: failed to process email observation — \(error.localizedDescription)")
        }
    }

    // MARK: - Node Upsert

    private struct NodeUpsert: Encodable {
        let profile_id: String
        let email: String
        let display_name: String?
        let total_emails_sent: Int
        let total_emails_received: Int
        let last_seen_at: String
    }

    private func upsertNode(
        client: SupabaseClient, profileId: UUID,
        email: String, displayName: String?, isSent: Bool
    ) async throws -> UUID {
        // Check if node exists
        let existing: [ONANodeRow] = try await client
            .from("ona_nodes")
            .select("id, total_emails_sent, total_emails_received")
            .eq("profile_id", value: profileId.uuidString)
            .eq("email", value: email)
            .limit(1)
            .execute()
            .value

        if let node = existing.first {
            // Update counts
            struct CountUpdate: Encodable {
                let total_emails_sent: Int
                let total_emails_received: Int
                let last_seen_at: String
            }
            let update = CountUpdate(
                total_emails_sent: node.totalEmailsSent + (isSent ? 1 : 0),
                total_emails_received: node.totalEmailsReceived + (isSent ? 0 : 1),
                last_seen_at: Date().ISO8601Format()
            )
            try await client
                .from("ona_nodes")
                .update(update)
                .eq("id", value: node.id.uuidString)
                .execute()
            return node.id
        } else {
            // Insert new node
            let insert = NodeUpsert(
                profile_id: profileId.uuidString,
                email: email,
                display_name: displayName,
                total_emails_sent: isSent ? 1 : 0,
                total_emails_received: isSent ? 0 : 1,
                last_seen_at: Date().ISO8601Format()
            )
            let result: [ONANodeRow] = try await client
                .from("ona_nodes")
                .insert(insert)
                .select("id, total_emails_sent, total_emails_received")
                .execute()
                .value
            guard let newNode = result.first else {
                throw ONAError.insertFailed
            }

            // Also create a relationship entry
            struct RelInsert: Encodable {
                let profile_id: String
                let node_id: String
                let last_contact_at: String
            }
            try? await client
                .from("relationships")
                .insert(RelInsert(
                    profile_id: profileId.uuidString,
                    node_id: newNode.id.uuidString,
                    last_contact_at: Date().ISO8601Format()
                ))
                .execute()

            return newNode.id
        }
    }

    // MARK: - Edge Insert

    private struct EdgeInsert: Encodable {
        let profile_id: String
        let from_node_id: String
        let to_node_id: String
        let direction: String
        let edge_timestamp: String
        let response_latency_seconds: Double?
        let thread_id: String?
        let thread_depth: Int?
        let recipient_position: String?
        let is_initiated: Bool
        let has_attachment: Bool
        let message_graph_id: String?
    }

    private func insertEdge(
        client: SupabaseClient, profileId: UUID,
        fromNodeId: UUID, toNodeId: UUID,
        direction: String, timestamp: Date,
        responseLatency: Double?, threadId: String?, threadDepth: Int?,
        recipientPosition: String?, isInitiated: Bool,
        hasAttachment: Bool, messageGraphId: String?
    ) async throws {
        let edge = EdgeInsert(
            profile_id: profileId.uuidString,
            from_node_id: fromNodeId.uuidString,
            to_node_id: toNodeId.uuidString,
            direction: direction,
            edge_timestamp: timestamp.ISO8601Format(),
            response_latency_seconds: responseLatency,
            thread_id: threadId,
            thread_depth: threadDepth,
            recipient_position: recipientPosition,
            is_initiated: isInitiated,
            has_attachment: hasAttachment,
            message_graph_id: messageGraphId
        )
        try await client
            .from("ona_edges")
            .insert(edge)
            .execute()

        // Update last_contact_at on relationship
        struct ContactUpdate: Encodable {
            let last_contact_at: String
            let updated_at: String
        }
        let nodeId = direction == "sent" ? toNodeId : fromNodeId
        try? await client
            .from("relationships")
            .update(ContactUpdate(last_contact_at: timestamp.ISO8601Format(), updated_at: Date().ISO8601Format()))
            .eq("profile_id", value: profileId.uuidString)
            .eq("node_id", value: nodeId.uuidString)
            .execute()
    }

    // MARK: - Centrality & Health RPCs

    /// Recompute degree centrality for all nodes (6.03)
    func updateCentralityMetrics() async {
        guard let client = supabaseClient.rawClient else { return }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }

        do {
            try await client.rpc("compute_degree_centrality", params: ["exec_id": executiveId.uuidString]).execute()
            TimedLogger.dataStore.info("ONAGraphBuilder: centrality metrics updated")
        } catch {
            TimedLogger.dataStore.error("ONAGraphBuilder: centrality update failed — \(error.localizedDescription)")
        }
    }

    /// Recompute relationship health scores (6.04)
    func updateRelationshipHealth() async {
        guard let client = supabaseClient.rawClient else { return }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }

        do {
            try await client.rpc("compute_relationship_health", params: ["exec_id": executiveId.uuidString]).execute()
            TimedLogger.dataStore.info("ONAGraphBuilder: relationship health updated")
        } catch {
            TimedLogger.dataStore.error("ONAGraphBuilder: relationship health update failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Supporting Types

    enum ONAError: Error {
        case insertFailed
    }

    private struct ONANodeRow: Decodable, Sendable {
        let id: UUID
        let totalEmailsSent: Int
        let totalEmailsReceived: Int

        enum CodingKeys: String, CodingKey {
            case id
            case totalEmailsSent = "total_emails_sent"
            case totalEmailsReceived = "total_emails_received"
        }
    }
}
