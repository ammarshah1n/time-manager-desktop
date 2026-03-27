import Foundation

struct CodexRunRequest {
    let prompt: String
    let autonomousMode: Bool
    let workingRoot: String
    let additionalRoots: [String]
}

struct CodexRunFailure: Equatable {
    let message: String
    let exitCode: Int32?
}

enum CodexRunResult: Equatable {
    case success(String)
    case failure(CodexRunFailure)
}

struct CodexBridge {
    func send(prompt: String) async -> CodexRunResult {
        await run(
            request: CodexRunRequest(
                prompt: prompt,
                autonomousMode: TimedPreferences.autonomousModeEnabled,
                workingRoot: TimedPreferences.workingRoot,
                additionalRoots: TimedPreferences.codexAdditionalRoots
            )
        )
    }

    func run(request: CodexRunRequest) async -> CodexRunResult {
        let executablePath = TimedPreferences.aiExecutablePath
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            return .failure(
                CodexRunFailure(
                    message: "Codex executable not found at \(executablePath). Update the path in Settings.",
                    exitCode: nil
                )
            )
        }

        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputFile) }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executablePath)
                process.currentDirectoryURL = URL(fileURLWithPath: request.workingRoot)
                process.arguments = Self.arguments(for: request, outputFile: outputFile.path)
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    if let data = request.prompt.data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                    stdinPipe.fileHandleForWriting.closeFile()
                    process.waitUntilExit()

                    let stderr = Self.cleanedOutput(from: stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    let stdout = Self.cleanedOutput(from: stdoutPipe.fileHandleForReading.readDataToEndOfFile())

                    if
                        process.terminationStatus == 0,
                        let data = try? Data(contentsOf: outputFile),
                        let response = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                        !response.isEmpty
                    {
                        continuation.resume(returning: .success(response))
                        return
                    }

                    let failureMessage: String
                    if process.terminationStatus != 0 {
                        failureMessage = stderr.isEmpty ? (stdout.isEmpty ? "Codex exited with status \(process.terminationStatus)." : stdout) : stderr
                        continuation.resume(
                            returning: .failure(
                                CodexRunFailure(
                                    message: failureMessage,
                                    exitCode: process.terminationStatus
                                )
                            )
                        )
                        return
                    }

                    if !stderr.isEmpty {
                        failureMessage = "Timed AI returned an empty response. \(stderr)"
                    } else if !stdout.isEmpty {
                        failureMessage = "Timed AI returned an empty response. \(stdout)"
                    } else {
                        failureMessage = "Timed AI returned an empty response."
                    }

                    continuation.resume(
                        returning: .failure(
                            CodexRunFailure(
                                message: failureMessage,
                                exitCode: process.terminationStatus
                            )
                        )
                    )
                } catch {
                    continuation.resume(
                        returning: .failure(
                            CodexRunFailure(
                                message: error.localizedDescription,
                                exitCode: nil
                            )
                        )
                    )
                }
            }
        }
    }

    private static func cleanedOutput(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func userFacingErrorMessage(for failure: CodexRunFailure) -> String {
        let trimmed = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if let exitCode = failure.exitCode {
                return "Codex failed with exit code \(exitCode)."
            }
            return "Timed AI failed before returning a response."
        }

        if let exitCode = failure.exitCode, !trimmed.localizedCaseInsensitiveContains("exit") {
            return "\(trimmed) (exit \(exitCode))"
        }

        return trimmed
    }

    static func response(from result: CodexRunResult) -> String? {
        switch result {
        case let .success(response):
            return response
        case .failure:
            return nil
        }
    }

    static func failure(from result: CodexRunResult) -> CodexRunFailure? {
        switch result {
        case .success:
            return nil
        case let .failure(failure):
            return failure
        }
    }

    static func handleFailureMessage(_ result: CodexRunResult) -> String? {
        guard let failure = failure(from: result) else { return nil }
        return userFacingErrorMessage(for: failure)
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
