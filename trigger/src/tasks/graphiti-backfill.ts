import { createHash } from "node:crypto";

import { logger, task } from "@trigger.dev/sdk";

import {
  callMcpTool,
  closeAgentSession,
  openAgentSession,
  traceToolCall,
} from "../lib/trace-tool-results.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * T32 -- one-shot Graphiti backfill.
 *
 * NOT scheduled. Triggered manually (via `trigger.dev` dashboard or CLI) once,
 * ideally right before the first nightly NREM run, to prime the Graphiti
 * knowledge graph with historical context:
 *
 *   - ona_nodes (contact entities)
 *   - ona_edges (directional email interactions)
 *   - tier0_observations from the last 90 days
 *
 * Each source becomes a synthetic `add_episode` call with the original
 * timestamp passed as `reference_time`.
 *
 * Idempotency is a two-layer defence:
 *   (1) `backfill_watermark` table: per-source cursor (kind, last_id,
 *       last_timestamp). Subsequent runs pick up strictly after the cursor.
 *   (2) Per-episode `episode_exists({ content_hash })` check against
 *       Graphiti before every add_episode. Even if watermarks are wiped,
 *       Graphiti itself refuses duplicates.
 */

const BATCH_SIZE = 500;
const TIER0_LOOKBACK_DAYS = 90;

type WatermarkKind = "ona_nodes" | "ona_edges" | "tier0_observations";

type WatermarkRow = {
  kind: WatermarkKind;
  last_id: string | null;
  last_timestamp: string | null;
};

async function loadWatermark(kind: WatermarkKind): Promise<WatermarkRow> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("backfill_watermark")
    .select("kind, last_id, last_timestamp")
    .eq("kind", kind)
    .maybeSingle();
  if (error) {
    throw new Error(`backfill_watermark read (${kind}) failed: ${error.message}`);
  }
  return (
    data ?? {
      kind,
      last_id: null,
      last_timestamp: null,
    }
  );
}

async function saveWatermark(
  kind: WatermarkKind,
  last_id: string,
  last_timestamp: string,
): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb.from("backfill_watermark").upsert(
    {
      kind,
      last_id,
      last_timestamp,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "kind" },
  );
  if (error) {
    throw new Error(`backfill_watermark upsert (${kind}) failed: ${error.message}`);
  }
}

function hashContent(content: string): string {
  return createHash("sha256").update(content).digest("hex").slice(0, 16);
}

/**
 * Emit one synthetic episode to Graphiti, guarded by `episode_exists`.
 * Writes a trace row for every tool call.
 *
 * Returns true if we added an episode (i.e., Graphiti didn't already know),
 * false if the exists-check short-circuited us.
 */
async function emitEpisode(args: {
  session_id: string;
  step_index_ref: { value: number };
  content: string;
  reference_time: string;
  source: string;
  source_id: string;
}): Promise<boolean> {
  const content_hash = hashContent(args.content);

  const t0 = Date.now();
  const existsOut = await callMcpTool("episode_exists", { content_hash });
  await traceToolCall({
    session_id: args.session_id,
    step_index: args.step_index_ref.value++,
    tool_name: "episode_exists",
    input: { content_hash },
    output: existsOut,
    latency_ms: Date.now() - t0,
  });

  if (existsTruthy(existsOut)) return false;

  const addT0 = Date.now();
  const input = {
    content: args.content,
    content_hash,
    reference_time: args.reference_time,
    source: args.source,
    source_id: args.source_id,
  };
  const addOut = await callMcpTool("add_episode", input);
  await traceToolCall({
    session_id: args.session_id,
    step_index: args.step_index_ref.value++,
    tool_name: "add_episode",
    input,
    output: addOut,
    latency_ms: Date.now() - addT0,
  });
  return true;
}

