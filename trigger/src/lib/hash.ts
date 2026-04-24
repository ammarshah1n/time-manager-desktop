import { createHash } from "node:crypto";

/** Deterministic SHA-256 hex hash of any JSON-serialisable value. */
export function sha256Hex(value: unknown): string {
  const json = typeof value === "string" ? value : JSON.stringify(value);
  return createHash("sha256").update(json).digest("hex");
}

/**
 * Approximate token count by character ratio. Anthropic has no client-side
 * tokenizer in Node; for the cache-control threshold we only need a rough
 * lower bound. 3.5 chars/token is a conservative English estimate.
 */
export function approxTokens(text: string): number {
  return Math.ceil(text.length / 3.5);
}
