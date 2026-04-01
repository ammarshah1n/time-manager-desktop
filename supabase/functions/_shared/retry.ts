// _shared/retry.ts
// Retry wrapper with backoff + Circuit breaker for Anthropic API calls.
// Handles 429 (rate limit — respects Retry-After) and 529 (overloaded — 30s delay).

/**
 * Retry wrapper for async operations.
 * - Max 3 attempts by default.
 * - On 429: waits for Retry-After header value (or 10s default).
 * - On 529: waits 30s before retry.
 * - Other errors: exponential backoff (1s, 2s).
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options?: { maxAttempts?: number; label?: string }
): Promise<T> {
  const maxAttempts = options?.maxAttempts ?? 3;
  const label = options?.label ?? "withRetry";

  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err: unknown) {
      lastError = err;

      if (attempt === maxAttempts) break;

      const status = getErrorStatus(err);
      let delayMs: number;

      if (status === 429) {
        // Rate limited — respect Retry-After or default 10s
        const retryAfter = getRetryAfterSeconds(err);
        delayMs = retryAfter ? retryAfter * 1000 : 10_000;
        console.warn(`[${label}] 429 rate limited, retry in ${delayMs}ms (attempt ${attempt}/${maxAttempts})`);
      } else if (status === 529) {
        // Overloaded — fixed 30s delay
        delayMs = 30_000;
        console.warn(`[${label}] 529 overloaded, retry in 30s (attempt ${attempt}/${maxAttempts})`);
      } else if (status && status >= 500) {
        // Server error — exponential backoff
        delayMs = 1000 * Math.pow(2, attempt - 1);
        console.warn(`[${label}] ${status} server error, retry in ${delayMs}ms (attempt ${attempt}/${maxAttempts})`);
      } else {
        // Non-retryable error — throw immediately
        throw err;
      }

      await sleep(delayMs);
    }
  }

  throw lastError;
}

// ============================================================
// Circuit Breaker — prevents hammering a failing upstream
// ============================================================

export class CircuitBreaker {
  private failures = 0;
  private lastFailureTime = 0;
  private state: "closed" | "open" | "half-open" = "closed";

  constructor(
    private readonly threshold: number = 5,
    private readonly resetMs: number = 2 * 60 * 1000, // 2 minutes
    private readonly label: string = "CircuitBreaker"
  ) {}

  /**
   * Check if the circuit allows a request through.
   * Returns true if the call should proceed, false if the circuit is open.
   */
  allowRequest(): boolean {
    if (this.state === "closed") return true;

    if (this.state === "open") {
      // Check if reset period has elapsed → move to half-open
      if (Date.now() - this.lastFailureTime >= this.resetMs) {
        this.state = "half-open";
        console.log(`[${this.label}] Circuit half-open — allowing probe request`);
        return true;
      }
      return false;
    }

    // half-open: allow one probe
    return true;
  }

  /** Record a successful call — resets the breaker. */
  recordSuccess(): void {
    if (this.state !== "closed") {
      console.log(`[${this.label}] Circuit closed — upstream recovered`);
    }
    this.failures = 0;
    this.state = "closed";
  }

  /** Record a failed call — may trip the breaker. */
  recordFailure(): void {
    this.failures++;
    this.lastFailureTime = Date.now();

    if (this.state === "half-open") {
      // Probe failed — back to open
      this.state = "open";
      console.warn(`[${this.label}] Half-open probe failed — circuit re-opened`);
      return;
    }

    if (this.failures >= this.threshold) {
      this.state = "open";
      console.warn(`[${this.label}] Circuit opened after ${this.failures} failures — blocking for ${this.resetMs / 1000}s`);
    }
  }

  /** Current state for diagnostics. */
  getState(): { state: string; failures: number } {
    return { state: this.state, failures: this.failures };
  }
}

// ============================================================
// Helpers
// ============================================================

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Extract HTTP status from various error shapes (Anthropic SDK, fetch, etc). */
function getErrorStatus(err: unknown): number | null {
  if (err && typeof err === "object") {
    // Anthropic SDK errors have .status
    if ("status" in err && typeof (err as Record<string, unknown>).status === "number") {
      return (err as Record<string, unknown>).status as number;
    }
    // Some errors wrap a response
    if ("response" in err) {
      const resp = (err as Record<string, unknown>).response;
      if (resp && typeof resp === "object" && "status" in resp) {
        return (resp as Record<string, unknown>).status as number;
      }
    }
  }
  return null;
}

/** Extract Retry-After header value in seconds from error, if present. */
function getRetryAfterSeconds(err: unknown): number | null {
  if (err && typeof err === "object" && "headers" in err) {
    const headers = (err as Record<string, unknown>).headers;
    if (headers && typeof headers === "object") {
      // Anthropic SDK exposes headers as a plain object or Headers instance
      const getVal = (h: unknown, key: string): string | null => {
        if (h instanceof Headers) return h.get(key);
        if (h && typeof h === "object" && key in h) return String((h as Record<string, unknown>)[key]);
        return null;
      };
      const val = getVal(headers, "retry-after");
      if (val) {
        const parsed = parseInt(val, 10);
        return isNaN(parsed) ? null : parsed;
      }
    }
  }
  return null;
}
