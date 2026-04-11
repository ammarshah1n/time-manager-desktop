import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

type CheckType =
  | "tier0_count"
  | "tier1_gap"
  | "acb_age"
  | "backfill_status"
  | "nightly_pipeline";

type Status = "ok" | "warning" | "critical";

type CheckResult = {
  check_type: CheckType;
  status: Status;
  details: Record<string, unknown>;
};

function responseHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Content-Type": "application/json",
  };
}

function errorCode(error: unknown): string {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return "";
  }

  const code = (error as { code?: unknown }).code;
  return typeof code === "string" ? code : "";
}

function errorMessage(error: unknown): string {
  if (typeof error !== "object" || error === null || !("message" in error)) {
    return "";
  }

  const message = (error as { message?: unknown }).message;
  return typeof message === "string" ? message : "";
}

function isMissingTableError(error: unknown): boolean {
  const code = errorCode(error);
  const message = errorMessage(error).toLowerCase();
  return code === "42P01" || (message.includes("relation") && message.includes("does not exist"));
}

function isMissingColumnError(error: unknown): boolean {
  const code = errorCode(error);
  const message = errorMessage(error).toLowerCase();
  return code === "42703" || (message.includes("column") && message.includes("does not exist"));
}

function dateKeyFromValue(value: string): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value.slice(0, 10);
  }

  return parsed.toISOString().slice(0, 10);
}

function utcDateKeyDaysAgo(daysAgo: number): string {
  const date = new Date();
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCDate(date.getUTCDate() - daysAgo);
  return date.toISOString().slice(0, 10);
}

async function countRecentRows(
  table: string,
  columns: string[],
  sinceValue: string
): Promise<
  | { kind: "success"; count: number; column: string }
  | { kind: "missing_table" }
  | { kind: "missing_column" }
> {
  for (const column of columns) {
    const { count, error } = await supabaseAdmin
      .from(table)
      .select("*", { count: "exact", head: true })
      .gte(column, sinceValue);

    if (!error) {
      return { kind: "success", count: count ?? 0, column };
    }

    if (isMissingTableError(error)) {
      return { kind: "missing_table" };
    }

    if (isMissingColumnError(error)) {
      continue;
    }

    throw error;
  }

  return { kind: "missing_column" };
}

async function fetchRecentDateValues(
  table: string,
  columns: string[],
  sinceValue: string
): Promise<
  | { kind: "success"; values: string[]; column: string }
  | { kind: "missing_table" }
  | { kind: "missing_column" }
> {
  for (const column of columns) {
    const { data, error } = await supabaseAdmin
      .from(table)
      .select(column)
      .gte(column, sinceValue)
      .order(column, { ascending: true });

    if (!error) {
      const values = (data ?? [])
        .map((row) => {
          const value = (row as Record<string, unknown>)[column];
          return typeof value === "string" ? value : null;
        })
        .filter((value): value is string => value !== null);

      return { kind: "success", values, column };
    }

    if (isMissingTableError(error)) {
      return { kind: "missing_table" };
    }

    if (isMissingColumnError(error)) {
      continue;
    }

    throw error;
  }

  return { kind: "missing_column" };
}

async function fetchLatestValue(
  table: string,
  columns: string[]
): Promise<
  | { kind: "success"; value: string | null; column: string }
  | { kind: "missing_table" }
  | { kind: "missing_column" }
