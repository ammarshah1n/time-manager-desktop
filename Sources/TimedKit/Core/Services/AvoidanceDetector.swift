import Foundation
import Dependencies
import Supabase

/// Phase 9.01: Detects avoidance patterns across 3 streams.
/// Email latency spikes, calendar rescheduling, document engagement.
/// Cross-stream: >= 2 of 3 for same domain → declare avoidance.
/// HARD RULE: never flag if network is expanding (false negatives cheaper than false positives).
actor AvoidanceDetector {
    static let shared = AvoidanceDetector()

    @Dependency(\.supabaseClient) private var supabaseClient

    struct AvoidanceFlag: Sendable {
        let domain: String
        let streams: [AvoidanceStream]
        let confidence: Double
        let isStrategicDelay: Bool
        let evidence: String
    }

    enum AvoidanceStream: Sendable {
        case emailLatency(contact: String, zScore: Double, businessDays: Int)
        case calendarRescheduling(contact: String, rescheduleCount: Int, sigmaDeviation: Double)
        case documentEngagement(topic: String, openCount: Int, editCount: Int)
    }

    /// Detect avoidance patterns across all streams (9.01)
    func detectAvoidance() async -> [AvoidanceFlag] {
        guard let client = supabaseClient.rawClient else { return [] }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return [] }

        var flags: [AvoidanceFlag] = []

        // Stream 1: Email latency spikes (z > 2.0 for sender cluster, 5+ business days)
        let emailFlags = await detectEmailLatencyAvoidance(client: client, executiveId: executiveId)

        // Stream 2: Calendar rescheduling (>2σ, 2+ weeks)
        let calendarFlags = await detectCalendarReschedulingAvoidance(client: client, executiveId: executiveId)

        // Stream 3: Document/task engagement — repeated deferrals correlating with calendar + email
        let documentFlags = await detectDocumentEngagementAvoidance(client: client, executiveId: executiveId)

        // Cross-stream check: >= 2 streams for same domain → declare avoidance
        // Group by contact/domain
        var domainSignals: [String: [AvoidanceStream]] = [:]
        for stream in emailFlags { domainSignals[streamDomain(stream), default: []].append(stream) }
        for stream in calendarFlags { domainSignals[streamDomain(stream), default: []].append(stream) }
        for stream in documentFlags { domainSignals[streamDomain(stream), default: []].append(stream) }

        for (domain, streams) in domainSignals {
            guard streams.count >= 2 else { continue }

            // HARD RULE: check if network is expanding for this contact
            let isExpanding = await isNetworkExpanding(client: client, executiveId: executiveId, domain: domain)
            if isExpanding {
                // Strategic delay, not avoidance
                continue
            }

            let flag = AvoidanceFlag(
                domain: domain,
                streams: streams,
                confidence: min(1.0, Double(streams.count) * 0.4),
                isStrategicDelay: false,
                evidence: "Cross-stream avoidance: \(streams.count) signals converging on \(domain)"
            )
            flags.append(flag)
        }

        let flagCount = flags.count
        if flagCount > 0 {
            TimedLogger.dataStore.info("AvoidanceDetector: \(flagCount) avoidance patterns detected")
        }
        return flags
    }

    // MARK: - Stream 1: Email Latency

    private func detectEmailLatencyAvoidance(client: SupabaseClient, executiveId: UUID) async -> [AvoidanceStream] {
        do {
            // Get contacts with high response latency (z > 2.0, 5+ business days)
            let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            let rows: [LatencyRow] = try await client
                .from("ona_nodes")
                .select("email, display_name, avg_response_latency_seconds")
                .eq("profile_id", value: executiveId.uuidString)
                .gt("avg_response_latency_seconds", value: 432000) // 5 business days in seconds
                .gte("last_seen_at", value: fiveDaysAgo.ISO8601Format())
                .limit(10)
                .execute()
                .value

            return rows.map { row in
                let businessDays = Int((row.avgResponseLatencySeconds ?? 0) / 86400)
                return AvoidanceStream.emailLatency(
                    contact: row.displayName ?? row.email,
                    zScore: 2.5, // Simplified — actual z-score would compare against baseline
                    businessDays: businessDays
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Stream 2: Calendar Rescheduling

    private func detectCalendarReschedulingAvoidance(client: SupabaseClient, executiveId: UUID) async -> [AvoidanceStream] {
        do {
            // Find contacts with repeated rescheduling (>2σ over 2+ weeks)
            let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date())!
            let rows: [RescheduleRow] = try await client
                .from("tier0_observations")
                .select("raw_data, occurred_at")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "calendar")
                .eq("event_type", value: "calendar.rescheduled")
                .gte("occurred_at", value: fourWeeksAgo.ISO8601Format())
                .execute()
                .value

            // Group by organiser/attendee
            var reschedulesByContact: [String: Int] = [:]
            for row in rows {
                if let contact = row.rawData?["organiser_email"] as? String {
                    reschedulesByContact[contact, default: 0] += 1
                }
            }

            return reschedulesByContact.compactMap { contact, count in
                guard count >= 3 else { return nil }
                return AvoidanceStream.calendarRescheduling(
                    contact: contact,
                    rescheduleCount: count,
                    sigmaDeviation: Double(count) / 1.5 // Simplified
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Stream 3: Document/Task Engagement

    private func detectDocumentEngagementAvoidance(client: SupabaseClient, executiveId: UUID) async -> [AvoidanceStream] {
        do {
            // Find tasks deferred 3+ times — signals topic avoidance
            let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date())!
            let rows: [DeferralRow] = try await client
                .from("behaviour_events")
                .select("task_id, bucket_type")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("event_type", value: "task_deferred")
                .gte("occurred_at", value: fourWeeksAgo.ISO8601Format())
                .execute()
                .value

            // Group by task_id and count deferrals
            var deferralsByTask: [String: (count: Int, bucket: String)] = [:]
            for row in rows {
                guard let taskId = row.taskId else { continue }
                let bucket = row.bucketType ?? "unknown"
                let key = taskId.uuidString
                if let existing = deferralsByTask[key] {
                    deferralsByTask[key] = (existing.count + 1, bucket)
                } else {
                    deferralsByTask[key] = (1, bucket)
                }
            }

            // Tasks deferred 3+ times → avoidance signal, grouped by bucket/topic
            var bucketDeferrals: [String: (opens: Int, defers: Int)] = [:]
            for (_, info) in deferralsByTask where info.count >= 3 {
                let existing = bucketDeferrals[info.bucket, default: (0, 0)]
                bucketDeferrals[info.bucket] = (existing.opens + 1, existing.defers + info.count)
            }

            return bucketDeferrals.map { bucket, counts in
                AvoidanceStream.documentEngagement(
                    topic: bucket,
                    openCount: counts.opens,
                    editCount: counts.defers
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Strategic Delay Discriminator

    /// If the contact's network is expanding (new sources), this is strategic delay, NOT avoidance
    private func isNetworkExpanding(client: SupabaseClient, executiveId: UUID, domain: String) async -> Bool {
        do {
            // Check if new contacts appeared in the same domain recently
            let twoWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date())!
            let rows: [NodeCountRow] = try await client
                .from("ona_nodes")
                .select("id")
                .eq("profile_id", value: executiveId.uuidString)
                .ilike("email", pattern: "%\(domain)%")
                .gte("first_seen_at", value: twoWeeksAgo.ISO8601Format())
                .execute()
                .value

            // Expanding if 2+ new contacts in same domain
            return rows.count >= 2
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func streamDomain(_ stream: AvoidanceStream) -> String {
        switch stream {
        case .emailLatency(let contact, _, _): return extractDomain(contact)
        case .calendarRescheduling(let contact, _, _): return extractDomain(contact)
        case .documentEngagement(let topic, _, _): return topic
        }
    }

    private func extractDomain(_ contactOrEmail: String) -> String {
        if let atIndex = contactOrEmail.firstIndex(of: "@") {
            return String(contactOrEmail[contactOrEmail.index(after: atIndex)...])
        }
        return contactOrEmail.lowercased()
    }

    // MARK: - Supporting Types

    private struct LatencyRow: Decodable, Sendable {
        let email: String
        let displayName: String?
        let avgResponseLatencySeconds: Double?

        enum CodingKeys: String, CodingKey {
            case email
            case displayName = "display_name"
            case avgResponseLatencySeconds = "avg_response_latency_seconds"
        }
    }

    private struct RescheduleRow: Decodable, Sendable {
        let rawData: [String: AnyCodable]?
        let occurredAt: String

        enum CodingKeys: String, CodingKey {
            case rawData = "raw_data"
            case occurredAt = "occurred_at"
        }
    }

    private struct NodeCountRow: Decodable, Sendable {
        let id: UUID
    }

    private struct DeferralRow: Decodable, Sendable {
        let taskId: UUID?
        let bucketType: String?

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case bucketType = "bucket_type"
        }
    }
}
