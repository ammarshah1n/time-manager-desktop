import Foundation
import Darwin

enum SeqtaBackgroundSync {
    static let launchAgentLabel = "au.facilitated.timed.seqta-sync"
    static let snapshotURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Timed/seqta-latest.json")
    static let launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    static let supportScriptURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Timed/seqta-sync.sh")
    static let transcriberPythonURL = URL(fileURLWithPath: "/Users/ammarshahin/Transcriber/.venv/bin/python")
    static let transcriberCrawlerURL = URL(fileURLWithPath: "/Users/ammarshahin/Transcriber/seqta_crawl.py")

    static func ensureLaunchAgentInstalled() {
        guard FileManager.default.fileExists(atPath: transcriberPythonURL.path) else { return }
        guard FileManager.default.fileExists(atPath: transcriberCrawlerURL.path) else { return }

        let fileManager = FileManager.default
        let timedDirectory = snapshotURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: timedDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let script = """
        #!/bin/zsh
        set -euo pipefail
        APP_SUPPORT="$HOME/Library/Application Support/Timed"
        mkdir -p "$APP_SUPPORT"
        TMP_OUTPUT="$(mktemp)"
        "\(transcriberPythonURL.path)" "\(transcriberCrawlerURL.path)" --mode local --skip-file-downloads > "$TMP_OUTPUT"
        OUTPUT_PATH=$(/usr/bin/python3 - "$TMP_OUTPUT" <<'PY'
        import json
        import pathlib
        import sys

        payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
        print(payload["output_path"])
        PY
        )
        /bin/cp "$OUTPUT_PATH" "$APP_SUPPORT/seqta-latest.json"
        /bin/rm -f "$TMP_OUTPUT"
        """

        try? script.write(to: supportScriptURL, atomically: true, encoding: .utf8)
        chmod(supportScriptURL.path, 0o755)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/zsh</string>
                <string>\(supportScriptURL.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>14400</integer>
            <key>StandardOutPath</key>
            <string>\(timedDirectory.appendingPathComponent("seqta-sync.out.log").path)</string>
            <key>StandardErrorPath</key>
            <string>\(timedDirectory.appendingPathComponent("seqta-sync.err.log").path)</string>
        </dict>
        </plist>
        """

        try? plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)

        let domain = "gui/\(getuid())"
        _ = runLaunchctl(arguments: ["bootout", domain, launchAgentURL.path])
        _ = runLaunchctl(arguments: ["bootstrap", domain, launchAgentURL.path])
        _ = runLaunchctl(arguments: ["enable", "\(domain)/\(launchAgentLabel)"])
        _ = runLaunchctl(arguments: ["kickstart", "-k", "\(domain)/\(launchAgentLabel)"])
    }

    static func loadTasks(now: Date = .now, snapshotURL: URL = snapshotURL) -> [TaskItem] {
        guard
            let data = try? Data(contentsOf: snapshotURL),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let assessments = raw["assessments"] as? [[String: Any]]
        else {
            return []
        }

        return assessments.compactMap { assessment in
            guard let title = stringValue(assessment["title"]) else { return nil }
            let rawSubject = stringValue(assessment["subject"]) ?? "General"
            let subject = normalizedSubject(rawSubject)
            let assessmentID = stringValue(assessment["id"]) ?? title
            let dueDate = parseDueDate(stringValue(assessment["due"]), now: now)
            let status = stringValue(assessment["status"]) ?? "UNKNOWN"
            let overdue = boolValue(assessment["overdue"])
            let hasFeedback = boolValue(assessment["hasFeedback"])

            return TaskItem(
                id: StableID.makeTaskID(source: .seqta, title: "\(assessmentID)-\(title)"),
                title: title,
                list: "Seqta",
                source: .seqta,
                subject: subject,
                estimateMinutes: subject == "Maths" ? 90 : 45,
                confidence: 3,
                importance: overdue ? 5 : 4,
                dueDate: dueDate,
                notes: buildNotes(subject: rawSubject, status: status, hasFeedback: hasFeedback, overdue: overdue),
                energy: subject == "Maths" ? .high : .medium,
                isCompleted: false,
                completedAt: nil
            )
        }
    }

    private static func buildNotes(subject: String, status: String, hasFeedback: Bool, overdue: Bool) -> String {
        var parts = ["Imported from Seqta background sync.", "Subject: \(subject)", "Status: \(status)"]
        if hasFeedback {
            parts.append("Feedback is available.")
        }
        if overdue {
            parts.append("This item is overdue.")
        }
        return parts.joined(separator: " ")
    }

    private static func normalizedSubject(_ rawSubject: String) -> String {
        let lowered = rawSubject.lowercased()

        if lowered.contains("english") { return "English" }
        if lowered.contains("math") { return "Maths" }
        if lowered.contains("economic") { return "Economics" }
        if lowered.contains("chem") { return "Chemistry" }
        if lowered.contains("physics") { return "Physics" }
        if lowered.contains("biology") { return "Biology" }
        if lowered.contains("legal") { return "Legal Studies" }
        if lowered.contains("history") { return "Modern History" }
        if lowered.contains("geography") { return "Geography" }
        if lowered.contains("physical") || lowered == "pe" { return "PE" }

        return SubjectCatalog.matchingSubject(in: rawSubject) ?? rawSubject
    }

    private static func parseDueDate(_ rawValue: String?, now: Date) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let parsed = formatter.date(from: rawValue) else { return nil }
        return Calendar.current.date(
            bySettingHour: 17,
            minute: 0,
            second: 0,
            of: parsed
        ) ?? parsed
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return (string as NSString).boolValue }
        return false
    }

    private static func runLaunchctl(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

final class SeqtaFileWatcher {
    private let fileDescriptor: Int32
    private let source: DispatchSourceFileSystemObject

    init?(snapshotURL: URL = SeqtaBackgroundSync.snapshotURL, onChange: @escaping @Sendable () -> Void) {
        let directoryURL = snapshotURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        fileDescriptor = descriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: DispatchQueue(label: "timed.seqta.file-watcher")
        )

        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
