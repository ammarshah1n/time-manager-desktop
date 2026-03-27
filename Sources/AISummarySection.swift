import SwiftUI

private enum AISummarySectionState: Equatable {
    case idle
    case loading
    case done(String)
    case error(String)
}

struct AISummarySection: View {
    let task: TaskItem
    let documents: [ContextDocument]
    let store: PlannerStore

    @State private var state: AISummarySectionState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 4)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Summary")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    Text("Summarises the top \(min(documents.count, 3)) Obsidian snippets for \(task.title).")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.54))
                }

                Spacer()

                if case .loading = state {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.82))
                }
            }

            switch state {
            case .idle:
                Button("Generate") {
                    Task { await generateSummary() }
                }
                .buttonStyle(.borderedProminent)

            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.82))

                    Text("Generating summary from your note snippets…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.68))
                }

            case let .done(summary):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summaryLines(from: summary), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            case let .error(message):
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.86))
                            .padding(8)
                            .background(Circle().fill(Color.red.opacity(0.18)))

                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Try again") {
                        Task { await generateSummary() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.24), lineWidth: 1)
                )
            }
        }
        .task(id: task.id) {
            syncStateFromCache()
        }
    }

    private func syncStateFromCache() {
        if let cachedSummary = store.obsidianSummaryCache[task.id] {
            state = .done(cachedSummary)
        } else {
            state = .idle
        }
    }

    private func generateSummary() async {
        state = .loading

        do {
            let summary = try await store.generateObsidianSummary(for: task)
            state = .done(summary)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func summaryLines(from summary: String) -> [String] {
        summary
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
