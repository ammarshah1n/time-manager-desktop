import Foundation

struct SchoolContextPack {
    let tasks: [TaskItem]
    let contexts: [ContextItem]
    let preferredTaskID: String?
    let preferredContextID: String?
    let message: String
    let focusSubject: String?
}

struct DiscoveredDeadline: Equatable, Sendable {
    let title: String
    let subject: String
    let importance: Int
    let dueDate: Date?
    let estimateMinutes: Int
    let energy: TaskEnergy
    let query: String
    let notes: String
    let matchedMemoryTitles: [String]

    func makeTask() -> TaskItem {
        TaskItem(
            id: StableID.makeTaskID(source: .codexMem, title: title),
            title: title,
            list: "codex-mem",
            source: .codexMem,
            subject: subject,
            estimateMinutes: estimateMinutes,
            confidence: 3,
            importance: importance,
            dueDate: dueDate,
            notes: notes,
            energy: energy,
            isCompleted: false,
            completedAt: nil,
            isAutoDiscovered: true
        )
    }
}

struct DiscoveredMemoryHit: Equatable, Sendable {
    let source: String
    let title: String
    let snippet: String
}

enum CodexMemorySchoolPack {
    typealias DiscoverySearchProvider = @Sendable (_ query: String, _ limit: Int) -> [DiscoveredMemoryHit]

