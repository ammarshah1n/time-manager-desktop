/**
 * Supabase data-access thin layer. Service role is used so the server bypasses
 * RLS (see `20260413000000_service_role_rls_bypass.sql`). We intentionally do
 * NOT expose raw SQL to MCP callers — every operation goes through an RPC or
 * a narrow `.from().insert()`.
 */

import { createClient, SupabaseClient } from "@supabase/supabase-js";
import type { Config } from "./config.js";

export interface RetrievedSkill {
  id: string;
  name: string;
  procedure_text: string;
  creation_context: Record<string, unknown>;
  usage_count: number;
  success_count: number;
  failure_count: number;
  last_used_at: string | null;
  similarity: number;
}

export class Db {
  private readonly client: SupabaseClient;

  constructor(cfg: Pick<Config, "supabaseUrl" | "supabaseServiceRoleKey">) {
    this.client = createClient(cfg.supabaseUrl, cfg.supabaseServiceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  async retrieveSkills(
    queryEmbedding: number[],
    topK: number
  ): Promise<RetrievedSkill[]> {
    const { data, error } = await this.client.rpc("retrieve_skills", {
      query_embedding: queryEmbedding,
      top_k: topK,
    });
    if (error) throw new Error(`retrieve_skills rpc: ${error.message}`);
    return (data ?? []) as RetrievedSkill[];
  }

  async writeSkill(args: {
    name: string;
    procedure_text: string;
    creation_context: Record<string, unknown>;
    embedding: number[];
    creation_session_id?: string | null;
  }): Promise<{ id: string }> {
    const { data, error } = await this.client
      .from("skills")
      .insert({
        name: args.name,
        procedure_text: args.procedure_text,
        creation_context: args.creation_context,
        embedding: args.embedding,
        creation_session_id: args.creation_session_id ?? null,
      })
      .select("id")
      .single();
    if (error) throw new Error(`skills insert: ${error.message}`);
    return { id: (data as { id: string }).id };
  }

  async recordUsage(args: {
    skill_id: string;
    outcome: "success" | "failure";
    session_id: string;
    notes: string;
  }): Promise<void> {
    const { error } = await this.client.rpc("record_skill_usage", {
      p_skill_id: args.skill_id,
      p_outcome: args.outcome,
      p_session_id: args.session_id,
      p_notes: args.notes,
    });
    if (error) throw new Error(`record_skill_usage rpc: ${error.message}`);
  }

  async ping(): Promise<void> {
    // Cheap RPC-less probe: read 1 row with a filter that returns nothing.
    const { error } = await this.client
      .from("skills")
      .select("id", { head: true, count: "exact" })
      .limit(1);
    if (error) throw new Error(`skills ping: ${error.message}`);
  }
}
