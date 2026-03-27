import SwiftUI

struct FocusTimerWidget: View {
    let timer: FocusTimerModel
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            FocusProgressRing(progress: timer.progress)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(timer.sessionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(timer.countdownText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: onTogglePause) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(timer.secondsRemaining == 0)

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timer.sessionTitle), \(timer.countdownText) remaining")
    }
}

struct FocusBreakBanner: View {
    let prompt: FocusBreakPrompt
    let onStartBreak: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: prompt.isLongBreak ? "cup.and.saucer.fill" : "figure.walk")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text(prompt.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("Start break", action: onStartBreak)
                .buttonStyle(.borderedProminent)

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

private struct FocusProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}
