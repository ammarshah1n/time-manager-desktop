import Foundation

enum CodexMemoryInsights {
    static func inferredConfidence(subject: String, title: String, fallback: Int = 3) -> Int {
        let keywords = subjectKeywords(for: subject) + titleKeywords(for: title)
        let frequency = keywordFrequency(for: Array(Set(keywords)))

        switch frequency {
        case 25...:
            return 1
        case 12...:
            return 2
        case 5...:
            return 3
        case 2...:
            return 4
        default:
            return fallback
        }
    }

    static func recordDebrief(task: TaskItem, confidence: Int, covered: String, blockers: String, at: Date) {
        guard FileManager.default.fileExists(atPath: TimedPreferences.codexMemDBPath) else { return }

        let sessionID = "timed-study-debrief"
        let epoch = Int(at.timeIntervalSince1970 * 1000)
        let summary = """
        Subject: \(task.subject)
        Task: \(task.title)
        Confidence now: \(confidence)/5
        Covered: \(covered.isEmpty ? "Nothing entered" : covered)
        Blockers: \(blockers.isEmpty ? "None" : blockers)
        """

        let sessionSQL = """
        INSERT OR IGNORE INTO sessions (
          id, source, external_id, title, project_label, project_path,
          started_at_epoch, updated_at_epoch, status, created_at_epoch
        ) VALUES (
          '\(escapeSQL(sessionID))',
          'timed',
          '\(escapeSQL(sessionID))',
          'Timed Study Debriefs',
          'Timed',
          '\(escapeSQL(FileManager.default.currentDirectoryPath))',
          \(epoch),
          \(epoch),
          'active',
          \(epoch)
        );
        UPDATE sessions SET updated_at_epoch = \(epoch) WHERE id = '\(escapeSQL(sessionID))';
        INSERT OR IGNORE INTO observations (
          session_id, observation_type, title, content_text, metadata_json, created_at_epoch
        ) VALUES (
          '\(escapeSQL(sessionID))',
          'study_debrief',
          '\(escapeSQL(task.title))',
          '\(escapeSQL(summary))',
          '\(escapeSQL("{\"subject\":\"\(task.subject)\",\"confidence\":\(confidence)}"))',
          \(epoch)
        );
        INSERT OR IGNORE INTO search_documents (
          session_id, doc_type, title, content, created_at_epoch
        ) VALUES (
          '\(escapeSQL(sessionID))',
          'study_debrief',
          '\(escapeSQL(task.title))',
          '\(escapeSQL(summary))',
          \(epoch)
        );
        """

        _ = shell(sql: sessionSQL)
    }

    private static func keywordFrequency(for keywords: [String]) -> Int {
        guard FileManager.default.fileExists(atPath: TimedPreferences.codexMemDBPath) else { return 0 }
        let filtered = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 3 }

        guard !filtered.isEmpty else { return 0 }
        let query = filtered.map { "\"\(escapeFTS($0))\"" }.joined(separator: " OR ")
        let sql = "SELECT COUNT(*) FROM search_documents_fts WHERE search_documents_fts MATCH '\(query)';"
        let output = shell(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output) ?? 0
    }

    private static func subjectKeywords(for subject: String) -> [String] {
        switch subject {
        case "Maths":
            return ["maths", "calculus", "quadratic", "differentiation", "integration", "algebra", "statistics", "investigation"]
        case "English":
            return ["english", "poetry", "analysis", "essay", "quotes", "themes"]
        case "Economics":
            return ["economics", "market", "inflation", "demand", "supply", "elasticity"]
        case "Chemistry":
            return ["chemistry", "moles", "equilibrium", "stoichiometry", "acid", "redox"]
        case "Physics":
            return ["physics", "motion", "force", "energy", "electricity", "waves"]
        case "Biology":
            return ["biology", "cell", "genetics", "photosynthesis", "ecosystem"]
        case "Legal Studies":
            return ["legal", "law", "court", "rights", "constitution"]
        case "Modern History":
            return ["history", "source", "war", "historian"]
        case "Geography":
            return ["geography", "urban", "climate", "population"]
        case "PE":
            return ["pe", "training", "sport", "performance"]
        case "Languages":
            return ["language", "vocabulary", "grammar", "translation"]
        default:
            return [subject.lowercased()]
        }
    }

    private static func titleKeywords(for title: String) -> [String] {
        title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 4 }
    }

    private static func shell(sql: String) -> String {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [TimedPreferences.codexMemDBPath, sql]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func escapeSQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func escapeFTS(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
