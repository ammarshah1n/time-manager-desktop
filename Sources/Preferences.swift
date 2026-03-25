import Foundation

enum TimedPreferences {
    static let aiExecutablePathKey = "timed.aiExecutablePath"
    static let defaultAIExecutablePath = "/Applications/Codex.app/Contents/Resources/codex"

    static var aiExecutablePath: String {
        let value = UserDefaults.standard.string(forKey: aiExecutablePathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : defaultAIExecutablePath
    }

    static func setAIExecutablePath(_ path: String) {
        UserDefaults.standard.set(path.trimmingCharacters(in: .whitespacesAndNewlines), forKey: aiExecutablePathKey)
    }
}
