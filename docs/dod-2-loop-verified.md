# DoD #2 Loop — Verified Wiring

**Status as of 2026-05-03 evening (Adelaide):** all build/deploy steps complete; tomorrow morning's auto-fire is the final live proof.

This file documents the *complete* path that closes the override → next-morning-briefing learning loop. Anyone (or any future agent) should be able to read this and verify the loop in under 5 minutes.

## What "DoD #2" means

When an executive overrides a task's AI estimate today (and optionally taps a reason chip), the next morning's briefing must reference that correction. Before this work, the path looked closed at the schema level but had **two real gaps**:

1. The Edge Function `generate-morning-briefing` was deployed and wired to read `behaviour_events` calibration via `loadCalibrationContext`, but **no Trigger.dev cron task existed to fire it daily**. JCODE's earlier "PASS" was a synthetic curl invocation, not an automatic schedule.
2. The function had **zero structured logging**, so silent failures (cold-start aborts, calibration helper bugs, RLS errors) would surface as missing briefings with no diagnostic.

Both gaps are now closed.

## What shipped tonight

### 1. Trigger.dev schedule

**File:** `trigger/src/tasks/morning-briefing.ts` (new)
**Task ID:** `morning-briefing`
**Cron:** `30 5 * * *` (Australia/Adelaide)
**Deploy:** `trigger deploy` from Mac, version `20260503.1`, project `proj_vrakwmzenqmmhrzhfqyl`
**Dashboard:** https://cloud.trigger.dev/projects/v3/proj_vrakwmzenqmmhrzhfqyl/deployments/sh43z3m3

Schedule self-registers in the cloud on deploy (v4 behaviour). The task POSTs an empty body to `/functions/v1/generate-morning-briefing` with the service-role bearer token. The Edge Function fans out internally over `executives` and writes one `briefings` row per executive per day. 3-attempt retry policy from `trigger.config.ts` covers transient failures.

### 2. Observability on the Edge Function

**File:** `supabase/functions/generate-morning-briefing/index.ts` (modified)

Three new structured log lines added (Edge Functions stream `console.*` to Supabase Logs):

- `console.log("[morning-briefing] start", { executiveCount, requestedExecutiveId, requestedDate, startedAt })` — fires after auth + executive query, so you know the run actually entered the work loop.
- `console.log("[morning-briefing] complete", { executiveCount, totalDurationMs, statusCounts })` — final summary with a histogram (e.g., `{ ok: 3 }` or `{ skipped: 3 }`) — one-glance health signal.
- `console.error("[morning-briefing] no executives found", { ... })` — early-return diagnostic when the executive table query is empty (which would otherwise look identical to a service-role-auth failure).

These were grep-verified absent before. Now they're the breadcrumbs Tomorrow's runs leave in Supabase Logs.

### 3. Synthetic fixture cleanup

The 8 synthetic fixtures JCODE created during its prior DoD smoke (1 task, 3 behaviour_events, 4 briefings, listed in the earlier `SHIPPED.md`) were deleted via Supabase REST API with service-role auth. Verified counts of fixture IDs returned 0 across all 3 tables.

This means: any briefing generated from now on cites only real data. There's no synthetic ghost data leaking into the calibration helper's queries.

## End-to-end data flow (one correction → next briefing)

```
Ammar overrides a task estimate in Timed.app (TasksPane stepper)
    ↓
DataBridge.logEstimateOverride() inserts behaviour_events row (event_type='estimate_override', old_value, new_value)
    ↓
Reason chip popover surfaces; tap writes event_metadata.reason via DataBridge.attachReasonToLastOverride()
    ↓
[ASLEEP — Mac caffeinated, no further user action ]
    ↓
05:30 Australia/Adelaide: Trigger.dev cron fires `morning-briefing` task
    ↓
Task POSTs {} to /functions/v1/generate-morning-briefing with service-role
    ↓
Edge Function loads executives → for each:
  - loads calibration context (yesterday's overrides, 30d drift, per-bucket bias)
  - runs Pass 1 Opus briefing (7-section JSON output; legacy Edge Function uses claude-opus-4-6 — Trigger.dev tasks route Opus to 4-7 via inference.ts but this function predates that alias)
  - injects calibration as Emerging Patterns section (calibrationBriefingSection helper)
  - runs Pass 2 adversarial review
  - inserts briefings row for today
    ↓
Ammar opens Timed.app the next morning → sees today's briefing → Emerging Patterns section quotes the override
```

## Verification recipe (5 min)

After Ammar makes a real override today and sleeps:

```bash
SUPA="https://fpmjuufefhtlwbfinxlx.supabase.co"
KEY=$(supabase projects api-keys --project-ref fpmjuufefhtlwbfinxlx | awk '/service_role/{for(i=1;i<=NF;i++)if($i~/^eyJ/){print $i;exit}}')

# 1. Confirm yesterday's override was recorded
curl -sS "$SUPA/rest/v1/behaviour_events?select=id,task_id,old_value,new_value,event_metadata,occurred_at&event_type=eq.estimate_override&order=occurred_at.desc&limit=3" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"

# 2. Confirm today's (Adelaide-local) briefing was auto-generated.
# The cron fires at 05:30 ACST, so when you run this in the morning, the
# briefing is dated TODAY (Adelaide), not yesterday or tomorrow. The Edge
# Function now uses each executive's `timezone` column (defaulting to
# Australia/Adelaide) to compute the correct local date — without that,
# the row would be stored under yesterday's UTC date and your client
# query would miss it.
TODAY_ADL=$(TZ=Australia/Adelaide date +%Y-%m-%d)
curl -sS "$SUPA/rest/v1/briefings?select=id,profile_id,date,generated_at&date=eq.$TODAY_ADL" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"

# 3. Spot-check that the briefing content references the override
curl -sS "$SUPA/rest/v1/briefings?select=content&date=eq.$TODAY_ADL&limit=1" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" | \
  python3 -c "import json,sys; b=json.load(sys.stdin)[0]; sects=b['content']['sections']; \
    print('\n---\n'.join([f\"[{s['section']}] {s['insight']}\" for s in sects]))"
# Expect: Emerging Patterns or Forward-Looking Observation section quotes the
# reason from step 1 (e.g., 'hidden complexity', 'took longer') OR cites the
# minute delta.
```

If step 2 returns empty rows → the trigger schedule didn't fire. Check Trigger.dev dashboard runs for the `morning-briefing` task.

## What still needs Ammar (S5 + S8 from the original plan)

### S5 — Real override (tonight, 30 sec)
Open `/Applications/Timed.app`. Pick any task with an AI estimate. Tap the time chip → change the value → tap Done → tap one of the 4 reason chips. That's it.

### S8 — Tomorrow morning verification (3 min)
Set a phone alarm for ~06:00 ACDT. When it fires, run the verification recipe above. If it green-lights, DoD #2 is verified end-to-end on real data. Update this doc's status block to `VERIFIED on YYYY-MM-DD`.

## Recovery if tomorrow's auto-fire fails

If the Trigger.dev cloud dashboard shows no `morning-briefing` run in the past 24h:

1. `cd ~/time-manager-desktop/trigger && ./node_modules/.bin/trigger deploy` to re-deploy.
2. Check `~/time-manager-desktop/trigger/src/tasks/morning-briefing.ts` exists and exports `morningBriefing` from `schedules.task({ id: "morning-briefing", cron: { pattern: "30 5 * * *", timezone: "Australia/Adelaide" }, ... })`.
3. Manually fire once via cloud dashboard or via `curl -X POST` to the Edge Function with service-role auth (proven to work tonight at 12:32 UTC against all 3 executives).

If the briefing is generated but contains no calibration text:

1. Confirm a real override exists in `behaviour_events` for the prior 24h: query above (step 1 of recipe).
2. Confirm the calibration helper queries return data: `loadCalibrationContext(client, executiveId)` reads `behaviour_events`, `user_profiles.avg_estimate_error_pct`, and `estimation_history` per-bucket. Spot-check each table.
3. Read `[morning-briefing] start` and `[morning-briefing] complete` logs in Supabase Logs to see the executive count and status histogram.

## Files to grep for if you need to find this work later

- Trigger.dev task: `trigger/src/tasks/morning-briefing.ts`
- Edge Function modifications: `[morning-briefing] start` and `[morning-briefing] complete` strings in `supabase/functions/generate-morning-briefing/index.ts`
- Calibration helper (built earlier): `supabase/functions/_shared/calibration.ts`
- Section composer (built earlier): `calibrationBriefingSection` and `ensureCalibrationSection` in the briefing function

## Why this is the moat

Without this loop closed at the morning-briefing layer, every estimate correction Ammar makes is filed in a drawer that nothing reads. The system would never feel intelligent — overriding 20→45m a thousand times changes nothing about tomorrow's advice.

With it closed: every override compounds. The 30-day drift becomes a real metric. Per-bucket bias becomes a callout. Reason chips become qualitative signal. Six months in, the morning briefing tells Ammar things about himself he didn't consciously articulate.

That's the difference between "task app" and "executive cognitive OS."
