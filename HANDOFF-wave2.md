# Wave 2 Handoff — Timed overnight cognitive OS

Date: 2026-04-24
Base branch: `ui/apple-v1-restore`
Head: `363199f` (Wave 2 complete)

## Summary

Wave 2 builds the server-side overnight engine on top of Wave 1's `inference()` wrapper, `agent_sessions` / `agent_traces` ledger, Graphiti MCP, and skill-library MCP:

- **Server-side Graph delta sync** replaces Swift client polling when a per-exec flag is flipped (`executives.email_sync_driver = 'server'`).
- **NREM pipeline** (02:00–03:00): Batch-API episode/entity extraction → A-MEM fact evolution → Nemori delta distillation.
- **REM synthesis** (03:30): Opus agent drives four canonical queries over Graphiti + skill-library MCPs, writes one `semantic_synthesis` row per exec per day.
- **Outcome harvester** (every 4h) closes the Reflexion feedback loop from `behaviour_events` to `recommendation_outcomes`.
- **Operational guards**: ingestion-health watchdog (15m), Graph webhook renewal (2h), weekly KG snapshot (Sun 03:45) with 52-week retention.
- **Full observability**: every MCP tool call and Agent-SDK loop block is persisted to `agent_traces`.

All 4 PRs reviewed SHIP by parallel Opus reviewers. `pnpm tsc --noEmit` clean on merged `ui/apple-v1-restore`.

## PRs merged

