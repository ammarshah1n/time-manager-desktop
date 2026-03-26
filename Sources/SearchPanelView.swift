import SwiftUI

struct SearchPanelView: View {
    let store: PlannerStore
    let service: ContextSearchService
    @Binding var query: String
    let onSelect: (SearchResult) -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var results: [SearchResult] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label("Search everything", systemImage: "magnifyingglass")
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                Text("⌘K")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            TextField("Search tasks, notes, transcripts, codex-mem context, and chat", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onChange(of: query) { _, _ in
                    refreshResults()
                }

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchHint
            } else if results.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedResults, id: \.type) { group in
                        Section(group.type.sectionTitle) {
                            ForEach(group.results) { result in
                                Button {
                                    dismiss()
                                    onSelect(result)
                                } label: {
                                    SearchResultRow(result: result, query: query)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 760, height: 620)
        .onAppear {
            refreshResults()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
    }

    private var groupedResults: [(type: SearchResultType, results: [SearchResult])] {
        SearchResultType.allCases.compactMap { type in
            let matches = results.filter { $0.type == type }
            guard !matches.isEmpty else { return nil }
            return (type, matches)
        }
    }

    private var searchHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results update as you type.")
                .font(.system(size: 14, weight: .semibold))

            Text("Timed searches task titles and notes, Obsidian note content, transcript excerpts, codex-mem context cards, and both planner and study chat history.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Try:")
                Text("economics")
                Text("photo essay")
                Text("consumer surplus")
                Text("quiz me")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No matches found")
                .font(.system(size: 14, weight: .semibold))

            Text("Try a subject name, assessment title, concept, or phrase from chat.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func refreshResults() {
        results = service.search(query, in: store)
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.type.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(result.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        if !result.subject.isEmpty {
                            subjectBadge
                        }
                    }

                    HStack(spacing: 8) {
                        Text(result.sourceLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(result.type.sectionTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(highlightedSnippet)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var subjectBadge: some View {
        Text(result.subject)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            )
    }

    private var highlightedSnippet: AttributedString {
        let baseText = result.snippet
        var attributed = AttributedString(baseText)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return attributed }

        let tokens = SubjectCatalog.normalizedSubjectText(trimmedQuery)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 2 }

        for token in tokens {
            let searchText = baseText as NSString
            var searchRange = NSRange(location: 0, length: searchText.length)

            while let foundRange = searchText.range(
                of: token,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            ).nonEmpty,
            let stringRange = Range(foundRange, in: baseText),
            let attributedRange = Range(stringRange, in: attributed) {
                attributed[attributedRange].foregroundColor = .primary
                attributed[attributedRange].font = .system(size: 13, weight: .semibold)

                let nextLocation = foundRange.location + foundRange.length
                searchRange = NSRange(location: nextLocation, length: searchText.length - nextLocation)
            }
        }

        return attributed
    }
}

private extension NSRange {
    var nonEmpty: NSRange? {
        location == NSNotFound ? nil : self
    }
}
