# BUILDPLAN.md — Timed
# Meticulous feature-by-feature build sequence. No guessing at coding time.
# Last updated: 2026-03-31 (overnight autonomous run)
# PRD source: ~/Timed-Brain/03 - Specs/prd-v02.md

---

## HOW TO USE THIS PLAN

1. Each phase has GATES — prerequisites that must pass before starting.
2. Each feature has ACCEPTANCE CRITERIA — binary yes/no, no interpretation.
3. Each task maps to exact files to create/modify.
4. Human-blocked tasks are marked 🔑 — need keys/accounts from Ammar.

---

## PHASE 0 — INFRA BOOTSTRAP
**Gate: must complete before ANY feature work**

### 0.1 Azure App Registration 🔑 (Human)
- Go to portal.azure.com → Azure Active Directory → App registrations → New registration
- Name: "Timed"
- Supported account types: Accounts in any organizational directory + personal Microsoft accounts
- Redirect URI: `msauth.com.pff.timed://auth`
- After creation: copy Application (client) ID → `GRAPH_CLIENT_ID`
- API Permissions: add Microsoft Graph → Delegated → `Mail.Read`, `Mail.ReadWrite`, `Calendars.Read`, `Calendars.ReadWrite`
- Copy Directory (tenant) ID → `GRAPH_TENANT_ID`
- Deliverable: `.env.local` file at project root with `GRAPH_CLIENT_ID=xxx` and `GRAPH_TENANT_ID=xxx`

### 0.2 Supabase Project Creation 🔑 (Human)
- Create project at supabase.com → New project
- Region: Sydney (closest to AU exec target user)
- After creation: copy Project URL → `SUPABASE_URL`, anon key → `SUPABASE_ANON_KEY`, service role key → `SUPABASE_SERVICE_ROLE_KEY`
- Enable extensions in SQL editor: `vector`, `pg_cron`, `pgmq`
- Run migration: `supabase/migrations/20260331000001_initial_schema.sql`
- Deliverable: All env vars in `.env.local`

### 0.3 Anthropic API Key 🔑 (Human)
- Get from console.anthropic.com → API Keys → New key
- Add to `.env.local`: `ANTHROPIC_API_KEY=sk-ant-xxx`

### 0.4 Swift Package Resolution ✅ (Already done)
- Package.swift now has: TCA, supabase-swift, MSAL
- Run: `swift package resolve` → verify no errors
- Gate check: `swift build` compiles without errors

