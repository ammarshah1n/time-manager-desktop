# Timed — Trigger.dev v3 pipeline (Wave 1 scaffold)

This folder hosts the Trigger.dev TypeScript project that replaces Timed's
nightly / morning Edge Functions with a single traceable agent runtime.

## Status

Wave 1 (Agent A1) scaffold only. Ships:

- `trigger.config.ts` — project config (runtime `node`, 15 min max, OTel-ready).
- `src/inference.ts` — centralised Anthropic wrapper with routing table,
  retry + exponential backoff, prompt-cache retrofit, and full `agent_traces`
  writes.
- `src/tasks/hello-claude.ts` — smoke task that exercises `inference()` end
  to end and asserts DB rows.
- `../supabase/migrations/20260425000000_agent_traces.sql` — the trace ledger.

Nothing here has been deployed yet. Task 2 (Trigger.dev org + secret upload)
and the Supabase migration apply are manual prerequisites owned by Ammar.

## Layout

```
trigger/
├── package.json
├── tsconfig.json
├── trigger.config.ts
└── src/
    ├── inference.ts
    ├── lib/
    │   ├── hash.ts
    │   └── supabase.ts
    └── tasks/
        └── hello-claude.ts
```

## Local checks

```bash
cd trigger
pnpm install
pnpm typecheck   # wrapper for `tsc --noEmit`
```

## Environment variables (populated by Trigger.dev secret storage in prod)

| Var | Used by |
| --- | --- |
| `ANTHROPIC_API_KEY` | `src/inference.ts` |
| `SUPABASE_URL` | `src/lib/supabase.ts` |
| `SUPABASE_SERVICE_ROLE_KEY` | `src/lib/supabase.ts` |
| `VOYAGE_API_KEY` | (reserved for Wave 2 skill-library MCP) |
| `TRIGGER_PROJECT_REF` | `trigger.config.ts` (defaults to placeholder) |

## Model routing table (edit here, nowhere else)

| Alias | Model |
| --- | --- |
| `opus_synthesis` | `claude-opus-4-7` |
| `opus_critic` | `claude-opus-4-7` |
| `opus_briefing` | `claude-opus-4-7` |
| `sonnet_extract` | `claude-sonnet-4-6` |
| `sonnet_estimate` | `claude-sonnet-4-6` |
| `haiku_classify` | `claude-haiku-4-5-20251001` |

Any future local fine-tune redirect is a diff to `MODEL_ROUTING` in
`src/inference.ts` — no call sites change.
