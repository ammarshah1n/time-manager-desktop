-- 20260504100006_workspace_invites_update_policy_no_recursion.sql
-- The original UPDATE WITH CHECK self-selected from workspace_invites and recursed
-- under RLS. Keep owner-gated revocation/update without referencing the target table.

drop policy if exists "workspace_invites_update_owner" on public.workspace_invites;
create policy "workspace_invites_update_owner" on public.workspace_invites
  for update using (
    workspace_id in (
      select wm.workspace_id from public.workspace_members wm
      where wm.profile_id = auth.uid() and wm.role = 'owner'
    )
  )
  with check (
    created_by = auth.uid()
    and workspace_id in (
      select wm.workspace_id from public.workspace_members wm
      where wm.profile_id = auth.uid() and wm.role = 'owner'
    )
  );