> {
  for (const column of columns) {
    const { data, error } = await supabaseAdmin
      .from(table)
      .select(column)
      .order(column, { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!error) {
      const value = data ? (data as Record<string, unknown>)[column] : null;
      return {
        kind: "success",
        value: typeof value === "string" ? value : null,
        column,
      };
    }

    if (isMissingTableError(error)) {
      return { kind: "missing_table" };
    }

    if (isMissingColumnError(error)) {
      continue;
    }

    throw error;
  }

  return { kind: "missing_column" };
}

async function runTier0Check(): Promise<CheckResult> {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const outcome = await countRecentRows("tier0_observations", ["occurred_at", "created_at"], since);

  if (outcome.kind === "missing_table") {
    return {
      check_type: "tier0_count",
      status: "ok",
      details: { note: "table not deployed yet", table: "tier0_observations" },
    };
  }

  if (outcome.kind === "missing_column") {
    return {
      check_type: "tier0_count",
      status: "ok",
      details: {
        note: "compatible timestamp column not deployed yet",
        table: "tier0_observations",
      },
    };
  }

  const status: Status =
    outcome.count === 0 ? "critical" : outcome.count < 50 ? "warning" : "ok";

  return {
    check_type: "tier0_count",
    status,
    details: {
      table: "tier0_observations",
      window_hours: 24,
      count: outcome.count,
      column: outcome.column,
    },
  };
}

async function runTier1GapCheck(): Promise<CheckResult> {
  const since = utcDateKeyDaysAgo(6);
  const outcome = await fetchRecentDateValues(
    "tier1_daily_summaries",
    ["summary_date", "date", "created_at", "generated_at"],
    since
  );

  if (outcome.kind === "missing_table") {
    return {
      check_type: "tier1_gap",
      status: "ok",
      details: { note: "table not deployed yet", table: "tier1_daily_summaries" },
    };
  }

  if (outcome.kind === "missing_column") {
    return {
      check_type: "tier1_gap",
      status: "ok",
      details: {
        note: "compatible date column not deployed yet",
        table: "tier1_daily_summaries",
      },
    };
  }

  const expectedDates = Array.from({ length: 7 }, (_, index) => utcDateKeyDaysAgo(6 - index));
  const observedDates = Array.from(new Set(outcome.values.map(dateKeyFromValue))).sort();
  const observedDateSet = new Set(observedDates);
  const missingDates = expectedDates.filter((date) => !observedDateSet.has(date));

  return {
    check_type: "tier1_gap",
    status: missingDates.length > 0 ? "warning" : "ok",
    details: {
      table: "tier1_daily_summaries",
      checked_days: 7,
      column: outcome.column,
      observed_dates: observedDates,
      missing_dates: missingDates,
    },
  };
}

async function runAcbAgeCheck(): Promise<CheckResult> {
  const outcome = await fetchLatestValue(
    "active_context_buffer",
    ["generated_at", "updated_at", "created_at"]
  );

  if (outcome.kind === "missing_table") {
    return {
      check_type: "acb_age",
      status: "ok",
      details: { note: "table not deployed yet", table: "active_context_buffer" },
    };
  }

  if (outcome.kind === "missing_column") {
    return {
      check_type: "acb_age",
      status: "ok",
      details: {
        note: "compatible timestamp column not deployed yet",
        table: "active_context_buffer",
      },
    };
  }

  if (!outcome.value) {
    return {
      check_type: "acb_age",
      status: "warning",
      details: {
        table: "active_context_buffer",
        column: outcome.column,
        note: "no rows found",
      },
    };
  }

  const generatedAt = new Date(outcome.value);
  const ageHours = (Date.now() - generatedAt.getTime()) / (60 * 60 * 1000);

  return {
    check_type: "acb_age",
    status: ageHours > 25 ? "warning" : "ok",
    details: {
      table: "active_context_buffer",
      column: outcome.column,
      generated_at: outcome.value,
      age_hours: Number(ageHours.toFixed(2)),
    },
  };
}

async function runBackfillCheck(): Promise<CheckResult> {
  return {
    check_type: "backfill_status",
    status: "ok",
    details: {
      note: "placeholder until backfill system exists (Phase 5.02)",
    },
  };
}

async function runNightlyPipelineCheck(): Promise<CheckResult> {
  return {
    check_type: "nightly_pipeline",
    status: "ok",
    details: {
      note: "placeholder until nightly pipeline exists (Phase 3)",
    },
  };
}

async function sendWebhookAlert(results: CheckResult[]): Promise<void> {
  const webhookUrl = Deno.env.get("PIPELINE_HEALTH_WEBHOOK_URL");
  if (!webhookUrl) return;

  const flagged = results.filter((r) => r.status !== "ok");
  if (flagged.length === 0) return;

  const text = flagged
    .map((r) => `[${r.status.toUpperCase()}] ${r.check_type}: ${JSON.stringify(r.details)}`)
    .join("\n");

  try {
    await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: `🔴 Pipeline Health Alert\n${text}` }),
    });
  } catch {
    // Non-fatal — log insert is the primary record
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const results = await Promise.all([
      runTier0Check(),
      runTier1GapCheck(),
      runAcbAgeCheck(),
      runBackfillCheck(),
      runNightlyPipelineCheck(),
    ]);

    const { error: insertError } = await supabaseAdmin
      .from("pipeline_health_log")
      .insert(results);

    if (insertError) {
      throw insertError;
    }

    await sendWebhookAlert(results);

    return new Response(
      JSON.stringify({ results }),
      { headers: responseHeaders() }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: errorMessage(err) || "Internal error" }),
      { status: 500, headers: responseHeaders() }
    );
  }
});
