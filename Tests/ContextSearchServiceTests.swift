import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Context search")
struct ContextSearchServiceTests {
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-03-26T10:00:00Z")!

    @Test("exact task title outranks content-only matches")
    @MainActor
    func testExactTaskTitleOutranksContentMatch() {
        let store = makeStore()
        store.tasks = [
            TaskItem(
                id: "task-economics-exact",
                title: "Economics test",
                list: "Seqta",
                source: .seqta,
                subject: "Economics",
                estimateMinutes: 60,
                confidence: 2,
                importance: 5,
                dueDate: fixedNow,
                notes: "Revise market failure and elasticity.",
                energy: .high,
                isCompleted: false,
                completedAt: nil
            ),
            TaskItem(
                id: "task-english-content",
                title: "English essay plan",
                list: "Seqta",
                source: .seqta,
                subject: "English",
                estimateMinutes: 45,
                confidence: 3,
                importance: 3,
                dueDate: fixedNow.addingTimeInterval(3600),
                notes: "Compare this with the economics test structure.",
                energy: .medium,
                isCompleted: false,
                completedAt: nil
            )
        ]
        store.contexts = []
        store.obsidianDocuments = []
        store.chat = []
        store.studyChat = []

        let service = ContextSearchService()
        let results = service.search("Economics test", in: store)

        #expect(results.first?.type == .task)
        #expect(results.first?.taskID == "task-economics-exact")
        #expect(results.first?.relevanceScore ?? 0 > results.dropFirst().first?.relevanceScore ?? 0)
    }

    @Test("search indexes notes transcripts and chat history together")
    @MainActor
    func testSearchIndexesNotesTranscriptsAndChat() {
        let store = makeStore()
        store.tasks = []
        store.obsidianDocuments = [
            ContextDocument(
                id: "note-consumer-surplus",
                subject: "Economics",
                title: "Consumer surplus revision",
                content: "Consumer surplus is the difference between willingness to pay and market price. Use the shaded triangle in diagrams.",
                path: "/Vault/Economics/consumer-surplus.md",
                importedAt: fixedNow
            )
        ]
        store.contexts = [
            ContextItem(
                id: "ctx-consumer-surplus",
                title: "Transcript excerpt",
                kind: "Transcript",
                subject: "Economics",
                summary: "Consumer surplus appears in the first diagram.",
                detail: "Consumer surplus is the top triangle above the market price line and below the demand curve.",
                createdAt: fixedNow.addingTimeInterval(-600)
            )
        ]
        store.chat = [
            PromptMessage(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                role: .assistant,
                text: "Your consumer surplus explanation is weak. Revisit the first diagram.",
                createdAt: fixedNow.addingTimeInterval(-1200)
            )
        ]
        store.studyChat = []

        let service = ContextSearchService()
        let results = service.search("consumer surplus", in: store)
        let types = Set(results.map(\.type))

        #expect(types.contains(.note))
        #expect(types.contains(.transcript))
        #expect(types.contains(.chat))
        #expect(results.contains(where: { $0.snippet.localizedCaseInsensitiveContains("Consumer surplus is the difference") }))
    }

    @MainActor
    private func makeStore() -> PlannerStore {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-search-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.tasks = []
        store.contexts = []
        store.obsidianDocuments = []
        store.schedule = []
        store.chat = []
        store.studyChat = []
        return store
    }
}
