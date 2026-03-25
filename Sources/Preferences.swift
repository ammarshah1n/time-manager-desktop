import Foundation

enum TimedPreferences {
    static let aiExecutablePathKey = "timed.aiExecutablePath"
    static let autonomousModeEnabledKey = "timed.autonomousModeEnabled"
    static let fileSearchEnabledKey = "timed.fileSearchEnabled"
    static let codexMemoryEnabledKey = "timed.codexMemoryEnabled"
    static let workingRootKey = "timed.workingRoot"
    static let codexMemDBPathKey = "timed.codexMemDBPath"
    static let defaultAIExecutablePath = "/Applications/Codex.app/Contents/Resources/codex"
    static let defaultWorkingRoot = NSHomeDirectory()
    static let defaultCodexMemDBPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex-mem", isDirectory: true)
        .appendingPathComponent("codex-mem.db")
        .path

    static var aiExecutablePath: String {
        let value = UserDefaults.standard.string(forKey: aiExecutablePathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : defaultAIExecutablePath
    }

    static func setAIExecutablePath(_ path: String) {
        UserDefaults.standard.set(path.trimmingCharacters(in: .whitespacesAndNewlines), forKey: aiExecutablePathKey)
    }

    static var autonomousModeEnabled: Bool {
        UserDefaults.standard.object(forKey: autonomousModeEnabledKey) as? Bool ?? true
    }

    static var fileSearchEnabled: Bool {
        UserDefaults.standard.object(forKey: fileSearchEnabledKey) as? Bool ?? true
    }

    static var codexMemoryEnabled: Bool {
        UserDefaults.standard.object(forKey: codexMemoryEnabledKey) as? Bool ?? true
    }

    static var workingRoot: String {
        let value = UserDefaults.standard.string(forKey: workingRootKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : defaultWorkingRoot
    }

    static var codexMemDBPath: String {
        let value = UserDefaults.standard.string(forKey: codexMemDBPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : defaultCodexMemDBPath
    }

    static func setWorkingRoot(_ path: String) {
        UserDefaults.standard.set(path.trimmingCharacters(in: .whitespacesAndNewlines), forKey: workingRootKey)
    }

    static func setCodexMemDBPath(_ path: String) {
        UserDefaults.standard.set(path.trimmingCharacters(in: .whitespacesAndNewlines), forKey: codexMemDBPathKey)
    }

    static var oneDriveRoots: [String] {
        let cloudStorage = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .map(\.path)
            .filter { $0.lowercased().contains("onedrive") }
            .sorted()
    }

    static var codexAdditionalRoots: [String] {
        var roots = oneDriveRoots
        let commonRoots = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop").path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents").path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads").path
        ]

        for root in commonRoots where FileManager.default.fileExists(atPath: root) {
            roots.append(root)
        }

        return Array(Set(roots + [workingRoot])).sorted()
    }
}
