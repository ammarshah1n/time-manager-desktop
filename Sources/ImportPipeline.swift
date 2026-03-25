import Foundation

enum ImportPipeline {
    static func parseImport(
        title: String,
        source: ImportSource,
        text: String,
        now: Date,
        existingTaskIDs: Set<String>
    ) -> ImportBatch {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferredSubject = SubjectCatalog.matchingSubject(in: trimmed) ?? ""
        let contextTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(source.rawValue) import" : title
        let context = ContextItem(
            id: StableID.makeContextID(source: source, title: contextTitle, createdAt: now),
            title: contextTitle,
            kind: source.rawValue,
            subject: inferredSubject.isEmpty ? "Unassigned" : inferredSubject,
            summary: summaryLine(from: trimmed),
            detail: trimmed,
            createdAt: now
        )

        let parseResult: ([ImportTaskDraft], [String]) = switch source {
        case .seqta:
            parseSeqtaTasks(text: trimmed, now: now, existingTaskIDs: existingTaskIDs)
        case .tickTick:
            parseTickTickTasks(text: trimmed, now: now, existingTaskIDs: existingTaskIDs)
        case .transcript, .chat:
            ([], [])
        }

        return ImportBatch(context: context, taskDrafts: parseResult.0, messages: parseResult.1)
    }

    static func inferredSubject(from text: String) -> String? {
        SubjectCatalog.matchingSubject(in: text)
    }

    private static func parseSeqtaTasks(
        text: String,
        now: Date,
        existingTaskIDs: Set<String>
    ) -> ([ImportTaskDraft], [String]) {
        var knownIDs = existingTaskIDs
        var drafts: [ImportTaskDraft] = []
        var messages: [String] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let cleaned = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count > 4 else { continue }

            let parsed = parseSeqtaLine(cleaned, now: now)
            let stableID = StableID.makeTaskID(source: .seqta, title: parsed.title)
            if knownIDs.contains(stableID) {
                messages.append("duplicate skipped: \(parsed.title)")
                continue
            }

            knownIDs.insert(stableID)
            drafts.append(
                ImportTaskDraft(
                    originalID: stableID,
                    title: parsed.title,
                    list: "Seqta",
                    source: .seqta,
                    subject: parsed.subject ?? "",
                    estimateMinutes: 45,
                    confidence: 3,
                    importance: 3,
                    dueDate: parsed.dueDate ?? Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now,
                    notes: "Imported from Seqta.",
                    energy: .medium
                )
            )
        }

        if drafts.isEmpty && messages.isEmpty {
            messages.append("No Seqta tasks were parsed from the pasted text.")
        }

