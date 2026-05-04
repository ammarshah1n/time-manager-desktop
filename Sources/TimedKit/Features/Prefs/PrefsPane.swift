// PrefsPane.swift — Timed macOS
// Settings: email accounts, sync, time blocks, notifications, appearance, voice.
// Mac-only: uses NSColor and Mac-only picker styles, references SharingPane.

#if os(macOS)
import SwiftUI
import Foundation
import Dependencies

struct PrefsPane: View {
    /// Default false — all wired tabs visible. Set true via debug only to demo
    /// the locked-down v1 surface area. Persisted so it can flip without rebuild.
    @AppStorage("v1BetaMode") private var v1BetaMode: Bool = false

    @State private var tab = PrefTab.accounts

    var body: some View {
        TabView(selection: $tab) {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "envelope.badge") }
                .tag(PrefTab.accounts)

            // Hidden in v1 beta — email sync settings (triage product)
            if !v1BetaMode {
                SyncTab()
                    .tabItem { Label("Sync",     systemImage: "arrow.clockwise") }
                    .tag(PrefTab.sync)
            }

            BlocksTab()
                .tabItem { Label("Blocks",   systemImage: "calendar.badge.plus") }
                .tag(PrefTab.blocks)

            // Hidden in v1 beta — excessive for minimal settings
            if !v1BetaMode {
                NotificationsTab()
                    .tabItem { Label("Alerts",   systemImage: "bell") }
                    .tag(PrefTab.notifications)

                AppearanceTab()
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                    .tag(PrefTab.appearance)
            }

            VoiceTab()
                .tabItem { Label("Voice", systemImage: "waveform") }
                .tag(PrefTab.voice)

            // Hidden in v1 beta — sharing is v2
            if !v1BetaMode {
                SharingPane()
                    .tabItem { Label("Sharing", systemImage: "person.2") }
                    .tag(PrefTab.sharing)
            }

            // Hidden in v1 beta — ML learns silently, no user-facing tab
            if !v1BetaMode {
                LearningTab()
                    .tabItem { Label("Learning", systemImage: "brain") }
                    .tag(PrefTab.learning)
            }
        }
        .padding(TimedLayout.Spacing.lg)
        .frame(minWidth: TimedLayout.Width.settingsPane, minHeight: TimedLayout.Height.settingsPane)
        .navigationTitle("Settings")
    }

    enum PrefTab { case accounts, sync, blocks, notifications, appearance, voice, sharing, learning }
}

// MARK: - Accounts

struct AccountsTab: View {
    @StateObject private var auth = AuthService.shared
    @State private var isConnectingGoogle = false
    @State private var isConnectingOutlook = false
    @State private var googleConnectionMessage: String?
    @State private var googleConnectionError: String?
    @State private var outlookConnectionMessage: String?
    @State private var outlookConnectionError: String?
    @State private var activeGoogleAttempt: UUID?
    @State private var activeOutlookAttempt: UUID?

    private var signedInEmail: String? {
        guard let email = auth.userEmail, !email.isEmpty else { return nil }
        return email
    }

    private var googleAccountEmail: String? {
        guard let email = auth.googleEmail, !email.isEmpty else { return nil }
        return email
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TimedLayout.Spacing.md) {
            Text("Email Accounts")
                .font(TimedType.headline)

            if let signedInEmail {
                signedInIdentityRow(email: signedInEmail)
                outlookLinkRow(loginHint: signedInEmail)
                gmailLinkRow()
            } else {
                Text("No account signed in.")
                    .font(TimedType.footnote)
                    .foregroundStyle(Color.Timed.labelSecondary)
            }

            if let googleConnectionMessage {
                accountStatusRow(googleConnectionMessage, systemImage: "checkmark.circle.fill", color: Color.Timed.success)
            }

            if let googleConnectionError {
                accountStatusRow(googleConnectionError, systemImage: "exclamationmark.triangle.fill", color: Color.Timed.destructive)
            }

            if let outlookConnectionMessage {
                accountStatusRow(outlookConnectionMessage, systemImage: "checkmark.circle.fill", color: Color.Timed.success)
            }

            if let outlookConnectionError {
                accountStatusRow(outlookConnectionError, systemImage: "exclamationmark.triangle.fill", color: Color.Timed.destructive)
            }

            if signedInEmail != nil {
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer()
        }
    }

