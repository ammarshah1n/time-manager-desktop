// TimedRootView.swift — Timed macOS V2
// Sidebar: Today → Triage → WORK (buckets + Waiting) → TOOLS (Capture, Calendar) → Settings
// Morning Interview auto-shows on open. Dish Me Up via sheet.

import SwiftUI
import Dependencies

struct TimedRootView: View {
    @AppStorage("hasCompletedOnboarding")       private var hasCompletedOnboarding: Bool = false
    @AppStorage("lastMorningInterviewDate")     private var lastMorningInterviewDate: String = ""

    @State private var selection: NavSection? = .today
    @State private var triageItems: [TriageItem] = []
    @State private var tasks: [TimedTask] = []
    @State private var blocks: [CalendarBlock] = []
    @State private var wooItems: [WOOItem] = []
    @State private var captureItems: [CaptureItem] = []
    @State private var freeTimeSlots: [FreeTimeSlot] = []

    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var auth = AuthService.shared
    @State private var showMorningInterview = false
    @State private var morningDone          = false
    @State private var showDishMeUp         = false
    @State private var focusTask: TimedTask? = nil
    @State private var showFocus: Bool = false

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        rootSplitView
    }

    private func saveTasks(_ v: [TimedTask])      { Task { try? await DataStore.shared.saveTasks(v) } }
    private func saveTriage(_ v: [TriageItem])    { Task { try? await DataStore.shared.saveTriageItems(v) } }
    private func saveWOO(_ v: [WOOItem])          { Task { try? await DataStore.shared.saveWOOItems(v) } }
    private func saveBlocks(_ v: [CalendarBlock])   { Task { try? await DataStore.shared.saveBlocks(v) } }
    private func saveCaptures(_ v: [CaptureItem])   { Task { try? await DataStore.shared.saveCaptureItems(v) } }

    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .background(persistenceObserver)
        .onAppear { loadData(); checkMorningInterview(); network.start() }
        .overlay(alignment: .topTrailing) {
            if !network.isConnected {
                Text("Offline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.orange, in: Capsule())
                    .padding(12)
            }
        }
        .sheet(isPresented: onboardingBinding) { onboardingSheet }
        .sheet(isPresented: $showMorningInterview) { morningInterviewSheet }
        .sheet(isPresented: $showDishMeUp) { dishMeUpSheet }
        .sheet(isPresented: $showFocus) {
            FocusPane(task: focusTask) { showFocus = false; focusTask = nil }
                .frame(minWidth: 600, minHeight: 680)
        }
    }

    @ViewBuilder private var persistenceObserver: some View {
        Color.clear
            .onChange(of: tasks)       { (_: [TimedTask],     v: [TimedTask])     in saveTasks(v) }
            .onChange(of: triageItems) { (_: [TriageItem],    v: [TriageItem])    in saveTriage(v) }
            .onChange(of: wooItems)    { (_: [WOOItem],       v: [WOOItem])       in saveWOO(v) }
            .onChange(of: blocks)        { (_: [CalendarBlock], v: [CalendarBlock]) in saveBlocks(v) }
            .onChange(of: captureItems)  { (_: [CaptureItem],   v: [CaptureItem])   in saveCaptures(v) }
    }

    // MARK: - Helpers broken out to avoid type-checker timeout

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !hasCompletedOnboarding }, set: { _ in })
    }

    @ViewBuilder private var onboardingSheet: some View {
        OnboardingFlow {
            hasCompletedOnboarding = true
            lastMorningInterviewDate = Self.ymd.string(from: Date())
            showMorningInterview = true
        }
    }

    @ViewBuilder private var morningInterviewSheet: some View {
        MorningInterviewPane(tasks: $tasks, blocks: $blocks, isPresented: $showMorningInterview)
            .onDisappear {
                morningDone = true
                lastMorningInterviewDate = Self.ymd.string(from: Date())
            }
    }

    @ViewBuilder private var dishMeUpSheet: some View {
        DishMeUpSheet(tasks: $tasks) {
            showDishMeUp = false
        } onAccept: { firstTask in
            showDishMeUp = false
            focusTask = firstTask
            showFocus = true
        }
    }

    private func loadData() {
        Task {
            let store = DataStore.shared

            // Load from local DataStore first (offline-first)
            if let v = try? await store.loadTasks(),        !v.isEmpty { tasks       = v }
            else if !hasCompletedOnboarding { tasks = TimedTask.samples }

            if let v = try? await store.loadTriageItems(),  !v.isEmpty { triageItems = v }
            else if !hasCompletedOnboarding { triageItems = TriageItem.samples }

            if let v = try? await store.loadWOOItems(),     !v.isEmpty { wooItems    = v }
            else if !hasCompletedOnboarding { wooItems = WOOItem.samples }

            if let v = try? await store.loadBlocks(),       !v.isEmpty { blocks      = v }
            else if !hasCompletedOnboarding { blocks = CalendarBlock.samples }

            if let v = try? await store.loadCaptureItems(), !v.isEmpty { captureItems = v }
            else if !hasCompletedOnboarding { captureItems = CaptureItem.samples }

            // Start email sync if Graph token is available
            startEmailSyncIfReady()

            // Start calendar sync if Graph token is available
            startCalendarSyncIfReady()

            // Fetch from Supabase if signed in (overlay on local data)
            await fetchFromSupabaseIfConnected()
        }
    }

    private func fetchFromSupabaseIfConnected() async {
        guard auth.isSignedIn,
              let wsId = auth.workspaceId,
              let profileId = auth.profileId else { return }
        @Dependency(\.supabaseClient) var supa
        do {
            let dbTasks = try await supa.fetchTasks(wsId, profileId, ["pending", "in_progress"])
            if !dbTasks.isEmpty { tasks = dbTasks.map(TimedTask.init(from:)) }

            let dbEmails = try await supa.fetchEmailMessages(wsId, "inbox", 100)
            if !dbEmails.isEmpty { triageItems = dbEmails.map(TriageItem.init(from:)) }
        } catch {
            TimedLogger.supabase.error("Supabase fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startEmailSyncIfReady() {
        guard let token = auth.graphAccessToken,
              let wsId = auth.workspaceId,
              let eaId = auth.emailAccountId else { return }
        Task {
            await EmailSyncService.shared.start(
                accessToken: token, workspaceId: wsId, emailAccountId: eaId,
                profileId: auth.profileId
            )
        }
    }

    private func startCalendarSyncIfReady() {
        guard let token = auth.graphAccessToken else { return }
        Task {
            do {
                let result = try await CalendarSyncService.shared.autoSync(accessToken: token)
                blocks = result.blocks
                freeTimeSlots = result.freeSlots
            } catch {
                TimedLogger.calendar.error("Calendar auto-sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func checkMorningInterview() {
        let today = Self.ymd.string(from: Date())
        guard hasCompletedOnboarding && lastMorningInterviewDate != today else { return }

        // Skip morning interview during quiet hours
        let quietEnabled = UserDefaults.standard.bool(forKey: "prefs.quietHours.enabled")
        let quietEnd = UserDefaults.standard.integer(forKey: "prefs.quietHours.end")
        let currentHour = Calendar.current.component(.hour, from: Date())
        if quietEnabled && currentHour < quietEnd { return }

        showMorningInterview = true
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {

            // ── Today ──────────────────────────────────────────────────
            SidebarRow(
                label: "Today",
                icon: "sparkles",
                color: .indigo,
                badge: 0
            )
            .tag(NavSection.today)

            // ── Triage ─────────────────────────────────────────────────
            SidebarRow(
                label: "Triage",
                icon: "tray.and.arrow.down.fill",
                color: .red,
                badge: triageItems.count
            )
            .tag(NavSection.triage)

            // ── WORK ───────────────────────────────────────────────────
            Section {
                let workBuckets: [TaskBucket] = [.action, .calls, .reply, .readToday, .readThisWeek, .transit]
                ForEach(workBuckets, id: \.self) { bucket in
                    let bucketTasks = tasks.filter { $0.bucket == bucket && !$0.isDone }
                    let totalMins   = bucketTasks.reduce(0) { $0 + $1.estimatedMinutes }

                    SidebarRow(
                        label: bucket.rawValue,
                        icon: bucket.icon,
                        color: bucket.color,
                        badge: bucketTasks.count,
                        timeHint: totalMins > 0 ? timeHint(totalMins) : nil
                    )
                    .tag(NavSection.tasks(bucket))
                }

                // Waiting on Others
                SidebarRow(
                    label: "Waiting",
                    icon: "clock.badge.questionmark",
                    color: .teal,
                    badge: overdueWOOCount
                )
                .tag(NavSection.waiting)

            } header: {
                sidebarHeader("WORK")
            }

            // ── TOOLS ──────────────────────────────────────────────────
            Section {
                SidebarRow(label: "Capture", icon: "mic.fill", color: .purple, badge: 0)
                    .tag(NavSection.capture)

                SidebarRow(label: "Calendar", icon: "calendar", color: .blue, badge: 0)
                    .tag(NavSection.calendar)

            } header: {
                sidebarHeader("TOOLS")
            }

            // ── Settings ───────────────────────────────────────────────
            Section {
                SidebarRow(label: "Settings", icon: "gear", color: Color(.systemGray), badge: 0)
                    .tag(NavSection.prefs)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .today {
        case .today:
            TodayPane(
                tasks: $tasks,
                blocks: $blocks,
                triageCount: triageItems.count,
                morningDone: morningDone,
                freeTimeSlots: freeTimeSlots,
                onStartMorning: { showMorningInterview = true },
                onDishMeUp: { showDishMeUp = true }
            )
        case .triage:
            TriagePane(items: $triageItems, tasks: $tasks)
        case .tasks(let bucket):
            TasksPane(bucket: bucket, tasks: $tasks, blocks: $blocks)
        case .waiting:
            WaitingPane(items: $wooItems, tasks: $tasks)
        case .capture:
            CapturePane(tasks: $tasks, items: $captureItems)
        case .calendar:
            CalendarPane(blocks: $blocks)
        case .prefs:
            PrefsPane()
        }
    }

    // MARK: - Helpers

    private var overdueWOOCount: Int {
        wooItems.filter { item in
            guard let expected = item.expectedByDate else { return false }
            return expected < Date()
        }.count
    }

    private func timeHint(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : (minutes % 60 == 0 ? "\(minutes/60)h" : "\(minutes/60)h\(minutes%60)m")
    }

    @ViewBuilder
    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }
}

// MARK: - Nav section enum

enum NavSection: Hashable {
    case today
    case triage
    case tasks(TaskBucket)
    case waiting
    case capture
    case calendar
    case prefs
}

// MARK: - Sidebar row

struct SidebarRow: View {
    let label: String
    let icon: String
    let color: Color
    let badge: Int
    var timeHint: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13))

            Spacer()

            if let hint = timeHint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
