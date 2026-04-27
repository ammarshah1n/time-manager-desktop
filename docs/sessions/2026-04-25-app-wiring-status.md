# App wiring status — what the SwiftUI app actually does with the Wave 1+2 backend

## TL;DR

The Swift app **is** wired into the relevant parts of the new backend. Most of Wave 1+2 is server-only and the app correctly does not need to know about it. **The one thing to watch:** A3's PR #3 modified `Sources/Features/Briefing/MorningBriefingPane.swift` to capture per-section interactions. If you're holding uncommitted UI changes to that same file in your working tree, you'll get a merge conflict on next pull. This doc lists exactly what's in A3's diff so you can reconcile by hand.

## What's wired (Swift ↔ backend)

### App → backend writes (these light up because of A3 / B1)

| When the user does this in the app | Swift call site | What lands server-side |
|---|---|---|
| Completes the onboarding voice flow | `Sources/Features/Onboarding/OnboardingFlow.swift` `onComplete` | Row in `executive_profile` (work hours, transit, time defaults, PA fields) via `SupabaseClient.upsertExecutiveProfile(...)` |
| Sees a briefing section appear (`.onAppear`) | `Sources/Features/Briefing/MorningBriefingPane.swift` | `behaviour_events` row with `event_type='briefing_section_viewed'` AND append to `briefings.sections_interacted` JSONB |
| Taps a briefing section (`.onTapGesture`) | same file | `behaviour_events` row with `event_type='briefing_section_interacted'` |
| Acts on a section via the overlay menu | same file | `behaviour_events` row with `event_type='recommendation_acted_on'` |
| Dismisses a section via the overlay menu | same file | `behaviour_events` row with `event_type='recommendation_dismissed'` |

