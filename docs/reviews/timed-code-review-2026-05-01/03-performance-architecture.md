| ID | Severity | Category | Status | Primary file:line | Finding | Impact | Remediation |
|---|---|---|---|---|---|---|---|
| P1 | critical | performance/data architecture | confirmed | `supabase/migrations/20260427230000_email_calendar_to_tier0_triggers.sql:77` | Email/calendar Tier 0 observations are emitted by both database triggers and Swift services, with no uniqueness guard on `tier0_observations`. | Duplicate memory rows, duplicate scoring/alerts, inflated briefings, extra Graphiti/NREM/model cost. | Pick one owner for Tier 0 bridging, add an idempotency key/unique index, switch inserts to conflict-safe upserts, then dedupe existing rows. |
| P2 | high | performance | confirmed | `Sources/TimedKit/Core/Services/GmailSyncService.swift:269` | Gmail 30-day backfill hydrates messages serially and fires classification per message. | First Gmail sync becomes a long N+1 API/model path; likely rate limits and stale UI after OAuth. | Hydrate with bounded concurrency, bulk upsert messages, and batch/queue classification server-side. |
| P3 | high | performance | confirmed | `Sources/TimedKit/Core/Services/EmailSyncService.swift:407` | Microsoft email delta processing does serial per-message token fetch, folder detection, upsert, Tier 0 emit, and classification. | Large deltas create one long foreground sync pass with repeated token/provider and Edge Function calls. | Pre-fetch tokens per pass, batch upserts, cache folder lookups, and batch/queue classification. |
| P4 | high | concurrency/performance | confirmed | `Sources/TimedKit/Core/Services/DeepgramSTTService.swift:122` | Audio tap spawns an unbounded `Task` per audio buffer and captures `self` strongly. | Backpressure from WebSocket/network creates task buildup, memory/CPU spikes, possible out-of-order audio chunks. | Replace per-buffer tasks with one bounded serial send loop; use weak capture in the tap and cancel the loop in `stop`. |
| P5 | high | performance/concurrency | confirmed | `Sources/TimedKit/Core/Services/DataBridge.swift:24` | Saving one task writes the whole task JSON file and launches detached upserts for every task. | Single checkbox/bucket edits become O(n) local writes plus O(n) network writes; overlapping detached syncs can race. | Add delta persistence methods and serialize sync; upsert only changed rows. |
| A1 | high | architecture | confirmed | `Sources/TimedKit/Core/Services/DataBridge.swift:20` | DataBridge still reads local JSON as source of truth for tasks and many non-task domains. | Authenticated state can diverge from Supabase; cross-device and server intelligence see different task/WOO/capture/calendar state. | Make Supabase primary when authenticated; use JSON/SQLite only as cache/offline queue or explicitly isolate local-only data. |
| P6 | medium | lifecycle/performance | needs verification | `Sources/TimedKit/Core/Services/NetworkMonitor.swift:14` | `NetworkMonitor.start()` is called from root `onAppear` without an idempotency guard or cancel path. | Reappearing root views can re-start one `NWPathMonitor`; possible runtime assertion/leaked path handler. | Add `isStarted`, expose `stop`, and start once from app/service lifecycle. |
| P7 | medium | SwiftUI performance | confirmed | `Sources/TimedKit/Features/TimedRootView.swift:13` | `TimedRootView` owns broad app state and recomputes bucket filters/reduces in body. | Any task/triage/calendar edit invalidates the split view and rescans task arrays repeatedly. | Move collections into narrower stores/selectors and precompute sidebar counts/minutes. |
| P8 | medium | Trigger.dev/backpressure | confirmed | `trigger/src/tasks/graph-calendar-delta-sync.ts:299` | Calendar delta sync walks all pages for each executive every five minutes with no per-exec cap; all executives are processed serially. | One noisy calendar can consume the whole 120s run and delay later executives; repeated ticks can lag behind. | Add per-run caps/resumable nextLink state, bounded concurrency, and schedule overlap/backpressure policy. |
| P9 | medium | SQL performance | needs verification | `supabase/migrations/20260428120000_score_memory.sql:60` | `get_top_observations` scores every recent Tier 0 row and computes `score_memory(obs)` twice, backed only by a BRIN recency index. | Orb observation retrieval can become CPU-heavy as Tier 0 grows, especially with duplicate email/calendar rows. | Compute score once in a subquery and add a selective btree index for `(profile_id, occurred_at desc)`; verify with `EXPLAIN`. |
| P10 | medium | voice latency/performance | confirmed | `Sources/TimedKit/Core/Services/StreamingTTSService.swift:33` | Streaming TTS accumulates all text, downloads all MP3 bytes, then plays. | Long orb answers have delayed first audio and memory grows with full MP3 payload size. | Either rename as one-shot or implement sentence/chunk-level audio queueing with bounded buffering. |
| A2 | medium | lifecycle/architecture | confirmed latent | `Sources/TimedKit/Core/Clients/SupabaseClient.swift:912` | Supabase realtime subscriptions spawn three untracked tasks and return no cancellation handle. | Once used by views, navigation can leak channels/tasks and multiply reload callbacks. | Return a subscription token that cancels tasks and unsubscribes the channel on view/service teardown. |
| A3 | medium | architecture | confirmed | `Sources/TimedKit/Core/Services/GracefulDegradation.swift:57` | Swift client directly checks Anthropic API health. | Client is coupled to provider availability and can show false degraded state; AI boundary is no longer exclusively Edge Functions. | Replace with a Supabase/Edge health endpoint that checks provider health server-side. |
| A4 | medium | architecture | confirmed | `supabase/functions/_shared/anthropic.ts:7` | Edge Function model routing is hardcoded/stale and some functions bypass the shared Anthropic helper. | Model upgrades require many edits; functions can drift on retry, caching, and observability behavior. | Centralize model aliases/env overrides in `_shared/anthropic.ts` and migrate direct fetch callers to it. |
| A5 | medium | lifecycle/architecture | needs verification | `Sources/TimedKit/Features/MorningCheckIn/MorningCheckInView.swift:44` | Morning check-in starts an ElevenLabs conversation in `.task` but only ends it through explicit buttons. | Closing/dismissing outside the button path can leave conversation state/live session work around longer than intended. | Add idempotent disappear cancellation/end handling and clear conversation/cancellables after end. |
| A6 | medium | architecture | confirmed | `trigger/src/tasks/graph-delta-sync.ts:97` | Server-side Trigger/Supabase code calls Microsoft Graph directly despite the written project rule that Graph calls go through `GraphClient.swift`. | Graph behavior is split across Swift, Trigger, and Edge Functions; auth/retry/pagination fixes must be duplicated. | Either update the architecture rule to bless a server-side Graph module, or centralize all TS Graph calls behind one shared client. |
| P11 | low | concurrency/performance | needs profiling | `Sources/TimedKit/Core/Clients/ConversationAIClient.swift:11` | Conversation streaming and SSE JSON parsing run on `@MainActor`. | Large orb/tool streams can add UI jank during active voice turns. | Keep UI mutation on MainActor but parse stream/tool JSON in a nonisolated worker or background task. |
| A7 | low | data reliability/architecture | confirmed | `Sources/TimedKit/Core/Clients/GraphClient.swift:516` | Client calendar fetch requests `$top=100` and ignores `@odata.nextLink`; response type cannot decode it. | Busy days/shared calendars silently truncate after 100 events. | Add nextLink decoding and bounded pagination. |

