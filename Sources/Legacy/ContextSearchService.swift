import Foundation

enum SearchResultType: String, CaseIterable, Identifiable, Hashable {
    case task
    case note
    case transcript
    case chat

    var id: String { rawValue }

    var sectionTitle: String {
        switch self {
        case .task:
            return "Tasks"
        case .note:
            return "Notes"
        case .transcript:
            return "Transcripts"
        case .chat:
            return "Chat"
        }
    }

    var iconName: String {
        switch self {
        case .task:
            return "checklist"
        case .note:
            return "note.text"
        case .transcript:
            return "text.book.closed"
        case .chat:
            return "message"
        }
    }
}

enum SearchMessageChannel: String, Hashable {
    case planner
    case study

    var label: String {
        switch self {
        case .planner:
            return "Planner chat"
        case .study:
            return "Study chat"
        }
    }
}

struct SearchResult: Identifiable, Hashable {
    let id: String
    let type: SearchResultType
    let title: String
    let subject: String
    let snippet: String
    let relevanceScore: Double
    let sourceLabel: String
    let taskID: String?
    let documentID: String?
    let contextID: String?
    let messageID: UUID?
    let messageChannel: SearchMessageChannel?
}

private struct SearchIndexEntry: Hashable {
    let id: String
    let type: SearchResultType
    let title: String
    let subject: String
    let sourceLabel: String
    let titleText: String
    let searchableText: String
    let snippetSource: String
    let createdAt: Date
    let taskID: String?
    let documentID: String?
    let contextID: String?
    let messageID: UUID?
    let messageChannel: SearchMessageChannel?
}

@MainActor
final class ContextSearchService {
    private var entriesByID: [String: SearchIndexEntry] = [:]
    private var buckets: [String: Set<String>] = [:]
    private var isDirty = true

    func invalidateIndex() {
        isDirty = true
    }

    func search(_ query: String, in store: PlannerStore) -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        rebuildIndexIfNeeded(using: store)

        let normalizedQuery = normalize(trimmedQuery)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = tokens(from: trimmedQuery)
        let candidateIDs = candidateEntryIDs(for: queryTokens, normalizedQuery: normalizedQuery)

