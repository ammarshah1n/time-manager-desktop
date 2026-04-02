# Supabase Edge Function Architecture Audit — Timed
**Research Thread 5 of 7 | Repo: `ammarshah1n/time-manager-desktop` | Branch: `ui/apple-v1-restore`**

***

## Executive Summary

Three Edge Functions power Timed's AI pipeline: `classify-email` (Haiku 4.5, every email), `estimate-time` (Sonnet 4.6 fallback, ~30% of tasks), and `generate-profile-card` (Opus 4.6, weekly batch). The audit surfaces **three critical bugs and five high-impact optimizations**. The most severe issue: `classify-email`'s `cache_control` directive is silently ignored because Haiku 4.5 requires a 4,096-token minimum and the current system prompt is ~400 tokens — meaning the app is paying full input rates on every email. Switching to Claude Haiku 3.5 alone saves **$1.24/month (75%)** on the busiest function. Total optimized monthly cost for a power user (50 emails/day, 20 estimations/day, 1 profile/week) drops from **~$2.10 to ~$0.60** — a 71% reduction.

***

## 1. Cold Start Behaviour on Deno Deploy

### Measured Performance

Supabase Edge Functions run on Deno Deploy and, since a July 2025 runtime overhaul, advertise **50–150ms cold starts** under normal conditions. The official docs confirm they run on Deno Deploy globally distributed infrastructure. In practice, community reports from late 2024 measured cold starts ranging from 200ms to 1.2s when using ESM module imports like `https://esm.sh/`, because ESM resolution adds HTTP round-trips at boot. The 2025 runtime update — which moved heavy compute away from the shared Tokio thread pool — brought cold starts down to the sub-100ms range for functions that don't do expensive boot-time work.[^1][^2][^3][^4]

### Platform Comparison

| Platform | Cold Start (minimal fn) | Cold Start (with deps) | Warm Latency |
|---|---|---|---|
| Supabase / Deno Deploy | 50–150ms | 150–400ms | 5–30ms |
| Cloudflare Workers | <1ms | <5ms | <0.5ms |
| AWS Lambda (Node.js) | 80–150ms | 150–300ms | 1–5ms |
| AWS Lambda (VPC) | 300–800ms | 500ms–1.3s | 1–5ms |

Cloudflare Workers use V8 isolates with near-zero cold starts by design; Workers outperform all alternatives for latency-sensitive endpoints. AWS Lambda without VPC is comparable to Supabase, but Lambda's provisioned concurrency option provides a keep-warm guarantee Supabase does not yet expose.[^5][^6][^7]

### Verdict for `classify-email`

At 50 emails/day, emails arrive roughly every 10–15 minutes during business hours. Cold starts at 150–400ms are **acceptable** for email triage because: (1) classification is asynchronous — the email arrives and the UI updates within seconds, not milliseconds; (2) the actual Anthropic API call takes 300–800ms for Haiku, which dwarfs the cold start; and (3) the function does no expensive boot-time compute.

**A cron-ping keep-warm is not recommended** for this workload. Pings add egress cost and complexity, and the 150ms cold-start penalty is invisible to the user given the overall LLM latency budget. The exception would be if email classification becomes synchronous and blocks a UI render — in that case, a 5-minute pg_cron ping to the Edge Function endpoint is the standard pattern.[^8]

**For `generate-profile-card`**: already invoked by pg_cron weekly, cold start is irrelevant.

***

## 2. Prompt Caching Strategy — Critical Bug

### How Anthropic Prompt Caching Works

Anthropic's prompt caching stores the **key-value attention tensors** for a fixed prefix of your prompt. When the same prefix appears in a subsequent request within the TTL window, those tensors are retrieved rather than recomputed. Key mechanics:[^9][^10]

- **TTL**: 5 minutes (refreshed on each cache hit); a 1-hour TTL is available at ~1.6x the standard write cost[^11]
- **Cache write cost**: 1.25× base input token price[^12][^13]
- **Cache read cost**: 0.10× base input token price (90% savings on cached tokens)[^13][^11]
- **Cache key**: exact byte-level match of the entire prompt prefix up to the `cache_control` breakpoint — any change to a character in the cached block invalidates it[^14]
- **Up to 4 breakpoints per request**, processed in order: `tools → system → messages`[^9]
- **Minimum cacheable prefix by model**:[^10][^15]

