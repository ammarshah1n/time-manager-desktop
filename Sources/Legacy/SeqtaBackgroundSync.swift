import Foundation
import Darwin

enum SeqtaBootstrapResult: Equatable {
    case success
    case failure(String)
}

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

    static func ensureLaunchAgentInstalled() -> SeqtaBootstrapResult {
        guard FileManager.default.fileExists(atPath: transcriberPythonURL.path) else {
            return .failure("Timed couldn't find the Seqta Python runtime at \(transcriberPythonURL.path).")
        }
        guard FileManager.default.fileExists(atPath: transcriberCrawlerURL.path) else {
            return .failure("Timed couldn't find the Seqta crawler at \(transcriberCrawlerURL.path).")
        }

        let fileManager = FileManager.default
        let timedDirectory = snapshotURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: timedDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .failure("Timed couldn't prepare the Seqta sync folder. \(error.localizedDescription)")
        }

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

        do {
            try script.write(to: supportScriptURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Timed couldn't write the Seqta support script. \(error.localizedDescription)")
        }
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

        do {
            try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Timed couldn't write the Seqta launch agent. \(error.localizedDescription)")
        }

        let domain = "gui/\(getuid())"
        _ = runLaunchctl(arguments: ["bootout", domain, launchAgentURL.path])
        let bootstrapStatus = runLaunchctl(arguments: ["bootstrap", domain, launchAgentURL.path])
        guard bootstrapStatus == 0 else {
            return .failure("Timed couldn't bootstrap the Seqta launch agent. launchctl exited with \(bootstrapStatus).")
        }

        let enableStatus = runLaunchctl(arguments: ["enable", "\(domain)/\(launchAgentLabel)"])
        guard enableStatus == 0 else {
            return .failure("Timed couldn't enable the Seqta launch agent. launchctl exited with \(enableStatus).")
        }

        let kickstartStatus = runLaunchctl(arguments: ["kickstart", "-k", "\(domain)/\(launchAgentLabel)"])
        guard kickstartStatus == 0 else {
            return .failure("Timed couldn't start the Seqta launch agent. launchctl exited with \(kickstartStatus).")
        }

        return .success
    }

    static func loadTasks(now: Date = .now, snapshotURL: URL = snapshotURL) -> [TaskItem] {
        guard
            let raw = loadSnapshot(snapshotURL: snapshotURL),
            let assessments = raw["assessments"] as? [[String: Any]]
        else {
            return []
        }

        return assessments.compactMap { assessment in
            guard let title = stringValue(assessment["title"]) else { return nil }
            let rawSubject = stringValue(assessment["subject"]) ?? "General"
            let subject = canonicalSubject(from: rawSubject)
            let remoteID = stringValue(assessment["id"])
            let dueDate = parseDueDate(stringValue(assessment["due"]), now: now)
            let status = stringValue(assessment["status"]) ?? "UNKNOWN"
            let overdue = boolValue(assessment["overdue"])
            let hasFeedback = boolValue(assessment["hasFeedback"])

            return TaskItem(
                id: StableID.makeSeqtaTaskID(remoteID: remoteID, title: title, subject: subject),
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

    static func loadGrades(now: Date = .now, snapshotURL: URL = snapshotURL) -> [GradeEntry] {
        guard let raw = loadSnapshot(snapshotURL: snapshotURL) else { return [] }

        let crawledAt = parseSnapshotTimestamp(raw["crawled_at"]) ?? now
        var gradeEntries: [GradeEntry] = []
        var seenEntryIDs: Set<String> = []
        collectGradeEntries(
            from: raw,
            currentSubject: nil,
            currentDate: crawledAt,
            fallbackNow: now,
            collected: &gradeEntries,
            seenEntryIDs: &seenEntryIDs
        )
        return gradeEntries.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.subject.caseInsensitiveCompare(rhs.subject) != .orderedSame {
                return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
            return lhs.assessmentTitle.localizedCaseInsensitiveCompare(rhs.assessmentTitle) == .orderedAscending
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

    static func canonicalSubject(from rawSubject: String) -> String {
        let trimmed = rawSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        return SubjectCatalog.matchingSubject(in: trimmed) ?? trimmed
    }

    static func parseDueDate(_ rawValue: String?, now: Date) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let cleaned = cleanedDueString(rawValue)
        guard !cleaned.isEmpty else { return nil }

        if let relativeDate = relativeDueDate(cleaned, now: now) {
            return endOfDay(relativeDate)
        }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.timeZone = calendar.timeZone

        for format in ["yyyy-MM-dd", "d MMMM yyyy", "d MMM yyyy", "d/MM/yyyy", "d/M/yyyy", "d/M/yy"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: cleaned) {
                return endOfDay(parsed)
            }
        }

        if let parsedWithoutYear = parseDayMonthDate(cleaned, now: now, formatter: formatter, calendar: calendar) {
            return endOfDay(parsedWithoutYear)
        }

        return nil
    }

    private static func cleanedDueString(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: #"(?i)^\s*due\s*[:\-]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func relativeDueDate(_ cleaned: String, now: Date) -> Date? {
        let normalized = cleaned.lowercased()
        let calendar = Calendar.current

        if normalized == "today" {
            return now
        }

        if normalized == "tomorrow" {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }

        let weekdayMap: [String: Int] = [
            "sunday": 1,
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7
        ]

        guard let weekday = weekdayMap[normalized] else { return nil }

        let startOfDay = calendar.startOfDay(for: now)
        return calendar.nextDate(
            after: startOfDay.addingTimeInterval(-1),
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTimePreservingSmallerComponents
        )
    }

    private static func parseDayMonthDate(
        _ cleaned: String,
        now: Date,
        formatter: DateFormatter,
        calendar: Calendar
    ) -> Date? {
        for format in ["EEE d MMM", "EEEE d MMM", "d MMM"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: cleaned) else { continue }

            let components = calendar.dateComponents([.day, .month], from: parsed)
            var yearComponents = calendar.dateComponents([.year], from: now)
            yearComponents.day = components.day
            yearComponents.month = components.month

            guard let currentYearDate = calendar.date(from: yearComponents) else { continue }
            if currentYearDate >= calendar.startOfDay(for: now) {
                return currentYearDate
            }

            return calendar.date(byAdding: .year, value: 1, to: currentYearDate)
        }

        return nil
    }

    private static func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(
            bySettingHour: 17,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func loadSnapshot(snapshotURL: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: snapshotURL),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return raw
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return (string as NSString).boolValue }
        return false
    }

    private static func collectGradeEntries(
        from value: Any,
        currentSubject: String?,
        currentDate: Date,
        fallbackNow: Date,
        collected: inout [GradeEntry],
        seenEntryIDs: inout Set<String>
    ) {
        if let dictionary = value as? [String: Any] {
            let nextSubject = explicitSubject(from: dictionary) ?? currentSubject
            let nextDate = explicitDate(from: dictionary) ?? currentDate
            for child in dictionary.values {
                collectGradeEntries(
                    from: child,
                    currentSubject: nextSubject,
                    currentDate: nextDate,
                    fallbackNow: fallbackNow,
                    collected: &collected,
                    seenEntryIDs: &seenEntryIDs
                )
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collectGradeEntries(
                    from: child,
                    currentSubject: currentSubject,
                    currentDate: currentDate,
                    fallbackNow: fallbackNow,
                    collected: &collected,
                    seenEntryIDs: &seenEntryIDs
                )
            }
            return
        }

        guard let string = value as? String else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let nestedJSON = nestedJSONObject(from: trimmed) {
            collectGradeEntries(
                from: nestedJSON,
                currentSubject: currentSubject,
                currentDate: currentDate,
                fallbackNow: fallbackNow,
                collected: &collected,
                seenEntryIDs: &seenEntryIDs
            )
        }

        guard trimmed.range(of: "<tr", options: [.caseInsensitive, .regularExpression]) != nil else { return }
        let parsedEntries = parseGradeRows(
            fromHTML: trimmed,
            currentSubject: currentSubject,
            currentDate: currentDate,
            fallbackNow: fallbackNow
        )
        for entry in parsedEntries where seenEntryIDs.insert(entry.id).inserted {
            collected.append(entry)
        }
    }

    private static func explicitSubject(from dictionary: [String: Any]) -> String? {
        if let directSubject = stringValue(dictionary["subject"]) {
            return canonicalSubject(from: directSubject)
        }

        if let nestedSubject = dictionary["subject"] as? [String: Any] {
            for key in ["description", "title", "code"] {
                if let value = stringValue(nestedSubject[key]), let matched = SubjectCatalog.matchingSubject(in: value) {
                    return matched
                }
            }
        }

        return nil
    }

    private static func explicitDate(from dictionary: [String: Any]) -> Date? {
        for key in ["date", "createdAt", "created_date", "updatedAt", "updated", "crawled_at"] {
            if let parsed = parseSnapshotTimestamp(dictionary[key]) {
                return parsed
            }
        }
        return nil
    }

    private static func nestedJSONObject(from string: String) -> Any? {
        guard string.first == "{" || string.first == "[" else { return nil }
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func parseGradeRows(
        fromHTML html: String,
        currentSubject: String?,
        currentDate: Date,
        fallbackNow: Date
    ) -> [GradeEntry] {
        guard let rowRegex = try? NSRegularExpression(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#) else {
            return []
        }
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let rows = rowRegex.matches(in: html, options: [], range: htmlRange)

        return rows.compactMap { rowMatch in
            guard let rowRange = Range(rowMatch.range(at: 1), in: html) else { return nil }
            let rowHTML = String(html[rowRange])
            let cells = htmlTableCells(from: rowHTML)
            guard !cells.isEmpty else { return nil }

            let joinedCells = cells.joined(separator: " | ")
            guard let score = parseScore(from: joinedCells) else { return nil }
            guard let assessmentTitle = assessmentTitle(from: cells, excludingScoreText: score.rawText) else { return nil }

            let subject = inferredSubject(from: cells, fallback: currentSubject)
            guard let subject else { return nil }

            let gradeDate = parseGradeDate(from: cells, fallback: currentDate) ?? fallbackNow

            return GradeEntry(
                subject: subject,
                assessmentTitle: assessmentTitle,
                mark: score.mark,
                outOf: score.outOf,
                date: gradeDate
            )
        }
    }

    private static func htmlTableCells(from rowHTML: String) -> [String] {
        guard let cellRegex = try? NSRegularExpression(pattern: #"(?is)<t[dh]\b[^>]*>(.*?)</t[dh]>"#) else {
            return []
        }
        let rowRange = NSRange(rowHTML.startIndex..<rowHTML.endIndex, in: rowHTML)
        return cellRegex.matches(in: rowHTML, options: [], range: rowRange).compactMap { match in
            guard let cellRange = Range(match.range(at: 1), in: rowHTML) else { return nil }
            let fragment = String(rowHTML[cellRange])
            let plainText = plainText(fromHTML: fragment)
            return plainText.isEmpty ? nil : plainText
        }
    }

    private static func plainText(fromHTML html: String) -> String {
        let breakNormalized = html.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        let stripped = breakNormalized.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return decoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ParsedScore {
        let mark: Int
        let outOf: Int
        let rawText: String
    }

    private static func parseScore(from text: String) -> ParsedScore? {
        if
            let ratioRegex = try? NSRegularExpression(pattern: #"\b(\d{1,3}(?:\.\d+)?)\s*/\s*(\d{1,3}(?:\.\d+)?)\b"#),
            let ratioMatch = ratioRegex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
            let markString = substring(in: text, nsRange: ratioMatch.range(at: 1)),
            let outOfString = substring(in: text, nsRange: ratioMatch.range(at: 2)),
            let rawText = substring(in: text, nsRange: ratioMatch.range(at: 0)),
            let mark = roundedInteger(from: markString),
            let outOf = roundedInteger(from: outOfString)
        {
            return ParsedScore(mark: mark, outOf: max(1, outOf), rawText: rawText)
        }

        if
            let percentageRegex = try? NSRegularExpression(pattern: #"\b(\d{1,3}(?:\.\d+)?)\s*%"#),
            let percentageMatch = percentageRegex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
            let markString = substring(in: text, nsRange: percentageMatch.range(at: 1)),
            let rawText = substring(in: text, nsRange: percentageMatch.range(at: 0)),
            let mark = roundedInteger(from: markString)
        {
            return ParsedScore(mark: mark, outOf: 100, rawText: rawText)
        }

        return nil
    }

    private static func roundedInteger(from string: String) -> Int? {
        guard let value = Double(string) else { return nil }
        return Int(value.rounded())
    }

    private static func substring(in text: String, nsRange: NSRange) -> String? {
        guard let range = Range(nsRange, in: text) else { return nil }
        return String(text[range])
    }

    private static func assessmentTitle(from cells: [String], excludingScoreText scoreText: String) -> String? {
        let filtered = cells.filter { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            guard parseScore(from: trimmed) == nil else { return false }
            guard parseGradeDate(from: [trimmed], fallback: nil) == nil else { return false }

            let lowered = trimmed.lowercased()
            let headerWords = ["mark", "marks", "grade", "result", "score", "date", "weight", "subject"]
            return !headerWords.contains(lowered) && trimmed != scoreText
        }
        return filtered.first
    }

    private static func inferredSubject(from cells: [String], fallback: String?) -> String? {
        for cell in cells {
            if let matched = SubjectCatalog.matchingSubject(in: cell) {
                return matched
            }
        }
        if let fallback {
            let canonical = canonicalSubject(from: fallback)
            return canonical.isEmpty ? nil : canonical
        }
        return nil
    }

    private static func parseGradeDate(from cells: [String], fallback: Date?) -> Date? {
        for cell in cells {
            if let parsed = parseSnapshotTimestamp(cell) ?? parseHumanDate(cell) {
                return parsed
            }
        }
        return fallback
    }

    private static func parseSnapshotTimestamp(_ value: Any?) -> Date? {
        guard let string = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            if let number = value as? NSNumber {
                let seconds = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000.0 : number.doubleValue
                return Date(timeIntervalSince1970: seconds)
            }
            return nil
        }

        if let timestamp = Double(string), timestamp > 0 {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000.0 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }

        let fallbackISOFormatter = ISO8601DateFormatter()
        if let parsed = fallbackISOFormatter.date(from: string) {
            return parsed
        }

        return parseHumanDate(string)
    }

    private static func parseHumanDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.timeZone = Calendar.current.timeZone

        for format in ["d MMM yyyy", "dd MMM yyyy", "d MMMM yyyy", "dd MMMM yyyy", "d/M/yyyy", "dd/MM/yyyy", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) {
                return parsed
            }
        }

        return nil
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
