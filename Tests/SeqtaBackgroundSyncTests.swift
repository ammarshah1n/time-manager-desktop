import Foundation
import Testing
@testable import time_manager_desktop

struct SeqtaBackgroundSyncTests {
    @Test
    func testSeqtaSnapshotLoadsTasks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshotURL = directory.appendingPathComponent("seqta-latest.json")

        let payload = """
        {
          "assessments": [
            {
              "id": 34819,
              "subject": "Legal Studies",
              "title": "Adversarial vs Inquisitorial Inquiry Essay",
              "due": "2026-03-18",
              "status": "UPCOMING",
              "hasFeedback": false,
              "overdue": false
            },
            {
              "id": 33952,
              "subject": "General Mathematics",
              "title": "INV 1 - Measurement Investigation Draft",
              "due": "2026-03-16",
              "status": "UPCOMING",
              "hasFeedback": false,
              "overdue": true
            }
          ]
        }
        """

        try payload.write(to: snapshotURL, atomically: true, encoding: .utf8)

        let tasks = SeqtaBackgroundSync.loadTasks(snapshotURL: snapshotURL)

        #expect(tasks.count == 2)
        #expect(tasks.contains(where: { $0.subject == "Legal Studies" }))
        #expect(tasks.contains(where: { $0.subject == "Maths" && $0.importance == 5 }))
        #expect(tasks.allSatisfy { $0.source == .seqta })
    }

    @Test
    func testSeqtaSnapshotParsesFlexibleDueDatesAndSubjectAliases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshotURL = directory.appendingPathComponent("seqta-latest.json")
        let fixedNow = ISO8601DateFormatter().date(from: "2026-03-26T02:00:00Z")!

        let payload = """
        {
          "assessments": [
            {
              "id": 1,
              "subject": "SACE Economics",
              "title": "Market structures revision",
              "due": "26 March 2026",
              "status": "UPCOMING",
              "hasFeedback": false,
              "overdue": false
            },
            {
              "id": 2,
              "subject": "Eng Stds",
              "title": "Comparative essay draft",
              "due": "26/03/2026",
              "status": "UPCOMING",
              "hasFeedback": false,
              "overdue": false
            },
            {
              "id": 3,
              "subject": "S&C",
              "title": "Photo essay planning",
              "due": "Due: Monday",
              "status": "UPCOMING",
              "hasFeedback": false,
              "overdue": false
            }
          ]
        }
        """

        try payload.write(to: snapshotURL, atomically: true, encoding: .utf8)

        let tasks = SeqtaBackgroundSync.loadTasks(now: fixedNow, snapshotURL: snapshotURL)

        #expect(tasks.count == 3)
        #expect(tasks.contains(where: { $0.subject == "Economics" && $0.dueDate != nil }))
        #expect(tasks.contains(where: { $0.subject == "English" && $0.dueDate != nil }))
        #expect(tasks.contains(where: { $0.subject == "Society and Culture" && $0.dueDate != nil }))
    }
}
