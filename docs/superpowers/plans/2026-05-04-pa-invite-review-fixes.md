# PA Invite Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the PA invite review findings so PA access is limited to shared task editing, workspace switching cannot leak stale task state, invite lifecycle semantics are deterministic, and the public invite page does not overpromise.

**Architecture:** Use an additive Supabase migration to harden PA RLS and replace broad invite UPDATE access with narrow RPCs. Keep Swift changes inside the existing `AuthService`, `TimedRootView`, `SharingPane`, `SharingService`, and `SupabaseClientDependency` boundaries. Use source-level guard tests where the project already uses static migration/UI tests, plus targeted Swift and Deno checks.

**Tech Stack:** Swift 6.1, SwiftUI, Swift Testing, Supabase Postgres RLS/RPC, Supabase Edge Functions, Deno, React/TypeScript in `/Users/integrale/facilitated`.

---

## Product Decision Baked Into This Plan

After a PA leaves a workspace, the old consumed invite remains used. Reopening that link must return "invite already used" and must not silently re-add membership. The owner must generate a new invite for re-entry.

## File Map

- Create: `/Users/integrale/time-manager-desktop/supabase/migrations/20260504101000_harden_pa_invite_boundary.sql`
- Modify: `/Users/integrale/time-manager-desktop/Tests/Sharing/PARoleRLSGuardTests.swift`
- Modify: `/Users/integrale/time-manager-desktop/supabase/functions/accept-invite/index.ts`
- Modify: `/Users/integrale/time-manager-desktop/supabase/functions/accept-invite/test.ts`
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/AppEntry/TimedAppShell.swift`
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/Features/TimedRootView.swift`
- Modify: `/Users/integrale/time-manager-desktop/Tests/Sharing/DataBridgeWorkspaceSwitchTests.swift`
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/Features/Sharing/SharingPane.swift`
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/Core/Clients/SupabaseClient.swift`
- Modify: `/Users/integrale/time-manager-desktop/Tests/Sharing/SharingServiceAcceptTests.swift`
- Modify: `/Users/integrale/facilitated/components/InviteAcceptPage.tsx`
- Modify: `/Users/integrale/time-manager-desktop/BUILD_STATE.md`

---

### Task 1: Add Failing RLS Guard Coverage

**Files:**
- Modify: `/Users/integrale/time-manager-desktop/Tests/Sharing/PARoleRLSGuardTests.swift`

- [ ] **Step 1: Replace the test body with a guard for the hardening migration**

Use this full file content:

```swift
import Testing
import Foundation
@testable import TimedKit

@Suite("PA role RLS boundary")
struct PARoleRLSGuardTests {
    static let hardeningMigration = "supabase/migrations/20260504101000_harden_pa_invite_boundary.sql"

    static let deniedWorkspaceTables = [
        "email_messages",
        "email_accounts",
        "email_triage_corrections",
        "sender_rules",
        "sender_social_graph",
        "behaviour_events",
        "behaviour_rules",
        "user_profiles",
        "estimation_history",
        "waiting_items",
        "bucket_completion_stats",
        "bucket_estimates",
        "voice_capture_items",
        "voice_captures",
        "estimate_priors",
        "ai_pipeline_runs",
        "daily_plans",
        "plan_items"
    ]

    @Test("PA hardening migration declares every denied workspace table")
    func everyDeniedWorkspaceTableIsDeclared() throws {
        let sql = try source(Self.hardeningMigration)
        for table in Self.deniedWorkspaceTables {
            #expect(sql.contains("'\(table)'"), "PA deny boundary missing table: \(table)")
        }
    }

    @Test("PA hardening migration blocks reads and writes")
    func hardeningPolicyBlocksAllCommands() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("as restrictive for all"),
                "PA policy must be FOR ALL so direct API writes cannot bypass the privacy boundary")
        #expect(sql.contains("with check"),
                "PA policy must include WITH CHECK so INSERT and UPDATE are denied")
    }

    @Test("Invite revocation is narrowed to an RPC")
    func inviteRevocationUsesRPC() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("drop policy if exists \"workspace_invites_update_owner\""),
                "Broad workspace_invites UPDATE policy must be removed")
        #expect(sql.contains("create or replace function public.revoke_workspace_invite"),
                "Revocation must go through a narrow RPC")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
swift test --filter PARoleRLSGuardTests
```

