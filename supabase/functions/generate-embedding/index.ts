import { serve } from "https://deno.land/std@0.208.0/http/server.ts";

const MAX_BATCH_SIZE = 10;
const VOYAGE_MODEL = "voyage-3";
const OPENAI_MODEL = "text-embedding-3-large";
const VOYAGE_DIMENSION = 1024;
const OPENAI_DIMENSION = 3072;

type EmbeddingRequest = {
  texts: string[];
  tier: 0 | 1 | 2 | 3;
};

type ProviderConfig = {
  apiKey: string;
  url: string;
  model: string;
  dimension: number;
  headers: Record<string, string>;
  body: (texts: string[]) => Record<string, unknown>;
};

type ProviderEmbeddingItem = {
  embedding?: unknown;
  index?: unknown;
};

type ProviderResponse = {
  data?: ProviderEmbeddingItem[];
};

function responseHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Content-Type": "application/json",
  };
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(),
  });
}

function isValidTier(value: unknown): value is 0 | 1 | 2 | 3 {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 3;
}

function parseRequestBody(body: unknown): EmbeddingRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }

  const texts = (body as { texts?: unknown }).texts;
  const tier = (body as { tier?: unknown }).tier;

  if (!Array.isArray(texts) || texts.length === 0 || texts.length > MAX_BATCH_SIZE) {
    return null;
  }

  if (!texts.every((text) => typeof text === "string")) {
    return null;
  }

  if (!isValidTier(tier)) {
    return null;
  }

  return { texts, tier };
}

function providerConfigForTier(tier: 0 | 1 | 2 | 3): ProviderConfig | null {
  if (tier === 0) {
    const apiKey = Deno.env.get("VOYAGE_API_KEY");
    if (!apiKey) {
      return null;
    }

    return {
      apiKey,
      url: "https://api.voyageai.com/v1/embeddings",
      model: VOYAGE_MODEL,
      dimension: VOYAGE_DIMENSION,
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: (texts) => ({
        model: VOYAGE_MODEL,
        input: texts,
        output_dimension: VOYAGE_DIMENSION,
      }),
    };
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return null;
  }

  return {
    apiKey,
    url: "https://api.openai.com/v1/embeddings",
    model: OPENAI_MODEL,
    dimension: OPENAI_DIMENSION,
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
    body: (texts) => ({
      model: OPENAI_MODEL,
      input: texts,
      dimensions: OPENAI_DIMENSION,
    }),
  };
}

function parseEmbeddingRows(data: ProviderEmbeddingItem[] | undefined, expectedCount: number): number[][] | null {
  if (!Array.isArray(data) || data.length !== expectedCount) {
    return null;
  }

  const sorted = [...data].sort((left, right) => {
    const leftIndex = typeof left.index === "number" ? left.index : 0;
    const rightIndex = typeof right.index === "number" ? right.index : 0;
    return leftIndex - rightIndex;
  });

  const embeddings = sorted.map((item) => item.embedding);
  if (!embeddings.every((embedding) => Array.isArray(embedding) && embedding.every((value) => typeof value === "number"))) {
    return null;
  }

  return embeddings as number[][];
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: responseHeaders() });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let parsedBody: EmbeddingRequest | null = null;
  try {
    parsedBody = parseRequestBody(await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (parsedBody === null) {
    return jsonResponse(
      { error: "Expected { texts: string[1...10], tier: 0|1|2|3 }" },
      400,
    );
  }

  const provider = providerConfigForTier(parsedBody.tier);
  if (provider === null) {
    return jsonResponse({ error: "Embedding provider is not configured" }, 500);
  }

  try {
    const upstreamResponse = await fetch(provider.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...provider.headers,
      },
      body: JSON.stringify(provider.body(parsedBody.texts)),
    });

    if (!upstreamResponse.ok) {
      const detail = await upstreamResponse.text();
      return jsonResponse(
        {
          error: "Embedding provider request failed",
          provider: provider.model,
          detail,
        },
        502,
      );
    }

    const payload = await upstreamResponse.json() as ProviderResponse;
    const embeddings = parseEmbeddingRows(payload.data, parsedBody.texts.length);

    if (embeddings === null || embeddings.some((embedding) => embedding.length !== provider.dimension)) {
      return jsonResponse(
        {
          error: "Embedding provider returned an invalid payload",
          provider: provider.model,
        },
        502,
      );
    }

    return jsonResponse({
      embeddings,
      dimension: provider.dimension,
      model: provider.model,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown upstream error";
    return jsonResponse(
      {
        error: "Embedding provider request failed",
        provider: provider.model,
        detail: message,
      },
      502,
    );
  }
});