    private func signedInIdentityRow(email: String) -> some View {
        accountRow(
            PrefAccount(email: email, icon: "person.crop.circle.fill", connected: true),
            connectedCopy: "Signed in to Timed",
            pendingCopy: "Signed in to Timed"
        )
    }

    @ViewBuilder
    private func outlookLinkRow(loginHint: String) -> some View {
        let connected = auth.graphAccessToken != nil
        accountRow(
            PrefAccount(email: "Outlook + Calendar", icon: "envelope.badge.fill", connected: connected),
            connectedCopy: "Outlook and calendar connected",
            pendingCopy: "Not connected yet"
        )
        if !connected {
            Button {
                Task { await connectOutlook(loginHint: loginHint) }
            } label: {
                Label(isConnectingOutlook ? "Connecting Outlook" : "Connect Outlook", systemImage: isConnectingOutlook ? "hourglass" : "link")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isConnectingOutlook)
        }
    }

    @ViewBuilder
    private func gmailLinkRow() -> some View {
        if let email = googleAccountEmail {
            accountRow(
                PrefAccount(email: email, icon: "envelope", connected: auth.googleAccessToken != nil),
                connectedCopy: "Gmail and calendar connected",
                pendingCopy: "Gmail sign-in complete. Timed is finishing setup."
            )
        } else {
            Button {
                Task { await connectGoogle() }
            } label: {
                Label(isConnectingGoogle ? "Connecting Gmail" : "Add Gmail", systemImage: isConnectingGoogle ? "hourglass" : "plus.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isConnectingGoogle)
        }
    }

    @MainActor
    private func connectGoogle() async {
        isConnectingGoogle = true
        googleConnectionMessage = nil
        googleConnectionError = nil
        let attempt = UUID()
        activeGoogleAttempt = attempt

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(45))
            guard activeGoogleAttempt == attempt, isConnectingGoogle else { return }
            auth.error = "Gmail did not open a sign-in window. Try again, or restart Timed if the browser is hidden."
            googleConnectionError = auth.error
            isConnectingGoogle = false
        }

        await auth.signInWithGoogle()

        guard activeGoogleAttempt == attempt else { return }
        activeGoogleAttempt = nil
        isConnectingGoogle = false
        if let error = auth.error, !error.isEmpty {
            googleConnectionError = error
        } else if auth.googleAccessToken != nil {
            googleConnectionMessage = "Gmail connected. Timed is importing mail and calendar now."
        } else {
            googleConnectionError = "Gmail was not connected. Try again."
        }
    }

