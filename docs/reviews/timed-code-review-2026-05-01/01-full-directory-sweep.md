# Timed Full Directory Sweep Code Review — 2026-05-01

Review-only pass on branch `unified` (`git status --short --branch`: ahead 4; modified `BUILD_STATE.md`, `SESSION_LOG.md`). No build, test, install, formatter, checkout, pull, commit, or repo write was run.

## Executive Findings

| ID | Severity | Status | File:line | Finding | Impact | Concrete remediation |
|---|---|---|---|---|---|---|
| C-01 | critical | confirmed | `Sources/TimedKit/Core/Services/AuthService.swift:38`, `Sources/TimedKit/Core/Services/AuthService.swift:544`, `Sources/TimedKit/Core/Services/AuthService.swift:565`, `Sources/TimedKit/Core/Services/DataBridge.swift:24`, `supabase/functions/bootstrap-executive/index.ts:53`, `supabase/migrations/20260331000001_initial_schema.sql:69`, `supabase/migrations/20260331000001_initial_schema.sql:101`, `supabase/migrations/20260331000001_initial_schema.sql:180` | The Swift app aliases `executiveId` as `workspaceId`, `profileId`, and `emailAccountId`, while bootstrap only creates an `executives` row and the production schema still requires `workspaces`, `profiles`, and `email_accounts` foreign keys. | Task saves, email inserts, Gmail/Outlook sync, and server Trigger sync fail FK checks for normal bootstrapped users unless legacy rows are manually seeded. | Pick one identity model. Either bootstrap real `workspaces`, `profiles`, `workspace_members`, and `email_accounts` rows and persist their IDs in Swift, or migrate all affected tables/FKs/RLS to `executives.id` consistently. |
| C-02 | critical | confirmed | `Sources/TimedKit/Core/Services/EmailSyncService.swift:726`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:735`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:737`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:429`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:434`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:435`, `supabase/functions/classify-email/index.ts:25`, `supabase/functions/classify-email/index.ts:49`, `supabase/functions/classify-email/index.ts:56` | Swift calls `classify-email` with the embedded anon JWT and snake_case `message_id` / `workspace_id`, but the function requires a user JWT and camelCase `emailMessageId`, `workspaceId`, `profileId`. | Email classification returns 401 or 400, so triage buckets, question detection, quick-reply detection, embeddings, and correction-aware ranking do not run from client sync. | Call with the Supabase session access token and the function's exact body shape, including `profileId`; or add a separate service-role/internal classifier endpoint with strict tenant derivation. |
| C-03 | critical | confirmed | `supabase/functions/anthropic-proxy/index.ts:7`, `supabase/functions/anthropic-proxy/index.ts:23`, `supabase/functions/anthropic-proxy/index.ts:29`, `supabase/functions/deepgram-transcribe/index.ts:13`, `supabase/functions/deepgram-transcribe/index.ts:39`, `supabase/functions/deepgram-transcribe/index.ts:45`, `supabase/functions/elevenlabs-tts-proxy/index.ts:7`, `supabase/functions/elevenlabs-tts-proxy/index.ts:24`, `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:18`, `Sources/TimedKit/Core/Services/SpeechService.swift:57`, `Sources/TimedKit/Core/Clients/InterviewAIClient.swift:285`, `Sources/TimedKit/Core/Clients/CaptureAIClient.swift:103`, `Sources/TimedKit/Core/Clients/OnboardingAIClient.swift:170` | Legacy Anthropic, Deepgram, and ElevenLabs proxy functions are intentionally callable with the public anon key and forward arbitrary or weakly bounded provider requests. | Anyone who extracts the embedded anon JWT can spend Timed's provider keys and bypass user-level quota or entitlement checks. | Retire the legacy proxies or add `verifyAuth`, per-user quotas, model/voice allowlists, max body/audio limits, and migrate clients to the authenticated `anthropic-relay` / `orb-tts` pattern. |
| C-04 | critical | confirmed | `services/graphiti/app/main.py:220`, `services/graphiti/app/main.py:244`, `services/graphiti/fly.toml:28`, `services/graphiti/README.md:94` | Graphiti core exposes `/episode` and `/search` without bearer auth, while committed Fly config enables public HTTP ingress despite README claiming the service is private-only. | A public deployment can accept arbitrary graph writes/searches and trigger LLM/embedding proxy spend or data exposure. | Add bearer auth to Graphiti core and/or remove public `http_service` so only the private Fly network can reach it; update README and deployment config together. |
| H-01 | high | confirmed | `Sources/TimedKit/Core/Clients/SupabaseClient.swift:748`, `supabase/migrations/20260331000001_initial_schema.sql:131`, `trigger/src/tasks/graph-delta-sync.ts:276` | Swift upserts `email_messages` with `onConflict: "graph_message_id"`, but the only declared unique constraint is `(email_account_id, graph_message_id)`; Trigger uses the correct conflict target. | Client email/Gmail persistence can fail with PostgREST conflict-target errors or be unable to update existing rows. | Change Swift to `onConflict: "email_account_id,graph_message_id"` or add a global unique index if Graph IDs are truly global. |
| H-02 | high | confirmed | `Sources/TimedKit/Core/Services/OfflineSyncQueue.swift:79`, `Sources/TimedKit/Core/Services/OfflineSyncQueue.swift:103`, `Sources/TimedKit/Core/Services/GracefulDegradation.swift:115` | `OfflineSyncQueue.startMonitoring` and `flush` exist, but repo search only finds their declarations; `GracefulDegradation.flushBuffers` only logs. | Offline-enqueued email/calendar/Tier0 operations can accumulate indefinitely and never reach Supabase after connectivity returns. | Wire one app-level queue executor on launch/network restoration and dispatch each stored `operation_type` to the matching Supabase client write. |
| H-03 | high | confirmed | `Sources/TimedKit/Core/Services/EmailSyncService.swift:194`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:301`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:314`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:320`, `supabase/migrations/20260411000000_executives_table.sql:19` | The Swift `email_sync_driver` gate reads `executives` through REST using the anon key. The RLS policy only allows `auth.uid() = auth_user_id`, so the gate fails open to client sync. | When an executive is configured for server-side Trigger sync, the app can still poll locally and double-write or fight server ownership. | Read the driver through an authenticated Supabase session/JWT-backed client or move the decision to an authenticated Edge Function. |
| H-04 | high | confirmed | `Sources/TimedKit/Core/Services/GmailSyncService.swift:123`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:133`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:241`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:273`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:326` | Gmail sync increments `processed` and stamps `gmail_linked=true` after `persist`, but `persist` catches upsert failures and returns `Void`. | The app can claim Gmail is linked and synced while zero messages were stored, unblocking inbox-dependent experiences on false data. | Make `persist` throw or return `Bool`, increment counts only after a durable write, and stamp `gmail_linked` only after at least one successful account/message persistence or explicit account verification. |
| H-05 | high | confirmed | `supabase/functions/pipeline-health-check/index.ts:5`, `supabase/functions/pipeline-health-check/index.ts:369`, `supabase/functions/pipeline-health-check/index.ts:388`, `supabase/functions/poll-batch-results/index.ts:10`, `supabase/functions/poll-batch-results/index.ts:14`, `supabase/functions/poll-batch-results/index.ts:153`, `supabase/functions/renew-graph-subscriptions/index.ts:11`, `supabase/functions/renew-graph-subscriptions/index.ts:16` | Several service-role Edge Functions have no `verifyServiceRole` or signed-secret check before reading/mutating production state. | Unauthenticated callers can trigger service-role health writes, batch polling, signature writes, and subscription renewal routines. | Require `verifyServiceRole(req)` or a signed cron/webhook secret before any service-role work, and reject all other requests before creating privileged clients. |
| H-06 | high | confirmed | `supabase/functions/graph-webhook/index.ts:44`, `supabase/functions/graph-webhook/index.ts:46`, `supabase/functions/graph-webhook/index.ts:59`, `supabase/migrations/20260427000100_email_sync_state.sql:44`, `supabase/migrations/20260427000100_email_sync_state.sql:50` | `graph-webhook` only checks that a subscription exists when `clientState` is present; it never requires or compares `clientState` with the stored `graph_subscriptions.client_state`. | Spoofed Microsoft Graph notifications can insert webhook events and enqueue email pipeline work. | Store the subscription secret, require `notification.clientState`, compare it against the stored value for the subscription, and reject unknown/mismatched notifications. |
| H-07 | high | confirmed | `supabase/functions/renew-graph-subscriptions/index.ts:21`, `supabase/functions/renew-graph-subscriptions/index.ts:24`, `supabase/functions/renew-graph-subscriptions/index.ts:27`, `supabase/migrations/20260331000001_initial_schema.sql:77`, `supabase/migrations/20260331000001_initial_schema.sql:87` | `renew-graph-subscriptions` selects `oauth_access_token` and filters `is_active`, but `email_accounts` defines `access_token_enc` and `sync_enabled` instead. | The renewal job query fails before patching subscriptions, so Graph webhooks expire. | Align the function with the current schema or replace it with the Trigger app-only subscription manager. |
| H-08 | high | confirmed | `Sources/TimedKit/AppEntry/IOSBackgroundTasks.swift:26`, `Sources/TimedKit/AppEntry/IOSBackgroundTasks.swift:30`, `Sources/TimedKit/AppEntry/IOSBackgroundTasks.swift:57`, `Sources/TimedKit/AppEntry/IOSPushManager.swift:27`, `Sources/TimedKit/AppEntry/IOSPushManager.swift:42`, `Platforms/iOS/TimediOSAppMain.swift:86` | iOS BGTask handlers and APNs token forwarding default to no-ops, and repo search finds no installed worker, token sink, or `register-push-token` Edge Function. | iOS background refresh, silent push, and push-token registration are declared but do not perform production sync or alert delivery. | Install real workers during iOS app launch, add the authenticated token-registration endpoint, and make silent push invoke the same single-pass sync path. |
| H-09 | high | confirmed | `Extensions/Share/ShareViewController.swift:90`, `Extensions/Share/ShareViewController.swift:101`, `Extensions/Share/ShareViewController.swift:106` | The Share extension appends captures to `share-queue.jsonl`, but repo search finds no main-app reader/drain. | Shared content appears accepted by the extension but is stranded in the App Group container. | Add a foreground/BG drain in the main app that atomically reads, posts/authenticates, and truncates or checkpoints the JSONL queue. |
| H-10 | high | confirmed | `trigger/src/tasks/graph-delta-sync.ts:255`, `trigger/src/tasks/graph-delta-sync.ts:262`, `supabase/functions/bootstrap-executive/index.ts:53`, `supabase/migrations/20260331000001_initial_schema.sql:69` | Server-side Graph delta sync resolves `email_accounts` by executive email, but bootstrap does not create any `email_accounts` row. | Trigger server sync silently skips or fails for ordinary users even if `email_sync_driver='server'`. | Create/link `email_accounts` during OAuth connection and make Trigger state keyed by that durable account row, not by inferred email alone. |
| H-11 | high | needs verification | `Sources/TimedKit/Core/Services/AuthService.swift:155`, `Sources/TimedKit/Core/Services/AuthService.swift:160`, `Sources/TimedKit/Core/Services/AuthService.swift:162` | `ASWebAuthenticationSession` is held in a local variable only; the service does not retain it across the async continuation. | OAuth sign-in can be cancelled or deallocated unexpectedly on some OS paths before the callback resumes. | Store the session as an `AuthService` property and nil it in the completion handler after resuming. |
| H-12 | high | confirmed | `Sources/TimedKit/Core/Services/AuthService.swift:401`, `Sources/TimedKit/Core/Services/AuthService.swift:413`, `Sources/TimedKit/Core/Services/AuthService.swift:418`, `Platforms/Mac/Timed.entitlements:24` | Outlook Graph access uses an in-memory token only because MSAL keychain persistence is disabled for ad-hoc builds. | Outlook sync stops after token expiry and requires manual reconnect roughly hourly. | Complete signed keychain entitlement setup or move Outlook refresh/server polling to a backend-held token model. |
| M-01 | medium | confirmed | `Sources/TimedKit/AppEntry/TimediOSRootView.swift:154`, `Sources/TimedKit/AppEntry/TimediOSRootView.swift:164`, `Sources/TimedKit/AppEntry/TimediOSRootView.swift:176`, `Sources/TimedKit/AppEntry/TimediOSRootView.swift:191` | The iOS app's primary tabs are placeholders and the orb sheet passes empty task/calendar state. | The iOS target is not a functional port of Today, Plan, Briefing, Triage, or Settings. | Introduce shared iOS state injection and instantiate the real panes, or hide iOS production claims until those flows are wired. |
| M-02 | medium | confirmed | `Extensions/Widgets/SharedSnapshot.swift:3`, `Extensions/Widgets/SharedSnapshot.swift:53`, `Extensions/Widgets/SharedSnapshot.swift:69` | Widget snapshot writing is implemented/commented as DataBridge-owned, but repo search finds no `SharedSnapshot.write` call. | Widgets fall back to placeholder or stale data instead of real daily priorities/events. | Write `TodaySnapshot` from the main app after successful data changes and request widget timeline reloads. |
| M-03 | medium | confirmed | `Extensions/Widgets/TimedConversationLiveActivity.swift:6`, `Extensions/Widgets/TimedConversationLiveActivity.swift:61` | Live Activity UI exists, but repo search finds no `Activity<TimedConversationActivityAttributes>.request`, update, or end call. | Dynamic Island/Lock Screen activity never starts despite shipped extension code. | Add a main-app ActivityKit coordinator around conversation and sync state transitions. |
| M-04 | medium | confirmed | `Sources/TimedKit/Core/Services/EmailSyncService.swift:430`, `Sources/TimedKit/Core/Services/CalendarSyncService.swift:231`, `Sources/TimedKit/Core/Services/CalendarSyncService.swift:264`, `Sources/TimedKit/Core/Services/GmailCalendarSyncService.swift:99`, `Sources/TimedKit/Core/Services/GmailCalendarSyncService.swift:135`, `supabase/migrations/20260427230000_email_calendar_to_tier0_triggers.sql:77`, `supabase/migrations/20260427230000_email_calendar_to_tier0_triggers.sql:156`, `supabase/migrations/20260411020000_tier0_observations.sql:3` | Swift services insert Tier0 observations directly and DB triggers also create Tier0 rows after email/calendar inserts; `tier0_observations` has no idempotency key. | Duplicate observations pollute memory, ranking, and downstream intelligence once both paths are active. | Pick one writer per source or add a unique idempotency key such as `(source,event_type,entity_id)` and use upserts. |
| M-05 | medium | confirmed | `Sources/TimedKit/Core/Clients/SupabaseClient.swift:466`, `Sources/TimedKit/Core/Clients/SupabaseClient.swift:474`, `Sources/TimedKit/Core/Clients/SupabaseClient.swift:967`, `Sources/TimedKit/Core/Clients/SupabaseClient.swift:970` | `fetchWorkspaceMembers` selects nested `profiles(email, full_name)` but decodes into flat `WorkspaceMemberRow.email/fullName`. | Workspace member fetches can decode-fail or lose profile fields. | Decode a nested `ProfileRow` or alias selected profile columns into flat fields supported by PostgREST. |
| M-06 | medium | confirmed | `Sources/TimedKit/Core/Clients/GoogleClient.swift:155`, `Sources/TimedKit/Core/Clients/GoogleClient.swift:156`, `Sources/TimedKit/Core/Clients/GoogleClient.swift:172`, `Platforms/iOS/Info.plist:59`, `Platforms/iOS/Info.plist:67`, `Platforms/Mac/Info.plist:55`, `Platforms/Mac/Info.plist:62` | Google sign-in is macOS/AppKit-only and iOS Info.plist lacks the Google reversed client scheme/GIDClientID present on macOS. | Additive Google OAuth/Gmail cannot work on iOS even though the iOS shell exists. | Add the iOS Google URL scheme/client ID and implement the UIKit presenting path for `GIDSignIn`. |
| M-07 | medium | confirmed | `Sources/TimedKit/Core/Services/HistoricalBackfillService.swift:49`, `Sources/TimedKit/Core/Services/HistoricalBackfillService.swift:58`, `Sources/TimedKit/Core/Services/HistoricalBackfillService.swift:61` | Historical backfill is TODO-only and marks itself completed with zero observations. | Product state can report completed backfill while no historical email/calendar context exists. | Either disable the completed state until real page processing exists or implement the Graph/Gmail/calendar backfill with persisted cursors. |
| M-08 | medium | confirmed | `supabase/functions/pipeline-health-check/index.ts:327`, `supabase/functions/pipeline-health-check/index.ts:337`, `supabase/functions/pipeline-health-check/index.ts:380` | Pipeline health returns `ok` for backfill and nightly pipeline placeholder checks. | Production monitoring can show green while critical pipelines do not exist or are stalled. | Return `unknown`/`not_implemented` or implement real checks before including them in green health summaries. |
| M-09 | medium | confirmed | `supabase/functions/weekly-pruning/index.ts:44`, `supabase/functions/weekly-pruning/index.ts:54`, `supabase/functions/weekly-pruning/index.ts:58`, `supabase/functions/weekly-pruning/index.ts:67` | Weekly pruning counts archive/tombstone candidates but does not archive raw payloads or tombstone old rows. | Tier0 raw data retention grows beyond the stated privacy/storage lifecycle. | Implement storage archival and row redaction/tombstoning, then verify with retention-specific tests. |
| M-10 | medium | confirmed | `scripts/package_app.sh:6`, `scripts/package_app.sh:154`, `scripts/create_dmg.sh:5`, `scripts/notarize_app.sh:5`, `scripts/notarize_app.sh:9` | Packaging creates `dist.noindex/Timed.app`, but notarization expects `dist/timed.app`. | The documented package-then-notarize flow fails before submission. | Align notarization paths/case with `scripts/package_app.sh` and `scripts/create_dmg.sh`, or make package output the notarization path. |
| M-11 | medium | confirmed | `Tests/DataBridgeTests.swift:15`, `Tests/DataBridgeTests.swift:19`, `Tests/DataBridgeTests.swift:22`, `Tests/DataBridgeTests.swift:26`, `Tests/DataBridgeTests.swift:50`, `Tests/DataBridgeTests.swift:54` | DataBridge tests assert tautologies such as `tasks.isEmpty || !tasks.isEmpty` and cover only crash absence. | The most fragile sync and persistence contracts above are untested. | Replace tautologies with deterministic local-store assertions and add focused tests for ID bootstrap, email upsert conflict, classifier payload/auth, Gmail persistence counts, and offline queue flushing. |
| L-01 | low | confirmed | `scripts/package_app.sh:144`, `scripts/package_app.sh:150`, `Platforms/Mac/Timed.entitlements:24`, `Platforms/Mac/Timed.entitlements:30` | Packaging comments say keychain access groups are applied to fix MSAL, while entitlements explicitly document that keychain access groups were removed and MSAL still fails. | Maintainers can trust the wrong packaging behavior and miss the reconnect regression. | Update comments to match the current entitlement reality. |
| L-02 | low | confirmed | `Platforms/Mac/Info.plist:33`, `Platforms/Mac/Info.plist:35` | Mac privacy strings claim Timed writes Apple Calendar events and automates local workflows, conflicting with the product boundary that Timed observes/recommends and does not act. | App Store/privacy review and user trust copy are inconsistent with actual product constraints. | Reword usage descriptions to match read/observe-only behavior or remove permissions that are not needed. |
| L-03 | low | confirmed | `Platforms/iOS/TimediOSAppMain.swift:40`, `Platforms/iOS/TimediOSAppMain.swift:41`, `Platforms/iOS/TimediOSAppMain.swift:45` | The iOS app requests notification permission as soon as the UI appears despite the comment saying it should happen after onboarding. | First-run permission timing is premature and likely lowers opt-in. | Move the call behind onboarding or the first user-visible alert-delivery value moment. |
| L-04 | low | confirmed | `trigger/scripts/replay.ts:203`, `trigger/scripts/replay.ts:251`, `trigger/scripts/export-training-data.ts:205`, `trigger/scripts/export-training-data.ts:243` | Trigger replay/export training-data scripts contain TODO/stub core routines. | Operational replay and training export commands are not production-ready recovery tools. | Implement or remove the scripts from production runbooks until functional. |
| L-05 | low | confirmed | `Sources/TimedKit/Core/Services/AuthService.swift:441`, `Sources/TimedKit/Core/Services/AuthService.swift:443`, `Sources/TimedKit/Core/Services/AuthService.swift:455` | `signOut()` returns immediately when the Supabase client is nil, before clearing local signed-in state and tokens. | Local-only or misconfigured launches can keep stale auth/UI state after sign-out. | Clear local published state and tokens before or regardless of remote `auth.signOut()`. |
| L-06 | low | needs verification | `project.yml:84` | iOS bundle ID is `com.timed.ios`, while surrounding project docs reference Timed under the `com.ammarshahin.timed` namespace. | App Store Connect, OAuth redirect schemes, entitlements, and associated domains may not line up across targets. | Confirm the intended iOS bundle ID and update project config, OAuth redirect schemes, and associated domains together. |

