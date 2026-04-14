// PrefsPane.swift — Timed macOS Preview
// Settings: email accounts, sync, time blocks, notifications, appearance, voice.

import SwiftUI
import AVFoundation
import Dependencies

struct PrefsPane: View {
    /// Set to false to reveal all settings tabs for v2.
    private let v1BetaMode = true

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
        .padding(20)
        .frame(minWidth: 500, minHeight: 360)
        .navigationTitle("Settings")
    }

    enum PrefTab { case accounts, sync, blocks, notifications, appearance, voice, sharing, learning }
}

// MARK: - Accounts

struct AccountsTab: View {
    @State private var accounts: [PrefAccount] = [
        PrefAccount(email: "ammar@pff.org",    provider: "Outlook / Microsoft 365", icon: "envelope.badge.fill", color: .blue,  connected: true),
        PrefAccount(email: "me@ammarshah.com", provider: "Gmail",                   icon: "envelope.fill",       color: .red,   connected: false),
    ]
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Email Accounts")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach($accounts) { $acct in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(acct.color.opacity(0.12))
                            .frame(width: 32, height: 32)
                            .overlay { Image(systemName: acct.icon).font(.system(size: 14)).foregroundStyle(acct.color) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acct.email).font(.system(size: 13))
                            Text(acct.provider).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(acct.connected ? Color(.systemGreen) : Color(.systemRed))
                            .frame(width: 7, height: 7)
                        Toggle("", isOn: $acct.connected).labelsHidden().controlSize(.mini)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    if acct.id != accounts.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Button("Add Account…") { showAdd = true }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()
        }
        .sheet(isPresented: $showAdd) {
            VStack(spacing: 16) {
                Text("Choose a provider").font(.headline)
                ForEach(["Outlook / Microsoft 365", "Gmail", "iCloud", "Other (IMAP)"], id: \.self) { name in
                    Button(name) { showAdd = false }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }
                Button("Cancel", role: .cancel) { showAdd = false }
            }
            .padding(24).frame(width: 300)
        }
    }
}

struct PrefAccount: Identifiable {
    let id = UUID()
    let email, provider, icon: String
    let color: Color
    var connected: Bool
}

// MARK: - Sync

struct SyncTab: View {
    @AppStorage("prefs.sync.frequency")        private var frequency = 1
    @AppStorage("prefs.sync.syncOnLaunch")     private var syncOnLaunch = true
    @AppStorage("prefs.sync.fetchAttachments") private var fetchAttachments = false

    private let options = ["Every 5 min", "Every 15 min", "Every 30 min", "Manual only"]

    var body: some View {
        Form {
            Picker("Check for mail:", selection: $frequency) {
                ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
            }.frame(maxWidth: 280)

            Toggle("Sync on launch", isOn: $syncOnLaunch)
            Toggle("Download attachments automatically", isOn: $fetchAttachments)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Blocks

struct BlocksTab: View {
    @AppStorage("prefs.blocks.defaultMins") private var defaultMins: Double = 60
    @AppStorage("prefs.blocks.autoBlock")   private var autoBlock = false
    @AppStorage("prefs.blocks.bufferMins")  private var bufferMins: Double = 10

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Default duration")
                    Spacer()
                    Text(formatDur(defaultMins)).foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $defaultMins, in: 15...180, step: 15)
            }

            Toggle("Auto-suggest time blocks for action emails", isOn: $autoBlock)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Buffer between blocks")
                    Spacer()
                    Text("\(Int(bufferMins)) min").foregroundStyle(.secondary).monospacedDigit()
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    private let accents: [(String, Color)] = [("Blue", .blue), ("Crimson", Color(red: 0.827, green: 0.184, blue: 0.184)), ("Indigo", .indigo)]

    var body: some View {
        Form {
            Picker("Appearance:", selection: $theme) {
                ForEach(themes.indices, id: \.self) { Text(themes[$0]).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .frame(maxWidth: 260)

            VStack(alignment: .leading, spacing: 8) {
                Text("Accent colour:")
                HStack(spacing: 12) {
                    ForEach(accents.indices, id: \.self) { i in
                        Button { accent = i } label: {
                            ZStack {
                                Circle().fill(accents[i].1).frame(width: 26, height: 26)
                                if accent == i {
                                    Circle().stroke(.white, lineWidth: 2).frame(width: 20, height: 20)
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
    @AppStorage("prefs.voice.identifier") private var selectedVoice = ""
    @AppStorage("prefs.voice.rate")       private var rate: Double = 0.50
    @StateObject private var speech = SpeechService()

    private var grouped: [(String, [AVSpeechSynthesisVoice])] {
        let order = ["en-GB", "en-US", "en-AU"]
        let dict = Dictionary(grouping: SpeechService.availablePremiumVoices()) { $0.language }
        return order.compactMap { key in dict[key].map { (key, $0) } }
    }

    var body: some View {
        Form {
            ForEach(grouped, id: \.0) { lang, voices in
                Section(lang) {
                    ForEach(voices, id: \.identifier) { voice in
                        HStack {
                            Button { selectedVoice = voice.identifier } label: {
                                Image(systemName: selectedVoice == voice.identifier
                                      ? "largecircle.fill.circle" : "circle")
                            }
                            .buttonStyle(.plain)
                            Text(voice.name).font(.system(size: 13))
                            Spacer()
                            Text(voice.language).font(.caption).foregroundStyle(.secondary)
                            Button("Preview") { speech.previewVoice(voice.identifier) }
                                .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                }
            }
            Section("Rate") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Speaking rate")
                        Spacer()
                        Text(String(format: "%.2f", rate)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $rate, in: 0.40...0.60, step: 0.02)
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
                    Text("No behaviour rules yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(rules) { rule in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(rule.evidence ?? humanReadableRule(rule.ruleKey)).lineLimit(2)
                                Spacer()
                                Text(humanReadableRuleType(rule.ruleType))
                                    .font(.caption).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            HStack(spacing: 12) {
                                ProgressView(value: Double(rule.confidence))
                                    .frame(maxWidth: 120)
                                Text("\(Int(rule.confidence * 100))% confidence")
                                    .font(.caption).monospacedDigit()
                                Text("\(rule.sampleSize) observations")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Accuracy") {
                if accuracy.isEmpty {
                    Text("Complete some tasks to see accuracy data.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(accuracy.keys.sorted { $0.rawValue < $1.rawValue }), id: \.self) { bucket in
                        if let avg = accuracy[bucket] {
                            let deviation = avg.avgEstimated > 0
                                ? abs(avg.avgActual - avg.avgEstimated) / avg.avgEstimated
                                : 0
                            let count = records.filter { $0.bucket == bucket && $0.actualMinutes != nil }.count
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: bucket.icon)
                                    Text(bucket.rawValue).font(.headline)
                                }
                                Text("Avg estimate: \(Int(avg.avgEstimated))m | Avg actual: \(Int(avg.avgActual))m")
                                    .font(.caption).monospacedDigit()
                                ProgressView(value: min(deviation, 1.0))
                                    .tint(deviation < 0.10 ? .green : deviation < 0.25 ? .yellow : .red)
                                Text("Based on \(count) tasks")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Suggestions") {
                if suggestions.isEmpty {
                    Text("No suggestions yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(suggestions, id: \.bucket) { item in
                        HStack {
                            Image(systemName: item.bucket.icon)
                                .foregroundStyle(item.bucket.color)
                            Text(item.message)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
