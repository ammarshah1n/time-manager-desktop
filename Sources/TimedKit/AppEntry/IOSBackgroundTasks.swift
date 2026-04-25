// IOSBackgroundTasks.swift — Timed Core / AppEntry (iOS only)
// BGTaskScheduler bindings for opportunistic email/calendar refresh + nightly
// synthesis pings while the app is suspended.
//
// Identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers):
//   com.timed.app.bgRefresh.email        — BGAppRefreshTask, ~15min minimum
//   com.timed.app.bgProcessing.synthesis — BGProcessingTask, plugged-in + idle
//
// Schedule next run inside each handler. iOS decides actual fire time —
// it can be longer than requested, sometimes never (battery / usage budget).

#if os(iOS)
import BackgroundTasks
import Foundation

@MainActor
public enum TimedBackgroundTasks {

    public static let emailRefreshIdentifier   = "com.timed.app.bgRefresh.email"
    public static let synthesisProcessingId    = "com.timed.app.bgProcessing.synthesis"

    /// Optional hook the main app installs at launch — receives a
    /// `BGAppRefreshTask` to drive a single email-delta sync. Defaults to a
    /// no-op so the handler still completes cleanly when no provider is
    /// installed (signed-out, voice-fix-in-flight, etc.).
    public static var emailRefreshWorker: @Sendable (BGAppRefreshTask) async -> Void = { task in
        task.setTaskCompleted(success: true)
    }

    public static var synthesisProcessingWorker: @Sendable (BGProcessingTask) async -> Void = { task in
        task.setTaskCompleted(success: true)
    }

    /// Call once during app launch (before scene becomes active).
    public static func registerHandlers() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: emailRefreshIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task: task, worker: emailRefreshWorker) {
                scheduleNextEmailRefresh()
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: synthesisProcessingId,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            handle(task: task, worker: synthesisProcessingWorker) {
                scheduleNextSynthesisProcessing()
            }
        }
    }

    /// Schedule the next email refresh window.
    public static func scheduleNextEmailRefresh(after seconds: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: emailRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Schedule the next synthesis processing window. Only fires when device
    /// is plugged in + idle.
    public static func scheduleNextSynthesisProcessing(after seconds: TimeInterval = 6 * 60 * 60) {
        let request = BGProcessingTaskRequest(identifier: synthesisProcessingId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Internal

    /// Box that lets us hand non-Sendable system types (BGTask) across an
    /// explicit isolation boundary. Safe because BGTask handlers run on the
    /// main thread per Apple's contract.
    private struct UnsafeSendableBox<T>: @unchecked Sendable {
        let value: T
    }

    private static func handle<T: BGTask>(
        task: T,
        worker: @Sendable @escaping (T) async -> Void,
        scheduleNext: @escaping () -> Void
    ) {
        // Schedule next *before* doing work — even if the work errors, the
        // schedule should advance so we don't fall off the cycle.
        scheduleNext()

        // BGTask is non-Sendable but the system delivers handlers on the
        // main thread per Apple docs. Wrap the task in an @unchecked Sendable
        // box so Swift 6 strict concurrency lets us hand it across the
        // explicit MainActor boundary; the capture is provably safe because
        // we're already on main.
        let box = UnsafeSendableBox(value: task)
        let workTask = Task { @MainActor in
            await worker(box.value)
        }
        task.expirationHandler = { workTask.cancel() }
    }
}
#endif
