// TimedDesignGuardTests.swift — Timed
// Static ratchet for the Timed design system. The source of truth is
// docs/UI-RULES.md, DESIGN.md, and .agents/skills/timed-design/.

import Foundation
import Testing

@Suite("Timed Design Guard")
struct TimedDesignGuardTests {
    private let baselineSHA = "c38c42595a6a2697294ed720716e0bb05ce8f93c"

    private let guardedRoots = [
        "Sources/TimedKit/Features",
        "Sources/TimedKit/AppEntry",
    ]

    private let cleanupTargets: Set<String> = [
        "Sources/TimedKit/Features/Briefing/MorningBriefingPane.swift",
        "Sources/TimedKit/Features/Prefs/PrefsPane.swift",
        "Sources/TimedKit/Features/Tasks/TaskDetailSheet.swift",
        "Sources/TimedKit/Features/Tasks/TasksPane.swift",
        "Sources/TimedKit/Features/TimedRootView.swift",
        "Sources/TimedKit/Features/DishMeUp/DishMeUpHomeView.swift",
        "Sources/TimedKit/Features/MorningInterview/MorningInterviewPane.swift",
        "Sources/TimedKit/Features/Triage/TriagePane.swift",
        "Sources/TimedKit/Features/Waiting/WaitingPane.swift",
    ]

    private let bans: [Ban] = [
        Ban(name: "raw .font(.system(size:)", pattern: #"\\.font\\(\\.system\\(size:"#),
        Ban(name: "raw semantic feature font", pattern: #"\\.font\\(\\.(caption|caption2|footnote|subheadline|callout|body|headline|title|title2|title3|largeTitle)\\)"#),
        Ban(name: "raw secondary foreground", pattern: #"\\.foreground(Style|Color)\\(\\.secondary\\)"#),
        Ban(name: "raw SwiftUI semantic colour", pattern: #"Color\\.(red|orange|green|teal|yellow|purple|pink|mint|cyan|indigo|brown)\\b"#),
        Ban(name: "SwiftUI gradient", pattern: #"(LinearGradient|RadialGradient|AngularGradient|MeshGradient)"#),
        Ban(name: "decorative AI icon", pattern: #"Image\\(systemName:\\s*\"(sparkles|wand\\.and\\.stars|bolt\\.fill)\""#),
        Ban(name: "raw numeric padding", pattern: #"\\.padding\\([^)]*\\b[0-9]+(\\.[0-9]+)?\\b"#),
        Ban(name: "raw numeric corner radius", pattern: #"\\.cornerRadius\\([^)]*\\b[0-9]+(\\.[0-9]+)?\\b"#),
        Ban(name: "raw fixed frame dimension", pattern: #"\\.frame\\([^)]*(width|height):\\s*[0-9]+(\\.[0-9]+)?\\b"#),
        Ban(name: "coloured warning foreground", pattern: #"\\.foregroundStyle\\(\\.(orange|red|yellow)\\)"#),
        Ban(name: "small control size", pattern: #"\\.controlSize\\(\\.small\\)"#),
    ]

    @Test func modifiedSwiftUIFilesRespectDesignRatchet() throws {
        let repoRoot = repoRoot()
        let modifiedFiles = try modifiedSwiftUIFiles(repoRoot: repoRoot)
        var failures: [String] = []

        for relativePath in modifiedFiles {
            let current = try read(relativePath, repoRoot: repoRoot)
            let currentViolations = violations(in: current, relativePath: relativePath)

            if cleanupTargets.contains(relativePath) {
                let baseline = try baselineContents(relativePath, repoRoot: repoRoot)
                let baselineCount = baseline.map { violations(in: $0, relativePath: relativePath).count } ?? 0
                if currentViolations.count > baselineCount {
                    failures.append("\(relativePath) added design violations: \(currentViolations.count) current vs \(baselineCount) at \(baselineSHA).")
                    failures.append(contentsOf: currentViolations.prefix(12).map { "  \($0)" })
                }
                continue
            }

            failures.append(contentsOf: currentViolations)
        }

        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
    }

    private func modifiedSwiftUIFiles(repoRoot: URL) throws -> [String] {
        var files = Set<String>()
        let diffFiles = try git(["diff", "--name-only", baselineSHA, "--"] + guardedRoots, repoRoot: repoRoot)
        let untrackedFiles = try git(["ls-files", "--others", "--exclude-standard", "--"] + guardedRoots, repoRoot: repoRoot)

        for path in (diffFiles + untrackedFiles) where path.hasSuffix(".swift") {
            files.insert(path)
        }

        return files.sorted()
    }

    private func violations(in contents: String, relativePath: String) -> [String] {
        var failures: [String] = []
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            let text = String(line)
            for ban in bans where text.range(of: ban.pattern, options: .regularExpression) != nil {
                if relativePath.hasPrefix("Sources/Legacy/") { continue }
                if relativePath == "Sources/TimedKit/Core/Design/Components/BucketDot.swift" { continue }
                failures.append("\(relativePath):\(index + 1) \(ban.name): \(text.trimmingCharacters(in: .whitespaces))")
            }
        }

        if contents.contains("#Preview") && contents.contains(".preferredColorScheme(.dark)") == false {
            failures.append("\(relativePath): preview coverage: new SwiftUI previews must include a dark `.preferredColorScheme(.dark)` preview.")
        }

        return failures
    }

    private func baselineContents(_ relativePath: String, repoRoot: URL) throws -> String? {
        try? git(["show", "\(baselineSHA):\(relativePath)"], repoRoot: repoRoot).joined(separator: "\n")
    }

    private func read(_ relativePath: String, repoRoot: URL) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func git(_ arguments: [String], repoRoot: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repoRoot

        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("timed-design-guard-\(UUID().uuidString).out")
        let errorURL = tempDirectory.appendingPathComponent("timed-design-guard-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()
        process.waitUntilExit()

        let data = try Data(contentsOf: outputURL)
        if process.terminationStatus != 0 {
            let errorData = try Data(contentsOf: errorURL)
            let message = String(data: errorData, encoding: .utf8) ?? "git failed"
            throw NSError(domain: "TimedDesignGuardTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private struct Ban {
    let name: String
    let pattern: String
}
