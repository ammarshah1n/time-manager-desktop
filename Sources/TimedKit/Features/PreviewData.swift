// PreviewData.swift — Timed macOS
// All mock types and realistic executive-style sample data.

import SwiftUI

// MARK: - Reply medium

enum ReplyMedium: String, CaseIterable, Codable {
    case email     = "Email"
    case whatsApp  = "WhatsApp"
    case other     = "Other"

    var icon: String {
        switch self {
        case .email:    "envelope.fill"
        case .whatsApp: "message.fill"
        case .other:    "bubble.left.fill"
        }
    }

    var color: Color {
        // Monochrome — panes are black/white/grey. No reply-medium tint.
        Color.Timed.labelSecondary
    }
}

// MARK: - Task bucket

enum TaskBucket: String, CaseIterable, Hashable, Codable {
    case reply        = "Reply"
    case action       = "Action"
    case calls        = "Calls"
    case readToday    = "Read Today"
    case readThisWeek = "Read This Week"
    case transit      = "Transit"
    case waiting      = "Waiting"
    case ccFyi        = "CC / FYI"

    var dbValue: String {
        switch self {
        case .reply:        "reply_email"
        case .action:       "action"
        case .calls:        "calls"
        case .readToday:    "read_today"
        case .readThisWeek: "read_this_week"
        case .transit:      "transit"
        case .waiting:      "waiting"
        case .ccFyi:        "cc_fyi"
        }
    }

    static func from(dbValue: String) -> TaskBucket? {
        switch dbValue.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Reply", "reply", "reply_email", "reply_wa", "reply_other":
            .reply
        case "Action", "action":
            .action
        case "Calls", "calls":
            .calls
        case "Read Today", "readToday", "read_today":
            .readToday
        case "Read This Week", "readThisWeek", "read_this_week":
            .readThisWeek
        case "Transit", "transit":
            .transit
        case "Waiting", "waiting":
            .waiting
        case "CC / FYI", "ccFyi", "cc_fyi":
            .ccFyi
        default:
            nil
        }
    }

    var icon: String {
        switch self {
        case .reply:        "arrowshape.turn.up.left.fill"
        case .action:       "bolt.fill"
        case .calls:        "phone.fill"
        case .readToday:    "doc.text.fill"
        case .readThisWeek: "doc.text"
        case .transit:      "car.fill"
        case .waiting:      "clock.arrow.circlepath"
        case .ccFyi:        "envelope.badge.fill"
        }
    }

    var color: Color {
        // Monochrome — buckets are distinguished by icon + label, never colour.
        Color.Timed.labelSecondary
    }

    /// The 8pt `BucketDot` colour — the single Apple-Reminders-style anchor
    /// that's allowed to carry hue. Never use this anywhere larger than the dot.
    /// For row icons / text / fills, use `Color.Timed.labelSecondary`.
    var dotColor: Color {
        switch self {
        case .reply:        Color(.systemBlue)
        case .action:       Color(.systemRed)
        case .calls:        Color(.systemGreen)
        case .readToday:    Color(.systemOrange)
        case .readThisWeek: Color(.systemGray)
        case .transit:      Color(.systemTeal)
        case .waiting:      Color(.systemPurple)
        case .ccFyi:        Color.Timed.labelTertiary
        }
    }

    var reviewCadence: String {
        switch self {
        case .reply:        "2–3× daily"
        case .action:       "Daily plan"
        case .calls:        "Daily"
        case .readToday:    "Today"
        case .readThisWeek: "Weekly slot"
        case .transit:      "In car / plane"
        case .waiting:      "Friday review"
        case .ccFyi:        "Archived"
        }
    }

    /// Title for the empty-state view in TasksPane. Calibrated per bucket so
    /// the copy reads naturally in English — bucket names alone (e.g.,
    /// "No transit", "No reply email") sound terse or wrong. Anchored by the
    /// no-bloat principle in CLAUDE.md and docs/UI-RULES.md.
    var emptyStateTitle: String {
        switch self {
        case .reply:        "Nothing to reply to"
        case .action:       "Nothing to action"
        case .calls:        "No calls"
        case .readToday:    "Nothing to read today"
        case .readThisWeek: "Nothing to read this week"
        case .transit:      "No transit tasks"
        case .waiting:      "Nothing waiting"
        case .ccFyi:        "Nothing archived"
        }
    }

    var staleAfterDays: Int {
        switch self {
        case .reply:        1
        case .action:       3
        case .calls:        2
        case .readToday:    1
        case .readThisWeek: 7
        case .transit:      14
        case .waiting:      7
        case .ccFyi:        14
        }
    }
}

