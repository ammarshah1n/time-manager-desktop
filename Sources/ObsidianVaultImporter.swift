import Foundation

struct ObsidianSyncResult {
    let contexts: [ContextItem]
    let message: String
}

enum ObsidianVaultImporter {
    static func sync(vaultPath: String) -> ObsidianSyncResult {
        let trimmedVaultPath = vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVaultPath.isEmpty else {
            return ObsidianSyncResult(contexts: [], message: "No Obsidian vault path is configured.")
        }

        let rootURL = URL(fileURLWithPath: trimmedVaultPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return ObsidianSyncResult(contexts: [], message: "Configured Obsidian vault path was not found.")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ObsidianSyncResult(contexts: [], message: "Could not read the Obsidian vault.")
        }

        var contexts: [ContextItem] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]) else {
                continue
            }
            guard values.isRegularFile == true else { continue }
            guard let subject = subjectForFile(fileURL, rootURL: rootURL) else { continue }
            guard let detail = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedDetail.isEmpty else { continue }

            let modifiedAt = values.contentModificationDate ?? .now
            let title = fileURL.deletingPathExtension().lastPathComponent
            contexts.append(
                ContextItem(
                    id: StableID.makeContextID(source: .transcript, title: fileURL.path, createdAt: modifiedAt),
                    title: title,
                    kind: "Obsidian",
                    subject: subject,
                    summary: summaryLine(from: cleanedDetail),
                    detail: cleanedDetail,
                    createdAt: modifiedAt
                )
            )
        }

        let sortedContexts = contexts.sorted { $0.createdAt > $1.createdAt }
        let message = sortedContexts.isEmpty
            ? "No subject-linked Obsidian markdown files were imported."
            : "Synced \(sortedContexts.count) Obsidian note(s) into study context."

        return ObsidianSyncResult(contexts: sortedContexts, message: message)
    }

    private static func subjectForFile(_ fileURL: URL, rootURL: URL) -> String? {
        let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path, with: "")
        if let matchedByPath = SubjectCatalog.matchingSubject(in: relativePath) {
            return matchedByPath
        }

        let folderNames = fileURL.deletingLastPathComponent().pathComponents.reversed()
        for folder in folderNames {
            if let matched = SubjectCatalog.matchingSubject(in: folder) {
                return matched
            }
        }

        return nil
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
