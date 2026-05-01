// SharedSnapshot.swift — Timed Widgets / Shared data
// App-Group-backed snapshot helper for widget reads/writes.
// No main-app writer is wired yet; widget data remains placeholder/stale until
// a production writer calls SharedSnapshot.write and reloads timelines.

import Foundation

struct TodaySnapshot: Codable, Hashable {
    var generatedAt: Date
    var topPriorities: [Priority]
    var nextEventTitle: String?
    var nextEventStartsAt: Date?

    struct Priority: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var bucket: String
        var estimatedMinutes: Int
    }

    static let empty = TodaySnapshot(
        generatedAt: .distantPast,
        topPriorities: [],
        nextEventTitle: nil,
        nextEventStartsAt: nil
    )

    /// Bland demo content for widget gallery / context.isPreview only.
    /// Never use as a fallback when the real snapshot is missing — that
    /// would leak fake "executive-flavoured" tasks into a real user's
    /// widget pre-onboarding.
    static let placeholder = TodaySnapshot(
        generatedAt: Date(),
        topPriorities: [
            Priority(id: "p1", title: "First priority", bucket: "reply", estimatedMinutes: 10),
            Priority(id: "p2", title: "Second priority", bucket: "decision", estimatedMinutes: 10),
            Priority(id: "p3", title: "Third priority", bucket: "read", estimatedMinutes: 10),
        ],
        nextEventTitle: "Next event",
        nextEventStartsAt: Date().addingTimeInterval(45 * 60)
    )

    /// Same-day-only freshness check. Returns true if the snapshot was
    /// generated today, in the user's current timezone. Stale snapshots
    /// (yesterday's plan still showing on a Lock Screen at 7am) are a
    /// confidentiality + UX failure.
    var isFreshToday: Bool {
        Calendar.current.isDateInToday(generatedAt)
    }
}

enum SharedSnapshot {
    static let appGroup = "group.com.timed.shared"
    static let filename = "today-snapshot.json"

    static func read() -> TodaySnapshot? {
        guard
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        let url = container.appendingPathComponent(filename, isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TodaySnapshot.self, from: data)
    }

    static func write(_ snapshot: TodaySnapshot) {
        guard
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return }
        let url = container.appendingPathComponent(filename, isDirectory: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}
