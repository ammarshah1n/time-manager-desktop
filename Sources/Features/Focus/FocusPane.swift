// FocusPane.swift — Timed macOS Preview
// Circular countdown. Focuses on a single TimedTask.
// @Observable timer drives the arc + digit display.

import SwiftUI

struct FocusPane: View {
    let task: TimedTask?
    let onComplete: () -> Void
    @State private var session: FocusSession
    @State private var showNextPrompt = false

    init(task: TimedTask?, onComplete: @escaping () -> Void) {
        self.task = task
        self.onComplete = onComplete
        self._session = State(initialValue: FocusSession(minutes: task?.estimatedMinutes ?? 90))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Task label
            VStack(spacing: 6) {
                Text("FOCUSING ON")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(2)

                if let task {
                    Text(task.title)
                        .font(.system(size: 22, weight: .semibold))
                        .multilineTextAlignment(.center)
                    if !task.sender.isEmpty && task.sender != "System" {
                        Text("from \(task.sender)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No active task")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 460)

            Spacer().frame(height: 52)

            // Ring + time
            ZStack {
                Circle()
                    .stroke(Color(.separatorColor), lineWidth: 12)
                    .frame(width: 260, height: 260)

                Circle()
                    .trim(from: 0, to: session.progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 260, height: 260)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: session.progress)

                VStack(spacing: 4) {
                    Text(session.timeString)
                        .font(.system(size: 52, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(stateLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer().frame(height: 56)

            // Controls
            HStack(spacing: 32) {
                macOSRoundButton(icon: "stop.fill", size: 48, dim: session.phase == .idle) {
                    session.stop()
                }

                macOSRoundButton(
                    icon: session.phase == .running ? "pause.fill" : "play.fill",
                    size: 64,
                    tint: ringColor,
                    prominent: true
                ) {
                    session.phase == .running ? session.pause() : session.start()
                }

                macOSRoundButton(icon: "forward.end.fill", size: 48) { onComplete() }
            }

            Spacer().frame(height: 44)

            // Info strip
            HStack(spacing: 0) {
                infoCell("Session",  "1 of 3")
                Divider().frame(height: 28).padding(.horizontal, 24)
                infoCell("Duration", task.map { "\($0.estimatedMinutes) min" } ?? "90 min")
                Divider().frame(height: 28).padding(.horizontal, 24)
                infoCell("Ends",     endTime)
            }
            .padding(.horizontal, 32).padding(.vertical, 16)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 400)

            Spacer()
        }
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .idle && session.didFinishNaturally {
                showNextPrompt = true
            }
        }
        .overlay(alignment: .bottom) {
            if showNextPrompt {
                HStack(spacing: 12) {
                    Text("Want another task?")
                        .font(.system(size: 13, weight: .medium))
                    Button("Dish Me Up") { showNextPrompt = false; onComplete() }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.small)
                    Button("Done") { showNextPrompt = false; onComplete() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separatorColor), lineWidth: 0.5))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.25), value: showNextPrompt)
            }
        }
        .navigationTitle("Focus")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ringColor: Color {
        session.phase == .paused ? .orange : .blue
    }

    private var stateLabel: String {
        switch session.phase {
        case .idle:    "ready"
        case .running: "remaining"
        case .paused:  "paused"
        }
    }

    private var endTime: String {
        let end = Date().addingTimeInterval(TimeInterval(session.secondsRemaining))
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"
        return fmt.string(from: end)
    }

    @ViewBuilder
    private func macOSRoundButton(
        icon: String,
        size: CGFloat,
        tint: Color = Color(.controlColor),
        prominent: Bool = false,
        dim: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(prominent ? tint : Color(.controlBackgroundColor))
                    .frame(width: size, height: size)
                    .shadow(color: prominent ? tint.opacity(0.3) : .clear, radius: 10, y: 3)
                Image(systemName: icon)
                    .font(.system(size: size * 0.33, weight: .medium))
                    .foregroundStyle(prominent ? .white : (dim ? Color(.disabledControlTextColor) : Color(.controlTextColor)))
            }
        }
        .buttonStyle(.plain)
        .disabled(dim)
    }

    @ViewBuilder
    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Timer model

enum FocusPhase { case idle, running, paused }

@Observable @MainActor
final class FocusSession {
    var secondsRemaining: Int
    var phase: FocusPhase = .idle
    var didFinishNaturally = false

    private let total: Int
    private var task: Task<Void, Never>?

    init(minutes: Int) {
        total = minutes * 60
        secondsRemaining = minutes * 60
    }

    var progress: Double { 1.0 - Double(secondsRemaining) / Double(total) }

    var timeString: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    func start() {
        phase = .running
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if self.secondsRemaining > 0 {
                    self.secondsRemaining -= 1
                } else {
                    self.didFinishNaturally = true
                    self.phase = .idle
                    return
                }
            }
        }
    }

    func pause() { task?.cancel(); task = nil; phase = .paused }

    func stop() {
        task?.cancel(); task = nil
        phase = .idle
        secondsRemaining = total
        didFinishNaturally = false
    }
}
