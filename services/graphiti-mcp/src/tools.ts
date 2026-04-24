/**
 * Tool registration for the graphiti MCP server.
 *
 * Exported tool names and argument shapes are the PUBLIC CONTRACT consumed by
 * Trigger.dev tasks and Claude agents. Do not rename without a migration.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { GraphitiClient } from "./graphitiClient.js";
import type { Neo4jClient } from "./neo4j.js";
import type { SnapshotService } from "./snapshot.js";

export interface ToolDeps {
  neo4j: Neo4jClient;
  graphiti: GraphitiClient;
  snapshot: SnapshotService;
}

/**
 * Helper — wraps a structured-JSON result into the MCP CallToolResult shape
 * with both a human-readable text block and machine-readable structuredContent.
 */
function jsonResult(value: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(value) }],
    structuredContent: value as Record<string, unknown>,
  };
}

export function registerTools(server: McpServer, deps: ToolDeps): void {
  const { neo4j, graphiti, snapshot } = deps;

  server.registerTool(
    "search_episodes",
    {
      title: "Search episodes",
      description:
        "Full-text search across episode content in the temporal knowledge graph. Optional time_window filters by episode valid_at timestamp.",
      inputSchema: {
        query: z.string().min(1),
        time_window: z
          .object({
            from: z.string().datetime().optional(),
            to: z.string().datetime().optional(),
          })
          .optional(),
      },
    },
    async ({ query, time_window }) => {
      const rows = await neo4j.searchEpisodes(query, time_window);
      return jsonResult({ episodes: rows });
    }
  );

  server.registerTool(
    "search_facts",
    {
      title: "Search facts",
      description:
        "Search facts (entity-entity edges) in the KG. When valid_at is provided, returns facts that were TRUE AT THAT TIME (temporal retrieval honouring valid_at / invalid_at / expired_at).",
      inputSchema: {
        query: z.string().min(1),
        valid_at: z.string().datetime().optional(),
      },
    },
    async ({ query, valid_at }) => {
      const rows = await neo4j.searchFacts(query, valid_at);
      return jsonResult({ facts: rows });
    }
  );

  server.registerTool(
    "get_entity_timeline",
    {
      title: "Get entity timeline",
      description:
        "Return every fact (edge) incident to the entity, newest first, including invalidated ones — the full evolutionary record.",
      inputSchema: {
        entity_id: z.string().min(1),
      },
    },
    async ({ entity_id }) => {
      const rows = await neo4j.getEntityTimeline(entity_id);
      return jsonResult({ facts: rows });
    }
  );

  server.registerTool(
    "get_entity_relationships",
    {
      title: "Get entity relationships",
      description:
        "Return peers reachable from the entity via RELATES_TO edges up to a given depth (max 3). Only currently-valid edges (expired_at IS NULL) are returned.",
      inputSchema: {
        entity_id: z.string().min(1),
        depth: z.number().int().min(1).max(3),
      },
    },
    async ({ entity_id, depth }) => {
      const rows = await neo4j.getEntityRelationships(entity_id, depth);
      return jsonResult({ relationships: rows });
    }
  );

  server.registerTool(
    "add_episode",
    {
      title: "Add episode",
      description:
        "Submit an episode for ingestion. Routes through Graphiti's entity-extraction pipeline (Sonnet via inference proxy) and stamps the externally-provided content_hash onto the resulting Episodic node so episode_exists() can dedupe on future retries. entity_refs is forwarded as a group_id hint.",
      inputSchema: {
        content: z.string().min(1),
        timestamp: z.string().datetime(),
        entity_refs: z.array(z.string()).optional(),
        content_hash: z.string().min(1),
      },
    },
    async ({ content, timestamp, entity_refs, content_hash }) => {
      // Idempotency — caller is expected to pre-check via episode_exists, but
      // we also guard here to make the tool safe under concurrent retries.
      const existing = await neo4j.episodeExists(content_hash);
      if (existing) {
        return jsonResult({ episode_id: existing.episode_id, deduped: true });
      }
      const res = await graphiti.addEpisode({
        name: `episode-${content_hash.slice(0, 12)}`,
        episode_body: content,
        reference_time: timestamp,
        group_id: entity_refs && entity_refs.length > 0 ? entity_refs[0] : null,
        source: "text",
      });
      if (res.episode_uuid) {
        await neo4j.stampEpisodeHash(res.episode_uuid, content_hash);
      }
      return jsonResult({ episode_id: res.episode_uuid, deduped: false });
    }
  );

  server.registerTool(
    "episode_exists",
    {
      title: "Episode exists",
      description:
        "Idempotency probe — returns { episode_id } if an Episodic node with this content_hash exists, otherwise null. Mandatory for backfill/retry flows; Graphiti has no native external-id dedupe.",
      inputSchema: {
        content_hash: z.string().min(1),
      },
    },
    async ({ content_hash }) => {
      const hit = await neo4j.episodeExists(content_hash);
      return jsonResult(hit);
    }
  );

  server.registerTool(
    "add_fact",
    {
      title: "Add fact",
      description:
        "Insert an (subject, predicate, object) triple as a RELATES_TO edge with temporal validity and evidence links back to episodes. Bypasses Graphiti extraction — use this when the caller (e.g. NREM A-MEM loop) already knows the triple.",
      inputSchema: {
        subject: z.string().min(1),
        predicate: z.string().min(1),
        object: z.string().min(1),
        valid_from: z.string().datetime().nullable().optional(),
        valid_to: z.string().datetime().nullable().optional(),
        evidence_episode_ids: z.array(z.string()).default([]),
      },
    },
    async ({
      subject,
      predicate,
      object,
      valid_from,
      valid_to,
      evidence_episode_ids,
    }) => {
      const res = await neo4j.addFact(
        subject,
        predicate,
        object,
        valid_from ?? null,
        valid_to ?? null,
        evidence_episode_ids
      );
      return jsonResult(res);
    }
  );

  server.registerTool(
    "invalidate_fact",
    {
      title: "Invalidate fact",
      description:
        "Mark a fact invalidated (sets invalid_at + expired_at + invalidation_reason). Preserves the edge for temporal replay — never DELETE.",
      inputSchema: {
        fact_id: z.string().min(1),
        reason: z.string().min(1),
        invalidated_at: z.string().datetime(),
      },
    },
    async ({ fact_id, reason, invalidated_at }) => {
      await neo4j.invalidateFact(fact_id, reason, invalidated_at);
      return jsonResult({ ok: true });
    }
  );

  server.registerTool(
    "list_communities",
    {
      title: "List communities",
      description:
        "List KG communities (Graphiti's Leiden-clustered entity groups) with member counts. Returns empty list if communities have not been built yet.",
      inputSchema: {},
    },
    async () => {
      const rows = await neo4j.listCommunities();
      return jsonResult({ communities: rows });
    }
  );

  server.registerTool(
    "export_snapshot",
    {
      title: "Export snapshot",
      description:
        "Dump the Neo4j database via apoc.export.json.all and upload to Supabase Storage bucket kg-snapshots/<YYYY-WW>/<session_id>.json. Returns storage path and counts. This is the only path by which task 41's replay --mode=kg-restore can reconstruct historical graph state.",
      inputSchema: {
        session_id: z.string().min(1),
      },
    },
    async ({ session_id }) => {
      const res = await snapshot.export(session_id);
      return jsonResult(res);
    }
  );
}
