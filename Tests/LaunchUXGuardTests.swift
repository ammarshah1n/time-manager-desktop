// LaunchUXGuardTests.swift — Timed
// Static launch-readiness ratchets for regressions found in docs/LAUNCH-UX-FINDINGS.md.

import Foundation
import Testing

@Suite("Launch UX Guard")
struct LaunchUXGuardTests {
    @Test func userFacingCopyDoesNotExposeInternalProjectOrSmokeTerms() throws {
        let repo = repoRoot()
        let checkedFiles = [
            "Sources/TimedKit/Features/Tasks/TasksPane.swift",
            "Sources/TimedKit/Features/Waiting/WaitingPane.swift",
            "Sources/TimedKit/Features/DishMeUp/DishMeUpHomeView.swift",
            "Sources/TimedKit/Features/Today/TodayPane.swift",
            "Sources/TimedKit/Features/Triage/TriagePane.swift",
            "Sources/TimedKit/Features/Briefing/MorningBriefingPane.swift",
            "supabase/functions/generate-dish-me-up/index.ts",
        ]
        let banned = ["Redish", "Timed DoD", "DoD briefing smoke", "smoke task", "gets the flywheel moving", "PFF"]
        var failures: [String] = []

        for file in checkedFiles {
            let text = try read(file, repoRoot: repo)
            for term in banned where text.localizedCaseInsensitiveContains(term) {
                failures.append("\(file) contains launch-hostile copy term: \(term)")
            }
        }

        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
    }

    @Test func taskImportanceUsesIntentLabelsNotColourNames() throws {
        let text = try read("Sources/TimedKit/Features/Tasks/TasksPane.swift", repoRoot: repoRoot())
        let labelSlice = slice(text, from: "var label: String", to: "var rank: Int")
        #expect(!labelSlice.contains("\"Blue\""), "Manual importance labels must not expose colour names.")
        #expect(!labelSlice.contains("\"Orange\""), "Manual importance labels must not expose colour names.")
        #expect(!labelSlice.contains("\"Red\""), "Manual importance labels must not expose colour names.")
        #expect(labelSlice.contains("\"Low\"") || labelSlice.contains("\"Normal\""))
        #expect(labelSlice.contains("\"High\""))
        #expect(labelSlice.contains("\"Urgent\""))
    }

    @Test func morningReviewCannotFinishByDiscardingVisibleTodayTasks() throws {
        let text = try read("Sources/TimedKit/Features/MorningInterview/MorningInterviewPane.swift", repoRoot: repoRoot())
        #expect(text.contains("private var hasUnconfirmedTodayCandidates"), "Morning review needs an explicit destructive-completion guard.")
        #expect(text.contains(".disabled(hasUnconfirmedTodayCandidates)"), "Start My Day must be disabled while visible today tasks are unconfirmed.")
        #expect(!text.contains("No tasks confirmed. Your Today screen will be empty."), "Morning review must not tell users visible work will be emptied by continuing.")
    }

    @Test func emptyTaskSectionsDoNotExposeBulkSelectionControls() throws {
        let text = try read("Sources/TimedKit/Features/Tasks/TasksPane.swift", repoRoot: repoRoot())
        #expect(text.contains("private var selectableTasks"), "TasksPane needs a single selectable row source.")
        #expect(text.contains("!selectableTasks.isEmpty"), "Select controls must be gated by non-empty selectable rows.")
        #expect(!text.contains("selectedIds = Set(activeRootTasks.map(\\.id))"), "Select All must not rely on activeRootTasks only or appear for empty sections.")
    }

    @Test func accountSettingsSeparatesSignedInIdentityFromLinkedProviders() throws {
        let text = try read("Sources/TimedKit/Features/Prefs/PrefsPane.swift", repoRoot: repoRoot())
        #expect(text.contains("signedInIdentityRow"), "Accounts tab must render Supabase identity separately from provider links.")
        #expect(text.contains("outlookLinkRow"), "Accounts tab must render Outlook as a link state, not the primary identity.")
        #expect(text.contains("gmailLinkRow"), "Accounts tab must render Gmail as a link state, not the primary identity.")
        #expect(!text.contains("provider: \"Microsoft\""), "Primary Supabase identity must not be hard-coded as Microsoft.")
    }

