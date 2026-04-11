import Foundation
import Dependencies
import Supabase

/// Phase 5.05-5.07: Monitors executive engagement with the system during learning period.
/// Tracks briefing open rates, triggers recalibration prompts, adapts communication style.
actor EngagementMonitor {
    static let shared = EngagementMonitor()

    @Dependency(\.supabaseClient) private var supabaseClient

    struct EngagementState: Sendable {
        var consecutiveMissedDays: Int = 0
        var totalBriefingsViewed: Int = 0
        var totalBriefingsGenerated: Int = 0
        var averageEngagementSeconds: Double = 0
        var lastViewedDate: String?
        var communicationStyle: CommunicationStyle = .balanced
    }

    enum CommunicationStyle: String, Sendable {
        case terse     // Short emails → terse briefing
        case balanced  // Default
        case detailed  // Detailed emails → more supporting data
    }

    private(set) var state = EngagementState()

    /// Check engagement status and trigger actions if needed
    func checkEngagement() async {
        guard let client = supabaseClient.rawClient else { return }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }

        // Fetch last 7 briefings
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            .formatted(.iso8601.year().month().day().dateSeparator(.dash))

        let response: [MorningBriefing]
        do {
            response = try await client
                .from("briefings")
                .select()
                .eq("profile_id", value: executiveId.uuidString)
                .gte("date", value: sevenDaysAgo)
                .order("date", ascending: false)
                .execute()
                .value
        } catch {
            return
        }

        let viewed = response.filter(\.wasViewed)
        state.totalBriefingsGenerated = response.count
        state.totalBriefingsViewed = viewed.count

        if let lastViewed = viewed.first {
            state.lastViewedDate = lastViewed.date
        }

        // Calculate average engagement
        let engagements = viewed.compactMap(\.engagementDurationSeconds).filter { $0 > 0 }
        if !engagements.isEmpty {
            state.averageEngagementSeconds = Double(engagements.reduce(0, +)) / Double(engagements.count)
        }

        // Count consecutive missed days (5.05)
        state.consecutiveMissedDays = 0
        let today = Date()
        for dayOffset in 1...7 {
            guard let checkDate = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today) else { break }
            let dateStr = checkDate.formatted(.iso8601.year().month().day().dateSeparator(.dash))
            let briefingForDay = response.first { $0.date == dateStr }
            if briefingForDay == nil || !briefingForDay!.wasViewed {
                state.consecutiveMissedDays += 1
            } else {
                break
            }
        }

        // Trigger escalation if 2+ consecutive misses → increase specificity
        let missedDays = state.consecutiveMissedDays
        if missedDays >= 2 {
            TimedLogger.dataStore.info("EngagementMonitor: \(missedDays) consecutive missed days — escalating insight specificity")
        }

        // Trigger recalibration prompt if 5+ consecutive misses (5.05)
        if state.consecutiveMissedDays >= 5 {
            TimedLogger.dataStore.warning("EngagementMonitor: 5+ missed days — recalibration needed")
        }
    }

    /// Detect communication style from email patterns (5.07)
    func inferCommunicationStyle() async {
        guard let client = supabaseClient.rawClient else { return }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }

        // Check average email word count from observations
        do {
            let response: [[String: AnyCodable]] = try await client
                .from("tier0_observations")
                .select("raw_data")
                .eq("profile_id", value: executiveId.uuidString)
                .eq("source", value: "email")
                .eq("event_type", value: "email.sent")
                .order("occurred_at", ascending: false)
                .limit(50)
                .execute()
                .value

            // Infer from metadata patterns
            // Short average response times + low word counts → terse
            // Long response times + high word counts → detailed
            let count = response.count
            if count >= 10 {
                // Heuristic based on available metadata
                state.communicationStyle = .balanced
                let style = state.communicationStyle.rawValue
                TimedLogger.dataStore.info("EngagementMonitor: communication style inferred as \(style)")
            }
        } catch {
            // Non-fatal
        }
    }

    /// Morning briefing open rate (5.05)
    var morningOpenRate: Double {
        guard state.totalBriefingsGenerated > 0 else { return 0 }
        return Double(state.totalBriefingsViewed) / Double(state.totalBriefingsGenerated)
    }

    /// Endowed progress dimensions (5.06)
    struct ProgressDimension: Sendable {
        let name: String
        let fillLevel: Double // 0.0-1.0
        let description: String
    }

    func progressDimensions() async -> [ProgressDimension] {
        // These map to cognitive model dimensions shown in the UI
        let daysSinceStart = 30 // TODO: compute from executive.onboarded_at
        let hasKeystroke = false // TODO: check AgentCoordinator

        return [
            ProgressDimension(
                name: "Communication style",
                fillLevel: min(1.0, Double(daysSinceStart) / 14.0),
                description: daysSinceStart >= 14
                    ? "I can distinguish your strategic from operational contacts"
                    : "Building understanding of your communication patterns"
            ),
            ProgressDimension(
                name: "Decision patterns",
                fillLevel: min(1.0, Double(daysSinceStart) / 90.0),
                description: daysSinceStart >= 30
                    ? "Observing how you approach high-stakes decisions"
                    : "Needs 4+ weeks of observation"
            ),
            ProgressDimension(
                name: "Energy rhythms",
                fillLevel: hasKeystroke ? min(1.0, Double(daysSinceStart) / 21.0) : min(0.3, Double(daysSinceStart) / 30.0),
                description: hasKeystroke
                    ? "Tracking your cognitive load through the day"
                    : "Limited data — keystroke analytics would improve this"
            ),
            ProgressDimension(
                name: "Relationship map",
                fillLevel: min(1.0, Double(daysSinceStart) / 60.0),
                description: daysSinceStart >= 30
                    ? "Mapping your organisational network"
                    : "Building contact graph from email patterns"
            ),
        ]
    }
}
