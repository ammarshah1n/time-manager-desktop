// CaptureForTimedIntent.swift — Timed Core / AppEntry / Intents
// Single AppIntent powering: Action Button (iPhone 15 Pro+), "Hey Siri,
// capture for Timed", Spotlight quick-action. Opens the orb in capture mode.
//
// Per ai-assistant-rules.md (Tool Dispatch on the client validates and clamps
// every argument): this intent has no parameters — it just opens the app.
// Parameter-bearing intents (e.g. OpenTimedTab(tab:)) live in their own files.

#if os(iOS)
import AppIntents
import SwiftUI

@available(iOS 18.0, *)
public struct CaptureForTimedIntent: AppIntent {
    public static let title: LocalizedStringResource = "Capture for Timed"
    public static let description: IntentDescription = IntentDescription(
        "Open Timed and start the orb in capture mode."
    )
    public static let openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        // Posts a local notification that the running app observes and routes
        // to the conversation orb. App Group is the cross-process channel.
        UserDefaults(suiteName: "group.com.timed.shared")?
            .set(true, forKey: "intent.openCapture")
        return .result()
    }
}

@available(iOS 18.0, *)
public struct OpenTimedTabIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Timed Tab"
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Tab")
    public var tab: TimedIntentTab

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.com.timed.shared")?
            .set(tab.rawValue, forKey: "intent.openTab")
        return .result()
    }
}

@available(iOS 18.0, *)
public enum TimedIntentTab: String, AppEnum {
    case today, plan, briefing, triage, settings

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Timed Tab"
    public static let caseDisplayRepresentations: [TimedIntentTab: DisplayRepresentation] = [
        .today:    "Today",
        .plan:     "Plan",
        .briefing: "Briefing",
        .triage:   "Triage",
        .settings: "Settings",
    ]
}

@available(iOS 18.0, *)
public struct TimedAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureForTimedIntent(),
            phrases: [
                "Capture for \(.applicationName)",
                "Talk to \(.applicationName)",
                "Open the orb in \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: OpenTimedTabIntent(),
            phrases: ["Open \(\.$tab) in \(.applicationName)"],
            shortTitle: "Open Tab",
            systemImageName: "square.grid.2x2"
        )
    }
}
#endif
