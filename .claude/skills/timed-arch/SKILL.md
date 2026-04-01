---
name: timeblock-arch
description: Timed system architecture and feature addition patterns
trigger: When designing new features, adding files, or making architecture decisions
---

# Timed Architecture

## Three Systems

```
┌──────────────────────────────┐
│  1. EMAIL ENGINE (Supabase)  │
│  Edge Functions + pg_cron    │
│  - graph-webhook             │
│  - process-email-pipeline    │
│  - classify-email            │
│  - extract-tasks             │
│  - estimate-time             │
│  - generate-daily-plan       │
│  - refresh-graph-subscription│
└──────────────┬───────────────┘
               │ Supabase Realtime + PostgREST
┌──────────────▼───────────────┐
│  2. macOS APP (Swift/SwiftUI)│
│  - Email triage UI           │
│  - Task list + estimation    │
│  - "Dish Me Up" planner      │
│  - Calendar read/write       │
│  - Voice input               │
│  Graph API calls (MSAL)      │
│  EventKit (Apple Calendar)   │
└──────────────┬───────────────┘
               │ Supabase Realtime
┌──────────────▼───────────────┐
│  3. PA VIEW (Karen)          │
│  Same macOS app, PA login    │
│  Full access, role=pa        │
└──────────────────────────────┘
```

## System Boundaries

| Rule | Enforced By |
|------|-------------|
| macOS app NEVER calls Claude API directly | All AI goes through Edge Functions |
| macOS app calls Graph API via GraphClient.swift only | Architecture rule + code review |
| PA view is same app, different auth role | Supabase RLS on workspace_members |
| Schema changes ONLY via migrations | no-raw-sql.sh hook blocks direct SQL |
| All background work in Edge Functions | No setTimeout/Timer in app code |

## The Core Loop

```
email arrives
  → Graph webhook → process-email-pipeline Edge Function
    → classify-email (Claude Sonnet) → inbox | later | blackhole
    → if inbox: extract-tasks (Claude Opus) → Task record
    → estimate-time (Claude Opus) → estimated_minutes
  → Supabase Realtime → macOS app updates live

user opens app
  → "I have 90 minutes"
  → generate-daily-plan Edge Function (Claude Opus)
    → reads: pending tasks + calendar gaps + voice input + constraints
    → returns: ordered PlanItem[] with schedule blocks
  → user approves → calendar blocks written (EventKit + Graph API)
```

## Feature Addition Checklist

When adding a new feature:

1. [ ] Write FR spec in `docs/specs/FR-XX-name.md` with acceptance criteria
2. [ ] Symlink spec to Obsidian: `ln -s docs/specs/FR-XX.md ~/Timed\ Vault/03\ -\ Specs/`
3. [ ] If new table needed: create migration in `supabase/migrations/`
4. [ ] If new Edge Function: create in `supabase/functions/`
5. [ ] If new Swift types: add to `Sources/TimedCore/Models/`
6. [ ] If new client code: add to appropriate feature folder in `Sources/TimedFeatures/`
7. [ ] **Update FILE ORACLE in CLAUDE.md** with all new files
8. [ ] Write tests in `Tests/`
9. [ ] Update PLAN.md with progress
10. [ ] On completion: walkthrough auto-written to Obsidian by Stop hook

## NEVER DO
- No business logic in SwiftUI views — views call Store actions only
- No direct Supabase imports — always through SupabaseClient.swift
- No direct Graph imports — always through GraphClient.swift
- No new files outside Sources/, Tests/, supabase/, docs/
- No manual schema changes — migrations only
