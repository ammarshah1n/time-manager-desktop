import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Obsidian vault import")
struct ObsidianVaultImporterTests {
    @Test("sync recursively indexes markdown notes by folder and tag")
    func testRecursiveImportIndexesByFolderAndTag() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-obsidian-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let economicsFolder = vaultURL.appendingPathComponent("Economics", isDirectory: true)
        let miscFolder = vaultURL.appendingPathComponent("Archive/Misc", isDirectory: true)
        try FileManager.default.createDirectory(at: economicsFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: miscFolder, withIntermediateDirectories: true)

        try """
        Consumer surplus notes
        Markets, elasticity, and economics revision.
        """.write(to: economicsFolder.appendingPathComponent("surplus.md"), atomically: true, encoding: .utf8)

        try """
        #english
        Comparative quote bank and essay structure.
        """.write(to: miscFolder.appendingPathComponent("quotes.md"), atomically: true, encoding: .utf8)

        try """
        Untagged admin note.
        """.write(to: miscFolder.appendingPathComponent("ignored.md"), atomically: true, encoding: .utf8)

        let result = ObsidianVaultImporter.sync(vaultPath: vaultURL.path)

        #expect(result.documents.count == 2)
        #expect(result.contexts.count == 2)
        #expect(Set(result.documents.map(\.subject)) == Set(["Economics", "English"]))
        #expect(result.documents.contains(where: { $0.path == "Economics/surplus.md" }))
        #expect(result.documents.contains(where: { $0.path == "Archive/Misc/quotes.md" }))
    }

    @Test("topDocuments returns the strongest matches for a subject")
    @MainActor
    func testTopDocumentsRanksByKeywordFrequency() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-obsidian-store-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        let now = Date(timeIntervalSince1970: 1_710_000_000)

        store.obsidianDocuments = [
            ContextDocument(
                id: "econ-1",
                subject: "Economics",
                title: "Price elasticity revision",
                content: "Economics elasticity markets economics producer surplus economics.",
                path: "Economics/elasticity.md",
                importedAt: now
            ),
            ContextDocument(
                id: "econ-2",
                subject: "Economics",
                title: "Short note",
                content: "Single economics mention.",
                path: "Economics/short.md",
                importedAt: now.addingTimeInterval(-60)
            ),
            ContextDocument(
                id: "eng-1",
                subject: "English",
                title: "Comparative quotes",
                content: "Essay quotes and themes.",
                path: "English/quotes.md",
                importedAt: now
            )
        ]

        let ranked = store.topDocuments(for: "Economics", limit: 2)

        #expect(ranked.map(\.id) == ["econ-1", "econ-2"])
    }
}
