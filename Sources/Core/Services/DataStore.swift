// DataStore.swift — Timed macOS
// Local JSON persistence to ~/Library/Application Support/Timed/
// Pure actor — no UI dependencies. Call from @MainActor views via Task { }.

import Foundation
import os

actor DataStore {

    static let shared = DataStore()

    private let folder: URL

    private init() {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Extremely unlikely on macOS, but avoid force-unwrap.
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("Timed", isDirectory: true)
            TimedLogger.dataStore.error("Application Support directory unavailable — falling back to temp")
            folder = fallback
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return
        }
        folder = base.appendingPathComponent("Timed", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        TimedLogger.dataStore.info("DataStore initialised at \(self.folder.path, privacy: .public)")
    }

    // MARK: - Generic helpers

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