## Performance Findings

### P1 - Duplicate Tier 0 emission for email/calendar
- Severity: critical
- Status: confirmed
- Locations: `supabase/migrations/20260427230000_email_calendar_to_tier0_triggers.sql:77`, `supabase/migrations/20260427230000_email_calendar_to_tier0_triggers.sql:156`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:425`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:326`, `Sources/TimedKit/Core/Services/CalendarSyncService.swift:241`, `Sources/TimedKit/Core/Services/Tier0Writer.swift:78`, `supabase/migrations/20260411020000_tier0_observations.sql:3`
- Hot path reasoning: email rows are inserted by Microsoft and Gmail sync, then Swift emits Tier 0 and calls classification. The SQL `AFTER INSERT` triggers on `email_messages` and `calendar_observations` also insert Tier 0 rows. `Tier0Writer` uses plain `.insert`, and the Tier 0 table has no unique key covering `(profile_id, source/entity/event)`.
- Likely runtime symptoms: duplicate memory evidence in orb answers, over-weighted email/calendar patterns, doubled alert candidates, larger nightly batches, and avoidable Graphiti/NREM ingestion cost.
- Impact: raw observation count and downstream inference inputs become wrong, not just expensive.
- Remediation: decide one ownership boundary. If database triggers own bridge rows, remove Swift Tier 0 emission for email/calendar. If Swift owns them, remove or narrow triggers. Add a deterministic idempotency key or partial unique index and use `on conflict do nothing`/upsert. Run a one-time dedupe migration before enabling the uniqueness constraint.

