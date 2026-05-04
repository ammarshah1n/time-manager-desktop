set lock_timeout = '5s';

create or replace function public.pa_workspace_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(wm.workspace_id), '{}'::uuid[])
  from public.workspace_members wm
  where wm.profile_id = auth.uid()
    and wm.role = 'pa'
$$;

revoke all on function public.pa_workspace_ids() from public, anon;
grant execute on function public.pa_workspace_ids() to authenticated, service_role;

alter table public.tasks
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

update public.tasks
set created_by = profile_id
where created_by is null
  and profile_id is not null;

create or replace function public.tasks_set_created_by()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;

  return new;
end;
$$;

drop trigger if exists tasks_set_created_by_trigger on public.tasks;
create trigger tasks_set_created_by_trigger
  before insert on public.tasks
  for each row
  execute function public.tasks_set_created_by();

do $$
declare
  deny_tables constant text[] := array[
    'email_messages',
    'email_accounts',
    'email_triage_corrections',
    'sender_rules',
    'behaviour_events',
    'behaviour_rules',
    'user_profiles',
    'estimation_history',
    'waiting_items',
    'bucket_completion_stats',
    'bucket_estimates',
    'voice_capture_items',
    'voice_captures',
    'estimate_priors',
    'ai_pipeline_runs'
  ];
  tbl text;
begin
  foreach tbl in array deny_tables loop
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = tbl
        and column_name = 'workspace_id'
    ) then
      execute format('drop policy if exists %I on public.%I', tbl || '_pa_deny', tbl);
      execute format('create policy %I on public.%I as restrictive for select to authenticated using (workspace_id <> all(public.pa_workspace_ids()))', tbl || '_pa_deny', tbl);
    end if;
  end loop;
end;
$$;
