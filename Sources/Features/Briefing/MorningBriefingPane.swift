import SwiftUI
import Dependencies
import Supabase

struct MorningBriefingPane: View {
    @State private var briefing: MorningBriefing?
    @State private var isLoading = true
    @State private var viewStartTime: Date?

    @Dependency(\.supabaseClient) private var supabaseClient

    var body: some View {
        ScrollView {
            if isLoading {
                loadingView
            } else if let briefing {
                briefingContent(briefing)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity)
        .task { await loadBriefing() }
        .onAppear { viewStartTime = Date() }
        .onDisappear { Task { await trackEngagement() } }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing your intelligence briefing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No briefing available yet")
                .font(.title3)
                .fontWeight(.medium)
            Text("Your morning intelligence briefing will appear here once enough observations have been collected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(briefing)

            ForEach(Array(briefing.content.sections.enumerated()), id: \.offset) { index, section in
                if index == 0 {
                    leadSection(section)
                } else if index == briefing.content.sections.count - 1 {
                    forwardLookingSection(section)
                } else {
                    bodySection(section)
                }
            }
        }
        .padding(24)
    }

    private func header(_ briefing: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(headerTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text(briefing.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(briefing.wordCount) words")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var headerTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 11 ? "Morning Briefing" : "Today's Intelligence"
    }

    // MARK: - Section Views

    private func leadSection(_ section: BriefingSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(section.section, systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(section.insight)
                .font(.body)
                .lineSpacing(4)

            if let data = section.supportingData {
                Text(data)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            confidenceBadge(section.confidence)
        }
        .padding(16)
        .background(Color.Timed.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func bodySection(_ section: BriefingSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.section)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(section.insight)
                .font(.body)
                .lineSpacing(3)

            if let data = section.supportingData {
                Text(data)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                confidenceBadge(section.confidence)
                if let track = section.trackRecord {
                    Text(track)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func forwardLookingSection(_ section: BriefingSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(section.section, systemImage: "arrow.forward.circle")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(section.insight)
                .font(.body)
                .italic()
                .lineSpacing(3)
        }
        .padding(12)
        .background(Color.Timed.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func confidenceBadge(_ confidence: BriefingConfidence) -> some View {
        Text(confidence == .high ? "High confidence" : "Moderate confidence")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.Timed.backgroundSecondary)
            .clipShape(Capsule())
    }

    // MARK: - Data Loading

    private func loadBriefing() async {
        guard let client = supabaseClient.rawClient else {
            isLoading = false
            return
        }

        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            isLoading = false
            return
        }

        let today = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))

        do {
            let response: MorningBriefing = try await client
                .from("briefings")
                .select()
                .eq("profile_id", value: executiveId.uuidString)
                .eq("date", value: today)
                .single()
                .execute()
                .value

            briefing = response

            // Mark as viewed if first time
            if !response.wasViewed {
                struct BriefingViewedUpdate: Encodable {
                    let was_viewed: Bool
                    let first_viewed_at: String
                }
                try? await client
                    .from("briefings")
                    .update(BriefingViewedUpdate(was_viewed: true, first_viewed_at: Date().ISO8601Format()))
                    .eq("id", value: response.id.uuidString)
                    .execute()
            }
        } catch {
            TimedLogger.dataStore.info("MorningBriefingPane: No briefing for today — \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Engagement Tracking (4.07)

    private func trackEngagement() async {
        guard let briefing, let viewStart = viewStartTime else { return }
        let duration = Int(Date().timeIntervalSince(viewStart))
        guard duration > 3 else { return } // Ignore sub-3s views

        guard let client = supabaseClient.rawClient else { return }

        struct EngagementUpdate: Encodable {
            let engagement_duration_seconds: Int
        }
        try? await client
            .from("briefings")
            .update(EngagementUpdate(engagement_duration_seconds: duration))
            .eq("id", value: briefing.id.uuidString)
            .execute()

        // Record as Tier 0 observation (the system observes its own reception)
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }

        let observation = Tier0Observation(
            profileId: executiveId,
            occurredAt: Date(),
            source: .engagement,
            eventType: "briefing.viewed",
            rawData: [
                "briefing_date": AnyCodable(briefing.date),
                "engagement_duration_seconds": AnyCodable(duration),
                "sections_count": AnyCodable(briefing.content.sections.count),
            ]
        )
        try? await Tier0Writer.shared.recordObservation(observation)
    }
}
