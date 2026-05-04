import SwiftUI
import Dependencies
import Supabase

struct MorningBriefingPane: View {
    @State private var briefing: MorningBriefing?
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var loadError: String?
    @State private var viewStartTime: Date?
    @State private var viewedSectionKeys: Set<String> = []
    @State private var dismissedSectionKeys: Set<String> = []
    @State private var actedSectionKeys: Set<String> = []

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
            Text(emptyHeadline)
                .font(.title3)
                .fontWeight(.medium)
            Text(emptyBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(Color.Timed.destructive)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await refreshBriefing() }
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)

                Button {
                    Task { await generateBriefingNow() }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating")
                    } else {
                        Text("Generate briefing now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    /// Day-keyed copy so Day-1 and Day-2 users see "engine is working on it",
    /// not "not enough data" (which on Day 2 reads as "the app is broken").
    /// Anchored on the first-bootstrap timestamp written by AuthService so we
    /// don't depend on whether the server `executives.onboarded_at` came back
    /// down to the client.
    private var daysSinceOnboard: Int {
        guard let bootstrappedAt = UserDefaults.standard.object(forKey: "auth.firstBootstrappedAt") as? Date
        else { return 0 }
        return Calendar.current.dateComponents([.day], from: bootstrappedAt, to: Date()).day ?? 0
    }

    private var emptyHeadline: String {
        switch daysSinceOnboard {
        case 0:  return "Your first briefing is being prepared"
        case 1:  return "Overnight analysis in progress"
        default: return "Briefing needs more signal"
        }
    }

    private var emptyBody: String {
        switch daysSinceOnboard {
        case 0:
            return "Tonight Timed runs its first overnight analysis of your patterns. Check back tomorrow morning."
        case 1:
            return "Your briefing usually appears by 6am. Refresh shortly."
        default:
            return "Timed does not have enough recent activity to create a useful briefing yet. Keep using Timed today and check back after the next overnight analysis."
        }
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(briefing)

            ForEach(Array(briefing.content.sections.enumerated()), id: \.offset) { index, section in
                Group {
                    if index == 0 {
                        leadSection(section)
                    } else if index == briefing.content.sections.count - 1 {
                        forwardLookingSection(section)
                    } else {
                        bodySection(section)
                    }
                }
                .overlay(alignment: .topTrailing) { sectionActionMenu(briefing: briefing, section: section) }
                .contentShape(Rectangle())
                .onTapGesture { Task { await recordSectionInteraction(briefing: briefing, section: section) } }
                .onAppear { Task { await recordSectionView(briefing: briefing, section: section) } }
                .opacity(dismissedSectionKeys.contains(section.section) ? 0.35 : 1.0)
            }
        }
        .padding(24)
    }

    // MARK: - Section Action Menu (Task 23)

    private func sectionActionMenu(briefing: MorningBriefing, section: BriefingSection) -> some View {
        HStack(spacing: 6) {
            Button {
                Task { await recordSectionActedOn(briefing: briefing, section: section) }
            } label: {
                Image(systemName: actedSectionKeys.contains(section.section) ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(actedSectionKeys.contains(section.section) ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Mark as acted on")

            Button {
                Task { await recordSectionDismissed(briefing: briefing, section: section) }
            } label: {
                Image(systemName: dismissedSectionKeys.contains(section.section) ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(dismissedSectionKeys.contains(section.section) ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(6)
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

    private struct GenerateMorningBriefingRequest: Encodable, Sendable {
        let executiveId: String
        let date: String
    }

    private struct GenerateMorningBriefingResponse: Decodable, Sendable {
        let results: [String: GenerateMorningBriefingResult]
    }

    private struct GenerateMorningBriefingResult: Decodable, Sendable {
        let status: String?
        let detail: String?
        let recommendationsError: String?

        enum CodingKeys: String, CodingKey {
            case status
            case detail
            case recommendationsError = "recommendations_error"
        }
    }

    private func refreshBriefing() async {
        isLoading = true
        loadError = nil
        await loadBriefing()
    }

    private func generateBriefingNow() async {
        guard let client = supabaseClient.rawClient else {
            loadError = "Timed is not connected to Supabase, so it cannot generate a briefing yet."
            return
        }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            loadError = "Sign in before generating a briefing."
            return
        }

        isGenerating = true
        loadError = nil
        defer { isGenerating = false }

        let today = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        do {
            let response: GenerateMorningBriefingResponse = try await client.functions.invoke(
                "generate-morning-briefing",
                options: FunctionInvokeOptions(
                    method: .post,
                    body: GenerateMorningBriefingRequest(executiveId: executiveId.uuidString, date: today)
                )
            )
            if let result = response.results[executiveId.uuidString], result.status == "error" {
                loadError = result.detail ?? "Briefing generation failed."
                return
            }
            await refreshBriefing()
        } catch {
            loadError = "Briefing generation failed: \(error.localizedDescription)"
        }
    }

    private func loadBriefing() async {
        guard let client = supabaseClient.rawClient else {
            loadError = "Supabase is not configured, so Timed cannot load briefings yet."
            isLoading = false
            return
        }

        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            loadError = "Sign in to view or generate your briefing."
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

    // MARK: - Section Interaction Capture (Task 23)

    private func recordSectionView(briefing: MorningBriefing, section: BriefingSection) async {
        guard !viewedSectionKeys.contains(section.section) else { return }
        await MainActor.run { _ = viewedSectionKeys.insert(section.section) }
        await writeSectionEvent(briefing: briefing, section: section, eventType: "briefing_section_viewed")
    }

    private func recordSectionInteraction(briefing: MorningBriefing, section: BriefingSection) async {
        await writeSectionEvent(briefing: briefing, section: section, eventType: "briefing_section_interacted")
    }

    private func recordSectionActedOn(briefing: MorningBriefing, section: BriefingSection) async {
        await MainActor.run { _ = actedSectionKeys.insert(section.section) }
        await writeSectionEvent(briefing: briefing, section: section, eventType: "recommendation_acted_on")
    }

    private func recordSectionDismissed(briefing: MorningBriefing, section: BriefingSection) async {
        await MainActor.run { _ = dismissedSectionKeys.insert(section.section) }
        await writeSectionEvent(briefing: briefing, section: section, eventType: "recommendation_dismissed")
    }

    /// Writes a behaviour_events row and appends to briefings.sections_interacted.
    private func writeSectionEvent(
        briefing: MorningBriefing,
        section: BriefingSection,
        eventType: String
    ) async {
        let wsId = await MainActor.run(body: { AuthService.shared.workspaceId })
        let profileId = await MainActor.run(body: { AuthService.shared.profileId })
        guard let wsId, let profileId else { return }

        let now = Date()
        let cal = Calendar.current
        let event = BehaviourEventInsert(
            workspaceId: wsId,
            profileId: profileId,
            eventType: eventType,
            taskId: nil,
            bucketType: "briefing",
            hourOfDay: cal.component(.hour, from: now),
            dayOfWeek: cal.component(.weekday, from: now) - 1,
            oldValue: nil,
            newValue: section.section
        )

        do {
            try await supabaseClient.insertBehaviourEvent(event)
        } catch {
            TimedLogger.supabase.debug("briefing section event insert failed: \(error.localizedDescription, privacy: .public)")
        }

        let entry: [String: String] = [
            "section_key": section.section,
            "event_type": eventType,
            "at": ISO8601DateFormatter().string(from: now),
        ]
        do {
            try await supabaseClient.appendBriefingSectionInteraction(briefing.id, entry)
        } catch {
            TimedLogger.supabase.debug("briefing sections_interacted append failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