## Directory / Module Sweep

### Root, Build Config, Packaging

Reviewed: `Package.swift`, `project.yml`, `Platforms/*/Info.plist`, entitlements, `scripts/package_app.sh`, `scripts/create_dmg.sh`, `scripts/notarize_app.sh`, core docs required by session contract.

Purpose: SwiftPM/Xcode target definition, platform bundle metadata, signing, packaging, notarization, and branch/build state.

Notable concerns:

- `Package.swift` is coherent with the documented stack: Swift 6.1, macOS 15/iOS 18, TCA, Supabase, MSAL, GRDB, usearch, Swift Testing, ElevenLabs, GoogleSignIn.
- Packaging and DMG scripts agree on `dist.noindex/Timed.app`; notarization does not.
- Mac entitlement comments and packaging comments disagree on keychain-group behavior.
- macOS privacy strings currently advertise write/automation capabilities beyond the no-action product boundary.
- iOS bundle ID needs confirmation against OAuth/App Store/associated-domain assumptions.

### App Entry, macOS/iOS Shims, Extensions

Reviewed: `Sources/TimedKit/AppEntry/*`, `Platforms/Mac/*`, `Platforms/iOS/*`, `Extensions/Share/*`, `Extensions/Widgets/*`.

Purpose: Thin platform entry points around shared `TimedKit`, URL routing, session restore, iOS tab shell, background tasks, APNs, share extension queueing, widgets, and Live Activity.

