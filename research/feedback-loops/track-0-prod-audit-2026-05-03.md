# Track 0 Production Audit — 2026-05-03

Supabase project: `fpmjuufefhtlwbfinxlx`

Method: remote Postgres read via Supabase CLI generated login role, then `set role postgres`. The v4 plan's "Pre-flight: Track 0" section contains five numbered SQL queries, despite the wave handoff referring to six.

## Query 1 — Are completion paths firing in prod?

```sql
select count(*) as total_tasks,
       count(*) filter (where actual_minutes is not null) as completed_with_actual,
       count(*) filter (where estimated_minutes_ai is not null) as ai_estimated,
       count(*) filter (where estimate_source = 'manual') as manual_set
from public.tasks;
```

Result:

```json
[
  {
    "total_tasks": "6",
    "completed_with_actual": "0",
    "ai_estimated": "6",
    "manual_set": "0"
  }
]
```

Interpretation: production has six task rows and all six already have `estimated_minutes_ai`, but no task has `actual_minutes`; completion/actual-time learning has not fired yet.

## Query 2 — Is estimation_history populating from the trigger?

```sql
select count(*) as history_rows,
       count(*) filter (where estimated_minutes_ai is not null) as with_ai_estimate,
       count(*) filter (where estimate_error is not null) as with_error
from public.estimation_history;
```

Result:

```json
[
  {
    "history_rows": "0",
    "with_ai_estimate": "0",
    "with_error": "0"
  }
]
```

Interpretation: `estimation_history` is empty in production, so the estimator has no historical/Bayesian learning corpus yet.

## Query 3 — Is override capture working in prod?

```sql
select count(*) as override_count,
       max(occurred_at) as latest_override
from public.behaviour_events
where event_type = 'estimate_override';
```

Result:

```json
[
  {
    "override_count": "0",
    "latest_override": null
  }
]
```

Interpretation: no production estimate override events have been captured, so the briefing calibration loop currently has no override signal to surface.

## Query 4 — Is the avg-error trigger firing?

```sql
select profile_id, avg_estimate_error_pct
from public.user_profiles
where avg_estimate_error_pct is not null;
```

Result:

```json
[]
```

Interpretation: no profile has a computed average estimate error, consistent with no completed actuals and no estimation history rows.

## Query 5 — Schema confirmation: does estimate_uncertainty column exist on tasks?

```sql
select column_name from information_schema.columns
where table_schema='public' and table_name='tasks' and column_name='estimate_uncertainty';
```

Result:

```json
[]
```

Interpretation: `tasks.estimate_uncertainty` is missing remotely. Track B.0's migration is required before estimator activation writes uncertainty successfully.