enum TaskManualImportance: String, CaseIterable, Codable, Sendable, Equatable {
    case blue
    case orange
    case red
}

enum TaskSource: String, Codable, Sendable {
    case email, whatsapp, voice, manual
}

enum EstimateSource: String, Codable, Sendable {
    case ai, manual, defaultBucket = "default"
}

struct TaskSection: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let parentSectionId: UUID?
    var title: String
    var canonicalBucketType: String
    var sortOrder: Int
    var colorKey: String?
    var isSystem: Bool
    var isArchived: Bool

    var bucket: TaskBucket? {
        TaskBucket.from(dbValue: canonicalBucketType)
    }

    static let defaultSystemSections: [TaskSection] = {
        let emailId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        return [
            TaskSection(
                id: emailId,
                parentSectionId: nil,
                title: "Email",
                canonicalBucketType: "other",
                sortOrder: 0,
                colorKey: "blue",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111112")!,
                parentSectionId: emailId,
                title: "Reply",
                canonicalBucketType: "reply_email",
                sortOrder: 0,
                colorKey: "blue",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111113")!,
                parentSectionId: emailId,
                title: "Read Today",
                canonicalBucketType: "read_today",
                sortOrder: 1,
                colorKey: "orange",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111114")!,
                parentSectionId: emailId,
                title: "Read This Week",
                canonicalBucketType: "read_this_week",
                sortOrder: 2,
                colorKey: "gray",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111115")!,
                parentSectionId: emailId,
                title: "CC / FYI",
                canonicalBucketType: "cc_fyi",
                sortOrder: 3,
                colorKey: "gray",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111116")!,
                parentSectionId: nil,
                title: "Action",
                canonicalBucketType: "action",
                sortOrder: 1,
                colorKey: "red",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111117")!,
                parentSectionId: nil,
                title: "Calls",
                canonicalBucketType: "calls",
                sortOrder: 2,
                colorKey: "green",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111118")!,
                parentSectionId: nil,
                title: "Transit",
                canonicalBucketType: "transit",
                sortOrder: 3,
                colorKey: "teal",
                isSystem: true,
                isArchived: false
            ),
            TaskSection(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111119")!,
                parentSectionId: nil,
                title: "Waiting",
                canonicalBucketType: "waiting",
                sortOrder: 4,
                colorKey: "purple",
                isSystem: true,
                isArchived: false
            )
        ]
    }()
}

// MARK: - Timed Task

struct TimedTask: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var profileId: UUID? = nil
    let title: String
    let sender: String
    var estimatedMinutes: Int
    let bucket: TaskBucket
    let emailCount: Int
    let receivedAt: Date
    var sectionId: UUID? = nil
    var parentTaskId: UUID? = nil
    var sortOrder: Int? = nil
    var manualImportance: TaskManualImportance? = nil
    var notes: String? = nil
    var isPlanningUnit: Bool? = nil
    // Reply
    var priority: Int? = nil
    var replyMedium: ReplyMedium? = nil
    // Planning flags
    var dueToday: Bool      = false
    var isDoFirst: Bool     = false
    var isTransitSafe: Bool = false
    // Waiting
    var waitingOn: String?  = nil
    var askedDate: Date?    = nil
    var expectedByDate: Date? = nil
    // State
    var isDone: Bool = false
    // AI estimation uncertainty (minutes) — nil means no data
    var estimateUncertainty: Int? = nil
    // Planning: score from PlanningEngine (higher = more important)
    var planScore: Int? = nil
    // Planning: scheduled start time from generated plan
    var scheduledStartTime: Date? = nil
    // Dish Me Up scoring fields
    var urgency: Int = 3          // 1-5, time-sensitivity
    var importance: Int = 3       // 1-5, strategic value
    var energyRequired: String = "medium"  // high/medium/low
    var context: String = "anywhere"       // desk/transit/anywhere
    var skipCount: Int = 0        // times skipped when ranked highly
    var snoozedUntil: Date? = nil
    var source: TaskSource = .manual
    var estimateSource: EstimateSource = .manual
    var estimateBasis: String? = nil

    /// True when uncertainty exceeds 25% of the estimated time
    var isUncertain: Bool {
        guard let u = estimateUncertainty, estimatedMinutes > 0 else { return false }
        return Double(u) > Double(estimatedMinutes) * 0.25
    }

    var timeLabel: String {
        estimatedMinutes < 60
            ? "\(estimatedMinutes)m"
            : (estimatedMinutes % 60 == 0
                ? "\(estimatedMinutes / 60)h"
                : "\(estimatedMinutes / 60)h \(estimatedMinutes % 60)m")
    }

    var daysInQueue: Int {
        max(0, Int(Date().timeIntervalSince(receivedAt) / 86_400))
    }

    var isStale: Bool {
        if let snoozedUntil, snoozedUntil > Date() { return false }
        return !isDone && daysInQueue >= bucket.staleAfterDays
    }

    var isSubtask: Bool {
        parentTaskId != nil
    }

    var effectiveManualImportance: TaskManualImportance {
        manualImportance ?? .blue
    }
}


