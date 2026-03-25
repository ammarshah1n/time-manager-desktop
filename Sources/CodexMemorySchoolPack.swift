import Foundation

struct SchoolContextPack {
    let tasks: [TaskItem]
    let contexts: [ContextItem]
    let preferredTaskID: String?
    let preferredContextID: String?
    let message: String
    let focusSubject: String?
}

enum CodexMemorySchoolPack {
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

    private struct MemorySessionRecord {
        let id: String
        let title: String
        let subject: String
        let oneLineSummary: String
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
