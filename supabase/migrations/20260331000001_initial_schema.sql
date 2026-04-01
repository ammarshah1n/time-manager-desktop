-- ============================================================
-- Timed — Initial Schema
-- Migration: 20260331000001_initial_schema.sql
-- Every business table has: workspace_id, RLS enabled
-- Time: always timestamptz (UTC)
-- ============================================================

-- Required extension
create extension if not exists "uuid-ossp";
create extension if not exists "vector";
create extension if not exists "pg_cron";
create extension if not exists "pgmq" schema pgmq;

-- ============================================================
-- 1. WORKSPACE & USER SCAFFOLDING
-- ============================================================

create table public.workspaces (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  slug         text unique,
  plan         text not null default 'solo', -- solo|team
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index workspaces_slug_idx on public.workspaces(slug);

-- profiles.id == auth.users.id
create table public.profiles (
  id           uuid primary key,
  email        text not null,
  full_name    text,
  avatar_url   text,
  timezone     text not null default 'UTC',
  created_at   timestamptz not null default now()
);

create table public.workspace_members (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  role         text not null default 'member', -- owner|pa|member
  created_at   timestamptz not null default now(),
  unique (workspace_id, profile_id)
);
create index workspace_members_workspace_id_idx on public.workspace_members(workspace_id);
create index workspace_members_profile_id_idx   on public.workspace_members(profile_id);

-- ============================================================
-- 2. RLS HELPER FUNCTIONS
-- ============================================================

create or replace function public.current_profile_id()
returns uuid language sql stable security definer as $$
  select auth.uid()
$$;

create or replace function public.current_workspace_ids()
returns uuid[] language sql stable security definer as $$
  select coalesce(array_agg(workspace_id), '{}'::uuid[])
  from public.workspace_members
  where profile_id = auth.uid()
$$;

-- ============================================================
-- 3. MICROSOFT GRAPH / EMAIL ACCOUNT
-- ============================================================

create table public.email_accounts (
  id                    uuid primary key default gen_random_uuid(),
  workspace_id          uuid not null references public.workspaces(id) on delete cascade,
  profile_id            uuid references public.profiles(id) on delete set null,
  provider              text not null default 'outlook', -- outlook|gmail
  provider_account_id   text not null,  -- Graph userId
  email_address         text not null,
  -- OAuth tokens (encrypted at rest via Supabase Vault in production)
  access_token_enc      text,
  refresh_token_enc     text,
  token_expires_at      timestamptz,
  -- Delta sync state
  delta_link            text,           -- current delta token URL
  delta_link_updated_at timestamptz,
  -- Webhook subscription
  graph_subscription_id text,
  subscription_expires_at timestamptz,
  -- Status
  sync_enabled          boolean not null default true,
  last_sync_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (workspace_id, provider, provider_account_id)
);
create index email_accounts_workspace_idx      on public.email_accounts(workspace_id);
create index email_accounts_subscription_idx   on public.email_accounts(graph_subscription_id)
  where graph_subscription_id is not null;

-- ============================================================
-- 4. EMAIL MESSAGES
-- ============================================================

create table public.email_messages (
  id                  uuid primary key default gen_random_uuid(),
  workspace_id        uuid not null references public.workspaces(id) on delete cascade,
  email_account_id    uuid not null references public.email_accounts(id) on delete cascade,
  -- Graph identifiers
  graph_message_id    text not null,
  graph_thread_id     text,
  -- Envelope
  from_address        text not null,
  from_name           text,
  to_addresses        text[] not null default '{}',
  cc_addresses        text[] not null default '{}',
  subject             text,
  snippet             text,
  body_plain          text,           -- truncated at 2000 chars for classification
  received_at         timestamptz not null,
  -- Classification
  triage_bucket       text not null default 'inbox' check (triage_bucket in ('inbox','later','black_hole','cc_fyi')),
  triage_confidence   real,
  triage_source       text default 'ai' check (triage_source in ('ai','rule','manual')),
  is_question         boolean default false,
  is_quick_reply      boolean default false,   -- estimated <2 min reply
  -- Flags
  is_cc_fyi           boolean not null default false,
  is_archived         boolean not null default false,
  has_task            boolean not null default false,  -- task extracted from this email
  -- Vector embedding for correction retrieval (text-embedding-3-small = 1536 dims)
  embedding           vector(1536),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (email_account_id, graph_message_id)
);
create index email_messages_workspace_received_idx
  on public.email_messages(workspace_id, received_at desc);
create index email_messages_account_received_idx
  on public.email_messages(email_account_id, received_at desc);
create index email_messages_triage_idx
  on public.email_messages(workspace_id, triage_bucket, is_archived, received_at desc);
create index email_messages_embedding_idx
  on public.email_messages using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

-- ============================================================
-- 5. EMAIL TRIAGE CORRECTIONS (drag-to-train signal)
-- ============================================================

create table public.email_triage_corrections (
  id               uuid primary key default gen_random_uuid(),
  workspace_id     uuid not null references public.workspaces(id) on delete cascade,
  email_message_id uuid not null references public.email_messages(id) on delete cascade,
  profile_id       uuid references public.profiles(id) on delete set null,
  old_bucket       text not null,
  new_bucket       text not null,
  from_address     text not null,   -- denormalised for sender rule extraction
  subject_snippet  text,
  created_at       timestamptz not null default now()
);
create index email_triage_corrections_workspace_idx
  on public.email_triage_corrections(workspace_id, created_at desc);
create index email_triage_corrections_from_idx
  on public.email_triage_corrections(workspace_id, from_address);

-- Sender rules extracted from corrections
create table public.sender_rules (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  from_address text not null,
  rule_type    text not null check (rule_type in ('inbox_always','black_hole')),
  created_at   timestamptz not null default now(),
  unique (workspace_id, profile_id, from_address)
);
create index sender_rules_workspace_profile_idx
  on public.sender_rules(workspace_id, profile_id, rule_type);

-- ============================================================
-- 6. TASKS
-- ============================================================

create table public.tasks (
  id                       uuid primary key default gen_random_uuid(),
  workspace_id             uuid not null references public.workspaces(id) on delete cascade,
  profile_id               uuid references public.profiles(id) on delete set null,
  -- Source
  source_type              text not null check (source_type in ('email','whatsapp','voice','manual')),
  source_email_id          uuid references public.email_messages(id) on delete set null,
  source_voice_capture_id  uuid,  -- FK added after voice_captures table
  -- Classification
  bucket_type              text not null check (bucket_type in (
    'action','reply_email','reply_wa','reply_other',
    'read_today','read_this_week','calls','transit','waiting','other'
  )),
  -- Content
  title                    text not null,
  description              text,
  reply_medium             text check (reply_medium in ('email','whatsapp','phone','other')),
  -- Scheduling
  status                   text not null default 'pending' check (status in (
    'pending','in_progress','done','cancelled','deferred'
  )),
  priority                 integer not null default 0,
  due_at                   timestamptz,
  scheduled_for            timestamptz,
  is_overdue               boolean not null default false,  -- materialised by pg_cron
  is_transit_safe          boolean not null default false,
  is_do_first              boolean not null default false,  -- daily update / family
  -- Time estimation
  estimated_minutes_ai     integer,
  estimated_minutes_manual integer,
  actual_minutes           integer,
  estimate_source          text not null default 'ai' check (estimate_source in ('ai','manual','default')),
  estimate_basis           text,   -- "Based on similar task" / "From subject" / "AI default"
  -- Staleness tracking
  deferred_count           integer not null default 0,
  last_deferred_at         timestamptz,
  -- Completion
  completed_at             timestamptz,
  completed_by             uuid references public.profiles(id) on delete set null,
  -- Vector embedding for time estimation similarity
  embedding                vector(1536),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index tasks_workspace_status_idx
  on public.tasks(workspace_id, profile_id, status, due_at);
create index tasks_workspace_bucket_idx
  on public.tasks(workspace_id, profile_id, bucket_type, status);
create index tasks_overdue_idx
  on public.tasks(workspace_id, profile_id, is_overdue)
  where is_overdue = true;
create index tasks_embedding_idx
  on public.tasks using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

-- ============================================================
-- 7. TIME ESTIMATION HISTORY
-- ============================================================

create table public.estimation_history (
  id                    uuid primary key default gen_random_uuid(),
  workspace_id          uuid not null references public.workspaces(id) on delete cascade,
  task_id               uuid not null references public.tasks(id) on delete cascade,
  profile_id            uuid references public.profiles(id) on delete set null,
  bucket_type           text not null,
  title_tokens          text[],               -- tokenised title for structured matching
  from_address          text,                 -- sender, if email-sourced
  estimated_minutes_ai  integer,
  estimated_minutes_manual integer,
  actual_minutes        integer,
  estimate_error        real,                 -- (actual - ai_estimate) / actual
  created_at            timestamptz not null default now()
);
create index estimation_history_workspace_bucket_idx
  on public.estimation_history(workspace_id, profile_id, bucket_type, created_at desc);

-- ============================================================
-- 8. DAILY PLANS (Morning Interview output)
-- ============================================================

create table public.daily_plans (
  id               uuid primary key default gen_random_uuid(),
  workspace_id     uuid not null references public.workspaces(id) on delete cascade,
  profile_id       uuid not null references public.profiles(id) on delete cascade,
  plan_date        date not null,
  available_minutes integer not null,
  total_planned_minutes integer,
  status           text not null default 'draft' check (status in ('draft','confirmed','complete')),
  mood_context     text check (mood_context in ('easy_wins','avoidance','deep_focus',null)),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (workspace_id, profile_id, plan_date)
);
create index daily_plans_workspace_date_idx
  on public.daily_plans(workspace_id, profile_id, plan_date desc);

create table public.plan_items (
  id                uuid primary key default gen_random_uuid(),
  workspace_id      uuid not null references public.workspaces(id) on delete cascade,
  plan_id           uuid not null references public.daily_plans(id) on delete cascade,
  task_id           uuid not null references public.tasks(id) on delete cascade,
  position          integer not null,          -- sort order in plan
  estimated_minutes integer not null,
  buffer_after_minutes integer not null default 5,
  rank_reason       text,                      -- LLM-generated explanation
  is_done           boolean not null default false,
  done_at           timestamptz,
  created_at        timestamptz not null default now()
);
create index plan_items_plan_idx
  on public.plan_items(plan_id, position);

-- ============================================================
-- 9. BEHAVIOUR EVENTS (Loop 3 — pattern learning)
-- ============================================================

create table public.behaviour_events (
  id             uuid not null default gen_random_uuid(),
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  event_type     text not null check (event_type in (
    'task_completed',
    'task_deferred',
    'task_deleted',
    'plan_order_override',     -- user reordered a plan item
    'estimate_override',       -- user changed AI estimate
    'session_started',
    'triage_correction'
  )),
  task_id        uuid references public.tasks(id) on delete set null,
  plan_id        uuid references public.daily_plans(id) on delete set null,
  -- Contextual signals
  bucket_type    text,
  hour_of_day    integer,          -- 0-23, extracted from event time
  day_of_week    integer,          -- 0=Sun, 6=Sat
  -- Event-specific data
  old_value      jsonb,
  new_value      jsonb,
  -- Timing
  occurred_at    timestamptz not null default now(),
  primary key (id, occurred_at)
) partition by range (occurred_at);

-- Create first 3 monthly partitions
create table public.behaviour_events_2026_03
  partition of public.behaviour_events
  for values from ('2026-03-01') to ('2026-04-01');
create table public.behaviour_events_2026_04
  partition of public.behaviour_events
  for values from ('2026-04-01') to ('2026-05-01');
create table public.behaviour_events_2026_05
  partition of public.behaviour_events
  for values from ('2026-05-01') to ('2026-06-01');

create index behaviour_events_workspace_profile_idx
  on public.behaviour_events(workspace_id, profile_id, occurred_at desc);
create index behaviour_events_type_idx
  on public.behaviour_events(profile_id, event_type, occurred_at desc);

-- ============================================================
-- 10. USER PROFILE (accumulated behavioural intelligence)
-- ============================================================

create table public.user_profiles (
  id                uuid primary key default gen_random_uuid(),
  workspace_id      uuid not null references public.workspaces(id) on delete cascade,
  profile_id        uuid not null references public.profiles(id) on delete cascade,
  -- Inferred rules (JSON array of rule objects)
  -- Rule object: { rule_key, rule_type, rule_value_json, confidence, sample_size, last_updated }
  behaviour_rules   jsonb not null default '[]'::jsonb,
  -- Explicit preferences (user-set)
  prefs_json        jsonb not null default '{}'::jsonb,
  -- Profile card: pre-rendered ~700-token summary, regenerated weekly by pg_cron
  profile_card_text text,
  profile_card_updated_at timestamptz,
  -- Calibration: how accurate is the AI vs user?
  avg_estimate_error_pct real,   -- (actual - ai_estimate) / actual, rolling 30 days
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (workspace_id, profile_id)
);

-- Individual rule rows (for queryability + audit)
create table public.behaviour_rules (
  id             uuid primary key default gen_random_uuid(),
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  rule_key       text not null,     -- e.g. 'order.calls_before_email'
  rule_type      text not null,     -- 'ordering' | 'threshold' | 'timing' | 'category_pref'
  rule_value_json jsonb not null,
  confidence     real not null default 0.0,   -- 0.0–1.0
  sample_size    integer not null default 0,
  evidence       text,              -- human-readable explanation for user audit
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (workspace_id, profile_id, rule_key)
);
create index behaviour_rules_profile_active_idx
  on public.behaviour_rules(profile_id, is_active, rule_key);

-- ============================================================
-- 11. WAITING ON OTHERS
-- ============================================================

create table public.waiting_items (
  id                uuid primary key default gen_random_uuid(),
  workspace_id      uuid not null references public.workspaces(id) on delete cascade,
  profile_id        uuid not null references public.profiles(id) on delete cascade,
  -- What was asked
  description       text not null,
  -- Who was asked
  contact_name      text not null,
  contact_email     text,
  contact_wa_number text,
  -- When
  asked_at          timestamptz not null default now(),
  expected_by       timestamptz,
  -- Source
  source_type       text not null check (source_type in ('email','whatsapp','verbal','manual')),
  source_email_thread_id text,   -- Graph conversationId for reply detection
  -- Status
  status            text not null default 'waiting' check (status in (
    'waiting','responded','overdue','cancelled'
  )),
  responded_at      timestamptz,
  response_email_id uuid references public.email_messages(id) on delete set null,
  -- Follow-up
  follow_up_count   integer not null default 0,
  last_follow_up_at timestamptz,
  next_check_at     timestamptz,   -- when to next poll Graph for reply
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index waiting_items_workspace_status_idx
  on public.waiting_items(workspace_id, profile_id, status, expected_by);
create index waiting_items_next_check_idx
  on public.waiting_items(next_check_at)
  where status = 'waiting';

-- ============================================================
-- 12. VOICE CAPTURES
-- ============================================================

create table public.voice_captures (
  id             uuid primary key default gen_random_uuid(),
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  raw_transcript text not null,
  audio_url      text,             -- Supabase Storage path if audio retained
  duration_secs  real,
  status         text not null default 'pending' check (status in (
    'pending','parsed','processed','failed'
  )),
  captured_at    timestamptz not null default now(),
  parsed_at      timestamptz,
  created_at     timestamptz not null default now()
);
create index voice_captures_workspace_status_idx
  on public.voice_captures(workspace_id, profile_id, status, captured_at desc);

-- Parsed items from voice capture
create table public.voice_capture_items (
  id               uuid primary key default gen_random_uuid(),
  workspace_id     uuid not null references public.workspaces(id) on delete cascade,
  voice_capture_id uuid not null references public.voice_captures(id) on delete cascade,
  title            text not null,
  suggested_bucket text,
  estimated_minutes integer,
  due_at           timestamptz,
  extraction_confidence real,
  task_id          uuid references public.tasks(id) on delete set null,  -- set when promoted to task
  created_at       timestamptz not null default now()
);

-- Add FK from tasks → voice_captures (deferred cycle resolution)
alter table public.tasks
  add constraint tasks_source_voice_capture_fk
  foreign key (source_voice_capture_id)
  references public.voice_captures(id)
  on delete set null;

-- ============================================================
-- 13. WEBHOOK EVENTS (idempotency gate for Graph push)
-- ============================================================

create table public.webhook_events (
  id              uuid primary key default gen_random_uuid(),
  graph_event_id  text not null,
  message_id      text not null,
  workspace_id    uuid references public.workspaces(id) on delete cascade,
  received_at     timestamptz not null default now(),
  status          text not null default 'received' check (status in (
    'received','queued','processed','failed'
  )),
  error_message   text,
  processed_at    timestamptz,
  constraint uq_graph_event unique (graph_event_id)
);
create index webhook_events_received_at_idx on public.webhook_events(received_at desc);
create index webhook_events_status_idx      on public.webhook_events(status)
  where status not in ('processed');

-- ============================================================
-- 14. AI PIPELINE RUNS (observability)
-- ============================================================

create table public.ai_pipeline_runs (
  id              uuid primary key default gen_random_uuid(),
  workspace_id    uuid references public.workspaces(id) on delete cascade,
  pipeline_name   text not null,  -- 'classify-email' | 'estimate-time' | 'generate-plan' | 'parse-voice'
  entity_type     text,           -- 'email_message' | 'task' | 'voice_capture' | 'daily_plan'
  entity_id       uuid,
  model           text not null,  -- 'claude-haiku-4-5' | 'claude-sonnet-4-6' | 'claude-opus-4-6'
  input_tokens    integer,
  output_tokens   integer,
  cached_tokens   integer,
  duration_ms     integer,
  status          text not null default 'pending' check (status in (
    'pending','running','success','failed','timeout'
  )),
  error_message   text,
  started_at      timestamptz not null default now(),
  completed_at    timestamptz
);
create index ai_pipeline_runs_workspace_pipeline_idx
  on public.ai_pipeline_runs(workspace_id, pipeline_name, started_at desc);
create index ai_pipeline_runs_entity_idx
  on public.ai_pipeline_runs(entity_type, entity_id)
  where entity_id is not null;

-- ============================================================
-- 15. RLS — Enable on all business tables
-- ============================================================

do $$ declare
  tbl text;
begin
  foreach tbl in array array[
    'email_accounts','email_messages','email_triage_corrections','sender_rules',
    'tasks','estimation_history','daily_plans','plan_items',
    'behaviour_events_2026_03','behaviour_events_2026_04','behaviour_events_2026_05',
    'user_profiles','behaviour_rules','waiting_items',
    'voice_captures','voice_capture_items','ai_pipeline_runs'
  ] loop
    execute format('alter table public.%I enable row level security', tbl);
  end loop;
end $$;

-- Standard workspace-isolation policy template
-- (Apply individually per table; using helper for brevity — expand in production)
create policy "tasks_workspace_isolation"
  on public.tasks for all to authenticated
  using  (workspace_id = any(public.current_workspace_ids()))
  with check (workspace_id = any(public.current_workspace_ids()));

create policy "email_messages_workspace_isolation"
  on public.email_messages for all to authenticated
  using  (workspace_id = any(public.current_workspace_ids()))
  with check (workspace_id = any(public.current_workspace_ids()));

create policy "daily_plans_workspace_isolation"
  on public.daily_plans for all to authenticated
  using  (workspace_id = any(public.current_workspace_ids()))
  with check (workspace_id = any(public.current_workspace_ids()));

create policy "waiting_items_workspace_isolation"
  on public.waiting_items for all to authenticated
  using  (workspace_id = any(public.current_workspace_ids()))
  with check (workspace_id = any(public.current_workspace_ids()));

create policy "voice_captures_workspace_isolation"
  on public.voice_captures for all to authenticated
  using  (workspace_id = any(public.current_workspace_ids()))
  with check (workspace_id = any(public.current_workspace_ids()));

create policy "user_profiles_workspace_isolation"
  on public.user_profiles for all to authenticated
  using  (workspace_id = any(public.current_workspace_ids()))
  with check (workspace_id = any(public.current_workspace_ids()));

create policy "behaviour_rules_workspace_isolation"
  on public.behaviour_rules for all to authenticated
  using  (workspace_id = any(public.current_workspace_ids()))
  with check (workspace_id = any(public.current_workspace_ids()));

-- ============================================================
-- 16. SUPABASE REALTIME — Enable on live-update tables
-- ============================================================
-- Tables that the Mac app subscribes to via postgres_changes:
--   tasks          — new tasks, status changes, estimate updates
--   email_messages — new triage results
--   plan_items     — plan confirmation, item completion
--   waiting_items  — response detection, follow-up triggers
--   voice_capture_items — parse completion notification

alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.email_messages;
alter publication supabase_realtime add table public.plan_items;
alter publication supabase_realtime add table public.waiting_items;
alter publication supabase_realtime add table public.voice_capture_items;

-- ============================================================
-- 17. PGVECTOR — ivfflat index tuning note
-- ============================================================
-- Indexes created above with lists=100 (suitable for <1M rows per workspace).
-- Rebuild indexes after bulk inserts: REINDEX INDEX CONCURRENTLY <idx>;
-- For production scale (>1M rows): switch to hnsw (m=16, ef_construction=64).
--
-- Embedding dimensions: 1536 (text-embedding-3-small).
-- Tables with embeddings:
--   email_messages.embedding — for correction retrieval (few-shot similarity)
--   tasks.embedding          — for estimation similarity (similar past tasks)
--
-- To generate embeddings (Deno Edge Function):
--   const { data } = await openai.embeddings.create({
--     model: 'text-embedding-3-small', input: text
--   });
--   const embedding = data[0].embedding; // float32[1536]

-- ============================================================
-- 18. PG_CRON JOBS
-- ============================================================
-- Schedule after Supabase project is live and pg_cron is enabled:
--
-- Renew Graph webhooks before 3-day expiry (every 2 days at 00:00 UTC):
-- select cron.schedule('renew-graph-subscriptions', '0 0 */2 * *',
--   $$select net.http_post(url := '<SUPABASE_URL>/functions/v1/renew-graph-subscriptions',
--     headers := '{"Authorization":"Bearer <SERVICE_ROLE_KEY>"}')$$);
--
-- Update is_overdue flags (every 15 min):
-- select cron.schedule('update-overdue-tasks', '*/15 * * * *',
--   $$update public.tasks set is_overdue = (due_at < now())
--     where status = 'pending' and due_at is not null$$);
--
-- Weekly profile card regeneration (Sunday 02:00 UTC):
-- select cron.schedule('regenerate-profile-cards', '0 2 * * 0',
--   $$select net.http_post(url := '<SUPABASE_URL>/functions/v1/generate-profile-cards',
--     headers := '{"Authorization":"Bearer <SERVICE_ROLE_KEY>"}')$$);
--
-- Monthly partition creation (1st of each month at 01:00 UTC):
-- select cron.schedule('create-behaviour-partitions', '0 1 1 * *',
--   $$do $$ declare ...  -- add next 2 months of partitions $$);
