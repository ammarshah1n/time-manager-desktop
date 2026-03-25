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
    private static let mathsSessionID = "codex-live-maths-investigation-20260325"
    private static let economicsSessionID = "codex_import:019d196e-3f71-7a30-b87b-ac8d57542a46"

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
            let mathsObservations = queryLines(
                sql: """
                SELECT title || ': ' || replace(content_text, char(10), ' ')
                FROM observations
                WHERE session_id = '\(mathsSessionID)'
                ORDER BY created_at_epoch DESC
                LIMIT 3;
                """,
                dbPath: codexMemDBPath
            )

            if !mathsObservations.isEmpty {
                contexts.append(
                    makeContext(
                        title: "Maths investigation feedback — priority fixes",
                        kind: "Feedback",
                        subject: "Maths",
                        summary: "Teacher feedback says the folio needs a stronger intro, clearer calculation explanation, explicit subtraction logic, dimensions on diagrams, fuller limitations, and a tighter conclusion.",
                        detail: """
                        Source: codex-mem session \(mathsSessionID)

                        \(mathsObservations.joined(separator: "\n\n"))
                        """,
                        createdAt: now
                    )
                )
            }

            let economicsSummary = queryFirstLine(
                sql: """
                SELECT one_line_summary
                FROM sessions
                WHERE id = '\(economicsSessionID)'
                LIMIT 1;
                """,
                dbPath: codexMemDBPath
            )

            if !economicsSummary.isEmpty {
                contexts.append(
                    makeContext(
                        title: "Economics stimulus rules from codex-mem",
                        kind: "Feedback",
                        subject: "Economics",
                        summary: economicsSummary,
                        detail: """
                        Source: codex-mem session \(economicsSessionID)

                        Active rules:
                        - Mirror the workbook question structure and only change the content.
                        - Keep the practice inside workbook bounds.
                        - Do not give away the answer or the determinants in the stimulus.
                        - Keep it test-like: no task tips, no weird curveballs, full written interpretation.
                        """,
                        createdAt: calendar.date(byAdding: .minute, value: -5, to: now) ?? now
                    )
                )
            }
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
            dbExists ? "codex-mem" : nil,
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
}
