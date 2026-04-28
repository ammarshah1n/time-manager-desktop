import { logger, schedules, task } from "@trigger.dev/sdk";

import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * Wave 2 Task 24 — outcome-harvester.
 *
 * Scheduled task that drains the `behaviour_events` stream every 4 hours and
 * converts matching events into `recommendation_outcomes` rows. This closes
 * the Reflexion feedback loop: the nightly agent needs a signal of whether
 * yesterday's recommendations were acted on, dismissed, deferred, etc.
 *
 * Matching strategies (documented order, first match wins):
 *   1. Direct: event.payload.recommendation_id → recommendations.id
 *      (only for `recommendation_acted_on` / `recommendation_dismissed`)
 *   2. task_ref: event.task_id → recommendations.task_ref (non-dismissed)
 *   3. content_hash: event.payload.content_hash → recommendations.content_hash
 *
 * event_type → outcome_type mapping:
 *   task_completed, recommendation_acted_on → acted_on
 *   task_deferred                           → partial   (pragmatic default)
 *   task_deleted, recommendation_dismissed  → dismissed
 *   other                                   → skipped (no row written)
 *
 * Watermark is persisted in `harvester_watermarks` keyed by `outcome-harvester`.
 * Each run processes up to 3 pages of 1000 events (3000 events/run) to stay
 * comfortably within the task maxDuration; the next tick picks up the tail.
 */

type UUID = string;

type OutcomeType = "acted_on" | "partial" | "dismissed" | "ignored" | "superseded";

interface BehaviourEventRow {
  id: UUID;
  event_type: string;
  task_id: UUID | null;
  occurred_at: string;
  old_value: Record<string, unknown> | null;
  new_value: Record<string, unknown> | null;
}

interface RecommendationRow {
  id: UUID;
  task_ref: string | null;
  content_hash: string;
  section_key: string;
}

interface WatermarkRow {
  harvester: string;
  last_event_id: UUID | null;
  last_event_at: string;
}

interface OutcomeInsert {
  recommendation_id: UUID;
  outcome_type: OutcomeType;
  observed_at: string;
  signal_source: string;
  raw_signal: Record<string, unknown>;
}

const HARVESTER_ID = "outcome-harvester";
const PAGE_SIZE = 1000;
const MAX_PAGES_PER_RUN = 3;

type SupabaseService = ReturnType<typeof getSupabaseServiceRole>;

function extractPayload(
  event: BehaviourEventRow,
): Record<string, unknown> {
  // behaviour_events has no single `payload` column; event-specific data lives
  // in `old_value` / `new_value` JSONB columns. Merging gives us a single bag
  // for the matchers below to read `recommendation_id` / `content_hash` from.
  const merged: Record<string, unknown> = {};
  if (event.old_value && typeof event.old_value === "object") {
    Object.assign(merged, event.old_value);
  }
  if (event.new_value && typeof event.new_value === "object") {
    Object.assign(merged, event.new_value);
  }
  return merged;
}