    @Test func syncHealthSurfacesAuthenticatedWriteFailures() throws {
        let prefs = try read("Sources/TimedKit/Features/Prefs/PrefsPane.swift", repoRoot: repoRoot())
        let bridge = try read("Sources/TimedKit/Core/Services/DataBridge.swift", repoRoot: repoRoot())
        #expect(prefs.contains("Sync health"), "Settings must expose authenticated write health, not only login state.")
        #expect(prefs.contains("Authenticated writes look healthy"), "Settings should show the healthy authenticated-write state.")
        #expect(prefs.contains("Retry sync now"), "Users need a visible recovery action when sync fails.")
        #expect(bridge.contains("offlineQueueDiagnostics"), "DataBridge should expose offline queue diagnostics for Settings.")
    }

    @Test func taskSectionSyncDoesNotWriteServiceOwnedRows() throws {
        let text = try read("Sources/TimedKit/Core/Services/DataBridge.swift", repoRoot: repoRoot())
        #expect(text.contains(".filter { !$0.isSystem }"), "Authenticated clients must not upsert service-owned task_sections rows.")
    }

    @Test func briefingHasScheduleAndManualRecovery() throws {
        let pane = try read("Sources/TimedKit/Features/Briefing/MorningBriefingPane.swift", repoRoot: repoRoot())
        let fn = try read("supabase/functions/generate-morning-briefing/index.ts", repoRoot: repoRoot())
        // The morning briefing schedule lives in the Trigger.dev task file
        // (we picked Trigger.dev over the pg_cron migration JCODE drafted —
        // see commits 8489db5 / b755ea0 — for retries, run history, max-
        // duration enforcement, and cloud dashboard observability).
        let triggerTask = try read("trigger/src/tasks/morning-briefing.ts", repoRoot: repoRoot())
        #expect(pane.contains("Refresh"), "Briefing empty state must not be a dead end.")
        #expect(pane.contains("Generate briefing now"), "Briefing empty state needs a manual generation path.")
        #expect(fn.contains("verifyAuth") && fn.contains("resolveExecutiveId"), "Manual generation must be user-scoped, not service-role-only.")
        #expect(triggerTask.contains("schedules.task") && triggerTask.contains("\"30 5 * * *\"") && triggerTask.contains("Australia/Adelaide"), "Morning briefing needs a checked-in Trigger.dev schedule firing at 05:30 Australia/Adelaide.")
    }

    @Test func settingsVoiceAndTaskDetailPolishStayFixed() throws {
        let prefs = try read("Sources/TimedKit/Features/Prefs/PrefsPane.swift", repoRoot: repoRoot())
        let layout = try read("Sources/TimedKit/Core/Design/TimedLayout.swift", repoRoot: repoRoot())
        let detail = try read("Sources/TimedKit/Features/Tasks/TaskDetailSheet.swift", repoRoot: repoRoot())
        let triage = try read("Sources/TimedKit/Features/Triage/TriagePane.swift", repoRoot: repoRoot())

        #expect(!prefs.contains("Voice confirmations are ready"), "Voice tab must not say setup is incomplete and confirmations are ready.")
        #expect(layout.contains("settingsPane:       CGFloat = 760"), "Settings width should keep tabs out of toolbar overflow.")
        #expect(detail.contains("isEditingWaitingOn") && detail.contains("waitingOnRow"), "Waiting On editing must be explicit so the sheet does not autofocus it.")
        #expect(triage.contains("Open account settings"), "Triage empty state needs a connect/sync recovery CTA.")
    }

    @Test func graphWebhookOnlyAcknowledgesAfterQueueing() throws {
        let text = try read("supabase/functions/graph-webhook/index.ts", repoRoot: repoRoot())
        #expect(!text.contains("EdgeRuntime.waitUntil(processNotifications(req))"), "Graph webhook must not ack before queueing succeeds.")
        #expect(text.contains("queueNotification"), "Graph webhook should expose a queueNotification helper that checks pgmq errors.")
        #expect(text.contains("status: 503"), "Graph webhook should return a retryable failure when queueing fails.")
    }

    @Test func releasePackagingRefusesAdHocLaunchBuilds() throws {
        let text = try read("scripts/package_app.sh", repoRoot: repoRoot())
        #expect(text.contains("TIMED_REQUIRE_NOTARIZATION"), "Launch packaging must have an explicit notarization-required mode.")
        #expect(text.contains("TIMED_APPLE_TEAM_ID"), "Launch packaging must require a Team ID for production signing.")
        #expect(text.contains("TIMED_CODESIGN_IDENTITY"), "Launch packaging must use an explicit Developer ID identity.")
        #expect(text.contains("--entitlements"), "Codesign must preserve app entitlements.")
    }

    private func read(_ relativePath: String, repoRoot: URL) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text[startRange.upperBound...].range(of: end) else { return "" }
        return String(text[startRange.upperBound..<endRange.lowerBound])
    }

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
