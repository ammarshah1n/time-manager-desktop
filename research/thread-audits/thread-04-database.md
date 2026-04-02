# Timed — Database Schema Optimisation Guide
**Research Thread 4 of 7 | `ammarshah1n/time-manager-desktop` · `ui/apple-v1-restore`**
**File audited:** `supabase/migrations/20260331000001_initial_schema.sql`

***

## Executive Summary

The schema is well-structured for its domain, but seven optimisation opportunities exist ranging from high-impact correctness fixes to nice-to-have tuning. The most critical issues are: (1) the `current_workspace_ids()` RLS helper is called per-row without plan caching, causing potentially catastrophic query slowdowns; (2) IVFFlat vector indexes should be migrated to HNSW given the continuous-insert pattern; and (3) the `behaviour_rules` JSONB column in `user_profiles` duplicates the separate `behaviour_rules` table, creating a data-consistency hazard.

| # | Area | Impact | Effort | Priority |
|---|------|--------|--------|----------|
| 1 | RLS policy caching (`select` wrapper) | 🔴 Critical | Low | **P0** |
| 2 | IVFFlat → HNSW index swap | 🟠 High | Low | **P1** |
| 3 | Partition RLS on child tables | 🟠 High | Low | **P1** |
| 4 | pg_cron job suite | 🟡 Medium | Medium | **P2** |
| 5 | JSONB de-duplication & GIN indexes | 🟡 Medium | Medium | **P2** |
| 6 | Partition strategy validation | 🟢 Low–Medium | Low | **P3** |
| 7 | Migration splitting & zero-downtime | 🟢 Low | High | **P3** |

***

## 1. Partitioning Strategy

### Is monthly range partitioning optimal here?

`behaviour_events` is partitioned by `RANGE (occurred_at)` monthly. For a single user generating 100–500 events/day, that is 3,000–15,000 rows per monthly partition — a very small table. PostgreSQL's partitioning planner overhead can become the dominant cost when partitions are small. The planner evaluates partition pruning logic for every partition in the inheritance tree, and on small datasets the planning time can exceed the execution time.[^1]

**Range vs Hash for this workload:**

| Criterion | Range (current) | Hash |
|-----------|----------------|------|
| Time-bounded queries (`occurred_at BETWEEN`) | ✅ Partition pruning eliminates old months | ❌ No pruning — all partitions scanned |
| "What happened in March 2026?" | ✅ Reads single child table | ❌ Reads all partitions |
| Even data distribution | ✅ Roughly even | ✅ Guaranteed even |
| Data archival (drop old month) | ✅ `DETACH PARTITION` is instant | ❌ Cannot detach by time |
| Planning overhead | ❌ Linear with partition count | ✅ Fixed number of partitions |

**Verdict:** Keep range partitioning. Hash partitioning would eliminate the only two real benefits of the partition strategy — time-range query pruning and instant old-data archival via `DETACH PARTITION`. The planning overhead concern is real but manageable by keeping partition count below 24 (rolling 2 years of monthly data).[^2][^3]

### Archival schedule

Old partitions should be detached after the data is no longer needed for ML feature extraction. Given that `estimation_history` and `behaviour_rules` distil insights continuously, the raw events become redundant after 6 months:

```sql
-- Run monthly via pg_cron to detach the partition 6 months ago
-- ~5 lines
DO $$
DECLARE
  partition_name text;
  cutoff_month   date := date_trunc('month', now() - interval '6 months');
BEGIN
  partition_name := 'behaviour_events_' || to_char(cutoff_month, 'YYYY_MM');
  IF to_regclass('public.' || partition_name) IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.behaviour_events DETACH PARTITION public.%I', partition_name);
    -- Optional: EXECUTE format('DROP TABLE public.%I', partition_name);
    -- Or: move to cold storage / Supabase Storage as JSONL export
  END IF;
END $$;
```

### Pre-creating future partitions

The schema only creates 3 partitions. Add a pg_cron job to stay 2 months ahead:

```sql
-- ~12 lines — create next 2 months' partitions if they don't exist
CREATE OR REPLACE FUNCTION public.ensure_behaviour_partitions()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  target_month date;
  pname        text;
BEGIN
  FOR i IN 0..1 LOOP
    target_month := date_trunc('month', now() + (i || ' months')::interval);
    pname := 'behaviour_events_' || to_char(target_month, 'YYYY_MM');
    IF to_regclass('public.' || pname) IS NULL THEN
      EXECUTE format(
        'CREATE TABLE public.%I PARTITION OF public.behaviour_events
         FOR VALUES FROM (%L) TO (%L)',
        pname,
        target_month,
        target_month + interval '1 month'
      );
      -- Re-enable RLS on new partition (see §3)
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', pname);
    END IF;
  END LOOP;
END $$;
```

***

## 2. Vector Index Audit — IVFFlat → HNSW

### Current state

Both `email_messages.embedding` and `tasks.embedding` use `ivfflat (lists = 100)` with `vector_cosine_ops`. The schema comment correctly notes a future switch to HNSW for >1M rows, but the cutover threshold should be much lower.

### Performance comparison at expected scale

| Metric | IVFFlat (lists=100) | HNSW (m=16, ef_construction=64) |
|--------|--------------------|---------------------------------|
| Query latency at ~58K rows | ~2.4 ms[^4] | ~1.5 ms[^4] |
| Default recall | 70–80% (needs tuning)[^5] | 95%+ out of box[^5] |
| Build time at 58K rows (pgvector 0.6+) | ~15 s[^4] | ~30 s[^4] |
| Index memory | Compact | 2–5× larger[^5] |
| Handles continuous inserts | Degrades — rebuilds needed[^5] | Incremental graph update[^5] |
| Maintenance | Periodic REINDEX after bulk loads | Minimal[^5] |

HNSW begins outperforming IVFFlat at around 30,000–50,000 vectors. Both `email_messages` and `tasks` will cross this threshold within months of normal use. More importantly, Timed inserts embeddings continuously (not in bulk batches), which is precisely the workload where IVFFlat recall degrades over time without periodic `REINDEX`. IVFFlat with `lists=100` should have at least 3,000 rows before the index is even built (the recommended rule of thumb is rows ≥ lists × 39).[^6][^5][^7]

### Migration SQL

```sql
-- Migration: 20260401000001_hnsw_embeddings.sql
-- ~18 lines total

-- Drop old IVFFlat indexes
DROP INDEX CONCURRENTLY IF EXISTS public.email_messages_embedding_idx;
DROP INDEX CONCURRENTLY IF EXISTS public.tasks_embedding_idx;

-- Rebuild as HNSW
-- m=16, ef_construction=64 are Supabase-recommended defaults
CREATE INDEX CONCURRENTLY email_messages_embedding_hnsw_idx
  ON public.email_messages
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE INDEX CONCURRENTLY tasks_embedding_hnsw_idx
  ON public.tasks
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Set ef_search at query time for accuracy vs speed trade-off
-- Add to edge function session: SET hnsw.ef_search = 100;
-- Values 80–120 are appropriate for this use case
```

**Build-time note:** On Supabase's shared Postgres, `maintenance_work_mem` is constrained. For tables under 50K rows, HNSW builds in seconds to low minutes. The parallel build improvements in pgvector 0.6.0 (up to 30× faster) are active on the Supabase platform. Use `CONCURRENTLY` to avoid blocking reads during the build.[^8]

**halfvec consideration:** If Supabase's shared instance shows memory pressure on the HNSW index, consider `halfvec(1536)` (pgvector 0.7.0+) which cuts index memory by exactly 50% at no recall cost for well-trained embeddings.[^9]

***

## 3. RLS — The Critical Performance Bug

### The problem

The current workspace isolation policy pattern is:

```sql
-- From schema — repeated across 7+ tables
USING (workspace_id = any(public.current_workspace_ids()))
```

`current_workspace_ids()` is declared `STABLE SECURITY DEFINER`, which is correct. However, without the `(select ...)` wrapper, PostgreSQL's query planner does **not** cache the function result — it calls it once per row. On a table with 10,000 rows, this means 10,000 round-trips to `workspace_members`. Supabase's own benchmarks show this pattern causing 171 ms execution time on a 100K row table, reducible to 9 ms with the wrapper.[^10]

