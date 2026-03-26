import AppKit
import Foundation
import Observation
import UserNotifications

struct FocusBreakPrompt: Equatable {
    let taskTitle: String
    let durationMinutes: Int
    let isLongBreak: Bool

    var title: String {
        isLongBreak ? "Take a long break (15 min)?" : "Take a short break (5 min)?"
    }

    var message: String {
        "\(taskTitle) is done. Reset before the next block."
    }
}

@MainActor
@Observable
final class FocusTimerModel {
    private enum SessionKind {
        case task(TaskItem)
        case shortBreak
        case longBreak

        var title: String {
            switch self {
            case .task(let task):
                return task.title
            case .shortBreak:
                return "Short break"
            case .longBreak:
                return "Long break"
            }
        }
    }

    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var onTaskCompletion: ((TaskItem) -> Int)?

    private var sessionKind: SessionKind?
    var currentTask: TaskItem?
    var secondsRemaining = 0
    var totalSeconds = 0
    var isRunning = false
    var pomodoroCount = 0
    var breakPrompt: FocusBreakPrompt?

    init() {
        requestNotificationAuthorization()
    }

    deinit {
        countdownTask?.cancel()
    }

    var isVisible: Bool {
        sessionKind != nil
    }

    var sessionTitle: String {
        sessionKind?.title ?? currentTask?.title ?? "Focus session"
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let completed = totalSeconds - secondsRemaining
        return max(0, min(1, Double(completed) / Double(totalSeconds)))
    }

    func start(for task: TaskItem, onCompletion: @escaping (TaskItem) -> Int) {
        reset(clearBreakPrompt: true)
        sessionKind = .task(task)
        currentTask = task
        pomodoroCount = task.pomodoroCount
        totalSeconds = TimedPreferences.focusSessionMinutes * 60
        secondsRemaining = totalSeconds
        isRunning = true
        onTaskCompletion = onCompletion
        startCountdownLoop()
    }

    func startSuggestedBreak() {
        guard let breakPrompt else { return }
        startBreak(minutes: breakPrompt.durationMinutes, isLongBreak: breakPrompt.isLongBreak)
    }

    func startBreak(minutes: Int, isLongBreak: Bool) {
        countdownTask?.cancel()
        currentTask = nil
        onTaskCompletion = nil
        breakPrompt = nil
        pomodoroCount = 0
        totalSeconds = max(1, minutes) * 60
        secondsRemaining = totalSeconds
        isRunning = true
        sessionKind = isLongBreak ? .longBreak : .shortBreak
        startCountdownLoop()
    }

    func togglePause() {
        if isRunning {
            pause()
        } else if sessionKind != nil && secondsRemaining > 0 {
            resume()
        }
    }

    func stop(clearBreakPrompt: Bool = true) {
        reset(clearBreakPrompt: clearBreakPrompt)
    }

    private func pause() {
        isRunning = false
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func resume() {
        guard sessionKind != nil, secondsRemaining > 0 else { return }
        isRunning = true
        startCountdownLoop()
    }

    private func startCountdownLoop() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.tick()
            }
        }
    }

    private func tick() {
        guard isRunning, secondsRemaining > 0 else { return }
        secondsRemaining -= 1

        if secondsRemaining == 0 {
            finishSession()
        }
    }

    private func finishSession() {
        countdownTask?.cancel()
        countdownTask = nil
        isRunning = false
        secondsRemaining = 0
        NSSound.beep()

        switch sessionKind {
        case .task(let task):
            let updatedPomodoroCount = onTaskCompletion?(task) ?? (pomodoroCount + 1)
            pomodoroCount = updatedPomodoroCount
            // Long breaks are per-task, matching the story acceptance wording.
            let needsLongBreak = updatedPomodoroCount.isMultiple(of: 4)
            breakPrompt = FocusBreakPrompt(
                taskTitle: task.title,
                durationMinutes: needsLongBreak ? 15 : 5,
                isLongBreak: needsLongBreak
            )
            postNotification(
                title: "Pomodoro complete",
                body: needsLongBreak
                    ? "\(task.title) finished. Take a 15 minute break."
                    : "\(task.title) finished. Take a 5 minute break."
            )
        case .shortBreak, .longBreak:
            let title = sessionTitle
            postNotification(title: "Break finished", body: "\(title) is over. Back to work.")
            reset(clearBreakPrompt: true)
        case nil:
            reset(clearBreakPrompt: true)
        }
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func reset(clearBreakPrompt: Bool) {
        countdownTask?.cancel()
        countdownTask = nil
        sessionKind = nil
        currentTask = nil
        totalSeconds = 0
        secondsRemaining = 0
        isRunning = false
        pomodoroCount = 0
        onTaskCompletion = nil
        if clearBreakPrompt {
            breakPrompt = nil
        }
    }
}
