// FocusPane.swift — Timed macOS Preview
// Circular countdown. Focuses on a single TimedTask.
// @Observable timer drives the arc + digit display.
// Persists sessions to DataStore. Fires completion notifications.

import SwiftUI
import Dependencies
@preconcurrency import UserNotifications

struct FocusPane: View {
    let task: TimedTask?
    let onComplete: () -> Void
    /// Called with (taskId, actualMinutes) when a focus session ends — feeds the Bayesian estimation loop
    var onSessionComplete: ((UUID, Int) -> Void)?
    @State private var session: FocusSession
    @State private var showNextPrompt = false
    @State private var showResumePrompt = false
    @State private var staleRecord: FocusSessionRecord? = nil

    init(task: TimedTask?, onComplete: @escaping () -> Void, onSessionComplete: ((UUID, Int) -> Void)? = nil) {
        self.task = task
        self.onComplete = onComplete
        self.onSessionComplete = onSessionComplete
        self._session = State(initialValue: FocusSession(minutes: task?.estimatedMinutes ?? 90))
    }

    var body: some View {
        Group {
            if task != nil {
                focusTimerView
            } else {
                focusEmptyState
            }
        }
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .idle && session.didFinishNaturally {
                persistSessionEnd(completed: true)
                sendCompletionNotification()
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
                        .tint(Color.Timed.accent)
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
        .alert("Resume Session?", isPresented: $showResumePrompt) {
            Button("Resume") {
                if let record = staleRecord {
                    let elapsed = record.totalSeconds - session.secondsRemaining
                    session.pomodoroIndex = record.pomodoroIndex
                    // Session is already at correct remaining time from init
                    persistResume()
                    session.start()
                }
                staleRecord = nil
            }
            Button("Discard", role: .destructive) {
                discardStaleSession()
                staleRecord = nil
            }
        } message: {
            Text("You have an unfinished focus session. Would you like to resume it?")
        }
        .task {
            await checkForUnfinishedSession()
            await loadCompletedCount()
            FocusNotificationManager.requestPermissionIfNeeded()
        }
        .navigationTitle("Focus")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Timer view (has task)

    private var focusTimerView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Task label
            VStack(spacing: 6) {
                Text("FOCUSING ON")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.Timed.secondaryText)
                    .tracking(2)

                if let task {
                    Text(task.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.Timed.primaryText)
                        .multilineTextAlignment(.center)
                    if !task.sender.isEmpty && task.sender != "System" {
                        Text("from \(task.sender)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.Timed.secondaryText)
                    }
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
                        .foregroundStyle(Color.Timed.secondaryText)
                }
            }

            Spacer().frame(height: 56)

            // Controls
            HStack(spacing: 32) {
                macOSRoundButton(icon: "stop.fill", size: 48, dim: session.phase == .idle) {
                    session.stop()
                    persistSessionEnd(completed: false)
                }

                macOSRoundButton(
                    icon: session.phase == .running ? "pause.fill" : "play.fill",
                    size: 64,
                    tint: ringColor,
                    prominent: true
                ) {
                    if session.phase == .running {
                        session.pause()
                        persistPause()
                    } else {
                        if session.phase == .idle {
                            persistSessionStart()
                        } else {
                            persistResume()
                        }
                        session.start()
                    }
                }

                macOSRoundButton(icon: "forward.end.fill", size: 48) {
                    persistSessionEnd(completed: false)
                    onComplete()
                }
            }

            Spacer().frame(height: 44)

            // Info strip
            HStack(spacing: 0) {
                infoCell("Session", "\(session.pomodoroIndex) of \(pomodoroTarget)")
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
    }

    // MARK: - Empty state (no task)

    private var focusEmptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                // Timer preview ring (static)
                ZStack {
                    Circle()
                        .stroke(Color.Timed.hairline, lineWidth: 10)
                        .frame(width: 180, height: 180)

                    VStack(spacing: 4) {
                        Text(defaultSessionLabel)
                            .font(.system(size: 36, weight: .thin, design: .rounded))
                            .foregroundStyle(Color.Timed.tertiaryText)
                            .monospacedDigit()
                        Text("default session")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.Timed.tertiaryText)
                    }
                }

                Spacer().frame(height: 8)

                Text("Pick a task and focus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.Timed.primaryText)
                Text("Select a task from your Today view to start a focus session")
                    .font(.subheadline)
                    .foregroundStyle(Color.Timed.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                Spacer().frame(height: 8)

                Button {
                    onComplete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Go to Today")
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Timed.accent)
            }

            Spacer()
        }
    }

    private var defaultSessionLabel: String {
        let mins = task?.estimatedMinutes ?? 90
        return String(format: "%02d:%02d", mins / 60, mins % 60)
    }

    // MARK: - Pomodoro

    @AppStorage("prefs.focus.pomodoroTarget") private var pomodoroTarget: Int = 4

    // MARK: - Appearance

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

    // MARK: - Persistence