        return (drafts, messages)
    }

    private static func parseTickTickTasks(
        text: String,
        now: Date,
        existingTaskIDs: Set<String>
    ) -> ([ImportTaskDraft], [String]) {
        if looksLikeTickTickCSV(text: text) {
            return parseTickTickCSV(text: text, now: now, existingTaskIDs: existingTaskIDs)
        }

        var knownIDs = existingTaskIDs
        var drafts: [ImportTaskDraft] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let cleaned = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count > 2 else { continue }
            let stableID = StableID.makeTaskID(source: .tickTick, title: cleaned)
            guard !knownIDs.contains(stableID) else { continue }
            knownIDs.insert(stableID)

            drafts.append(
                ImportTaskDraft(
                    originalID: stableID,
                    title: cleaned,
                    list: "TickTick",
                    source: .tickTick,
                    subject: inferredSubject(from: cleaned) ?? "",
                    estimateMinutes: 30,
                    confidence: 3,
                    importance: 3,
                    dueDate: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now,
                    notes: "Imported from TickTick.",
                    energy: .medium
                )
            )
        }

        return (drafts, [])
    }

    private static func parseTickTickCSV(
        text: String,
        now: Date,
        existingTaskIDs: Set<String>
    ) -> ([ImportTaskDraft], [String]) {
        var knownIDs = existingTaskIDs
        var drafts: [ImportTaskDraft] = []
        var messages: [String] = []
        let rows = parseCSV(text: text)
        guard rows.count >= 2 else {
            return ([], ["TickTick CSV looked valid but had no task rows."])
        }

        for row in rows.dropFirst() {
            guard row.count >= 6 else { continue }
            let title = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let stableID = StableID.makeTaskID(source: .tickTick, title: title)
            if knownIDs.contains(stableID) {
                messages.append("duplicate skipped: \(title)")
                continue
            }

            knownIDs.insert(stableID)
            let tags = row[1]
            let note = row[2]
            let dueDate = parseTickTickDueDate(row[3], now: now) ?? Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            let priority = mapTickTickPriority(row[4])
            let status = row[5].lowercased()
            let isCompleted = status.contains("completed") || status.contains("done")

            drafts.append(
                ImportTaskDraft(
                    originalID: stableID,
                    title: title,
                    list: "TickTick",
                    source: .tickTick,
                    subject: inferredSubject(from: "\(title) \(tags) \(note)") ?? "",
                    estimateMinutes: 30,
                    confidence: 3,
                    importance: priority,
                    dueDate: dueDate,
                    notes: note,
                    energy: .medium
                )
            )

            if isCompleted {
                messages.append("completed task imported for review: \(title)")
            }
        }

        return (drafts, messages)
    }

    private static func parseSeqtaLine(_ line: String, now: Date) -> (title: String, dueDate: Date?, subject: String?) {
        let pattern = #"(?i)due\s+([^:]+):\s*(.+)$"#
        let range = NSRange(location: 0, length: (line as NSString).length)
        if
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: range),
            match.numberOfRanges == 3,
            let dueRange = Range(match.range(at: 1), in: line),
            let titleRange = Range(match.range(at: 2), in: line)
        {
            let duePhrase = String(line[dueRange])
            let title = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, parseDuePhrase(duePhrase, now: now), inferredSubject(from: title))
        }

        return (
            line
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            nil,
            inferredSubject(from: line)
        )
    }

    private static func parseDuePhrase(_ phrase: String, now: Date) -> Date? {
        let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current

        let weekdayMap: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ]

        if let weekday = weekdayMap[cleaned.lowercased()] {
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            components.weekday = weekday
            guard let startOfWeek = calendar.date(from: components) else { return nil }
            let candidate = calendar.date(byAdding: .day, value: 0, to: startOfWeek) ?? startOfWeek
            if candidate >= now {
                return candidate
            }
            return calendar.date(byAdding: .day, value: 7, to: candidate)
        }

        let monthDayFormats = ["d MMM yyyy", "d MMM", "d/M/yyyy", "d/M/yy", "d/M"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")

        for format in monthDayFormats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: cleaned) {
                if format == "d MMM" || format == "d/M" {
                    let components = calendar.dateComponents([.day, .month], from: parsed)
                    var yearComponents = calendar.dateComponents([.year], from: now)
                    yearComponents.day = components.day
                    yearComponents.month = components.month
                    if let currentYearDate = calendar.date(from: yearComponents) {
                        if currentYearDate >= now {
                            return currentYearDate
                        }
                        return calendar.date(byAdding: .year, value: 1, to: currentYearDate)
                    }
                }
                return parsed
            }
        }

        return nil
    }

    private static func parseTickTickDueDate(_ value: String, now: Date) -> Date? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        if let iso = formatter.date(from: cleaned) {
            return iso
        }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_AU")
        for format in ["yyyy-MM-dd", "d/M/yyyy", "d MMM yyyy", "d MMM"] {
            parser.dateFormat = format
            if let date = parser.date(from: cleaned) {
                if format == "d MMM" {
                    let calendar = Calendar.current
                    var components = calendar.dateComponents([.year], from: now)
                    let rawComponents = calendar.dateComponents([.day, .month], from: date)
                    components.day = rawComponents.day
                    components.month = rawComponents.month
                    return calendar.date(from: components)
                }
                return date
            }
        }

        return nil
    }

    private static func mapTickTickPriority(_ value: String) -> Int {
        switch Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 {
        case 2:
            return 5
        case 1:
            return 3
        default:
            return 1
        }
    }

    private static func looksLikeTickTickCSV(text: String) -> Bool {
        guard let firstLine = text.split(whereSeparator: \.isNewline).first else { return false }
        return firstLine.replacingOccurrences(of: "\"", with: "").lowercased() == "task name,tag,note,due date,priority,status"
    }

    private static func parseCSV(text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false

        for character in text {
            switch character {
            case "\"":
                insideQuotes.toggle()
            case "," where !insideQuotes:
                row.append(field)
                field = ""
            case "\n" where !insideQuotes:
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            case "\r":
                continue
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func summaryLine(from text: String) -> String {
        let sanitized = text.replacingOccurrences(of: "\n", with: " ")
        let firstSentence = sanitized.split(separator: ".").first.map(String.init) ?? sanitized
        return String(firstSentence.prefix(140))
    }
}