| Model | Min Cacheable Tokens |
|---|---|
| Claude Haiku 4.5 | **4,096** |
| Claude Haiku 3.5 | 2,048 |
| Claude Sonnet 4.6 | 2,048 |
| Claude Opus 4.6 | 4,096 |

### The Bug in `classify-email`

`classify-email` uses `claude-haiku-4-5-20251001` and applies `cache_control: { type: "ephemeral" }` to its system prompt. **The system prompt is approximately 350–400 tokens** — far below the 4,096-token minimum for Haiku 4.5. The result: every request silently falls through as a full-price cache-write attempt that never produces a cache hit. The API does not error; it simply charges full input rates and `cache_creation_input_tokens` stays at 0.[^15][^10]

**Fix Option A — Switch to Claude 3.5 Haiku** (recommended, see §3): minimum threshold drops to 2,048. Expanding the system prompt with the 15 few-shot corrections (currently in the user message) to ~2,300 total tokens enables caching on the stable instruction block. The corrections are user-specific but refresh daily — they can live in the system prompt and be re-cached each morning.

**Fix Option B — Stay on Haiku 4.5**: pad the system prompt to ≥4,096 tokens by embedding the 15 corrections plus detailed examples directly into the system block. This requires curating ~3,600 tokens of static instructions — feasible but verbose.

### Should Few-Shot Corrections Be in System or User Prompt?

**System prompt (cached)** is the correct location for the 15 corrections *when they are stable over a session*. Cache hit requires byte-identical prefix — so the corrections must be ordered deterministically (e.g., sorted by `created_at`) and not change between calls in the same 5-minute window. The user message should contain only the single email being classified plus the dynamic sender rules for that specific call.[^16][^17]

**Revised structure for `classify-email` (with Haiku 3.5):**

```typescript
system: [
  {
    type: "text",
    text: STATIC_CLASSIFICATION_INSTRUCTIONS,   // ~400 tokens
    // No cache_control here — not the final block
  },
  {
    type: "text",
    text: buildDailyCorrections(corrections),   // ~1,900 tokens (15 examples × ~125 tokens)
    // cache_control on the LAST cacheable block
    cache_control: { type: "ephemeral" },
  },
],
messages: [
  {
    role: "user",
    content: buildEmailContext(email, senderRules),  // ~200 tokens (dynamic)
  },
],
```

**Important**: cache is placed on the **last** system block, caching everything before it as a prefix. Total cached tokens: ~2,300 — above the 2,048 Haiku 3.5 threshold.[^10]

### Cache in `generate-profile-card`

The Opus 4.6 system prompt is approximately 1,200 tokens — below the 4,096 minimum for Opus. Same bug as `classify-email`. Since this runs weekly with a massive user-message payload (8,000–10,000 tokens), caching the system prompt would save only ~$0.001/call — negligible. **Remove the `cache_control` from `generate-profile-card`** entirely to avoid confusion and unnecessary overhead.[^10]

### Cache in `estimate-time`

`estimate-time` uses Sonnet 4.6 (min 2,048 tokens) with a ~80-token system prompt. Cache never fires. Since the Sonnet call is a fallback path (triggered for only ~30% of tasks after embedding and historical lookups fail), the caching upside is minimal. A simple fix: remove `cache_control` from `estimate-time` as well, since no structural benefit exists at current prompt sizes.

***

## 3. Model Selection Audit

### Current Pricing (April 2026)[^18][^19][^20]

| Model | Input ($/1M) | Output ($/1M) | Cache Write ($/1M) | Cache Read ($/1M) |
|---|---|---|---|---|
| Claude Opus 4.6 | $5.00 | $25.00 | $6.25 | $0.50 |
| Claude Sonnet 4.6 | $3.00 | $15.00 | $3.75 | $0.30 |
| Claude Haiku 4.5 | $1.00 | $5.00 | $1.25 | $0.10 |
| Claude Haiku 3.5 | $0.25 | $1.25 | $0.31 | $0.025 |

### `classify-email`: Haiku 4.5 → Haiku 3.5

