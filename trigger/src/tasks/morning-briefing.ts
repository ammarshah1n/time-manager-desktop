import { logger, schedules } from "@trigger.dev/sdk";

/**
 * Morning briefing scheduled task.
 *
 * Fires once per day at 05:30 Australia/Adelaide and POSTs an empty body to
 * the `generate-morning-briefing` Supabase Edge Function. The function
 * itself iterates over all executives in `public.executives` and writes one
 * `briefings` row per executive for today's date — this task is the cron
 * arm that wakes it up.
 *
 * Scope:
 * - Service-role auth via SUPABASE_SERVICE_ROLE_KEY.
 * - 15-minute hard cap from trigger.config.ts.
 * - 3-attempt retry policy (default from trigger.config.ts) — handles
 *   transient Anthropic rate limits / Supabase function cold-start hiccups.
 *
 * Cognitive-only rule: this task triggers ONE function call. It never
 * sends mail, books, or contacts anyone. The downstream Edge Function
 * generates a `briefings` row that the Mac app reads passively.
 */

const SCHEDULE_TZ = "Australia/Adelaide";
const SCHEDULE_CRON = "30 5 * * *";

export const morningBriefing = schedules.task({
  id: "morning-briefing",
  cron: { pattern: SCHEDULE_CRON, timezone: SCHEDULE_TZ },
  maxDuration: 900,
  run: async (_payload, { ctx }) => {
    const t0 = Date.now();
    logger.info("morning-briefing starting", {
      runId: ctx.run.id,
      cron: SCHEDULE_CRON,
      timezone: SCHEDULE_TZ,
    });

    const url = process["env"]["SUPABASE_URL"];
    const key = process["env"]["SUPABASE_SERVICE_ROLE_KEY"];
    if (!url) {
      throw new Error("morning-briefing: SUPABASE_URL not set");
    }
    if (!key) {
      throw new Error("morning-briefing: SUPABASE_SERVICE_ROLE_KEY not set");
    }

    const endpoint = `${url}/functions/v1/generate-morning-briefing`;
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });

    const text = await response.text();
    const durationMs = Date.now() - t0;

    if (!response.ok) {
      logger.error("morning-briefing FAILED", {
        alert: true,
        status: response.status,
        statusText: response.statusText,
        body: text.slice(0, 2000),
        durationMs,
      });
      throw new Error(
        `morning-briefing: ${response.status} ${response.statusText}: ${text.slice(0, 500)}`,
      );
    }

    let parsed: unknown = null;
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { raw: text.slice(0, 1000) };
    }

    logger.info("morning-briefing complete", {
      runId: ctx.run.id,
      durationMs,
      results: parsed,
    });

    return parsed;
  },
});