    static func load(
        now: Date = .now,
        homeDirectory: String = NSHomeDirectory(),
        codexMemDBPath: String = TimedPreferences.codexMemDBPath,
        fileManager: FileManager = .default
    ) -> SchoolContextPack {
        let calendar = Calendar.current
        let studyPlanURL = URL(fileURLWithPath: homeDirectory).appendingPathComponent("study-plan.html")
        let mathsMapURL = URL(fileURLWithPath: homeDirectory).appendingPathComponent("output/doc/maths-investigation-feedback.html")
        let dbExists = fileManager.fileExists(atPath: codexMemDBPath)

        let mathsTask = makeTask(
            title: "Maths investigation cleanup",
            subject: "Maths",
            estimateMinutes: 180,
            confidence: 2,
            importance: 5,
            dueDate: nextWeekday(4, hour: 9, minute: 0, from: now, calendar: calendar),
            notes: "Maths is due Wednesday. Apply teacher feedback across intro, calculations, subtraction logic, dimensions, limitations, and conclusion.",
            energy: .high
        )

        let englishTask = makeTask(
            title: "English comparative revision for Friday",
            subject: "English",
            estimateMinutes: 150,
            confidence: 3,
            importance: 5,
            dueDate: nextWeekday(6, hour: 9, minute: 0, from: now, calendar: calendar),
            notes: "Build phrase bank, concept framing, comparative paragraph fluency, then convert it into a poem-specific answer after class.",
            energy: .high
        )

        let economicsTask = makeTask(
            title: "Economics revision and formative follow-up",
            subject: "Economics",
            estimateMinutes: 120,
            confidence: 3,
            importance: 5,
            dueDate: nextWeekday(6, hour: 15, minute: 30, from: now, calendar: calendar),
            notes: "Keep workbook-only practice active: surplus, MB = MC, PED, PES, graph interpretation, and timed sets.",
            energy: .high
        )

        var contexts: [ContextItem] = []

        if dbExists {
            contexts.append(contentsOf: memoryContexts(
                subject: "Maths",
                keywords: ["maths", "mathematics", "investigation", "measurement"],
                kind: "Feedback",
                limit: 2,
                dbPath: codexMemDBPath,
                createdAt: now
            ))
            contexts.append(contentsOf: memoryContexts(
                subject: "English",
                keywords: ["english", "poetry", "comparative", "literary"],
                kind: "Feedback",
                limit: 2,
                dbPath: codexMemDBPath,
                createdAt: calendar.date(byAdding: .minute, value: -4, to: now) ?? now
            ))
            contexts.append(contentsOf: memoryContexts(
                subject: "Economics",
                keywords: ["economics", "elasticity", "ped", "pes", "surplus", "microeconomics"],
                kind: "Feedback",
                limit: 3,
                dbPath: codexMemDBPath,
                createdAt: calendar.date(byAdding: .minute, value: -8, to: now) ?? now
            ))
        }

        if fileManager.fileExists(atPath: mathsMapURL.path) {
            contexts.append(
                makeContext(
                    title: "Maths investigation planner + HTML feedback map",
                    kind: "Reference",
                    subject: "Maths",
                    summary: "The HTML feedback map is the quickest working reference because it maps each feedback point to the exact section and insert-ready fix.",
                    detail: """
                    Useful file: \(mathsMapURL.path)

                    Use the HTML map when rewriting:
                    - introduction and design justification
                    - linking sentences before calculations
                    - subtraction and exposed-surface logic
                    - dimensions on diagrams
                    - limitations and conclusion cleanup
                    """,
                    createdAt: calendar.date(byAdding: .hour, value: -12, to: now) ?? now
                )
            )
        }

        if fileManager.fileExists(atPath: studyPlanURL.path) {
            contexts.append(
                makeContext(
                    title: "English revision for Friday — conversion plan",
                    kind: "Plan",
                    subject: "English",
                    summary: "English stays generic until Thursday: phrase bank, concept framing, comparative paragraph fluency, then poem-specific synthesis Thursday night.",
                    detail: """
                    Source: \(studyPlanURL.path)

                    Key takeaways:
                    - Build a phrase bank of 10-12 analytical stems.
                    - Train comparative paragraph fluency, not just quote memorisation.
                    - Use thesis, topic sentence, quote integration, effect sentence, and final link.
                    - After class on Thursday: annotate the given poem, lock three comparison points, build one thesis, and write timed body paragraphs.
                    """,
                    createdAt: calendar.date(byAdding: .minute, value: -10, to: now) ?? now
                )
            )

            contexts.append(
                makeContext(
                    title: "Economics revision — workbook boundaries",
                    kind: "Plan",
                    subject: "Economics",
                    summary: "Economics should stay workbook-only: consumer surplus, producer surplus, social surplus, MB = MC, PED, PES, graphing, timed sets, and an error sheet.",
                    detail: """
                    Source: \(studyPlanURL.path)

                    Keep active:
                    - repeated retrieval instead of a late cram
                    - Topic 2 workbook and practice sheets only
                    - clean graphs plus written interpretation
                    - a running error sheet for graph interpretation, social surplus, and elasticity reasoning
                    """,
                    createdAt: calendar.date(byAdding: .minute, value: -15, to: now) ?? now
                )
            )
        }

        let economicsTranscriptPaths = [
            "Documents/Obsidian Vault/03 School/Transcripts/Economics/Consumer and Producer Surplus/2026-03-25 — Calculating Consumer and Producer Surplus.md",
            "Documents/Obsidian Vault/03 School/Transcripts/Economics/Price elasticity and surplus/2026-03-25 0930 — PED, PES, Consumer Surplus, and Producer Surplus.md"
        ]

        if economicsTranscriptPaths
            .map({ URL(fileURLWithPath: homeDirectory).appendingPathComponent($0).path })
            .contains(where: fileManager.fileExists(atPath:))
        {
            contexts.append(
                makeContext(
                    title: "Economics formative follow-up — recent focus",
                    kind: "Transcript",
                    subject: "Economics",
                    summary: "The recent economics follow-up is centred on PED, PES, consumer surplus, producer surplus, social surplus, and graph interpretation under time pressure.",
                    detail: """
                    Grounded local sources:
                    - \(URL(fileURLWithPath: homeDirectory).appendingPathComponent(economicsTranscriptPaths[0]).path)
                    - \(URL(fileURLWithPath: homeDirectory).appendingPathComponent(economicsTranscriptPaths[1]).path)

                    Actionable follow-up:
                    - rework any slow graph questions
                    - tighten written interpretation after calculations
                    - keep the latest formative content live in the next timed workbook burst
                    """,
                    createdAt: calendar.date(byAdding: .minute, value: -20, to: now) ?? now
                )
            )
        }

        let messageParts = [
            dbExists ? "codex-mem discovery" : nil,
            fileManager.fileExists(atPath: studyPlanURL.path) ? "study-plan" : nil,
            fileManager.fileExists(atPath: mathsMapURL.path) ? "maths HTML map" : nil
        ].compactMap { $0 }

        let message = messageParts.isEmpty
            ? "No codex-mem school context sources were found."
            : "Loaded school context from \(messageParts.joined(separator: ", "))."

        return SchoolContextPack(
            tasks: [mathsTask, englishTask, economicsTask],
            contexts: contexts,
            preferredTaskID: mathsTask.id,
            preferredContextID: contexts.first?.id,
            message: message,
            focusSubject: "Maths"
        )
    }

