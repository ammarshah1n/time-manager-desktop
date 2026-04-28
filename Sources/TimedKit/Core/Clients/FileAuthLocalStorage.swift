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
        return try Data(contentsOf: url)
    }

    public func remove(key: String) throws {
        let url = fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