function readStringField(
  payload: Record<string, unknown>,
  key: string,
): string | null {
  const value = payload[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function mapOutcomeType(eventType: string): OutcomeType | null {
  switch (eventType) {
    case "task_completed":
    case "recommendation_acted_on":
      return "acted_on";
    case "task_deferred":
      // Pragmatic default: a deferred task is neither acted-on nor dismissed,
      // so we record it as `partial` progress on the recommendation.
      return "partial";
    case "task_deleted":
    case "recommendation_dismissed":
      return "dismissed";
    default:
      return null;
  }
}

async function loadOrInitWatermark(sb: SupabaseService): Promise<WatermarkRow> {
  const { data, error } = await sb
    .from("harvester_watermarks")
    .select("harvester, last_event_id, last_event_at")
    .eq("harvester", HARVESTER_ID)
    .maybeSingle();
  if (error) {
    throw new Error(`harvester_watermarks select failed: ${error.message}`);
  }
  if (data) {
    return data as WatermarkRow;
  }

  const fallback = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const { data: inserted, error: insertErr } = await sb
    .from("harvester_watermarks")
    .insert({
      harvester: HARVESTER_ID,
      last_event_id: null,
      last_event_at: fallback,
    })
    .select("harvester, last_event_id, last_event_at")
    .single();
  if (insertErr) {
    throw new Error(
      `harvester_watermarks insert failed: ${insertErr.message}`,
    );
  }
  return inserted as WatermarkRow;
}

async function findRecommendation(
  sb: SupabaseService,
  event: BehaviourEventRow,
): Promise<RecommendationRow | null> {
  const payload = extractPayload(event);

  // Strategy (a): direct recommendation_id on explicit interaction events.
  if (
    event.event_type === "recommendation_acted_on" ||
    event.event_type === "recommendation_dismissed"
  ) {
    const recId = readStringField(payload, "recommendation_id");
    if (recId) {
      const { data, error } = await sb
        .from("recommendations")
        .select("id, task_ref, content_hash, section_key")
        .eq("id", recId)
        .maybeSingle();
      if (error) {
        throw new Error(
          `recommendations lookup by id failed: ${error.message}`,
        );
      }
      if (data) return data as RecommendationRow;
    }
  }

  // Strategy (b): task_ref match (ignoring dismissed sections).
  if (event.task_id) {
    const { data, error } = await sb
      .from("recommendations")
      .select("id, task_ref, content_hash, section_key")
      .eq("task_ref", event.task_id)
      .neq("section_key", "dismissed")
      .order("created_at", { ascending: false })
      .limit(1);
    if (error) {
      throw new Error(
        `recommendations lookup by task_ref failed: ${error.message}`,
      );
    }
    if (data && data.length > 0) {
      const first = data[0];
      if (first) return first as RecommendationRow;
    }
  }

  // Strategy (c): content_hash match.
  const contentHash = readStringField(payload, "content_hash");
  if (contentHash) {
    const { data, error } = await sb
      .from("recommendations")
      .select("id, task_ref, content_hash, section_key")
      .eq("content_hash", contentHash)
      .order("created_at", { ascending: false })
      .limit(1);
    if (error) {
      throw new Error(
        `recommendations lookup by content_hash failed: ${error.message}`,
      );
    }
    if (data && data.length > 0) {
      const first = data[0];
      if (first) return first as RecommendationRow;
    }
  }

  return null;
}

async function processPage(
  sb: SupabaseService,
  watermark: WatermarkRow,
): Promise<{
  processed: number;
  matched: number;
  unmatched: number;
  skipped: number;
  nextWatermark: WatermarkRow;
}> {
  const { data: events, error } = await sb
    .from("behaviour_events")
    .select("id, event_type, task_id, occurred_at, old_value, new_value")
    .gte("occurred_at", watermark.last_event_at)
    .order("occurred_at", { ascending: true })
    .order("id", { ascending: true })
    .limit(PAGE_SIZE);
  if (error) {
    throw new Error(`behaviour_events select failed: ${error.message}`);
  }

  const page = (events ?? []) as BehaviourEventRow[];
  if (page.length === 0) {
    return {
      processed: 0,
      matched: 0,
      unmatched: 0,
      skipped: 0,
      nextWatermark: watermark,
    };
  }

  const inserts: OutcomeInsert[] = [];
  let matched = 0;
  let unmatched = 0;
  let skipped = 0;

  for (const event of page) {
    // Skip rows we already processed in the previous run. The (occurred_at,
    // last_event_id) tuple is the resume key — we use `>=` on occurred_at
    // because occurred_at is not strictly unique, so we must filter the
    // exact previous id out in-memory.
    if (
      watermark.last_event_id &&
      event.id === watermark.last_event_id &&
      event.occurred_at === watermark.last_event_at
    ) {
      continue;
    }

    const outcomeType = mapOutcomeType(event.event_type);
    if (!outcomeType) {
      skipped += 1;
      continue;
    }

    const rec = await findRecommendation(sb, event);
    if (!rec) {
      unmatched += 1;
      continue;
    }

    inserts.push({
      recommendation_id: rec.id,
      outcome_type: outcomeType,
      observed_at: event.occurred_at,
      signal_source: "behaviour_events",
      raw_signal: {
        behaviour_event_id: event.id,
        event_type: event.event_type,
        task_id: event.task_id,
        matched_section_key: rec.section_key,
      },
    });
    matched += 1;
  }

  if (inserts.length > 0) {
    const { error: insertErr } = await sb
      .from("recommendation_outcomes")
      .upsert(inserts, {
        onConflict: "recommendation_id,outcome_type",
        ignoreDuplicates: true,
      });
    if (insertErr) {
      throw new Error(
        `recommendation_outcomes insert failed: ${insertErr.message}`,
      );
    }
  }

  // Advance the watermark only after inserts succeed. `page` is ordered
  // ascending by (occurred_at, id), so the last row is the new cursor.
  const tail = page[page.length - 1];
  if (!tail) {
    return {
      processed: page.length,
      matched,
      unmatched,
      skipped,
      nextWatermark: watermark,
    };
  }

  const { data: updated, error: updateErr } = await sb
    .from("harvester_watermarks")
    .update({
      last_event_id: tail.id,
      last_event_at: tail.occurred_at,
      updated_at: new Date().toISOString(),
    })
    .eq("harvester", HARVESTER_ID)
    .select("harvester, last_event_id, last_event_at")
    .single();
  if (updateErr) {
    throw new Error(
      `harvester_watermarks update failed: ${updateErr.message}`,
    );
  }

  return {
    processed: page.length,
    matched,
    unmatched,
    skipped,
    nextWatermark: updated as WatermarkRow,
  };
}

// Demoted from schedules.task → task on 2026-04-28 to free a Trigger.dev hobby
// declarative slot (10/10 cap). Harvester logic intact and triggerable manually
// or from another task; re-add the cron + switch back to schedules.task once
// the schedule-cap upgrade lands. Companion to ingestion-health-watchdog
// which was demoted earlier in the same sprint.
export const outcomeHarvester = task({
  id: "outcome-harvester",
  maxDuration: 300,
  run: async (payload: { timestamp?: string; lastTimestamp?: string }) => {
    logger.info("outcome-harvester starting", {
      timestamp: payload.timestamp,
      lastTimestamp: payload.lastTimestamp,
    });

    const sb = getSupabaseServiceRole();
    let watermark = await loadOrInitWatermark(sb);

    let totalProcessed = 0;
    let totalMatched = 0;
    let totalUnmatched = 0;
    let totalSkipped = 0;
    let pagesRun = 0;

    for (let i = 0; i < MAX_PAGES_PER_RUN; i += 1) {
      const result = await processPage(sb, watermark);
      pagesRun += 1;
      totalProcessed += result.processed;
      totalMatched += result.matched;
      totalUnmatched += result.unmatched;
      totalSkipped += result.skipped;
      watermark = result.nextWatermark;

      if (result.processed < PAGE_SIZE) break;
    }

    logger.info("outcome-harvester done", {
      pages: pagesRun,
      processed: totalProcessed,
      matched: totalMatched,
      unmatched: totalUnmatched,
      skipped: totalSkipped,
      last_event_at: watermark.last_event_at,
      last_event_id: watermark.last_event_id,
    });

    return {
      pages: pagesRun,
      processed: totalProcessed,
      matched: totalMatched,
      unmatched: totalUnmatched,
      skipped: totalSkipped,
      last_event_at: watermark.last_event_at,
      last_event_id: watermark.last_event_id,
    };
  },
});
