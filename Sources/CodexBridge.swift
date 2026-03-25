import Foundation

struct CodexBridge {
    func run(prompt: String) async -> String? {
        let executablePath = TimedPreferences.aiExecutablePath
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            return nil
        }

        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputFile) }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdinPipe = Pipe()
                let outputPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = [
                    "exec",
                    "--skip-git-repo-check",
                    "--color", "never",
                    "--ephemeral",
                    "--output-last-message", outputFile.path,
                    "-"
                ]
                process.standardInput = stdinPipe
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                    if let data = prompt.data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                    stdinPipe.fileHandleForWriting.closeFile()
                    process.waitUntilExit()

                    if
                        process.terminationStatus == 0,
                        let data = try? Data(contentsOf: outputFile),
                        let response = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                        !response.isEmpty
                    {
                        continuation.resume(returning: response)
                        return
                    }

                    let fallbackData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let fallback = String(data: fallbackData, encoding: .utf8)?
                        .replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: fallback?.isEmpty == false ? fallback : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func extractTaskActions(response: String, taskTitles: [String]) -> [String: String] {
        let lines = response.split(whereSeparator: \.isNewline).map(String.init)
        var actions: [String: String] = [:]

        for line in lines {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let rawTitle = line[..<separatorIndex].trimmingCharacters(in: CharacterSet(charactersIn: "[] ").union(.whitespaces))
            let rawAction = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawAction.isEmpty else { continue }

            if let task = taskTitles.first(where: { $0.caseInsensitiveCompare(rawTitle) == .orderedSame }) {
                actions[task] = rawAction
            }
        }

        return actions
    }

    static func extractProminentSubject(response: String, knownSubjects: [String]) -> String? {
        for subject in knownSubjects {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: subject) + "\\b"
            if response.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return subject
            }
        }
        return nil
    }
}
