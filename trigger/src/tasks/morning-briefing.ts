import { logger, schedules } from "@trigger.dev/sdk";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * Morning briefing scheduled task.
 *
 * Fires once per day at 05:30 Australia/Adelaide. Fans out: queries every
 * executive in `public.executives`, then invokes the
 * `generate-morning-briefing` Supabase Edge Function once per executive_id.
 *
 * Why fan out (instead of one POST with empty body)?
 *
 * The Edge Function gateway has a ~150 s wall-clock cap, but each
 * executive's two-pass Opus briefing typically takes 50–90 s. With three
 * executives running sequentially inside the function, runs 2 and 3 are
 * routinely killed by the gateway before the function inserts their
 * briefing rows. Result: only the first executive of the morning got a
 * briefing, silent loss for the rest. (Confirmed empirically on 2026-05-04
 * — only 1 of 3 expected briefing rows landed; the other two had to be
 * back-filled manually.)
 *
 * Per-executive invocations parallelise via `Promise.allSettled`, so each
 * invocation gets its own gateway budget. We use `allSettled` (not `all`)
 * so one failed executive does not deny the others their briefing.
 *
 * Cognitive-only rule: this task triggers Edge Function calls. It never
 * sends mail, books, or contacts anyone.
 */

const SCHEDULE_TZ = "Australia/Adelaide";
const SCHEDULE_CRON = "30 5 * * *";

type ExecutiveResult = {
  executiveId: string;
  status: number | "error";
  durationMs: number;
  body?: unknown;
  error?: string;
};

async function generateBriefingFor(
  executiveId: string,
  endpoint: string,
  bearer: string,
): Promise<ExecutiveResult> {
  const t0 = Date.now();
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ executiveId }),
    });
    const text = await response.text();
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { raw: text.slice(0, 500) };
    }
    const durationMs = Date.now() - t0;
    if (!response.ok) {
      return {
        executiveId,
        status: response.status,
        durationMs,
        body: parsed,
        error: `HTTP ${response.status} ${response.statusText}`,
      };
    }
    return { executiveId, status: response.status, durationMs, body: parsed };
  } catch (err) {
    return {
      executiveId,
      status: "error",
      durationMs: Date.now() - t0,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

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
    if (!url) throw new Error("morning-briefing: SUPABASE_URL not set");
    if (!key) throw new Error("morning-briefing: SUPABASE_SERVICE_ROLE_KEY not set");

    const supa = getSupabaseServiceRole();
    const { data: executives, error: execError } = await supa
      .from("executives")
      .select("id");
    if (execError) {
      logger.error("morning-briefing: failed to list executives", {
        alert: true,
        error: execError.message,
      });
      throw new Error(`morning-briefing: list executives failed: ${execError.message}`);
    }
    if (!executives || executives.length === 0) {
      logger.warn("morning-briefing: no executives found, nothing to do", {
        runId: ctx.run.id,
      });
      return { executiveCount: 0, results: [] };
    }

    const endpoint = `${url}/functions/v1/generate-morning-briefing`;

    const settled = await Promise.allSettled(
      executives.map((e) => generateBriefingFor(e.id as string, endpoint, key)),
    );

    const results: ExecutiveResult[] = settled.map((s, i) => {
      if (s.status === "fulfilled") return s.value;
      const ex = executives[i] as { id?: string };
      return {
        executiveId: ex?.id ?? "<unknown>",
        status: "error",
        durationMs: 0,
        error: s.reason instanceof Error ? s.reason.message : String(s.reason),
      };
    });

    // Histogram for log scanability
    const statusCounts: Record<string, number> = {};
    for (const r of results) {
      const k = typeof r.status === "number"
        ? (r.status >= 200 && r.status < 300 ? "ok" : `http_${r.status}`)
        : "error";
      statusCounts[k] = (statusCounts[k] ?? 0) + 1;
    }

    const okCount = statusCounts["ok"] ?? 0;
    const totalDurationMs = Date.now() - t0;

    if (okCount === 0) {
      logger.error("morning-briefing FAILED — zero successful executives", {
        alert: true,
        executiveCount: executives.length,
        statusCounts,
        results,
        totalDurationMs,
      });
      throw new Error(
        `morning-briefing: all ${executives.length} executives failed; statusCounts=${JSON.stringify(statusCounts)}`,
      );
    }

    if (okCount < executives.length) {
      logger.warn("morning-briefing partial success", {
        executiveCount: executives.length,
        okCount,
        statusCounts,
        results,
        totalDurationMs,
      });
    } else {
      logger.info("morning-briefing complete", {
        runId: ctx.run.id,
        executiveCount: executives.length,
        statusCounts,
        totalDurationMs,
      });
    }

    return {
      executiveCount: executives.length,
      okCount,
      statusCounts,
      totalDurationMs,
      results,
    };
  },
});
