# Timed Master Issue List - 2026-05-01

Review scope: full codebase review of `/Users/integrale/time-manager-desktop` on `unified`.

Read-only constraints held for the review: no repo edits, no commits, no destructive commands, no builds/tests/package installs run. The installed Codex CLI could not start because the current sandbox could not access `/Users/integrale/.codex/sessions`; the review was completed with five parallel `gpt-5.5` / `xhigh` subagents and outputs were written under `/private/tmp/timed-code-review-2026-05-01/`.

Branch/worktree observed by the review agents: `unified`, ahead of `origin/unified` by 4 commits, with pre-existing modifications to `BUILD_STATE.md` and `SESSION_LOG.md`.

## Top 20 Issues Ranked By Impact

| Rank | Severity | Status | Issue | Exact references | Why it matters | Recommended fix |
|---:|---|---|---|---|---|---|
| 1 | critical | confirmed | Local ignored Docker compose file contains live-looking Supabase service-role and provider secrets. | `docker-compose.local.yml:12`, `docker-compose.local.yml:15`, `docker-compose.local.yml:18`, `docker-compose.local.yml:31`, `docker-compose.local.yml:33`, `docker-compose.local.yml:34`, `docker-compose.local.yml:54`, `.gitignore:19` | A leaked local workspace, backup, support bundle, or forced add exposes RLS-bypass Supabase access plus provider billing keys. | Rotate every value present, replace literals with env interpolation, keep only `.example` config in repo, and make secret scanning blocking. |
| 2 | critical | confirmed | Tracked handoff documentation leaks Graphiti/MCP/Neo4j infrastructure secrets. | `HANDOFF.md:181`, `HANDOFF.md:183`, `HANDOFF.md:184` | Repo readers or shared artifacts can authenticate to graph infrastructure and tamper with memory/context services. | Rotate leaked tokens/passwords, remove tracked values, and consider Git history purge if the branch was pushed/shared. |
| 3 | critical | confirmed | Telegram control bot token is tracked in repo. | `scripts/ralph-telegram.ts:23`, `scripts/ralph-telegram.ts:24`, `.codex/ralph/.telegram-chat-id:1`, `scripts/ralph-telegram.ts:201`, `scripts/ralph-telegram.ts:226`, `scripts/ralph-telegram.ts:236` | Anyone with repo access can control the bot or mutate/stop local automation. | Revoke the bot token, move the replacement to an environment secret/keychain, remove tracked chat IDs, and block future secrets in CI. |
| 4 | critical | confirmed | Legacy provider-cost Edge Functions are callable with the public anon key and forward weakly bounded paid-provider requests. | `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:18`, `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:31`, `supabase/functions/anthropic-proxy/index.ts:7`, `supabase/functions/anthropic-proxy/index.ts:23`, `supabase/functions/anthropic-proxy/index.ts:29`, `supabase/functions/anthropic-proxy/index.ts:31`, `supabase/functions/elevenlabs-tts-proxy/index.ts:7`, `supabase/functions/elevenlabs-tts-proxy/index.ts:24`, `supabase/functions/elevenlabs-tts-proxy/index.ts:37`, `supabase/functions/deepgram-transcribe/index.ts:13` | Extracting the shipped anon key can turn Timed into an Anthropic/ElevenLabs/Deepgram cost proxy. | Undeploy or retire legacy proxies; otherwise add `verifyAuth`, per-user quota/rate limits, model/voice/body allowlists, max request sizes, and migrate clients to hardened relays. |
| 5 | critical | confirmed | Graphiti core exposes unauthenticated write/search routes while Fly config publishes HTTP ingress. | `services/graphiti/fly.toml:28`, `services/graphiti/app/main.py:185`, `services/graphiti/app/main.py:220`, `services/graphiti/app/main.py:244` | A reachable service can accept arbitrary graph writes and return graph facts, enabling graph poisoning and data disclosure. | Remove public `http_service` or require bearer auth on all non-health endpoints; keep core Graphiti private behind the MCP service. |
| 6 | critical | confirmed | App identity model is split: Swift aliases `executiveId` as workspace/profile/email account IDs while schema still requires legacy FK rows. | `Sources/TimedKit/Core/Services/AuthService.swift:38`, `Sources/TimedKit/Core/Services/AuthService.swift:544`, `Sources/TimedKit/Core/Services/AuthService.swift:565`, `Sources/TimedKit/Core/Services/DataBridge.swift:24`, `supabase/functions/bootstrap-executive/index.ts:53`, `supabase/migrations/20260331000001_initial_schema.sql:69`, `supabase/migrations/20260331000001_initial_schema.sql:101`, `supabase/migrations/20260331000001_initial_schema.sql:180` | Normal bootstrapped users can hit FK/RLS failures across task saves, email inserts, Gmail/Outlook sync, and Trigger sync. | Pick one identity model: either bootstrap durable `workspaces`, `profiles`, `workspace_members`, and `email_accounts`, or migrate affected tables/RLS to `executives.id`. |
| 7 | high | confirmed | Several service-role Edge Functions lack explicit service-role auth gates. | `supabase/functions/poll-batch-results/index.ts:10`, `supabase/functions/poll-batch-results/index.ts:14`, `supabase/functions/pipeline-health-check/index.ts:369`, `supabase/functions/pipeline-health-check/index.ts:388`, `supabase/functions/renew-graph-subscriptions/index.ts:11`, `supabase/functions/renew-graph-subscriptions/index.ts:16`, `scripts/deploy_security_hardening.sh:24` | If deployed with normal anon JWT gateway verification, public clients can trigger privileged writes, polling, subscription renewal, or health alert spam. | Add shared `verifyServiceRole(req)` or signed cron/webhook secrets before creating privileged clients; deploy or retire each function intentionally. |
| 8 | high | confirmed | Tenant IDs are trusted from request bodies in multiple authenticated Edge Functions. | `supabase/functions/estimate-time/index.ts:42`, `supabase/functions/estimate-time/index.ts:51`, `supabase/functions/generate-profile-card/index.ts:36`, `supabase/functions/generate-profile-card/index.ts:45`, `supabase/functions/detect-reply/index.ts:21`, `supabase/functions/detect-reply/index.ts:27`, `supabase/functions/parse-voice-capture/index.ts:26`, `supabase/functions/parse-voice-capture/index.ts:34` | A signed-in user can supply another tenant's UUIDs and read, summarize, or mutate cross-tenant data through service-role paths. | Resolve `authUserId -> executive/workspace/profile` server-side, reject mismatched body IDs, and scope all reads/writes by owned tenant columns. |
| 9 | high | confirmed | `classify-email` validates tenant IDs but fetches/updates email rows by ID only. | `supabase/functions/classify-email/index.ts:37`, `supabase/functions/classify-email/index.ts:57`, `supabase/functions/classify-email/index.ts:83`, `supabase/functions/classify-email/index.ts:112`, `supabase/functions/classify-email/index.ts:280` | A caller with their own tenant IDs and a victim email UUID could send victim email data through the LLM path or alter classification. | Add ownership predicates to every email read/update: `workspace_id`, `profile_id`, or current executive-derived account scope. |
| 10 | high | confirmed | Microsoft Graph webhook does not require or compare `clientState`. | `Sources/TimedKit/Core/Clients/GraphClient.swift:441`, `Sources/TimedKit/Core/Clients/GraphClient.swift:446`, `supabase/functions/graph-webhook/index.ts:44`, `supabase/functions/graph-webhook/index.ts:47`, `supabase/functions/graph-webhook/index.ts:59`, `supabase/functions/graph-webhook/index.ts:77`, `supabase/migrations/20260427000100_email_sync_state.sql:44`, `supabase/migrations/20260427000100_email_sync_state.sql:50` | Forged/replayed notifications can enqueue pipeline work under service-role processing. | Persist subscription `clientState`, require it on every notification, timing-safe compare to stored value, and reject before inserting/queueing on mismatch. |
| 11 | critical | confirmed | Email/calendar Tier 0 observations are emitted by both DB triggers and Swift services without an idempotency key. | `supabase/migrations/20260427230000_email_calendar_to_tier0_triggers.sql:77`, `supabase/migrations/20260427230000_email_calendar_to_tier0_triggers.sql:156`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:425`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:326`, `Sources/TimedKit/Core/Services/CalendarSyncService.swift:241`, `Sources/TimedKit/Core/Services/Tier0Writer.swift:78`, `supabase/migrations/20260411020000_tier0_observations.sql:3` | Duplicate raw observations distort memory, alert scoring, briefings, Graphiti/NREM inputs, and provider costs. | Choose one owner for Tier 0 bridging, add deterministic idempotency/unique constraints, switch writes to conflict-safe upserts, and dedupe existing rows. |
| 12 | high | confirmed | Swift calls `classify-email` with anon auth and the wrong payload shape. | `Sources/TimedKit/Core/Services/EmailSyncService.swift:726`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:735`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:737`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:429`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:434`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:435`, `supabase/functions/classify-email/index.ts:25`, `supabase/functions/classify-email/index.ts:49`, `supabase/functions/classify-email/index.ts:56` | Email classification can return 401/400, disabling triage buckets, embeddings, question detection, and correction-aware ranking from client sync. | Call with current Supabase session JWT and the function's exact `emailMessageId`, `workspaceId`, `profileId` contract, or add a narrow internal classifier endpoint. |
| 13 | high | confirmed | Microsoft email delta can advance the delta cursor even when individual message processing fails. | `Sources/TimedKit/Core/Services/EmailSyncService.swift:407`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:430`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:447`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:454`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:459` | A failed upsert, Tier 0 emit, folder move, or classification can be skipped forever once Graph will no longer replay it. | Track failed message IDs, queue/dead-letter failures, and persist the new delta link only after durable storage or replay state exists. |
| 14 | high | confirmed | Gmail sync swallows hydration/upsert failures and can still advance `historyId` or mark Gmail linked. | `Sources/TimedKit/Core/Services/GmailSyncService.swift:123`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:133`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:202`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:241`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:248`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:273`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:326`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:429`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:434` | Gmail can appear linked/synced while messages were skipped or never persisted, corrupting inbox-dependent intelligence. | Make persistence failures throw or return success state; advance history only after durable store/queue; stamp `gmail_linked` after account verification and successful persistence. |
| 15 | high | confirmed | Offline queue and failed task remote writes are not durably replayed. | `Sources/TimedKit/Core/Services/OfflineSyncQueue.swift:79`, `Sources/TimedKit/Core/Services/OfflineSyncQueue.swift:86`, `Sources/TimedKit/Core/Services/OfflineSyncQueue.swift:103`, `Sources/TimedKit/Core/Services/GracefulDegradation.swift:115`, `Sources/TimedKit/Core/Services/GracefulDegradation.swift:116`, `Sources/TimedKit/Core/Services/DataBridge.swift:24`, `Sources/TimedKit/Core/Services/DataBridge.swift:58`, `Sources/TimedKit/Core/Services/DataBridge.swift:61` | Local UI can look correct while Supabase and intelligence pipelines permanently miss task/email/calendar/Tier0 changes. | Register one operation dispatcher on app launch/network restoration, queue remote write failures with idempotency keys, and expose pending/permanent failure diagnostics. |
| 16 | high | confirmed | Client/server email sync driver gate fails open because Swift reads RLS-protected `executives` with anon credentials. | `Sources/TimedKit/Core/Services/EmailSyncService.swift:194`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:293`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:301`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:317`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:320`, `supabase/migrations/20260411000000_executives_table.sql:16`, `supabase/migrations/20260411000000_executives_table.sql:19`, `supabase/migrations/20260427000000_email_sync_driver.sql:10` | Users configured for server-side Trigger sync can still be polled by the client, causing duplicate or racing ingestion. | Read the flag with a user JWT or narrow authenticated function; default to visible degraded state instead of silent client polling. |
| 17 | high | confirmed | Email message upsert conflict target in Swift does not match the schema. | `Sources/TimedKit/Core/Clients/SupabaseClient.swift:748`, `supabase/migrations/20260331000001_initial_schema.sql:131`, `trigger/src/tasks/graph-delta-sync.ts:276` | Client email/Gmail persistence can fail with PostgREST conflict-target errors or fail to update existing rows. | Use `onConflict: "email_account_id,graph_message_id"` or add a deliberate global unique index if Graph IDs are truly global. |
| 18 | high | confirmed | Server-side Graph sync and subscription renewal are schema-drifted from current account/bootstrap state. | `trigger/src/tasks/graph-delta-sync.ts:255`, `trigger/src/tasks/graph-delta-sync.ts:262`, `supabase/functions/bootstrap-executive/index.ts:53`, `supabase/migrations/20260331000001_initial_schema.sql:69`, `supabase/functions/renew-graph-subscriptions/index.ts:21`, `supabase/functions/renew-graph-subscriptions/index.ts:24`, `supabase/functions/renew-graph-subscriptions/index.ts:27`, `supabase/migrations/20260331000001_initial_schema.sql:77`, `supabase/migrations/20260331000001_initial_schema.sql:87` | Trigger server sync can skip ordinary users because `email_accounts` rows are not bootstrapped, and renewal queries reference old columns. | Create/link durable `email_accounts` during OAuth connection and align renewal code with current `graph_subscriptions`/token schema or retire legacy renewal. |
| 19 | high | confirmed | Microsoft and Gmail sync paths are serial N+1 pipelines with per-message classification and repeated network/model work. | `Sources/TimedKit/Core/Services/GmailSyncService.swift:269`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:275`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:345`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:407`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:411`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:430`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:726` | First sync or large deltas can take minutes, hit rate limits, drain battery, and multiply Edge Function/model calls. | Reuse tokens per pass, hydrate with bounded concurrency, chunk/bulk upserts, cache folder lookups, and batch/queue classification server-side. |
| 20 | high | confirmed | Packaging, notarization, and CI disagree on artifact paths while release packaging is still ad-hoc signed. | `scripts/package_app.sh:5`, `scripts/package_app.sh:6`, `scripts/package_app.sh:150`, `scripts/create_dmg.sh:5`, `scripts/notarize_app.sh:5`, `scripts/notarize_app.sh:6`, `scripts/notarize_app.sh:9`, `scripts/notarize_app.sh:30`, `.github/workflows/macos-ci.yml:35`, `.github/workflows/macos-ci.yml:42` | A release candidate can package successfully but fail notarization/artifact upload, leaving users with an unnotarized app. | Standardize one app path/case, package from the Xcode-built app or shared plist, Developer ID sign with hardened runtime, notarize/staple, and gate release on verification. |

## Recommended Fix Order

1. Rotate and remove leaked secrets: local compose values, tracked handoff values, Telegram token, Graphiti/MCP/Neo4j credentials, Supabase service-role key if there is any chance of exposure.
2. Make secret detection blocking: gitleaks at minimum, then baseline semgrep/actionlint separately.
3. Lock down external cost/data surfaces: undeploy or authenticate legacy Anthropic/ElevenLabs/Deepgram proxies; make Graphiti private or bearer-protected.
4. Add service-role gates to privileged Edge Functions and verify remote JWT settings for every retained function.
5. Fix cross-tenant authorization in body-ID Edge Functions, including `classify-email` ownership predicates.
6. Fix Graph webhook `clientState` validation before relying on webhook-triggered ingestion.
7. Resolve the identity model mismatch between `executives` and workspace/profile/email-account tables.
8. Repair email account/bootstrap and Graph subscription schema drift.
9. Fix Swift `classify-email` auth/payload contract.
10. Fix Microsoft and Gmail cursor advancement so failed messages are queued/dead-lettered before cursors move.
11. Wire offline queue replay and queue failed DataBridge remote writes.
12. Choose a single Tier 0 bridge owner and add idempotency/unique constraints before deduping historical rows.
13. Fix email upsert conflict target and add tests around Supabase upsert contracts.
14. Batch Microsoft/Gmail sync and server-side classification to reduce foreground latency and provider pressure.
15. Fix packaging/notarization/CI path drift and release signing gates.
16. Add XcodeGen/Xcode target builds to CI, not only `swift build`.
17. Add dependency-lock coverage for Deno Edge Functions and service packages.
18. Upgrade public service runtimes/dependencies: Node 20 EOL services and Graphiti FastAPI/Starlette constraints.
19. Wire iOS/share/widget/live-activity/background paths or remove production claims until implemented.
20. Replace tautological/high-risk tests with targeted regression coverage for auth/bootstrap, sync cursors, offline replay, classification, and Tier 0 idempotency.

## Test And Build Commands After Fixes

These were not run during the review.

```bash
git branch --show-current
git status --short --branch