    @MainActor
    private func connectOutlook(loginHint: String) async {
        isConnectingOutlook = true
        outlookConnectionMessage = nil
        outlookConnectionError = nil
        let attempt = UUID()
        activeOutlookAttempt = attempt

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(45))
            guard activeOutlookAttempt == attempt, isConnectingOutlook else { return }
            auth.error = "Outlook did not open a sign-in window. Try again, or restart Timed if the browser is hidden."
            outlookConnectionError = auth.error
            isConnectingOutlook = false
        }

        await auth.signInWithGraph(loginHint: loginHint)

        guard activeOutlookAttempt == attempt else { return }
        activeOutlookAttempt = nil
        isConnectingOutlook = false
        if let error = auth.error, !error.isEmpty {
            outlookConnectionError = error
        } else if auth.graphAccessToken != nil {
            outlookConnectionMessage = "Outlook connected. Timed is importing mail and calendar now."
        } else {
            outlookConnectionError = "Outlook was not connected. Try again."
        }
    }

    private func accountStatusRow(_ message: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: TimedLayout.Spacing.xs) {
            Image(systemName: systemImage)
                .font(TimedType.caption.weight(.semibold))
            Text(message)
                .font(TimedType.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, TimedLayout.Spacing.sm)
    }

    @ViewBuilder
    private func accountRow(_ acct: PrefAccount, connectedCopy: String, pendingCopy: String) -> some View {
        HStack(spacing: TimedLayout.Spacing.sm) {
            RoundedRectangle(cornerRadius: TimedLayout.Radius.chip)
                .fill(Color.Timed.backgroundSecondary)
                .frame(width: TimedLayout.Height.accountIcon, height: TimedLayout.Height.accountIcon)
                .overlay {
                    Image(systemName: acct.icon)
                        .font(TimedType.footnote)
                        .foregroundStyle(Color.Timed.labelSecondary)
                }
            VStack(alignment: .leading, spacing: TimedLayout.Spacing.xxs) {
                Text(acct.email)
                    .font(TimedType.footnote)
                Text(acct.connected ? connectedCopy : pendingCopy)
                    .font(TimedType.caption)
                    .foregroundStyle(Color.Timed.labelSecondary)
            }
            Spacer()
            Circle()
                .fill(acct.connected ? Color.Timed.success : Color.Timed.labelTertiary)
                .frame(width: TimedLayout.Height.statusDot, height: TimedLayout.Height.statusDot)
        }
        .padding(.vertical, TimedLayout.Spacing.xs)
        .padding(.horizontal, TimedLayout.Spacing.sm)
        .background(Color.Timed.backgroundSecondary, in: RoundedRectangle(cornerRadius: TimedLayout.Radius.input))
    }
}

struct PrefAccount: Identifiable {
    let id = UUID()
    let email, icon: String
    var connected: Bool
}

// MARK: - Sync

struct SyncTab: View {
    @AppStorage("prefs.sync.frequency")        private var frequency = 1
    @AppStorage("prefs.sync.syncOnLaunch")     private var syncOnLaunch = true
    @AppStorage("prefs.sync.fetchAttachments") private var fetchAttachments = false
    @StateObject private var syncHealth = SyncHealthCenter.shared

    private let options = ["Every 5 min", "Every 15 min", "Every 30 min", "Manual only"]