### P2 - Gmail backfill serial N+1 plus per-message classification
- Severity: high
- Status: confirmed
- Locations: `Sources/TimedKit/Core/Services/GmailSyncService.swift:269`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:275`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:326`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:345`, `Sources/TimedKit/Core/Services/GmailSyncService.swift:429`
- Hot path reasoning: each page returns refs, then each message is fetched one at a time, persisted one at a time, Tier 0 emitted one at a time, and classified through one Edge Function request per message.
- Likely runtime symptoms: first-run Gmail sync takes minutes for large inboxes, classification backlog grows, and OAuth completion appears to do nothing while sync is still serially hydrating.
- Impact: high latency, API quota risk, battery/network waste, and duplicated cost when combined with P1.
- Remediation: fetch message bodies with bounded concurrency, upsert in chunks, and submit classification jobs as batches or through a server-side queue.

### P3 - Microsoft email delta serializes per-message expensive work
- Severity: high
- Status: confirmed
- Locations: `Sources/TimedKit/Core/Services/EmailSyncService.swift:407`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:411`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:430`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:441`, `Sources/TimedKit/Core/Services/EmailSyncService.swift:726`
- Hot path reasoning: for every delta message the service may fetch a fresh token, detect folder moves, upsert, emit Tier 0, compute sender importance, and call `classify-email`.
- Likely runtime symptoms: slow Outlook catch-up after app launch, repeated token-provider calls in long deltas, and bursty Edge Function/model traffic.
- Impact: the sync loop is bounded by the slowest per-message network/model path.
- Remediation: reuse one valid token per pass, make folder detection cache-aware, bulk upsert rows, and classify via batch/queue worker.

### P4 - Deepgram audio tap creates unbounded send tasks
- Severity: high
- Status: confirmed
- Locations: `Sources/TimedKit/Core/Services/DeepgramSTTService.swift:122`, `Sources/TimedKit/Core/Services/DeepgramSTTService.swift:125`, `Sources/TimedKit/Core/Services/DeepgramSTTService.swift:134`
- Hot path reasoning: the render callback fires many times per second and creates a new unstructured `Task` for every buffer. When the WebSocket send slows, there is no bounded queue or ordering guarantee. The tap closure also references `self` strongly through the local VAD path.
- Likely runtime symptoms: memory growth, CPU spikes, delayed transcripts, audio chunk reordering, and difficult cancellation during barge-in/stop.
- Impact: voice is a core interaction path; this is a real-time backpressure bug.
- Remediation: yield buffers into a bounded `AsyncStream`/channel and have one serial sender task consume it. Drop oldest/newest according to product tolerance. Capture `self` weakly in the tap and cancel the send loop in `stop`.

