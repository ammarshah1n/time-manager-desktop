// MockModels.swift — Timed iOS Mockup
// Drop into a new iOS 17+ Xcode project to preview all screens.
// Not compiled in the main macOS target.

import SwiftUI

// MARK: - Email

struct MockEmail: Identifiable {
    let id = UUID()
    let sender: String
    let subject: String
    let preview: String
    let timestamp: Date
    let avatarColor: Color
    var isRead: Bool
    var isSnoozed = false
    var hasTimeBlock = false

    var initials: String {
        sender.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var relativeTime: String {
        let diff = Date().timeIntervalSince(timestamp)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        let fmt = DateFormatter()
        fmt.dateFormat = diff < 7 * 86400 ? "EEE" : "MMM d"
        return fmt.string(from: timestamp)
    }
}

extension MockEmail {
    static let samples: [MockEmail] = [
        MockEmail(
            sender: "Sarah Chen",
            subject: "Q4 Strategy Review",
            preview: "Following up on our discussion — can we block 90 minutes this week to go through the numbers?",
            timestamp: Date().addingTimeInterval(-240),
            avatarColor: .blue,
            isRead: false
        ),
        MockEmail(
            sender: "James Park",
            subject: "Design System v2 — ready for review",
            preview: "The new component library is ready. Two hours should cover everything. Loom walkthrough attached.",
            timestamp: Date().addingTimeInterval(-3600),
            avatarColor: .purple,
            isRead: false,
            hasTimeBlock: true
        ),
        MockEmail(
            sender: "Notion",
            subject: "Your weekly digest",
            preview: "3 pages were updated in your workspace this week. Here's what changed.",
            timestamp: Date().addingTimeInterval(-7200),
            avatarColor: .gray,
            isRead: true
        ),
        MockEmail(
            sender: "Alex Morgan",
            subject: "Budget approval — needs sign-off",
            preview: "Contractor invoices need approval before EOD Friday. Two items flagged for your attention.",
            timestamp: Date().addingTimeInterval(-86400),
            avatarColor: .orange,
            isRead: true
        ),
        MockEmail(
            sender: "GitHub",
            subject: "[pffteam/timed] PR: auth-refactor",
            preview: "ammarshah1n opened pull request #47: Refactor auth middleware to use JWT rotation.",
            timestamp: Date().addingTimeInterval(-172800),
            avatarColor: Color(.systemGreen),
            isRead: true
        ),
        MockEmail(
            sender: "Lena Kovacs",
            subject: "Client onboarding checklist",
            preview: "Revised onboarding checklist attached. Please review before Thursday's call at 2pm.",
            timestamp: Date().addingTimeInterval(-259200),
            avatarColor: .teal,
            isRead: true
        ),
        MockEmail(
            sender: "Stripe",
            subject: "Invoice #1042 paid — $3,200",
            preview: "Payment received from Facilitated Pty Ltd. Funds will appear in your account within 2 business days.",
            timestamp: Date().addingTimeInterval(-345600),
            avatarColor: Color(.systemIndigo),
            isRead: true
        ),
    ]
}

// MARK: - Time Block

struct MockTimeBlock: Identifiable {
    let id = UUID()
    let emailSubject: String
    let sender: String
    let startHour: Double   // e.g. 9.5 = 9:30 am
    let durationHours: Double
    let color: Color
    let weekdayIndex: Int   // 0 = Monday … 6 = Sunday in displayed week

    var startTimeLabel: String { formatHour(startHour) }
    var endTimeLabel: String   { formatHour(startHour + durationHours) }
    var durationLabel: String  {
        let mins = Int(durationHours * 60)
        if mins < 60 { return "\(mins) min" }
        if mins == 60 { return "1 hr" }
        let h = mins / 60; let m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h)h \(m)m"
    }

    private func formatHour(_ h: Double) -> String {
        let hour = Int(h)
        let min  = Int((h - Double(hour)) * 60)
        let suffix = hour >= 12 ? "pm" : "am"
        let display = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return min == 0 ? "\(display)\(suffix)" : "\(display):\(String(format: "%02d", min))\(suffix)"
    }
}

extension MockTimeBlock {
    static let samples: [MockTimeBlock] = [
        MockTimeBlock(emailSubject: "Q4 Strategy Review",      sender: "Sarah Chen",  startHour: 9.0,  durationHours: 1.5, color: .blue,   weekdayIndex: 0),
        MockTimeBlock(emailSubject: "Design System v2",        sender: "James Park",  startHour: 11.0, durationHours: 2.0, color: .purple, weekdayIndex: 0),
        MockTimeBlock(emailSubject: "Budget Approval",         sender: "Alex Morgan", startHour: 14.0, durationHours: 0.5, color: .orange, weekdayIndex: 0),
        MockTimeBlock(emailSubject: "Auth PR Review",          sender: "GitHub",      startHour: 16.0, durationHours: 1.0, color: Color(.systemGreen), weekdayIndex: 0),
        MockTimeBlock(emailSubject: "Client Onboarding",       sender: "Lena Kovacs", startHour: 9.0,  durationHours: 0.5, color: .teal,   weekdayIndex: 1),
        MockTimeBlock(emailSubject: "Q4 Strategy Prep",        sender: "Sarah Chen",  startHour: 13.0, durationHours: 2.0, color: .blue,   weekdayIndex: 2),
        MockTimeBlock(emailSubject: "Design Review Follow-up", sender: "James Park",  startHour: 10.0, durationHours: 1.0, color: .purple, weekdayIndex: 3),
    ]
}

// MARK: - Email Account (Settings)

struct MockEmailAccount: Identifiable {
    let id = UUID()
    let address: String
    let provider: String
    let icon: String
    let color: Color
    var isConnected: Bool
}

extension MockEmailAccount {
    static let samples: [MockEmailAccount] = [
        MockEmailAccount(address: "ammar@pff.org",       provider: "Outlook / Microsoft 365", icon: "envelope.badge.fill", color: .blue, isConnected: true),
        MockEmailAccount(address: "me@ammarshah.com",    provider: "Gmail",                   icon: "envelope.fill",       color: .red,  isConnected: false),
    ]
}