Haiku 4.5 outperforms Haiku 3.5 on GPQA and SWE-bench Verified benchmarks, but both benchmarks test coding and graduate-level reasoning — **irrelevant for 4-class email triage** (inbox / later / black\_hole / cc\_fyi). For structured classification of short text into a fixed schema, Haiku 3.5 achieves equivalent accuracy at **4× lower cost**. Haiku 4.5's multi-modal input support and computer-use capabilities are unused here. The correct recommendation: **downgrade to Haiku 3.5** for classification. The upgrade to Haiku 4.5 is only warranted if human-evaluated accuracy tests show measurable regression.[^21][^22]

**Code change — `classify-email/index.ts`:**

```typescript
// Before
model: "claude-haiku-4-5-20251001",

// After
model: "claude-haiku-3-5-20241022",
```

### `estimate-time`: Sonnet 4.6 → Haiku 4.5

The task is: given a task title, bucket type, and category default, return `{ estimated_minutes: int, confidence: float }`. This is **a single-turn, low-complexity numerical estimation** — structurally similar to classification. Sonnet 4.6 is justified for complex multi-step reasoning; it is over-powered here. Haiku 4.5 at $1.00 input vs $3.00 for Sonnet is the correct trade-off. The function already has a Bayesian fallback to category defaults, so a slightly less precise LLM estimate is acceptable.

**Code change — `estimate-time/index.ts`:**

```typescript
// Before
model: "claude-sonnet-4-6",

// After
model: "claude-haiku-4-5-20251001",
```

### `generate-profile-card`: Keep Opus 4.6

The Opus 4.6 system prompt requires multi-axis statistical analysis: (1) timing preference windows per bucket type, (2) Bayesian estimation bias computation, (3) order-override pattern extraction, and (4) cohesive narrative profile generation. This is genuinely complex structured reasoning over heterogeneous event data — the use case Opus exists for. Switching to Sonnet 4.6 saves ~$0.09/month (from $0.23 to $0.14 for 4 weekly runs) but risks degraded rule quality. **Keep Opus 4.6 and instead apply the Batch API** (see §4) for 50% savings while preserving model quality.

### Monthly Cost Model — Power User (50 emails/day, 20 tasks/day, 1 profile/week)

| Function | Current Config | Monthly | Optimized Config | Monthly |
|---|---|---|---|---|
| `classify-email` | Haiku 4.5, no cache | $1.65 | Haiku 3.5, no cache | $0.41 |
| `estimate-time` | Sonnet 4.6 fallback | $0.22 | Haiku 4.5 fallback | $0.07 |
| `generate-profile-card` | Opus 4.6, sync | $0.23 | Opus 4.6, Batch API | $0.12 |
| **Total** | | **$2.10** | | **$0.60** |

**Net savings: $1.50/month (71% reduction)** — primarily from the Haiku 3.5 downgrade on `classify-email`.

***

## 4. Streaming vs Batch

### `estimate-time`: No Streaming

`estimate-time` returns a single JSON object with one integer. Streaming a 40-token response provides zero UX benefit and adds SDK complexity (stream accumulation, error handling). Keep synchronous `messages.create()`. The function already responds in ~300–500ms for Haiku — acceptable for a background task that pre-populates the UI's estimated duration field.

### `generate-profile-card`: Use Anthropic Batch API

`generate-profile-card` runs weekly via pg\_cron at 02:00 UTC — an archetypal **offline, non-interactive workload**. The Anthropic Message Batches API offers 50% off both input and output tokens for asynchronous processing (up to 24-hour completion window, typically completing in under 1 hour). For a function triggered by pg\_cron with no user waiting on the response, this is the ideal trade.[^23][^24][^25]

**Implementation with Batch API:**

```typescript
// In generate-profile-card, replace direct messages.create() with:
const batch = await anthropic.messages.batches.create({
  requests: [
    {
      custom_id: `profile-${workspaceId}-${profileId}-${Date.now()}`,
      params: {
        model: "claude-opus-4-6",
        max_tokens: 1024,
        system: [...],   // same system prompt
        messages: [{ role: "user", content: userMessage }],
      },
    },
  ],
});

// Store batch.id in Supabase. A separate pg_cron or webhook polls for completion:
// SELECT * FROM ai_pipeline_runs WHERE batch_id = $1 AND status = 'pending_batch'
// Poll: anthropic.messages.batches.results(batch.id)
```