    static func discoverDeadlines(
        now: Date = .now,
        codexMemDBPath: String = TimedPreferences.codexMemDBPath,
        codexConfigPath: String = defaultCodexConfigPath,
        searchProvider: DiscoverySearchProvider? = nil
    ) async -> [DiscoveredDeadline] {
        await Task.detached(priority: .utility) {
            let calendar = Calendar.current
            let provider = searchProvider ?? { query, limit in
                searchCodexMem(
                    query: query,
                    limit: limit,
                    codexMemDBPath: codexMemDBPath,
                    codexConfigPath: codexConfigPath
                )
            }

            return deadlineSpecs(now: now, calendar: calendar).map { spec in
                let hits = provider(spec.query, 5)
                let matchedHits = relevantHits(from: hits, keywords: spec.keywords)
                let effectiveHits = matchedHits.isEmpty ? Array(hits.prefix(3)) : matchedHits
                let matchedTitles = effectiveHits
                    .map(\.title)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                let dueDate = spec.fixedDueDate ?? inferredDueDate(from: effectiveHits, now: now, calendar: calendar)
                let notes = discoveryNotes(for: spec, hits: effectiveHits, dueDate: dueDate)
                let label = matchedTitles.isEmpty ? "no direct hits" : matchedTitles.joined(separator: " | ")
                print("[PlannerStore] codex-mem deadline query '\(spec.query)' -> \(label)")

                return DiscoveredDeadline(
                    title: spec.title,
                    subject: spec.subject,
                    importance: spec.importance,
                    dueDate: dueDate,
                    estimateMinutes: spec.estimateMinutes,
                    energy: spec.energy,
                    query: spec.query,
                    notes: notes,
                    matchedMemoryTitles: matchedTitles
                )
            }
        }.value
    }

    private struct MemorySessionRecord {
        let id: String
        let title: String
        let subject: String
        let oneLineSummary: String
    }

    private struct DeadlineSpec {
        let title: String
        let subject: String
        let importance: Int
        let estimateMinutes: Int
        let energy: TaskEnergy
        let query: String
        let fixedDueDate: Date?
        let keywords: [String]
    }

    private struct CodexMemCLIResponse: Decodable {
        let workstreams: [CodexMemCLIWorkstream]?
        let rawResults: [CodexMemCLIRawResult]?
    }

    private struct CodexMemCLIWorkstream: Decodable {
        let canonicalName: String?
        let summary: String?
        let representativeTitle: String?
    }

    private struct CodexMemCLIRawResult: Decodable {
        let source: String?
        let title: String?
        let snippet: String?
    }

    private static func makeTask(
        title: String,
        subject: String,
        estimateMinutes: Int,
        confidence: Int,
        importance: Int,
        dueDate: Date,
        notes: String,
        energy: TaskEnergy
    ) -> TaskItem {
        TaskItem(
            id: StableID.makeTaskID(source: .chat, title: title),
            title: title,
            list: "Codex memory",
            source: .chat,
            subject: subject,
            estimateMinutes: estimateMinutes,
            confidence: confidence,
            importance: importance,
            dueDate: dueDate,
            notes: notes,
            energy: energy,
            isCompleted: false,
            completedAt: nil
        )
    }

