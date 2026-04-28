// FileAuthLocalStorage.swift — Timed Core / Clients
// File-based AuthLocalStorage for the Supabase Swift SDK. Replaces the default
// KeychainLocalStorage so ad-hoc-signed dev builds don't hit Keychain ACL
// prompts on every rebuild (different signature → "always allow" never sticks).
//
// Tradeoff: session JSON sits on disk readable by any process running as the
// user, vs. encrypted-at-rest in Keychain. Acceptable for dev / pre-Apple-Dev
// distribution. Switch back to KeychainLocalStorage once Developer ID signing
// is in place — only one line in SupabaseClient.live() changes.

import Foundation
import Supabase

public struct FileAuthLocalStorage: AuthLocalStorage {

    private let folder: URL

    public init(folder: URL = PlatformPaths.authStorage) {
        self.folder = folder
    }

    private func fileURL(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(safe, isDirectory: false)
    }

    public func store(key: String, value: Data) throws {
        try value.write(to: fileURL(key), options: [.atomic])
    }

    public func retrieve(key: String) throws -> Data? {
        let url = fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        // Defend against zero-byte / corrupt files left over by a SIGTERM mid-write.
        // .atomic write protects against torn writes on normal termination, but a
        // hard kill during the rename window can leave a 0-byte target. Decoding
        // nothing as "no session" rather than throwing forces a clean re-login
        // instead of a Supabase SDK boot-loop on the LoginView.
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                TimedLogger.supabase.error("FileAuthLocalStorage zero-byte file for \(key, privacy: .public) — clearing")
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return data
        } catch {
            TimedLogger.supabase.error(
                "FileAuthLocalStorage corrupt read for \(key, privacy: .public) — clearing: \(error.localizedDescription, privacy: .public)"
            )
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    public func remove(key: String) throws {
        let url = fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