Notable concerns:

- macOS app entry is thin and routes into `TimedAppShell`; session restore and URL handling live in shared code.
- iOS is structurally present but largely placeholder-only: tab destinations do not instantiate real feature panes and the orb has empty planning/calendar state.
- iOS BGTask/APNs APIs are declared but unwired; they currently complete or forward to no-op closures.
- Share extension captures are written to an App Group queue with no main-app drain.
- Widget snapshot and Live Activity code exist but are not wired from the main app.

### TimedKit Core Services and Clients

Reviewed: `AuthService`, `SupabaseClient`, `SupabaseEndpoints`, `DataBridge`, `EmailSyncService`, `GmailSyncService`, `CalendarSyncService`, `GmailCalendarSyncService`, `Tier0Writer`, `OfflineSyncQueue`, `GracefulDegradation`, `HistoricalBackfillService`, Google/Microsoft clients, voice/AI clients.

Purpose: Auth/session restore, OAuth token providers, local/Supabase persistence, Microsoft/Gmail sync, calendar observations, Tier0 observation writes, offline buffering, voice/AI calls, and production data bridges.

Notable concerns:

- The largest production blocker is the split identity model: Swift uses `executiveId` everywhere, while the database still requires legacy workspace/profile/account rows.
- Email classification cannot currently be triggered by the Swift clients due to auth and payload mismatch.
- Gmail sync can report success after failed persistence.
- Server-side sync gating is ineffective because it uses anon REST against RLS-protected `executives`.
- Offline queue plumbing is present but not started/flushed by app-level code.
- Swift and DB triggers duplicate Tier0 creation for email/calendar sources.
- `WorkspaceMemberRow` decoding does not match the nested PostgREST select.
- Historical backfill is a placeholder that marks itself complete.

