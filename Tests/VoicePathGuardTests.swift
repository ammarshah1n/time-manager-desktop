// VoicePathGuardTests.swift — Timed
// Build-failing regression guard. Voice path is locked to ElevenLabs + Deepgram +
// Anthropic Opus. Apple TTS (AVSpeechSynthesizer / NSSpeechSynthesizer) and Apple
// STT (SFSpeechRecognizer) must NEVER appear in the orb call graph — if a
// well-meaning future change reintroduces one, this test fails the build.
//
// VoiceCaptureService is exempt — it's the dictation-to-task feature (Apple
// Speech is the only on-device option), not the orb conversation path.

import Foundation
import Testing

@Suite("Voice Path Guard")
struct VoicePathGuardTests {
    /// Files in the orb conversation call graph. None of these may reference
    /// Apple TTS/STT symbols.
    private let orbFiles: [String] = [
        "Sources/TimedKit/Core/Services/StreamingTTSService.swift",
        "Sources/TimedKit/Core/Services/SpeechService.swift",
        "Sources/TimedKit/Core/Services/DeepgramSTTService.swift",
        "Sources/TimedKit/Features/Conversation/ConversationModel.swift",
        "Sources/TimedKit/Features/Conversation/ConversationView.swift",
        "Sources/TimedKit/Core/Clients/ConversationAIClient.swift",
    ]

    private let bannedSymbols: [String] = [
        "AVSpeechSynthesizer",
        "NSSpeechSynthesizer",
        "SFSpeechRecognizer",
        "SFSpeechAudioBufferRecognitionRequest",
    ]

    @Test func noAppleTTSorSTTInOrbCallGraph() throws {
        let repoRoot = repoRoot()
        for relativePath in orbFiles {
            let fullPath = repoRoot.appendingPathComponent(relativePath)
            // If a file in the list is renamed or removed, fail loudly so the
            // guard list stays in sync with reality.
            #expect(FileManager.default.fileExists(atPath: fullPath.path),
                    "Orb-graph file missing — update VoicePathGuardTests when refactoring: \(relativePath)")
            guard let contents = try? String(contentsOf: fullPath, encoding: .utf8) else { continue }
            for symbol in bannedSymbols {
                #expect(!contents.contains(symbol),
                        "Banned symbol \"\(symbol)\" found in \(relativePath). The orb is locked to ElevenLabs + Deepgram + Opus — Apple TTS/STT must not appear in this call graph.")
            }
        }
    }

    /// Walk up from this source file to the repo root — works regardless of
    /// where `swift test` is invoked from.
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

