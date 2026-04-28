import { logger, task } from "@trigger.dev/sdk";

import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * Ingestion health watchdog.
 *
 * Runs every 15 minutes. Checks three signals and logs a structured
 * `alert: true` record for each problem it finds. Paging to Ammar (email/SMS)
 * is Trigger.dev's alert-rule concern — it watches for `alert: true` entries
 * and fans out via its built-in notification rules. This keeps the Wave 2
 * implementation paging-provider-agnostic.
 *
 * Signals:
 *   1. email_messages.received_at: stale if > 90 min during Sydney business
 *      hours (09:00–17:00 weekdays) OR > 8h overall.
 *   2. calendar_observations.event_start: stale if > 8h.
 *   3. agent_sessions.status = 'failed' in the last 24 hours: one alert per
 *      failed row.
 *
 * Pragmatic defaults:
 *   - Single-executive system today (Yasser). We resolve Yasser's exec_id via
 *     env var YASSER_EMAIL if set, else fall back to the single row in
 *     `executives`. Multi-tenant support is a future concern.
 *   - Email recency is scanned globally across email_messages (not filtered
 *     per-exec) because (a) single-exec today, (b) email_messages has no
 *     direct exec_id column — the join through email_accounts -> profiles
 *     isn't worth the complexity here.
 *
 * Schedule: callable on demand. Was `*\/15 * * * *` until 2026-04-28 when the
 * Trigger.dev hobby plan's 10-schedule cap forced one task off the schedule
 * list — the watchdog (monitoring, not pipeline) was the cheapest to demote.
 * Re-add a cron + switch back to `schedules.task` when the plan is upgraded.
 */

const SYDNEY_TIMEZONE = "Australia/Sydney";
const EMAIL_STALE_BUSINESS_MIN = 90;
const EMAIL_STALE_OVERALL_HOURS = 8;
const CALENDAR_STALE_HOURS = 8;

interface ExecutiveLookupRow {
  id: string;
  email: string;
}

interface FailedSessionRow {
  id: string;
  task_name: string | null;
  started_at: string | null;
  status: string | null;
}

