// SharedSnapshot.swift — Timed Widgets / Shared data
// App-Group-backed snapshot the main app writes for the widget process to read.
// Wire location: Sources/TimedKit/Core/Services/DataBridge.swift writes
// today-snapshot.json after every successful local save (10s debounce).
// Widget timeline provider reads it; if missing or stale, falls back to placeholder.

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

    static let placeholder = TodaySnapshot(
        generatedAt: Date(),
        topPriorities: [
            Priority(id: "p1", title: "Reply to David — board pre-read", bucket: "reply", estimatedMinutes: 12),
            Priority(id: "p2", title: "Approve Q2 budget shift", bucket: "decision", estimatedMinutes: 8),
            Priority(id: "p3", title: "Read: legal counsel summary", bucket: "read", estimatedMinutes: 15),
        ],
        nextEventTitle: "Strategy review with Mark",
        nextEventStartsAt: Date().addingTimeInterval(45 * 60)
    )
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