@Suite("Production Readiness Guards")
struct ProductionReadinessGuardTests {
    @Test func classifyEmailCallersUseAuthenticatedCamelCaseContract() throws {
        for relativePath in [
            "Sources/TimedKit/Core/Services/EmailSyncService.swift",
            "Sources/TimedKit/Core/Services/GmailSyncService.swift",
        ] {
            let contents = try read(relativePath)

            #expect(contents.contains("EdgeFunctions.shared.authorizationHeader()"),
                    "\(relativePath) must call classify-email with the current Supabase session JWT.")
            #expect(contents.contains("\"emailMessageId\""),
                    "\(relativePath) must use the classify-email emailMessageId key.")
            #expect(contents.contains("\"workspaceId\""),
                    "\(relativePath) must use the classify-email workspaceId key.")
            #expect(contents.contains("\"profileId\""),
                    "\(relativePath) must include profileId for classify-email tenant validation.")
            #expect(contents.contains("\"message_id\"") == false,
                    "\(relativePath) must not use the old snake_case message_id key.")
            #expect(contents.contains("\"workspace_id\"") == false,
                    "\(relativePath) must not use the old snake_case workspace_id key.")
        }
    }

    @Test func emailMessageUpsertUsesCompositeConflictTarget() throws {
        let contents = try read("Sources/TimedKit/Core/Clients/SupabaseClient.swift")

        #expect(contents.contains("onConflict: \"email_account_id,graph_message_id\""),
                "email_messages upsert must match the schema's composite unique constraint.")
        #expect(contents.contains("onConflict: \"graph_message_id\"") == false,
                "email_messages upsert must not use the old graph_message_id-only conflict target.")
    }

    @Test func taskHierarchyMigrationDefinesDatabaseGuardrails() throws {
        let migration = try read("supabase/migrations/20260501211829_task_hierarchy_schema.sql")

        #expect(migration.contains("create domain public.canonical_bucket"),
                "Task hierarchy schema must define a canonical bucket domain.")
        #expect(migration.contains("create table if not exists public.task_sections"),
                "Task hierarchy schema must add task_sections.")
        #expect(migration.contains("private.user_workspace_ids()"),
                "task_sections RLS must use the private workspace helper.")
        #expect(migration.contains("trg_enforce_task_section_depth"),
                "task_sections must enforce one subsection level in the database.")
        #expect(migration.contains("tasks_parent_task_id_fkey") && migration.contains("on delete restrict"),
                "Task parent deletion must be trigger-owned, not FK SET NULL.")
        #expect(migration.contains("tasks_parent_not_self"),
                "Tasks must reject self-parenting.")
        #expect(migration.contains("trg_promote_orphaned_subtasks"),
                "Parent deletion must promote children before delete.")
        #expect(migration.contains("trg_sync_task_parent_insert_update"),
                "Parent planning-unit state must update when subtasks change.")
        #expect(migration.contains("status not in ('done', 'cancelled')"),
                "Planning-unit restoration must use active-child semantics.")
        #expect(migration.contains("'task_section_changed'"),
                "Section-changing promotion must emit a behaviour event.")
        #expect(migration.contains("create table if not exists public.estimate_priors"),
                "Silent learning needs estimate_priors before backend jobs ship.")
    }

    @Test func bucketMigrationKeepsBriefingBehaviourEventsValid() throws {
        let migration = try read("supabase/migrations/20260501211002_normalize_task_bucket_values.sql")

        #expect(migration.contains("'briefing'"),
                "behaviour_events.bucket_type must keep existing briefing interaction events valid.")
    }

    @Test func disabledEmbeddingFunctionIsDocumentedAsNotProductionReady() throws {
        let function = try read("supabase/functions/generate-embedding/index.ts")
        let docs = try combinedReadinessDocs()

        if function.contains("disabled: true") {
            #expect(docs.contains("generate-embedding` is disabled") || docs.contains("generate-embedding` remains"),
                    "Readiness docs must say generate-embedding is disabled.")
            #expect(docs.contains("dimension `0`") || docs.contains("dimension 0"),
                    "Readiness docs must say disabled generate-embedding returns dimension 0.")
            #expect(docs.contains("not production-ready"),
                    "Readiness docs must not imply app MemoryStore embeddings are production-ready while generate-embedding is disabled.")
        }
    }

    @Test func deepgramTranscribeIsDocumentedAsLocalOnlyBatchPath() throws {
        let function = try read("supabase/functions/deepgram-transcribe/index.ts")
        let docs = try combinedReadinessDocs()

        if function.contains("Currently UNUSED") || function.contains("local-only") {
            #expect(docs.contains("deepgram-transcribe` is local-only") || docs.contains("deepgram-transcribe` also remains local-only"),
                    "Readiness docs must mark deepgram-transcribe as local-only.")
            #expect(docs.contains("deepgram-token") && docs.contains("Deepgram WSS"),
                    "Readiness docs must distinguish live Deepgram WSS token flow from the parked batch proxy.")
        }
    }

    @Test func voiceOnboardingDoesNotClearResumeWhenExtractorFails() throws {
        let contents = try read("Sources/TimedKit/Features/Onboarding/VoiceOnboardingView.swift")

        #expect(contents.contains("EdgeFunctions.shared.authorizationHeader()"),
                "Voice onboarding must call extract-onboarding-profile with the current Supabase session JWT.")
        #expect(contents.contains("postTranscriptToExtractor() async -> Bool"),
                "Voice onboarding must know whether backend profile extraction persisted.")
        #expect(contents.contains("HTTPURLResponse") && contents.contains("200..<300"),
                "Voice onboarding must check non-2xx extractor responses instead of swallowing them.")
        #expect(contents.contains("let shouldResumeVoiceSetup = skipped || (extractProfile && !profilePersisted)"),
                "Failed profile extraction must leave pendingVoiceOnboarding true so setup remains resumable.")
        #expect(contents.contains("UserDefaults.standard.set(shouldResumeVoiceSetup, forKey: \"pendingVoiceOnboarding\")"),
                "Voice onboarding must persist the resumable setup flag after extractor failure.")
    }

    @Test func unwiredIOSSurfacesAreDocumentedHonestly() throws {
        let docs = try combinedReadinessDocs()
        let iosRoot = try read("Sources/TimedKit/AppEntry/TimediOSRootView.swift")
        let backgroundTasks = try read("Sources/TimedKit/AppEntry/IOSBackgroundTasks.swift")
        let pushManager = try read("Sources/TimedKit/AppEntry/IOSPushManager.swift")
        let appMain = try read("Platforms/iOS/TimediOSAppMain.swift")

        if iosRoot.contains("PlaceholderPane") {
            #expect(docs.contains("iOS remains simulator-build/scaffold only") || docs.contains("Scaffold / simulator-build only"),
                    "Readiness docs must mark iOS as scaffold-only while primary panes are placeholders.")
            #expect(docs.contains("placeholder") || docs.contains("PlaceholderPane"),
                    "Readiness docs must mention placeholder iOS panes.")
        }

        if backgroundTasks.contains("setTaskCompleted(success: true)") {
            #expect(docs.contains("BGTask workers") && docs.contains("not installed"),
                    "Readiness docs must say BGTask workers are not installed.")
        }

        let hasPushTokenRegistration = try sourceOccurrences(of: "register-push-token", excluding: [
            "Sources/TimedKit/AppEntry/IOSPushManager.swift",
        ]).isEmpty == false
        if pushManager.contains("tokenSink") && hasPushTokenRegistration == false {
            #expect(docs.contains("APNs token sink") && docs.contains("not installed"),
                    "Readiness docs must say APNs token registration is not wired.")
        }

        if appMain.contains("completionHandler(.noData)") {
            #expect(docs.contains("silent-push sync") || docs.contains("silent push currently returns `.noData`"),
                    "Readiness docs must say silent push sync is not wired.")
        }

        let hasShareQueueDrain = try sourceOccurrences(of: "share-queue.jsonl", excluding: [
            "Extensions/Share/ShareViewController.swift",
        ]).isEmpty == false
        if hasShareQueueDrain == false {
            #expect(docs.contains("Share extension") && docs.contains("without a main-app drain"),
                    "Readiness docs must say the Share queue has no main-app drain.")
        }

        let hasWidgetWriter = try sourceOccurrences(of: "SharedSnapshot.write(", excluding: [
            "Extensions/Widgets/SharedSnapshot.swift",
        ]).isEmpty == false
        if hasWidgetWriter == false {
            #expect(docs.contains("widget snapshot") && docs.contains("not wired"),
                    "Readiness docs must say widget snapshot writes are not wired.")
        }

        let hasLiveActivityStarter = try sourceOccurrences(of: "Activity<TimedConversationActivityAttributes>.request", excluding: [
            "Extensions/Widgets/TimedConversationLiveActivity.swift",
        ]).isEmpty == false
        if hasLiveActivityStarter == false {
            #expect(docs.contains("Live Activity coordinator") && docs.contains("not wired"),
                    "Readiness docs must say Live Activity lifecycle is not wired.")
        }
    }

    private func combinedReadinessDocs() throws -> String {
        try [
            "BUILD_STATE.md",
            "README.md",
            "docs/04-integrations.md",
            "docs/UNIFIED-BRANCH.md",
            "NEXT.md",
        ]
        .map { try read($0) }
        .joined(separator: "\n")
    }

    private func sourceOccurrences(of needle: String, excluding excludedPaths: Set<String>) throws -> [String] {
        let root = repoRoot()
        var matches: [String] = []

        for directory in ["Sources", "Platforms", "Extensions", "supabase/functions"] {
            let url = root.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                guard ["swift", "ts"].contains(fileURL.pathExtension) else { continue }

                let relativePath = relativePath(for: fileURL, root: root)
                guard excludedPaths.contains(relativePath) == false else { continue }

                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                if contents.contains(needle) {
                    matches.append(relativePath)
                }
            }
        }

        return matches
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
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
