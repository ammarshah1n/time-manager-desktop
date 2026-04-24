# skill-library-mcp

MCP server exposing Timed's Voyager-style procedural skill library. The REM
synthesis agent (task 28) calls `write_skill(...)` when it discovers a novel
analytical procedure; the morning briefing agent (task 29) and weekly synthesis
agent (task 35) call `retrieve_skills(...)` to fetch the top-K relevant skills
before reasoning.

Storage is `public.skills` in the Timed Supabase project (migration
`20260426000000_skill_library.sql` in this repo). Embeddings are Voyage
`voyage-3` (1024-dim) to match the `VECTOR(1024)` column and HNSW index.

## Tools (public contract)

| Tool | Signature | Purpose |
|---|---|---|
| `retrieve_skills(context_text, top_k)` | `context_text: string; top_k: 1..50 (default 5)` | Embed query in "query" mode; cosine k-NN over `skills.embedding` via `retrieve_skills` RPC |
| `write_skill(name, procedure_text, creation_context, creation_session_id?)` | — | Embed procedure in "document" mode; insert row. `creation_session_id` (FK → `agent_sessions`) is optional but should be populated when called from a traced Trigger.dev run |
| `record_skill_usage(skill_id, outcome, session_id, notes)` | `outcome: "success" | "failure"` | Atomically increments counters + stamps `last_used_at`. Called by REM / weekly pipelines after a skill is used in a reasoning loop |

## Environment contract

| Variable | Required | Meaning |
|---|---|---|
| `SKILL_LIBRARY_MCP_TOKEN` | yes | Bearer token clients must present |
| `SUPABASE_URL` | yes | `https://fpmjuufefhtlwbfinxlx.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | Service-role key (bypasses RLS) |
| `VOYAGE_API_KEY` | yes | Voyage AI API key |
| `VOYAGE_MODEL` | no (default `voyage-3`) | Embedding model — must produce `VOYAGE_DIM`-dim vectors |
| `VOYAGE_DIM` | no (default `1024`) | Must match `skills.embedding` column width |
| `PORT` | no (default `8080`) | HTTP bind port |

## HTTP surface

| Path | Auth | Purpose |
|---|---|---|
| `GET /healthz` | none | Liveness |
| `GET /readyz` | none | Probes Supabase |
| `POST /mcp` | bearer | MCP Streamable HTTP endpoint |

## Local development

```bash
cd services/skill-library-mcp
pnpm install
pnpm typecheck
pnpm build
SKILL_LIBRARY_MCP_TOKEN=dev-token \
SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=dev-key \
VOYAGE_API_KEY=<dev-key> \
pnpm dev
```

## Deploy

```bash
fly launch --no-deploy --copy-config
fly secrets set \
  SKILL_LIBRARY_MCP_TOKEN=$(openssl rand -hex 32) \
  SUPABASE_URL=https://fpmjuufefhtlwbfinxlx.supabase.co \
  SUPABASE_SERVICE_ROLE_KEY=<secret> \
  VOYAGE_API_KEY=<secret>
fly deploy
```

## Shared container with `graphiti-mcp`

Same option as documented in `services/graphiti-mcp/README.md` — both servers
are small (<100 MB resident) and can be merged into one Fly app by combining
their `registerTools(...)` calls on a single `McpServer` instance. Default is
**separate apps** until the MCP surfaces stabilise.