function readEnv(key: string): string | undefined {
  const value = process["env"][key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

async function resolveYasserExecId(): Promise<ExecutiveLookupRow | null> {
  const sb = getSupabaseServiceRole();
  const yasserEmail = readEnv("YASSER_EMAIL");

  if (yasserEmail) {
    const { data, error } = await sb
      .from("executives")
      .select("id, email")
      .eq("email", yasserEmail)
      .limit(1)
      .maybeSingle<ExecutiveLookupRow>();
    if (error) {
      throw new Error(
        `ingestion-health-watchdog: executives(email=YASSER_EMAIL) failed: ${error.message}`,
      );
    }
    if (data) return data;
  }

  // Fallback: pick the first (and realistically only) exec.
  const { data, error } = await sb
    .from("executives")
    .select("id, email")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle<ExecutiveLookupRow>();
  if (error) {
    throw new Error(
      `ingestion-health-watchdog: executives fallback query failed: ${error.message}`,
    );
  }
  return data;
}

/**
 * Returns true when `now` falls inside 09:00–17:00 Monday–Friday
 * in the Australia/Sydney timezone (so Sydney DST is handled by Intl).
 */
function isSydneyBusinessHours(now: Date): boolean {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: SYDNEY_TIMEZONE,
    weekday: "short",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(now);

  const weekdayRaw = parts.find((p) => p.type === "weekday")?.value ?? "";
  const hourRaw = parts.find((p) => p.type === "hour")?.value ?? "0";
  const hour = Number.parseInt(hourRaw, 10);

  // "24" appears for midnight in some locales — normalise to 0.
  const hourNormalised = Number.isFinite(hour) ? hour % 24 : 0;
  const weekdayLower = weekdayRaw.toLowerCase();
  const isWeekday = ["mon", "tue", "wed", "thu", "fri"].includes(weekdayLower);

  return isWeekday && hourNormalised >= 9 && hourNormalised < 17;
}

async function latestEmailReceivedAt(): Promise<Date | null> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("email_messages")
    .select("received_at")
    .order("received_at", { ascending: false })
    .limit(1)
    .maybeSingle<{ received_at: string | null }>();
  if (error) {
    throw new Error(
      `ingestion-health-watchdog: email_messages max query failed: ${error.message}`,
    );
  }
  if (!data?.received_at) return null;
  return new Date(data.received_at);
}

async function latestCalendarEventStart(
  executiveId: string,
): Promise<Date | null> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("calendar_observations")
    .select("event_start")
    .eq("executive_id", executiveId)
    .order("event_start", { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle<{ event_start: string | null }>();
  if (error) {
    throw new Error(
      `ingestion-health-watchdog: calendar_observations max query failed: ${error.message}`,
    );
  }
  if (!data?.event_start) return null;
  return new Date(data.event_start);
}

async function recentFailedAgentSessions(): Promise<FailedSessionRow[]> {
  const sb = getSupabaseServiceRole();
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await sb
    .from("agent_sessions")
    .select("id, task_name, started_at, status")
    .eq("status", "failed")
    .gt("started_at", cutoff);
  if (error) {
    throw new Error(
      `ingestion-health-watchdog: agent_sessions query failed: ${error.message}`,
    );
  }
  return (data ?? []) as FailedSessionRow[];
}

export const ingestionHealthWatchdog = task({
  id: "ingestion-health-watchdog",
  maxDuration: 120,
  run: async () => {
    const now = new Date();
    const exec = await resolveYasserExecId();
    if (!exec) {
      logger.warn(
        "ingestion-health-watchdog: no executive row, nothing to check",
      );
      return { pages_fired: 0 };
    }

    let pagesFired = 0;

    // 1. Email recency
    const lastEmail = await latestEmailReceivedAt();
    const businessHours = isSydneyBusinessHours(now);
    if (lastEmail === null) {
      logger.error("ingestion-health-watchdog: no email_messages rows at all", {
        alert: true,
        signal: "email_empty",
        exec_id: exec.id,
      });
      pagesFired += 1;
    } else {
      const ageMs = now.getTime() - lastEmail.getTime();
      const ageMin = ageMs / (60 * 1000);
      const ageHours = ageMs / (60 * 60 * 1000);
      const businessStale =
        businessHours && ageMin > EMAIL_STALE_BUSINESS_MIN;
      const overallStale = ageHours > EMAIL_STALE_OVERALL_HOURS;
      if (businessStale || overallStale) {
        logger.error("ingestion-health-watchdog: email ingestion stale", {
          alert: true,
          signal: "email_stale",
          exec_id: exec.id,
          last_email_iso: lastEmail.toISOString(),
          age_minutes: Math.round(ageMin),
          business_hours: businessHours,
          business_stale: businessStale,
          overall_stale: overallStale,
        });
        pagesFired += 1;
      }
    }

    // 2. Calendar recency
    const lastCalendar = await latestCalendarEventStart(exec.id);
    if (lastCalendar === null) {
      logger.warn(
        "ingestion-health-watchdog: no calendar_observations rows for exec",
        {
          exec_id: exec.id,
        },
      );
    } else {
      const calAgeHours =
        (now.getTime() - lastCalendar.getTime()) / (60 * 60 * 1000);
      if (calAgeHours > CALENDAR_STALE_HOURS) {
        logger.error("ingestion-health-watchdog: calendar ingestion stale", {
          alert: true,
          signal: "calendar_stale",
          exec_id: exec.id,
          last_event_iso: lastCalendar.toISOString(),
          age_hours: Math.round(calAgeHours),
        });
        pagesFired += 1;
      }
    }

    // 3. Failed agent sessions in the last 24 hours
    const failed = await recentFailedAgentSessions();
    for (const row of failed) {
      logger.error("ingestion-health-watchdog: agent session failed", {
        alert: true,
        signal: "agent_session_failed",
        session_id: row.id,
        task_name: row.task_name,
        started_at: row.started_at,
      });
      pagesFired += 1;
    }

    return {
      pages_fired: pagesFired,
      exec_id: exec.id,
      last_email_iso: lastEmail?.toISOString() ?? null,
      last_calendar_iso: lastCalendar?.toISOString() ?? null,
      failed_sessions: failed.length,
    };
  },
});
