import Foundation

struct CodexRunRequest {
    let prompt: String
    let autonomousMode: Bool
    let workingRoot: String
    let additionalRoots: [String]
}

struct CodexBridge {
    func run(request: CodexRunRequest) async -> String? {
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
                process.currentDirectoryURL = URL(fileURLWithPath: request.workingRoot)
                process.arguments = Self.arguments(for: request, outputFile: outputFile.path)
                process.standardInput = stdinPipe
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                    if let data = request.prompt.data(using: .utf8) {
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

    static func arguments(for request: CodexRunRequest, outputFile: String) -> [String] {
        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--color", "never",
            "-C", request.workingRoot
        ]

        if request.autonomousMode {
            arguments.append("--dangerously-bypass-approvals-and-sandbox")
            arguments.append("--search")
            for root in request.additionalRoots where root != request.workingRoot {
                arguments.append(contentsOf: ["--add-dir", root])
            }
        } else {
            arguments.append("--ephemeral")
        }

        arguments.append(contentsOf: [
            "--output-last-message", outputFile,
            "-"
        ])

        return arguments
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

    static func extractSubjectConfidences(response: String, knownSubjects: [String]) -> [String: Int] {
        let lines = response.split(whereSeparator: \.isNewline).map(String.init)
        var values: [String: Int] = [:]

        for line in lines {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let rawKey = parts[0]
                .trimmingCharacters(in: CharacterSet(charactersIn: "[] ").union(.whitespacesAndNewlines))
                .lowercased()
            guard rawKey.hasSuffix("confidence") else { continue }

            let subjectName = rawKey
                .replacingOccurrences(of: "confidence", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                let subject = knownSubjects.first(where: { $0.lowercased() == subjectName }),
                let confidence = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                (1...5).contains(confidence)
            else {
                continue
            }

            values[subject] = confidence
        }

        return values
    }
}
