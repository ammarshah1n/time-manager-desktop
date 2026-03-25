import Foundation
import Testing

@testable import time_manager_desktop

struct CodexMemorySchoolPackTests {
    @Test
    func testSchoolPackLoadsTasksAndContextsFromLocalSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let studyPlanURL = root.appendingPathComponent("study-plan.html")
        let mathsHTMLURL = root.appendingPathComponent("output/doc/maths-investigation-feedback.html")
        try FileManager.default.createDirectory(at: mathsHTMLURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        try "<html>study plan</html>".write(to: studyPlanURL, atomically: true, encoding: .utf8)
        try "<html>maths feedback</html>".write(to: mathsHTMLURL, atomically: true, encoding: .utf8)

        let dbURL = root.appendingPathComponent("codex-mem.db")
        try runSQLite(
            sql: """
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              source TEXT,
              external_id TEXT,
              title TEXT,
              project_label TEXT,
              project_path TEXT,
              started_at_epoch INTEGER,
              updated_at_epoch INTEGER,
              status TEXT,
              metadata_json TEXT,
              created_at_epoch INTEGER,
              subject TEXT,
              one_line_summary TEXT
            );
            CREATE TABLE session_summaries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              source_type TEXT NOT NULL,
              summary_text TEXT NOT NULL,
              structured_json TEXT,
              created_at_epoch INTEGER NOT NULL
            );
            CREATE TABLE observations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              observation_type TEXT NOT NULL,
              title TEXT NOT NULL,
              content_text TEXT NOT NULL,
              metadata_json TEXT,
              created_at_epoch INTEGER NOT NULL
            );
            INSERT INTO sessions (id, source, external_id, title, updated_at_epoch, created_at_epoch, subject, one_line_summary)
            VALUES
              (
                'codex_import:019d196e-3f71-7a30-b87b-ac8d57542a46',
                'timed',
                'codex_import:019d196e-3f71-7a30-b87b-ac8d57542a46',
                'Economics revision session',
                20,
                20,
                'Economics',
                'Session focused on workbook-style economics revision without giving away elasticity answers.'
              ),
              (
                'codex-live-maths-investigation-20260325',
                'timed',
                'codex-live-maths-investigation-20260325',
                'Maths investigation feedback cleanup',
                10,
                10,
                'Maths',
                'Maths feedback session.'
              );
            INSERT INTO observations (session_id, observation_type, title, content_text, created_at_epoch)
            VALUES
              ('codex-live-maths-investigation-20260325', 'feedback', 'Teacher feedback scan 1', 'Define the task and explain the subtraction logic.', 1),
              ('codex-live-maths-investigation-20260325', 'feedback', 'Teacher feedback scan 2', 'Label dimensions and tighten the conclusion.', 2);
            INSERT INTO session_summaries (session_id, source_type, summary_text, created_at_epoch)
            VALUES
              ('codex_import:019d196e-3f71-7a30-b87b-ac8d57542a46', 'manual', 'Keep the practice inside workbook bounds and do not give away determinant answers.', 3);
            """,
            dbPath: dbURL.path
        )

        let now = ISO8601DateFormatter().date(from: "2026-03-26T09:15:00Z")!
        let pack = CodexMemorySchoolPack.load(
            now: now,
            homeDirectory: root.path,
            codexMemDBPath: dbURL.path
        )

        #expect(pack.tasks.count == 3)
        #expect(pack.contexts.count >= 4)
        #expect(pack.tasks.first(where: { $0.subject == "Maths" })?.dueDate != nil)
        #expect(pack.contexts.contains(where: { $0.subject == "Maths" && $0.kind == "Feedback" }))
        #expect(pack.contexts.contains(where: { $0.subject == "Economics" && $0.kind == "Feedback" }))
        #expect(pack.contexts.contains(where: { $0.subject == "English" && $0.kind == "Plan" }))
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
