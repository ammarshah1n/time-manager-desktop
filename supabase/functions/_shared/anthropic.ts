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

export async function callAnthropic(request: AnthropicRequest): Promise<AnthropicResponse> {
  const apiKey = getApiKey();

  const body: Record<string, unknown> = {
    model: request.model,
    messages: request.messages,
    max_tokens: request.max_tokens,
  };

  if (request.system) body.system = request.system;
  if (request.temperature !== undefined) body.temperature = request.temperature;
  if (request.thinking) body.thinking = request.thinking;

  const response = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Anthropic API ${response.status}: ${detail}`);
  }

  return await response.json() as AnthropicResponse;
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
