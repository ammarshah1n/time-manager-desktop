import { logger, schedules } from "@trigger.dev/sdk";

import {
  getGraphAppToken,
  invalidateGraphAppToken,
} from "../lib/graph-app-auth.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * Server-side Microsoft Graph calendar delta sync.
 *
 * Runs every 5 minutes. For each executive whose `email_sync_driver = 'server'`
 * the task walks /users/{email}/calendarView/delta with the required
 * startDateTime/endDateTime window, inserts new events into
 * `calendar_observations`, and persists the next deltaLink into
 * `email_sync_state.calendar_delta_link`.
 *
 * Dedup: `calendar_observations` has no natural key in the base schema, so the
 * companion migration (20260427000100_email_sync_state.sql) adds a nullable
 * `graph_event_id` column plus a partial unique index on
 * (executive_id, graph_event_id). This task uses that column as the dedup key
 * via a pre-query + insert pattern — `.upsert()` with `onConflict` would only
 * work once the existing rows get backfilled with a graph_event_id, which is
 * out of scope for Wave 2.
 *
 * Error handling mirrors graph-delta-sync: 410 -> reset deltaLink to null and
 * rebuild the calendarView window, 401 -> invalidate the token cache and retry
 * once.
 *
 * Schedule: cron `*\/5 * * * *`, id `graph-calendar-delta-sync`.
 */

const WINDOW_DAYS_PAST = 7;
const WINDOW_DAYS_FUTURE = 30;

interface ExecutiveRow {
  id: string;
  email: string;
}

interface EmailSyncStateRow {
  calendar_delta_link: string | null;
}

interface GraphEvent {
  id?: string;
  subject?: string | null;
  bodyPreview?: string | null;
  isCancelled?: boolean | null;
  isOrganizer?: boolean | null;
  start?: { dateTime?: string | null; timeZone?: string | null } | null;
  end?: { dateTime?: string | null; timeZone?: string | null } | null;
  attendees?: unknown[] | null;
  "@removed"?: unknown;
}

interface GraphCalendarDeltaResponse {
  value?: GraphEvent[];
  "@odata.nextLink"?: string;
  "@odata.deltaLink"?: string;
}

interface CalendarObservationInsert {
  executive_id: string;
  observed_at: string;
  event_start: string | null;
  event_end: string | null;
  title: string | null;
  description: string | null;
  attendee_count: number | null;
  organiser_is_self: boolean | null;
  was_cancelled: boolean | null;
  was_rescheduled: boolean | null;
  graph_event_id: string;
}

class GraphAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GraphAuthError";
  }
}

class GraphDeltaExpiredError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GraphDeltaExpiredError";
  }
}

function windowBounds(): { start: string; end: string } {
  const now = Date.now();
  return {
    start: new Date(now - WINDOW_DAYS_PAST * 24 * 60 * 60 * 1000).toISOString(),
    end: new Date(now + WINDOW_DAYS_FUTURE * 24 * 60 * 60 * 1000).toISOString(),
  };
}

function initialCalendarDeltaUrl(email: string): string {
  const { start, end } = windowBounds();
  const query = new URLSearchParams({
    startDateTime: start,
    endDateTime: end,
  });
  return `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(
    email,
  )}/calendarView/delta?${query.toString()}`;
}

async function graphGet(
  url: string,
  token: string,
): Promise<GraphCalendarDeltaResponse> {
  const response = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      // Graph requires an explicit Prefer header on calendarView/delta in some
      // cases; we opt in to the recommended max page size.
      Prefer: 'odata.maxpagesize=50, outlook.timezone="UTC"',
    },
  });

  if (response.status === 401) {
    throw new GraphAuthError(
      `graph-calendar-delta-sync: Graph returned 401 for ${url}`,
    );
  }
  if (response.status === 410) {
    throw new GraphDeltaExpiredError(
      `graph-calendar-delta-sync: delta token expired (410) for ${url}`,
    );
  }
  if (!response.ok) {
    const text = await response.text().catch(() => "<unreadable>");
    throw new Error(
      `graph-calendar-delta-sync: Graph ${response.status} ${response.statusText}: ${text}`,
    );
  }

  return (await response.json()) as GraphCalendarDeltaResponse;
}

async function graphGetWithRetry(
  url: string,
): Promise<GraphCalendarDeltaResponse> {
  let token = await getGraphAppToken();
  try {
    return await graphGet(url, token);
  } catch (err) {
    if (err instanceof GraphAuthError) {
      invalidateGraphAppToken();
      token = await getGraphAppToken();
      return await graphGet(url, token);
    }
    throw err;
  }
}

async function loadExecutives(): Promise<ExecutiveRow[]> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("executives")
    .select("id, email")
    .eq("email_sync_driver", "server");
  if (error) {
    throw new Error(
      `graph-calendar-delta-sync: executives query failed: ${error.message}`,
    );
  }
  return (data ?? []) as ExecutiveRow[];
}

async function loadCalendarDeltaLink(execId: string): Promise<string | null> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("email_sync_state")
    .select("calendar_delta_link")
    .eq("exec_id", execId)
    .maybeSingle<EmailSyncStateRow>();
  if (error) {
    throw new Error(
      `graph-calendar-delta-sync: email_sync_state read failed for ${execId}: ${error.message}`,
    );
  }
  return data?.calendar_delta_link ?? null;
}

async function persistCalendarDeltaLink(
  execId: string,
  deltaLink: string | null,
): Promise<void> {
  const sb = getSupabaseServiceRole();
  const nowIso = new Date().toISOString();
  const { error } = await sb.from("email_sync_state").upsert(
    {
      exec_id: execId,
      calendar_delta_link: deltaLink,
      last_calendar_synced_at: nowIso,
      updated_at: nowIso,
    },
    { onConflict: "exec_id" },
  );
  if (error) {
    throw new Error(
      `graph-calendar-delta-sync: email_sync_state upsert failed for ${execId}: ${error.message}`,
    );
  }
}