function existsTruthy(output: unknown): boolean {
  if (output === true) return true;
  if (typeof output === "object" && output !== null) {
    const rec = output as Record<string, unknown>;
    if (rec["exists"] === true) return true;
    if (Array.isArray(rec["content"])) {
      const first = (rec["content"] as unknown[])[0];
      if (
        typeof first === "object" &&
        first !== null &&
        "text" in first &&
        String((first as { text: unknown }).text).toLowerCase().trim() === "true"
      ) {
        return true;
      }
    }
  }
  if (Array.isArray(output)) {
    const first = output[0];
    if (
      typeof first === "object" &&
      first !== null &&
      "text" in first &&
      String((first as { text: unknown }).text).toLowerCase().trim() === "true"
    ) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// ona_nodes
// ---------------------------------------------------------------------------

type OnaNodeRow = {
  id: string;
  email: string;
  display_name: string | null;
  inferred_role: string | null;
  inferred_org: string | null;
  authority_tier: string | null;
  relationship_type: string | null;
  first_seen_at: string | null;
  created_at: string | null;
};

async function backfillOnaNodes(
  session_id: string,
  step_index_ref: { value: number },
): Promise<{ scanned: number; emitted: number }> {
  const wm = await loadWatermark("ona_nodes");
  const sb = getSupabaseServiceRole();

  let scanned = 0;
  let emitted = 0;
  let cursor_ts = wm.last_timestamp ?? new Date(0).toISOString();
  let cursor_id = wm.last_id;

  while (true) {
    let q = sb
      .from("ona_nodes")
      .select(
        "id, email, display_name, inferred_role, inferred_org, authority_tier, relationship_type, first_seen_at, created_at",
      )
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .limit(BATCH_SIZE);
    if (cursor_ts) {
      q = q.gte("created_at", cursor_ts);
    }

    const { data, error } = await q;
    if (error) throw new Error(`ona_nodes read failed: ${error.message}`);
    const rows = (data ?? []) as OnaNodeRow[];
    if (rows.length === 0) break;

    // Drop the exact-cursor tie-breaker row if present (strictly-after semantics).
    const toProcess = rows.filter(
      (r) => !(r.created_at === cursor_ts && r.id === cursor_id),
    );
    if (toProcess.length === 0) {
      // Nothing new past the cursor -- we're done.
      break;
    }

    for (const row of toProcess) {
      scanned++;
      const ref = row.first_seen_at ?? row.created_at ?? new Date().toISOString();
      const content = formatOnaNodeEpisode(row);
      const added = await emitEpisode({
        session_id,
        step_index_ref,
        content,
        reference_time: ref,
        source: "ona_nodes",
        source_id: row.id,
      });
      if (added) emitted++;
      cursor_ts = row.created_at ?? ref;
      cursor_id = row.id;
      await saveWatermark("ona_nodes", cursor_id, cursor_ts);
    }

    if (rows.length < BATCH_SIZE) break;
  }

  return { scanned, emitted };
}

function formatOnaNodeEpisode(row: OnaNodeRow): string {
  const bits = [
    `Contact: ${row.display_name ?? row.email} <${row.email}>`,
    row.inferred_role ? `role=${row.inferred_role}` : null,
    row.inferred_org ? `org=${row.inferred_org}` : null,
    row.authority_tier ? `authority=${row.authority_tier}` : null,
    row.relationship_type ? `relationship=${row.relationship_type}` : null,
  ].filter((s): s is string => s !== null);
  return bits.join("; ");
}

// ---------------------------------------------------------------------------
// ona_edges
// ---------------------------------------------------------------------------

type OnaEdgeRow = {
  id: string;
  edge_timestamp: string;
  direction: string;
  from_node_id: string | null;
  to_node_id: string | null;
  thread_id: string | null;
  recipient_position: string | null;
  has_attachment: boolean | null;
};

async function backfillOnaEdges(
  session_id: string,
  step_index_ref: { value: number },
): Promise<{ scanned: number; emitted: number }> {
  const wm = await loadWatermark("ona_edges");
  const sb = getSupabaseServiceRole();

  let scanned = 0;
  let emitted = 0;
  let cursor_ts = wm.last_timestamp ?? new Date(0).toISOString();
  let cursor_id = wm.last_id;

  while (true) {
    let q = sb
      .from("ona_edges")
      .select(
        "id, edge_timestamp, direction, from_node_id, to_node_id, thread_id, recipient_position, has_attachment",
      )
      .order("edge_timestamp", { ascending: true })
      .order("id", { ascending: true })
      .limit(BATCH_SIZE);
    if (cursor_ts) {
      q = q.gte("edge_timestamp", cursor_ts);
    }

    const { data, error } = await q;
    if (error) throw new Error(`ona_edges read failed: ${error.message}`);
    const rows = (data ?? []) as OnaEdgeRow[];
    if (rows.length === 0) break;

    const toProcess = rows.filter(
      (r) => !(r.edge_timestamp === cursor_ts && r.id === cursor_id),
    );
    if (toProcess.length === 0) break;

    for (const row of toProcess) {
      scanned++;
      const content = formatOnaEdgeEpisode(row);
      const added = await emitEpisode({
        session_id,
        step_index_ref,
        content,
        reference_time: row.edge_timestamp,
        source: "ona_edges",
        source_id: row.id,
      });
      if (added) emitted++;
      cursor_ts = row.edge_timestamp;
      cursor_id = row.id;
      await saveWatermark("ona_edges", cursor_id, cursor_ts);
    }

    if (rows.length < BATCH_SIZE) break;
  }

  return { scanned, emitted };
}

function formatOnaEdgeEpisode(row: OnaEdgeRow): string {
  const bits = [
    `Email ${row.direction}`,
    row.from_node_id ? `from=${row.from_node_id}` : null,
    row.to_node_id ? `to=${row.to_node_id}` : null,
    row.thread_id ? `thread=${row.thread_id}` : null,
    row.recipient_position ? `position=${row.recipient_position}` : null,
    row.has_attachment ? "has_attachment=true" : null,
  ].filter((s): s is string => s !== null);
  return bits.join("; ");
}

// ---------------------------------------------------------------------------
// tier0_observations (last 90 days)
// ---------------------------------------------------------------------------

type Tier0Row = {
  id: string;
  occurred_at: string;
  source: string;
  event_type: string;
  summary: string | null;
  raw_data: unknown;
};

async function backfillTier0(
  session_id: string,
  step_index_ref: { value: number },
): Promise<{ scanned: number; emitted: number }> {
  const wm = await loadWatermark("tier0_observations");
  const sb = getSupabaseServiceRole();

  const lookback = new Date(
    Date.now() - TIER0_LOOKBACK_DAYS * 24 * 60 * 60 * 1_000,
  ).toISOString();
  let cursor_ts = wm.last_timestamp && wm.last_timestamp > lookback
    ? wm.last_timestamp
    : lookback;
  let cursor_id = wm.last_id;

  let scanned = 0;
  let emitted = 0;

  while (true) {
    const { data, error } = await sb
      .from("tier0_observations")
      .select("id, occurred_at, source, event_type, summary, raw_data")
      .gte("occurred_at", cursor_ts)
      .order("occurred_at", { ascending: true })
      .order("id", { ascending: true })
      .limit(BATCH_SIZE);
    if (error) {
      throw new Error(`tier0_observations read failed: ${error.message}`);
    }
    const rows = (data ?? []) as Tier0Row[];
    if (rows.length === 0) break;

    const toProcess = rows.filter(
      (r) => !(r.occurred_at === cursor_ts && r.id === cursor_id),
    );
    if (toProcess.length === 0) break;

    for (const row of toProcess) {
      scanned++;
      const content = formatTier0Episode(row);
      const added = await emitEpisode({
        session_id,
        step_index_ref,
        content,
        reference_time: row.occurred_at,
        source: "tier0_observations",
        source_id: row.id,
      });
      if (added) emitted++;
      cursor_ts = row.occurred_at;
      cursor_id = row.id;
      await saveWatermark("tier0_observations", cursor_id, cursor_ts);
    }

    if (rows.length < BATCH_SIZE) break;
  }

  return { scanned, emitted };
}

function formatTier0Episode(row: Tier0Row): string {
  const bits = [
    `Observation[${row.source}/${row.event_type}]`,
    row.summary ?? "",
    `raw=${JSON.stringify(row.raw_data ?? {}).slice(0, 500)}`,
  ];
  return bits.join(" :: ");
}

// ---------------------------------------------------------------------------
// Trigger.dev task entrypoint
// ---------------------------------------------------------------------------

export const graphitiBackfill = task({
  id: "graphiti-backfill",
  // This one-shot can take a while on a cold graph -- give it the full 15 min.
  maxDuration: 900,
  run: async (_payload: Record<string, unknown> = {}, { ctx }) => {
    logger.info("graphiti-backfill starting");

    const mcp_url = process["env"]["GRAPHITI_MCP_URL"];
    const mcp_token = process["env"]["GRAPHITI_MCP_TOKEN"];
    if (!mcp_url || !mcp_token) {
      throw new Error(
        "graphiti-backfill: GRAPHITI_MCP_URL and GRAPHITI_MCP_TOKEN must be set",
      );
    }

    const session_id = await openAgentSession(
      "graphiti-backfill",
      null,
      ctx.run.id ?? null,
    );
    const step_index_ref = { value: 0 };

    try {
      const nodes = await backfillOnaNodes(session_id, step_index_ref);
      logger.info("graphiti-backfill ona_nodes done", nodes);

      const edges = await backfillOnaEdges(session_id, step_index_ref);
      logger.info("graphiti-backfill ona_edges done", edges);

      const t0 = await backfillTier0(session_id, step_index_ref);
      logger.info("graphiti-backfill tier0_observations done", t0);

      await closeAgentSession(session_id, "completed", {
        input_tokens: 0,
        output_tokens: 0,
        cache_read_tokens: 0,
      });

      return {
        session_id,
        ona_nodes: nodes,
        ona_edges: edges,
        tier0_observations: t0,
      };
    } catch (err) {
      await closeAgentSession(session_id, "failed", {
        input_tokens: 0,
        output_tokens: 0,
        cache_read_tokens: 0,
      });
      throw err;
    }
  },
});
