import AppKit
import CoreGraphics
import CryptoKit
import Foundation

@MainActor
private final class AppUsageMonitorController {
    static let shared = AppUsageMonitorController()

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleIdentifier = application.bundleIdentifier
            else {
                return
            }

            let titleSeed = Self.frontmostWindowTitle(for: application) ?? application.localizedName ?? bundleIdentifier
            let timestamp = Date()

            Task {
                await AppUsageAgent.shared.handleActivation(
                    bundleIdentifier: bundleIdentifier,
                    titleSeed: titleSeed,
                    at: timestamp
                )
            }
        }
    }

    func stop() {
        guard let observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }

    static func frontmostWindowTitle(for app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windowList {
            if let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
               ownerPID == pid,
               let name = window[kCGWindowName as String] as? String,
               !name.isEmpty {
                return name
            }
        }
        return nil
    }

    func currentFrontmostApp() -> (bundleIdentifier: String, titleSeed: String)? {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = application.bundleIdentifier
        else {
            return nil
        }

        let titleSeed = Self.frontmostWindowTitle(for: application) ?? application.localizedName ?? bundleIdentifier
        return (bundleIdentifier, titleSeed)
    }
}

actor AppUsageAgent {
    static let shared = AppUsageAgent()

    private let minimumSessionDuration: TimeInterval = 30
    private var monitorTask: Task<Void, Never>? = nil
    private var lastBundleIdentifier: String?
    private var lastTitleHash: String?
    private var lastActivatedAt: Date?

    func start() async {
        guard monitorTask == nil else { return }

        if let frontmostApp = await MainActor.run(body: { AppUsageMonitorController.shared.currentFrontmostApp() }) {
            lastBundleIdentifier = frontmostApp.bundleIdentifier
            lastTitleHash = Self.sha256Hex(frontmostApp.titleSeed)
            lastActivatedAt = Date()
        }

        await MainActor.run(body: { AppUsageMonitorController.shared.start() })
        TimedLogger.dataStore.info("AppUsageAgent started")

        monitorTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(86400))
            }
        }
    }

    func stop() async {
        guard let monitorTask else { return }

        await finalizeCurrentSession(endedAt: Date())
        monitorTask.cancel()
        self.monitorTask = nil

        await MainActor.run(body: { AppUsageMonitorController.shared.stop() })
        TimedLogger.dataStore.info("AppUsageAgent stopped")
    }

    func handleActivation(bundleIdentifier: String, titleSeed: String, at timestamp: Date) async {
        let newTitleHash = Self.sha256Hex(titleSeed)

        if bundleIdentifier != lastBundleIdentifier {
            await finalizeCurrentSession(endedAt: timestamp)
        }

        lastBundleIdentifier = bundleIdentifier
        lastTitleHash = newTitleHash
        lastActivatedAt = timestamp
    }

    private func finalizeCurrentSession(endedAt: Date) async {
        guard
            let bundleIdentifier = lastBundleIdentifier,
            let titleHash = lastTitleHash,
            let startedAt = lastActivatedAt
        else {
            return
        }

        let duration = endedAt.timeIntervalSince(startedAt)
        guard duration > minimumSessionDuration else { return }

        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            return
        }

        let observation = Tier0Observation(
            profileId: executiveId,
            occurredAt: endedAt,
            source: .appUsage,
            eventType: "app.session",
            rawData: [
                "bundle_id": AnyCodable(bundleIdentifier),
                "window_title_hash": AnyCodable(titleHash),
                "focus_duration_seconds": AnyCodable(duration),
                "app_category": AnyCodable(Self.category(for: bundleIdentifier))
            ]
        )

        try? await Tier0Writer.shared.recordObservation(observation)
    }

    private static func category(for bundleIdentifier: String) -> String {
        switch bundleIdentifier {
        case "com.apple.mail",
             "com.microsoft.teams",
             "com.tinyspeck.slackmacgap",
             "com.apple.MobileSMS":
            return "communication"
        case "com.apple.dt.Xcode",
             "com.apple.Terminal",
             "com.microsoft.VSCode",
             "com.microsoft.VSCodeInsiders",
             "com.todesktop.230313mzl4w4u92":
            return "coding"
        case "com.apple.Safari",
             "com.google.Chrome",
             "org.mozilla.firefox",
             "company.thebrowser.Browser":
            return "browsing"
        case "com.figma.Desktop",
             "com.bohemiancoding.sketch3",
             "com.apple.iWork.Keynote":
            return "creative"
        case "com.apple.iWork.Numbers",
             "com.microsoft.Excel",
             "com.microsoft.Word",
             "com.apple.iWork.Pages":
            return "productivity"
        default:
            return "other"
        }
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