    var body: some View {
        Form {
            Picker("Check for mail:", selection: $frequency) {
                ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
            }
            .frame(maxWidth: TimedLayout.Width.settingsPicker)

            Toggle("Sync on launch", isOn: $syncOnLaunch)
            Toggle("Download attachments automatically", isOn: $fetchAttachments)

            Section("Sync health") {
                if let issue = syncHealth.lastIssue {
                    Label("Sync needs attention", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.Timed.destructive)
                    Text("\(issue.operationType): \(issue.message)")
                        .font(TimedType.caption)
                        .foregroundStyle(Color.Timed.labelSecondary)
                    Text("Last seen \(issue.occurredAt.formatted(date: .omitted, time: .shortened))")
                        .font(TimedType.caption)
                        .foregroundStyle(Color.Timed.labelTertiary)
                } else if syncHealth.permanentFailureCount > 0 {
                    Label("Some changes could not be synced", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.Timed.destructive)
                } else if syncHealth.pendingCount > 0 {
                    Label("\(syncHealth.pendingCount) change\(syncHealth.pendingCount == 1 ? "" : "s") waiting to sync", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(Color.Timed.labelSecondary)
                } else {
                    Label("Authenticated writes look healthy", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.Timed.success)
                }

                Button("Retry sync now") {
                    Task { await retrySync() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .task { await refreshDiagnostics() }
    }

    private func retrySync() async {
        await DataBridge.shared.flushOfflineReplay()
        await refreshDiagnostics()
    }

    private func refreshDiagnostics() async {
        _ = await DataBridge.shared.offlineQueueDiagnostics()
    }
}

// MARK: - Blocks

struct BlocksTab: View {
    @AppStorage("prefs.blocks.defaultMins") private var defaultMins: Double = 60
    @AppStorage("prefs.blocks.autoBlock")   private var autoBlock = false
    @AppStorage("prefs.blocks.bufferMins")  private var bufferMins: Double = 10

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: TimedLayout.Spacing.xs) {
                HStack {
                    Text("Default duration")
                    Spacer()
                    Text(formatDur(defaultMins))
                        .foregroundStyle(Color.Timed.labelSecondary)
                        .monospacedDigit()
                }
                Slider(value: $defaultMins, in: 15...180, step: 15)
            }

            Toggle("Auto-suggest time blocks for action emails", isOn: $autoBlock)

            VStack(alignment: .leading, spacing: TimedLayout.Spacing.xs) {
                HStack {
                    Text("Buffer between blocks")
                    Spacer()
                    Text("\(Int(bufferMins)) min")
                        .foregroundStyle(Color.Timed.labelSecondary)
                        .monospacedDigit()
                }
                Slider(value: $bufferMins, in: 0...30, step: 5)
            }
        }
        .formStyle(.grouped)
    }

    private func formatDur(_ m: Double) -> String {
        let mins = Int(m)
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60; let r = mins % 60
        return r == 0 ? "\(h) hr" : "\(h)h \(r)m"
    }
}

// MARK: - Notifications

struct NotificationsTab: View {
    @AppStorage("prefs.notif.enabled")        private var enabled = true
    @AppStorage("prefs.notif.blockStart")     private var blockStart = true
    @AppStorage("prefs.notif.breakReminders") private var breakReminders = true
    @AppStorage("prefs.notif.digest")         private var digestEnabled = false
    @AppStorage("prefs.quietHours.enabled")   private var quietEnabled = true
    @AppStorage("prefs.quietHours.end")       private var quietEnd = 9

    var body: some View {
        Form {
            Toggle("Enable notifications", isOn: $enabled)

            Group {
                Toggle("Block start reminders",       isOn: $blockStart)
                Toggle("Break reminders",              isOn: $breakReminders)
                Toggle("Daily digest at 8 am",         isOn: $digestEnabled)
            }
            .disabled(!enabled)

            Section("Quiet Hours") {
                Toggle("Enable quiet hours", isOn: $quietEnabled)
                Stepper("End at \(quietEnd):00", value: $quietEnd, in: 5...22)
                    .disabled(!quietEnabled)
                Text("During quiet hours, only Do First tasks appear in the plan.")
                    .font(TimedType.caption)
                    .foregroundStyle(Color.Timed.labelSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceTab: View {
    @AppStorage("prefs.appearance.theme")  private var theme = 0
    @AppStorage("prefs.appearance.accent") private var accent = 0

    private let themes  = ["Automatic", "Light", "Dark"]
    private let accents: [(String, Color)] = [
        ("Blue", Color.Timed.accent),
        ("Crimson", Color.Timed.destructive),
        ("Graphite", Color.Timed.labelSecondary),
    ]

    var body: some View {
        Form {
            Picker("Appearance:", selection: $theme) {
                ForEach(themes.indices, id: \.self) { Text(themes[$0]).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .frame(maxWidth: TimedLayout.Width.settingsCompact)

            VStack(alignment: .leading, spacing: TimedLayout.Spacing.xs) {
                Text("Accent colour:")
                HStack(spacing: TimedLayout.Spacing.sm) {
                    ForEach(accents.indices, id: \.self) { i in
                        Button { accent = i } label: {
                            ZStack {
                                Circle()
                                    .fill(accents[i].1)
                                    .frame(width: TimedLayout.Height.colorSwatch, height: TimedLayout.Height.colorSwatch)
                                if accent == i {
                                    Circle()
                                        .stroke(Color.Timed.backgroundPrimary, lineWidth: TimedLayout.Stroke.hairline)
                                        .frame(width: TimedLayout.Height.swatchRing, height: TimedLayout.Height.swatchRing)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(accents[i].0)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Voice

struct VoiceTab: View {
    @AppStorage("pendingVoiceOnboarding") private var pendingVoiceOnboarding = false
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Form {
            if pendingVoiceOnboarding {
                Section("Setup") {
                    HStack(alignment: .top, spacing: TimedLayout.Spacing.sm) {
                        Image(systemName: "exclamationmark.circle")
                            .font(TimedType.subheadline)
                            .foregroundStyle(Color.Timed.labelSecondary)
                        VStack(alignment: .leading, spacing: TimedLayout.Spacing.xxs) {
                            Text("Voice setup is incomplete.")
                                .font(TimedType.footnote.weight(.medium))
                            Text("Take 90 seconds to introduce yourself — Timed needs this to feel right.")
                                .font(TimedType.caption)
                                .foregroundStyle(Color.Timed.labelSecondary)
                        }
                        Spacer()
                        Button {
                            auth.replayOnboarding()
                        } label: {
                            Text("Resume setup")
                                .font(TimedType.caption.weight(.medium))
                                .lineLimit(1)
                        }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(minHeight: TimedLayout.Height.iconButton)
                    }
                }
            }
            Section("Voice") {
                HStack(alignment: .top, spacing: TimedLayout.Spacing.sm) {
                    Image(systemName: pendingVoiceOnboarding ? "info.circle" : "checkmark.circle")
                        .font(TimedType.subheadline)
                        .foregroundStyle(Color.Timed.labelSecondary)
                    VStack(alignment: .leading, spacing: TimedLayout.Spacing.xxs) {
                        Text(pendingVoiceOnboarding ? "Assistant voice is installed." : "Voice is ready.")
                            .font(TimedType.subheadline)
                        Text(pendingVoiceOnboarding ? "Resume setup to finish personalising spoken check-ins and confirmations." : "Timed uses its configured assistant voice for check-ins and confirmations.")
                            .font(TimedType.caption)
                            .foregroundStyle(Color.Timed.labelSecondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Learning

struct LearningTab: View {
    @Dependency(\.supabaseClient) private var supabase
    @State private var rules: [BehaviourRuleRow] = []
    @State private var accuracy: [TaskBucket: (avgEstimated: Double, avgActual: Double)] = [:]
    @State private var suggestions: [(bucket: TaskBucket, message: String)] = []
    @State private var records: [CompletionRecord] = []

    var body: some View {
        Form {
            Section("What I've Learned") {
                if rules.isEmpty {
                    Text("No behaviour rules yet.")
                        .foregroundStyle(Color.Timed.labelSecondary)
                } else {
                    ForEach(rules) { rule in
                        VStack(alignment: .leading, spacing: TimedLayout.Spacing.xs) {
                            HStack {
                                Text(rule.evidence ?? humanReadableRule(rule.ruleKey)).lineLimit(2)
                                Spacer()
                                Text(humanReadableRuleType(rule.ruleType))
                                    .font(TimedType.caption.weight(.semibold))
                                    .padding(.horizontal, TimedLayout.Spacing.xs)
                                    .padding(.vertical, TimedLayout.Spacing.xxs)
                                    .background(Color.Timed.labelQuaternary, in: Capsule())
                            }
                            HStack(spacing: TimedLayout.Spacing.sm) {
                                ProgressView(value: Double(rule.confidence))
                                    .frame(maxWidth: TimedLayout.Width.learningProgress)
                                Text("\(Int(rule.confidence * 100))% confidence")
                                    .font(TimedType.caption)
                                    .monospacedDigit()
                                Text("\(rule.sampleSize) observations")
                                    .font(TimedType.caption)
                                    .foregroundStyle(Color.Timed.labelSecondary)
                            }
                        }
                    }
                }
            }

            Section("Accuracy") {
                if accuracy.isEmpty {
                    Text("Complete some tasks to see accuracy data.")
                        .foregroundStyle(Color.Timed.labelSecondary)
                } else {
                    ForEach(Array(accuracy.keys.sorted { $0.rawValue < $1.rawValue }), id: \.self) { bucket in
                        if let avg = accuracy[bucket] {
                            let deviation = avg.avgEstimated > 0
                                ? abs(avg.avgActual - avg.avgEstimated) / avg.avgEstimated
                                : 0
                            let count = records.filter { $0.bucket == bucket && $0.actualMinutes != nil }.count
                            VStack(alignment: .leading, spacing: TimedLayout.Spacing.xxs) {
                                HStack {
                                    Image(systemName: bucket.icon)
                                        .foregroundStyle(Color.Timed.labelSecondary)
                                    Text(bucket.rawValue)
                                        .font(TimedType.headline)
                                }
                                Text("Avg estimate: \(Int(avg.avgEstimated))m | Avg actual: \(Int(avg.avgActual))m")
                                    .font(TimedType.caption)
                                    .monospacedDigit()
                                ProgressView(value: min(deviation, 1.0))
                                    .tint(Color.Timed.labelSecondary)
                                Text("Based on \(count) tasks")
                                    .font(TimedType.caption2)
                                    .foregroundStyle(Color.Timed.labelSecondary)
                            }
                        }
                    }
                }
            }

            Section("Suggestions") {
                if suggestions.isEmpty {
                    Text("No suggestions yet.")
                        .foregroundStyle(Color.Timed.labelSecondary)
                } else {
                    ForEach(suggestions, id: \.bucket) { item in
                        HStack(spacing: TimedLayout.Spacing.sm) {
                            Image(systemName: item.bucket.icon)
                                .foregroundStyle(Color.Timed.labelSecondary)
                            Text(item.message)
                        }
                        .padding(TimedLayout.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.Timed.labelQuaternary, in: RoundedRectangle(cornerRadius: TimedLayout.Radius.input))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadData() }
    }

    private func loadData() async {
        do {
            guard let wsId = AuthService.shared.workspaceId else { return }
            rules = try await supabase.fetchBehaviourRules(wsId)
        } catch {}
        do {
            records = try await DataStore.shared.loadCompletionRecords()
            accuracy = InsightsEngine.accuracyByBucket(records)
            suggestions = InsightsEngine.suggestedAdjustments(records)
        } catch {}
    }

    private func humanReadableRule(_ key: String) -> String {
        switch key {
        case "calls_before_email": return "You prefer handling calls before email"
        case "email_first": return "You tend to start with email"
        case "deep_work_morning": return "Deep focus works best in the morning"
        case "quick_wins_first": return "You often start with quick tasks"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func humanReadableRuleType(_ type: String) -> String {
        switch type {
        case "ordering": return "Ordering"
        case "threshold": return "Threshold"
        case "timing": return "Timing"
        case "category_pref": return "Preference"
        default: return type.capitalized
        }
    }
}

#if DEBUG
@MainActor
private enum VoiceTabPreviewStorage {
    static let pendingVoiceSetup: UserDefaults = {
        let defaults = UserDefaults(suiteName: "Timed.VoiceTabPreview.Pending") ?? .standard
        defaults.set(true, forKey: "pendingVoiceOnboarding")
        return defaults
    }()
}

#Preview("Voice Setup - Light") {
    VoiceTab()
        .environmentObject(AuthService.shared)
        .defaultAppStorage(VoiceTabPreviewStorage.pendingVoiceSetup)
}

#Preview("Voice Setup - Dark") {
    VoiceTab()
        .environmentObject(AuthService.shared)
        .defaultAppStorage(VoiceTabPreviewStorage.pendingVoiceSetup)
        .preferredColorScheme(.dark)
}
#endif

#endif