extension TimedTask {
    enum CodingKeys: String, CodingKey {
        case id
        case profileId
        case title
        case sender
        case estimatedMinutes
        case bucket
        case emailCount
        case receivedAt
        case sectionId
        case parentTaskId
        case sortOrder
        case manualImportance
        case notes
        case isPlanningUnit
        case priority
        case replyMedium
        case dueToday
        case isDoFirst
        case isTransitSafe
        case waitingOn
        case askedDate
        case expectedByDate
        case isDone
        case estimateUncertainty
        case planScore
        case scheduledStartTime
        case urgency
        case importance
        case energyRequired
        case context
        case skipCount
        case snoozedUntil
        case source
        case estimateSource
        case estimateBasis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        profileId = try c.decodeIfPresent(UUID.self, forKey: .profileId)
        title = try c.decode(String.self, forKey: .title)
        sender = try c.decode(String.self, forKey: .sender)
        estimatedMinutes = try c.decode(Int.self, forKey: .estimatedMinutes)
        bucket = try c.decode(TaskBucket.self, forKey: .bucket)
        emailCount = try c.decode(Int.self, forKey: .emailCount)
        receivedAt = try c.decode(Date.self, forKey: .receivedAt)
        sectionId = try c.decodeIfPresent(UUID.self, forKey: .sectionId)
        parentTaskId = try c.decodeIfPresent(UUID.self, forKey: .parentTaskId)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        manualImportance = try c.decodeIfPresent(TaskManualImportance.self, forKey: .manualImportance)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        isPlanningUnit = try c.decodeIfPresent(Bool.self, forKey: .isPlanningUnit)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        replyMedium = try c.decodeIfPresent(ReplyMedium.self, forKey: .replyMedium)
        dueToday = try c.decodeIfPresent(Bool.self, forKey: .dueToday) ?? false
        isDoFirst = try c.decodeIfPresent(Bool.self, forKey: .isDoFirst) ?? false
        isTransitSafe = try c.decodeIfPresent(Bool.self, forKey: .isTransitSafe) ?? false
        waitingOn = try c.decodeIfPresent(String.self, forKey: .waitingOn)
        askedDate = try c.decodeIfPresent(Date.self, forKey: .askedDate)
        expectedByDate = try c.decodeIfPresent(Date.self, forKey: .expectedByDate)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        estimateUncertainty = try c.decodeIfPresent(Int.self, forKey: .estimateUncertainty)
        planScore = try c.decodeIfPresent(Int.self, forKey: .planScore)
        scheduledStartTime = try c.decodeIfPresent(Date.self, forKey: .scheduledStartTime)
        urgency = try c.decodeIfPresent(Int.self, forKey: .urgency) ?? 3
        importance = try c.decodeIfPresent(Int.self, forKey: .importance) ?? 3
        energyRequired = try c.decodeIfPresent(String.self, forKey: .energyRequired) ?? "medium"
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? "anywhere"
        skipCount = try c.decodeIfPresent(Int.self, forKey: .skipCount) ?? 0
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        source = try c.decodeIfPresent(TaskSource.self, forKey: .source) ?? .manual
        estimateSource = try c.decodeIfPresent(EstimateSource.self, forKey: .estimateSource) ?? .manual
        estimateBasis = try c.decodeIfPresent(String.self, forKey: .estimateBasis)
    }
}