### SwiftUI Feature Surfaces

Reviewed representative large surfaces and cross-feature wiring: `TimedRootView`, `TodayPane`, `PlanPane`, `TriagePane`, `MorningInterviewPane`, onboarding, capture/orb clients, preferences/settings paths, and iOS shell.

Purpose: Main macOS product UI, planning/triage/today workflows, onboarding, voice capture, and sync status surfaces.

Notable concerns:

- macOS is the only substantial app surface; iOS routes to placeholder panes.
- `TimedRootView` starts core auth-driven sync paths, so it inherits the identity, token-expiry, Gmail, and email-sync-driver bugs above.
- Large view files remain high-risk for regression, but the confirmed production bugs are mostly service/data-contract issues rather than isolated SwiftUI rendering defects.

### Supabase Migrations and Edge Functions

Reviewed: migrations under `supabase/migrations`, shared auth/config helpers, AI proxies/relays, email classification, bootstrap, webhook, health, pruning, Graph subscription renewal, batch polling, voice functions, Gmail/Graph function set.

Purpose: Production database schema/RLS, user bootstrap, AI calls through Edge Functions, classification, Graph webhook handling, health checks, pruning, and scheduled/service-role jobs.

Notable concerns:

- Schema still contains workspace/profile/email-account FKs while the current app stack moved toward executive IDs.
- `classify-email` has a good authenticated tenant-validation model, but Swift callers do not meet its contract.
- Newer authenticated functions (`anthropic-relay`, `orb-tts`, `voice-llm-proxy`) are materially safer than legacy anon-key proxies, but legacy functions remain deployed in-tree and used by clients.
- Several service-role functions are callable without service-role verification.
- Graph webhook validation does not compare `clientState`.
- Health/pruning/backfill functions contain placeholders that report or imply more production readiness than implemented.