Expected: fail because `20260504101000_harden_pa_invite_boundary.sql` does not exist yet.

- [ ] **Step 3: Commit the failing guard**

```bash
git add Tests/Sharing/PARoleRLSGuardTests.swift
git commit -m "test(timed): guard PA workspace boundary hardening"
```

---

### Task 2: Harden PA RLS and Invite RPC Semantics

**Files:**
- Create: `/Users/integrale/time-manager-desktop/supabase/migrations/20260504101000_harden_pa_invite_boundary.sql`
- Modify: `/Users/integrale/time-manager-desktop/supabase/functions/accept-invite/index.ts`
- Modify: `/Users/integrale/time-manager-desktop/supabase/functions/accept-invite/test.ts`
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/Core/Clients/SupabaseClient.swift`

- [ ] **Step 1: Create the additive migration**

Create `/Users/integrale/time-manager-desktop/supabase/migrations/20260504101000_harden_pa_invite_boundary.sql` with this content:

```sql
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
```

- [ ] **Step 2: Update the Edge Function error mapping**

In `/Users/integrale/time-manager-desktop/supabase/functions/accept-invite/index.ts`, update `ERRCODE_TO_MSG` to include the new deterministic RPC errors:

```ts
export const ERRCODE_TO_MSG: Record<string, { msg: string; status: number }> = {
  P0001: { msg: "This invite was revoked.", status: 410 },
  P0002: { msg: "This invite has already been used.", status: 410 },
  P0003: { msg: "This invite has expired.", status: 410 },
  P0004: { msg: "You are already a member of this workspace with a different role.", status: 409 },
  P0005: { msg: "This invite is no longer valid.", status: 410 },
  P0404: { msg: "Invite not found.", status: 404 },
  "22023": { msg: "You can't accept your own invite.", status: 400 },
  "42501": { msg: "Sign in first.", status: 401 },
};
```

- [ ] **Step 3: Add Deno coverage for the new error codes**

Append this test to `/Users/integrale/time-manager-desktop/supabase/functions/accept-invite/test.ts`:

```ts
Deno.test("invite RPC error map covers role and stale-owner cases", async () => {
  seedRequiredEnv();
  const mod = await import("./index.ts");

  assertEquals(mod.ERRCODE_TO_MSG.P0004.status, 409);
  assertEquals(mod.ERRCODE_TO_MSG.P0005.status, 410);
  assertEquals(mod.ERRCODE_TO_MSG.P0004.msg.includes("different role"), true);
  assertEquals(mod.ERRCODE_TO_MSG.P0005.msg.includes("no longer valid"), true);
});
```

- [ ] **Step 4: Route revoke through the new RPC**

In `/Users/integrale/time-manager-desktop/Sources/TimedKit/Core/Clients/SupabaseClient.swift`, replace the body of `revokeWorkspaceInvite` with:

```swift
            revokeWorkspaceInvite: { inviteId in
                try await client
                    .rpc("revoke_workspace_invite", params: ["p_invite_id": inviteId.uuidString])
                    .execute()
            },
```

- [ ] **Step 5: Run focused checks**

Run:

```bash
swift test --filter PARoleRLSGuardTests
deno test --allow-env supabase/functions/accept-invite/test.ts
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260504101000_harden_pa_invite_boundary.sql Tests/Sharing/PARoleRLSGuardTests.swift supabase/functions/accept-invite/index.ts supabase/functions/accept-invite/test.ts Sources/TimedKit/Core/Clients/SupabaseClient.swift
git commit -m "fix(timed): harden PA invite RLS boundary"
```

---

### Task 3: Fix Workspace Switch Reload and Stale Task State

**Files:**
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/AppEntry/TimedAppShell.swift`
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/Features/TimedRootView.swift`
- Modify: `/Users/integrale/time-manager-desktop/Tests/Sharing/DataBridgeWorkspaceSwitchTests.swift`

- [ ] **Step 1: Add source guards for root workspace switching**

Append these tests to `DataBridgeWorkspaceSwitchTests` before `restoreActiveExecutive`:

```swift
    @Test("TimedRootView observes active workspace changes")
    func rootObservesActiveWorkspaceChanges() throws {
        let content = try source("Sources/TimedKit/Features/TimedRootView.swift")
        #expect(content.contains(".onChange(of: auth.activeWorkspaceId)"),
                "TimedRootView must reload task state when the active workspace changes")
        #expect(content.contains("resetWorkspaceScopedState()"),
                "Workspace switch must clear in-memory task state before refetch")
    }

    @Test("TimedRootView assigns empty Supabase task results")
    func rootAssignsEmptyTaskFetches() throws {
        let content = try source("Sources/TimedKit/Features/TimedRootView.swift")
        #expect(!content.contains("if !dbTasks.isEmpty { tasks = dbTasks.map"),
                "Empty remote task results must replace stale in-memory tasks")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