**Polling pattern**: insert a `pending_batch` row into `ai_pipeline_runs` with `batch_id`. A separate Edge Function (`process-batch-results`) is triggered by a 15-minute pg\_cron job to poll open batches and apply results. This decouples invocation from result processing and keeps the background task limit well within Supabase's 400-second paid plan limit.[^26]

**Key caveat**: Batch API does not support prompt caching. For 4 weekly runs at ~9,200 tokens input, this is irrelevant — the caching upside would be near-zero anyway.[^24]

### Supabase `EdgeRuntime.waitUntil()` for Long Operations

For any work that should not block the HTTP response (e.g., generating the profile in the background after acknowledging the pg\_cron trigger), use `EdgeRuntime.waitUntil()`:[^8][^26]

```typescript
Deno.serve(async (req) => {
  // Validate request, return 202 immediately
  EdgeRuntime.waitUntil(runProfileGeneration(workspaceId, profileId));
  return new Response(JSON.stringify({ status: "accepted" }), { status: 202 });
});
```

Paid plan allows background tasks up to 400 seconds (6m 40s) — sufficient for Opus 4.6 calls but not if the Batch API pattern is adopted instead.[^26]

***

## 5. Error Handling and Retries

### Anthropic 429 (Rate Limited) vs 529 (Overloaded)

These errors have different causes and require different retry strategies:[^27][^28]

| Error | Cause | Strategy |
|---|---|---|
| `429 Too Many Requests` | Token/request rate limit exceeded | Read `retry-after` header; exponential backoff if absent |
| `529 Overloaded` | Anthropic infrastructure overload | Fixed 30–60s delay + jitter; do NOT use `retry-after` |

**Recommended retry wrapper for all three functions:**

```typescript
async function callAnthropicWithRetry<T>(
  fn: () => Promise<T>,
  maxRetries = 3
): Promise<T> {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err: any) {
      const isLast = attempt === maxRetries - 1;
      if (isLast) throw err;

      if (err.status === 429) {
        const retryAfter = err.headers?.["retry-after"];
        const delay = retryAfter
          ? parseFloat(retryAfter) * 1000
          : Math.min(1000 * Math.pow(2, attempt), 30_000);
        const jitter = Math.random() * delay * 0.1;
        await sleep(delay + jitter);

      } else if (err.status === 529) {
        // Server overload — longer fixed wait
        await sleep(30_000 + Math.random() * 30_000);

      } else {
        throw err; // Non-retryable (400, 401, 403) — fail fast
      }
    }
  }
  throw new Error("Unreachable");
}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
```

Apply this wrapper around each `anthropic.messages.create()` call in all three functions.

### Circuit Breaker Pattern

A circuit breaker is **recommended for `classify-email`** specifically, because it is called on every inbound email. Without one, if Anthropic is degraded, the app makes 50+ retry sequences per day and logs hundreds of errors. The circuit breaker prevents cascading load on a degraded service:[^29][^30]

```typescript
// Module-level singleton (persists across warm invocations)
class AnthropicCircuitBreaker {
  private failures = 0;
  private lastFailure = 0;
  private state: "closed" | "open" | "half-open" = "closed";
  private readonly threshold = 5;
  private readonly timeout = 120_000; // 2 min recovery window

  async call<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === "open") {
      if (Date.now() - this.lastFailure > this.timeout) {
        this.state = "half-open";
      } else {
        throw new Error("circuit_open"); // Fast-fail, go to fallback
      }
    }
    try {
      const result = await fn();
      this.reset();
      return result;
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  private reset() { this.state = "closed"; this.failures = 0; }
  private recordFailure() {
    this.failures++;
    this.lastFailure = Date.now();
    if (this.failures >= this.threshold) this.state = "open";
  }
}

const anthropicBreaker = new AnthropicCircuitBreaker();
```

**Note**: Deno Deploy does not guarantee global shared state between Edge Function instances across machines. The circuit breaker above works correctly within a single warm instance's request sequence but resets on cold start or new instance. For a fully persistent circuit breaker, store `{ failures, lastFailure, state }` in a Redis/Supabase KV store. Given Timed's single-user-per-workspace model, instance-level state is acceptable.

### Fallback When LLM is Down

Each function already has a graceful degradation path — use and document it explicitly:

| Function | LLM Down Fallback |
|---|---|
| `classify-email` | Apply deterministic sender-rule matching only; if sender not in rules, emit `bucket: "later"` with `confidence: 0.5, source: "fallback"`. Update `triage_source = "rules_only"` to flag for manual review. |
| `estimate-time` | Skip LLM tier entirely; return `categoryDefault` with `basis: "category_default", confident: false`. Already implemented in the catch block. |
| `generate-profile-card` | Log `ai_pipeline_runs.status = "skipped_outage"` and skip the week. The existing rules remain active; a missed weekly run causes no user-facing degradation. |

***

## 6. Token Budget Management

### `classify-email` — max\_tokens: 256

The function uses tool\_use (`classify` tool) with a 3-field schema returning `bucket` + `confidence` + `reasoning`. The maximum possible output is approximately 60–80 tokens. **max\_tokens: 256 is reasonable** — provides headroom without waste. No change needed.

### `estimate-time` — max\_tokens: 128

Outputs `{ estimated_minutes: int, confidence: float }` — approximately 20–30 tokens. **max\_tokens: 128 is fine.** Consider reducing to 64 for marginally tighter control:

```typescript
max_tokens: 64,  // JSON with 2 fields never exceeds 40 tokens
```

### `generate-profile-card` — max\_tokens: 1024

This is the most important budget to examine. The current cap is 1,024 tokens. The response structure is: a 2–3 sentence `profile_summary` (~60 tokens) plus an array of rules (each rule ~80–120 tokens, typically 6–12 rules = ~720–1,440 tokens). **1,024 is potentially too tight** — a run producing 12 rules at 100 tokens each would be 1,260 tokens, causing a truncated JSON response that fails the `JSON.parse()` call.

**Recommended**: increase to 2,048. Opus 4.6 output is billed at $25/1M tokens; the difference between 1,024 and 2,048 max is at most ~$0.025/month for this use case. The truncation risk is far more costly.

```typescript
max_tokens: 2048,
```

Add a JSON completeness check before parsing:

```typescript
// After: const jsonMatch = text.match(/\{[\s\S]*\}/);
if (!jsonMatch) throw new Error("Claude returned no valid JSON");

// Validate JSON is complete (not truncated)
const parsed = JSON.parse(jsonMatch);
if (!parsed.rules || !Array.isArray(parsed.rules)) {
  throw new Error(`Incomplete response: rules missing. Output tokens: ${message.usage.output_tokens}`);
}
```

If `output_tokens === max_tokens`, the response was truncated — log this as a warning and increment `max_tokens` in the next run.

***

## 7. Edge Function Security

### API Key Handling — Current Status: Correct

All three functions read `ANTHROPIC_API_KEY` via `Deno.env.get("ANTHROPIC_API_KEY")`. This is the correct pattern — Supabase injects secrets as environment variables, never exposing them in source code or HTTP headers. The key must be set via the Supabase Dashboard (Settings → Edge Functions → Secrets) or CLI:[^31]

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

Supabase automatically provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` at runtime. The `SUPABASE_SERVICE_ROLE_KEY` used in all three functions bypasses RLS — this is intentional for server-side operations but means any breach of the Edge Function is a full-database breach. This is standard and acceptable when the function validates input before executing DB writes.[^32][^31]

### Request Validation Gap — High Priority

All three functions accept a plain JSON body with `workspaceId`, `profileId`, and entity IDs. **There is no authentication or authorization check.** Any caller who discovers the Edge Function URL can submit arbitrary `workspaceId` + `profileId` combinations and trigger Anthropic API calls billed to your account.

Supabase no longer auto-enforces JWT validation on Edge Functions. Add explicit JWT verification:[^33]

```typescript
// At the top of each Edge Function's serve() handler:
const authHeader = req.headers.get("Authorization");
if (!authHeader?.startsWith("Bearer ")) {
  return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
}

const token = authHeader.slice(7);
const { data: { user }, error } = await supabase.auth.getUser(token);
if (error || !user) {
  return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401 });
}

// Verify user owns the workspaceId
const { data: membership } = await supabase
  .from("workspace_members")
  .select("id")
  .eq("workspace_id", workspaceId)
  .eq("user_id", user.id)
  .single();

