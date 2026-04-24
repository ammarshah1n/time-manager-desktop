/**
 * `export_snapshot` implementation — dumps Neo4j via apoc.export.json.all,
 * uploads to Supabase Storage bucket `kg-snapshots/` keyed by ISO week +
 * session_id.
 */

import { createClient, SupabaseClient } from "@supabase/supabase-js";
import type { Config } from "./config.js";
import type { Neo4jClient } from "./neo4j.js";

/** ISO week (YYYY-Www) for a given date. */
export function isoWeek(d: Date): string {
  // Week number per ISO 8601. Copied pattern; kept inline to avoid dragging a
  // dep for a single function.
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const weekNum = Math.ceil(((date.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(weekNum).padStart(2, "0")}`;
}

export class SnapshotService {
  private readonly supabase: SupabaseClient;

  constructor(
    private readonly cfg: Pick<Config, "supabaseUrl" | "supabaseServiceRoleKey" | "snapshotBucket">,
    private readonly neo4j: Neo4jClient
  ) {
    this.supabase = createClient(cfg.supabaseUrl, cfg.supabaseServiceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  async export(sessionId: string, now: Date = new Date()): Promise<{
    storage_path: string;
    node_count: number;
    relationship_count: number;
    size_bytes: number;
  }> {
    const dump = await this.neo4j.exportSnapshotJson();
    const week = isoWeek(now);
    const storagePath = `${week}/${sessionId}.json`;
    const payload = new Blob([dump.data], { type: "application/json" });

    const { error } = await this.supabase.storage
      .from(this.cfg.snapshotBucket)
      .upload(storagePath, payload, {
        contentType: "application/json",
        upsert: true,
      });
    if (error) {
      throw new Error(`supabase storage upload failed: ${error.message}`);
    }

    return {
      storage_path: `${this.cfg.snapshotBucket}/${storagePath}`,
      node_count: dump.nodes,
      relationship_count: dump.relationships,
      size_bytes: dump.data.length,
    };
  }
}
