-- 20260504100003_workspace_member_pa_self_delete.sql
-- Allow a PA to remove THEIR OWN membership (leave-workspace UI).
-- Owner / member roles cannot self-delete via this policy — only via
-- the existing workspace_members_delete_owner policy from 20260415100000.

create policy "workspace_members_pa_self_delete" on public.workspace_members
  for delete using (
    role = 'pa'
    and profile_id = auth.uid()
  );