### Fix — Wrap all RLS policies

```sql
-- Migration: 20260401000002_rls_perf_fix.sql
-- ~60 lines total (one DROP/CREATE pair per policy)

-- Example: tasks (repeat pattern for all 7 tables)
DROP POLICY IF EXISTS "tasks_workspace_isolation" ON public.tasks;
CREATE POLICY "tasks_workspace_isolation"
  ON public.tasks FOR ALL TO authenticated
  USING  (workspace_id = any((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = any((select public.current_workspace_ids())));

-- Pattern to apply to: email_messages, daily_plans, waiting_items,
-- voice_captures, user_profiles, behaviour_rules
```

The `(select ...)` wrapper forces the planner to run `current_workspace_ids()` once as an `initPlan` and cache the result for the entire query. Benchmarks show improvements of 11×–100× depending on table size.[^10]

### Missing RLS policies

The schema enables RLS on all tables via the `DO $$` loop, but only creates explicit policies for 7 tables. The following tables have RLS **enabled but no policy** — meaning authenticated users see zero rows:

- `email_triage_corrections`
- `sender_rules`
- `estimation_history`
- `plan_items`
- `voice_capture_items`
- `ai_pipeline_runs`
- `webhook_events` (this one may be intentional for service-role-only access)

```sql
-- Migration: 20260401000003_missing_rls_policies.sql
-- ~50 lines

CREATE POLICY "email_triage_corrections_workspace_isolation"
  ON public.email_triage_corrections FOR ALL TO authenticated
  USING  (workspace_id = any((select public.current_workspace_ids())))
  WITH CHECK (workspace_id = any((select public.current_workspace_ids())));

-- Repeat for: sender_rules, estimation_history, plan_items,
-- voice_capture_items, ai_pipeline_runs

-- For webhook_events: service_role only (no authenticated policy needed)
-- For workspaces / workspace_members / profiles: add read-only policies
```

### Child partition RLS gap

The schema enables RLS on `behaviour_events_2026_03/04/05` individually in the `DO $$` loop, but the `ensure_behaviour_partitions()` function above (and any manually created partitions) must also have RLS enabled. Native partitioning in PostgreSQL does **not** automatically propagate RLS from the parent to new child partitions.[^11]

```sql
-- Add to ensure_behaviour_partitions() after CREATE TABLE:
EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', pname);

-- And add the isolation policy:
EXECUTE format(
  'CREATE POLICY workspace_isolation ON public.%I FOR ALL TO authenticated
   USING (workspace_id = any((select public.current_workspace_ids())))',
  pname
);
```

### Single-user app: keep RLS anyway

The schema uses `workspace_id` throughout — suggesting multi-tenancy readiness even for a "solo" plan. Disabling RLS and using the `service_role` key in all edge functions saves ~10 ms per query on small datasets but introduces meaningful risks: any client-side JavaScript that accidentally receives the service role key bypasses **all** security permanently. The `service_role` key should be used selectively — only in server-side edge functions for batch jobs that need to write across workspace boundaries. Keep RLS enabled; fix the `(select ...)` wrapper instead.[^12][^13][^14]

***

## 4. pg_cron Job Suite

The schema has all cron jobs commented out as `-- TODO`. The following jobs should be activated immediately after deploying the schema. **Free tier caveat:** Supabase's pg_cron runs jobs within a 2-minute soft timeout on shared infrastructure. All jobs below are designed to complete well within that window for single-user data volumes.[^15]