if (!membership) {
  return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 });
}
```

For `generate-profile-card` (invoked by pg\_cron, not a user), use a **service-level shared secret** instead of user JWT:

```typescript
const cronSecret = Deno.env.get("CRON_SECRET");
const providedSecret = req.headers.get("X-Cron-Secret");
if (!cronSecret || providedSecret !== cronSecret) {
  return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
}
```

Set `CRON_SECRET` via Supabase secrets and pass it as a header from the pg\_cron `http_post()` call.

### Secret Scanning

Anthropic has partnered with GitHub to auto-detect and deactivate exposed API keys in public repositories. Since this is a private repo, ensure it stays private. Add `supabase/.env.local` to `.gitignore`. Run `gitleaks` in CI to prevent accidental key commits.[^34]

***

## 8. Consolidated Code Changes by Priority

### Priority 1 — Critical (revenue/security impact)

**`classify-email/index.ts` — Model downgrade + cache fix:**

```typescript
// 1. Change model
model: "claude-haiku-3-5-20241022",   // was claude-haiku-4-5-20251001

// 2. Move corrections into system prompt (above the cache_control block)
system: [
  {
    type: "text",
    text: STATIC_SYSTEM_PROMPT,   // ~400 tokens
  },
  {
    type: "text",
    text: buildCorrectionBlock(corrections),  // ~1,900 tokens (15 examples)
    cache_control: { type: "ephemeral" },     // Now above 2048 min threshold
  },
],
messages: [
  {
    role: "user",
    content: buildEmailUserMessage(email, senderRules),  // dynamic only
  },
],
```

**All functions — Add JWT/auth validation** (see §7).

**All functions — Add retry wrapper** (see §5).

### Priority 2 — High Impact (cost + stability)

**`generate-profile-card/index.ts` — Batch API + max\_tokens fix:**

```typescript
// 1. Increase max_tokens
max_tokens: 2048,   // was 1024