extension TimedTask {
    // swiftlint:disable:next function_body_length
    static var samples: [TimedTask] {
        let cal = Calendar.current
        let now = Date()
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }
        func asked(_ d: String) -> Date {
            let f = DateFormatter(); f.dateFormat = "d/M/yy"
            return f.date(from: d) ?? daysAgo(30)
        }

        return [
            // ── DO FIRST ───────────────────────────────────────────────
            TimedTask(id: UUID(), title: "Daily Update",
                      sender: "System", estimatedMinutes: 5,
                      bucket: .action, emailCount: 1, receivedAt: daysAgo(0),
                      dueToday: true, isDoFirst: true),

            TimedTask(id: UUID(), title: "PFF: Check items ex Saif and ex Sanad",
                      sender: "PFF", estimatedMinutes: 5,
                      bucket: .action, emailCount: 0, receivedAt: daysAgo(0),
                      dueToday: true, isDoFirst: true),

            // ── REPLY — EMAIL ──────────────────────────────────────────
            TimedTask(id: UUID(), title: "Reply Patrick re Le Mans livery",
                      sender: "Patrick M.", estimatedMinutes: 5,
                      bucket: .reply, emailCount: 1, receivedAt: daysAgo(1),
                      replyMedium: .email, dueToday: true),

            TimedTask(id: UUID(), title: "Reply Nosseiba (PFF)",
                      sender: "Nosseiba", estimatedMinutes: 5,
                      bucket: .reply, emailCount: 1, receivedAt: daysAgo(0),
                      replyMedium: .email, dueToday: true),

            TimedTask(id: UUID(), title: "Tom Koutsantonis — legislation update",
                      sender: "Tom K.", estimatedMinutes: 5,
                      bucket: .reply, emailCount: 2, receivedAt: daysAgo(1),
                      replyMedium: .email, dueToday: true),

            TimedTask(id: UUID(), title: "Message Hadi (Geneva)",
                      sender: "Hadi", estimatedMinutes: 3,
                      bucket: .reply, emailCount: 0, receivedAt: daysAgo(2),
                      replyMedium: .email, dueToday: true),

            // ── REPLY — WHATSAPP ───────────────────────────────────────
            TimedTask(id: UUID(), title: "30 WhatsApp messages",
                      sender: "Various", estimatedMinutes: 60,
                      bucket: .reply, emailCount: 0, receivedAt: daysAgo(0),
                      replyMedium: .whatsApp, dueToday: true),

            // ── ACTION — DUE TODAY ─────────────────────────────────────
            TimedTask(id: UUID(), title: "Wendy's Statement Review",
                      sender: "Wendy S.", estimatedMinutes: 60,
                      bucket: .action, emailCount: 3, receivedAt: daysAgo(2),
                      dueToday: true),

            TimedTask(id: UUID(), title: "NMI FA Supplementary — review before 23 March",
                      sender: "NMI Team", estimatedMinutes: 30,
                      bucket: .action, emailCount: 2, receivedAt: daysAgo(3),
                      dueToday: true),

            // ── ACTION ─────────────────────────────────────────────────
            TimedTask(id: UUID(), title: "Q4 Strategy Deck — Michael + 4 attachments",
                      sender: "Michael R.", estimatedMinutes: 45,
                      bucket: .action, emailCount: 4, receivedAt: daysAgo(1)),

            TimedTask(id: UUID(), title: "Athelstone evaluation — MD",
                      sender: "MD", estimatedMinutes: 30,
                      bucket: .action, emailCount: 2, receivedAt: daysAgo(5)),

            TimedTask(id: UUID(), title: "Race expenses summary — YS/SS",
                      sender: "Finance", estimatedMinutes: 60,
                      bucket: .action, emailCount: 1, receivedAt: daysAgo(4)),

            TimedTask(id: UUID(), title: "Budget approval sign-off (2 items)",
                      sender: "Alex M.", estimatedMinutes: 20,
                      bucket: .action, emailCount: 2, receivedAt: daysAgo(1)),

            TimedTask(id: UUID(), title: "Request for Approval — Flights mid-year family trip",
                      sender: "PA", estimatedMinutes: 10,
                      bucket: .action, emailCount: 1, receivedAt: daysAgo(2)),

            TimedTask(id: UUID(), title: "Review WRT invoices (Motoring & Motorsport folder)",
                      sender: "WRT", estimatedMinutes: 10,
                      bucket: .action, emailCount: 1, receivedAt: daysAgo(3),
                      isTransitSafe: true),

            // ── CALLS ──────────────────────────────────────────────────
            TimedTask(id: UUID(), title: "Trevor Schumack",
                      sender: "T. Schumack", estimatedMinutes: 15,
                      bucket: .calls, emailCount: 0, receivedAt: daysAgo(2)),

            TimedTask(id: UUID(), title: "Tom Koutsantonis — return call",
                      sender: "T. Koutsantonis", estimatedMinutes: 10,
                      bucket: .calls, emailCount: 0, receivedAt: daysAgo(1)),

            // ── READ TODAY ─────────────────────────────────────────────
            TimedTask(id: UUID(), title: "ATO — reasons for judgement",
                      sender: "ATO", estimatedMinutes: 20,
                      bucket: .readToday, emailCount: 1, receivedAt: daysAgo(1),
                      dueToday: true),

            TimedTask(id: UUID(), title: "CBA credit cards — OOD staff (KJ)",
                      sender: "KJ", estimatedMinutes: 5,
                      bucket: .readToday, emailCount: 1, receivedAt: daysAgo(0)),

            // ── READ THIS WEEK ─────────────────────────────────────────
            TimedTask(id: UUID(), title: "Q1 board pack — final version",
                      sender: "Board Sec.", estimatedMinutes: 40,
                      bucket: .readThisWeek, emailCount: 2, receivedAt: daysAgo(4)),

            TimedTask(id: UUID(), title: "Dolomites guide — One Note",
                      sender: "PA", estimatedMinutes: 20,
                      bucket: .readThisWeek, emailCount: 0, receivedAt: daysAgo(6)),

            TimedTask(id: UUID(), title: "Ansoff matrix — research doc",
                      sender: "Strategy", estimatedMinutes: 10,
                      bucket: .readThisWeek, emailCount: 1, receivedAt: daysAgo(7)),

            // ── TRANSIT ────────────────────────────────────────────────
            TimedTask(id: UUID(), title: "Create 1-Password ID",
                      sender: "", estimatedMinutes: 15,
                      bucket: .transit, emailCount: 0, receivedAt: daysAgo(10),
                      isTransitSafe: true),

            TimedTask(id: UUID(), title: "Sort email folders",
                      sender: "", estimatedMinutes: 20,
                      bucket: .transit, emailCount: 0, receivedAt: daysAgo(8),
                      isTransitSafe: true),

            TimedTask(id: UUID(), title: "Set up Moom",
                      sender: "", estimatedMinutes: 10,
                      bucket: .transit, emailCount: 0, receivedAt: daysAgo(12),
                      isTransitSafe: true),

            TimedTask(id: UUID(), title: "Get Handoff working",
                      sender: "", estimatedMinutes: 15,
                      bucket: .transit, emailCount: 0, receivedAt: daysAgo(14),
                      isTransitSafe: true),

            TimedTask(id: UUID(), title: "Fix bookmarks in laptop",
                      sender: "", estimatedMinutes: 10,
                      bucket: .transit, emailCount: 0, receivedAt: daysAgo(9),
                      isTransitSafe: true),

            TimedTask(id: UUID(), title: "Set up Apple TV+",
                      sender: "", estimatedMinutes: 10,
                      bucket: .transit, emailCount: 0, receivedAt: daysAgo(11),
                      isTransitSafe: true),

            TimedTask(id: UUID(), title: "Refile photo gallery",
                      sender: "", estimatedMinutes: 20,
                      bucket: .transit, emailCount: 0, receivedAt: daysAgo(15),
                      isTransitSafe: true),

            // ── WAITING ────────────────────────────────────────────────
            TimedTask(id: UUID(), title: "New helmet delivery — WRT",
                      sender: "WRT", estimatedMinutes: 5,
                      bucket: .waiting, emailCount: 1, receivedAt: asked("6/2/26"),
                      waitingOn: "WRT",
                      askedDate: asked("6/2/26")),

            TimedTask(id: UUID(), title: "Football coach for Ammar — Ali Fahour",
                      sender: "Ali Fahour", estimatedMinutes: 5,
                      bucket: .waiting, emailCount: 0, receivedAt: asked("6/2/26"),
                      waitingOn: "Ali Fahour",
                      askedDate: asked("6/2/26")),

            TimedTask(id: UUID(), title: "Panel review system scaling to 100 — MMR",
                      sender: "MMR", estimatedMinutes: 5,
                      bucket: .waiting, emailCount: 2, receivedAt: asked("2/3/26"),
                      waitingOn: "MMR",
                      askedDate: asked("2/3/26")),

            TimedTask(id: UUID(), title: "Potential recruit NMI to meet — Sahar",
                      sender: "Sahar", estimatedMinutes: 5,
                      bucket: .waiting, emailCount: 1, receivedAt: asked("2/3/26"),
                      waitingOn: "Sahar",
                      askedDate: asked("2/3/26")),

            TimedTask(id: UUID(), title: "Athelstone evaluation — MD",
                      sender: "MD", estimatedMinutes: 5,
                      bucket: .waiting, emailCount: 0, receivedAt: asked("13/2/26"),
                      waitingOn: "MD",
                      askedDate: asked("13/2/26")),

            TimedTask(id: UUID(), title: "Sandgate Chronology — KP",
                      sender: "KP", estimatedMinutes: 5,
                      bucket: .waiting, emailCount: 0, receivedAt: asked("14/5/25"),
                      waitingOn: "KP",
                      askedDate: asked("14/5/25")),
        ]
    }
}

