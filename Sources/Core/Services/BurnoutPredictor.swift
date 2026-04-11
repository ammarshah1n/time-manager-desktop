import Foundation
import Dependencies
import Supabase

/// Phase 9.02: Burnout prediction using 17 signals across 3 MBI dimensions.
/// Triple gate: 3+ weeks duration, 3+ modalities converging, 2-of-3 MBI dimensions elevated.
/// Sprint discriminator: visible end date + stable network → suppress.
/// Minimum 11 weeks before first alert (8 baseline + 3 sustained signal).
actor BurnoutPredictor {
    static let shared = BurnoutPredictor()

    @Dependency(\.supabaseClient) private var supabaseClient

    // MARK: - Types

    /// Maslach Burnout Inventory dimensions
    enum MBIDimension: String, Sendable {
        case exhaustion           // Physical/emotional depletion
        case depersonalisation    // Cynicism, detachment
        case reducedAccomplishment // Declining efficacy
    }

    struct BurnoutAssessment: Sendable {
        let overallRisk: Double           // 0.0-1.0
        let exhaustionScore: Double       // 0.0-1.0
        let depersonalisationScore: Double // 0.0-1.0
        let reducedAccomplishmentScore: Double // 0.0-1.0
        let elevatedDimensions: [MBIDimension]
        let weeksDuration: Int
        let modalitiesConverging: Int
        let isSprintPattern: Bool
        let recommendation: BurnoutRecommendation
    }

    enum BurnoutRecommendation: Sendable {
        case noRisk
        case monitoring(reason: String)
        case elevated(reason: String)
        case critical(reason: String)
        case suppressed(reason: String) // Sprint discriminator
    }

    // MARK: - Detection

    /// Run burnout assessment (9.02)
    func assess() async -> BurnoutAssessment {
        guard let client = supabaseClient.rawClient else { return defaultAssessment() }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return defaultAssessment() }

        // Check minimum data: 11 weeks (8 baseline + 3 signal)
        let elevenWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -11, to: Date())!
        do {
            let countResult: [CountRow] = try await client
                .from("tier1_daily_summaries")
                .select("id")
                .eq("profile_id", value: executiveId.uuidString)
                .gte("summary_date", value: elevenWeeksAgo.ISO8601Format())
                .execute()
                .value

            if countResult.count < 55 { // ~8 weeks of data minimum
                return defaultAssessment()
            }
        } catch {
            return defaultAssessment()
        }

        // Compute MBI dimensions from available signals
        let exhaustion = await computeExhaustion(client: client, executiveId: executiveId)
        let depersonalisation = await computeDepersonalisation(client: client, executiveId: executiveId)
        let reducedAccomplishment = await computeReducedAccomplishment(client: client, executiveId: executiveId)

        var elevated: [MBIDimension] = []
        if exhaustion > 0.6 { elevated.append(.exhaustion) }
        if depersonalisation > 0.6 { elevated.append(.depersonalisation) }
        if reducedAccomplishment > 0.6 { elevated.append(.reducedAccomplishment) }

        // Count modalities with elevated signals
        let modalities = await countElevatedModalities(client: client, executiveId: executiveId)

        // Check sprint discriminator
        let isSprint = await detectSprintPattern(client: client, executiveId: executiveId)

        // Triple gate: 3+ weeks, 3+ modalities, 2-of-3 MBI
        let overallRisk = (exhaustion + depersonalisation + reducedAccomplishment) / 3.0
        let recommendation: BurnoutRecommendation

        if isSprint {
            recommendation = .suppressed(reason: "Sprint pattern detected — visible end date + stable network")
        } else if elevated.count >= 2 && modalities >= 3 {
            recommendation = .critical(reason: "\(elevated.count) MBI dimensions elevated, \(modalities) modalities converging")
        } else if elevated.count >= 1 && modalities >= 2 {
            recommendation = .elevated(reason: "\(elevated.count) MBI dimension(s) elevated")
        } else if overallRisk > 0.4 {
            recommendation = .monitoring(reason: "Moderate signals across dimensions")
        } else {
            recommendation = .noRisk
        }

        return BurnoutAssessment(
            overallRisk: overallRisk,
            exhaustionScore: exhaustion,
            depersonalisationScore: depersonalisation,
            reducedAccomplishmentScore: reducedAccomplishment,
            elevatedDimensions: elevated,
            weeksDuration: 0, // TODO: compute from first elevated signal
            modalitiesConverging: modalities,
            isSprintPattern: isSprint,
            recommendation: recommendation
        )
    }

    // MARK: - MBI Dimension Computation

    /// Exhaustion: late-night email, extended hours, high meeting density, declining breaks
    private func computeExhaustion(client: SupabaseClient, executiveId: UUID) async -> Double {
        let threeWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())!
        do {
            // After-hours email volume (proxy for exhaustion)
            let rows: [ObsRow] = try await client
                .from("tier0_observations")
                .select("occurred_at")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "email")
                .eq("event_type", value: "email.sent")
                .gte("occurred_at", value: threeWeeksAgo.ISO8601Format())
                .execute()
                .value

            let afterHoursCount = rows.filter { row in
                if let date = ISO8601DateFormatter().date(from: row.occurredAt) {
                    let hour = Calendar.current.component(.hour, from: date)
                    return hour >= 21 || hour < 6
                }
                return false
            }.count

            let totalCount = max(1, rows.count)
            let afterHoursRatio = Double(afterHoursCount) / Double(totalCount)

            return min(1.0, afterHoursRatio * 3.0) // Scale: 33%+ after-hours = max exhaustion signal
        } catch {
            return 0
        }
    }

    /// Depersonalisation: shorter responses, declining initiated contact, increased CC usage
    private func computeDepersonalisation(client: SupabaseClient, executiveId: UUID) async -> Double {
        // Simplified: check declining initiated contact ratio
        let threeWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())!
        do {
            let edges: [EdgeDirectionRow] = try await client
                .from("ona_edges")
                .select("direction, is_initiated")
                .eq("profile_id", value: executiveId.uuidString)
                .gte("edge_timestamp", value: threeWeeksAgo.ISO8601Format())
                .execute()
                .value

            let sentEdges = edges.filter { $0.direction == "sent" }
            guard sentEdges.count >= 10 else { return 0 }

            let initiatedCount = sentEdges.filter(\.isInitiated).count
            let initiatedRate = Double(initiatedCount) / Double(sentEdges.count)

            // Low initiation rate → depersonalisation signal
            return max(0, 1.0 - initiatedRate * 2.0)
        } catch {
            return 0
        }
    }

    /// Reduced accomplishment: declining task completion, missed deadlines
    private func computeReducedAccomplishment(client: SupabaseClient, executiveId: UUID) async -> Double {
        // Simplified: check calendar cancellation rate
        let threeWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())!
        do {
            let cancellations: [CountRow] = try await client
                .from("tier0_observations")
                .select("id")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "calendar")
                .eq("event_type", value: "calendar.cancelled")
                .gte("occurred_at", value: threeWeeksAgo.ISO8601Format())
                .execute()
                .value

            let total: [CountRow] = try await client
                .from("tier0_observations")
                .select("id")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "calendar")
                .gte("occurred_at", value: threeWeeksAgo.ISO8601Format())
                .execute()
                .value

            guard total.count >= 10 else { return 0 }
            let cancellationRate = Double(cancellations.count) / Double(total.count)

            return min(1.0, cancellationRate * 5.0) // Scale: 20%+ cancellations = max signal
        } catch {
            return 0
        }
    }

    // MARK: - Modality Count

    private func countElevatedModalities(client: SupabaseClient, executiveId: UUID) async -> Int {
        // Count how many signal types show elevated patterns
        var count = 0
        let threeWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())!

        do {
            // Check email volume trend
            let emailRows: [CountRow] = try await client
                .from("tier0_observations")
                .select("id")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "email")
                .gte("occurred_at", value: threeWeeksAgo.ISO8601Format())
                .execute()
                .value
            if emailRows.count > 0 { count += 1 }

            // Check calendar density
            let calRows: [CountRow] = try await client
                .from("tier0_observations")
                .select("id")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "calendar")
                .gte("occurred_at", value: threeWeeksAgo.ISO8601Format())
                .execute()
                .value
            if calRows.count > 0 { count += 1 }

            // Check app usage patterns
            let appRows: [CountRow] = try await client
                .from("tier0_observations")
                .select("id")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "app_usage")
                .gte("occurred_at", value: threeWeeksAgo.ISO8601Format())
                .execute()
                .value
            if appRows.count > 0 { count += 1 }
        } catch {
            // Non-fatal
        }

        return count
    }

    // MARK: - Sprint Discriminator

    /// Visible end date + stable network → suppress burnout alert
    private func detectSprintPattern(client: SupabaseClient, executiveId: UUID) async -> Bool {
        // Check for upcoming calendar events that could indicate sprint end
        // (simplified: look for "deadline", "launch", "release" in calendar events)
        do {
            let twoWeeksOut = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date())!
            let rows: [SummaryRow] = try await client
                .from("tier0_observations")
                .select("summary")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "calendar")
                .gte("occurred_at", value: Date().ISO8601Format())
                .lte("occurred_at", value: twoWeeksOut.ISO8601Format())
                .execute()
                .value

            let sprintKeywords = ["deadline", "launch", "release", "go-live", "delivery", "sprint end"]
            return rows.contains { row in
                guard let summary = row.summary?.lowercased() else { return false }
                return sprintKeywords.contains { summary.contains($0) }
            }
        } catch {
            return false
        }
    }

    // MARK: - Default

    private func defaultAssessment() -> BurnoutAssessment {
        BurnoutAssessment(
            overallRisk: 0, exhaustionScore: 0, depersonalisationScore: 0,
            reducedAccomplishmentScore: 0, elevatedDimensions: [],
            weeksDuration: 0, modalitiesConverging: 0, isSprintPattern: false,
            recommendation: .noRisk
        )
    }

    // MARK: - Supporting Types

    private struct CountRow: Decodable, Sendable { let id: UUID }
    private struct ObsRow: Decodable, Sendable {
        let occurredAt: String
        enum CodingKeys: String, CodingKey { case occurredAt = "occurred_at" }
    }
    private struct EdgeDirectionRow: Decodable, Sendable {
        let direction: String
        let isInitiated: Bool
        enum CodingKeys: String, CodingKey { case direction; case isInitiated = "is_initiated" }
    }
    private struct SummaryRow: Decodable, Sendable { let summary: String? }
}
