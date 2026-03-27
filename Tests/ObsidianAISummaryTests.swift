import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Obsidian AI summary")
struct ObsidianAISummaryTests {
    @Test("parses numbered dashed and dot bullets into a 3-line digest")
    func parseObsidianSummaryBulletsHandlesCommonPrefixes() {
        let parsed = PlannerStore.parseObsidianSummaryBullets(
            from: """
            Here is the digest:
            1. Revise the core definition first.
            - Practise the strongest diagram from memory.
            • Finish with one evaluation sentence you can reuse.
            """
        )

        #expect(parsed == [
            "Revise the core definition first.",
            "Practise the strongest diagram from memory.",
            "Finish with one evaluation sentence you can reuse."
        ])
    }

    @MainActor
    @Test("summary generation caches per task and avoids a second Codex call")
    func generateObsidianSummaryCachesByTaskID() async throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-obsidian-summary-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        let task = TaskItem(
            id: "economics-test",
            title: "Economics test",
            list: "Seqta",
            source: .seqta,
            subject: "Economics",
            estimateMinutes: 60,
            confidence: 2,
            importance: 10,
            dueDate: nil,
            notes: "",
            energy: .high,
            isCompleted: false,
            completedAt: nil
        )

        store.tasks = [task]
        store.obsidianDocuments = [
            ContextDocument(
                id: "econ-1",
                subject: "Economics",
                title: "Elasticity drill",
                content: "Elasticity definitions and worked diagram steps.",
                path: "Economics/elasticity.md",
                importedAt: .now
            ),
            ContextDocument(
                id: "econ-2",
                subject: "Economics",
                title: "Surplus recap",
                content: "Consumer and producer surplus reminders.",
                path: "Economics/surplus.md",
                importedAt: .now.addingTimeInterval(-60)
            ),
            ContextDocument(
                id: "econ-3",
                subject: "Economics",
                title: "Workbook corrections",
                content: "Keep answers grounded in workbook-style language.",
                path: "Economics/workbook.md",
                importedAt: .now.addingTimeInterval(-120)
            )
        ]

        var promptCount = 0

        let summary = try await store.generateObsidianSummary(for: task) { prompt in
            promptCount += 1
            #expect(prompt.contains("Summarise these notes in exactly 3 bullet points relevant to the task: Economics test"))
            #expect(prompt.contains("[Elasticity drill]"))
            return .success(
                """
                1. Lock in elasticity definitions and the worked sequence.
                - Rehearse the consumer and producer surplus diagrams.
                • Keep your final explanation in workbook-style wording.
                """
            )
        }

        let cachedSummary = try await store.generateObsidianSummary(for: task) { _ in
            promptCount += 100
            return .failure(CodexRunFailure(message: "Runner should not have been called.", exitCode: 1))
        }

        #expect(summary == """
        • Lock in elasticity definitions and the worked sequence.
        • Rehearse the consumer and producer surplus diagrams.
        • Keep your final explanation in workbook-style wording.
        """)
        #expect(cachedSummary == summary)
        #expect(store.obsidianSummaryCache[task.id] == summary)
        #expect(promptCount == 1)
    }
}