// MARK: - WOO Item (distinct from task - for Waiting pane detail)

struct WOOItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let contact: String
    let description: String
    let category: String   // Personal / PFF / Business
    let askedDate: Date
    var expectedByDate: Date?
    var hasReplied: Bool = false

    var daysWaiting: Int {
        max(0, Int(Date().timeIntervalSince(askedDate) / 86_400))
    }

    var isOverdue: Bool {
        guard let exp = expectedByDate else { return daysWaiting > 30 }
        return Date() > exp
    }
}

extension WOOItem {
    static var samples: [WOOItem] {
        let f = DateFormatter(); f.dateFormat = "d/M/yy"
        func d(_ s: String) -> Date { f.date(from: s) ?? Date() }

        return [
            WOOItem(id: UUID(), contact: "WRT", description: "New helmet delivery", category: "Personal",
                    askedDate: d("6/2/26"), expectedByDate: d("1/3/26")),
            WOOItem(id: UUID(), contact: "Ali Fahour", description: "Football coach for Ammar", category: "Personal",
                    askedDate: d("6/2/26")),
            WOOItem(id: UUID(), contact: "MD", description: "Athelstone evaluation", category: "Business",
                    askedDate: d("13/2/26"), expectedByDate: d("28/2/26")),
            WOOItem(id: UUID(), contact: "MD", description: "Agent for Marryatville", category: "Business",
                    askedDate: d("8/2/26")),
            WOOItem(id: UUID(), contact: "MMR", description: "Panel review system scaling to 100", category: "PFF",
                    askedDate: d("2/3/26"), expectedByDate: d("15/3/26")),
            WOOItem(id: UUID(), contact: "Sahar", description: "Potential recruit NMI to meet", category: "PFF",
                    askedDate: d("2/3/26")),
            WOOItem(id: UUID(), contact: "KP", description: "Sandgate Chronology", category: "Business",
                    askedDate: d("14/5/25"), expectedByDate: d("1/6/25")),
            WOOItem(id: UUID(), contact: "KP", description: "Globe Derby Access", category: "Business",
                    askedDate: d("14/5/25")),
            WOOItem(id: UUID(), contact: "Todd Rozenthal", description: "Review Infinity safe info + other safe", category: "Personal",
                    askedDate: d("3/5/24"), expectedByDate: d("1/6/24")),
            WOOItem(id: UUID(), contact: "Josh Ling", description: "Activation of C4 music with one touch", category: "Personal",
                    askedDate: d("30/8/23")),
        ]
    }
}