    private func persistSessionStart() {
        let completedToday = session.pomodoroIndex - 1  // current index is 1-based "next"
        let record = FocusSessionRecord(
            id: UUID(),
            taskId: task?.id,
            startedAt: Date(),
            pausedAt: nil,
            endedAt: nil,
            totalSeconds: session.total,
            wasCompleted: false,
            pomodoroIndex: completedToday + 1
        )
        session.activeRecordId = record.id
        Task {
            try? await DataStore.shared.saveActiveFocusSession(record)
        }
    }

    private func persistPause() {
        Task {
            guard var record = try? await DataStore.shared.loadActiveFocusSession() else { return }
            record.pausedAt = Date()
            try? await DataStore.shared.saveActiveFocusSession(record)
        }
    }

    private func persistResume() {
        Task {
            guard var record = try? await DataStore.shared.loadActiveFocusSession() else { return }
            record.pausedAt = nil
            try? await DataStore.shared.saveActiveFocusSession(record)
        }
    }

    private func persistSessionEnd(completed: Bool) {
        Task {
            let activeRecord = try? await DataStore.shared.loadActiveFocusSession()
            guard var record = activeRecord else { return }
            record.endedAt = Date()
            record.wasCompleted = completed
            record.totalSeconds = session.total - session.secondsRemaining

            // Append to history
            var history = (try? await DataStore.shared.loadFocusSessions()) ?? []
            history.append(record)
            try? await DataStore.shared.saveFocusSessions(history)

            // Clear active session
            try? await DataStore.shared.saveActiveFocusSession(nil)

            // Feed actual_minutes back for Bayesian estimation loop
            if let taskId = record.taskId {
                let actualMinutes = max(1, record.totalSeconds / 60)
                onSessionComplete?(taskId, actualMinutes)

                // Update bucket estimates (EMA posterior update)
                if let task = self.task {
                    var estimates = (try? await DataStore.shared.loadBucketEstimates()) ?? [:]
                    let bucketKey = task.bucket.rawValue
                    var est = estimates[bucketKey] ?? BucketEstimate(
                        meanMinutes: Double(task.estimatedMinutes), sampleCount: 0, lastUpdatedAt: Date()
                    )
                    let alpha = est.sampleCount < 20 ? 1.0 / Double(est.sampleCount + 1) : 0.15
                    est.meanMinutes = (1 - alpha) * est.meanMinutes + alpha * Double(actualMinutes)
                    est.sampleCount += 1
                    est.lastUpdatedAt = Date()
                    estimates[bucketKey] = est
                    try? await DataStore.shared.saveBucketEstimates(estimates)
                }

                // Sync actual_minutes to Supabase (triggers DB estimation_history trigger)
                @Dependency(\.supabaseClient) var supa
                try? await supa.updateTaskStatus(taskId, "done", actualMinutes)
            }

            // Update Pomodoro count if completed
            if completed {
                await loadCompletedCount()
            }
        }
    }

    private func checkForUnfinishedSession() async {
        guard let record = try? await DataStore.shared.loadActiveFocusSession() else { return }
        staleRecord = record
        showResumePrompt = true
    }

    private func discardStaleSession() {
        Task {
            // Move to history as incomplete
            if var record = try? await DataStore.shared.loadActiveFocusSession() {
                record.endedAt = Date()
                record.wasCompleted = false
                var history = (try? await DataStore.shared.loadFocusSessions()) ?? []
                history.append(record)
                try? await DataStore.shared.saveFocusSessions(history)
            }
            try? await DataStore.shared.saveActiveFocusSession(nil)
        }
    }

    private func loadCompletedCount() async {
        let history = (try? await DataStore.shared.loadFocusSessions()) ?? []
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayCompleted = history.filter { record in
            record.wasCompleted && record.startedAt >= startOfDay
        }.count
        session.pomodoroIndex = todayCompleted + 1
    }

    // MARK: - Notifications

    private func sendCompletionNotification() {
        let minutes = (session.total - session.secondsRemaining) / 60
        let taskName = task?.title ?? "your task"
        FocusNotificationManager.sendCompletion(minutes: minutes, taskName: taskName)
    }

    // MARK: - Subviews

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
    var pomodoroIndex: Int = 1
    var activeRecordId: UUID? = nil

    let total: Int
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

// MARK: - Notification Manager

enum FocusNotificationManager {

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    TimedLogger.focus.error("Notification permission error: \(error.localizedDescription, privacy: .public)")
                } else {
                    TimedLogger.focus.info("Notification permission \(granted ? "granted" : "denied", privacy: .public)")
                }
            }
        }
    }

    static func sendCompletion(minutes: Int, taskName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Focus Session Complete"
        content.body = "You focused for \(minutes) minute\(minutes == 1 ? "" : "s") on \(taskName)"
        content.sound = .default
        content.categoryIdentifier = "FOCUS_COMPLETE"

        let request = UNNotificationRequest(
            identifier: "focus-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil  // fire immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                TimedLogger.focus.error("Failed to send focus notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
