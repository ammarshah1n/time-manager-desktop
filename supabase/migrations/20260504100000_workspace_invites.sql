-- 20260504100000_workspace_invites.sql
-- Stores PA invite codes. Owner inserts (created_by defaults to auth.uid()),
-- service-role / authenticated user consumes via accept_workspace_invite RPC.

create table public.workspace_invites (
  id              uuid primary key default gen_random_uuid(),
  workspace_id    uuid not null references public.workspaces(id) on delete cascade,
  code            uuid not null unique default gen_random_uuid(),
  created_by      uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default (now() + interval '14 days'),
  is_revoked      boolean not null default false,
  consumed_at     timestamptz,
  consumed_by     uuid references public.profiles(id) on delete set null
);

create index workspace_invites_workspace_id_idx
  on public.workspace_invites(workspace_id);
create index workspace_invites_code_active_idx
  on public.workspace_invites(code)
  where consumed_at is null and is_revoked = false;

alter table public.workspace_invites enable row level security;

-- Owner of the workspace can SELECT their own invites
create policy "workspace_invites_select_owner" on public.workspace_invites
  for select using (
    workspace_id in (
      select wm.workspace_id from public.workspace_members wm
      where wm.profile_id = auth.uid() and wm.role = 'owner'
    )
    or auth.role() = 'service_role'
  );

-- Owner of the workspace can INSERT new invite codes
create policy "workspace_invites_insert_owner" on public.workspace_invites
  for insert with check (
    created_by = auth.uid()
    and workspace_id in (
      select wm.workspace_id from public.workspace_members wm
      where wm.profile_id = auth.uid() and wm.role = 'owner'
    )
  );

-- Owner can UPDATE only is_revoked / expires_at fields. WITH CHECK enforces
-- workspace_id and created_by are immutable from the client side.
create policy "workspace_invites_update_owner" on public.workspace_invites
  for update using (
    workspace_id in (
      select wm.workspace_id from public.workspace_members wm
      where wm.profile_id = auth.uid() and wm.role = 'owner'
    )
  )
  with check (
    workspace_id in (
      select wm.workspace_id from public.workspace_members wm
      where wm.profile_id = auth.uid() and wm.role = 'owner'
    )
    and created_by = (select created_by from public.workspace_invites wi where wi.id = workspace_invites.id)
  );

-- Service role (and the security-definer RPC) handles consume + delete
create policy "workspace_invites_all_service" on public.workspace_invites
  for all using (auth.role() = 'service_role');