// MARK: - Capture Item

struct CaptureItem: Identifiable, Codable, Sendable, Equatable {
    enum InputType: String, Codable { case voice, text }

    let id: UUID
    let inputType: InputType
    let rawText: String
    var parsedTitle: String
    var suggestedBucket: TaskBucket
    var suggestedMinutes: Int
    let capturedAt: Date
    var isConverted: Bool = false
}

extension CaptureItem {
    static var samples: [CaptureItem] {
        let now = Date()
        return [
            CaptureItem(id: UUID(), inputType: .voice,
                        rawText: "Call John back, five minutes",
                        parsedTitle: "Call John back",
                        suggestedBucket: .calls, suggestedMinutes: 5,
                        capturedAt: now - 3_600),
            CaptureItem(id: UUID(), inputType: .voice,
                        rawText: "Review the Acme contract from David, allow thirty minutes, needs to be done before Thursday",
                        parsedTitle: "Review Acme contract — David (due Thu)",
                        suggestedBucket: .action, suggestedMinutes: 30,
                        capturedAt: now - 7_200),
            CaptureItem(id: UUID(), inputType: .text,
                        rawText: "Arrange Moom home",
                        parsedTitle: "Arrange Moom home",
                        suggestedBucket: .transit, suggestedMinutes: 10,
                        capturedAt: now - 14_400),
            CaptureItem(id: UUID(), inputType: .voice,
                        rawText: "Note to RRV re the year ahead, ten minutes",
                        parsedTitle: "Note to RRV — year ahead",
                        suggestedBucket: .action, suggestedMinutes: 10,
                        capturedAt: now - 86_400),
        ]
    }
}

