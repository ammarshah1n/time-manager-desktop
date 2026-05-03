// Shared Anthropic API helper for nightly pipeline Edge Functions
// Supports Opus, Sonnet, Haiku with extended thinking and Batch API

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_BATCH_URL = "https://api.anthropic.com/v1/messages/batches";

export type AnthropicModel =
  | "claude-opus-4-6"
  | "claude-sonnet-4-6"
  | "claude-haiku-4-5-20251001";

export type ThinkingEffort = "low" | "medium" | "high";

export type AnthropicMessage = {
  role: "user" | "assistant";
  content: string;
};

export type AnthropicRequest = {
  model: AnthropicModel;
  messages: AnthropicMessage[];
  system?: string;
  max_tokens: number;
  temperature?: number;
  timeout_ms?: number;
  max_retries?: number;
  thinking?: {
    type: "enabled";
    budget_tokens?: number;
    effort?: ThinkingEffort;
  };
};

export type AnthropicResponse = {
  id: string;
  content: Array<{
    type: "text" | "thinking";
    text?: string;
    thinking?: string;
  }>;
  model: string;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
};

function getApiKey(): string {
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) throw new Error("ANTHROPIC_API_KEY not set");
  return key;
}

const MAX_RETRIES = 3;
const RETRY_BASE_MS = 1000;
const FETCH_TIMEOUT_MS = 55000; // 55s — leave 5s headroom for Edge Function 60s wall clock

export async function callAnthropic(request: AnthropicRequest): Promise<AnthropicResponse> {
  const apiKey = getApiKey();
  const timeoutMs = request.timeout_ms ?? FETCH_TIMEOUT_MS;
  const maxRetries = request.max_retries ?? MAX_RETRIES;

  const body: Record<string, unknown> = {
    model: request.model,
    messages: request.messages,
    max_tokens: request.max_tokens,
  };

  if (request.system) body.system = request.system;
  if (request.temperature !== undefined) body.temperature = request.temperature;
  if (request.thinking) body.thinking = request.thinking;

  let lastError: Error | undefined;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const response = await fetch(ANTHROPIC_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });

      if (response.ok) {
        return await response.json() as AnthropicResponse;
      }

      const detail = await response.text();
      lastError = new Error(`Anthropic API ${response.status} [model=${request.model}]: ${detail}`);

      // Retry on transient errors only
      if (response.status === 429 || response.status === 529 || response.status >= 500) {
        const delay = RETRY_BASE_MS * Math.pow(2, attempt - 1);
        console.warn(`[anthropic] ${response.status} on attempt ${attempt}/${maxRetries}, retrying in ${delay}ms`);
        await new Promise((r) => setTimeout(r, delay));
        continue;
      }

      // Non-retryable error (400, 401, 403, etc.)
      throw lastError;
    } catch (err) {
      if (err instanceof DOMException && err.name === "TimeoutError") {
        lastError = new Error(`Anthropic API timeout after ${timeoutMs}ms [model=${request.model}]`);
        console.warn(`[anthropic] Timeout on attempt ${attempt}/${maxRetries}`);
        if (attempt < maxRetries) {
          await new Promise((r) => setTimeout(r, RETRY_BASE_MS * Math.pow(2, attempt - 1)));
          continue;
        }
      } else if (lastError && (err as Error).message === lastError.message) {
        throw err; // Non-retryable error already set above
      } else {
        lastError = err instanceof Error ? err : new Error(String(err));
        throw lastError;
      }
    }
  }

  throw lastError ?? new Error("Anthropic API: max retries exceeded");
}

export function extractText(response: AnthropicResponse): string {
  return response.content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("\n");
}

export function extractThinking(response: AnthropicResponse): string {
  return response.content
    .filter((block) => block.type === "thinking")
    .map((block) => block.thinking ?? "")
    .join("\n");
}

// Batch API support for async pipeline steps (50% discount)
export type BatchRequest = {
  custom_id: string;
  params: AnthropicRequest;
};

export async function submitBatch(requests: BatchRequest[]): Promise<string> {
  const apiKey = getApiKey();

  const response = await fetch(ANTHROPIC_BATCH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({ requests }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Anthropic Batch API ${response.status}: ${detail}`);
  }

  const result = await response.json() as { id: string };
  return result.id;
}

export async function getBatchStatus(batchId: string): Promise<{
  processing_status: string;
  results_url?: string;
}> {
  const apiKey = getApiKey();

  const response = await fetch(`${ANTHROPIC_BATCH_URL}/${batchId}`, {
    method: "GET",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Anthropic Batch Status ${response.status}: ${detail}`);
  }

  return await response.json();
}