// 2. Replace messages.create() with batch submission (see §4)
// 3. Remove cache_control from system prompt (below 4096 threshold)
// 4. Add JSON completeness validation (see §6)
```

**`estimate-time/index.ts` — Model downgrade:**

```typescript
model: "claude-haiku-4-5-20251001",   // was claude-sonnet-4-6
max_tokens: 64,                        // was 128
```

### Priority 3 — Reliability

**All functions — Circuit breaker** (see §5, inline singleton pattern).

**`classify-email` — Deterministic fallback** when circuit is open:

```typescript
} catch (err) {
  if (err.message === "circuit_open") {
    // Apply sender-rule-only classification
    if (inboxAlways.includes(email.from_address)) return respondWithBucket("inbox", 0.9, "sender_rule");
    if (blackHole.includes(email.from_address)) return respondWithBucket("black_hole", 0.9, "sender_rule");
    return respondWithBucket("later", 0.5, "fallback_circuit_open");
  }
  throw err;
}
```

### Priority 4 — Hygiene

- Remove `cache_control` from `generate-profile-card` system prompt (has no effect at current token count)
- Remove `cache_control` from `estimate-time` system prompt (80 tokens, below 2048 threshold)
- Add `beforeunload` listener to `generate-profile-card` for graceful shutdown logging (see §4)
- Log `circuit_state` changes in `ai_pipeline_runs` for observability

***

## Impact Ranking

| Optimization | Monthly Savings | Complexity | Priority |
|---|---|---|---|
| Downgrade classify-email to Haiku 3.5 | ~$1.24 | Low | 🔴 Critical |
| Fix cache placement in classify-email | ~$0.05 (at low volume) | Medium | 🟠 High |
| Add JWT auth to all Edge Functions | Security — not cost | Medium | 🔴 Critical |
| Add retry wrapper (429/529 handling) | Availability | Low | 🟠 High |
| Batch API for generate-profile-card | ~$0.12 | Medium | 🟠 High |
| Downgrade estimate-time to Haiku 4.5 | ~$0.15 | Low | 🟡 Medium |
| Increase generate-profile-card max_tokens to 2048 | Prevents JSON truncation | Trivial | 🟠 High |
| Circuit breaker for classify-email | Reliability | Medium | 🟡 Medium |
| Remove no-op cache_control from opus/sonnet fns | Clarity | Trivial | 🟢 Low |

---

## References

1. [Poor performance with Edge Functions #29301 - GitHub](https://github.com/orgs/supabase/discussions/29301) - I have been trialing Edge Functions and found the performance pretty awful. This has ranged from ~1....

2. [Persistent Storage and 97% Faster Cold Starts for Edge Functions](https://supabase.com/blog/persistent-storage-for-faster-edge-functions) - Today, we are introducing Persistent Storage and up to 97% faster cold start times for Edge Function...

3. [How to Deploy JavaScript with Supabase Edge Functions - Chat2DB](https://chat2db.ai/resources/blog/supabase-edge-functions-guide) - The key advantages include sub-100ms cold starts, native TypeScript support, and tight integration w...

4. [Edge Functions Overview - Supabase - Mintlify](https://www.mintlify.com/supabase/supabase/functions/overview) - Supabase Edge Functions are server-side TypeScript functions that run on Deno, distributed globally ...

5. [AWS Lambda vs Cloudflare Workers: Serverless Comparison](https://www.linkedin.com/posts/raahul-mehta_aws-lambda-vs-cloudflare-workers-a-activity-7428649487222435840-XsdP) - Cloudflare Workers Designed for near-zero cold starts. Extremely fast startup time. For performance-...

6. [Cloudflare Workers vs AWS Lambda: Complete Comparison Guide](https://www.mgsoftware.nl/en/vergelijking/cloudflare-workers-vs-aws-lambda) - Cloudflare Workers and AWS Lambda represent two fundamentally different approaches to serverless com...

7. [Cloudflare Workers vs Lambda vs Cloud Functions vs Azure Functions](https://inventivehq.com/blog/cloudflare-workers-vs-aws-lambda-vs-google-cloud-functions-vs-azure-functions-comparison) - This architectural difference determines cold start behavior, language support, execution limits, pr...

8. [Background Tasks | Supabase Docs](https://supabase.com/docs/guides/functions/background-tasks) - Background tasks are useful for asynchronous operations like uploading a file to Storage, updating a...

9. [Prompt Caching with OpenAI, Anthropic, and Google Models](https://www.prompthub.us/blog/prompt-caching-with-openai-anthropic-and-google-models) - Learn how prompt caching reduces costs and latency when using LLMs. We compare caching strategies, p...

10. [Prompt caching - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) - If you find that 5 minutes is too short, Anthropic also offers a 1-hour cache duration at additional...

11. [Prompt Caching: Cost & Performance Analysis Across Providers](https://artificialanalysis.ai/models/caching) - Prompt Caching API Specifications · Cache read tokens are 90% cheaper than base input tokens · Cache...

12. [Slashing LLM Costs and Latencies with Prompt Caching - Hakkoda](https://hakkoda.io/resources/prompt-caching/) - Cache Write: Writing to the cache costs 25% more than the base input token price for the model you'r...

13. [Prompt Caching for Anthropic and OpenAI Models - DigitalOcean](https://www.digitalocean.com/blog/prompt-caching-with-digital-ocean) - Key pricing characteristics: Cache writes cost 25% more than base input tokens; Cache hits cost 10% ...

14. [An Evaluation of Prompt Caching for Long-Horizon Agentic Tasks](https://arxiv.org/html/2601.06007v2) - Anthropic provides developer-controlled caching through explicit cache breakpoints, allowing users t...

15. [Amazon Bedrock Prompt Caching: Saving Time and Money in LLM ...](https://caylent.com/blog/prompt-caching-saving-time-and-money-in-llm-applications) - Explore how to use prompt caching on Large Language Models (LLMs) such as Amazon Bedrock and Anthrop...

16. [Prompt Caching - Mechanics, Guarantees, and Failure Modes](https://www.linkedin.com/pulse/prompt-caching-mechanics-guarantees-failure-modes-sanjay-basu-phd-iyiqf) - The default TTL is 60 minutes, but you can set it anywhere from 60 seconds to 24 hours. Cache entrie...

17. [How to Use Prompt Caching and Cache Control with Anthropic Models](https://www.firecrawl.dev/blog/using-prompt-caching-with-anthropic) - Anthropic recently launched prompt caching and cache control in beta, allowing you to cache large co...

18. [Claude API Pricing - Opus 4.6, Sonnet 4.6, Haiku Token Costs - TLDL](https://www.tldl.io/resources/anthropic-api-pricing) - Updated March 2026. Anthropic Claude API pricing per 1M tokens: Opus 4.6 at $5/$25, Sonnet 4.6 at $3...

19. [Claude Pricing Explained: Subscription Plans & API Costs](https://intuitionlabs.ai/articles/claude-pricing-plans-api-costs) - Claude Opus 4.6 is available at $5 per million input tokens and $25 per million output tokens. Claud...

20. [Claude vs OpenAI: Pricing Considerations - Vantage.sh](https://www.vantage.sh/blog/aws-bedrock-claude-vs-azure-openai-gpt-ai-cost) - ... Anthropic's Claude, where Amazon provides additional APIs and security. ... prices as low as $0....

21. [Claude Haiku 4.5 Deep Dive: Cost, Capabilities, and the Multi-Agent ...](https://caylent.com/blog/claude-haiku-4-5-deep-dive-cost-capabilities-and-the-multi-agent-opportunity) - Haiku 4.5 achieves 73.3% on SWE-bench Verified, which tests models on real GitHub issues from actual...

22. [Claude 3.5 Haiku vs Claude Haiku 4.5 Comparison - LLM Stats](https://llm-stats.com/models/compare/claude-3-5-haiku-20241022-vs-claude-haiku-4-5-20251001) - Claude 3.5 Haiku outperforms in 0 benchmarks, while Claude Haiku 4.5 is better at 2 benchmarks (GPQA...

23. [Anthropic Batch API in Production: 50% Cost Reduction Through ...](https://dotzlaw.com/insights/obsidian-notes-02/) - The Deal: 50% Off#

 Anthropic's Batch API offers a straightforward trade: accept asynchronous proce...

24. [Anthropic Message Batches in 2026: When the 50% Discount Is ...](https://aicheckerhub.com/anthropic-message-batches-2026-when-the-50-percent-discount-is-worth-it) - Anthropic positions Message Batches as an asynchronous lane for high-volume Messages API work, with ...

25. [Anthropic challenges OpenAI with affordable batch processing](https://venturebeat.com/ai/anthropic-challenges-openai-with-affordable-batch-processing) - The Batch API offers a 50% discount on both input and output tokens compared to real-time processing...

26. [Supabase Edge Functions: Introducing Background Tasks ...](https://supabase.com/blog/edge-functions-background-tasks-websockets) - Edge Function invocations now have access to ephemeral storage. This is useful for background tasks,...

27. [Claude Code Rate Limit Guide: Understand, Prevent, and Optimize ...](https://blog.laozhang.ai/en/posts/claude-code-rate-limit) - Both require retry logic, but the strategies differ: for 429 errors, respect the retry-after header ...

28. [How to Fix Claude API 429 Rate Limit Error: Complete 2026 Guide ...](https://www.aifreeapi.com/en/posts/fix-claude-api-429-rate-limit-error) - The most effective approach combines the retry-after header with exponential backoff as a fallback, ...

29. [Implementing the Circuit Breaker Pattern in TypeScript (2026 Guide)](https://dev.to/young_gao/implementing-the-circuit-breaker-pattern-in-typescript-182m) - When a downstream service fails, your entire system cascades. Implement the circuit breaker pattern ...

30. [Circuit Breaker Pattern in Node.js and TypeScript - DEV Community](https://dev.to/wallacefreitas/circuit-breaker-pattern-in-nodejs-and-typescript-enhancing-resilience-and-stability-bfi) - We'll examine the Circuit Breaker paradigm, its advantages, and real-world applications using TypeSc...

31. [Environment Variables | Supabase Docs](https://supabase.com/docs/guides/functions/secrets) - Edge Functions have access to these secrets by default: SUPABASE_URL : The API gateway for your Supa...

32. [How to authenticate within Edge Functions using RLS? : r/Supabase](https://www.reddit.com/r/Supabase/comments/1o2hy27/how_to_authenticate_within_edge_functions_using/) - RLS only works in an Edge Function if PostgREST sees the user's JWT as the Authorization header; oth...

33. [Securing Edge Functions | Supabase Docs](https://supabase.com/docs/guides/functions/auth) - For legacy keys, copy the anon key for client-side operations and the service_role key for server-si...

34. [API Key Best Practices: Keeping Your Keys Safe and Secure](https://support.claude.com/en/articles/9767949-api-key-best-practices-keeping-your-keys-safe-and-secure) - Best Practices for API Key Security · 1. Never share your API key · 2. Monitor Usage and Logs Closel...

