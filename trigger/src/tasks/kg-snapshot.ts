/**
 * Timed overnight cognitive OS — T28a: weekly knowledge-graph snapshot.
 *
 * Cron: Sunday 03:45 UTC. Drives a single `export_snapshot` call on
 * graphiti-mcp, which in turn runs `apoc.export.json.all` against Neo4j,
 * uploads the dump to Supabase Storage bucket
 * `kg-snapshots/<YYYY-WW>/<session_id>.json`, and returns
 * { storage_path, node_count, relationship_count | rel_count, size_bytes }.
 *
 * The task opens an agent_sessions envelope via `openAgentSession`, calls the
 * MCP tool via `callMcpTool` (which handles JSON-RPC + Streamable HTTP), and
 * records one `kg_snapshots` row per successful snapshot. Retention: the
 * 52 most recent rows per executive are kept, older rows are deleted.
 *
 * Pragmatic defaults:
 *   - exec_id uses the same resolver as rem-synthesis (YASSER_EMAIL first,
 *     fall back to oldest executives row). Single-exec system for now.
 *   - The MCP response field is `relationship_count` (per snapshot.ts) but
 *     the ledger column is `rel_count` (per schema). We read either key.
 *   - Retention runs as a DELETE ... WHERE id NOT IN (keep-list) scoped to
 *     exec_id — safe even if two snapshots happen to land in the same ISO
 *     week.
 */

import { schedules, logger } from "@trigger.dev/sdk";

import { getSupabaseServiceRole } from "../lib/supabase.js";
import {
  openAgentSession,
  closeAgentSession,
  callMcpTool,
  traceToolCall,
} from "../lib/trace-tool-results.js";

// ---------------------------------------------------------------------------
// Env helpers
// ---------------------------------------------------------------------------

