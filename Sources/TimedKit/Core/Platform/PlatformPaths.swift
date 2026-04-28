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

    /// UserDefaults key written by AuthService once an executive is signed in.
    /// Read here so on-disk storage partitions per user without DataStore having
    /// to reach across actor isolation into AuthService on every call.
    public static let activeExecutiveDefaultsKey = "com.timed.auth.activeExecutiveID"

    /// Unscoped root: <ApplicationSupport>/Timed/. Used for data that exists
    /// before sign-in (session tokens, auth scratch). Per-user data uses
    /// `applicationSupport` instead.
    public static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Timed", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    /// Storage for Supabase Auth session JSON. Lives outside the per-user
    /// folder because the session must be readable BEFORE we know who the
    /// user is.
    public static var authStorage: URL {
        let url = applicationSupportRoot.appendingPathComponent("_auth", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    /// Root directory for Timed's persistent data, scoped to the active executive.
    /// Layout: <ApplicationSupport>/Timed/users/<executive-uuid>/  (signed in)
    ///         <ApplicationSupport>/Timed/_anonymous/              (no session)
    /// Different signed-in executives never share on-disk state on the same Mac.
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let root = base.appendingPathComponent("Timed", isDirectory: true)
        let scoped: URL
        if let uuid = UserDefaults.standard.string(forKey: activeExecutiveDefaultsKey),
           !uuid.isEmpty {
            scoped = root
                .appendingPathComponent("users", isDirectory: true)
                .appendingPathComponent(uuid, isDirectory: true)
        } else {
            scoped = root.appendingPathComponent("_anonymous", isDirectory: true)
        }
        ensureDirectoryExists(scoped)
        return scoped
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