swift test --filter DataBridgeWorkspaceSwitchTests
```

Expected: fail because `TimedRootView` does not yet observe `auth.activeWorkspaceId` and still keeps stale empty fetches.

- [ ] **Step 3: Reload workspaces after invite accept**

In `/Users/integrale/time-manager-desktop/Sources/TimedKit/AppEntry/TimedAppShell.swift`, replace the accept callback with:

```swift
                    onAccepted: { response in
                        auth.clearPendingInviteCode()
                        Task {
                            await auth.reloadAvailableWorkspaces()
                            await auth.switchWorkspace(to: response.workspaceId)
                        }
                    },
```

- [ ] **Step 4: Add active workspace change handling in `TimedRootView`**

In `/Users/integrale/time-manager-desktop/Sources/TimedKit/Features/TimedRootView.swift`, add this modifier after the existing `auth.isSignedIn` `.onChange` block:

```swift
        .onChange(of: auth.activeWorkspaceId) { _, _ in
            resetWorkspaceScopedState()
            Task { await fetchFromSupabaseIfConnected() }
        }
```

Add this helper near `loadData()`:

```swift
    private func resetWorkspaceScopedState() {
        tasks = []
        taskSections = []
        focusTask = nil
        syncMenuBar()
    }
```

- [ ] **Step 5: Replace stale-preserving task fetch logic**

In `fetchFromSupabaseIfConnected()`, replace the task fetch block with:

```swift
            if let taskWorkspaceId = auth.activeOrPrimaryWorkspaceId {
                let dbTasks = try await supa.fetchTasks(taskWorkspaceId, profileId, ["pending", "in_progress"])
                tasks = dbTasks.map(TimedTask.init(from:))
            }
```

Replace the section load block with:

```swift
            taskSections = (try? await DataBridge.shared.loadTaskSections()) ?? []
```

- [ ] **Step 6: Run focused checks**

Run:

```bash
swift test --filter DataBridgeWorkspaceSwitchTests
swift test --filter SharingService.acceptInvite
```

Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/TimedKit/AppEntry/TimedAppShell.swift Sources/TimedKit/Features/TimedRootView.swift Tests/Sharing/DataBridgeWorkspaceSwitchTests.swift
git commit -m "fix(timed): reload state on workspace switch"
```

---

### Task 4: Gate Sharing UI Controls by Active Workspace Role

**Files:**
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/Features/Sharing/SharingPane.swift`
- Modify: `/Users/integrale/time-manager-desktop/Tests/Sharing/SharingServiceAcceptTests.swift`

- [ ] **Step 1: Add source guards for owner-only controls**

Append this suite to `/Users/integrale/time-manager-desktop/Tests/Sharing/SharingServiceAcceptTests.swift`:

```swift
@Suite("SharingPane role guards")
struct SharingPaneRoleGuardTests {
    @Test("member removal is owner gated")
    func memberRemovalIsOwnerGated() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/SharingPane.swift")
        #expect(content.contains("isActiveWorkspaceOwner"),
                "SharingPane must derive the active workspace role")
        #expect(content.contains("if isActiveWorkspaceOwner && member.role != \"owner\""),
                "Remove button must be owner-only")
    }

    @Test("sharing pane reloads when active workspace changes")
    func reloadsOnWorkspaceChange() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/SharingPane.swift")
        #expect(content.contains(".onChange(of: auth.activeWorkspaceId)"),
                "SharingPane must reload members and invites after workspace switch")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}
