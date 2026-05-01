# Graphiti core service — wraps getzep/graphiti Python package and exposes an
# HTTP embed/extract surface configured to call Sonnet via the centralized
# inference proxy (never OpenAI directly).
#
# Environment contract (all required at runtime, none baked in):
#   NEO4J_URI               bolt+s://<host>:7687
#   NEO4J_USER              neo4j
#   NEO4J_PASSWORD          <secret>
#   INFERENCE_PROXY_URL     OpenAI-compatible base URL fronting Anthropic Sonnet
#                           (e.g. https://trigger-proxy.fly.dev/v1). This is the
#                           integration seam into trigger/src/inference.ts.
#   INFERENCE_PROXY_API_KEY Bearer token the proxy accepts
#   GRAPHITI_MODEL          Logical name the proxy routes to Sonnet
#                           (default: sonnet_extract)
#   GRAPHITI_SMALL_MODEL    Small-model alias (default: haiku_classify)
#   EMBEDDER_BASE_URL       OpenAI-compatible embeddings endpoint (defaults to
#                           INFERENCE_PROXY_URL; same proxy fronts Voyage)
#   EMBEDDER_API_KEY        Bearer token for embeddings proxy
#   EMBEDDER_MODEL          voyage-3
#   EMBEDDER_DIM            1024
#   PORT                    HTTP bind port (default: 8000)

FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt requirements.lock ./
RUN pip install --no-cache-dir -r requirements.txt -c requirements.lock

COPY app ./app

# Non-root runtime
RUN useradd --system --uid 10001 graphiti \
 && chown -R graphiti:graphiti /app
USER graphiti

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT:-8000}/healthz || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
