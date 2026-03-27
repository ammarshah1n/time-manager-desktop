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

    @Test
    func testSeqtaSnapshotLoadsGradesFromNestedHTML() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshotURL = directory.appendingPathComponent("seqta-latest.json")

        let payload = #"""
        {
          "crawled_at": "2026-03-27T09:30:00Z",
          "courses": [
            {
              "subject": {
                "description": "Economics"
              },
              "payload": {
                "contents": "{\"document\":{\"modules\":[{\"content\":{\"html\":\"<table><tr><td>Assessment</td><td>Date</td><td>Mark</td></tr><tr><td>Market structures test</td><td>21 Mar 2026</td><td>14 / 20</td></tr><tr><td>Short response</td><td>14 Mar 2026</td><td>75%</td></tr></table>\"}}]}}"
              }
            }
          ]
        }
        """#

        try payload.write(to: snapshotURL, atomically: true, encoding: .utf8)

        let grades = SeqtaBackgroundSync.loadGrades(snapshotURL: snapshotURL)

        #expect(grades.count == 2)
        #expect(grades.first?.subject == "Economics")
        #expect(grades.first?.assessmentTitle == "Market structures test")
        #expect(grades.first?.mark == 14)
        #expect(grades.first?.outOf == 20)
        let percentageGrade = grades.first(where: { $0.assessmentTitle == "Short response" })
        #expect(percentageGrade?.mark == 75)
        #expect(percentageGrade?.outOf == 100)
    }

    @Test
    @MainActor
    func testPlannerStorePersistsAndDeduplicatesGrades() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-grades-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        let grade = GradeEntry(
            subject: "Economics",
            assessmentTitle: "Market structures test",
            mark: 14,
            outOf: 20,
            date: ISO8601DateFormatter().date(from: "2026-03-21T09:00:00Z")!
        )

        store.updateGrades([grade, grade])

        #expect(store.grades.count == 1)
        #expect(store.latestGrade(for: "Economics")?.mark == 14)

        let reloadedStore = PlannerStore(storageURL: storageURL)
        #expect(reloadedStore.grades.count == 1)
        #expect(reloadedStore.latestGrade(for: "Economics")?.assessmentTitle == "Market structures test")
    }
}
