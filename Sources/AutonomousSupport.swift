import Foundation

struct LocalFileHit: Hashable {
    let path: String
    let source: String
}

struct CodexMemoryHit: Hashable {
    let title: String
    let excerpt: String
    let source: String
}

struct TaskHint: Hashable {
    let title: String
    let subject: String
    let dueDate: Date?
    let notes: String
}

struct AutonomousContextBundle {
    let fileHits: [LocalFileHit]
    let memoryHits: [CodexMemoryHit]
    let taskHints: [TaskHint]
}

enum PromptIntent: Equatable {
    case planner
    case lookup
}

enum PromptIntentClassifier {
    static func classify(_ question: String) -> PromptIntent {
        let lowered = question.lowercased()
        let triggers = [
            "find", "where is", "search", "open", "pull", "onedrive", "sharepoint",
            "file", "folder", "document", "docx", "feedback", "codex mem", "memory",
            "did i already", "past work", "previous chat", "inside of codex"
        ]

        return triggers.contains(where: lowered.contains) ? .lookup : .planner
    }
}

enum SharePointPathResolver {
    static func resolve(rawText: String, oneDriveRoots: [String]) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        let matches = detector?.matches(in: rawText, options: [], range: range) ?? []

        for match in matches {
            guard
                let url = match.url,
                let host = url.host?.lowercased(),
                host.contains("sharepoint.com")
            else {
                continue
            }

            let pathComponents = url.pathComponents.compactMap { $0.removingPercentEncoding }
            guard let documentsIndex = pathComponents.firstIndex(of: "Documents") else { continue }
            let relativeComponents = Array(pathComponents[(documentsIndex + 1)...]).filter { !$0.isEmpty && $0 != "/" }
            guard !relativeComponents.isEmpty else { continue }

            let preferredRoot = preferredOneDriveRoot(for: host, roots: oneDriveRoots) ?? oneDriveRoots.first
            guard let preferredRoot else { continue }

            let candidate = relativeComponents.reduce(URL(fileURLWithPath: preferredRoot)) { partial, component in
                partial.appendingPathComponent(component, isDirectory: false)
            }

            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }

            return candidate.path
        }

        return nil
    }

    private static func preferredOneDriveRoot(for host: String, roots: [String]) -> String? {
        if host.contains("princealfredcollege") {
            return roots.first(where: { $0.lowercased().contains("princealfredcollege") })
        }
        if host.contains("pff") {
            return roots.first(where: { $0.lowercased().contains("pff") })
        }
        return roots.first
    }
}

enum LocalFileSearchProvider {
    static func search(question: String, limit: Int = 8) -> [LocalFileHit] {
        guard TimedPreferences.fileSearchEnabled else { return [] }

        var hits: [LocalFileHit] = []

        if let sharePointPath = SharePointPathResolver.resolve(
            rawText: question,
            oneDriveRoots: TimedPreferences.oneDriveRoots
        ) {
            hits.append(LocalFileHit(path: sharePointPath, source: "Resolved SharePoint/OneDrive link"))
        }

        let query = searchQuery(from: question)
        guard !query.isEmpty else { return Array(hits.prefix(limit)) }

        for root in TimedPreferences.codexAdditionalRoots {
            guard hits.count < limit else { break }
            let output = runProcess(
                executable: "/usr/bin/mdfind",
                arguments: ["-onlyin", root, query]
            )

            let newPaths = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for path in newPaths where hits.count < limit {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                if hits.contains(where: { $0.path == path }) { continue }
                hits.append(LocalFileHit(path: path, source: "Spotlight in \(root)"))
            }
        }

        return Array(hits.prefix(limit))
    }

    private static func searchQuery(from question: String) -> String {
        let cleaned = question
            .replacingOccurrences(of: "[^A-Za-z0-9 ._-]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let ignored = Set([
            "the", "and", "for", "from", "with", "this", "that", "have", "need",
            "also", "inside", "today", "please", "pull", "find", "search", "open",
            "file", "files", "feedback", "ticktick", "codex", "memory", "chat"
        ])

        let filtered = cleaned
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { $0.count >= 3 && !ignored.contains($0) }

        return Array(filtered.prefix(6)).joined(separator: " ")
    }
}

