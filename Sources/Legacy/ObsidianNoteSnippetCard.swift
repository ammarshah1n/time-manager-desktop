import SwiftUI

struct ObsidianNoteSnippetCard: View {
    let document: ContextDocument
    @State private var isExpanded = false

    var body: some View {
        TimedCard(title: document.title, icon: "note.text") {
            VStack(alignment: .leading, spacing: 10) {
                Text(document.path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .textSelection(.enabled)

                Text(snippetText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                    .textSelection(.enabled)

                if document.content.count > snippetLimit {
                    Button(isExpanded ? "Show less" : "Show more") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var snippetText: String {
        if isExpanded || document.content.count <= snippetLimit {
            return document.content
        }

        let prefix = document.content.prefix(snippetLimit)
        return "\(prefix)…"
    }

    private var snippetLimit: Int { 400 }
}
