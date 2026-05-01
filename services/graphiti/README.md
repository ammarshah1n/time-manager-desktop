# graphiti (core)

Thin wrapper around [`getzep/graphiti`](https://github.com/getzep/graphiti)
configured so that **every LLM call and every embedding call** routes through
the Timed centralized inference proxy — never directly to OpenAI.

This service is an internal dependency of `services/graphiti-mcp`. End users
(Trigger.dev tasks, Claude agents) talk to `graphiti-mcp`, not to this.

## Why this exists

`graphiti-core` hard-codes an OpenAI-compatible client for LLM + embedder +
reranker. We need Sonnet (not GPT-4.x) for entity extraction and Voyage
`voyage-3` for embeddings, and we want every token accounted for in
`agent_traces`. The cheapest way to satisfy both is:

1. Stand up an OpenAI-compatible HTTP proxy in front of `trigger/src/inference.ts`
   (Task 5). The proxy accepts `/v1/chat/completions` and `/v1/embeddings`,
   maps them onto our aliases (`sonnet_extract`, `voyage-3`), and writes traces.
2. Point Graphiti's `OpenAIGenericClient` at that proxy via `base_url`.

From Graphiti's perspective it is still "OpenAI"; from our perspective every
call lands in `agent_traces` with full token accounting.

## Environment contract (Sonnet proxy integration seam)

| Variable | Required | Meaning |
|---|---|---|
| `NEO4J_URI` | yes | Bolt URI — AuraDB Professional or Fly Neo4j machine |
| `NEO4J_USER` | yes | neo4j |
| `NEO4J_PASSWORD` | yes | secret |
| `GRAPHITI_API_TOKEN` | yes | Bearer token required for `/episode` and `/search` |
| `INFERENCE_PROXY_URL` | yes | OpenAI-compatible base URL of the Trigger.dev `inference()` proxy (e.g. `https://timed-inference-proxy.fly.dev/v1`) |
| `INFERENCE_PROXY_API_KEY` | yes | Bearer token accepted by the proxy |
| `GRAPHITI_MODEL` | no (default `sonnet_extract`) | Alias routed to Sonnet inside `inference()` |
| `GRAPHITI_SMALL_MODEL` | no (default `haiku_classify`) | Alias routed to Haiku for short extraction prompts |
| `EMBEDDER_BASE_URL` | no (defaults to `INFERENCE_PROXY_URL`) | OpenAI-compatible embeddings endpoint |
| `EMBEDDER_API_KEY` | no (defaults to `INFERENCE_PROXY_API_KEY`) | Bearer token for embeddings proxy |
| `EMBEDDER_MODEL` | no (default `voyage-3`) | Embedding model alias — must be 1024-dim to match `skills.embedding` |
| `EMBEDDER_DIM` | no (default `1024`) | Must match `EMBEDDER_MODEL` |
| `PORT` | no (default `8000`) | HTTP bind port |
| `LOG_LEVEL` | no (default `INFO`) | Python logging level |

### Wave 1 integration seam (no proxy deployed yet)

Task 5 (A1's scope) will ship the proxy. Until then, `graphiti` cannot run end-
to-end. **This is deliberate**: A2's Wave 1 deliverable is the container + the
environment contract, not a live service. The README documents the seam; the
Dockerfile + `fly.toml` stand up the second `INFERENCE_PROXY_URL` is populated.

If you need to smoke-test before A1 lands:

```bash
export INFERENCE_PROXY_URL=https://api.openai.com/v1
export INFERENCE_PROXY_API_KEY=sk-...
export GRAPHITI_MODEL=gpt-4o-mini
export EMBEDDER_MODEL=text-embedding-3-small
export EMBEDDER_DIM=1536  # must match
```

Swap back to the Trigger.dev proxy once it is live. Nothing in this service
changes.

## HTTP surface

| Method | Path | Purpose |
|---|---|---|
| GET  | `/healthz`  | Liveness (always returns 200 if process is up) |
| GET  | `/readyz`   | Readiness — pings Neo4j |
| POST | `/episode`  | Bearer-authenticated `graphiti.add_episode(...)` passthrough |
| POST | `/search`   | Bearer-authenticated `graphiti.search(...)` hybrid BM25+semantic |

`graphiti-mcp` uses `/episode` when a caller invokes `add_episode(...)` so that
entity extraction runs through Graphiti's canonical pipeline (which now routes
to Sonnet via the proxy). Simple reads (`search_episodes`, `search_facts`,
`get_entity_timeline`, etc.) bypass this service and go to Neo4j directly —
faster and no LLM involvement.

## Deploy

```bash
cd services/graphiti
fly launch --no-deploy --copy-config       # first time only
fly secrets set \
    NEO4J_URI=bolt+s://<host>:7687 \
    NEO4J_USER=neo4j \
    NEO4J_PASSWORD=<secret> \
    GRAPHITI_API_TOKEN=<generate-256-bit-token> \
    INFERENCE_PROXY_URL=https://<trigger-proxy>/v1 \
    INFERENCE_PROXY_API_KEY=<secret>
fly deploy
```

## Non-goals

- No public data endpoints without bearer auth. Health/readiness remain public
  for Fly checks; all graph reads/writes require `GRAPHITI_API_TOKEN`.
- No direct Neo4j admin endpoints. For snapshots see `graphiti-mcp`'s
  `export_snapshot` which runs `apoc.export.json.all`.