// MARK: - Triage items

struct TriageItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let sender: String
    let subject: String
    let preview: String
    let receivedAt: Date
    var emailMessageId: UUID? = nil
    var classificationConfidence: Float? = nil
    var classifiedBucket: String? = nil

    var initials: String {
        sender.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var relativeTime: String {
        let d = Date().timeIntervalSince(receivedAt)
        if d < 60     { return "now" }
        if d < 3_600  { return "\(Int(d/60))m" }
        if d < 86_400 { return "\(Int(d/3_600))h" }
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: receivedAt)
    }

    /// Monochrome — all avatars share one secondary-label tint.
    var avatarColor: Color {
        Color.Timed.labelSecondary
    }
}

extension TriageItem {
    static var samples: [TriageItem] {
        let now = Date()
        return [
            TriageItem(id: UUID(), sender: "LinkedIn Recruiter",
                       subject: "Exciting opportunity at Scale AI",
                       preview: "Hi, I came across your profile and thought you'd be a great fit…",
                       receivedAt: now - 1_800),
            TriageItem(id: UUID(), sender: "Marcus Webb",
                       subject: "Quick question about the proposal",
                       preview: "Hey, sorry to bother you — just wanted to clarify one point in section 3…",
                       receivedAt: now - 5_400),
            TriageItem(id: UUID(), sender: "AWS",
                       subject: "Your March billing statement",
                       preview: "Your AWS bill for March 2026 is ready. Total charges: $284.12",
                       receivedAt: now - 10_800),
            TriageItem(id: UUID(), sender: "Slack",
                       subject: "New sign-in to your account",
                       preview: "A new sign-in was detected from Sydney, AU",
                       receivedAt: now - 18_000),
            TriageItem(id: UUID(), sender: "Tom Aldridge",
                       subject: "Re: Partnership discussion",
                       preview: "Thanks for taking the time — there's definitely something worth exploring here.",
                       receivedAt: now - 28_800),
        ]
    }
}

// MARK: - CalendarBlock helpers

extension CalendarBlock {
    var startHour: Double {
        let c = Calendar.current
        return Double(c.component(.hour, from: startTime)) + Double(c.component(.minute, from: startTime)) / 60.0
    }
    var durationHours: Double { endTime.timeIntervalSince(startTime) / 3_600 }
    var weekdayIndex: Int     { (Calendar.current.component(.weekday, from: startTime) + 5) % 7 }
    var categoryColor: Color  {
        // Focus is the single accent-bearing category (the "one thing that matters").
        // Every other block is rendered monochrome.
        switch category {
        case .focus:                            return Color.Timed.accent
        case .meeting, .admin, .break, .transit: return Color.Timed.labelSecondary
        }
    }
    var startLabel: String { formatHour(startHour) }
    var endLabel:   String { formatHour(startHour + durationHours) }
    var durationLabel: String {
        let m = Int(durationHours * 60)
        if m < 60 { return "\(m) min" }
        let h = m / 60; let r = m % 60
        return r == 0 ? "\(h) hr" : "\(h)h \(r)m"
    }
    private func formatHour(_ h: Double) -> String {
        let hour = Int(h); let min = Int((h - Double(hour)) * 60)
        let sfx  = hour >= 12 ? "pm" : "am"
        let disp = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return min == 0 ? "\(disp)\(sfx)" : "\(disp):\(String(format: "%02d", min))\(sfx)"
    }
}