swift build
swift test
swift test --filter DataBridgeTests
swift test --filter EmailSyncServiceTests
swift test --filter GmailSyncServiceTests
swift test --filter OfflineSyncQueueTests
swift test --filter EmailClassificationContractTests

xcodegen generate
xcodebuild -project Timed.xcodeproj \
  -scheme TimedMac \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build

xcodebuild -project Timed.xcodeproj \
  -scheme TimediOS \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  build
```

```bash
supabase db lint
supabase migration list --linked
supabase functions list --project-ref fpmjuufefhtlwbfinxlx
supabase functions deploy <changed-function> --project-ref fpmjuufefhtlwbfinxlx

curl -i -X POST https://fpmjuufefhtlwbfinxlx.supabase.co/functions/v1/poll-batch-results \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H 'Content-Type: application/json' \
  -d '{}'
```

Expected result after service-role gating: non-service-role requests return `401` or `403`.

```bash
cd trigger
pnpm typecheck
pnpm test
pnpm exec trigger deploy --env prod --dry-run
```

```bash
cd services/graphiti
python -m pytest

cd ../graphiti-mcp
pnpm typecheck
pnpm build

cd ../skill-library-mcp
pnpm typecheck
pnpm build
```

```bash
bash scripts/package_app.sh
bash scripts/create_dmg.sh
codesign --verify --deep --strict dist.noindex/Timed.app
spctl --assess --type execute --verbose dist.noindex/Timed.app
TIMED_NOTARY_PROFILE=timed-notary bash scripts/notarize_app.sh
```

```bash
gitleaks detect --source . --redact --no-banner
actionlint

deno check --lock=supabase/functions/deno.lock supabase/functions/*/index.ts

psql "$SUPABASE_DB_URL" -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.get_top_observations('<exec_id>'::uuid, 24, 40);"
```

## Source Reports

- `/private/tmp/timed-code-review-2026-05-01/01-full-directory-sweep.md`
- `/private/tmp/timed-code-review-2026-05-01/02-security-audit.md`
- `/private/tmp/timed-code-review-2026-05-01/03-performance-architecture.md`
- `/private/tmp/timed-code-review-2026-05-01/04-production-readiness.md`
- `/private/tmp/timed-code-review-2026-05-01/05-dependency-config-audit.md`

