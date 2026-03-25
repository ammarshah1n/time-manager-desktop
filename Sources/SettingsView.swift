import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(TimedPreferences.aiExecutablePathKey) private var aiExecutablePath = TimedPreferences.defaultAIExecutablePath

    var body: some View {
        Form {
            Section("Timed AI") {
                Text("Timed uses the local Codex CLI for planning and quiz mode.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("Codex executable path", text: $aiExecutablePath)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Configure AI path") {
                        chooseExecutable()
                    }

                    Button("Reset default") {
                        aiExecutablePath = TimedPreferences.defaultAIExecutablePath
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex executable"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []

        if panel.runModal() == .OK, let url = panel.url {
            aiExecutablePath = url.path
        }
    }
}