extension CalendarBlock {
    static var samples: [CalendarBlock] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        func d(_ dayOff: Int, _ h: Int, _ m: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: dayOff, to: today)!
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
        }
        return [
            CalendarBlock(id: UUID(), title: "Q4 Strategy Review",    startTime: d(0,9),    endTime: d(0,10,30), sourceEmailId: nil, category: .focus),
            CalendarBlock(id: UUID(), title: "Design System v2",       startTime: d(0,11),   endTime: d(0,13),    sourceEmailId: nil, category: .meeting),
            CalendarBlock(id: UUID(), title: "Budget Approval",        startTime: d(0,14),   endTime: d(0,14,30), sourceEmailId: nil, category: .admin),
            CalendarBlock(id: UUID(), title: "Auth PR Review",         startTime: d(0,16),   endTime: d(0,17),    sourceEmailId: nil, category: .focus),
            CalendarBlock(id: UUID(), title: "Client Onboarding",      startTime: d(1,9),    endTime: d(1,9,30),  sourceEmailId: nil, category: .meeting),
            CalendarBlock(id: UUID(), title: "Q4 Strategy Prep",       startTime: d(2,13),   endTime: d(2,15),    sourceEmailId: nil, category: .focus),
            CalendarBlock(id: UUID(), title: "Design Review",          startTime: d(3,10),   endTime: d(3,11),    sourceEmailId: nil, category: .meeting),
        ]
    }
}

// MARK: - DB → Model Mappings

extension TriageItem {
    init(from row: EmailMessageRow) {
        self.init(
            id: UUID(),
            sender: row.fromName ?? row.fromAddress,
            subject: row.subject,
            preview: row.snippet ?? "",
            receivedAt: row.receivedAt,
            emailMessageId: row.id,
            classificationConfidence: row.triageConfidence,
            classifiedBucket: row.triageBucket
        )
    }
}

extension TimedTask {
    init(from row: TaskDBRow) {
        let bucket = TaskBucket.from(dbValue: row.bucketType) ?? .action
        let source = TaskSource(rawValue: row.sourceType) ?? .manual
        let estimateSource = EstimateSource(rawValue: row.estimateSource ?? "manual") ?? .manual
        let estimatedMinutes = switch estimateSource {
        case .ai, .defaultBucket:
            row.estimatedMinutesAi ?? row.estimatedMinutesManual ?? 15
        case .manual:
            row.estimatedMinutesManual ?? row.estimatedMinutesAi ?? 15
        }
        self.init(
            id: row.id,
            profileId: row.profileId,
            title: row.title,
            sender: "",
            estimatedMinutes: estimatedMinutes,
            bucket: bucket,
            emailCount: 0,
            receivedAt: row.createdAt,
            sectionId: row.sectionId,
            parentTaskId: row.parentTaskId,
            sortOrder: row.sortOrder,
            manualImportance: row.manualImportance.flatMap(TaskManualImportance.init(rawValue:)),
            notes: row.notes,
            isPlanningUnit: row.isPlanningUnit,
            dueToday: row.dueAt.map { Calendar.current.isDateInToday($0) } ?? false,
            isDoFirst: row.isDoFirst,
            isTransitSafe: row.isTransitSafe,
            isDone: row.status == "done",
            source: source,
            estimateSource: estimateSource,
            estimateBasis: row.estimateBasis
        )
    }
}

extension TaskSection {
    init(from row: TaskSectionDBRow) {
        self.init(
            id: row.id,
            parentSectionId: row.parentSectionId,
            title: row.title,
            canonicalBucketType: row.canonicalBucketType,
            sortOrder: row.sortOrder,
            colorKey: row.colorKey,
            isSystem: row.isSystem,
            isArchived: row.isArchived
        )
    }
}
