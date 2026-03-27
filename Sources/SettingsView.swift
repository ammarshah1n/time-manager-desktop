import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(TimedPreferences.appearanceModeKey) private var appearanceMode = TimedPreferences.defaultAppearanceMode
    @AppStorage(TimedPreferences.accentColorKey) private var accentColor = TimedPreferences.defaultAccentColor
    @AppStorage(TimedPreferences.fontSizeCategoryKey) private var fontSizeCategory = TimedPreferences.defaultFontSizeCategory
    @AppStorage(TimedPreferences.aiExecutablePathKey) private var aiExecutablePath = TimedPreferences.defaultAIExecutablePath
    @AppStorage(TimedPreferences.autonomousModeEnabledKey) private var autonomousModeEnabled = true
    @AppStorage(TimedPreferences.fileSearchEnabledKey) private var fileSearchEnabled = true
    @AppStorage(TimedPreferences.codexMemoryEnabledKey) private var codexMemoryEnabled = true
    @AppStorage(TimedPreferences.workingRootKey) private var workingRoot = TimedPreferences.defaultWorkingRoot
    @AppStorage(TimedPreferences.codexMemDBPathKey) private var codexMemDBPath = TimedPreferences.defaultCodexMemDBPath
    @AppStorage(TimedPreferences.obsidianVaultPathKey) private var obsidianVaultPath = TimedPreferences.defaultObsidianVaultPath
    @AppStorage(TimedPreferences.focusSessionMinutesKey) private var focusSessionMinutes = TimedPreferences.defaultFocusSessionMinutes

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $appearanceMode) {
                    ForEach(TimedAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Accent colour")
                            .timedScaledFont(13, weight: .semibold)

                        Spacer()

                        Text(selectedAccentColor.title)
                            .timedScaledFont(12, weight: .medium)
                            .foregroundStyle(.secondary)
                    }

                    LazyHGrid(rows: [GridItem(.fixed(34))], spacing: 12) {
                        ForEach(TimedAccentColor.allCases) { option in
                            Button {
                                accentColor = option.rawValue
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(option.color.gradient)
                                        .frame(width: 26, height: 26)

                                    if option == selectedAccentColor {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(option == selectedAccentColor ? 0.12 : 0.04))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(option == selectedAccentColor ? option.color.opacity(0.9) : Color.white.opacity(0.08), lineWidth: option == selectedAccentColor ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(option.title)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Font size")
                            .timedScaledFont(13, weight: .semibold)

                        Spacer()

                        Text(fontSizeSummary)
                            .timedScaledFont(12, weight: .medium)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { selectedFontSizeCategory.sliderValue },
                            set: { fontSizeCategory = TimedFontSizeCategory.nearest(to: $0).rawValue }
                        ),
                        in: 0...2,
                        step: 1
                    )

                    HStack {
                        ForEach(TimedFontSizeCategory.allCases) { option in
                            Text(option.title)
                                .timedScaledFont(12, weight: option == selectedFontSizeCategory ? .semibold : .medium)
                                .foregroundStyle(option == selectedFontSizeCategory ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity, alignment: alignment(for: option))
                        }
                    }
                }
            }

            Section("Timed AI") {
                Text("Timed uses the local Codex CLI in autonomous mode for planning and study.")
                    .timedScaledFont(13)
                    .foregroundStyle(.secondary)

                Toggle("Enable autonomous Codex mode", isOn: $autonomousModeEnabled)
                Toggle("Allow local file and OneDrive search", isOn: $fileSearchEnabled)
                Toggle("Allow Codex memory search", isOn: $codexMemoryEnabled)

                TextField("Codex executable path", text: $aiExecutablePath)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Choose executable") {
                        chooseExecutable()
                    }

                    Button("Reset default") {
                        aiExecutablePath = TimedPreferences.defaultAIExecutablePath
                    }
                }
            }

            Section("Context sources") {
                TextField("Working root", text: $workingRoot)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Choose working root") {
                        chooseDirectory(title: "Choose working root") { workingRoot = $0 }
                    }

                    Button("Use home folder") {
                        workingRoot = TimedPreferences.defaultWorkingRoot
                    }
                }

                TextField("Codex memory DB path", text: $codexMemDBPath)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Choose memory DB") {
                        chooseFile(title: "Choose Codex memory DB") { codexMemDBPath = $0 }
                    }

                    Button("Reset memory DB") {
                        codexMemDBPath = TimedPreferences.defaultCodexMemDBPath
                    }
                }

                TextField("Obsidian vault path", text: $obsidianVaultPath)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Choose vault") {
                        chooseDirectory(title: "Choose Obsidian vault") {
                            obsidianVaultPath = $0
                            TimedPreferences.markObsidianVaultPromptHandled()
                        }
                    }

                    Button("Auto-detect") {
                        obsidianVaultPath = TimedPreferences.defaultObsidianVaultPath
                        TimedPreferences.markObsidianVaultPromptHandled()
                    }

                    Button("Sync Vault") {
                        NotificationCenter.default.post(name: .timedSyncObsidianVaultRequested, object: nil)
                    }
                    .disabled(obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Focus timer") {
                Picker("Pomodoro length", selection: $focusSessionMinutes) {
                    ForEach(TimedPreferences.supportedFocusSessionMinutes, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)

                Text("The inline focus timer uses this duration for task-bound Pomodoro sessions.")
                    .timedScaledFont(12)
                    .foregroundStyle(.secondary)
            }

            Section("Detected OneDrive roots") {
                if TimedPreferences.oneDriveRoots.isEmpty {
                    Text("No OneDrive roots detected on this Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(TimedPreferences.oneDriveRoots, id: \.self) { root in
                        Text(root)
                            .timedScaledFont(12)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 640)
        .onChange(of: obsidianVaultPath) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TimedPreferences.markObsidianVaultPromptHandled()
            }
        }
    }

    private var selectedAccentColor: TimedAccentColor {
        TimedAccentColor.resolve(accentColor)
    }

    private var selectedFontSizeCategory: TimedFontSizeCategory {
        TimedFontSizeCategory(rawValue: fontSizeCategory) ?? .medium
    }

    private var fontSizeSummary: String {
        "\(selectedFontSizeCategory.title) (\(Int(selectedFontSizeCategory.bodyPointSize))pt body)"
    }

    private func alignment(for option: TimedFontSizeCategory) -> Alignment {
        switch option {
        case .small: .leading
        case .medium: .center
        case .large: .trailing
        }
    }

    private func chooseExecutable() {
        chooseFile(title: "Choose Codex executable") {
            aiExecutablePath = $0
        }
    }

    private func chooseFile(title: String, assign: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []

        if panel.runModal() == .OK, let url = panel.url {
            assign(url.path)
        }
    }

    private func chooseDirectory(title: String, assign: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let url = panel.url {
            assign(url.path)
        }
    }
}