### Trigger.dev Tasks and Tooling

Reviewed: `trigger/src/tasks/*`, Trigger Supabase/Graph helpers, Trigger scripts, config/package files.

Purpose: Server-side Microsoft Graph delta sync, calendar delta sync, NREM/REM intelligence tasks, replay/export tooling, and Trigger deployment config.

Notable concerns:

- `graph-delta-sync` uses the correct email-message conflict target, unlike Swift.
- Server Graph sync depends on `email_accounts` rows that bootstrap does not create.
- Replay/export scripts are stubs, so recovery/training-data runbooks cannot rely on them yet.

### Services

Reviewed: `services/graphiti`, `services/graphiti-mcp`, `services/skill-library-mcp`.

Purpose: Graphiti graph ingestion/search service, authenticated MCP wrapper, and authenticated skill-library MCP.

Notable concerns:

- `graphiti-mcp` and `skill-library-mcp` implement bearer-token style protection.
- Graphiti core itself does not, and committed Fly config exposes public HTTP ingress while README claims private-only reachability.

### Tests and Docs

Reviewed: Swift tests, Trigger/service test-adjacent scripts, and production-behavior docs that materially affect deployment expectations.

Purpose: Regression coverage, operational guidance, and current-state tracking.

Notable concerns:

- Existing Swift tests do not cover the main sync/auth/schema contracts that are currently broken.
- `DataBridgeTests` contain tautological assertions and do not prove persistence behavior.
- Docs accurately capture several known gaps, but some status language is more optimistic than code reality for iOS, backfill, classification, and packaging/notarization.

## Verification Commands Needed After Fixes

Do not treat this list as commands already run. This review intentionally did not run builds or tests.

```bash
swift build
swift test
swift test --filter DataBridgeTests
xcodegen generate
xcodebuild -skipMacroValidation -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -scheme TimedMacApp -destination 'platform=macOS' build
```

Add or update targeted Swift tests before relying on the full suite:

```bash
swift test --filter AuthServiceBootstrapTests
swift test --filter SupabaseEmailMessageUpsertTests
swift test --filter EmailClassificationContractTests
swift test --filter GmailSyncPersistenceTests
swift test --filter OfflineSyncQueueTests
```

Supabase/Trigger/service verification after server fixes:

```bash
supabase db lint
supabase migration up
supabase functions serve classify-email
supabase functions serve anthropic-relay
supabase functions serve orb-tts
cd trigger && pnpm typecheck
cd trigger && pnpm test
cd services/graphiti && python -m pytest
```
