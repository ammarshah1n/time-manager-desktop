import SwiftUI

struct TimedSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.56))
            .tracking(1.2)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
    }
}

struct TaskLibraryCompactRow: View {
    let title: String
    let iconName: String
    let dueText: String
    let countdownText: String?
    let urgencyColor: Color
    let isSelected: Bool
    let isCompleted: Bool
    let depth: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if depth > 0 {
                    HStack(spacing: 6) {
                        ForEach(0..<depth, id: \.self) { _ in
                            Color.clear
                                .frame(width: 8, height: 1)
                        }

                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(isCompleted ? 0.25 : 0.42))
                    }
                }

                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(isCompleted ? 0.35 : 0.76))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(isCompleted ? 0.42 : 0.88))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Circle()
                    .fill(isCompleted ? Color.white.opacity(0.18) : urgencyColor)
                    .frame(width: 7, height: 7)

                if let countdownText {
                    DeadlineCountdownBadge(text: countdownText)
                }

                Text(dueText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.14) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }
}

struct NextUpTaskCard: View {
    let ranked: RankedTask
    let iconName: String
    let isSelected: Bool
    let onStart: () -> Void
    let onContext: () -> Void
    let onComplete: () -> Void

    var body: some View {
        TimedCard(title: ranked.task.title, icon: iconName) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    pill(text: ranked.band)
                    pill(text: "Score \(ranked.score)", highlighted: true)
                    Spacer()
                }

                Text(ranked.suggestedNextAction)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Button("Start", action: onStart)
                        .buttonStyle(.borderedProminent)

                    Button("Context", action: onContext)
                        .buttonStyle(.bordered)

                    Button("Done", action: onComplete)
                        .buttonStyle(.bordered)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private func pill(text: String, highlighted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(highlighted ? 0.94 : 0.78))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(highlighted ? Color.white.opacity(0.14) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

struct ContextSnippetCard: View {
    let context: ContextItem
    let onQuiz: () -> Void

    var body: some View {
        TimedCard(title: context.title, icon: "text.book.closed") {
            VStack(alignment: .leading, spacing: 10) {
                Text(context.kind)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Text(context.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)

                Text(context.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(6)

                Button("Study", action: onQuiz)
                    .buttonStyle(.bordered)
            }
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }
}
