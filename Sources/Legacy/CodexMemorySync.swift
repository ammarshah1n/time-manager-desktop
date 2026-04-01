import Foundation

enum TimedConversationChannel: String {
    case planner
    case study

    var sessionID: String {
        "timed-chat-\(rawValue)"
    }

    var sessionTitle: String {
        switch self {
        case .planner:
            return "Timed Planner Chat"
        case .study:
            return "Timed Study Chat"
        }
    }
}

private struct CodexMemoryChatMetadata: Codable {
    let id: String
    let role: String
    let isQuiz: Bool
    let isPinned: Bool?
    let subject: String?
    let channel: String
}

enum CodexMemorySync {
    static func loadConversation(
        channel: TimedConversationChannel,
        dbPath: String = TimedPreferences.codexMemDBPath
    ) -> [PromptMessage] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let sql = """
        SELECT metadata_json, content_text, created_at_epoch
        FROM observations
        WHERE session_id = '\(escapeSQL(channel.sessionID))'
          AND observation_type = 'timed_chat_message'
        ORDER BY created_at_epoch ASC, id ASC;
        """

        return runJSONQuery(sql: sql, dbPath: dbPath).compactMap { row -> PromptMessage? in
            guard
                let text = row["content_text"] as? String,
                let createdAtEpoch = epochMillis(from: row["created_at_epoch"])
            else {
                return nil
            }

            let metadata = parseMetadata(from: row["metadata_json"] as? String)
            let role = metadata.flatMap { PromptRole(rawValue: $0.role) } ?? .assistant
            let id = metadata.flatMap { UUID(uuidString: $0.id) } ?? UUID()

            return PromptMessage(
                id: id,
                role: role,
                text: text,
                createdAt: Date(timeIntervalSince1970: createdAtEpoch / 1000),
                isQuiz: metadata?.isQuiz ?? false,
                isPinned: metadata?.isPinned ?? false
            )
        }
    }

    static func merge(local: [PromptMessage], remote: [PromptMessage]) -> [PromptMessage] {
        var mergedByID: [UUID: PromptMessage] = [:]

        for message in (local + remote).sorted(by: messageSortOrder) {
            mergedByID[message.id] = mergedByID[message.id] ?? message
        }

        return mergedByID.values.sorted(by: messageSortOrder)
    }

    static func recordMessage(
        _ message: PromptMessage,
        channel: TimedConversationChannel,
        subject: String? = nil,
        dbPath: String = TimedPreferences.codexMemDBPath,
        projectPath: String = TimedPreferences.workingRoot
    ) {
        guard TimedPreferences.codexMemoryEnabled else { return }
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        let epoch = Int(message.createdAt.timeIntervalSince1970 * 1000)
        let preview = message.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = CodexMemoryChatMetadata(
            id: message.id.uuidString,
            role: message.role.rawValue,
            isQuiz: message.isQuiz,
            isPinned: message.isPinned,
            subject: subject,
            channel: channel.rawValue
        )
        let metadataJSON = encodeJSON(metadata)

        let sessionSQL = """
        INSERT OR IGNORE INTO sessions (
          id, source, external_id, title, project_label, project_path,
          started_at_epoch, updated_at_epoch, status, subject, one_line_summary, created_at_epoch
        ) VALUES (
          '\(escapeSQL(channel.sessionID))',
          'timed',
          '\(escapeSQL(channel.sessionID))',
          '\(escapeSQL(channel.sessionTitle))',
          'Timed',
          '\(escapeSQL(projectPath))',
          \(epoch),
          \(epoch),
          'active',
          \(sqlValue(subject)),
          '\(escapeSQL(String(preview.prefix(180)).isEmpty ? channel.sessionTitle : String(preview.prefix(180))))',
          \(epoch)
        );
        UPDATE sessions
        SET
          updated_at_epoch = \(epoch),
          subject = \(sqlValue(subject)),
          one_line_summary = '\(escapeSQL(String(preview.prefix(180)).isEmpty ? channel.sessionTitle : String(preview.prefix(180))))'
        WHERE id = '\(escapeSQL(channel.sessionID))';
        INSERT OR IGNORE INTO observations (
          session_id, observation_type, title, content_text, metadata_json, created_at_epoch
        ) VALUES (
          '\(escapeSQL(channel.sessionID))',
          'timed_chat_message',
          '\(escapeSQL(message.role.displayName))',
          '\(escapeSQL(message.text))',
          '\(escapeSQL(metadataJSON))',
          \(epoch)
        );
        INSERT OR IGNORE INTO search_documents (
          session_id, doc_type, title, content, created_at_epoch
        ) VALUES (
          '\(escapeSQL(channel.sessionID))',
          'timed_chat_message',
          '\(escapeSQL("\(channel.sessionTitle) • \(message.role.displayName)"))',
          '\(escapeSQL(message.text))',
          \(epoch)
        );
        """

        _ = runSQL(sql: sessionSQL, dbPath: dbPath)
    }

    private static func parseMetadata(from rawValue: String?) -> CodexMemoryChatMetadata? {
        guard
            let rawValue,
            let data = rawValue.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(CodexMemoryChatMetadata.self, from: data)
    }

    private static func encodeJSON(_ metadata: CodexMemoryChatMetadata) -> String {
        guard
            let data = try? JSONEncoder().encode(metadata),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    private static func epochMillis(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func messageSortOrder(lhs: PromptMessage, rhs: PromptMessage) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return lhs.createdAt < rhs.createdAt
    }

    private static func runJSONQuery(sql: String, dbPath: String) -> [[String: Any]] {
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

    @discardableResult
    private static func runSQL(sql: String, dbPath: String) -> String {
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
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func escapeSQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func sqlValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "NULL"
        }

        return "'\(escapeSQL(value))'"
    }
}