function mapEvent(
  event: GraphEvent,
  executiveId: string,
): CalendarObservationInsert | null {
  if (!event.id) return null;
  if (event["@removed"] !== undefined) return null;

  const nowIso = new Date().toISOString();

  return {
    executive_id: executiveId,
    observed_at: nowIso,
    event_start: event.start?.dateTime ?? null,
    event_end: event.end?.dateTime ?? null,
    title: event.subject ?? null,
    description: event.bodyPreview ?? null,
    attendee_count: Array.isArray(event.attendees)
      ? event.attendees.length
      : null,
    organiser_is_self: event.isOrganizer ?? null,
    was_cancelled: event.isCancelled ?? null,
    // Graph delta doesn't give us a dedicated reschedule flag — we leave it
    // null on server-side inserts and let the reflection layer infer it.
    was_rescheduled: null,
    graph_event_id: event.id,
  };
}

async function filterNewGraphEventIds(
  executiveId: string,
  graphIds: string[],
): Promise<Set<string>> {
  if (graphIds.length === 0) return new Set<string>();
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("calendar_observations")
    .select("graph_event_id")
    .eq("executive_id", executiveId)
    .in("graph_event_id", graphIds);
  if (error) {
    throw new Error(
      `graph-calendar-delta-sync: existing id lookup failed: ${error.message}`,
    );
  }
  const existing = new Set<string>();
  for (const row of (data ?? []) as { graph_event_id: string | null }[]) {
    if (row.graph_event_id) existing.add(row.graph_event_id);
  }
  const newSet = new Set<string>();
  for (const id of graphIds) {
    if (!existing.has(id)) newSet.add(id);
  }
  return newSet;
}

async function insertObservations(
  rows: CalendarObservationInsert[],
): Promise<void> {
  if (rows.length === 0) return;
  const sb = getSupabaseServiceRole();
  // The partial unique index (executive_id, graph_event_id) defends us from
  // a racing duplicate insert; `onConflict` below names it explicitly.
  const { error } = await sb.from("calendar_observations").upsert(rows, {
    onConflict: "executive_id,graph_event_id",
    ignoreDuplicates: true,
  });
  if (error) {
    throw new Error(
      `graph-calendar-delta-sync: calendar_observations upsert failed: ${error.message}`,
    );
  }
}

interface SyncResult {
  processed: number;
  nextDeltaLink: string | null;
}

async function runSyncPass(
  execEmail: string,
  executiveId: string,
  startUrl: string,
): Promise<SyncResult> {
  let processed = 0;
  let finalDeltaLink: string | null = null;
  let cursor: string | undefined = startUrl;

  while (cursor !== undefined) {
    const page: GraphCalendarDeltaResponse = await graphGetWithRetry(cursor);

    const mapped: CalendarObservationInsert[] = [];
    for (const event of page.value ?? []) {
      const row = mapEvent(event, executiveId);
      if (row) mapped.push(row);
    }

    if (mapped.length > 0) {
      const candidateIds = mapped.map((row) => row.graph_event_id);
      const newIds = await filterNewGraphEventIds(executiveId, candidateIds);
      const toInsert = mapped.filter((row) =>
        newIds.has(row.graph_event_id),
      );
      await insertObservations(toInsert);
      processed += toInsert.length;
    }

    if (page["@odata.nextLink"]) {
      cursor = page["@odata.nextLink"];
    } else {
      cursor = undefined;
      if (page["@odata.deltaLink"]) {
        finalDeltaLink = page["@odata.deltaLink"];
      }
    }
  }

  logger.info("graph-calendar-delta-sync: pass complete", {
    execEmail,
    processed,
    hasDeltaLink: finalDeltaLink !== null,
  });

  return { processed, nextDeltaLink: finalDeltaLink };
}

export const graphCalendarDeltaSync = schedules.task({
  id: "graph-calendar-delta-sync",
  cron: "*/5 * * * *",
  maxDuration: 120,
  run: async () => {
    const executives = await loadExecutives();
    if (executives.length === 0) {
      logger.info("graph-calendar-delta-sync: no server-driven executives");
      return { executives_processed: 0 };
    }

    let totalProcessed = 0;

    for (const exec of executives) {
      try {
        const storedDelta = await loadCalendarDeltaLink(exec.id);
        const startUrl = storedDelta ?? initialCalendarDeltaUrl(exec.email);

        let result: SyncResult;
        try {
          result = await runSyncPass(exec.email, exec.id, startUrl);
        } catch (err) {
          if (err instanceof GraphDeltaExpiredError) {
            logger.warn(
              "graph-calendar-delta-sync: delta expired, rebuilding window",
              { execId: exec.id },
            );
            await persistCalendarDeltaLink(exec.id, null);
            result = await runSyncPass(
              exec.email,
              exec.id,
              initialCalendarDeltaUrl(exec.email),
            );
          } else {
            throw err;
          }
        }

        await persistCalendarDeltaLink(exec.id, result.nextDeltaLink);
        totalProcessed += result.processed;
      } catch (err) {
        const message =
          err instanceof Error ? err.message : JSON.stringify(err);
        logger.error("graph-calendar-delta-sync: exec failed", {
          execId: exec.id,
          execEmail: exec.email,
          error: message,
        });
      }
    }

    return {
      executives_processed: executives.length,
      events_inserted: totalProcessed,
    };
  },
});
