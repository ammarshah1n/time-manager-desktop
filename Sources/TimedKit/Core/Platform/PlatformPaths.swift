// PlatformPaths.swift — Timed Core / Platform
// Storage path resolution that works on macOS and iOS.
// macOS: ~/Library/Application Support/Timed/
// iOS:   <sandbox>/Library/Application Support/Timed/
//        (persists across launches; auto-included in iCloud unless excluded
//        per-file via URLResourceValues.isExcludedFromBackup)
//
// Used by DataStore, OfflineSyncQueue, any feature that needs durable
// per-app on-device storage. All paths are created on first read.

import Foundation

public enum PlatformPaths {

    /// Root directory for Timed's persistent data.
    /// Identical layout on macOS + iOS: <ApplicationSupport>/Timed/.
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Timed", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    /// Directory for transient caches that should NOT round-trip through
    /// iCloud / Time Machine. iOS automatically excludes <Caches>; on macOS
    /// we set the resource flag explicitly to match.
    public static var cache: URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Timed", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    /// JSON store path for a given filename inside the Application Support root.
    public static func store(_ filename: String) -> URL {
        applicationSupport.appendingPathComponent(filename, isDirectory: false)
    }

    /// SQLite store path under Application Support.
    public static func sqlite(_ filename: String) -> URL {
        applicationSupport.appendingPathComponent(filename, isDirectory: false)
    }

    private static func ensureDirectoryExists(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
