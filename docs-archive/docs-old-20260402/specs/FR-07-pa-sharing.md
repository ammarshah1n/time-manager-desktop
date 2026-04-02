# FR-07: PA Sharing (Karen)

## Summary
Karen (PA) gets full real-time access to everything. Same app, different login.

## Permissions
Karen can do EVERYTHING the executive can:
- View all tasks, emails, schedule blocks
- Create, edit, complete, reclassify tasks
- Mark tasks done on behalf of executive
- Reorder tasks, add notes
- See the daily plan

## Acceptance Criteria
- [ ] Karen has separate Supabase Auth account (role: pa)
- [ ] Karen logs into same macOS app with her credentials
- [ ] Supabase Realtime subscriptions: Karen sees all changes live
- [ ] All mutations carry created_by / updated_by for audit trail
- [ ] Role-based UI hints: "Karen completed this task at 2:15 PM"
- [ ] Invite flow: executive sends invite → Karen gets auth credentials
- [ ] RLS policies: both owner and PA can access same workspace

## Data Model
- `workspace_members`: user_id, workspace_id, role (owner|pa)
- All tables filtered by workspace_id via RLS

## Dependencies
- Supabase Auth + RLS configured
- All other FRs working (Karen sees everything)