### 0.5 Xcode Project Setup
- File: `time-manager-desktop.xcodeproj` must be opened in Xcode 16+
- Add entitlements: `com.apple.security.device.microphone`, `com.apple.security.network.client`
- Add Info.plist keys: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`
- Set bundle ID: `com.pff.timed`
- Sign with development certificate

---

## PHASE 1 — EMAIL TRIAGE (FR-01)
**Gate: Phase 0 complete. Azure + Supabase keys in .env.local**
**PRD ref: Feature 4 — Email Triage (BACKGROUND ENGINE)**

### 1.1 Graph OAuth Flow
**Files:** `Sources/Core/Clients/GraphClient.swift` (already stubbed — implement authenticate())

Steps:
- Implement `authenticate(tenantId:clientId:)` using MSAL framework
- MSAL config: `MSALPublicClientApplication` with clientId + authority (common)
- Scopes: `["Mail.Read", "Mail.ReadWrite", "Calendars.Read", "Calendars.ReadWrite"]`
- On success: store access_token + refresh_token encrypted in Keychain (NOT UserDefaults)
- Token refresh: MSAL handles automatically via `acquireTokenSilent`

Acceptance criteria:
- [ ] `authenticate()` returns valid access token without crashing
- [ ] Token persists across app restarts (Keychain)
- [ ] Token refresh works silently when expired

### 1.2 Delta Sync (Email Fetching)
**Files:** `GraphClient.swift` (implement fetchDeltaMessages), new Edge Function `supabase/functions/process-email-pipeline/index.ts`

Steps:
- Implement `fetchDeltaMessages(accountId:deltaLink:accessToken:)`:
  - GET `https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta`
  - If deltaLink: use it directly (incremental); else: add `$select=id,subject,from,receivedDateTime,bodyPreview,toRecipients,ccRecipients`
  - Paginate: follow `@odata.nextLink` until none
  - Return: messages[], nextDeltaLink (for next call), hasMore
- Store deltaLink in `email_accounts.delta_link`
- Edge Function `process-email-pipeline`:
  - Receives: `{ accountId, workspaceId }`
  - Calls `fetchDeltaMessages` → upserts to `email_messages`
  - Calls `classify-email` for each new message
  - Updates `email_accounts.last_sync_at` and `delta_link`

Acceptance criteria:
- [ ] First sync fetches last 30 days of inbox messages
- [ ] Second sync only fetches new messages (delta link works)
- [ ] Stale delta link: recover by re-syncing from 30 days ago
- [ ] All messages upserted to `email_messages` without duplicates

### 1.3 Classification Pipeline (AI)
**Files:** `supabase/functions/classify-email/index.ts` (already complete — needs env vars)

Steps:
- Set environment: `supabase secrets set ANTHROPIC_API_KEY=xxx` in Supabase Dashboard
- Test with real email payload
- Smoke test: call with known black_hole sender → verify bucket = black_hole
- Smoke test: call with inbox_always sender → verify bucket = inbox
- Smoke test: newsletter → verify bucket = later

Acceptance criteria:
- [ ] Classification returns valid bucket in < 3 seconds
- [ ] Sender rule overrides work (inbox_always, black_hole)
- [ ] Prompt caching tokens appear in ai_pipeline_runs.cached_tokens
- [ ] ai_pipeline_runs row created for every call

### 1.4 CC/FYI Auto-routing
**Files:** `classify-email/index.ts` (add CC detection logic)

Steps:
- Before AI call: check if user's email address is ONLY in cc_addresses (not to_addresses)
- If yes: set `triage_bucket = 'cc_fyi'`, `triage_source = 'rule'`, skip AI call
- Move email to Outlook CC/FYI folder via Graph API `moveMessage()`

Acceptance criteria:
- [ ] CC-only emails routed to cc_fyi without AI call
- [ ] Email moved to Outlook CC/FYI folder
- [ ] User can override manually (drag to inbox)

### 1.5 Drag-to-Train UI
**Files:** `Sources/Features/Triage/TriagePane.swift` (already has UI — connect to backend)

Steps:
- On drop/button action: call Supabase to insert `email_triage_corrections` row
- Update `email_messages.triage_bucket` in Supabase
- Move email via `GraphClient.moveMessage()` to correct Outlook folder
- Update `sender_rules` if pattern detected (same sender dragged 2+ times)
- Trigger `classify-email` with updated corrections for next email

Acceptance criteria:
- [ ] Drag inbox → black_hole: email moves in Outlook + DB updated immediately
- [ ] Correction row inserted in `email_triage_corrections`
- [ ] After 2 corrections from same sender: `sender_rules` row created
- [ ] Next email from same sender auto-classified correctly

### 1.6 Graph Webhook (Real-time push)
**Files:** `supabase/functions/graph-webhook/index.ts` (already complete)

Steps:
- Register webhook subscription: `GraphClient.registerWebhook(notificationUrl:accessToken:)`
  - notificationUrl = `{SUPABASE_URL}/functions/v1/graph-webhook`
  - Set `email_accounts.graph_subscription_id` and `subscription_expires_at`
- pg_cron renewal: schedule `renew-graph-subscriptions` function (every 2 days)
- Test: send email to Outlook → webhook fires → email classified within 30s

Acceptance criteria:
- [ ] Webhook validation handshake works (returns validationToken)
- [ ] New email triggers classification within 30 seconds
- [ ] Duplicate notifications deduplicated (webhook_events UNIQUE constraint)
- [ ] Subscription renewed before 3-day expiry

---

## PHASE 2 — TASK ENGINE (FR-03 + FR-04)
**Gate: Phase 1 complete. Emails flowing into email_messages.**
**PRD ref: Feature 5 — Task Engine (SOURCE OF TRUTH)**

### 2.1 Task Extraction from Email
**Files:** New Edge Function `supabase/functions/extract-task/index.ts`

Steps:
- Model: Claude Sonnet 4.6
- Input: email subject, snippet, from_address, is_question, is_quick_reply
- Output: `{ title, bucketType, description, replyMedium, isQuickReply }`
- Classify email as: action (requires work), reply (needs response), read (no action now)
- Subject format `P1 | topic | 30 mins` → auto-fills priority + estimatedMinutes
- Multi-email thread → bundle as single action task (detect by conversationId)
- On extraction: insert into `tasks`, set `source_email_id`, call `estimate-time`

Acceptance criteria:
- [ ] Email with question → task with bucket_type='reply_email'
- [ ] Email with work packet → task with bucket_type='action'
- [ ] Subject format `P1 | Report | 45 mins` → priority=1, estimated=45
- [ ] Task appears in TasksPane with correct bucket

### 2.2 Time Estimation Engine
**Files:** `supabase/functions/estimate-time/index.ts` (already complete)

Steps:
- Wire into `extract-task` flow: call `estimate-time` after task created
- Cold start: uses category defaults (reply=2min, action=30min, calls=10min)
- Warm state (>3 similar tasks): uses weighted historical average
- User override: `estimated_minutes_manual` updated, `estimate_source='manual'`
- Completion: update `actual_minutes` when task marked done + insert `estimation_history` row

Acceptance criteria:
- [ ] New task gets AI estimate within 5 seconds
- [ ] Category default used when no history
- [ ] Historical estimate used when ≥3 similar tasks exist
- [ ] User override persists in `estimated_minutes_manual`
- [ ] `estimation_history` row created on task completion

### 2.3 Tasks UI — Bucket Views
**Files:** `Sources/Features/Tasks/TasksPane.swift` (already has UI — connect to Supabase)

Steps:
- Subscribe to `tasks` via Supabase Realtime (`postgres_changes`)
- Load tasks filtered by `bucket_type`, `status='pending'`
- Task row shows: title, sender, estimated time, estimate basis label, due date
- Tap checkbox → update `status='done'`, `completed_at=now()`, `actual_minutes` prompted
- Long-press → defer (increment `deferred_count`, update `last_deferred_at`)
- Drag to reorder (update `priority` field)

Acceptance criteria:
- [ ] Tasks load from Supabase on app launch
- [ ] New task appears via Realtime (no manual refresh)
- [ ] Completing task: status=done, actual_minutes logged
- [ ] Deferred task: deferred_count incremented, removed from today view
- [ ] Estimate basis label shows correctly ("Based on similar task" / "AI default" / "You set this")

### 2.4 Manual Task Creation
**Files:** `Sources/Features/Tasks/TasksPane.swift` (add quick-add row)

Steps:
- Quick-add: text field at bottom of each bucket → type title → press Enter → task created
- Voice: tap mic icon → VoiceCaptureService.start() → parsed items shown for confirmation
- Parsed items: show title + detected estimate + due date + bucket → user confirms or edits
- On confirm: insert into Supabase tasks

Acceptance criteria:
- [ ] Type task title + Enter → task created in correct bucket
- [ ] Voice capture → parsed items preview → confirm → task created
- [ ] Natural language: "Review the Acme contract, 30 min, before Thursday" → parsed correctly

---

## PHASE 3 — PLANNING ENGINE (FR-05)
**Gate: Phase 2 complete. Tasks flowing. Estimates working.**
**PRD ref: Feature 3 — Dish Me Up + Feature 1 — Morning Interview**

### 3.1 generatePlan() — Server Side
**Files:** `supabase/functions/generate-daily-plan/index.ts` (already complete)

Steps:
- Wire environment vars: `ANTHROPIC_API_KEY`
- Test with seed data: 20 tasks, various buckets, some overdue, some with deadlines
- Verify: daily_update email always position 0
- Verify: family email always position 1
- Verify: overdue tasks score highest after fixed items
- Verify: mood=easy_wins → small tasks surfaced first
- Verify: mood=deep_focus → only action bucket tasks selected

Acceptance criteria:
- [ ] Plan generated in < 10 seconds for 50 tasks
- [ ] Fixed ordering rules: daily update first, family second
- [ ] Overdue tasks always appear before non-overdue
- [ ] Mood modifiers change plan composition
- [ ] ai_pipeline_runs row logged with token counts
- [ ] plan_items inserted to DB with rank_reason from Opus

### 3.2 Morning Interview UI
**Files:** `Sources/Features/MorningInterview/MorningInterviewPane.swift` (already complete — connect to backend)

Steps:
- Step 0 (Time Declaration): user sets availableMinutes → saves to state
- Step 1 (Due Today Review): load tasks where `due_at = today OR is_do_first = true` from Supabase
- Step 2 (Assumptions Review): load all tasks with AI estimates → sort by estimatedMinutes desc → show top 10
- When user overrides estimate: update `estimated_minutes_manual` in Supabase immediately
- Step 3 (Plan Confirm): call `generate-daily-plan` with availableMinutes + moodContext
- On confirm: upsert `daily_plans`, update `plan_items.status='confirmed'`
- Auto-open: set `showMorningInterview=true` on first launch of day (check `daily_plans` for today)

Acceptance criteria:
- [ ] First launch of day: Morning Interview auto-opens
- [ ] Subsequent launches same day: goes straight to Today
- [ ] Step 1 shows only due-today + do-first tasks
- [ ] Step 2 shows assumptions sorted by time cost (biggest first)
- [ ] Estimate override in Step 2 persists to DB
- [ ] Step 3 shows generated plan total time
- [ ] Confirm creates daily_plans row + plan_items

### 3.3 Today Screen
**Files:** `Sources/Features/Today/TodayPane.swift` (already complete — connect to backend)

Steps:
- Load today's plan from `daily_plans` + `plan_items` joined with `tasks`
- Running totals: planned - done = remaining (live as tasks ticked)
- Tap checkbox → update plan_items.is_done=true, done_at=now(), log behaviour_event
- Track actual_minutes: prompt on completion or auto-calculate from done_at - start
- Sections: Do First, Replies (sub-labelled Email/WA), Action, Reads (collapsed), Calls (collapsed)
- Long-press: defer, re-estimate, move to transit, delete
- Drag to reorder → update plan_items.position

Acceptance criteria:
- [ ] Today screen shows confirmed plan from morning interview
- [ ] Running totals update immediately on checkbox tap
- [ ] Reply section shows sub-labels (Email badge, WA badge) correctly
- [ ] Sections collapsed/expanded state persists through session
- [ ] Ticking task: plan_item updated + behaviour_event logged

### 3.4 Dish Me Up Sheet
**Files:** `Sources/Features/DishMeUp/DishMeUpSheet.swift` (already complete — connect to backend)

Steps:
- Available anytime: tap "Dish Me Up" button from Today or via keyboard shortcut
- Input: time slider (5-240 min) or voice "I have 40 minutes"
- Context: At Desk / In Transit / On Flight / No Calls → filter by allowed bucket types
- Mood: Easy wins / Kill avoidance list / Deep focus / No preference
- Call `generate-daily-plan` with time + mood + context filters
- Show result: ordered cards with rank_reason
- Accept: inject into Today's plan (append to plan_items)
- Swap: call generate-daily-plan again with excluded task IDs

Acceptance criteria:
- [ ] Time input via slider and voice command both work
- [ ] Context filter limits task types (transit: only transit-safe tasks)
- [ ] Mood modifier changes which tasks appear
- [ ] Accept: tasks added to Today plan
- [ ] Swap: replaces single task with next-best fit of equal/lesser time

---

## PHASE 4 — CALENDAR INTEGRATION (FR-06)
**Gate: Phase 1 complete. Graph auth working.**
**PRD ref: Feature 3 (Dish Me Up context) + Feature 10 (Transit Mode)**

### 4.1 Read Calendar Events
**Files:** `GraphClient.swift` (implement fetchCalendarEvents), new `Sources/Core/Services/CalendarService.swift`

Steps:
- Fetch today's events: GET `/me/calendar/events?$filter=start/dateTime ge '{today}T00:00:00Z' and end/dateTime le '{today}T23:59:59Z'`
- Parse: id, subject, start/end dateTime, isAllDay, isCancelled
- Calculate free blocks: sort events by start, find gaps >= 15 min
- Detect transit events: subject/location contains "transit", "flight", "drive", "travel"
- Store in local state (CalendarBlock array) — no DB needed for calendar cache

Acceptance criteria:
- [ ] Free blocks calculated correctly from today's calendar
- [ ] Morning interview shows "You have X hours available" from free blocks
- [ ] Transit events detected → Transit Mode prompt shown
- [ ] All-day events do NOT consume free blocks (they don't block time)

### 4.2 Write Calendar Blocks
**Files:** `GraphClient.swift` (implement createCalendarEvent), `DishMeUpSheet.swift` (add to calendar button)

Steps:
- "Add to Calendar" button in Dish Me Up result → creates Outlook event via Graph POST `/me/events`
- Event: title = task title, duration = estimated + buffer, body = "Created by Timed"
- Category: tag with "Timed" to distinguish from real meetings

Acceptance criteria:
- [ ] "Add to Calendar" creates event in Outlook calendar
- [ ] Event appears in Calendar.app (via Outlook sync)
- [ ] Event duration matches task estimate + 5-min buffer

### 4.3 Transit Mode
**Files:** `Sources/Features/Calendar/CalendarPane.swift`, `DishMeUpSheet.swift`

Steps:
- When transit event detected in next 4 hours: show banner "2h drive starting at 3pm — queue transit tasks?"
- Auto-activate in Dish Me Up context picker when calendar shows travel
- Filter tasks: only `is_transit_safe=true` or bucket_type in [transit, read_today, calls]

Acceptance criteria:
- [ ] Transit banner appears when calendar event indicates travel within 4 hours
- [ ] Dish Me Up transit context only shows transit-safe tasks
- [ ] Tasks pre-filtered by travel window duration

---

## PHASE 5 — WAITING ON OTHERS (FR-06 / Feature 6)
**Gate: Phase 1 complete. Email sync working.**
**PRD ref: Feature 6 — Waiting On Others**

### 5.1 Waiting Item Creation
**Files:** `Sources/Features/Waiting/WaitingPane.swift` (already has UI — connect to backend)

Steps:
- "Add waiting item" form: what, who, date asked, expected by, source (email/WA/verbal)
- If source = email: paste thread URL or select from recent emails → store `source_email_thread_id`
- Insert to `waiting_items`

Acceptance criteria:
- [ ] Add form captures all fields
- [ ] Row appears immediately in WaitingPane list
- [ ] Status: waiting (blue), overdue (red past expectedBy), responded (green)

### 5.2 Reply Detection
**Files:** New Edge Function `supabase/functions/detect-reply/index.ts`

Steps:
- Schedule: pg_cron every 30 min → call `detect-reply` for all waiting items where `status='waiting'`
- For each item with `source_email_thread_id`: call Graph GET `/me/messages?$filter=conversationId eq '{threadId}'`
- If new message from expected sender after `asked_at`: mark `status='responded'`, set `responded_at`, `response_email_id`
- Update `next_check_at = now() + 30 min`

Acceptance criteria:
- [ ] Reply detection runs every 30 min for active waiting items
- [ ] When reply detected: waiting item shows "responded" badge
- [ ] Responded email visible via link

### 5.3 Follow-up Generation
**Files:** `WaitingPane.swift` (follow-up button), new API route or Edge Function

Steps:
- "Follow up" button on overdue items
- Generates: "Hi [name], following up on [description] from [asked_date]..."
- User can edit before sending
- "Send" → Graph API POST to reply on thread

Acceptance criteria:
- [ ] Follow-up template generated with correct name/date/description
- [ ] User can edit before sending
- [ ] Sent follow-up appears in Outlook sent items

---

## PHASE 6 — VOICE CAPTURE (Feature 8)
**Gate: Phase 2 complete. Tasks engine working.**
**PRD ref: Feature 8 — Voice Capture**

### 6.1 VoiceCaptureService (Already written)
**Files:** `Sources/Core/Services/VoiceCaptureService.swift` (complete)

Steps:
- Wire microphone entitlement in Xcode (com.apple.security.device.microphone)
- Add Info.plist keys (NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription)
- Test: speak "Call John back 5 minutes" → verify ParsedItem(title: "Call John back", bucketType: "calls", estimatedMinutes: 5)
- Test: "Review contract 30 minutes before Thursday" → correct date extraction

Acceptance criteria:
- [ ] Authorization prompt appears on first use
- [ ] Live transcript updates as user speaks
- [ ] Stop → parsed items appear with title, est, due date, bucket
- [ ] Self-correction: "actually 20 not 30" → 20 selected (last value wins)

### 6.2 Capture Pane UI
**Files:** `Sources/Features/Capture/CapturePane.swift` (existing — wire to VoiceCaptureService)

Steps:
- Tap mic button → VoiceCaptureService.start()
- Show live transcript text as user speaks
- Stop → show parsed items as cards
- Each card: title (editable), time (editable), due date (editable), bucket (dropdown)
- "Confirm all" → insert all items to tasks table
- "Review one by one" → step through cards
- Rejected items: discard

Acceptance criteria:
- [ ] Mic button starts/stops recording
- [ ] Live transcript visible during recording
- [ ] Parsed cards shown after stop
- [ ] All fields editable before confirmation
- [ ] Confirmed items → tasks created in Supabase

### 6.3 Supabase Persistence
**Files:** `supabase/functions/parse-voice-capture/index.ts` (stub → implement)

Steps:
- Insert `voice_captures` row on capture
- Parse transcript → insert `voice_capture_items` rows
- On confirm: create task for each confirmed item, set `source_voice_capture_id`

Acceptance criteria:
- [ ] Every voice session persisted to DB
- [ ] voice_capture_items rows created per parsed item
- [ ] Confirmed items linked to tasks via source_voice_capture_id

---

## PHASE 7 — BEHAVIOUR LEARNING + INSIGHTS (FR Phase 2)
**Gate: Phase 3 complete. Planning engine working. Tasks completing.**
**PRD ref: Feature 9 — Insights + Loop 3 learning**

### 7.1 Behaviour Event Logging
**Files:** All feature panes (wire behaviour_event inserts on key actions)

Events to log:
- `task_completed`: on checkbox tick → `{ task_id, bucket_type, hour_of_day, day_of_week, actual_minutes }`
- `task_deferred`: on long-press defer → `{ task_id, deferred_count }`
- `plan_order_override`: on drag to reorder in Today → `{ old_position, new_position }`
- `estimate_override`: on Morning Interview step 2 edit → `{ old_estimate, new_estimate }`
- `triage_correction`: on drag between triage panes → `{ old_bucket, new_bucket }`

Acceptance criteria:
- [ ] behaviour_events row inserted for every tracked action
- [ ] hour_of_day and day_of_week populated correctly
- [ ] No missing event types in 1-week test run

### 7.2 Weekly Profile Card Regeneration
**Files:** `supabase/functions/generate-profile-card/index.ts` (stub → implement)

Steps:
- Runs via pg_cron (Sunday 02:00 UTC)
- Queries last 30 days of behaviour_events → aggregates patterns
- LLM (Claude Sonnet): summarise patterns into ~700-token profile card
- Extracts rules: "You complete calls before emails 84% of the time"
- Updates `user_profiles.profile_card_text` + `behaviour_rules` rows

Acceptance criteria:
- [ ] Profile card generated after 7+ days of usage
- [ ] Rules detected match observed behaviour (>80% confidence threshold)
- [ ] Profile card < 700 tokens (verified by token count)
- [ ] Rules visible to user in Settings > My Profile

### 7.3 Insights View
**Files:** `Sources/Features/` (new InsightsPane.swift — post-MVP polish)

Shows:
- Procrastination alerts: "This task has been in queue 14 days. Do it today."
- Pattern insights: "You complete email replies 40% faster than estimated."
- Avoidance flags: "Deferred 3 times. Want me to reassign or delete?"

---

## PHASE 8 — POLISH + PRD GAPS
**Gate: Phases 1-6 complete and tested.**

### 8.1 PRD Gap Audit

**✅ Implemented:**
- Morning Interview 4-step flow (Time → Due Today → Assumptions → Confirm)
- Today screen with running totals, sections, Do First group
- Dish Me Up with time input, context, mood
- Email Triage 3-bucket system with card UI
- Task buckets: Action, Reply (Email/WA sub-labels), Calls, Read Today, Read This Week, Transit, Waiting
- Voice Capture with transcript parser
- Calendar read + free block detection
- Waiting On Others tracker
- Supabase schema: complete with RLS + pgvector + realtime

**⚠️ Missing from current UI:**
- [ ] Today screen: WA batch item "30 WhatsApp messages — 60m [batch]" (PRD p.4) — add WhatsApp batch row to Replies section
- [ ] Today screen: "Due today" visual indicator distinct from general items — add orange dot or badge
- [ ] Triage: CC/FYI fourth bucket visible in UI
- [ ] MorningInterview: Travel check — "upcoming calendar travel surfaced prominently" (Step 2 pre-check)
- [ ] Settings: Onboarding interview flow for first-time Outlook connection
- [ ] Tasks: "aging alerts" — 3-week untouched items surface reminder (pg_cron job)
- [ ] Insights: procrastination alerts visible somewhere in UI (can be Today header)
- [ ] Tasks: sub-category badge (Work / Personal) — low priority
- [ ] Transit: "No connectivity required" — offline task cache needed

**❌ Out of MVP scope (confirmed in PRD §9):**
- PA sharing (Phase 2)
- WhatsApp AI replies (Phase 2)
- Multi-user roles (Phase 2)
- Native calendar view (exports to external)
- Email composition (Outlook stays as client)
- iPhone app (Mac first)
- Insights deep reporting (Phase 2)

### 8.2 Edge Cases

- Delta sync stale token: detect `410 Gone` → re-sync from 30 days ago (no re-processing via is_archived flag)
- Graph throttle: 10k req/10min — at 10 users × 50 emails/day = 500 pipeline runs/day, well within limit
- Morning Interview skip: if user skips, Today shows tasks sorted by default score (no confirmed plan)
- Zero tasks: show empty state with "Add tasks via voice or type below" prompt
- No available time declared: use calendar-derived estimate as default
- Estimate conflict: if user sets manual estimate then actual is far off → log to estimation_history for learning, don't change user's manual estimate

---

## PHASE 0.5 — CURRENTLY UNBLOCKED (do now while waiting for keys)

These tasks need NO Azure or Supabase keys:

| Task | File | Status |
|---|---|---|
| Package.swift dependencies | Package.swift | ✅ Done |
| Initial DB migration | supabase/migrations/*.sql | ✅ Done |
| SupabaseClient stub | Sources/Core/Clients/SupabaseClient.swift | ✅ Done |
| GraphClient stub | Sources/Core/Clients/GraphClient.swift | ✅ Done |
| PlanningEngine (pure Swift) | Sources/Core/Services/PlanningEngine.swift | ✅ Done |
| VoiceCaptureService | Sources/Core/Services/VoiceCaptureService.swift | ✅ Done |
| classify-email Edge Function | supabase/functions/classify-email/ | ✅ Done |
| generate-daily-plan Edge Function | supabase/functions/generate-daily-plan/ | ✅ Done |
| estimate-time Edge Function | supabase/functions/estimate-time/ | ✅ Done |
| graph-webhook Edge Function | supabase/functions/graph-webhook/ | ✅ Done |
| Today screen PRD gaps | Sources/Features/Today/TodayPane.swift | 🔲 Pending |
| WhatsApp batch row in Today | Sources/Features/Today/TodayPane.swift | 🔲 Pending |
| Due-today visual indicator | Sources/Features/Today/TodayPane.swift | 🔲 Pending |
| CC/FYI bucket in Triage UI | Sources/Features/Triage/TriagePane.swift | 🔲 Pending |
| Travel check in Morning Interview | Sources/Features/MorningInterview/MorningInterviewPane.swift | 🔲 Pending |
| Aging alerts pg_cron job comment | supabase/migrations/ | 🔲 Pending |
| Comprehensive tests for PlanningEngine | Tests/ | 🔲 Pending |

---

## COST MODEL (monthly, 10 active users)

| Service | Usage | Monthly cost |
|---|---|---|
| Claude Haiku (email classification) | 200 emails/day × 10 users × 30 days × $0.0025/call | ~$15 |
| Claude Sonnet (task extraction, estimates) | 50 tasks/day × 10 users × 30 days × $0.006/call | ~$90 |
| Claude Opus (daily planning, rank reasons) | 1 plan/day × 10 users × 30 days × $0.015/call | ~$45 |
| Supabase (Pro plan) | Compute + storage | $25 |
| **Total** | | **~$175/month** |

At $1,000/week per user = $4,000/month for 1 user.
Margin: 95%+ until significant scale.

---
*Generated: 2026-03-31 overnight autonomous run*
*PRD verified: all features from ~/Timed-Brain/03 - Specs/prd-v02.md accounted for*