### P5 - Whole-array task persistence on every edit
- Severity: high
- Status: confirmed
- Locations: `Sources/TimedKit/Features/TimedRootView.swift:40`, `Sources/TimedKit/Features/TimedRootView.swift:128`, `Sources/TimedKit/Core/Services/DataBridge.swift:24`, `Sources/TimedKit/Core/Services/DataBridge.swift:29`
- Hot path reasoning: `onChange(of: tasks)` calls `saveTasks` for any array mutation. `DataBridge.saveTasks` writes the full JSON file and then detached-upserts every task.
- Likely runtime symptoms: checkbox toggles, bucket moves, and triage conversions get slower as task count grows; detached syncs can overlap and older full-list passes can finish after newer edits.
- Impact: O(n) work per small edit and race-prone network writes.
- Remediation: add mutation-specific methods (`upsertTask`, `markDone`, `moveTask`, `deleteTask`) and route UI edits through them. Keep full save only for import/repair flows.

### P6 - NetworkMonitor start is not idempotent
- Severity: medium
- Status: needs verification
- Locations: `Sources/TimedKit/Core/Services/NetworkMonitor.swift:14`, `Sources/TimedKit/Core/Services/NetworkMonitor.swift:18`, `Sources/TimedKit/Features/TimedRootView.swift:54`
- Hot path reasoning: root `onAppear` calls `network.start()` each time. The monitor is a singleton with one `NWPathMonitor` and no `isStarted` guard or cancel path.
- Likely runtime symptoms: repeated path handler setup, possible runtime assertion from starting the same `NWPathMonitor` more than once, or leaked monitoring after view lifecycle churn.
- Impact: lifecycle fragility in the root app shell.
- Remediation: guard `start`, expose `stop`, and start the monitor from a single app/service owner.

### P7 - Broad SwiftUI invalidation in TimedRootView
- Severity: medium
- Status: confirmed
- Locations: `Sources/TimedKit/Features/TimedRootView.swift:13`, `Sources/TimedKit/Features/TimedRootView.swift:126`, `Sources/TimedKit/Features/TimedRootView.swift:281`, `Sources/TimedKit/Features/TimedRootView.swift:335`
- Hot path reasoning: the root view owns tasks, blocks, triage, WOO, captures, and menu side effects. The sidebar filters `tasks` once per bucket and reduces minutes during body evaluation.
- Likely runtime symptoms: typing/editing tasks causes sidebar and detail panes to recompute together; large task lists make checkbox/bucket updates feel sticky.
- Impact: avoidable body work and persistence side effects at the widest view scope.
- Remediation: introduce narrow observable stores/selectors, precompute bucket aggregates on mutation, and pass derived values to sidebar rows.

### P8 - Trigger calendar sync lacks per-exec cap/backpressure
- Severity: medium
- Status: confirmed
- Locations: `trigger/src/tasks/graph-calendar-delta-sync.ts:299`, `trigger/src/tasks/graph-calendar-delta-sync.ts:318`, `trigger/src/tasks/graph-calendar-delta-sync.ts:337`, `trigger/src/tasks/graph-calendar-delta-sync.ts:350`, `trigger/src/tasks/graph-delta-sync.ts:319`
- Hot path reasoning: email sync has `MAX_MESSAGES_PER_EXEC`; calendar sync loops until no `@odata.nextLink` with no event/page cap. Both scheduled tasks then process every server-driven executive serially.
- Likely runtime symptoms: a noisy calendar can starve later executives, hit `maxDuration: 120`, and leave the next run to repeat pressure.
- Impact: poor tenant-level fairness and weak backpressure.
- Remediation: add max pages/events per executive, persist nextLink separately from final deltaLink, bound parallelism across executives, and confirm Trigger overlap behavior.

