// TimediOSRootView.swift — Timed Core / AppEntry (iOS only)
// Adaptive root: iPhone uses a TabView (5 tabs + persistent orb FAB);
// iPad falls through to NavigationSplitView with the same tabs as the
// sidebar. Gated on horizontalSizeClass so a single binary covers both.

#if os(iOS)
import SwiftUI

@MainActor
struct TimediOSRootView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: TimedTab = .today
    @State private var showOrb = false

    private static let appGroupSuite = "group.com.timed.shared"

    var body: some View {
        Group {
            if sizeClass == .regular {
                ipadSplitLayout
            } else {
                iphoneTabLayout
            }
        }
        .onAppear { consumeIntentFlags() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumeIntentFlags() }
        }
    }

    /// Read-and-clear App Group intent flags written by AppIntents
    /// (`CaptureForTimedIntent`, `OpenTimedTabIntent`) and the URL scheme
    /// route in TimedAppShell. One-shot semantics — flags are wiped after
    /// they fire so subsequent launches don't re-open the orb / switch tabs.
    private func consumeIntentFlags() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupSuite) else { return }

        if defaults.bool(forKey: "intent.openCapture") {
            defaults.removeObject(forKey: "intent.openCapture")
            showOrb = true
        }

        if let raw = defaults.string(forKey: "intent.openTab") {
            defaults.removeObject(forKey: "intent.openTab")
            // Clamp via TimedTab(rawValue:) — unknown enum values are dropped.
            if let tab = TimedTab(rawValue: raw) {
                selectedTab = tab
            }
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
            List(selection: Binding<TimedTab?>(
                get: { selectedTab },
                set: { if let new = $0 { selectedTab = new } }
            )) {
                ForEach(TimedTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab as TimedTab?)
                }
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
        // Each pane needs richly-injected state (tasks, blocks, triageCount,
        // morningDone, callbacks). The Mac god-view in TimedRootView.swift
        // owns that state today; the iOS port will introduce a TimediOSAppState
        // observable that lifts it out so each pane can be instantiated from
        // both shells. For Step 6's deliverable we ship a placeholder per tab
        // — the actual pane wiring is a follow-up commit gated on the iOS
        // state-management refactor.
        switch self {
        case .today:    PlaceholderPane(title: "Today")
        case .plan:     PlaceholderPane(title: "Plan")
        case .briefing: PlaceholderPane(title: "Briefing")
        case .triage:   PlaceholderPane(title: "Triage")
        case .settings: PlaceholderPane(title: "Settings")
        }
    }
}

private struct PlaceholderPane: View {
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
            Text("iOS pane wiring lands once TimediOSAppState lifts feature-pane state out of TimedRootView.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Orb sheet (wraps ConversationView with iOS presentation chrome)

private struct ConversationOrbSheet: View {
    // Bindings are empty for iOS until tasks/calendar are wired through the
    // tab views — the orb still functions as voice + reasoning without them.
    @State private var tasks: [TimedTask] = []
    @State private var blocks: [CalendarBlock] = []

    var body: some View {
        ConversationView(
            tasks: $tasks,
            blocks: $blocks,
            freeTimeSlots: []
        )
    }
}

#endif
