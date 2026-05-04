-- 20260504100002_accept_workspace_invite_rpc.sql
-- Atomic invite acceptance. Locks the invite row with FOR UPDATE so failure-reason
-- classification is race-safe. Self-accept rejected BEFORE the consume update so
-- the owner cannot burn their own invite by mis-clicking.
-- Returns one row with workspace summary + already_member flag.

create or replace function public.accept_workspace_invite(p_code uuid)
returns table (
  workspace_id    uuid,
  workspace_name  text,
  owner_email     text,
  role            text,
  already_member  boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid := auth.uid();
  v_invite       record;
  v_now          timestamptz := now();
  v_inserted_rc  integer;
begin
  if v_uid is null then
    raise exception 'auth required' using errcode = '42501';
  end if;

  -- Lock the invite row so the failure-reason re-classification below
  -- cannot race against a concurrent consume by another session.
  select wi.id, wi.workspace_id, wi.created_by, wi.is_revoked, wi.consumed_at, wi.expires_at
    into v_invite
    from public.workspace_invites wi
    where wi.code = p_code
    for update;

  if not found then
    raise exception 'invite not found' using errcode = 'P0404';
  end if;

  -- Reject self-accept BEFORE consume so owner can't burn their own invite
  if v_invite.created_by = v_uid then
    raise exception 'cannot accept own invite' using errcode = '22023';
  end if;

  if v_invite.is_revoked then
    raise exception 'invite revoked' using errcode = 'P0001';
  end if;

  if v_invite.consumed_at is not null then
    raise exception 'invite already used' using errcode = 'P0002';
  end if;

  if v_invite.expires_at <= v_now then
    raise exception 'invite expired' using errcode = 'P0003';
  end if;

  -- Atomic consume
  update public.workspace_invites
    set consumed_at = v_now, consumed_by = v_uid
    where id = v_invite.id;

  -- Insert membership; on conflict, row_count = 0 means already member
  insert into public.workspace_members (workspace_id, profile_id, role)
    values (v_invite.workspace_id, v_uid, 'pa')
    on conflict (workspace_id, profile_id) do nothing;

  get diagnostics v_inserted_rc = row_count;

  return query
    select w.id, w.name, p.email, 'pa'::text, (v_inserted_rc = 0)
    from public.workspaces w
    left join public.profiles p on p.id = v_invite.created_by
    where w.id = v_invite.workspace_id;
end
$$;

revoke all on function public.accept_workspace_invite(uuid) from public, anon;
grant execute on function public.accept_workspace_invite(uuid) to authenticated, service_role;
