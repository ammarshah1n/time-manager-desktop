// FocusTimerView.swift — Timed iOS Mockup
// Screen 3: Circular focus timer with start / pause / stop controls.

import SwiftUI

struct FocusTimerView: View {
    @StateObject private var timer = FocusTimer(minutes: 90)

    // In production this would come from the active time block; hardcoded for mockup.
    private let block = MockTimeBlock.samples[0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Active task label
                VStack(spacing: 6) {
                    Text("FOCUSING ON")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    Text(block.emailSubject)
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Text("from \(block.sender)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer().frame(height: 52)

                // Ring + countdown
                ZStack {
                    // Track ring
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 14)
                        .frame(width: 256, height: 256)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(
                            timerColor,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 256, height: 256)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timer.progress)

                    // Time + state
                    VStack(spacing: 4) {
                        Text(timer.timeString)
                            .font(.system(size: 54, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        Text(stateLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .animation(.easeInOut, value: timer.state)
                    }
                }

                Spacer().frame(height: 56)

                // Controls
                HStack(spacing: 36) {
                    // Stop
                    CircleButton(
                        icon: "stop.fill",
                        size: 58,
                        background: Color(.systemGray6),
                        foreground: timer.state == .idle ? Color(.systemGray3) : .primary
                    ) {
                        timer.stop()
                    }
                    .disabled(timer.state == .idle)

                    // Play / Pause (primary)
                    CircleButton(
                        icon: timer.state == .running ? "pause.fill" : "play.fill",
                        size: 76,
                        background: timerColor,
                        foreground: .white,
                        shadow: timerColor.opacity(0.35)
                    ) {
                        timer.state == .running ? timer.pause() : timer.start()
                    }

                    // Skip
                    CircleButton(
                        icon: "forward.end.fill",
                        size: 58,
                        background: Color(.systemGray6),
                        foreground: Color(.systemGray2)
                    ) { }
                }

                Spacer().frame(height: 44)

                // Session info strip
                HStack(spacing: 0) {
                    InfoPill(label: "Session", value: "1 of 3")
                    Divider().frame(height: 28).padding(.horizontal, 20)
                    InfoPill(label: "Duration", value: block.durationLabel)
                    Divider().frame(height: 28).padding(.horizontal, 20)
                    InfoPill(label: "Ends", value: block.endTimeLabel)
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var timerColor: Color {
        switch timer.state {
        case .idle:    .blue
        case .running: .blue
        case .paused:  .orange
        }
    }

    private var stateLabel: String {
        switch timer.state {
        case .idle:    "ready"
        case .running: "remaining"
        case .paused:  "paused"
        }
    }
}

// MARK: - Timer Model

enum TimerState { case idle, running, paused }

@MainActor
final class FocusTimer: ObservableObject {
    @Published var secondsRemaining: Int
    @Published var state: TimerState = .idle

    private let total: Int
    private var task: Task<Void, Never>?

    init(minutes: Int) {
        total = minutes * 60
        secondsRemaining = minutes * 60
    }

    var progress: CGFloat {
        CGFloat(total - secondsRemaining) / CGFloat(total)
    }

    var timeString: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    func start() {
        state = .running
        task = Task {
            while !Task.isCancelled && secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                secondsRemaining -= 1
            }
            if secondsRemaining == 0 { state = .idle }
        }
    }

    func pause() {
        task?.cancel(); task = nil
        state = .paused
    }

    func stop() {
        task?.cancel(); task = nil
        state = .idle
        secondsRemaining = total
    }
}

// MARK: - Supporting Views

struct CircleButton: View {
    let icon: String
    let size: CGFloat
    let background: Color
    let foreground: Color
    var shadow: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(background)
                    .frame(width: size, height: size)
                    .shadow(color: shadow, radius: 14, y: 4)
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(foreground)
                    .offset(x: icon == "play.fill" ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
    }
}

struct InfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    FocusTimerView()
}
