import Foundation
import Testing

@testable import time_manager_desktop

struct CodexMemorySyncTests {
    @Test
    func testRecordAndLoadConversationRoundTripsMessages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let dbURL = root.appendingPathComponent("codex-mem.db")
        try runSQLite(
            sql: """
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              source TEXT NOT NULL,
              external_id TEXT NOT NULL,
              title TEXT NOT NULL,
              project_label TEXT,
              project_path TEXT,
              started_at_epoch INTEGER,
              updated_at_epoch INTEGER,
              status TEXT,
              raw_pointer TEXT,
              metadata_json TEXT,
              created_at_epoch INTEGER NOT NULL,
              transcript_jsonb TEXT,
              project TEXT,
              tags TEXT,
              subject TEXT,
              one_line_summary TEXT,
              related_files TEXT,
              tagged_at TEXT,
              UNIQUE(source, external_id)
            );
            CREATE TABLE observations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              observation_type TEXT NOT NULL,
              title TEXT NOT NULL DEFAULT '',
              content_text TEXT NOT NULL,
              metadata_json TEXT,
              created_at_epoch INTEGER NOT NULL,
              UNIQUE(session_id, observation_type, title, content_text, created_at_epoch)
            );
            CREATE TABLE search_documents (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              doc_type TEXT NOT NULL,
              title TEXT,
              content TEXT NOT NULL,
              created_at_epoch INTEGER NOT NULL,
              UNIQUE(session_id, doc_type, title, content, created_at_epoch)
            );
            CREATE VIRTUAL TABLE search_documents_fts USING fts5(
              title,
              content,
              content='search_documents',
              content_rowid='id'
            );
            CREATE TRIGGER search_documents_ai AFTER INSERT ON search_documents BEGIN
              INSERT INTO search_documents_fts(rowid, title, content)
              VALUES (new.id, new.title, new.content);
            END;
            CREATE TRIGGER search_documents_ad AFTER DELETE ON search_documents BEGIN
              INSERT INTO search_documents_fts(search_documents_fts, rowid, title, content)
              VALUES ('delete', old.id, old.title, old.content);
            END;
            CREATE TRIGGER search_documents_au AFTER UPDATE ON search_documents BEGIN
              INSERT INTO search_documents_fts(search_documents_fts, rowid, title, content)
              VALUES ('delete', old.id, old.title, old.content);
              INSERT INTO search_documents_fts(rowid, title, content)
              VALUES (new.id, new.title, new.content);
            END;
            """,
            dbPath: dbURL.path
        )

        let plannerMessage = PromptMessage(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            role: .user,
            text: "Rank my tasks for maths and economics.",
            createdAt: Date(timeIntervalSince1970: 1_711_420_000),
            isQuiz: false
        )
        let studyMessage = PromptMessage(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            role: .tutor,
            text: "Question 1: explain PED.",
            createdAt: Date(timeIntervalSince1970: 1_711_420_060),
            isQuiz: true
        )

        CodexMemorySync.recordMessage(
            plannerMessage,
            channel: .planner,
            subject: "Maths",
            dbPath: dbURL.path,
            projectPath: root.path
        )
        CodexMemorySync.recordMessage(
            studyMessage,
            channel: .study,
            subject: "Economics",
            dbPath: dbURL.path,
            projectPath: root.path
        )

        let plannerConversation = CodexMemorySync.loadConversation(channel: .planner, dbPath: dbURL.path)
        let studyConversation = CodexMemorySync.loadConversation(channel: .study, dbPath: dbURL.path)

        #expect(plannerConversation.count == 1)
        #expect(studyConversation.count == 1)
        #expect(plannerConversation.first?.id == plannerMessage.id)
        #expect(plannerConversation.first?.role == .user)
        #expect(plannerConversation.first?.text == plannerMessage.text)
        #expect(studyConversation.first?.id == studyMessage.id)
        #expect(studyConversation.first?.role == .tutor)
        #expect(studyConversation.first?.isQuiz == true)
    }

    private func runSQLite(sql: String, dbPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, sql]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
