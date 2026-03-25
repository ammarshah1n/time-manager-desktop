import SwiftUI

struct ContentView: View {
    @State private var store = PlannerStore()
    @State private var promptText = "Rank my school work for tonight"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.04, green: 0.05, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                header

                HStack(alignment: .top, spacing: 16) {
                    leftPane
                    centerPane
                    rightPane
                }
                .frame(maxHeight: .infinity)
            }
            .padding(22)
        }
        .frame(minWidth: 1280, minHeight: 840)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Time Manager")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                Text("Separate desktop app. Planner first. Context loaded when needed.")
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            HStack(spacing: 10) {
                StatusPill(label: "Local first")
                StatusPill(label: "Apple glass")
                StatusPill(label: "Codex-ready")
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var leftPane: some View {
        glassColumn(title: "Sources") {
            VStack(spacing: 10) {
                ForEach(store.tasks) { task in
                    SourceCard(task: task, isSelected: task.id == store.selectedTaskID) {
                        store.selectTask(task)
                    }
                }
            }
        }
        .frame(width: 340)
    }

    private var centerPane: some View {
        glassColumn(title: "Ranked plan") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Ask the planner...", text: $promptText)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button("Rank") {
                        store.promptText = promptText
                        Task {
                            await store.submitPrompt()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if store.isRunningPrompt {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running Codex prompt...")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.leading, 4)
                }

                if let top = store.rankedTasks.first {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top priority")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            Spacer()
                            Text("\(top.band) · \(top.score)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        Text(top.task.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(top.reasons.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.64))
                    }
                    .padding(14)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(spacing: 12) {
                    ForEach(store.rankedTasks.prefix(4)) { ranked in
                        RankedTaskCard(ranked: ranked, isSelected: ranked.task.id == store.selectedTaskID) {
                            store.selectTask(ranked.task)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Time boxes")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ForEach(store.schedule) { block in
                        ScheduleCard(block: block)
                    }
                }
            }
        }
    }

    private var rightPane: some View {
        glassColumn(title: "Context pack") {
            VStack(alignment: .leading, spacing: 14) {
                if let context = store.selectedContext {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(context.summary)
                            .foregroundStyle(.white.opacity(0.74))
                        Text(context.detail)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(16)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Memory sources")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ForEach(store.contexts) { context in
                        ContextCard(context: context, isSelected: context.id == store.selectedContextID) {
                            store.selectContext(context)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Chat")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.chat) { message in
                                ChatBubble(message: message)
                            }
                        }
                    }
                    .frame(minHeight: 240)
                }
            }
        }
        .frame(width: 380)
    }

    private func glassColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(1.6)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct SourceCard: View {
    let task: TaskItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(task.list.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(task.source.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                Text(task.notes)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.64))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.11) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? .blue.opacity(0.55) : .white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RankedTaskCard: View {
    let ranked: RankedTask
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.9) : Color.white.opacity(0.2))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(ranked.task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(ranked.task.subject) · \(ranked.task.estimateMinutes) min · confidence \(ranked.task.confidence)/5")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(ranked.band)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(ranked.score)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Text(ranked.task.energy.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? .blue.opacity(0.52) : .white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ContextCard: View {
    let context: ContextItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(context.kind.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(context.subject)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Text(context.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                Text(context.summary)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.11) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? .blue.opacity(0.52) : .white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ScheduleCard: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                Text(block.note)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.64))
            }

            Spacer()

            Text(block.timeRange)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(.white.opacity(0.08), in: Capsule())
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ChatBubble: View {
    let message: PromptMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.54))
            Text(message.text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