function readEnv(key: string): string | undefined {
  const value = process["env"][key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

async function resolveYasserExecId(): Promise<string> {
  const sb = getSupabaseServiceRole();
  const email = readEnv("YASSER_EMAIL");

  if (email) {
    const { data, error } = await sb
      .from("executives")
      .select("id")
      .eq("email", email)
      .limit(1)
      .maybeSingle();
    if (error) throw new Error(`executives lookup by email failed: ${error.message}`);
    if (data?.id) return data.id as string;
    logger.warn(
      "kg-snapshot: YASSER_EMAIL set but no matching executives row; falling back to oldest row",
    );
  }

  const { data, error } = await sb
    .from("executives")
    .select("id")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw new Error(`executives fallback lookup failed: ${error.message}`);
  if (!data?.id) throw new Error("kg-snapshot: no executives row found");
  return data.id as string;
}

// ---------------------------------------------------------------------------
// ISO week — duplicate of services/graphiti-mcp/src/snapshot.ts::isoWeek so
// the column is populated locally even if the MCP payload omits it.
// ---------------------------------------------------------------------------

function isoWeek(d: Date): string {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const weekNum = Math.ceil(
    ((date.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7,
  );
  return `${date.getUTCFullYear()}-W${String(weekNum).padStart(2, "0")}`;
}

// ---------------------------------------------------------------------------
// MCP payload parsing
// ---------------------------------------------------------------------------

/**
 * Snapshot fields we expect from graphiti-mcp `export_snapshot`. The MCP
 * server emits these as `structuredContent` AND as a JSON-encoded text
 * block (see services/graphiti-mcp/src/tools.ts::jsonResult). We read the
 * text block because `callMcpTool` returns `result.content`, which is the
 * content-block array only.
 */
type SnapshotPayload = {
  storage_path: string;
  node_count?: number;
  relationship_count?: number;
  rel_count?: number;
  size_bytes?: number;
};

type McpTextBlock = { type: "text"; text: string };

function extractSnapshotPayload(content: unknown): SnapshotPayload {
  if (!Array.isArray(content) || content.length === 0) {
    throw new Error("kg-snapshot: export_snapshot returned empty content");
  }
  for (const entry of content) {
    if (
      entry &&
      typeof entry === "object" &&
      (entry as { type?: unknown }).type === "text" &&
      typeof (entry as McpTextBlock).text === "string"
    ) {
      const text = (entry as McpTextBlock).text;
      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        continue;
      }
      if (parsed && typeof parsed === "object" && "storage_path" in parsed) {
        return parsed as SnapshotPayload;
      }
    }
  }
  throw new Error(
    "kg-snapshot: could not find storage_path in export_snapshot response",
  );
}

// ---------------------------------------------------------------------------
// Task body
// ---------------------------------------------------------------------------

export const kgSnapshot = schedules.task({
  id: "kg-snapshot",
  cron: "45 3 * * 0",
  maxDuration: 900,
  run: async (payload, { ctx }) => {
    logger.info("kg-snapshot starting", { timestamp: payload.timestamp });

    const execId = await resolveYasserExecId();
    const triggerRunId = ctx.run?.id ?? null;

    const sessionId = await openAgentSession("kg-snapshot", execId, triggerRunId);
    logger.info("kg-snapshot session opened", {
      session_id: sessionId,
      exec_id: execId,
    });

    let stepIndex = 0;

    try {
      const startedAt = Date.now();
      const rawContent = await callMcpTool(
        "export_snapshot",
        { session_id: sessionId },
        { server: "graphiti" },
      );
      const latencyMs = Date.now() - startedAt;

      await traceToolCall({
        session_id: sessionId,
        step_index: stepIndex++,
        tool_name: "export_snapshot",
        input: { session_id: sessionId },
        output: rawContent,
        latency_ms: latencyMs,
      });

      const snap = extractSnapshotPayload(rawContent);
      const relCount = snap.rel_count ?? snap.relationship_count ?? null;

      const sb = getSupabaseServiceRole();
      const week = isoWeek(new Date());

      const { data: inserted, error: insertErr } = await sb
        .from("kg_snapshots")
        .insert({
          session_id: sessionId,
          exec_id: execId,
          week,
          storage_path: snap.storage_path,
          node_count: snap.node_count ?? null,
          rel_count: relCount,
          size_bytes: snap.size_bytes ?? null,
        })
        .select("id")
        .single();
      if (insertErr) {
        throw new Error(`kg_snapshots insert failed: ${insertErr.message}`);
      }
      if (!inserted) {
        throw new Error("kg_snapshots insert returned no row");
      }

      // Retention — keep the 52 most recent snapshots per executive. The
      // NOT IN (keep-list) form is scoped by exec_id on both sides so a
      // multi-exec future still behaves per-exec.
      const { data: keepRows, error: keepErr } = await sb
        .from("kg_snapshots")
        .select("id")
        .eq("exec_id", execId)
        .order("week", { ascending: false })
        .limit(52);
      if (keepErr) {
        throw new Error(`kg_snapshots retention select failed: ${keepErr.message}`);
      }
      const keepIds = (keepRows ?? []).map((r) => r.id as string);
      if (keepIds.length > 0) {
        const { error: delErr } = await sb
          .from("kg_snapshots")
          .delete()
          .eq("exec_id", execId)
          .not("id", "in", `(${keepIds.join(",")})`);
        if (delErr) {
          // Retention failure must not fail the whole run — the snapshot
          // is already durable. Log and keep going.
          logger.warn("kg-snapshot retention delete failed", { error: delErr.message });
        }
      }

      await closeAgentSession(sessionId, "completed", {
        input_tokens: 0,
        output_tokens: 0,
        cache_read_tokens: 0,
      });

      logger.info("kg-snapshot completed", {
        session_id: sessionId,
        storage_path: snap.storage_path,
        week,
        node_count: snap.node_count,
        rel_count: relCount,
        size_bytes: snap.size_bytes,
      });

      return {
        session_id: sessionId,
        storage_path: snap.storage_path,
        week,
        node_count: snap.node_count ?? null,
        rel_count: relCount,
        size_bytes: snap.size_bytes ?? null,
      };
    } catch (err) {
      await closeAgentSession(sessionId, "failed", {
        input_tokens: 0,
        output_tokens: 0,
        cache_read_tokens: 0,
      }).catch(() => undefined);
      logger.error("kg-snapshot failed", { error: (err as Error).message });
      throw err;
    }
  },
});
