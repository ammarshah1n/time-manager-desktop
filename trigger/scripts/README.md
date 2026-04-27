# trigger/scripts — replay + export-training-data (Wave 1 Agent A5 stubs)

These files are scaffolded in parallel with Agent A1's `trigger/` Trigger.dev v3
project. At the time this was authored the full `trigger/` workspace
(`package.json`, `trigger.config.ts`, `src/`, shared `inference()` wrapper) does
not yet exist — A1 owns that scope. After both Wave 1 branches merge into
`ui/apple-v1-restore`, these two CLIs slot into the A1 workspace as the
operational scripts for deterministic replay (task 41) and fine-tuning corpus
export (task 42).

## Files

| Path | Purpose |
|---|---|
| `replay.ts` | Task 41 stub — deterministic-replay CLI with `--mode=prompt` (default) and `--mode=kg-restore --snapshot-week=YYYY-WW`. Full CLI parsing + report generation are real; Supabase / Neo4j / inference calls are TODO(wave2). |
| `export-training-data.ts` | Task 42 stub — JSONL dump of `(system_prompt, user_prompt, tools_available, tool_use_trajectory, final_response, cache_stats)` for `--from=YYYY-MM-DD --to=YYYY-MM-DD`, uploaded to Supabase Storage bucket `fine-tuning-corpus/`. CLI parsing + schema validation + Supabase client wiring are real; data fetch + upload are TODO(wave2). |
| `types.stubs.ts` | Hand-written row shapes for `agent_sessions`, `agent_traces`, `kg_snapshots`, and the reconstructed `InferenceTuple`. Must be deleted and replaced by generated Supabase types after A1 + B4 land. |
| `tsconfig.scripts.json` | Isolated tsconfig so `tsc --noEmit` passes without depending on A1's workspace `package.json`. Points `types` at `node` only and uses local path aliases. |
| `package.json` | **Stub dependency manifest only.** Absorbed by A1's workspace `package.json` after merge. Do not add application code here. |

## CLI argument parser

[`commander`](https://www.npmjs.com/package/commander) v12. Chosen over
`yargs` for a simpler action/option API and smaller dep surface.

## Runner

[`tsx`](https://www.npmjs.com/package/tsx). The two CLIs have `#!/usr/bin/env tsx`
shebangs so they can be run directly after `chmod +x` or invoked as
`tsx replay.ts` / `tsx export-training-data.ts`.

## Verification commands (Wave 1 gate)

```sh
cd trigger/scripts

# 1. Typecheck in isolation — passes without A1's package.json.
./node_modules/.bin/tsc -p tsconfig.scripts.json --noEmit

# 2. --help renders cleanly.
./node_modules/.bin/tsx replay.ts --help
./node_modules/.bin/tsx export-training-data.ts --help

# 3. Dry-run prints an accurate plan without touching Supabase.
./node_modules/.bin/tsx replay.ts --session-id=<uuid> --dry-run
./node_modules/.bin/tsx replay.ts --session-id=<uuid> --mode=kg-restore --snapshot-week=2026-17 --dry-run
./node_modules/.bin/tsx export-training-data.ts --from=2026-04-01 --to=2026-04-20 --dry-run
```

## Determinism guarantees (task 41)

`replay.ts --help` and the report header both document this; summarised here
for reviewers:

- **`--mode=prompt` (default):** deterministic at the LLM-input level modulo
  sampling. **NOT** deterministic at the KG-state level — tool results come
  from the current Graphiti instance, which has mutated since the original run.
  Any divergence in the diff report may be real KG drift rather than a bug.
- **`--mode=kg-restore --snapshot-week=YYYY-WW`:** forensic replay. Restores
  the weekly `kg_snapshots` row into a scratch Neo4j at `NEO4J_REPLAY_URI`,
  re-points Graphiti MCP at the scratch instance, then re-runs the trajectory.
  Deterministic at both LLM-input and KG-state level modulo sampling noise.

## TODO(wave2) checklist

Each stub call site raises an explicit `TODO(wave2)` error message that names
its next step. The big-picture work is:

1. Replace `types.stubs.ts` with generated Supabase types (`supabase gen types`).
2. Wire `loadSession` / `loadTraces` / `loadTracesForSession` /
   `listSessionsInRange` against the real `agent_sessions` + `agent_traces`
   tables (task 4 migration).
3. Implement `reconstructInferences(traces)` once per agent — both CLIs must
   share the same grouping helper. Boundary rule: a new `InferenceTuple`
   begins at the first trace row or whenever `role='system' | 'user'` follows
   a `tool_result`.
4. Wire `reissueInference` against A1's shared `inference()` function.
5. Wire `locateKgSnapshot` / `restoreKgIntoScratchNeo4j` / `repointGraphitiMcp`
   against B4's weekly snapshot migration (task 28a) and the graphiti-mcp
   service A2 ships.
6. Wire `uploadToStorage` against the Supabase Storage JS client.
7. Delete this `package.json` + `tsconfig.scripts.json` once A1's workspace
   can resolve deps and typecheck for this folder. Keep only the `.ts` files.

## Merge ordering

Merges **after** A1. Once A1's `trigger/package.json` lands:

- Delete `trigger/scripts/package.json`, `trigger/scripts/package-lock.json`,
  `trigger/scripts/package.stubs.json`, and `trigger/scripts/node_modules/`.
- Move `commander`, `zod`, `@supabase/supabase-js` into A1's workspace deps.
- Replace `tsconfig.scripts.json` with an `extends` of A1's root tsconfig.
- Regenerate canonical row types from Supabase and delete `types.stubs.ts`.
