# ADR-003: Use Supabase Edge Functions, Not Inngest

## Decision
All background jobs run as Supabase Edge Functions + pg_cron. No Inngest. No Railway.

## Context
The TIMEBLOCK_AI_OPTIMISATION doc recommended Inngest on Railway. Rejected because:

## Why Not Inngest
- Adds Railway as a deployment target (extra infrastructure)
- Inngest requires a separate running worker process
- Supabase Edge Functions are already in the ecosystem
- Edge Functions handle the AI pipeline workload (classify → extract → estimate)
- pg_cron covers scheduled jobs (subscription renewal, delta sync backup)

## Consequences
- Edge Function timeout is 150s. Each pipeline stage must fit within this.
- For batch processing (50 emails), fan out with parallel Edge Function invocations.
- If pipelines grow complex post-MVP, consider Inngest/Temporal as an upgrade path.

## Known Tradeoff: No Step-Level Retries

Inngest's killer feature is automatic step-level retries — if step 3 of 5 fails,
only step 3 retries. Edge Functions retry the entire function.

**Mitigation (chosen):** Adopt pgflow (npx pgflow@latest install) which provides
per-step retries, dependency DAGs, and result caching within Supabase.
See: https://github.com/pgflow-dev/pgflow

**If pgflow is not adopted:** Accept that a failed folder-move will re-classify
the email on retry. Mitigate with idempotency checks:
- Before classifying: check if email.is_processed = true → skip
- Before moving folder: check if email is already in target folder → skip

**Revisit trigger:** If we serve more than 1 user, re-evaluate Inngest on Railway.

---

## Email Sync Architecture: Webhooks + Delta Query (Not Delta Query Alone)

**Decision:** Combine Graph API webhooks AND delta query. Do NOT use delta query polling alone.

**Pattern:**
```
Graph webhook fires → "inbox changed"
    ↓
Delta query runs → returns only emails changed since last sync
    ↓
Enqueue to pgmq → classify + route
```

**Why:** pg_cron polling fires even when nothing changed, burning Edge Function invocations.
Webhooks trigger only when mail arrives. Supabase Edge Functions already have public URLs —
no extra infrastructure needed for the webhook endpoint.

**Per-folder deltaLinks:** There is no "sync all folders" endpoint. Store a separate
`delta_link` per folder in Supabase. Folders to track:
- Inbox, Action/QuickReply, Action/Task, Action/Calls
- Read/ToRead, Read/CCFYI, Later, BlackHole

Each folder gets its own delta link row in a `folder_sync_state` table.

---

## pgmq — Message Queue for Retry Layer

**Decision:** Use pgmq as the queue between webhook receipt and Edge Function processing.

**Why:** pgmq runs inside Supabase Postgres — no external infra. If an Edge Function crashes
mid-processing, the message becomes visible again after a timeout and retries automatically.
This is the same guarantee Inngest provides, within the existing stack.

**Setup:**
```sql
SELECT pgmq.create('email_triage');

-- On webhook receipt, enqueue:
SELECT pgmq.send('email_triage',
  '{"emailId": "abc123", "folder": "inbox"}'::jsonb
);
```

**pgflow pipeline (per-step retries + DAG):**
```typescript
const triageFlow = new Flow('email_triage')
  .step('classify', { retries: 3 }, async (email) => classifyEmail(email))
  .step('moveToFolder', { retries: 2, dependsOn: ['classify'] }, async (r) => moveEmail(r))
  .step('createTask',   { retries: 2, dependsOn: ['classify'] }, async (r) => extractTask(r))
```
If LLM times out in `classify`, only `classify` retries. `moveToFolder` and `createTask`
run in parallel after classify resolves, with prior results cached in Postgres.