| PR | Branch | Tasks | Squash SHA |
|----|--------|-------|-----------|
| [#6](https://github.com/ammarshah1n/time-manager-desktop/pull/6) | `wave2-b1-server-graph` | T8 T9 T10 T11 T12 T12a T39 | `bbf6888` |
| [#7](https://github.com/ammarshah1n/time-manager-desktop/pull/7) | `wave2-b2-nrem-pipeline` | T25 T25a T26 T27 T32 | `bce4fd9` |
| [#8](https://github.com/ammarshah1n/time-manager-desktop/pull/8) | `wave2-b3-outcome-loop` | T24 | `6b78af1` |
| [#9](https://github.com/ammarshah1n/time-manager-desktop/pull/9) | `wave2-b4-rem-synthesis` | T28 T28a T30 | `363199f` |

### What landed (17 new files, ~5000 LOC)

**Trigger.dev tasks** (`trigger/src/tasks/`):
- `graph-delta-sync.ts` (cron `*/1 * * * *`) — email delta per exec.
- `graph-calendar-delta-sync.ts` (`*/5 * * * *`) — calendarView delta.
- `graph-webhook-renewal.ts` (`0 */2 * * *`) — subscription renewal with app token.
- `ingestion-health-watchdog.ts` (`*/15 * * * *`) — email/calendar/agent_sessions staleness alerts.
- `nrem-entity-extraction.ts` (`0 2 * * *`) — Anthropic Batch API submit, exit.
- `nrem-entity-extraction-consume.ts` (`*/5 2-8 * * *`) — poll + drain + graphiti-mcp upsert.
- `nrem-amem-evolution.ts` (`30 2 * * *`) — Agent SDK + Opus + graphiti-mcp.
- `nrem-nemori-distillation.ts` (`45 2 * * *`) — search_facts → predict → delta-only add_fact.
- `rem-synthesis.ts` (`30 3 * * *`) — Opus agent, four canonical queries, writes `semantic_synthesis`.
- `kg-snapshot.ts` (`45 3 * * 0`) — weekly `export_snapshot`, 52-week retention.
- `outcome-harvester.ts` (`0 */4 * * *`) — behaviour_events → recommendation_outcomes via watermarks.
- `graphiti-backfill.ts` (one-off) — idempotent backfill of ona_nodes/edges + last 90d tier0_observations.

**Trigger.dev libs** (`trigger/src/lib/`):
- `graph-app-auth.ts` — Microsoft client-credentials token cache per tenant.
- `trace-tool-results.ts` — shared helpers: `openAgentSession`, `closeAgentSession`, `traceToolCall`, `callMcpTool`, `callSkillLibraryMcpTool`.

**Supabase migrations** (`supabase/migrations/`):
- `20260427000000_email_sync_driver.sql` — `executives.email_sync_driver` client|server.
- `20260427000100_email_sync_state.sql` — `email_sync_state`, `graph_subscriptions`, `calendar_observations.graph_event_id`.
- `20260427100000_batch_jobs.sql` — Anthropic Batch job tracker.
- `20260427100100_graphiti_backfill_watermark.sql` — per-kind backfill cursor.
- `20260427110000_harvester_watermarks.sql` — outcome-harvester watermark (seeded).
- `20260427200000_semantic_synthesis.sql` — one row per (exec_id, date), UPSERT semantics.
- `20260427210000_briefings_source.sql` — `briefings.source` legacy|trigger.
- `20260427220000_kg_snapshots.sql` — weekly KG snapshot metadata.

**Swift**:
- `Sources/Core/Services/EmailSyncService.swift` — `start(...)` now async; reads `executives.email_sync_driver` via Supabase REST and no-ops when `server`. Fails open to `client` on any read error.

### What did NOT change
- `trigger/src/inference.ts` — T31 prompt caching remains the single source of truth for model routing + cache_control retrofit (verified in every review).

## PRs blocked

None.

## Wave 2 runtime gate status

Wave 2 code is MERGED but NOT YET running in production. The runtime gate is 3 consecutive nights of `nrem-entity-extraction` + `rem-synthesis` completing clean with `cache_read_tokens > 0` in `agent_sessions`. This gate is STILL BLOCKED — it depends on the manual steps below.

## Ammar's next manual steps (unchanged from Wave 1 handoff, repeated here for convenience)

1. **T7 — Microsoft Entra ID app** `Timed-Server-Graph` with *application-level* permissions `Mail.Read` + `Calendars.Read`, admin consent granted on the tenant, 24-month client secret. Record `MSFT_TENANT_ID`, `MSFT_APP_CLIENT_ID`, `MSFT_APP_CLIENT_SECRET`.
2. **T13 — Neo4j** — either Neo4j AuraDB Professional (managed) or a Fly.io Neo4j instance with 4 GB RAM / 50 GB storage and nightly snapshots enabled. Record `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD`.
3. **T2 — Trigger.dev** org + project + all secrets set:
   - `ANTHROPIC_API_KEY`
   - `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
   - `VOYAGE_API_KEY` (skill-library-mcp)
   - `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD`
   - `MSFT_TENANT_ID`, `MSFT_APP_CLIENT_ID`, `MSFT_APP_CLIENT_SECRET`
   - `GRAPHITI_MCP_URL`, `GRAPHITI_MCP_TOKEN`
   - `SKILL_LIBRARY_MCP_URL`, `SKILL_LIBRARY_MCP_TOKEN`
   - `YASSER_EMAIL`
   - `TRIGGER_PROJECT_REF` (for `trigger.config.ts`)
4. **Deploy** in this order:
   - `supabase db push` — 8 new migrations from Wave 2 land.
   - `fly deploy` of `services/graphiti` (FastAPI) and `services/graphiti-mcp` and `services/skill-library-mcp`.
   - `pnpm -F @timed/trigger deploy` (`trigger.dev deploy`).
5. **Flip the driver**: `UPDATE executives SET email_sync_driver='server' WHERE email='<yasser>';` — this is the one switch that moves polling off the Swift client.
6. **Seed the KG**: manually trigger `graphiti-backfill` once. Running twice should be a provable no-op (watermark + `episode_exists`).
7. **Watch three nights**: verify `agent_sessions WHERE task_name IN ('nrem-amem-evolution','rem-synthesis') AND status='completed'` for three consecutive nights with `cache_read_tokens > 0`. When that holds, the Wave 2 runtime gate is satisfied.

## Wave 3+

**Wave 3 MUST NOT be attempted until Wave 2 runtime is verified (three clean nights with non-zero `cache_read_tokens`).** Merging more code before the engine has demonstrably run once in production only compounds debugging surface.

## Build verification

- `pnpm -F @timed/trigger tsc --noEmit` — clean on merged `ui/apple-v1-restore` (`363199f`).
- `swift build` — NOT RUN. Swift 6.1 toolchain is not available in the environment that merged this wave. The B1 `EmailSyncService.swift` edit was authored to compile under Swift 6.1 StrictConcurrency but must be verified on macOS before the next Sparkle build. Specifically:
  - `start(...)` is now `async`.
  - A new private helper reads `executives.email_sync_driver` via URLSession + anon key (URLSession calls inside the actor, no captured mutable state crosses boundaries).
  - If a Sendable or isolation warning shows up on a macOS build, the likely culprit is the URLSession completion in the helper — move the decode call inside the actor.

## Known pragmatic defaults that outlived review (revisit if they bite)

- `EmailSyncService` reads the driver via Supabase REST (anon key + RLS `executives_select_own`) rather than adding a method to `SupabaseClient.swift`. Cleanup: once the DataBridge overhaul lands, route through the typed client.
- `calendar_observations.graph_event_id` added by B1's supporting migration (column + partial unique index). Any future calendar provider must respect this unique constraint.
- Watchdog queries `email_messages` globally (no exec-level join). Acceptable while single-exec; revisit when multi-exec lands.
- `task_deferred` → `partial` outcome mapping is a B3 pragmatic default — adjust if Ammar wants `task_deferred` to count as `dismissed`.
- `callMcpTool` does NOT unwrap `structuredContent` — callers parse text blocks themselves. If a tool-call ergonomics pass is needed, centralise unwrapping in the helper.
- B2 & B4 both added `callSkillLibraryMcpTool`; B4's version was taken on merge (strict superset). Functionally identical.
- Agent SDK uses `budgetTokens` (camelCase); raw Messages API uses `budget_tokens`. Do not conflate.

## Wave 1 follow-ups still open

Not touched in Wave 2 (explicitly out of scope):
- **A3 RMW race** on `briefings.sections_interacted` — pending Postgres RPC refactor for atomic JSONB append.
- **A5 stubs** in `trigger/scripts/` — `replay.ts` / `export-training-data.ts` are scaffolds, not yet production-callable.
