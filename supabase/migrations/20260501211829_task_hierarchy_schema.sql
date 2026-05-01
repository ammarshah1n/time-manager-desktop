set lock_timeout = '5s';

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create or replace function private.user_profile_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_remove(array[
    auth.uid(),
    (select e.id from public.executives e where e.auth_user_id = auth.uid() limit 1)
  ], null)::uuid[]
$$;

create or replace function private.user_workspace_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct wm.workspace_id), '{}'::uuid[])
  from public.workspace_members wm
  where wm.profile_id = any(private.user_profile_ids())
$$;

revoke all on function private.user_profile_ids() from public, anon;
revoke all on function private.user_workspace_ids() from public, anon;
grant execute on function private.user_profile_ids() to authenticated, service_role;
grant execute on function private.user_workspace_ids() to authenticated, service_role;

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'canonical_bucket'
  ) then
    create domain public.canonical_bucket as text;
  end if;
end $$;

alter domain public.canonical_bucket
  drop constraint if exists canonical_bucket_check;
alter domain public.canonical_bucket
  add constraint canonical_bucket_check
  check (value in (
    'action', 'reply_email', 'reply_wa', 'reply_other',
    'read_today', 'read_this_week', 'calls', 'transit',
    'waiting', 'cc_fyi', 'other'
  ));

alter table public.tasks
  drop constraint if exists tasks_bucket_type_check;
alter table public.estimation_history
  drop constraint if exists estimation_history_bucket_type_check;
alter table public.bucket_completion_stats
  drop constraint if exists bucket_completion_stats_bucket_type_check;
alter table public.bucket_estimates
  drop constraint if exists bucket_estimates_bucket_type_check;

alter table public.tasks
  alter column bucket_type type public.canonical_bucket
  using bucket_type::public.canonical_bucket;
alter table public.estimation_history
  alter column bucket_type type public.canonical_bucket
  using bucket_type::public.canonical_bucket;
alter table public.bucket_completion_stats
  alter column bucket_type type public.canonical_bucket
  using bucket_type::public.canonical_bucket;
alter table public.bucket_estimates
  alter column bucket_type type public.canonical_bucket
  using bucket_type::public.canonical_bucket;