### P9 - `get_top_observations` rescoring path can become CPU-heavy
- Severity: medium
- Status: needs verification
- Locations: `supabase/migrations/20260428120000_score_memory.sql:60`, `supabase/migrations/20260428120000_score_memory.sql:69`, `supabase/migrations/20260411020000_tier0_observations.sql:21`
- Hot path reasoning: the query computes `score_memory(obs)` in SELECT and ORDER BY for every recent row. The only recency index on Tier 0 is BRIN `(profile_id, occurred_at)`, which is efficient for append scans but not selective ordering per profile as volume grows.
- Likely runtime symptoms: orb conversation startup slows as 24-hour observation count grows; duplicate rows from P1 make this worse.
- Impact: higher Postgres CPU on interactive requests.
- Remediation: compute score once in a subquery/CTE, add a btree `(profile_id, occurred_at desc)` index for recent per-exec retrieval, and validate with `EXPLAIN (ANALYZE, BUFFERS)`.

### P10 - TTS stream buffers full answer and full MP3 before playback
- Severity: medium
- Status: confirmed
- Locations: `Sources/TimedKit/Core/Services/StreamingTTSService.swift:33`, `Sources/TimedKit/Core/Services/StreamingTTSService.swift:39`, `Sources/TimedKit/Core/Services/StreamingTTSService.swift:80`, `Sources/TimedKit/Core/Services/StreamingTTSService.swift:81`, `Sources/TimedKit/Core/Services/StreamingTTSService.swift:89`
- Hot path reasoning: `send(sentence:)` appends to `pendingText`; `finish()` calls the Edge Function once; `playProxiedAudio` appends all stream chunks into one `Data` before constructing `AVAudioPlayer`.
- Likely runtime symptoms: no speech until the LLM turn and TTS download fully complete; long responses consume more memory and feel non-streaming.
- Impact: conversational latency.
- Remediation: either rename this as a one-shot TTS path or implement sentence-level queueing and incremental audio playback with bounded buffering.

### P11 - Conversation stream parsing is MainActor-isolated
- Severity: low
- Status: needs profiling
- Locations: `Sources/TimedKit/Core/Clients/ConversationAIClient.swift:11`, `Sources/TimedKit/Core/Clients/ConversationAIClient.swift:46`, `Sources/TimedKit/Core/Clients/ConversationAIClient.swift:124`, `Sources/TimedKit/Core/Clients/ConversationAIClient.swift:130`, `Sources/TimedKit/Core/Services/EdgeFunctions.swift:4`, `Sources/TimedKit/Core/Services/EdgeFunctions.swift:115`
- Hot path reasoning: the client and EdgeFunctions helper are `@MainActor`; the task that reads SSE lines and parses JSON also runs on MainActor.
- Likely runtime symptoms: UI hitches during long tool-heavy orb responses, especially when audio and transcript UI are updating at the same time.
- Impact: probably modest today, but the path is interactive and latency-sensitive.
- Remediation: keep only published state mutations on MainActor; parse stream lines and tool JSON in a nonisolated worker.

## Architecture Findings

### A1 - Local JSON still acts as source of truth
- Severity: high
- Status: confirmed
- Locations: `Sources/TimedKit/Core/Services/DataBridge.swift:1`, `Sources/TimedKit/Core/Services/DataBridge.swift:20`, `Sources/TimedKit/Core/Services/DataBridge.swift:100`, `Sources/TimedKit/Core/Services/DataStore.swift:1`, `Sources/TimedKit/Features/TimedRootView.swift:177`
- Hot path reasoning: DataBridge comments define local-first/local-read behavior. `loadTasks` returns local JSON. Triage, WOO, blocks, captures, completions, bucket estimates, and focus sessions read/write only local JSON. Root load reads local state before partial Supabase overlay.
- Likely runtime symptoms: signed-in app state differs between devices; server-generated plans/briefings see incomplete context; stale local files can rehydrate over newer server state.
- Impact: violates the stated Supabase source-of-truth direction once Auth lands.
- Remediation: for authenticated users, read Supabase first and treat local storage as cache/offline queue. Add explicit sync ownership for every domain or mark the domain local-only and remove it from intelligence paths.

