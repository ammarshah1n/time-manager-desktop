/**
 * Tool registration for skill-library-mcp.
 *
 * Tool names and signatures are the public contract. Do not rename.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { Db } from "./db.js";
import type { VoyageClient } from "./voyage.js";

export interface ToolDeps {
  db: Db;
  voyage: VoyageClient;
}

function jsonResult(value: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(value) }],
    structuredContent: value as Record<string, unknown>,
  };
}

export function registerTools(server: McpServer, deps: ToolDeps): void {
  const { db, voyage } = deps;

  server.registerTool(
    "retrieve_skills",
    {
      title: "Retrieve skills",
      description:
        "Embed context_text via Voyage voyage-3 (1024-dim) and run cosine k-NN against skills.embedding. Only active (non-retired) skills are returned.",
      inputSchema: {
        context_text: z.string().min(1),
        top_k: z.number().int().min(1).max(50).default(5),
      },
    },
    async ({ context_text, top_k }) => {
      const embedding = await voyage.embed(context_text, "query");
      const skills = await db.retrieveSkills(embedding, top_k);
      return jsonResult({ skills });
    }
  );

  server.registerTool(
    "write_skill",
    {
      title: "Write skill",
      description:
        "Persist a new procedural skill. Embeds procedure_text via Voyage voyage-3 (document mode). creation_context is stored verbatim as JSONB.",
      inputSchema: {
        name: z.string().min(1).max(200),
        procedure_text: z.string().min(1),
        creation_context: z.record(z.unknown()).default({}),
        creation_session_id: z.string().uuid().optional(),
      },
    },
    async ({ name, procedure_text, creation_context, creation_session_id }) => {
      const embedding = await voyage.embed(procedure_text, "document");
      const result = await db.writeSkill({
        name,
        procedure_text,
        creation_context,
        embedding,
        creation_session_id: creation_session_id ?? null,
      });
      return jsonResult(result);
    }
  );

  server.registerTool(
    "record_skill_usage",
    {
      title: "Record skill usage",
      description:
        "Atomically increment usage/success/failure counters and stamp last_used_at. outcome must be 'success' or 'failure'. Notes are appended into creation_context.last_usage for auditability.",
      inputSchema: {
        skill_id: z.string().uuid(),
        outcome: z.enum(["success", "failure"]),
        session_id: z.string().uuid(),
        notes: z.string().default(""),
      },
    },
    async ({ skill_id, outcome, session_id, notes }) => {
      await db.recordUsage({ skill_id, outcome, session_id, notes });
      return jsonResult({ ok: true });
    }
  );
}
