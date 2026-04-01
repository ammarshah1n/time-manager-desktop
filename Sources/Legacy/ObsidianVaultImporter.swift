import Foundation

struct ObsidianSyncResult {
    let documents: [ContextDocument]
    let contexts: [ContextItem]
    let message: String
}

enum ObsidianVaultImporter {
    static func sync(vaultPath: String) -> ObsidianSyncResult {
        let trimmedVaultPath = vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVaultPath.isEmpty else {
            return ObsidianSyncResult(documents: [], contexts: [], message: "No Obsidian vault path is configured.")
        }

        let rootURL = URL(fileURLWithPath: trimmedVaultPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return ObsidianSyncResult(documents: [], contexts: [], message: "Configured Obsidian vault path was not found.")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ObsidianSyncResult(documents: [], contexts: [], message: "Could not read the Obsidian vault.")
        }

        var documents: [ContextDocument] = []
        var contexts: [ContextItem] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]) else {
                continue
            }
            guard values.isRegularFile == true else { continue }
            guard let detail = loadMarkdown(from: fileURL) else { continue }
            guard let subject = subjectForFile(fileURL, rootURL: rootURL, detail: detail) else { continue }

            let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedDetail.isEmpty else { continue }

            let modifiedAt = values.contentModificationDate ?? .now
            let title = fileURL.deletingPathExtension().lastPathComponent
            let documentID = StableID.makeContextID(source: .transcript, title: fileURL.path, createdAt: modifiedAt)
            let relativePath = relativePath(for: fileURL, rootURL: rootURL)

            documents.append(
                ContextDocument(
                    id: documentID,
                    subject: subject,
                    title: title,
                    content: cleanedDetail,
                    path: relativePath,
                    importedAt: modifiedAt
                )
            )
            contexts.append(
                ContextItem(
                    id: documentID,
                    title: title,
                    kind: "Obsidian",
                    subject: subject,
                    summary: summaryLine(from: cleanedDetail),
                    detail: cleanedDetail,
                    createdAt: modifiedAt
                )
            )
        }

        let sortedDocuments = documents.sorted { lhs, rhs in
            if lhs.importedAt != rhs.importedAt {
                return lhs.importedAt > rhs.importedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let sortedContexts = contexts.sorted { $0.createdAt > $1.createdAt }
        let message = sortedDocuments.isEmpty
            ? "No subject-linked Obsidian markdown files were imported."
            : "Synced \(sortedDocuments.count) Obsidian note(s) into study context."

        return ObsidianSyncResult(documents: sortedDocuments, contexts: sortedContexts, message: message)
    }

    private static func subjectForFile(_ fileURL: URL, rootURL: URL, detail: String) -> String? {
        let relativePath = relativePath(for: fileURL, rootURL: rootURL)
        if let matchedByPath = SubjectCatalog.matchingSubject(in: relativePath) {
            return matchedByPath
        }

        if let matchedByTags = subjectFromTags(in: detail) {
            return matchedByTags
        }

        let folderNames = fileURL.deletingLastPathComponent().pathComponents.reversed()
        for folder in folderNames {
            if let matched = SubjectCatalog.matchingSubject(in: folder) {
                return matched
            }
        }

        return nil
    }

    private static func loadMarkdown(from fileURL: URL) -> String? {
        if let utf8 = try? String(contentsOf: fileURL, encoding: .utf8) {
            return utf8
        }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func subjectFromTags(in detail: String) -> String? {
        let tags = detail
            .split(whereSeparator: \.isWhitespace)
            .filter { $0.hasPrefix("#") }
            .map { String($0.dropFirst()) }
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: "[](){}.,;:!?"))
            }

        guard !tags.isEmpty else { return nil }
        return SubjectCatalog.matchingSubject(in: tags.joined(separator: " "))
    }

    private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path.hasSuffix("/") ? rootURL.standardizedFileURL.path : rootURL.standardizedFileURL.path + "/"
        let fullPath = fileURL.standardizedFileURL.path
        if fullPath.hasPrefix(rootPath) {
            return String(fullPath.dropFirst(rootPath.count))
        }

        let fallback = fileURL.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !fallback.isEmpty {
            return fallback
        }

        return fileURL.lastPathComponent
    }

    private static func summaryLine(from detail: String) -> String {
        let lines = detail.split(whereSeparator: \.isNewline)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("#") else { continue }
            return String(trimmed.prefix(180))
        }

        return String(detail.prefix(180))
    }
}