```

- [ ] **Step 2: Run the guard and confirm it fails**

Run:

```bash
swift test --filter SharingPaneRoleGuardTests
```

Expected: fail until `SharingPane` is role-gated.

- [ ] **Step 3: Add active role helpers**

In `/Users/integrale/time-manager-desktop/Sources/TimedKit/Features/Sharing/SharingPane.swift`, add these computed properties near `isConnected`:

```swift
    private var activeWorkspaceRole: String? {
        guard let id = auth.activeOrPrimaryWorkspaceId else { return nil }
        return auth.availableWorkspaces.first(where: { $0.id == id })?.role
    }

    private var isActiveWorkspaceOwner: Bool {
        activeWorkspaceRole == "owner"
    }
```

- [ ] **Step 4: Gate owner-only sections and reload on switch**

Replace the connected body section with:

```swift
            } else {
                statusIndicator
                if isActiveWorkspaceOwner {
                    inviteSection
                    activeInvitesSection
                }
                membersSection
                leaveWorkspaceSection
            }
```

Add this modifier after the existing `.task` block:

```swift
        .onChange(of: auth.activeWorkspaceId) { _, _ in
            Task {
                await loadMembers()
                await loadInvites()
            }
        }
```

- [ ] **Step 5: Gate remove and invite generation**

Replace the remove button condition with:

```swift
            if isActiveWorkspaceOwner && member.role != "owner" {
```

At the start of `generateAndShare()`, after the workspace guard, add:

```swift
        guard isActiveWorkspaceOwner else {
            errorMessage = "Only the workspace owner can create invite links."
            return
        }
```

At the start of `loadInvites()`, after the workspace guard, add:

```swift
        guard isActiveWorkspaceOwner else {
            activeInvites = []
            return
        }
```

- [ ] **Step 6: Run focused checks**

Run:

```bash
swift test --filter SharingPaneRoleGuardTests
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/TimedKit/Features/Sharing/SharingPane.swift Tests/Sharing/SharingServiceAcceptTests.swift
git commit -m "fix(timed): gate sharing controls by owner role"
```

---

### Task 5: Decode Workspace Member Profiles Correctly

**Files:**
- Modify: `/Users/integrale/time-manager-desktop/Sources/TimedKit/Core/Clients/SupabaseClient.swift`
- Modify: `/Users/integrale/time-manager-desktop/Tests/Sharing/SharingServiceAcceptTests.swift`

- [ ] **Step 1: Add a decoding test**

Append this suite to `/Users/integrale/time-manager-desktop/Tests/Sharing/SharingServiceAcceptTests.swift`:

```swift
@Suite("WorkspaceMemberRow decoding")
struct WorkspaceMemberRowDecodingTests {
    @Test("decodes nested profiles join")
    func decodesNestedProfilesJoin() throws {
        let json = """
        [{
          "id": "11111111-1111-4111-8111-111111111111",
          "workspace_id": "22222222-2222-4222-8222-222222222222",
          "profile_id": "33333333-3333-4333-8333-333333333333",
          "role": "pa",
          "profiles": {
            "email": "pa@example.com",
            "full_name": "Karen PA"
          }
        }]
        """.data(using: .utf8)!

        let rows = try JSONDecoder().decode([WorkspaceMemberRow].self, from: json)

        #expect(rows.first?.email == "pa@example.com")
        #expect(rows.first?.fullName == "Karen PA")
    }
}
```

- [ ] **Step 2: Run the decoding test and confirm it fails**

Run:

```bash
swift test --filter WorkspaceMemberRowDecodingTests
```

Expected: fail because `WorkspaceMemberRow` ignores nested `profiles`.

- [ ] **Step 3: Replace `WorkspaceMemberRow` with a nested profile shape**

In `/Users/integrale/time-manager-desktop/Sources/TimedKit/Core/Clients/SupabaseClient.swift`, replace `WorkspaceMemberRow` with:

```swift
struct WorkspaceMemberRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let role: String
    let profiles: ProfileJoin?

    var email: String? { profiles?.email }
    var fullName: String? { profiles?.fullName }

    struct ProfileJoin: Codable, Sendable {
        let email: String?
        let fullName: String?

        enum CodingKeys: String, CodingKey {
            case email
            case fullName = "full_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case role
        case profiles
    }
}
```

- [ ] **Step 4: Run focused checks**

Run:

```bash
swift test --filter WorkspaceMemberRowDecodingTests
swift test --filter SharingService.acceptInvite
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TimedKit/Core/Clients/SupabaseClient.swift Tests/Sharing/SharingServiceAcceptTests.swift
git commit -m "fix(timed): decode workspace member profiles"
```

---

### Task 6: Correct Facilitated Invite Page Copy

**Files:**
- Modify: `/Users/integrale/facilitated/components/InviteAcceptPage.tsx`

- [ ] **Step 1: Update capability and privacy copy**

In `/Users/integrale/facilitated/components/InviteAcceptPage.tsx`, replace lines 169-176 text blocks with:

```tsx
              This invite lets your PA create, edit, reschedule, and complete shared tasks in Timed.
```

and:

```tsx
              Your PA gets access to the shared task-editing surface only. Timed keeps email and intelligence data outside the PA workspace boundary.
```

- [ ] **Step 2: Verify the copy no longer references comments**

Run:

```bash
rg -n "comment|private notes|passwords" /Users/integrale/facilitated/components/InviteAcceptPage.tsx
```

Expected: no matches.

- [ ] **Step 3: Run the Facilitated project check**

Run in `/Users/integrale/facilitated`:

```bash
npm run build
```

Expected: build exits 0.

- [ ] **Step 4: Commit in the Facilitated repo**

```bash
cd /Users/integrale/facilitated
git add components/InviteAcceptPage.tsx
git commit -m "fix: align Timed invite copy with shipped scope"
```

---

### Task 7: Full Verification and State Update

**Files:**
- Modify: `/Users/integrale/time-manager-desktop/BUILD_STATE.md`

- [ ] **Step 1: Run full Timed verification**

Run in `/Users/integrale/time-manager-desktop`:

```bash
swift build
swift test
deno check supabase/functions/accept-invite/index.ts
deno test --allow-env supabase/functions/accept-invite/test.ts
```

Expected: all exit 0.

- [ ] **Step 2: Apply and smoke-test Supabase migration**

Run:

```bash
npx supabase migration up --linked
```

Expected: migration `20260504101000_harden_pa_invite_boundary.sql` applies cleanly.

Remote smoke cases to run with two real test profiles:

```text
1. Owner creates invite.
2. PA accepts invite and can SELECT/INSERT/UPDATE tasks and task_sections in owner workspace.
3. PA SELECT/INSERT/UPDATE/DELETE fails for daily_plans, plan_items, sender_social_graph, email_messages, behaviour_events.
4. PA leaves workspace.
5. PA reopens the same invite and receives the mapped "already used" error.
6. Owner revokes a fresh pending invite through revoke_workspace_invite.
7. Direct update of workspace_invites as owner fails without the RPC.
```

- [ ] **Step 3: Update Graphify**

Run:

```bash
graphify update .
```

Expected: exits 0.

- [ ] **Step 4: Update `BUILD_STATE.md`**

Add one dated entry recording:

```markdown
> **Verified 2026-05-04 PA invite review fixes** — `swift build` PASS; `swift test` PASS; `deno check supabase/functions/accept-invite/index.ts` PASS; `deno test --allow-env supabase/functions/accept-invite/test.ts` PASS; Supabase migration `20260504101000_harden_pa_invite_boundary.sql` applied; PA RLS smoke confirmed tasks/task_sections allowed and cognitive tables denied; same consumed invite after leave returns used; invite revocation uses RPC only; Facilitated invite copy no longer mentions comments.
```

- [ ] **Step 5: Commit final Timed state**

```bash
git add BUILD_STATE.md
git commit -m "docs(timed): record PA invite review verification"
```

---

## Self-Review

- Finding 1 covered by Task 1 and Task 2 denied table list.
- Finding 2 covered by Task 2 `AS RESTRICTIVE FOR ALL` with `WITH CHECK`.
- Finding 3 covered by Task 3 active workspace observer and empty fetch assignment.
- Finding 4 covered by Task 3 invite accept workspace reload.
- Finding 5 covered by Task 2 consumed invite membership check.
- Finding 6 covered by Task 4 owner-only sharing controls.
- Finding 7 covered by Task 2 dropping broad update policy and adding `revoke_workspace_invite`.
- Finding 8 covered by Task 5 nested profile decode.
- Finding 9 covered by Task 6 Facilitated copy update.
- No new external Swift dependencies.
- All Supabase access remains routed through `SupabaseClient.swift` or Edge Functions.
- Commits are split by change area.
