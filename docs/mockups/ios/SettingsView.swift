// SettingsView.swift — Timed iOS Mockup
// Screen 4: Email accounts, notifications, defaults, theme.

import SwiftUI

struct SettingsView: View {
    @State private var accounts       = MockEmailAccount.samples
    @State private var syncFrequency  = SyncFrequency.every15m
    @State private var defaultMinutes: Double = 60
    @State private var notificationsOn = true
    @State private var breakReminders  = true
    @State private var theme           = AppTheme.system
    @State private var showAddAccount  = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Email Accounts ──────────────────────────────────────
                Section {
                    ForEach($accounts) { $account in
                        AccountRow(account: $account)
                    }
                    .onDelete { accounts.remove(atOffsets: $0) }

                    Button {
                        showAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                } header: {
                    SectionHeader("Email Accounts")
                }

                // ── Sync ────────────────────────────────────────────────
                Section {
                    Picker("Check every", selection: $syncFrequency) {
                        ForEach(SyncFrequency.allCases) { freq in
                            Text(freq.label).tag(freq)
                        }
                    }
                } header: {
                    SectionHeader("Sync")
                }

                // ── Time Blocks ─────────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Default duration")
                            Spacer()
                            Text(formatDuration(defaultMinutes))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $defaultMinutes, in: 15...180, step: 15)
                            .tint(.blue)
                    }
                    .padding(.vertical, 4)
                } header: {
                    SectionHeader("Time Blocks")
                }

                // ── Notifications ───────────────────────────────────────
                Section {
                    Toggle("Notifications", isOn: $notificationsOn)
                        .tint(.blue)
                    Toggle("Break reminders", isOn: $breakReminders)
                        .tint(.blue)
                        .disabled(!notificationsOn)
                        .foregroundStyle(notificationsOn ? .primary : .secondary)
                } header: {
                    SectionHeader("Notifications")
                }

                // ── Appearance ──────────────────────────────────────────
                Section {
                    Picker("Theme", selection: $theme) {
                        ForEach(AppTheme.allCases) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                } header: {
                    SectionHeader("Appearance")
                }

                // ── About ───────────────────────────────────────────────
                Section {
                    LabeledContent("Version", value: "0.1.0 (mockup)")
                    NavigationLink("Privacy Policy") {
                        Text("Privacy Policy")
                            .padding()
                            .navigationTitle("Privacy Policy")
                    }
                    NavigationLink("Acknowledgements") {
                        Text("Acknowledgements")
                            .padding()
                            .navigationTitle("Acknowledgements")
                    }
                } header: {
                    SectionHeader("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddAccount) {
                AddAccountSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m < 60 { return "\(m) min" }
        let h = m / 60; let rem = m % 60
        return rem == 0 ? "\(h) hr" : "\(h)h \(rem)m"
    }
}

// MARK: - Account Row

struct AccountRow: View {
    @Binding var account: MockEmailAccount

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(account.color.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: account.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(account.color)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.address)
                    .font(.system(size: 15))
                Text(account.provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(account.isConnected ? Color(.systemGreen) : Color(.systemRed))
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Add Account Sheet

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let providers = [
        ("Microsoft 365 / Outlook", "envelope.badge.fill", Color.blue),
        ("Gmail",                    "envelope.fill",       Color.red),
        ("iCloud Mail",              "icloud.fill",         Color.gray),
        ("Other (IMAP)",             "envelope.circle",     Color.secondary),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(providers, id: \.0) { name, icon, color in
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color.opacity(0.12))
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Image(systemName: icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(color)
                                }
                            Text(name)
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Shared Header

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.subheadline).fontWeight(.semibold)
    }
}

// MARK: - Enums

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self { case .light: "Light"; case .dark: "Dark"; case .system: "Auto" }
    }
    var icon: String {
        switch self { case .light: "sun.max"; case .dark: "moon"; case .system: "circle.lefthalf.filled" }
    }
}

enum SyncFrequency: String, CaseIterable, Identifiable {
    case every5m = "every5m"
    case every15m = "every15m"
    case every30m = "every30m"
    case manual = "manual"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .every5m:  "5 minutes"
        case .every15m: "15 minutes"
        case .every30m: "30 minutes"
        case .manual:   "Manual"
        }
    }
}

#Preview {
    SettingsView()
}