    private static func makeContext(
        title: String,
        kind: String,
        subject: String,
        summary: String,
        detail: String,
        createdAt: Date
    ) -> ContextItem {
        ContextItem(
            id: StableID.makeContextID(source: .chat, title: title, createdAt: createdAt),
            title: title,
            kind: kind,
            subject: subject,
            summary: summary,
            detail: detail,
            createdAt: createdAt
        )
    }

    private static func nextWeekday(
        _ weekday: Int,
        hour: Int,
        minute: Int,
        from now: Date,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        components.second = 0

        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? now
    }

    private static var defaultCodexConfigPath: String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/config.toml")
            .path
    }

    private static func deadlineSpecs(now: Date, calendar: Calendar) -> [DeadlineSpec] {
        [
            DeadlineSpec(
                title: "Economics test",
                subject: "Economics",
                importance: 10,
                estimateMinutes: 120,
                energy: .high,
                query: "economics test deadline due assessment friday",
                fixedDueDate: nextWeekday(6, hour: 9, minute: 0, from: now, calendar: calendar),
                keywords: ["economics", "test", "assessment"]
            ),
            DeadlineSpec(
                title: "English assessment",
                subject: "English",
                importance: 8,
                estimateMinutes: 90,
                energy: .high,
                query: "english assessment deadline due",
                fixedDueDate: nil,
                keywords: ["english", "assessment", "essay", "comparative"]
            ),
            DeadlineSpec(
                title: "Maths investigation",
                subject: "Maths",
                importance: 7,
                estimateMinutes: 150,
                energy: .high,
                query: "maths investigation deadline due assessment wednesday",
                fixedDueDate: nextWeekday(4, hour: 9, minute: 0, from: now, calendar: calendar),
                keywords: ["maths", "mathematics", "investigation"]
            ),
            DeadlineSpec(
                title: "Society and Culture photo essay",
                subject: "Society and Culture",
                importance: 5,
                estimateMinutes: 120,
                energy: .medium,
                query: "society and culture photo essay deadline due assessment",
                fixedDueDate: nil,
                keywords: ["society", "culture", "photo essay", "essay"]
            )
        ]
    }

    private static func discoveryNotes(for spec: DeadlineSpec, hits: [DiscoveredMemoryHit], dueDate: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none

        let hitSummary = hits.isEmpty
            ? "No direct codex-mem hit returned, so Timed seeded this deadline from the startup school pack."
            : hits.prefix(3).map {
                let snippet = $0.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                if snippet.isEmpty {
                    return $0.title
                }
                return "\($0.title): \(snippet)"
            }.joined(separator: "\n- ")

        let dueLine = dueDate.map { "Resolved deadline: \(formatter.string(from: $0))." } ?? "Resolved deadline: not fixed in memory."

        return """
        Auto-discovered from codex-mem startup search.
        Query: \(spec.query)
        \(dueLine)
        Matches:
        - \(hitSummary)
        """
    }

    private static func relevantHits(from hits: [DiscoveredMemoryHit], keywords: [String]) -> [DiscoveredMemoryHit] {
        guard !keywords.isEmpty else { return hits }

        let loweredKeywords = keywords.map { $0.lowercased() }
        return hits.filter { hit in
            let haystack = "\(hit.title) \(hit.snippet)".lowercased()
            return loweredKeywords.contains(where: haystack.contains)
        }
    }

    private static func inferredDueDate(
        from hits: [DiscoveredMemoryHit],
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let formatter = ISO8601DateFormatter()
        let weekdayMap: [(String, Int)] = [
            ("monday", 2),
            ("tuesday", 3),
            ("wednesday", 4),
            ("thursday", 5),
            ("friday", 6),
            ("saturday", 7),
            ("sunday", 1)
        ]

        for text in hits.flatMap({ [$0.title, $0.snippet] }) {
            let lowered = text.lowercased()

            if let match = lowered.range(of: #"\b20\d{2}-\d{2}-\d{2}\b"#, options: .regularExpression),
               let parsed = formatter.date(from: "\(lowered[match])T09:00:00Z")
            {
                return parsed
            }

            for (weekdayName, weekdayValue) in weekdayMap where lowered.contains(weekdayName) {
                return nextWeekday(weekdayValue, hour: 9, minute: 0, from: now, calendar: calendar)
            }
        }

        return nil
    }

    private static func searchCodexMem(
        query: String,
        limit: Int,
        codexMemDBPath: String,
        codexConfigPath: String
    ) -> [DiscoveredMemoryHit] {
        if let invocation = resolveCodexMemCLIInvocation(configPath: codexConfigPath),
           let response = runCodexMemCLI(invocation: invocation, query: query, limit: limit)
        {
            let hits = cliHits(from: response)
            if !hits.isEmpty {
                return hits
            }
        }

        return CodexMemorySearchProvider.search(question: query, limit: limit, dbPath: codexMemDBPath).map {
            DiscoveredMemoryHit(source: $0.source, title: $0.title, snippet: $0.excerpt)
        }
    }

    private static func resolveCodexMemCLIInvocation(
        configPath: String
    ) -> (executable: String, baseArguments: [String])? {
        let fileManager = FileManager.default
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent("codex-mem").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return (candidate, [])
            }
        }

        let installedWrapper = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex-mem/bin/codex-mem")
            .path
        if fileManager.isExecutableFile(atPath: installedWrapper) {
            return (installedWrapper, [])
        }

        guard let configText = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }

        let lines = configText.components(separatedBy: .newlines)
        guard let blockStart = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[mcp_servers.codex_mem]" }) else {
            return nil
        }

        let blockLines = lines[(blockStart + 1)...].prefix { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("[")
        }

        guard
            let commandLine = blockLines.first(where: { $0.contains("command =") }),
            let executable = quotedValues(in: commandLine).first,
            fileManager.isExecutableFile(atPath: executable)
        else {
            return nil
        }

        let argsLine = blockLines.first(where: { $0.contains("args =") })
        let args = argsLine.map(quotedValues(in:)) ?? []
        guard let cliPath = args.first, fileManager.fileExists(atPath: cliPath) else {
            return nil
        }

        return (executable, [cliPath])
    }

    private static func runCodexMemCLI(
        invocation: (executable: String, baseArguments: [String]),
        query: String,
        limit: Int
    ) -> CodexMemCLIResponse? {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.baseArguments + ["search", query, "--limit", String(limit)]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8),
                  let jsonStart = output.firstIndex(of: "{")
            else {
                return nil
            }

            let json = String(output[jsonStart...])
            return try JSONDecoder().decode(CodexMemCLIResponse.self, from: Data(json.utf8))
        } catch {
            return nil
        }
    }

    private static func cliHits(from response: CodexMemCLIResponse) -> [DiscoveredMemoryHit] {
        var hits: [DiscoveredMemoryHit] = []

        if let workstreams = response.workstreams {
            hits.append(contentsOf: workstreams.map { workstream in
                DiscoveredMemoryHit(
                    source: "workstream",
                    title: workstream.representativeTitle ?? workstream.canonicalName ?? "codex-mem workstream",
                    snippet: workstream.summary ?? ""
                )
            })
        }

        if let rawResults = response.rawResults {
            hits.append(contentsOf: rawResults.map { result in
                DiscoveredMemoryHit(
                    source: result.source ?? "rawResult",
                    title: result.title ?? "",
                    snippet: result.snippet ?? ""
                )
            })
        }

        var deduped: [DiscoveredMemoryHit] = []
        var seen: Set<String> = []
        for hit in hits {
            let key = "\(hit.source)|\(hit.title)|\(hit.snippet)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            deduped.append(hit)
        }

        return deduped
    }

    private static func quotedValues(in line: String) -> [String] {
        let pattern = #""([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[captureRange])
        }
    }

    private static func queryFirstLine(sql: String, dbPath: String) -> String {
        queryLines(sql: sql, dbPath: dbPath).first ?? ""
    }

    private static func memoryContexts(
        subject: String,
        keywords: [String],
        kind: String,
        limit: Int,
        dbPath: String,
        createdAt: Date
    ) -> [ContextItem] {
        recentSessions(subject: subject, keywords: keywords, limit: limit, dbPath: dbPath)
            .enumerated()
            .compactMap { index, session in
                let observations = sessionObservations(sessionID: session.id, dbPath: dbPath)
                let summaries = sessionSummaries(sessionID: session.id, dbPath: dbPath)

                let summary = [
                    session.oneLineSummary,
                    summaries.first,
                    observations.first
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })

                let detailSections = [
                    "Source session: \(session.id)",
                    session.subject.isEmpty ? nil : "Subject: \(session.subject)",
                    session.oneLineSummary.isEmpty ? nil : "One-line summary:\n\(session.oneLineSummary)",
                    summaries.isEmpty ? nil : "Session summaries:\n\(summaries.joined(separator: "\n\n"))",
                    observations.isEmpty ? nil : "Observations:\n\(observations.joined(separator: "\n\n"))"
                ].compactMap { $0 }

                guard !detailSections.isEmpty else { return nil }

                let titleSeed = session.title.isEmpty ? session.id : session.title
                let offsetMinutes = index * 2
                return makeContext(
                    title: "\(subject) codex-mem — \(titleSeed)",
                    kind: kind,
                    subject: subject,
                    summary: summary ?? "Recovered relevant \(subject) context from codex-mem.",
                    detail: detailSections.joined(separator: "\n\n"),
                    createdAt: Calendar.current.date(byAdding: .minute, value: -offsetMinutes, to: createdAt) ?? createdAt
                )
            }
    }

    private static func recentSessions(
        subject: String,
        keywords: [String],
        limit: Int,
        dbPath: String
    ) -> [MemorySessionRecord] {
        let clause = sessionMatchClause(subject: subject, keywords: keywords)
        guard !clause.isEmpty else { return [] }

        let sql = """
        SELECT
          id,
          COALESCE(title, '') AS title,
          COALESCE(subject, '') AS subject,
          COALESCE(one_line_summary, '') AS one_line_summary
        FROM sessions
        WHERE \(clause)
        ORDER BY COALESCE(updated_at_epoch, created_at_epoch) DESC
        LIMIT \(limit);
        """

        return queryRows(sql: sql, dbPath: dbPath).compactMap { row in
            guard let id = row["id"] as? String else { return nil }

            return MemorySessionRecord(
                id: id,
                title: row["title"] as? String ?? "",
                subject: row["subject"] as? String ?? "",
                oneLineSummary: row["one_line_summary"] as? String ?? ""
            )
        }
    }

    private static func sessionObservations(sessionID: String, dbPath: String) -> [String] {
        queryLines(
            sql: """
            SELECT title || ': ' || replace(content_text, char(10), ' ')
            FROM observations
            WHERE session_id = '\(escapeSQL(sessionID))'
            ORDER BY created_at_epoch DESC
            LIMIT 4;
            """,
            dbPath: dbPath
        )
    }

    private static func sessionSummaries(sessionID: String, dbPath: String) -> [String] {
        queryLines(
            sql: """
            SELECT replace(summary_text, char(10), ' ')
            FROM session_summaries
            WHERE session_id = '\(escapeSQL(sessionID))'
            ORDER BY created_at_epoch DESC
            LIMIT 2;
            """,
            dbPath: dbPath
        )
    }

    private static func sessionMatchClause(subject: String, keywords: [String]) -> String {
        let termClauses = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .map { keyword in
                let escaped = escapeSQL(keyword)
                return """
                lower(COALESCE(title, '')) LIKE '%\(escaped)%' OR
                lower(COALESCE(one_line_summary, '')) LIKE '%\(escaped)%' OR
                lower(COALESCE(id, '')) LIKE '%\(escaped)%'
                """
            }

        let subjectClause = "lower(COALESCE(subject, '')) = lower('\(escapeSQL(subject))')"
        return ([subjectClause] + termClauses).joined(separator: " OR ")
    }

    private static func queryRows(sql: String, dbPath: String) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", dbPath, sql]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return [] }

            let json = try JSONSerialization.jsonObject(with: data)
            return json as? [[String: Any]] ?? []
        } catch {
            return []
        }
    }

    private static func queryLines(sql: String, dbPath: String) -> [String] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, sql]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    private static func escapeSQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
