import SwiftUI

struct WeeklyReviewView: View {
    let summary: WeeklyReviewSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewCard
                    confidenceCard
                    prioritiesCard
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 620)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Review")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("What moved this week, what your confidence did, and what Timed wants at the top of next week.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var overviewCard: some View {
        TimedCard(title: "This week", icon: "calendar.badge.clock") {
            HStack(spacing: 12) {
                statBlock(
                    title: "Completed",
                    value: "\(summary.completedTaskCount)",
                    subtitle: "tasks finished"
                )

                statBlock(
                    title: "Pomodoros",
                    value: "\(summary.totalPomodoros)",
                    subtitle: "focus blocks logged"
                )
            }
        }
    }

    private var confidenceCard: some View {
        TimedCard(title: "Confidence change", icon: "waveform.path.ecg") {
            if summary.confidenceDeltas.isEmpty {
                emptyState("No confidence history yet.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(summary.confidenceDeltas) { delta in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(delta.subject)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)

                                Text("\(confidenceText(delta.startingValue)) -> \(confidenceText(delta.latestValue))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }

                            Spacer()

                            deltaBadge(delta.delta)
                        }

                        if delta.id != summary.confidenceDeltas.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private var prioritiesCard: some View {
        TimedCard(title: "Top priorities", icon: "flag.fill") {
            if summary.topPriorities.isEmpty {
                emptyState("No active tasks to rank.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(summary.topPriorities.enumerated()), id: \.element.id) { index, ranked in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 22, height: 22)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.12))
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ranked.task.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)

                                    Text("\(ranked.task.subject) · \(ranked.band) · score \(ranked.score)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                }

                                Spacer()
                            }

                            Text(ranked.suggestedNextAction)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.78))
                                .padding(.leading, 32)
                        }

                        if ranked.id != summary.topPriorities.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private func statBlock(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func deltaBadge(_ delta: Double) -> some View {
        let tint: Color = delta >= 0 ? .green : .orange

        return Text(deltaText(delta))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.24))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.58))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func confidenceText(_ value: Double) -> String {
        String(format: "%.1f/5", value * 5.0)
    }

    private func deltaText(_ value: Double) -> String {
        String(format: "%@%.1f", value >= 0 ? "+" : "", value * 5.0)
    }
}
