import Foundation
import PDFKit
import Testing

@testable import time_manager_desktop

@Suite("PDF export")
struct PDFExporterTests {
    private let fixedDate = ISO8601DateFormatter().date(from: "2026-03-27T08:30:00Z")!

    @Test("testPDFOutputFilenameMatchesStory")
    func testPDFOutputFilenameMatchesStory() {
        let url = PDFExporter.outputURL(for: fixedDate, fileManager: .default)
        #expect(url.lastPathComponent == "Timed-2026-03-27.pdf")
    }

    @Test("testPDFDocumentContainsTasksScheduleAndPomodoroNote")
    @MainActor
    func testPDFDocumentContainsTasksScheduleAndPomodoroNote() throws {
        let task = TaskItem(
            id: "econ-test",
            title: "Economics test",
            list: "School",
            source: .seqta,
            subject: "Economics",
            estimateMinutes: 90,
            confidence: 2,
            importance: 10,
            dueDate: fixedDate,
            notes: "Revise market failure and elasticity.",
            energy: .high,
            isCompleted: false,
            completedAt: nil
        )
        let scheduleBlock = ScheduleBlock(
            id: "block-1",
            taskID: task.id,
            title: "Economics revision block",
            start: fixedDate,
            end: fixedDate.addingTimeInterval(60 * 60),
            timeRange: "8:30 AM - 9:30 AM",
            note: "Practice short-answer questions",
            isApproved: true
        )

        let document = try PDFExporter.makeDocument(
            date: fixedDate,
            tasks: [task],
            schedule: [scheduleBlock],
            activePomodoroNote: "Economics test • 12:00 remaining"
        )

        #expect(document.pageCount == 1)
        let pageText = document.page(at: 0)?.string ?? ""
        #expect(pageText.contains("Timed Daily Plan"))
        #expect(pageText.contains("Economics test"))
        #expect(pageText.contains("Importance 10"))
        #expect(pageText.contains("Economics revision block"))
        #expect(pageText.contains("Active Pomodoro"))
    }
}