create table if not exists public.task_sections (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete set null,
  parent_section_id uuid references public.task_sections(id) on delete set null,
  title text not null check (length(btrim(title)) > 0),
  canonical_bucket_type public.canonical_bucket not null,
  sort_order integer not null default 0,
  color_key text,
  is_system boolean not null default false,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_sections_workspace_idx
  on public.task_sections(workspace_id, profile_id, is_archived, sort_order);
create index if not exists task_sections_parent_idx
  on public.task_sections(parent_section_id)
  where parent_section_id is not null;
create index if not exists task_sections_bucket_idx
  on public.task_sections(workspace_id, canonical_bucket_type)
  where is_archived = false;
create unique index if not exists task_sections_system_unique_idx
  on public.task_sections(
    workspace_id,
    coalesce(parent_section_id, '00000000-0000-0000-0000-000000000000'::uuid),
    title
  )
  where is_system = true;

create or replace function public.enforce_task_section_depth()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  parent_workspace_id uuid;
  parent_parent_id uuid;
begin
  new.updated_at = now();

  if new.parent_section_id is null then
    return new;
  end if;

  if new.parent_section_id = new.id then
    raise exception 'task section cannot parent itself';
  end if;

  select parent.workspace_id, parent.parent_section_id
  into parent_workspace_id, parent_parent_id
  from public.task_sections parent
  where parent.id = new.parent_section_id;

  if parent_workspace_id is null then
    raise exception 'parent task section does not exist';
  end if;

  if parent_workspace_id <> new.workspace_id then
    raise exception 'task section parent must belong to same workspace';
  end if;

  if parent_parent_id is not null then
    raise exception 'task sections support only one subsection level';
  end if;

  if exists (
    select 1
    from public.task_sections child
    where child.parent_section_id = new.id
      and child.id <> new.id
  ) then
    raise exception 'task section with children cannot become a subsection';
  end if;

  return new;
end
$$;

drop trigger if exists trg_enforce_task_section_depth on public.task_sections;
create trigger trg_enforce_task_section_depth
  before insert or update of parent_section_id, workspace_id, title on public.task_sections
  for each row execute function public.enforce_task_section_depth();

alter table public.task_sections enable row level security;
alter table public.task_sections force row level security;

drop policy if exists "task_sections_select_member" on public.task_sections;
create policy "task_sections_select_member"
on public.task_sections
for select
to authenticated
using (workspace_id = any((select private.user_workspace_ids())));

drop policy if exists "task_sections_insert_member" on public.task_sections;
create policy "task_sections_insert_member"
on public.task_sections
for insert
to authenticated
with check (
  is_system = false
  and workspace_id = any((select private.user_workspace_ids()))
  and profile_id = any((select private.user_profile_ids()))
);

drop policy if exists "task_sections_update_member" on public.task_sections;
create policy "task_sections_update_member"
on public.task_sections
for update
to authenticated
using (
  is_system = false
  and workspace_id = any((select private.user_workspace_ids()))
)
with check (
  is_system = false
  and workspace_id = any((select private.user_workspace_ids()))
  and profile_id = any((select private.user_profile_ids()))
);

drop policy if exists "task_sections_delete_member" on public.task_sections;
create policy "task_sections_delete_member"
on public.task_sections
for delete
to authenticated
using (
  is_system = false
  and workspace_id = any((select private.user_workspace_ids()))
);

drop policy if exists "task_sections_service_all" on public.task_sections;
create policy "task_sections_service_all"
on public.task_sections
for all
to service_role
using (true)
with check (true);

with email_sections as (
  insert into public.task_sections (
    workspace_id, profile_id, title, canonical_bucket_type, sort_order, is_system
  )
  select w.id, null, 'Email', 'other'::public.canonical_bucket, 0, true
  from public.workspaces w
  on conflict do nothing
  returning id, workspace_id
),
all_email_sections as (
  select id, workspace_id
  from email_sections
  union
  select id, workspace_id
  from public.task_sections
  where is_system = true
    and title = 'Email'
    and canonical_bucket_type = 'other'::public.canonical_bucket
),
top_level(title, bucket_type, sort_order) as (
  values
    ('Action', 'action'::public.canonical_bucket, 1),
    ('Calls', 'calls'::public.canonical_bucket, 2),
    ('Transit', 'transit'::public.canonical_bucket, 3),
    ('Waiting', 'waiting'::public.canonical_bucket, 4)
),
email_children(title, bucket_type, sort_order) as (
  values
    ('Reply', 'reply_email'::public.canonical_bucket, 0),
    ('Read Today', 'read_today'::public.canonical_bucket, 1),
    ('Read This Week', 'read_this_week'::public.canonical_bucket, 2),
    ('CC / FYI', 'cc_fyi'::public.canonical_bucket, 3)
),
insert_top_level as (
  insert into public.task_sections (
    workspace_id, profile_id, title, canonical_bucket_type, sort_order, is_system
  )
  select w.id, null, t.title, t.bucket_type, t.sort_order, true
  from public.workspaces w
  cross join top_level t
  on conflict do nothing
  returning id
)
insert into public.task_sections (
  workspace_id, profile_id, parent_section_id, title, canonical_bucket_type, sort_order, is_system
)
select e.workspace_id, null, e.id, c.title, c.bucket_type, c.sort_order, true
from all_email_sections e
cross join email_children c
on conflict do nothing;

alter table public.tasks
  add column if not exists section_id uuid,
  add column if not exists parent_task_id uuid,
  add column if not exists sort_order integer not null default 0,
  add column if not exists manual_importance text not null default 'blue',
  add column if not exists notes text,
  add column if not exists is_planning_unit boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_section_id_fkey'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_section_id_fkey
      foreign key (section_id)
      references public.task_sections(id)
      on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_parent_task_id_fkey'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_parent_task_id_fkey
      foreign key (parent_task_id)
      references public.tasks(id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_parent_not_self'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_parent_not_self
      check (parent_task_id is null or parent_task_id <> id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_manual_importance_check'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_manual_importance_check
      check (manual_importance in ('blue', 'orange', 'red'));
  end if;
end $$;

create index if not exists tasks_section_id_idx
  on public.tasks(section_id)
  where section_id is not null;
create index if not exists tasks_parent_task_id_idx
  on public.tasks(parent_task_id)
  where parent_task_id is not null;
create index if not exists tasks_planning_units_idx
  on public.tasks(workspace_id, profile_id, status, is_planning_unit, sort_order)
  where status in ('pending', 'in_progress');

update public.tasks t
set section_id = s.id
from public.task_sections s
where t.section_id is null
  and s.workspace_id = t.workspace_id
  and s.is_system = true
  and s.is_archived = false
  and s.canonical_bucket_type = case
    when t.bucket_type in ('reply_wa'::public.canonical_bucket, 'reply_other'::public.canonical_bucket)
      then 'reply_email'::public.canonical_bucket
    else t.bucket_type
  end;

create or replace function public.enforce_task_hierarchy()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  parent_workspace_id uuid;
  parent_parent_task_id uuid;
  section_workspace_id uuid;
begin
  if new.section_id is not null then
    select s.workspace_id
    into section_workspace_id
    from public.task_sections s
    where s.id = new.section_id;

    if section_workspace_id is null then
      raise exception 'task section does not exist';
    end if;

    if section_workspace_id <> new.workspace_id then
      raise exception 'task section must belong to same workspace as task';
    end if;
  end if;

  if new.parent_task_id is null then
    return new;
  end if;

  if new.parent_task_id = new.id then
    raise exception 'task cannot parent itself';
  end if;

  select parent.workspace_id, parent.parent_task_id
  into parent_workspace_id, parent_parent_task_id
  from public.tasks parent
  where parent.id = new.parent_task_id;

  if parent_workspace_id is null then
    raise exception 'parent task does not exist';
  end if;

  if parent_workspace_id <> new.workspace_id then
    raise exception 'parent task must belong to same workspace';
  end if;

  if parent_parent_task_id is not null then
    raise exception 'subtasks support only one level';
  end if;

  if exists (
    select 1
    from public.tasks child
    where child.parent_task_id = new.id
      and child.id <> new.id
  ) then
    raise exception 'task with subtasks cannot become a subtask';
  end if;

  new.is_planning_unit = true;
  return new;
end
$$;

create or replace function public.sync_task_parent_planning_unit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_parent_id uuid;
  new_parent_id uuid;
begin
  if tg_op = 'DELETE' then
    old_parent_id := old.parent_task_id;
    new_parent_id := null;
  elsif tg_op = 'INSERT' then
    old_parent_id := null;
    new_parent_id := new.parent_task_id;
  else
    old_parent_id := old.parent_task_id;
    new_parent_id := new.parent_task_id;
  end if;

  if new_parent_id is not null and (tg_op <> 'UPDATE' or new.status not in ('done', 'cancelled')) then
    update public.tasks
    set is_planning_unit = false,
        updated_at = now()
    where id = new_parent_id
      and is_planning_unit = true;
  end if;

  if old_parent_id is not null then
    if not exists (
      select 1
      from public.tasks child
      where child.parent_task_id = old_parent_id
        and child.status not in ('done', 'cancelled')
    ) then
      update public.tasks
      set is_planning_unit = true,
          updated_at = now()
      where id = old_parent_id
        and is_planning_unit = false;
    end if;
  end if;

  return null;
end
$$;

create or replace function public.promote_orphaned_subtasks()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.behaviour_events (
    workspace_id,
    profile_id,
    event_type,
    task_id,
    bucket_type,
    hour_of_day,
    day_of_week,
    old_value,
    new_value,
    occurred_at
  )
  select
    child.workspace_id,
    child.profile_id,
    'task_section_changed',
    child.id,
    child.bucket_type::text,
    extract(hour from now())::int,
    extract(dow from now())::int,
    jsonb_build_object('section_id', child.section_id),
    jsonb_build_object('section_id', old.section_id),
    now()
  from public.tasks child
  where child.parent_task_id = old.id
    and child.profile_id is not null
    and child.section_id is null
    and old.section_id is not null;

  update public.tasks child
  set parent_task_id = null,
      section_id = coalesce(child.section_id, old.section_id),
      is_planning_unit = true,
      updated_at = now()
  where child.parent_task_id = old.id;

  return old;
end
$$;

drop trigger if exists trg_enforce_task_hierarchy on public.tasks;
create trigger trg_enforce_task_hierarchy
  before insert or update of parent_task_id, section_id, workspace_id on public.tasks
  for each row execute function public.enforce_task_hierarchy();

drop trigger if exists trg_sync_task_parent_insert_update on public.tasks;
create trigger trg_sync_task_parent_insert_update
  after insert or update of parent_task_id, status on public.tasks
  for each row execute function public.sync_task_parent_planning_unit();

drop trigger if exists trg_sync_task_parent_delete on public.tasks;
create trigger trg_sync_task_parent_delete
  after delete on public.tasks
  for each row execute function public.sync_task_parent_planning_unit();

drop trigger if exists trg_promote_orphaned_subtasks on public.tasks;
create trigger trg_promote_orphaned_subtasks
  before delete on public.tasks
  for each row execute function public.promote_orphaned_subtasks();

alter table public.behaviour_events
  add column if not exists section_id uuid references public.task_sections(id) on delete set null,
  add column if not exists parent_task_id uuid references public.tasks(id) on delete set null,
  add column if not exists event_metadata jsonb;

create index if not exists behaviour_events_section_idx
  on public.behaviour_events(section_id, occurred_at desc)
  where section_id is not null;
create index if not exists behaviour_events_parent_task_idx
  on public.behaviour_events(parent_task_id, occurred_at desc)
  where parent_task_id is not null;

alter table public.behaviour_events
  drop constraint if exists behaviour_events_event_type_check;
alter table public.behaviour_events
  add constraint behaviour_events_event_type_check
  check (event_type in (
    'task_completed',
    'task_deferred',
    'task_deleted',
    'plan_order_override',
    'estimate_override',
    'session_started',
    'triage_correction',
    'task_abandoned',
    'task_unblocked',
    'session_interrupted',
    'recommendation_acted_on',
    'recommendation_dismissed',
    'briefing_section_viewed',
    'briefing_section_interacted',
    'section_created',
    'section_renamed',
    'task_section_changed',
    'subtask_created',
    'subtask_completed',
    'manual_importance_changed'
  ));

create table if not exists public.estimate_priors (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  bucket_type public.canonical_bucket not null,
  section_id uuid not null references public.task_sections(id) on delete cascade,
  prior_minutes integer not null,
  confidence numeric not null default 0 check (confidence between 0 and 1),
  sample_size integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, profile_id, bucket_type, section_id)
);

create index if not exists estimate_priors_section_idx
  on public.estimate_priors(section_id, updated_at desc);

alter table public.estimate_priors enable row level security;
alter table public.estimate_priors force row level security;

drop policy if exists "estimate_priors_select_member" on public.estimate_priors;
create policy "estimate_priors_select_member"
on public.estimate_priors
for select
to authenticated
using (workspace_id = any((select private.user_workspace_ids())));

drop policy if exists "estimate_priors_service_all" on public.estimate_priors;
create policy "estimate_priors_service_all"
on public.estimate_priors
for all
to service_role
using (true)
with check (true);

do $$
declare
  month_start date;
  next_month date;
  partition_name text;
  partition_reg regclass;
begin
  for month_start in
    select generate_series('2026-06-01'::date, '2026-12-01'::date, interval '1 month')::date
  loop
    next_month := (month_start + interval '1 month')::date;
    partition_name := 'behaviour_events_' || to_char(month_start, 'YYYY_MM');

    if to_regclass('public.' || partition_name) is null then
      execute format(
        'create table public.%I partition of public.behaviour_events for values from (%L) to (%L)',
        partition_name,
        month_start,
        next_month
      );
    end if;

    partition_reg := to_regclass('public.' || partition_name);

    execute format('alter table public.%I enable row level security', partition_name);
    execute format('alter table public.%I force row level security', partition_name);

    if to_regprocedure('public.update_rules_on_event()') is not null
       and not exists (
         select 1
         from pg_trigger
         where tgrelid = partition_reg
           and tgname = 'trg_update_rules_on_event'
       ) then
      execute format(
        'create trigger trg_update_rules_on_event after insert on public.%I for each row execute function public.update_rules_on_event()',
        partition_name
      );
    end if;

    if to_regprocedure('public.update_bucket_stats()') is not null
       and not exists (
         select 1
         from pg_trigger
         where tgrelid = partition_reg
           and tgname = 'trg_update_bucket_stats'
       ) then
      execute format(
        'create trigger trg_update_bucket_stats after insert on public.%I for each row execute function public.update_bucket_stats()',
        partition_name
      );
    end if;
  end loop;
end $$;
