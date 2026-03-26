import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(TimedPreferences.aiExecutablePathKey) private var aiExecutablePath = TimedPreferences.defaultAIExecutablePath
    @AppStorage(TimedPreferences.autonomousModeEnabledKey) private var autonomousModeEnabled = true
    @AppStorage(TimedPreferences.fileSearchEnabledKey) private var fileSearchEnabled = true
    @AppStorage(TimedPreferences.codexMemoryEnabledKey) private var codexMemoryEnabled = true
    @AppStorage(TimedPreferences.workingRootKey) private var workingRoot = TimedPreferences.defaultWorkingRoot
    @AppStorage(TimedPreferences.codexMemDBPathKey) private var codexMemDBPath = TimedPreferences.defaultCodexMemDBPath
    @AppStorage(TimedPreferences.obsidianVaultPathKey) private var obsidianVaultPath = TimedPreferences.defaultObsidianVaultPath

    var body: some View {
        Form {
            Section("Timed AI") {
                Text("Timed uses the local Codex CLI in autonomous mode for planning and study.")
                    .font(.system(size: 13))
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

            Section("Detected OneDrive roots") {
                if TimedPreferences.oneDriveRoots.isEmpty {
                    Text("No OneDrive roots detected on this Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(TimedPreferences.oneDriveRoots, id: \.self) { root in
                        Text(root)
                            .font(.system(size: 12))
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
