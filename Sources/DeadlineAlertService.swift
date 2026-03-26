import AppKit
import Foundation
import UserNotifications

@MainActor
final class DeadlineAlertService {
    static let shared = DeadlineAlertService()

    private struct AlertCheckpoint {
        let hoursBeforeDeadline: Int

        var identifierSuffix: String { "\(hoursBeforeDeadline)h" }
        var offset: TimeInterval { TimeInterval(hoursBeforeDeadline * 3600) }
        var titleText: String { "due in \(hoursBeforeDeadline)h" }
    }

    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationPrefix = "timed.deadline"
    private let checkpoints = [
        AlertCheckpoint(hoursBeforeDeadline: 24),
        AlertCheckpoint(hoursBeforeDeadline: 4),
        AlertCheckpoint(hoursBeforeDeadline: 1)
    ]

    private var rescheduleTask: Task<Void, Never>?

    func requestAuthorizationIfNeeded() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleAlerts(for tasks: [TaskItem], now: Date = .now) {
        refresh(tasks: tasks, now: now, shouldRescheduleNotifications: true)
    }

    func refresh(tasks: [TaskItem], now: Date = .now, shouldRescheduleNotifications: Bool) {
        updateDockBadge(for: tasks, now: now)

        guard shouldRescheduleNotifications else { return }

        let snapshot = tasks
        rescheduleTask?.cancel()
        rescheduleTask = Task { [snapshot] in
            await rescheduleNotifications(for: snapshot, now: now)
        }
    }

    func updateDockBadge(for tasks: [TaskItem], now: Date = .now) {
        // Overdue tasks stay badged because they are more urgent than "within 24h".
        let dueSoonCount = tasks.filter { task in
            guard !task.isCompleted, let dueDate = task.dueDate else { return false }
            return dueDate.timeIntervalSince(now) <= 24 * 3600
        }.count

        NSApp.dockTile.badgeLabel = dueSoonCount > 0 ? "\(dueSoonCount)" : nil
        NSApp.dockTile.display()
    }

    private func rescheduleNotifications(for tasks: [TaskItem], now: Date) async {
        guard !Task.isCancelled else { return }

        let managedIDs = await existingManagedNotificationIdentifiers()
        if !managedIDs.isEmpty {
            let identifiers = Array(managedIDs)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        for task in tasks where !task.isCompleted && task.dueDate != nil {
            guard !Task.isCancelled else { return }
            await scheduleNotifications(for: task, now: now)
        }
    }

    private func scheduleNotifications(for task: TaskItem, now: Date) async {
        guard let dueDate = task.dueDate else { return }

        let taskNotificationIDs = checkpoints.map { identifier(for: task, checkpoint: $0) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: taskNotificationIDs)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: taskNotificationIDs)

        for checkpoint in checkpoints {
            let fireDate = dueDate.addingTimeInterval(-checkpoint.offset)

            // Skip elapsed checkpoints instead of trying to retro-schedule an expired alert.
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(task.title) \(checkpoint.titleText)"
            content.body = "\(task.subject) deadline: \(dueDate.formatted(date: .abbreviated, time: .shortened))"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier(for: task, checkpoint: checkpoint),
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: triggerComponents(for: fireDate),
                    repeats: false
                )
            )

            do {
                try await add(request)
            } catch {
                continue
            }
        }
    }

    private func existingManagedNotificationIdentifiers() async -> Set<String> {
        async let pendingIDs = pendingNotificationIdentifiers()
        async let deliveredIDs = deliveredNotificationIdentifiers()
        return await pendingIDs.union(deliveredIDs)
    }

    private func pendingNotificationIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                let identifiers = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix(self.notificationPrefix) }
                continuation.resume(returning: Set(identifiers))
            }
        }
    }

    private func deliveredNotificationIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            notificationCenter.getDeliveredNotifications { notifications in
                let identifiers = notifications
                    .map(\.request.identifier)
                    .filter { $0.hasPrefix(self.notificationPrefix) }
                continuation.resume(returning: Set(identifiers))
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func identifier(for task: TaskItem, checkpoint: AlertCheckpoint) -> String {
        "\(notificationPrefix).\(task.id).\(checkpoint.identifierSuffix)"
    }

    private func triggerComponents(for date: Date) -> DateComponents {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = Calendar.current
        components.timeZone = Calendar.current.timeZone
        return components
    }
}