        return candidateIDs.compactMap { entryID in
            guard let entry = entriesByID[entryID] else { return nil }
            let score = score(for: entry, normalizedQuery: normalizedQuery, queryTokens: queryTokens)
            guard score > 0 else { return nil }

            return SearchResult(
                id: entry.id,
                type: entry.type,
                title: entry.title,
                subject: entry.subject,
                snippet: snippet(for: entry, normalizedQuery: normalizedQuery, queryTokens: queryTokens),
                relevanceScore: score,
                sourceLabel: entry.sourceLabel,
                taskID: entry.taskID,
                documentID: entry.documentID,
                contextID: entry.contextID,
                messageID: entry.messageID,
                messageChannel: entry.messageChannel
            )
        }
        .sorted { lhs, rhs in
            if lhs.relevanceScore != rhs.relevanceScore {
                return lhs.relevanceScore > rhs.relevanceScore
            }
            if lhs.type != rhs.type {
                return lhs.type.sectionTitle < rhs.type.sectionTitle
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func rebuildIndexIfNeeded(using store: PlannerStore) {
        guard isDirty else { return }

        entriesByID = [:]
        buckets = [:]

        for task in store.tasks {
            let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = SearchIndexEntry(
                id: "task-\(task.id)",
                type: .task,
                title: task.title,
                subject: task.subject,
                sourceLabel: task.source.rawValue,
                titleText: normalize(task.title),
                searchableText: normalize([task.title, task.subject, task.list, notes].joined(separator: " ")),
                snippetSource: notes.isEmpty ? task.title : notes,
                createdAt: task.completedAt ?? task.dueDate ?? .distantPast,
                taskID: task.id,
                documentID: nil,
                contextID: nil,
                messageID: nil,
                messageChannel: nil
            )
            register(entry)
        }

        for document in store.obsidianDocuments {
            let entry = SearchIndexEntry(
                id: "note-\(document.id)",
                type: .note,
                title: document.title,
                subject: document.subject,
                sourceLabel: "Obsidian",
                titleText: normalize(document.title),
                searchableText: normalize([document.title, document.subject, document.path, document.content].joined(separator: " ")),
                snippetSource: document.content,
                createdAt: document.importedAt,
                taskID: nil,
                documentID: document.id,
                contextID: nil,
                messageID: nil,
                messageChannel: nil
            )
            register(entry)
        }

        for context in store.contexts where context.kind.caseInsensitiveCompare("Obsidian") != .orderedSame {
            let entry = SearchIndexEntry(
                id: "context-\(context.id)",
                type: .transcript,
                title: context.title,
                subject: context.subject,
                sourceLabel: context.kind,
                titleText: normalize(context.title),
                searchableText: normalize([context.title, context.subject, context.kind, context.summary, context.detail].joined(separator: " ")),
                snippetSource: [context.summary, context.detail].joined(separator: "\n"),
                createdAt: context.createdAt,
                taskID: nil,
                documentID: nil,
                contextID: context.id,
                messageID: nil,
                messageChannel: nil
            )
            register(entry)
        }

        for message in store.chat {
            register(chatEntry(from: message, channel: .planner))
        }

        for message in store.studyChat {
            register(chatEntry(from: message, channel: .study))
        }

        isDirty = false
    }

    private func chatEntry(from message: PromptMessage, channel: SearchMessageChannel) -> SearchIndexEntry {
        let title = chatTitle(for: message, channel: channel)
        let subject = SubjectCatalog.matchingSubject(in: message.text) ?? ""

        return SearchIndexEntry(
            id: "chat-\(message.id.uuidString)",
            type: .chat,
            title: title,
            subject: subject,
            sourceLabel: channel.label,
            titleText: normalize(title),
            searchableText: normalize([title, subject, message.role.displayName, message.text].joined(separator: " ")),
            snippetSource: message.text,
            createdAt: message.createdAt,
            taskID: nil,
            documentID: nil,
            contextID: nil,
            messageID: message.id,
            messageChannel: channel
        )
    }

    private func register(_ entry: SearchIndexEntry) {
        entriesByID[entry.id] = entry

        for token in tokens(fromNormalizedText: entry.searchableText) {
            let bucketKey = String(token.prefix(3))
            guard !bucketKey.isEmpty else { continue }
            buckets[bucketKey, default: []].insert(entry.id)
        }
    }

    private func candidateEntryIDs(for queryTokens: [String], normalizedQuery: String) -> Set<String> {
        var candidates: Set<String> = []

        for token in queryTokens {
            let bucketKey = String(token.prefix(3))
            guard !bucketKey.isEmpty else { continue }
            candidates.formUnion(buckets[bucketKey] ?? [])
        }

        if candidates.isEmpty {
            let bucketKey = String(normalizedQuery.prefix(3))
            candidates = buckets[bucketKey] ?? []
        }

        return candidates
    }

    private func score(for entry: SearchIndexEntry, normalizedQuery: String, queryTokens: [String]) -> Double {
        var score = 0.0

        if entry.titleText == normalizedQuery {
            score += 100
        } else if entry.titleText.contains(normalizedQuery) {
            score += 80
        }

        if entry.searchableText.contains(normalizedQuery) {
            score += score >= 80 ? 10 : 50
        }

        for token in queryTokens {
            if entry.titleText.contains(token) {
                score += 8
            } else if entry.searchableText.contains(token) {
                score += 3
            }
        }

        score += recencyBoost(for: entry.createdAt)
        return score
    }

    private func recencyBoost(for createdAt: Date) -> Double {
        guard createdAt != .distantPast else { return 0 }
        let ageInHours = max(0, Date.now.timeIntervalSince(createdAt) / 3600)
        return max(0, 20 - ageInHours / 24)
    }

    private func snippet(for entry: SearchIndexEntry, normalizedQuery: String, queryTokens: [String]) -> String {
        let sentences = sentenceCandidates(from: entry.snippetSource)

        if let exactMatch = sentences.first(where: { normalize($0).contains(normalizedQuery) }) {
            return exactMatch
        }

        if let tokenMatch = sentences.first(where: { sentence in
            let normalizedSentence = normalize(sentence)
            return queryTokens.contains(where: normalizedSentence.contains(_:))
        }) {
            return tokenMatch
        }

        if let firstSentence = sentences.first {
            return firstSentence
        }

        return entry.title
    }

    private func sentenceCandidates(from text: String) -> [String] {
        let rawSentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawSentences.isEmpty else { return [] }

        return rawSentences.map { sentence in
            if sentence.count <= 220 {
                return sentence
            }
            return "\(sentence.prefix(220))."
        }
    }

    private func chatTitle(for message: PromptMessage, channel: SearchMessageChannel) -> String {
        let prefix = "\(message.role.displayName) · \(channel.label)"
        let summary = sentenceCandidates(from: message.text).first ?? message.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !summary.isEmpty else { return prefix }
        let trimmedSummary = summary.count > 60 ? "\(summary.prefix(60))…" : summary
        return "\(prefix) — \(trimmedSummary)"
    }

    private func tokens(from text: String) -> [String] {
        tokens(fromNormalizedText: normalize(text))
    }

    private func tokens(fromNormalizedText normalizedText: String) -> [String] {
        Array(
            Set(
                normalizedText
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
                    .filter { $0.count >= 2 }
            )
        )
        .sorted()
    }

    private func normalize(_ text: String) -> String {
        SubjectCatalog.normalizedSubjectText(text)
    }
}