```sql
-- Migration: 20260401000004_cron_jobs.sql
-- ~55 lines

-- 1. UPDATE is_overdue flags every 15 minutes
SELECT cron.schedule(
  'update-overdue-tasks',
  '*/15 * * * *',
  $$UPDATE public.tasks
    SET is_overdue = (due_at < now()), updated_at = now()
    WHERE status IN ('pending','in_progress')
      AND due_at IS NOT NULL
      AND is_overdue != (due_at < now())$$
);

-- 2. VACUUM ANALYZE high-write tables nightly at 03:00 UTC
-- (autovacuum handles most cases; this ensures fresh planner stats)
SELECT cron.schedule(
  'nightly-vacuum-analyse',
  '0 3 * * *',
  $$VACUUM ANALYZE public.behaviour_events,
                   public.tasks,
                   public.email_messages,
                   public.ai_pipeline_runs$$
);

-- 3. Create next month's behaviour_events partition on 1st of each month
SELECT cron.schedule(
  'create-behaviour-partitions',
  '0 1 1 * *',
  $$SELECT public.ensure_behaviour_partitions()$$
);

-- 4. Detach stale behaviour_events partitions > 6 months old
SELECT cron.schedule(
  'archive-old-behaviour-partitions',
  '0 2 1 * *',
  $$SELECT public.archive_old_behaviour_partitions()$$  -- function from §1
);

-- 5. Prune estimation_history older than 1 year (keep ML signal window bounded)
SELECT cron.schedule(
  'prune-estimation-history',
  '0 4 1 * *',  -- 1st of month, 04:00 UTC
  $$DELETE FROM public.estimation_history
    WHERE created_at < now() - interval '1 year'$$
);

-- 6. Clean up processed webhook_events older than 7 days
SELECT cron.schedule(
  'cleanup-processed-webhooks',
  '0 5 * * *',
  $$DELETE FROM public.webhook_events
    WHERE status = 'processed'
      AND processed_at < now() - interval '7 days'$$
);

-- 7. Clean up stale ai_pipeline_runs older than 90 days
SELECT cron.schedule(
  'cleanup-old-pipeline-runs',
  '0 5 1 * *',
  $$DELETE FROM public.ai_pipeline_runs
    WHERE started_at < now() - interval '90 days'$$
);

-- 8. Weekly profile card regeneration (Sunday 02:00 UTC) — already in schema
SELECT cron.schedule(
  'regenerate-profile-cards',
  '0 2 * * 0',
  $$SELECT net.http_post(
      url := current_setting('app.supabase_url') || '/functions/v1/generate-profile-cards',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || current_setting('app.service_role_key')
      )
  )$$
);

-- 9. Renew Graph webhook subscriptions every 2 days — already in schema
SELECT cron.schedule(
  'renew-graph-subscriptions',
  '0 0 */2 * *',
  $$SELECT net.http_post(
      url := current_setting('app.supabase_url') || '/functions/v1/renew-graph-subscriptions',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || current_setting('app.service_role_key')
      )
  )$$
);
```

**Store secrets safely:** Use `ALTER DATABASE postgres SET app.supabase_url = '...'` rather than hard-coding service role keys in cron SQL. The schema's commented-out versions inline the key directly — this is a security risk if the `cron.job` table is ever accidentally read.

***

## 5. JSONB vs Normalised Tables

### Current dual-storage problem

`user_profiles` has a `behaviour_rules` JSONB column (an array of rule objects) **and** there is a separate `behaviour_rules` table with the same logical data. The comment says the JSONB column holds "inferred rules" for the profile card generator, while the table holds "individual rule rows for queryability + audit". This creates two sources of truth that can drift.

### Decision framework for this schema

| Column | Store as JSONB? | Rationale |
|--------|----------------|-----------|
| `user_profiles.behaviour_rules` (JSONB array) | ✅ Keep as **derived cache** | Profile card generator reads all rules at once; JSONB avoids a JOIN |
| `user_profiles.prefs_json` | ✅ Keep | Flexible user preferences with unknown schema; will evolve |
| `behaviour_rules.rule_value_json` | ✅ Keep | Rule values vary by `rule_type` (ordering vs threshold vs timing) |
| `behaviour_events.old_value / new_value` | ✅ Keep | Event-specific payload, schema varies by `event_type` |
| `profile_card_text` | ✅ Keep as `text` | Already correct — pre-rendered prose, not queryable |

### Fix: make JSONB a derived materialisation

The `behaviour_rules` column on `user_profiles` should be treated as a read-through cache refreshed by a trigger or the weekly cron job, not written directly:

```sql
-- Migration: 20260401000005_behaviour_rules_sync.sql
-- ~20 lines

CREATE OR REPLACE FUNCTION public.sync_behaviour_rules_cache()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.user_profiles up
  SET behaviour_rules = (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'rule_key',       br.rule_key,
        'rule_type',      br.rule_type,
        'rule_value_json',br.rule_value_json,
        'confidence',     br.confidence,
        'sample_size',    br.sample_size,
        'last_updated',   br.updated_at
      )
    ), '[]'::jsonb)
    FROM public.behaviour_rules br
    WHERE br.workspace_id = NEW.workspace_id
      AND br.profile_id   = NEW.profile_id
      AND br.is_active    = true
  )
  WHERE up.workspace_id = NEW.workspace_id
    AND up.profile_id   = NEW.profile_id;
  RETURN NEW;
END $$;

CREATE TRIGGER sync_behaviour_rules_after_upsert
  AFTER INSERT OR UPDATE OR DELETE
  ON public.behaviour_rules
  FOR EACH ROW EXECUTE FUNCTION public.sync_behaviour_rules_cache();
```

### GIN index for profile card batch job

The `generate-profile-cards` edge function presumably reads `behaviour_rules` via containment queries like `rule_value_json @> '{"rule_type": "ordering"}'`. Without a GIN index, this is a sequential scan:[^16]

```sql
-- Migration: 20260401000006_jsonb_gin_indexes.sql
-- ~8 lines

-- jsonb_path_ops for containment queries only (@>) — smaller index, faster writes
CREATE INDEX behaviour_rules_value_gin_idx
  ON public.behaviour_rules
  USING gin (rule_value_json jsonb_path_ops);

-- GIN on prefs_json for user preference lookups
CREATE INDEX user_profiles_prefs_gin_idx
  ON public.user_profiles
  USING gin (prefs_json jsonb_path_ops);

-- Expression index for frequently queried rule_type column (already normalised, add btree)
CREATE INDEX IF NOT EXISTS behaviour_rules_type_idx
  ON public.behaviour_rules (profile_id, rule_type, is_active);
```

**TOAST awareness:** JSONB columns over ~2KB get TOASTed (compressed out-of-line), which adds I/O overhead on retrieval. The `behaviour_rules` JSONB array in `user_profiles` will grow with each new rule. If it exceeds 20–30 rules, consider the trigger-based sync above with a GIN index rather than fetching the full array every time.[^17]

***

## 6. Connection Pooling — PgBouncer/Supavisor Gotchas

Supabase moved from PgBouncer to **Supavisor** in 2023 but the behaviour for edge functions is functionally identical: transaction-mode pooling is the default on port 6543.[^18][^19]

### What breaks in transaction mode

| Feature | Status in transaction mode | Timed impact |
|---------|---------------------------|-------------|
| Regular queries | ✅ Works | Normal |
| `pg_advisory_lock()` (session-scoped) | ❌ Breaks | Don't use in edge functions |
| `pg_advisory_xact_lock()` (tx-scoped) | ✅ Works | Use this instead |
| Prepared statements (named) | ❌ Breaks | Disable in Deno/Node driver |
| `SET statement_timeout` (session) | ❌ Resets between transactions | Use `SET LOCAL` |
| `LISTEN/NOTIFY` | ❌ Breaks | Use Realtime subscriptions instead |
| Temp tables | ❌ Breaks | Use CTEs |
| Explicit transactions | ✅ Works | Use `BEGIN/COMMIT` blocks |

[^20][^21]

### Specific recommendations for Timed's edge functions

```typescript
// ❌ Wrong — advisory_lock is session-scoped, gets orphaned after transaction
await supabase.rpc('pg_advisory_lock', { key: 12345 });

// ✅ Correct — transaction-scoped advisory lock released automatically on COMMIT
await supabase.rpc('pg_advisory_xact_lock', { key: 12345 });
```

```typescript
// ❌ Wrong — prepared statements break with Supavisor transaction mode
const stmt = db.prepare('SELECT * FROM tasks WHERE workspace_id = $1');

// ✅ Correct — disable named prepared statements in deno-postgres
const client = new Client({
  ...connectionConfig,
  // deno-postgres: use raw queries, not .prepare()
});
```

