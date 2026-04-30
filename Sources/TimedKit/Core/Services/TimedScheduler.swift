// TimedScheduler.swift — Timed Core
// Notification scheduling for task transitions, meeting prep, and focus nudges.
// Uses UNUserNotificationCenter for local notifications on macOS.

import Foundation
@preconcurrency import UserNotifications
import os

// MARK: - Protocol

protocol TimedScheduling: Sendable {
    /// Legacy: suggest calendar blocks from emails
    func suggestBlocks(for emails: [EmailMessage]) -> [CalendarBlock]
    /// Schedule notifications for a generated plan
    func schedulePlanNotifications(_ items: [PlanItem], workStartHour: Int, calendarBlocks: [CalendarBlock]) async
    /// Cancel all previously scheduled Timed notifications
    func cancelAllNotifications() async
    /// Request notification permission if not already granted
    func requestPermissionIfNeeded() async -> Bool
}

// MARK: - Notification categories

private enum NotificationCategory {
    static let taskTransition  = "TIMED_TASK_TRANSITION"
    static let meetingPrep     = "TIMED_MEETING_PREP"
    static let focusNudge      = "TIMED_FOCUS_NUDGE"
}

private let notificationPrefix = "timed."

// MARK: - TimedSchedulerService

struct TimedSchedulerService: TimedScheduling {

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private let logger = Logger(subsystem: "com.timed.scheduler", category: "notifications")

    // MARK: - Legacy block suggestion (kept for backward compat)

    func suggestBlocks(for emails: [EmailMessage]) -> [CalendarBlock] {
        let classifier = EmailClassifierService()
        var blocks: [CalendarBlock] = []
        var currentTime = Date()

        for email in emails {
            let category = classifier.classify(email, senderRules: [])
            guard category == .actionRequired else { continue }

            let block = CalendarBlock(
                id: UUID(),
                title: "Focus: \(email.subject)",
                startTime: currentTime,
                endTime: currentTime.addingTimeInterval(30 * 60),
                sourceEmailId: email.id,
                category: .focus
            )
            blocks.append(block)
            currentTime = block.endTime
        }

        return blocks
    }

    // MARK: - Permission

    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    logger.info("Notification permission granted")
                    await registerCategories()
                } else {
                    logger.info("Notification permission denied by user")
                }
                return granted
            } catch {
                logger.error("Failed to request notification permission: \(error.localizedDescription)")
                return false
            }
        case .denied, .ephemeral:
            logger.info("Notification permission denied — skipping scheduling")
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Schedule plan notifications

    func schedulePlanNotifications(
        _ items: [PlanItem],
        workStartHour: Int,
        calendarBlocks: [CalendarBlock]
    ) async {
        // Ensure permission
        guard await requestPermissionIfNeeded() else { return }

        // Cancel existing Timed notifications before rescheduling
        await cancelAllNotifications()

        let now = Date()
        let cal = Calendar.current

        // Compute scheduled start times from plan item order
        // Start from workStartHour today, or now if already past start
        let todayStart = cal.startOfDay(for: now)
        guard let workStart = cal.date(bySettingHour: workStartHour, minute: 0, second: 0, of: todayStart) else { return }
        var cursor = max(now, workStart)

        // Round cursor up to next 5-min boundary
        let minute = cal.component(.minute, from: cursor)
        let remainder = minute % 5
        if remainder > 0 {
            cursor = cal.date(byAdding: .minute, value: 5 - remainder, to: cursor) ?? cursor
        }

        var scheduledCount = 0

        for item in items {
            let taskStart = cursor
            let duration = TimeInterval(item.estimatedMinutes * 60)
            let buffer = TimeInterval(item.bufferAfterMinutes * 60)

            // Only schedule future notifications
            if taskStart > now {
                let content = UNMutableNotificationContent()
                content.title = "Time to start"
                content.body = item.task.title
                content.categoryIdentifier = NotificationCategory.taskTransition
                content.sound = .default
                content.threadIdentifier = "timed-plan"

                let interval = taskStart.timeIntervalSince(now)
                if interval > 0 {
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: "\(notificationPrefix)task.\(item.task.id.uuidString)",
                        content: content,
                        trigger: trigger
                    )
                    do {
                        try await center.add(request)
                        scheduledCount += 1
                    } catch {
                        logger.error("Failed to schedule task notification: \(error.localizedDescription)")
                    }
                }
            }

            cursor = cursor.addingTimeInterval(duration + buffer)
        }

        // Meeting prep reminders — 10 minutes before each non-focus calendar block
        let today = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return }

        let todayMeetings = calendarBlocks.filter { block in
            block.startTime >= today && block.startTime < tomorrow
                && block.category != .focus
                && block.category != .break
        }

        for meeting in todayMeetings {
            let prepTime = meeting.startTime.addingTimeInterval(-10 * 60)  // 10 min before
            guard prepTime > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Meeting in 10 min"
            content.body = meeting.title
            content.categoryIdentifier = NotificationCategory.meetingPrep
            content.sound = .default
            content.threadIdentifier = "timed-meetings"

            let interval = prepTime.timeIntervalSince(now)
            if interval > 0 {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(notificationPrefix)meeting.\(meeting.id.uuidString)",
                    content: content,
                    trigger: trigger
                )
                do {
                    try await center.add(request)
                    scheduledCount += 1
                } catch {
                    logger.error("Failed to schedule meeting notification: \(error.localizedDescription)")
                }
            }
        }

        // Focus nudge: if the first task is scheduled in the future and user hasn't started,
        // send a gentle nudge 5 minutes after the first task's scheduled start
        if let firstItem = items.first {
            let firstTaskStart = max(now, workStart)
            let nudgeTime = firstTaskStart.addingTimeInterval(5 * 60)
            if nudgeTime > now {
                let content = UNMutableNotificationContent()
                content.title = "Ready to focus?"
                content.body = "Your first task is \"\(firstItem.task.title)\" — start a focus session."
                content.categoryIdentifier = NotificationCategory.focusNudge
                content.sound = .default
                content.threadIdentifier = "timed-focus"

                let interval = nudgeTime.timeIntervalSince(now)
                if interval > 0 {
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: "\(notificationPrefix)focus.nudge",
                        content: content,
                        trigger: trigger
                    )
                    do {
                        try await center.add(request)
                        scheduledCount += 1
                    } catch {
                        logger.error("Failed to schedule focus nudge: \(error.localizedDescription)")
                    }
                }
            }
        }

        logger.info("Scheduled \(scheduledCount) notifications for today's plan")
    }

    // MARK: - Cancel

    func cancelAllNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let timedIds = pending
            .filter { $0.identifier.hasPrefix(notificationPrefix) }
            .map(\.identifier)
        if !timedIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: timedIds)
            logger.info("Cancelled \(timedIds.count) pending Timed notifications")
        }
    }

    // MARK: - Categories

    private func registerCategories() async {
        let taskCategory = UNNotificationCategory(
            identifier: NotificationCategory.taskTransition,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let meetingCategory = UNNotificationCategory(
            identifier: NotificationCategory.meetingPrep,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let focusCategory = UNNotificationCategory(
            identifier: NotificationCategory.focusNudge,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([taskCategory, meetingCategory, focusCategory])
    }
}
