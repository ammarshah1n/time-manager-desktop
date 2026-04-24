# graphiti-mcp

MCP server exposing the Timed temporal knowledge graph (Graphiti + Neo4j) as
first-class tools to Trigger.dev tasks and Claude agents. Shipped as a Fly.io
HTTP service over the Streamable HTTP MCP transport with a bearer-token guard.

## Architecture

```
 Trigger.dev / Claude agent
          │  HTTP POST /mcp, Bearer GRAPHITI_MCP_TOKEN
          ▼
 ┌─────────────────────┐
 │   graphiti-mcp      │ ── this service
 │   (TypeScript)      │
 └──────┬──────┬───────┘
        │      │
        │      └────────────▶ sibling `graphiti` service (Python)
        │                     add_episode → Sonnet entity extraction
        │                     + Voyage embeddings via inference proxy
        ▼
     Neo4j (AuraDB Professional or Fly machine)
        reads: search_episodes, search_facts, timeline, relationships
        writes: add_fact, invalidate_fact, episode_exists, export_snapshot
```

Reads hit Neo4j directly (no LLM round-trip, no Python hop). Only `add_episode`
routes through the sibling Graphiti Python service so entity extraction + fact
inference run through Graphiti's canonical pipeline.

## Tools (public contract)

| Tool | Signature | Purpose |
|---|---|---|
| `search_episodes(query, time_window?)` | `query: string; time_window?: {from?, to?}` | Content search over Episodic nodes, optionally bounded by `valid_at` |
| `search_facts(query, valid_at?)` | `query: string; valid_at?: ISO` | **Temporal retrieval**: when `valid_at` is set, only facts true at that time are returned (honours `valid_at` / `invalid_at` / `expired_at`) |
| `get_entity_timeline(entity_id)` | `entity_id: string` | Full history of every fact incident to the entity, including invalidated ones |
| `get_entity_relationships(entity_id, depth)` | `depth: 1..3` | Reachable peers, currently-valid edges only |
| `add_episode(content, timestamp, entity_refs, content_hash)` | — | Ingest an episode; routes through Graphiti's extraction pipeline. **Idempotent** — pre-checks `episode_exists(content_hash)` |
| `episode_exists(content_hash)` | `content_hash: string` → `{ episode_id } | null` | Mandatory idempotency probe for backfill / retry flows. Graphiti has no native external-id dedupe |
| `add_fact(subject, predicate, object, valid_from, valid_to, evidence_episode_ids)` | — | Direct triple write (bypasses extraction). Used by NREM A-MEM loop |
| `invalidate_fact(fact_id, reason, invalidated_at)` | — | Sets `invalid_at` + `expired_at` + `invalidation_reason`. Never DELETE — preserves temporal replay |
| `list_communities()` | — | Leiden-clustered entity groups with member counts |
| `export_snapshot(session_id)` | — | `apoc.export.json.all` → Supabase Storage `kg-snapshots/<YYYY-WW>/<session_id>.json`. Sole feed for replay `--mode=kg-restore` (task 41) |

All tools return `{ content: [{type: "text", ...}], structuredContent: {...} }`
per the MCP spec.

## Environment contract

| Variable | Required | Meaning |
|---|---|---|
| `GRAPHITI_MCP_TOKEN` | yes | Bearer token clients must present. Generate with `openssl rand -hex 32` |
| `NEO4J_URI` | yes | Bolt URI, must match the one given to the `graphiti` service |
| `NEO4J_USER` | yes | neo4j |
| `NEO4J_PASSWORD` | yes | secret |
| `GRAPHITI_URL` | yes | Base URL of the sibling Python service, e.g. `http://timed-graphiti.internal:8000` |
| `SUPABASE_URL` | yes | `https://fpmjuufefhtlwbfinxlx.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | Service-role key (required for Storage writes) |
| `GRAPHITI_SNAPSHOT_BUCKET` | no (default `kg-snapshots`) | Storage bucket |
| `PORT` | no (default `8080`) | HTTP bind port |

## HTTP surface

| Path | Auth | Purpose |
|---|---|---|
| `GET /healthz` | none | Liveness |
| `GET /readyz` | none | Pings Neo4j |
| `POST /mcp` | bearer | MCP Streamable HTTP endpoint |

## Local development

```bash
cd services/graphiti-mcp
pnpm install
pnpm typecheck      # gate 1
pnpm build
GRAPHITI_MCP_TOKEN=dev-token \
NEO4J_URI=bolt://localhost:7687 NEO4J_USER=neo4j NEO4J_PASSWORD=password \
GRAPHITI_URL=http://localhost:8000 \
SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=dev-key \
pnpm dev
```

## Deploy

```bash
fly launch --no-deploy --copy-config   # first time only
fly secrets set \
  GRAPHITI_MCP_TOKEN=$(openssl rand -hex 32) \
  NEO4J_URI=bolt+s://<host>:7687 \
  NEO4J_USER=neo4j \
  NEO4J_PASSWORD=<secret> \
  GRAPHITI_URL=http://timed-graphiti.internal:8000 \
  SUPABASE_URL=https://fpmjuufefhtlwbfinxlx.supabase.co \
  SUPABASE_SERVICE_ROLE_KEY=<secret>
fly deploy
```

## Shared-container option with `skill-library-mcp`

Both MCP servers are cheap processes (each <100 MB resident). If Fly machine
cost matters, they can be co-located in a single container:

1. Duplicate `src/server.ts` into a combined entrypoint that mounts both sets
   of tools on the same `McpServer` instance (they share no state; keys don't
   collide).
2. Change `fly.toml` `app` to a single name and expose one port.
3. Merge secrets (append `SUPABASE_SERVICE_ROLE_KEY` already present, add
   `VOYAGE_API_KEY`).

We default to **separate Fly apps** in Wave 1 so deployment + blast radius is
per-service. Revisit once the MCP surfaces stabilise.

## `graphiti-smoke` contract (task 16 — not in A2 scope)

The downstream smoke task must prove temporal retrieval fidelity by exercising
this server's tools in the following sequence. Summarised here so A2's contract
is testable end-to-end when task 16 lands:

1. `add_episode(content="facts at T0", timestamp=T0, content_hash=H0)`
2. `add_episode(content="facts at T1", timestamp=T1, content_hash=H1)`
3. `add_episode(content="facts at T2", timestamp=T2, content_hash=H2)`
4. `add_fact(subject=S, predicate=P1, object=O1, valid_from=T0, evidence=[H0])`
5. `add_fact(subject=S, predicate=P1, object=O2, valid_from=T1, evidence=[H1])` — contradicts #4
6. `invalidate_fact(fact_id=<id from #4>, reason="superseded", invalidated_at=T1)`
7. Assert `search_facts(query="P1", valid_at=T0).facts` contains O1 (pre-invalidation truth)
8. Assert `search_facts(query="P1", valid_at=T2).facts` contains O2 and NOT O1
9. Assert `episode_exists(H0).episode_id` is the id returned by step 1
10. Re-run step 1 with the same `content_hash` — must return `{ deduped: true, episode_id: <same id> }`, no duplicate Episodic node

If any assertion fails, temporal retrieval or idempotency are broken and the
gate must fail.
