"""
Graphiti core service.

Wraps `graphiti-core` and configures its LLM + embedder clients to point at the
Timed centralized inference proxy (Trigger.dev `inference()` exposed as an
OpenAI-compatible HTTP endpoint). Graphiti never talks to OpenAI directly.

The only HTTP surface this service exposes is:
  GET  /healthz              liveness
  GET  /readyz               checks Neo4j + proxy reachability
  POST /episode              add_episode passthrough (primary write path)
  POST /search               hybrid search passthrough

`graphiti-mcp` (Task 15) is the public-facing MCP server; it talks to Neo4j
directly for most ops and only uses this service when it needs Graphiti's
internal entity extraction + embedding pipeline (i.e. `add_episode`).
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from graphiti_core import Graphiti
from graphiti_core.cross_encoder.openai_reranker_client import OpenAIRerankerClient
from graphiti_core.embedder.openai import OpenAIEmbedder, OpenAIEmbedderConfig
from graphiti_core.llm_client.config import LLMConfig
from graphiti_core.llm_client.openai_generic_client import OpenAIGenericClient
from graphiti_core.nodes import EpisodeType

logger = logging.getLogger("graphiti.service")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))


def _required(name: str) -> str:
    val = os.getenv(name)
    if not val:
        raise RuntimeError(f"Missing required env var: {name}")
    return val


def build_graphiti() -> Graphiti:
    """Construct a Graphiti instance pointed at the inference proxy.

    The proxy is OpenAI-compatible — `OpenAIGenericClient` with `base_url`
    pointed at it routes every LLM call through our traced `inference()`
    wrapper. This is the integration seam: swap `INFERENCE_PROXY_URL` for a
    local fine-tuned endpoint in Phase 4 and nothing else changes.
    """
    proxy_url = _required("INFERENCE_PROXY_URL")
    proxy_key = _required("INFERENCE_PROXY_API_KEY")

    llm_config = LLMConfig(
        api_key=proxy_key,
        model=os.getenv("GRAPHITI_MODEL", "sonnet_extract"),
        small_model=os.getenv("GRAPHITI_SMALL_MODEL", "haiku_classify"),
        base_url=proxy_url,
    )
    llm_client = OpenAIGenericClient(config=llm_config)

    embedder_url = os.getenv("EMBEDDER_BASE_URL", proxy_url)
    embedder_key = os.getenv("EMBEDDER_API_KEY", proxy_key)
    embedder = OpenAIEmbedder(
        config=OpenAIEmbedderConfig(
            api_key=embedder_key,
            embedding_model=os.getenv("EMBEDDER_MODEL", "voyage-3"),
            embedding_dim=int(os.getenv("EMBEDDER_DIM", "1024")),
            base_url=embedder_url,
        )
    )

    cross_encoder = OpenAIRerankerClient(client=llm_client, config=llm_config)

    return Graphiti(
        _required("NEO4J_URI"),
        _required("NEO4J_USER"),
        _required("NEO4J_PASSWORD"),
        llm_client=llm_client,
        embedder=embedder,
        cross_encoder=cross_encoder,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.graphiti = build_graphiti()
    try:
        await app.state.graphiti.build_indices_and_constraints()
    except Exception:  # noqa: BLE001 — idempotent; log and proceed
        logger.exception("build_indices_and_constraints failed; continuing")
    try:
        yield
    finally:
        await app.state.graphiti.close()


app = FastAPI(title="graphiti-core", lifespan=lifespan)


class EpisodeIn(BaseModel):
    name: str
    episode_body: str
    source_description: str = "timed"
    reference_time: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    group_id: str | None = None
    source: str = Field(default="text", pattern="^(text|message|json)$")


class SearchIn(BaseModel):
    query: str
    num_results: int = 10
    center_node_uuid: str | None = None


@app.get("/healthz")
async def healthz() -> dict[str, Any]:
    return {"ok": True}


@app.get("/readyz")
async def readyz() -> dict[str, Any]:
    g: Graphiti = app.state.graphiti
    try:
        # Cheap probe — cypher ping. Driver is exposed as `g.driver`.
        async with g.driver.session() as session:
            await session.run("RETURN 1")
        return {"ok": True, "neo4j": True}
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=f"neo4j: {exc}") from exc


@app.post("/episode")
async def add_episode(body: EpisodeIn) -> dict[str, Any]:
    g: Graphiti = app.state.graphiti
    source_map = {
        "text": EpisodeType.text,
        "message": EpisodeType.message,
        "json": EpisodeType.json,
    }
    try:
        result = await g.add_episode(
            name=body.name,
            episode_body=body.episode_body,
            source_description=body.source_description,
            reference_time=body.reference_time,
            source=source_map[body.source],
            group_id=body.group_id,
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("add_episode failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    ep = getattr(result, "episode", None)
    return {"episode_uuid": ep.uuid if ep is not None else None}


@app.post("/search")
async def search(body: SearchIn) -> dict[str, Any]:
    g: Graphiti = app.state.graphiti
    edges = await g.search(
        query=body.query,
        num_results=body.num_results,
        center_node_uuid=body.center_node_uuid,
    )
    return {
        "edges": [
            {
                "uuid": e.uuid,
                "fact": e.fact,
                "valid_at": e.valid_at.isoformat() if e.valid_at else None,
                "invalid_at": e.invalid_at.isoformat() if e.invalid_at else None,
                "episodes": list(getattr(e, "episodes", []) or []),
            }
            for e in edges
        ]
    }
