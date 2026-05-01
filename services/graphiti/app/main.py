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

import json
import logging
import hmac
import os
import re
import typing
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

import openai
from fastapi import Depends, FastAPI, Header, HTTPException
from openai.types.chat import ChatCompletionMessageParam
from pydantic import BaseModel, Field

from graphiti_core import Graphiti
from graphiti_core.cross_encoder.openai_reranker_client import OpenAIRerankerClient
from graphiti_core.embedder.openai import OpenAIEmbedder, OpenAIEmbedderConfig
from graphiti_core.llm_client.anthropic_client import AnthropicClient
from graphiti_core.llm_client.config import DEFAULT_MAX_TOKENS, LLMConfig, ModelSize
from graphiti_core.llm_client.errors import RateLimitError
from graphiti_core.llm_client.openai_generic_client import (
    DEFAULT_MODEL,
    OpenAIGenericClient,
)
from graphiti_core.nodes import EpisodeType
from graphiti_core.prompts.models import Message

logger = logging.getLogger("graphiti.service")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))


# Anthropic via litellm wraps JSON output in ```json ... ``` fences even when
# response_format={"type":"json_object"} is requested. graphiti-core's
# OpenAIGenericClient calls json.loads() on the raw content and crashes. This
# subclass mirrors the upstream method body and strips the fence before parsing.
_FENCE_RE = re.compile(r"^\s*```(?:json)?\s*\n?(.*?)\n?```\s*$", re.DOTALL)


def _strip_json_fence(text: str) -> str:
    if not text:
        return text
    match = _FENCE_RE.match(text)
    return match.group(1).strip() if match else text.strip()


class FenceTolerantOpenAIClient(OpenAIGenericClient):
    """OpenAIGenericClient that tolerates markdown-fenced JSON in LLM output."""

    async def _generate_response(
        self,
        messages: list[Message],
        response_model: type[BaseModel] | None = None,
        max_tokens: int = DEFAULT_MAX_TOKENS,
        model_size: ModelSize = ModelSize.medium,
    ) -> dict[str, typing.Any]:
        openai_messages: list[ChatCompletionMessageParam] = []
        for m in messages:
            m.content = self._clean_input(m.content)
            if m.role == "user":
                openai_messages.append({"role": "user", "content": m.content})
            elif m.role == "system":
                openai_messages.append({"role": "system", "content": m.content})
        try:
            response = await self.client.chat.completions.create(
                model=self.model or DEFAULT_MODEL,
                messages=openai_messages,
                temperature=self.temperature,
                max_tokens=self.max_tokens,
                response_format={"type": "json_object"},
            )
            result = response.choices[0].message.content or ""
            cleaned = _strip_json_fence(result)
            return json.loads(cleaned)
        except openai.RateLimitError as e:
            raise RateLimitError from e
        except Exception as e:
            logger.error(
                "Error in generating LLM response: %s; raw=%r", e, result if "result" in locals() else None
            )
            raise


def _required(name: str) -> str:
    val = os.getenv(name)
    if not val:
        raise RuntimeError(f"Missing required env var: {name}")
    return val


GRAPHITI_API_TOKEN = _required("GRAPHITI_API_TOKEN")


def require_api_token(authorization: str | None = Header(default=None)) -> None:
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="unauthorized",
            headers={"WWW-Authenticate": "Bearer"},
        )
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=401,
            detail="unauthorized",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not hmac.compare_digest(token, GRAPHITI_API_TOKEN):
        raise HTTPException(status_code=403, detail="forbidden")


def build_graphiti() -> Graphiti:
    """Construct a Graphiti instance pointed at the inference proxy.

    The proxy is OpenAI-compatible — `OpenAIGenericClient` with `base_url`
    pointed at it routes every LLM call through our traced `inference()`
    wrapper. This is the integration seam: swap `INFERENCE_PROXY_URL` for a
    local fine-tuned endpoint in Phase 4 and nothing else changes.
    """
    proxy_url = _required("INFERENCE_PROXY_URL")
    proxy_key = _required("INFERENCE_PROXY_API_KEY")

    # LLM extraction goes direct to Anthropic. graphiti-core's AnthropicClient
    # uses Anthropic's tool-use API to enforce response schemas — required
    # because Claude (via litellm OpenAI-compat) doesn't reliably produce
    # schema-conforming JSON, and graphiti's pipeline crashes on shape drift.
    # Embeddings + reranker still go through litellm (kept for tracing +
    # for the voyage-3 embedder routing).
    anthropic_key = _required("ANTHROPIC_API_KEY")
    anthropic_llm_config = LLMConfig(
        api_key=anthropic_key,
        model=os.getenv("GRAPHITI_ANTHROPIC_MODEL", "claude-sonnet-4-6"),
        small_model=os.getenv(
            "GRAPHITI_ANTHROPIC_SMALL_MODEL", "claude-haiku-4-5-20251001"
        ),
        max_tokens=DEFAULT_MAX_TOKENS,
    )
    llm_client = AnthropicClient(config=anthropic_llm_config)

    llm_config = LLMConfig(
        api_key=proxy_key,
        model=os.getenv("GRAPHITI_MODEL", "sonnet_extract"),
        small_model=os.getenv("GRAPHITI_SMALL_MODEL", "haiku_classify"),
        base_url=proxy_url,
    )

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

    # `OpenAIRerankerClient` builds its own `AsyncOpenAI` from this config, so the
    # reranker hits the same INFERENCE_PROXY_URL as the LLM/embedder seam. We
    # deliberately do NOT pass `client=llm_client` — that kwarg expects an
    # `AsyncOpenAI`, not Graphiti's `OpenAIGenericClient` wrapper.
    cross_encoder = OpenAIRerankerClient(config=llm_config)

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


@app.post("/episode", dependencies=[Depends(require_api_token)])
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
            group_id=body.group_id or "",
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("add_episode failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    ep = getattr(result, "episode", None)
    return {"episode_uuid": ep.uuid if ep is not None else None}


@app.post("/search", dependencies=[Depends(require_api_token)])
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
