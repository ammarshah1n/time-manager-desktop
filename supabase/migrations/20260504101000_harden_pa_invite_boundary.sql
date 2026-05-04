-- 20260504101000_harden_pa_invite_boundary.sql
-- Tighten PA access to task-editing surfaces and make invite lifecycle RPC-only.

create or replace function public.pa_denied_workspace_tables()
returns text[]
language sql
stable
as $$
  select array[
    'email_messages',
    'email_accounts',
    'email_triage_corrections',
    'sender_rules',
    'sender_social_graph',
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
    'ai_pipeline_runs',
    'daily_plans',
    'plan_items'
  ]::text[];
$$;

grant execute on function public.pa_denied_workspace_tables() to authenticated, service_role;

do $$
declare
  tbl text;
begin
  foreach tbl in array public.pa_denied_workspace_tables() loop
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = tbl
        and column_name = 'workspace_id'
    ) then
      execute format('drop policy if exists %I on public.%I', tbl || '_pa_deny', tbl);
      execute format(
        'create policy %I on public.%I as restrictive for all to authenticated using (workspace_id <> all(public.pa_workspace_ids())) with check (workspace_id <> all(public.pa_workspace_ids()))',
        tbl || '_pa_deny',
        tbl
      );
    end if;
  end loop;
end;
$$;

do $$
declare
  partition_name regclass;
  policy_name text;
begin
  if to_regclass('public.behaviour_events') is null then
    return;
  end if;

  for partition_name in
    select inhrelid::regclass
    from pg_inherits
    where inhparent = 'public.behaviour_events'::regclass
  loop
    policy_name := replace(partition_name::text, 'public.', '') || '_pa_deny';
    execute format('alter table %s enable row level security', partition_name);
    execute format('alter table %s force row level security', partition_name);
    execute format('drop policy if exists %I on %s', policy_name, partition_name);
    execute format(
      'create policy %I on %s as restrictive for all to authenticated using (workspace_id <> all(public.pa_workspace_ids())) with check (workspace_id <> all(public.pa_workspace_ids()))',
      policy_name,
      partition_name
    );
  end loop;
end;
$$;

create or replace function public.trg_insert_estimation_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.workspace_id = any(public.pa_workspace_ids()) then
    return NEW;
  end if;

  if NEW.actual_minutes is not null and (OLD.actual_minutes is null or OLD.actual_minutes is distinct from NEW.actual_minutes) then
    insert into public.estimation_history (
      workspace_id,
      task_id,
      profile_id,
      bucket_type,
      title_tokens,
      from_address,
      estimated_minutes_ai,
      estimated_minutes_manual,
      actual_minutes,
      estimate_error,
      embedding
    )
    values (
      NEW.workspace_id,
      NEW.id,
      NEW.profile_id,
      NEW.bucket_type,
      regexp_split_to_array(lower(coalesce(NEW.title, '')), '[^a-z0-9]+'),
      (select em.from_address from public.email_messages em where em.id = NEW.source_email_id),
      NEW.estimated_minutes_ai,
      NEW.estimated_minutes_manual,
      NEW.actual_minutes,
      case
        when NEW.estimated_minutes_ai is not null and NEW.actual_minutes > 0
        then (NEW.actual_minutes - NEW.estimated_minutes_ai)::real / NEW.actual_minutes::real
        else null
      end,
      NEW.embedding
    )
    on conflict do nothing;
  end if;

  return NEW;
end;
$$;

create or replace function public.get_top_observations(
    p_exec_id uuid,
    p_hours integer default 24,
    p_limit integer default 40
) returns table (
    id uuid,
    occurred_at timestamptz,
    event_type text,
    summary text,
    score float
)
language sql
stable
security definer
set search_path = public
as $$
    select
        obs.id,
        obs.occurred_at,
        obs.event_type,
        obs.summary,
        public.score_memory(obs)::float as score
    from public.tier0_observations obs
    where obs.profile_id = p_exec_id
      and (
        auth.role() = 'service_role'
        or p_exec_id = public.get_executive_id(auth.uid())
      )
      and obs.occurred_at >= now() - (p_hours || ' hours')::interval
    order by public.score_memory(obs) desc
    limit greatest(1, least(p_limit, 200));
$$;

revoke all on function public.get_top_observations(uuid, integer, integer) from public, anon;
grant execute on function public.get_top_observations(uuid, integer, integer) to authenticated, service_role;

drop policy if exists "workspace_invites_update_owner" on public.workspace_invites;

create or replace function public.revoke_workspace_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  update public.workspace_invites wi
    set is_revoked = true
    where wi.id = p_invite_id
      and wi.is_revoked = false
      and wi.consumed_at is null
      and wi.created_by = auth.uid()
      and wi.workspace_id in (
        select wm.workspace_id
        from public.workspace_members wm
        where wm.profile_id = auth.uid()
          and wm.role = 'owner'
      );

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'invite not revocable' using errcode = 'P0006';
  end if;
end;
$$;

revoke all on function public.revoke_workspace_invite(uuid) from public, anon;
grant execute on function public.revoke_workspace_invite(uuid) to authenticated, service_role;

create or replace function public.accept_workspace_invite(p_code uuid)
returns table (
  workspace_id uuid,
  workspace_name text,
  owner_email text,
  role text,
  already_member boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.workspace_invites%rowtype;
  v_now timestamptz := now();
  v_uid uuid := auth.uid();
  v_existing_role text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select *
    into v_invite
    from public.workspace_invites wi
    where wi.code = p_code
    for update;

  if not found then
    raise exception 'invite not found' using errcode = 'P0404';
  end if;

  if v_invite.created_by = v_uid then
    raise exception 'cannot accept own invite' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = v_invite.workspace_id
      and wm.profile_id = v_invite.created_by
      and wm.role = 'owner'
  ) then
    raise exception 'invite owner no longer active' using errcode = 'P0005';
  end if;

  select wm.role
    into v_existing_role
    from public.workspace_members wm
    where wm.workspace_id = v_invite.workspace_id
      and wm.profile_id = v_uid
    for update;

  if v_existing_role is not null and v_existing_role <> 'pa' then
    raise exception 'already member with different role' using errcode = 'P0004';
  end if;

  if v_invite.is_revoked then
    raise exception 'invite revoked' using errcode = 'P0001';
  end if;

  if v_invite.consumed_at is not null then
    if v_invite.consumed_by = v_uid and v_existing_role = 'pa' then
      return query
        select w.id, w.name, p.email, 'pa'::text, true
        from public.workspaces w
        left join public.profiles p on p.id = v_invite.created_by
        where w.id = v_invite.workspace_id;
      return;
    end if;

    raise exception 'invite already used' using errcode = 'P0002';
  end if;

  if v_invite.expires_at <= v_now then
    raise exception 'invite expired' using errcode = 'P0003';
  end if;

  update public.workspace_invites wi
    set consumed_at = v_now, consumed_by = v_uid
    where wi.id = v_invite.id;

  if v_existing_role is null then
    insert into public.workspace_members (workspace_id, profile_id, role)
      values (v_invite.workspace_id, v_uid, 'pa');
  end if;

  return query
    select w.id, w.name, p.email, 'pa'::text, (v_existing_role is not null)
    from public.workspaces w
    left join public.profiles p on p.id = v_invite.created_by
    where w.id = v_invite.workspace_id;
end;
$$;

revoke all on function public.accept_workspace_invite(uuid) from public, anon;
grant execute on function public.accept_workspace_invite(uuid) to authenticated, service_role;
