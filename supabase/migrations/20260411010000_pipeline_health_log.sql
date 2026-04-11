create table if not exists public.pipeline_health_log (
  id uuid primary key default gen_random_uuid(),
  checked_at timestamptz not null default now(),
  check_type text not null check (
    check_type in (
      'tier0_count',
      'tier1_gap',
      'acb_age',
      'backfill_status',
      'nightly_pipeline'
    )
  ),
  status text not null default 'ok' check (
    status in (
      'ok',
      'warning',
      'critical'
    )
  ),
  details jsonb,
  created_at timestamptz default now()
);

alter table public.pipeline_health_log enable row level security;

create policy "pipeline_health_log_select_authenticated"
on public.pipeline_health_log
for select
to authenticated
using (true);

create index if not exists pipeline_health_log_checked_at_brin_idx
on public.pipeline_health_log
using brin (checked_at);