### Multi-query atomicity in edge functions

The `generate-profile-cards` job reads from `behaviour_events`, `estimation_history`, and `behaviour_rules`, then writes to `user_profiles`. This multi-step operation needs atomicity. The `supabase-js` client has no native transaction support (it sits on PostgREST). Two options:[^22]

**Option A (Recommended) — Stored procedure called via `rpc()`:**
```sql
-- Entire profile card generation in one ACID transaction
CREATE OR REPLACE FUNCTION public.regenerate_profile_card(
  p_workspace_id uuid, p_profile_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Aggregate behaviour signals
  -- 2. Call external AI via pg_net (or delegate to caller)
  -- 3. Atomically update user_profiles
  UPDATE public.user_profiles
  SET profile_card_updated_at = now(), ...
  WHERE workspace_id = p_workspace_id AND profile_id = p_profile_id;
END $$;
```

**Option B — Direct DB connection with `deno-postgres` and `SET LOCAL` for RLS:**
```typescript
// As described by Marmelab's pattern
await client.query(`BEGIN`);
await client.query(`SET LOCAL role = authenticated`);
await client.query(`SET LOCAL request.jwt.claims = '{"sub":"${userId}"}'`);
// ... queries now respect RLS
await client.query(`COMMIT`);
```

### Free tier connection limits

Supabase free tier: 60 direct connections, pooler handles bursts up to configured `max_client_conn`. For a solo desktop app, this is non-binding. However, pg_cron jobs run on direct connections and count toward the 60 limit — ensure cron jobs are short-lived to release connections quickly.[^15][^18]

***

## 7. Migration Strategy

### Current state

The entire schema is in one monolithic file: `20260331000001_initial_schema.sql`. This is acceptable at the initial creation stage but should not be the pattern going forward.

### Incremental migration principles for Supabase

Each schema change should be its own timestamped file in `supabase/migrations/`. Supabase CLI applies these in order and tracks which have run. The naming convention is already correct (`YYYYMMDDHHMMSS_description.sql`).[^23][^24]

### Zero-downtime patterns for the desktop app

The Mac app may be running a cached version of the schema model (via TypeScript types generated from `supabase gen types`). The **expand-and-contract** pattern handles this:[^25]

**Phase 1 — Expand (safe to deploy while old app is running):**
- Add new columns with `DEFAULT` values
- Add new tables
- Add new indexes (`CONCURRENTLY`)
- Do **not** remove or rename anything

**Phase 2 — Migrate (deploy new app version):**
- Backfill data in the new column
- Switch app to read/write new structure

**Phase 3 — Contract (deploy after old app version is retired):**
- Drop old columns / constraints
- Remove compatibility code

```sql
-- Example: Adding a new column safely
-- Phase 1 migration (deploy while old app running):
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS priority_v2 text DEFAULT 'medium'
  CHECK (priority_v2 IN ('critical','high','medium','low'));

-- Phase 3 migration (after new app deployed and stable for 1 week):
ALTER TABLE public.tasks DROP COLUMN IF EXISTS priority;
ALTER TABLE public.tasks RENAME COLUMN priority_v2 TO priority;
```

### Recommended migration file split

Break the monolith into logical units for future maintainability:

```
supabase/migrations/
  20260331000001_initial_schema.sql      ← existing (keep as-is)
  20260401000001_hnsw_indexes.sql        ← §2 above (~18 lines)
  20260401000002_rls_perf_fix.sql        ← §3 above (~60 lines)
  20260401000003_missing_rls_policies.sql ← §3 above (~50 lines)
  20260401000004_cron_jobs.sql           ← §4 above (~55 lines)
  20260401000005_behaviour_rules_sync.sql ← §5 above (~20 lines)
  20260401000006_jsonb_gin_indexes.sql   ← §5 above (~8 lines)
  20260401000007_partition_automation.sql ← §1 functions (~30 lines)
```

### Rollback strategy