### A2 - Supabase realtime subscriptions cannot be torn down
- Severity: medium
- Status: confirmed latent
- Locations: `Sources/TimedKit/Core/Clients/SupabaseClient.swift:912`, `Sources/TimedKit/Core/Clients/SupabaseClient.swift:934`, `Sources/TimedKit/Core/Clients/SupabaseClient.swift:936`, `Sources/TimedKit/Core/Clients/SupabaseClient.swift:939`, `Sources/TimedKit/Core/Clients/SupabaseClient.swift:942`, `Sources/TimedKit/Core/Services/SharingService.swift:118`
- Hot path reasoning: `subscribeToTaskChanges` creates a channel and three unstructured tasks for insert/update/delete streams, but returns no handle and does not unsubscribe.
- Likely runtime symptoms: when a view starts using this, each navigation/refresh can add another channel and duplicate callbacks.
- Impact: latent lifecycle leak and eventual reload storm.
- Remediation: return a `TaskSubscription`/`AsyncDisposable` type that cancels listener tasks and unsubscribes the channel.

### A3 - Client directly checks Anthropic
- Severity: medium
- Status: confirmed
- Locations: `Sources/TimedKit/Core/Services/GracefulDegradation.swift:57`, `Sources/TimedKit/Core/Services/GracefulDegradation.swift:67`
- Hot path reasoning: the Swift app sends a `HEAD` request to `https://api.anthropic.com/v1/messages` for health.
- Likely runtime symptoms: false "Claude down" state from network/proxy/auth differences, and provider coupling in client code.
- Impact: architecture drift from "all AI calls go through Edge Functions." Even without an inference payload, provider health belongs server-side.
- Remediation: replace with an Edge Function or existing pipeline health endpoint that returns Timed-specific AI capability health.

### A4 - Model routing is hardcoded and split
- Severity: medium
- Status: confirmed
- Locations: `supabase/functions/_shared/anthropic.ts:7`, `supabase/functions/generate-morning-briefing/index.ts:252`, `supabase/functions/generate-morning-briefing/index.ts:298`, `supabase/functions/generate-dish-me-up/index.ts:311`, `supabase/functions/generate-dish-me-up/index.ts:319`
- Hot path reasoning: the shared Anthropic type only allows 4.6-era aliases, and some functions directly `fetch` Anthropic instead of using the shared helper. Docs say Trigger aliases have moved while legacy Edge Functions remain older.
- Likely runtime symptoms: inconsistent retry/caching behavior, missed model upgrades, and hard-to-audit inference quality changes.
- Impact: model selection becomes scattered across Edge Functions.
- Remediation: define canonical model aliases/env overrides in one shared module, include current Opus/Sonnet/Haiku aliases, and remove direct Anthropic fetches from feature functions.

### A5 - Morning check-in lacks view-disappear cleanup
- Severity: medium
- Status: needs verification
- Locations: `Sources/TimedKit/Features/MorningCheckIn/MorningCheckInView.swift:44`, `Sources/TimedKit/Features/MorningCheckIn/MorningCheckInView.swift:145`, `Sources/TimedKit/Features/MorningCheckIn/MorningCheckInView.swift:156`, `Sources/TimedKit/Features/MorningCheckIn/MorningCheckInManager.swift:53`, `Sources/TimedKit/Features/MorningCheckIn/MorningCheckInManager.swift:88`
- Hot path reasoning: `.task` starts the ElevenLabs conversation; only explicit End/Cancel buttons call `manager.end()`. The manager retains `conversation` and cancellables.
- Likely runtime symptoms: closing the sheet/window outside those buttons can leave the SDK session or observers alive longer than expected, and learnings extraction may not run.
- Impact: lifecycle leak risk in a voice feature.
- Remediation: add idempotent `onDisappear` cleanup and clear `conversation`/cancellables after `end`.