These four event types are NEW in `BehaviourEventInsert` (PR #3 extended `Sources/Core/Clients/SupabaseClient.swift`).

`outcome-harvester` (Trigger.dev cron `0 */4 * * *`) reads these `behaviour_events` rows every 4h, matches them to the `recommendations` rows that A4's patched briefing EF emits, and writes `recommendation_outcomes`. The Reflexion feedback loop closes from app → server without further app changes.

### Backend → app reads (these are unchanged or forward-compatible)

| What the user sees | Swift read path | What changed in Wave 1+2 |
|---|---|---|
| Morning briefing | `MorningBriefingPane` reads most-recent `briefings` row for today | **Forward-compatible.** Today reads `source='legacy'`. When Wave 3's `morning-briefing-v2` Trigger.dev task lands, briefings will start arriving with `source='trigger'`. Swift always picks the most recent row for the date — no Swift change needed. |
| Email + calendar | `DataBridge` / existing UI | **Forward-compatible.** `EmailSyncService` now no-ops when `executives.email_sync_driver='server'`, and B1's server-side delta sync writes to the same `email_messages` / `calendar_observations` tables the UI already reads. Swap is invisible to the UI. |

### What's deliberately NOT wired into the app

These are all server-internal — the app should never call them directly:

- `inference()` wrapper, `agent_sessions`, `agent_traces` — Trigger.dev reasons over these; the app would learn nothing from reading them.
- Graphiti MCP, skill-library MCP, graphiti-python — agentic-loop infrastructure, server-side only.
- `semantic_synthesis` table — upstream of `briefings`. The app reads the briefing, not the synthesis.
- All Trigger.dev tasks (graph-delta-sync, NREM, REM, kg-snapshot, outcome-harvester, etc.) — fire on cron, not from the app.
- `kg_snapshots`, `batch_jobs`, `harvester_watermarks`, `graphiti_backfill_watermark`, `graph_subscriptions`, `email_sync_state` — operational state owned by Trigger.dev.

If you ever want the app to expose any of these (e.g. "show me the synthesis that drove today's briefing"), that's a future feature — not a Wave 1+2 concern.

## The one thing you need to know about your in-progress UI work

The Swift files A3 (PR #3) modified:

- `Sources/Features/Onboarding/OnboardingFlow.swift`
- `Sources/Features/Briefing/MorningBriefingPane.swift`
- `Sources/Core/Clients/SupabaseClient.swift`
- `Sources/Core/Models/MorningBriefing.swift`

Of those, when we last looked at your main worktree's `git status`, you had uncommitted edits in:

- `Sources/Features/Briefing/MorningBriefingPane.swift` ← **conflicts with A3**

(plus several other files like `TriagePane.swift`, `BrandTokens.swift`, `CapturePane.swift`, etc. — none of those overlap with Wave 1+2).

**What A3 added to `MorningBriefingPane.swift`:**

- A `Set<String>` to track which sections have already been "viewed" (so `.onAppear` doesn't double-count on scroll-back).
- An `.onAppear` modifier on each section that fires `briefing_section_viewed` once per section per session.
- An `.onTapGesture` on each section that fires `briefing_section_interacted`.
- An overlay menu (long-press or contextMenu, depending on platform) with "Act on" / "Dismiss" actions that fire `recommendation_acted_on` / `recommendation_dismissed`.
- A helper `writeSectionEvent(...)` that calls `SupabaseClient.insertBehaviourEvent(...)` AND `SupabaseClient.appendBriefingSectionInteraction(...)`.

**What A3 added to `MorningBriefing.swift` (model):**

- `sectionsInteracted` shape changed from `[String]` to `[[String: String]]` — each entry is a dict like `{"section_key": "priorities", "event_type": "viewed", "occurred_at": "2026-04-25T..."}`. If your UI work iterates `sectionsInteracted` as plain strings, this will fail to compile.

### Recommended reconciliation flow

```bash
# from your main worktree
cd ~/time-manager-desktop

# stash your in-progress UI work
git stash push -m "ui-edits-in-flight" -- Sources Tests

# pull the merged trunk (includes A3 + everything else)
git fetch origin ui/apple-v1-restore
git reset --hard origin/ui/apple-v1-restore

# pop your stash, accept conflicts on MorningBriefingPane.swift only
git stash pop
# resolve MorningBriefingPane.swift by hand:
#   - keep A3's writeSectionEvent helper, .onAppear/.onTapGesture, overlay menu
#   - merge in your visual edits around them
# resolve MorningBriefing.swift if you touched it (check git status)

# verify it compiles
swift build

# commit the merge
git add Sources
git commit -m "merge: reconcile UI in-flight with A3 per-section capture"
```

If your changes to `MorningBriefingPane.swift` are purely visual (typography, spacing, colours, brand tokens), the merge will be a 5-minute operation — A3's additions are at the data-flow layer, your changes are at the View layer.

## Verification — does the wiring actually work end-to-end?

Right now, the answer is: **mostly yes, with one gap**.

### Yes:
- `swift build` clean on merged HEAD (verified after Wave 1+2 merged).
- `OnboardingFlow.upsertExecutiveProfile` payload struct matches the migration columns 1:1 (verified by A3's reviewer).
- `BehaviourEventInsert` extended with the four new event types; database CHECK constraint accepts them (migration `20260425020000_briefing_interaction_events.sql` is applied).
- `appendBriefingSectionInteraction` Postgres-side targets the column added by the same migration.

### Gap (known, queued for follow-up — not breaking):
- `appendBriefingSectionInteraction` uses a SELECT → modify → UPDATE pattern on `briefings.sections_interacted` JSONB. If two interactions fire concurrently in the same RTT, one append could be lost. Single-user app means risk is low; A3's reviewer flagged it. The fix is a Postgres RPC using `jsonb_insert` or `||` array append, but it's not on the critical path because `behaviour_events` is the authoritative source and is never lost. Add to a future `fix/jsonb-append-rpc` PR before any concurrent-write feature ships.

### Untested live but logically sound:
- The path from a real interaction → `behaviour_events` → `outcome-harvester` cron → `recommendation_outcomes`. We have not fired this in production because the briefing pipeline has not yet emitted recommendations rows for a real briefing — that requires the legacy briefing EF (now patched in PR #4) to fire on Yasser's account at 5am UTC. The patch is deployed-but-deferred-deploy: source-only on origin, not yet pushed to Supabase via `supabase functions deploy`. Once you `supabase functions deploy generate-morning-briefing` and the next 5am briefing fires, the loop completes.

## Next-touch points for the UI

Things you might naturally want to add as part of your in-flight UI work that would benefit from Wave 1+2:

- **Show "X people acted on this kind of section last week"** — read from `recommendation_outcomes` aggregated by `outcome_type`.
- **Show "this insight was synthesised from Y episodes"** — read `semantic_synthesis.evidence_refs` and resolve back to `tier0_observations`.
- **Show synthesis confidence / dissent** — read the `critique` column on `weekly_syntheses` once Wave 4 lands.

None of these are needed for Wave 1+2 to ship. They're just the natural surfaces for the data the new pipeline produces.
