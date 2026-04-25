// TimediOSRootView.swift — Timed Core / AppEntry (iOS only)
// Adaptive root: iPhone uses a TabView (5 tabs + persistent orb FAB);
// iPad falls through to NavigationSplitView with the same tabs as the
// sidebar. Gated on horizontalSizeClass so a single binary covers both.

#if os(iOS)
import SwiftUI

@MainActor
struct TimediOSRootView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: TimedTab = .today
    @State private var showOrb = false

    var body: some View {
        if sizeClass == .regular {
            ipadSplitLayout
        } else {
            iphoneTabLayout
        }
    }

    // MARK: - iPhone (compact)

    private var iphoneTabLayout: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                ForEach(TimedTab.allCases) { tab in
                    tab.destination
                        .tabItem {
                            Label(tab.title, systemImage: tab.icon)
                        }
                        .tag(tab)
                }
            }
            orbFAB
                .padding(.trailing, 20)
                .padding(.bottom, 60)
        }
        .sheet(isPresented: $showOrb) {
            ConversationOrbSheet()
        }
    }

    // MARK: - iPad (regular)

    private var ipadSplitLayout: some View {
        NavigationSplitView {
            List(TimedTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Timed")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                orbFAB.padding()
            }
        } detail: {
            selectedTab.destination
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showOrb) {
            ConversationOrbSheet()
        }
    }

    // MARK: - Orb FAB (capture-from-anywhere)

    private var orbFAB: some View {
        Button {
            showOrb = true
        } label: {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .medium))
                )
                .shadow(radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Timed orb")
    }
}

// MARK: - Tab enumeration

enum TimedTab: String, CaseIterable, Identifiable, Hashable {
    case today
    case plan
    case briefing
    case triage
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:    return "Today"
        case .plan:     return "Plan"
        case .briefing: return "Briefing"
        case .triage:   return "Triage"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today:    return "sun.max"
        case .plan:     return "calendar"
        case .briefing: return "sparkles"
        case .triage:   return "tray.full"
        case .settings: return "gearshape"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .today:    TodayPane()
        case .plan:     PlanPane()
        case .briefing: MorningBriefingPane()
        case .triage:   TriagePane()
        case .settings: PrefsPane()
        }
    }
}

// MARK: - Orb sheet placeholder

private struct ConversationOrbSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The conversation orb itself lives in TimedKit/Features/Conversation/.
        // This sheet wraps ConversationView with iOS presentation chrome.
        // Wired in Step 7 once the in-flight voice rework lands cleanly.
        VStack(spacing: 16) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            Spacer()
            Text("Orb sheet — wired to ConversationView in Step 7")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") { dismiss() }
        }
    }
}

#endif