### A6 - Direct server-side Microsoft Graph calls are split across modules
- Severity: medium
- Status: confirmed
- Locations: `trigger/src/tasks/graph-delta-sync.ts:97`, `trigger/src/tasks/graph-calendar-delta-sync.ts:105`, `supabase/functions/renew-graph-subscriptions/index.ts:57`, `trigger/src/tasks/graph-webhook-renewal.ts:61`, `Sources/TimedKit/Core/Clients/GraphClient.swift:18`
- Hot path reasoning: Swift Graph calls are centralized in `GraphClient.swift`, but Trigger tasks and an Edge Function construct Graph URLs directly. The written rule says Graph calls go through `GraphClient.swift`; server-side sync likely needs a separate approved client boundary.
- Likely runtime symptoms: pagination/retry/auth fixes land in one path but not others; error semantics drift between client and server sync.
- Impact: coupling and duplication around a critical integration.
- Remediation: either update the architecture rule to explicitly allow a shared server-side Graph client, or create one and route all TS Graph calls through it.

### A7 - Client calendar fetch truncates after 100 events
- Severity: low
- Status: confirmed
- Locations: `Sources/TimedKit/Core/Clients/GraphClient.swift:516`, `Sources/TimedKit/Core/Clients/GraphClient.swift:520`, `Sources/TimedKit/Core/Clients/GraphClient.swift:538`, `Sources/TimedKit/Core/Clients/GraphClient.swift:599`
- Hot path reasoning: `fetchCalendarEvents` requests `$top=100` and returns only the first response page. `GraphCalendarResponse` decodes only `value`, unlike the email delta response which decodes `@odata.nextLink`.
- Likely runtime symptoms: busy days or shared calendars silently drop events after 100, which makes free-time and briefing context wrong.
- Impact: data completeness issue that can become performance-related when later code compensates with repeated fetches.
- Remediation: decode `@odata.nextLink` and loop with a sane page cap.

## Architecture Rule Checks

- AI through Edge Functions: client inference paths generally proxy through Edge Functions, but `GracefulDegradation` directly checks Anthropic health (`A3`). Edge Functions also have split direct Anthropic fetches (`A4`).
- Microsoft Graph through `GraphClient.swift`: no extra client-side Swift Graph callers were found outside `GraphClient.swift`; server-side Trigger/Edge code does call Graph directly (`A6`), which needs an explicit architecture decision.
- Google/Gmail through `GoogleClient.swift`/`GmailClient.swift`: no Swift direct Google/Gmail API callers were found outside those clients during this pass.
- Ranking through `PlanningEngine`: `PlanPane` and `DishMeUpSheet` call `PlanningEngine.generatePlan` at `Sources/TimedKit/Features/Plan/PlanPane.swift:402` and `Sources/TimedKit/Features/DishMeUp/DishMeUpSheet.swift:469`. I did not find a confirmed view/store task-ranking replacement. `VoiceCaptureService.swift:515` computes parse confidence, not task ranking.
- Local JSON source of truth: confirmed drift in `A1`.

## Commands Needed After Fixes

Do not treat these as run results; this review was static by request.

```bash
swift build
swift test
swift test --filter DataBridge
swift test --filter GmailSyncService
swift test --filter EmailSyncService
swift test --filter CalendarSyncService
swift test --filter DeepgramSTTService
cd trigger && pnpm typecheck
supabase db lint
supabase functions serve classify-email
```

Profiling/verification after fixes:

```bash
swift build -c release
instruments -t "Time Profiler" .build/release/Timed
instruments -t "Allocations" .build/release/Timed
psql "$SUPABASE_DB_URL" -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.get_top_observations('<exec_id>'::uuid, 24, 40);"
```

Recommended runtime smoke paths:

- Gmail OAuth then 30-day backfill with a mailbox over 500 messages; verify bounded concurrent hydration and one classification batch per chunk.
- Microsoft delta catch-up with a mailbox over 500 messages; verify token fetch count, Edge Function call count, and no duplicate Tier 0 rows.
- Voice orb for a 60-second turn while throttling network; verify no growth in outstanding audio send tasks.
- Calendar sync for an executive with over 100 events in the 7-day/30-day window; verify pagination and caps.
- Navigate repeatedly into any future realtime-backed PA/shared-task view; verify one active Supabase channel and listener set.