enum CodexMemorySearchProvider {
    static func search(question: String, limit: Int = 5) -> [CodexMemoryHit] {
        guard TimedPreferences.codexMemoryEnabled else { return [] }
        guard FileManager.default.fileExists(atPath: TimedPreferences.codexMemDBPath) else { return [] }

        let query = ftsQuery(from: question)
        guard !query.isEmpty else { return [] }

        let sql = """
        SELECT COALESCE(search_documents.title, ''), substr(search_documents.content, 1, 320), search_documents.doc_type
        FROM search_documents_fts
        JOIN search_documents ON search_documents_fts.rowid = search_documents.id
        WHERE search_documents_fts MATCH '\(query)'
        LIMIT \(limit);
        """

        let output = runProcess(
            executable: "/usr/bin/sqlite3",
            arguments: ["-separator", "||", TimedPreferences.codexMemDBPath, sql]
        )

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { line in
                let columns = line.components(separatedBy: "||")
                guard columns.count >= 3 else { return nil }
                return CodexMemoryHit(
                    title: columns[0].isEmpty ? "Untitled memory" : columns[0],
                    excerpt: columns[1].trimmingCharacters(in: .whitespacesAndNewlines),
                    source: columns[2]
                )
            }
    }

    private static func ftsQuery(from question: String) -> String {
        let tokens = question
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
            .filter { $0.count >= 3 }

        guard !tokens.isEmpty else { return "" }
        return Array(tokens.prefix(6)).map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}

enum TaskHintExtractor {
    static func extract(from question: String, now: Date) -> [TaskHint] {
        let lowered = question.lowercased()
        var hints: [TaskHint] = []

        let candidates: [(subject: String, title: String, trigger: String)] = [
            ("Economics", "Economics test", "economics"),
            ("Maths", "Maths investigation", "maths investigation"),
            ("English", "English poetry analysis", "english poetry")
        ]

        for candidate in candidates where lowered.contains(candidate.trigger) {
            hints.append(
                TaskHint(
                    title: candidate.title,
                    subject: candidate.subject,
                    dueDate: dueDate(from: lowered, subject: candidate.subject, now: now),
                    notes: "Captured from prompt."
                )
            )
        }

        return Array(Set(hints))
    }

    private static func dueDate(from lowered: String, subject: String, now: Date) -> Date? {
        let calendar = Calendar.current

        if subject == "Economics" || subject == "English", lowered.contains("friday") {
            return nextWeekday(6, from: now, calendar: calendar)
        }
        if subject == "Maths", lowered.contains("monday") {
            return nextWeekday(2, from: now, calendar: calendar)
        }
        return nil
    }

    private static func nextWeekday(_ weekday: Int, from now: Date, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.weekday = weekday
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
    }
}

enum TickTickAutonomousImport {
    static func recentRelevantTasks(now: Date) -> [TaskItem] {
        let directories = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        ]

        let csvFiles = directories.flatMap { recentCSVFiles(in: $0) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

        for file in csvFiles.prefix(5) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            guard text.contains("Task Name,Tag,Note,Due Date,Priority,Status") else { continue }

            let batch = ImportPipeline.parseImport(
                title: "TickTick import",
                source: .tickTick,
                text: text,
                now: now,
                existingTaskIDs: []
            )

            let relevant = batch.taskDrafts
                .filter { draft in
                    let dueDate = draft.dueDate
                    let isSoon = dueDate.timeIntervalSince(now) <= 10 * 24 * 60 * 60
                    let isSchoolSubject = SubjectCatalog.supported.contains(draft.resolvedSubject())
                    return isSoon || isSchoolSubject
                }
                .map { $0.makeTask() }

            if !relevant.isEmpty {
                return relevant
            }
        }

        return []
    }

    private static func recentCSVFiles(in directory: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.filter { $0.pathExtension.lowercased() == "csv" }
    }
}

enum AutonomousContextProvider {
    static func build(question: String, now: Date) -> AutonomousContextBundle {
        AutonomousContextBundle(
            fileHits: LocalFileSearchProvider.search(question: question),
            memoryHits: CodexMemorySearchProvider.search(question: question),
            taskHints: TaskHintExtractor.extract(from: question, now: now)
        )
    }
}

@discardableResult
private func runProcess(executable: String, arguments: [String]) -> String {
    let process = Process()
    let outputPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ""
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
