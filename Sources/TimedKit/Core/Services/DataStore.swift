// DataStore.swift — Timed macOS
// Local JSON persistence to ~/Library/Application Support/Timed/
// Pure actor — no UI dependencies. Call from @MainActor views via Task { }.

import Foundation
import os

actor DataStore {

    static let shared = DataStore()

    private init() {
        TimedLogger.dataStore.info("DataStore initialised; folder resolved per-call from PlatformPaths.applicationSupport (user-scoped)")
    }

    // MARK: - Generic helpers

    /// Resolved on every access. Returns the per-user folder when signed in
    /// (PlatformPaths reads UserDefaults activeExecutiveDefaultsKey), or the
    /// _anonymous bucket otherwise. Means a sign-in/sign-out flips the on-disk
    /// store without restart and without DataStore caching a stale path.
    private var folder: URL { PlatformPaths.applicationSupport }

    private func fileURL(_ name: String) -> URL {
        folder.appendingPathComponent("\(name).json")
    }

    private func load<T: Decodable>(_ name: String) throws -> T {
        do {
            let data = try Data(contentsOf: fileURL(name))
            let result = try JSONDecoder.timed.decode(T.self, from: data)
            TimedLogger.dataStore.debug("Loaded \(name, privacy: .public) successfully")
            return result
        } catch {
            TimedLogger.dataStore.error("Failed to load \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func save<T: Encodable>(_ value: T, _ name: String) throws {
        do {
            let data = try JSONEncoder.timed.encode(value)
            try data.write(to: fileURL(name), options: .atomic)
            TimedLogger.dataStore.debug("Saved items to \(name, privacy: .public)")
        } catch {
            TimedLogger.dataStore.error("Failed to save \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Public API

    func loadTasks()                      throws -> [TimedTask]     { try load("tasks") }
    func saveTasks(_ v: [TimedTask])      throws                    { try save(v, "tasks") }

    func loadTaskSections()                    throws -> [TaskSection] { try load("task_sections") }
    func saveTaskSections(_ v: [TaskSection])  throws                 { try save(v, "task_sections") }

    func clearWorkspaceCaches() async {
        // These caches are intentionally user-scoped but not workspace-keyed.
        // Clear before switching active workspaces to avoid a flash of stale rows.
        try? saveTasks([])
        try? saveTaskSections([])
    }

    func loadTriageItems()                throws -> [TriageItem]    { try load("triage") }
    func saveTriageItems(_ v: [TriageItem]) throws                  { try save(v, "triage") }

    func loadWOOItems()                   throws -> [WOOItem]       { try load("woo") }
    func saveWOOItems(_ v: [WOOItem])     throws                    { try save(v, "woo") }

    func loadBlocks()                     throws -> [CalendarBlock] { try load("blocks") }
    func saveBlocks(_ v: [CalendarBlock]) throws                    { try save(v, "blocks") }

    func loadCaptureItems()                       throws -> [CaptureItem] { try load("captures") }
    func saveCaptureItems(_ v: [CaptureItem])     throws                  { try save(v, "captures") }

    func loadCompletionRecords()                            throws -> [CompletionRecord] { try load("completions") }
    func saveCompletionRecords(_ v: [CompletionRecord])     throws                       { try save(v, "completions") }

    func loadBucketEstimates()                              throws -> [String: BucketEstimate] { try load("bucket_estimates") }
    func saveBucketEstimates(_ v: [String: BucketEstimate]) throws                             { try save(v, "bucket_estimates") }

    func loadFocusSessions()                                   throws -> [FocusSessionRecord] { try load("focus_sessions") }
    func saveFocusSessions(_ v: [FocusSessionRecord])          throws                         { try save(v, "focus_sessions") }

    func loadActiveFocusSession()                              throws -> FocusSessionRecord?  { try load("active_focus_session") }
    func saveActiveFocusSession(_ v: FocusSessionRecord?)      throws {
        if let v {
            try save(v, "active_focus_session")
        } else {
            // Remove the file when clearing active session
            let url = fileURL("active_focus_session")
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Shared encoder / decoder

private extension JSONEncoder {
    static let timed: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let timed: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
