# ADR-002: Use Supabase as Backend

## Decision
New Supabase project for Timed. Postgres + Auth + Realtime + Edge Functions + Storage.

## Context
Need: relational queries (email/task/calendar joins), real-time PA sync, serverless AI pipeline, auth with roles.

## Alternatives Considered
- **Firebase/Firestore**: Document model wrong for relational queries. Vendor lock-in.
- **Railway + Postgres**: More ops overhead. No built-in realtime or auth.
- **CloudKit**: No web access for Karen. No Edge Functions. Apple-only.
- **Convex**: Good realtime but newer ecosystem. Ammar has no experience.

## Consequences
- Edge Functions limited to 150s. Design AI pipelines to fit.
- pg_cron for scheduled jobs (subscription renewal, delta sync backup).
- supabase-swift SDK covers Auth, Realtime, PostgREST, Storage.