Supabase does not support automatic rollbacks. Each migration should have a paired `rollback/` SQL file:[^24]

```sql
-- rollback/20260401000001_hnsw_indexes.sql
DROP INDEX CONCURRENTLY IF EXISTS public.email_messages_embedding_hnsw_idx;
DROP INDEX CONCURRENTLY IF EXISTS public.tasks_embedding_hnsw_idx;
CREATE INDEX CONCURRENTLY email_messages_embedding_idx
  ON public.email_messages USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX CONCURRENTLY tasks_embedding_idx
  ON public.tasks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

**Schema version table** — add to the initial schema for the desktop app to detect mismatches:

```sql
-- ~8 lines
CREATE TABLE IF NOT EXISTS public.schema_version (
  version      integer primary key,
  applied_at   timestamptz not null default now(),
  description  text
);
INSERT INTO public.schema_version (version, description)
  VALUES (1, 'initial schema');
-- Desktop app checks: SELECT version FROM schema_version ORDER BY version DESC LIMIT 1
-- If version < minimum_supported, show "please update" dialog before making DB calls
```

***

## Consolidated Impact Ranking

| Migration File | Lines | Impact | Risk |
|----------------|-------|--------|------|
| `_rls_perf_fix.sql` | ~60 | 🔴 10–100× query speedup | Low — policy recreate only |
| `_missing_rls_policies.sql` | ~50 | 🔴 Tables currently return 0 rows | Low |
| `_hnsw_indexes.sql` | ~18 | 🟠 Better recall + continuous-insert support | Low — `CONCURRENTLY` |
| `_cron_jobs.sql` | ~55 | 🟠 Automated maintenance prevents data rot | Low |
| `_behaviour_rules_sync.sql` | ~20 | 🟡 Eliminates dual-write inconsistency | Medium — adds trigger |
| `_jsonb_gin_indexes.sql` | ~8 | 🟡 Batch job query performance | Low |
| `_partition_automation.sql` | ~30 | 🟡 Prevents partition gap (app crash risk) | Low |
| `schema_version` table | ~8 | 🟢 Desktop app safety guard | None |

---

## References

1. [Partitioning in Postgres and the risk of high partition counts](https://pganalyze.com/blog/5mins-postgres-partitioning) - In this article, Hans-Jürgen shows how you can get performance slowdowns by using partitioning. Corr...

2. [Documentation: 18: 5.12. Table Partitioning - PostgreSQL](https://www.postgresql.org/docs/current/ddl-partitioning.html) - When queries or updates access a large percentage of a single partition, performance can be improved...

3. [How to Scale Tables with Time-Based Partitioning in PostgreSQL](https://oneuptime.com/blog/post/2026-01-26-time-based-partitioning-postgresql/view) - Learn how to implement time-based table partitioning in PostgreSQL to handle billions of rows effici...

4. [Optimize generative AI applications with pgvector indexing - AWS](https://aws.amazon.com/blogs/database/optimize-generative-ai-applications-with-pgvector-indexing-a-deep-dive-into-ivfflat-and-hnsw-techniques/) - In this post, we explore the architecture and implementation of both index types (IVFFlat and HNSW) ...

5. [IVFFlat vs HNSW in pgvector: Which Index Should You Use?](https://dev.to/philip_mcclarence_2ef9475/ivfflat-vs-hnsw-in-pgvector-which-index-should-you-use-305p) - The upside: IVFFlat builds are fast and the resulting index is compact. For very large datasets (50M...

6. [IVFFlat vs HNSW in pgvector with text‑embedding‑3‑large. When is it ...](https://www.reddit.com/r/Rag/comments/1pijk7q/ivfflat_vs_hnsw_in_pgvector_with/) - HNSW actually starts paying off once you cross something like 30k to 50k vectors. Below that, both a...

7. [What Is pgvector? PostgreSQL Vector Search Extension Explained](https://www.velodb.io/glossary/what-is-pgvector) - Use IVFFlat when memory is constrained or you need faster index builds; Start without indexes for sm...

8. [pgvector 0.6.0: 30x faster with parallel index builds - Supabase](https://supabase.com/blog/pgvector-fast-builds) - Building an HNSW index is now up to 30x faster for unlogged tables. This release is a huge step forw...

9. [What's new in pgvector v0.7.0 - Supabase](https://supabase.com/blog/pgvector-0-7-0) - An HNSW index is most efficient when it fits into shared memory and avoids being evicted due to conc...

10. [RLS Performance and Best Practices - Supabase](https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv) - 1. The first thing to try is put an index on columns used in the RLS that are not primary keys or un...

11. [Re: Row level security - PostgreSQL](https://www.postgresql.org/message-id/d094a87d-9d63-46c9-8c27-631f881b80fb@supportex.net) - Using direct partitioning and applying RLS policies to each partition should help with performance i...

12. [Edge Function only Invoking when Anon Policy is actvated for table ...](https://github.com/orgs/supabase/discussions/23172) - I'm encountering an issue with the Row Level Security (RLS) policy in Supabase. The policy is set to...

13. [Row Level Security | Supabase Docs](https://supabase.com/docs/guides/database/postgres/row-level-security) - Supabase provides special "Service" keys, which can be used to bypass RLS. These should never be use...

14. [Supabase Security Best Practices - Complete Guide - SupaExplorer](https://supaexplorer.com/guides/supabase-security-best-practices) - Comprehensive guide to securing your Supabase application. Learn RLS best practices, API key managem...

15. [Running vacuum with pg_cron extension #30054 - GitHub](https://github.com/orgs/supabase/discussions/30054) - I need to run maintenance tasks (particularly VACUUM operations) on our database during off-peak hou...

16. [PostgreSQL JSONB GIN Indexes: Why Your Queries Are Slow (And ...](https://dev.to/polliog/postgresql-jsonb-gin-indexes-why-your-queries-are-slow-and-how-to-fix-them-12a0) - You added a JSONB column. You created a GIN index. Your queries are still doing sequential scans. So...

17. [Postgres JSONB Columns and TOAST: A Performance Guide](https://www.snowflake.com/en/engineering-blog/postgres-jsonb-columns-and-toast/) - Understand how Postgres handles variable-length JSONB data using The Oversize Attribute Storage Tech...

18. [Use Connection Pooling for All Applications - Postgres Best Practice](https://supaexplorer.com/best-practices/supabase-postgres/conn-pooling/) - Warning: Supabase free tier allows only 60 direct connections. Without pooling, you'll hit this limi...

19. [PgBouncer is now available in Supabase](https://supabase.com/blog/supabase-pgbouncer) - If Postgres is configured for a maximum of 50 connections before connection pooling, it will still o...

20. [PgBouncer in transaction mode breaks prepared statements ...](https://www.reddit.com/r/sysadmin/comments/1rsoexl/pgbouncer_in_transaction_mode_breaks_prepared/) - PgBouncer in transaction mode breaks prepared statements, advisory locks, and LISTEN/NOTIFY — here's...

21. [Postgres Locking: When is it Concerning? | Crunchy Data Blog](https://www.crunchydata.com/blog/postgres-locking-when-is-it-concerning) - Clients have also run into some questions about advisory locks, particularly when using a transactio...

22. [Transactions and RLS in Supabase Edge Functions - Marmelab](https://marmelab.com/blog/2025/12/08/supabase-edge-function-transaction-rls.html) - Edge functions are a powerful way to run server-side code close to your users. But how to handle tra...

23. [How to Efficiently Manage Supabase Migrations - Chat2DB](https://chat2db.ai/resources/blog/how-to-manage-supabase-migrations) - Advanced Techniques for Managing Migrations · Database Seeding · Zero-Downtime Migrations · Monitori...

24. [Best Practices for Supabase | Security, Scaling & Maintainability](https://www.leanware.co/insights/supabase-best-practices) - Supabase gives you Postgres, authentication, storage, and realtime subscriptions without managing in...

25. [How to handle schema migrations without downtime - Technori](https://technori.com/news/zero-downtime-schema-migrations/) - 1. Design Forward-Compatible Changes · 2. Deploy Application Code That Handles Both Versions · 3. Mi...

