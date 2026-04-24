/**
 * Thin Neo4j client wrapper.
 *
 * Graphiti's Python service (task 14) owns writes that need entity extraction
 * (`add_episode`). Everything else — searches, timelines, invalidation,
 * snapshots — is a cypher call and is faster to do directly than through a
 * second HTTP hop.
 *
 * Cypher conventions used by Graphiti (confirmed via getzep/graphiti source):
 *   - Episode nodes: (:Episodic { uuid, name, content, created_at, valid_at, group_id })
 *   - Entity nodes:  (:Entity   { uuid, name, summary, group_id, created_at })
 *   - Facts (edges): (src:Entity)-[:RELATES_TO { uuid, fact, valid_at, invalid_at, expired_at, episodes }]->(dst:Entity)
 *
 * We keep those names stable across this file so upgrades to Graphiti are
 * easy to spot.
 */

import neo4j, { Driver, Session } from "neo4j-driver";
import type { Config } from "./config.js";

export interface EpisodeRow {
  uuid: string;
  name: string;
  content: string;
  created_at: string;
  valid_at: string | null;
  group_id: string | null;
  content_hash: string | null;
}

export interface FactRow {
  uuid: string;
  fact: string;
  source_uuid: string;
  source_name: string;
  target_uuid: string;
  target_name: string;
  valid_at: string | null;
  invalid_at: string | null;
  expired_at: string | null;
  episodes: string[];
}

export interface EntityRelationshipRow {
  direction: "out" | "in";
  depth: number;
  peer_uuid: string;
  peer_name: string;
  fact: string;
  valid_at: string | null;
  invalid_at: string | null;
  expired_at: string | null;
}

export interface CommunityRow {
  uuid: string;
  name: string;
  summary: string | null;
  member_count: number;
}

export class Neo4jClient {
  private readonly driver: Driver;

  constructor(cfg: Pick<Config, "neo4jUri" | "neo4jUser" | "neo4jPassword">) {
    this.driver = neo4j.driver(
      cfg.neo4jUri,
      neo4j.auth.basic(cfg.neo4jUser, cfg.neo4jPassword),
      { disableLosslessIntegers: true }
    );
  }

  async close(): Promise<void> {
    await this.driver.close();
  }

  private async run<T>(fn: (s: Session) => Promise<T>): Promise<T> {
    const session = this.driver.session();
    try {
      return await fn(session);
    } finally {
      await session.close();
    }
  }

  async ping(): Promise<void> {
    await this.run(async (s) => {
      await s.run("RETURN 1");
    });
  }

  async searchEpisodes(
    query: string,
    timeWindow?: { from?: string; to?: string }
  ): Promise<EpisodeRow[]> {
    // Simple BM25-style match on content + name. Graphiti also builds vector
    // indices; when the Python service is the caller it uses the full hybrid
    // search. For the MCP server we expose the lighter path + client can pass
    // a time window filter.
    const cypher = `
      MATCH (e:Episodic)
      WHERE (
        toLower(e.content) CONTAINS toLower($query) OR
        toLower(coalesce(e.name, '')) CONTAINS toLower($query)
      )
      ${timeWindow?.from ? "AND e.valid_at >= datetime($from)" : ""}
      ${timeWindow?.to ? "AND e.valid_at <= datetime($to)" : ""}
      RETURN e.uuid AS uuid, e.name AS name, e.content AS content,
             toString(e.created_at) AS created_at,
             toString(e.valid_at) AS valid_at,
             e.group_id AS group_id,
             e.content_hash AS content_hash
      ORDER BY e.valid_at DESC
      LIMIT 50
    `;
    const rows = await this.run((s) =>
      s.run(cypher, {
        query,
        from: timeWindow?.from ?? null,
        to: timeWindow?.to ?? null,
      })
    );
    return rows.records.map((r) => ({
      uuid: r.get("uuid"),
      name: r.get("name"),
      content: r.get("content"),
      created_at: r.get("created_at"),
      valid_at: r.get("valid_at"),
      group_id: r.get("group_id"),
      content_hash: r.get("content_hash"),
    }));
  }

  async searchFacts(query: string, validAt?: string): Promise<FactRow[]> {
    // Temporal retrieval: a fact is "true at T" iff
    //   valid_at <= T AND (invalid_at IS NULL OR invalid_at > T) AND (expired_at IS NULL OR expired_at > T)
    const cypher = `
      MATCH (a:Entity)-[r:RELATES_TO]->(b:Entity)
      WHERE toLower(r.fact) CONTAINS toLower($query)
      ${
        validAt
          ? `AND (r.valid_at IS NULL OR r.valid_at <= datetime($validAt))
             AND (r.invalid_at IS NULL OR r.invalid_at > datetime($validAt))
             AND (r.expired_at IS NULL OR r.expired_at > datetime($validAt))`
          : "AND r.expired_at IS NULL"
      }
      RETURN r.uuid AS uuid, r.fact AS fact,
             a.uuid AS source_uuid, a.name AS source_name,
             b.uuid AS target_uuid, b.name AS target_name,
             toString(r.valid_at) AS valid_at,
             toString(r.invalid_at) AS invalid_at,
             toString(r.expired_at) AS expired_at,
             coalesce(r.episodes, []) AS episodes
      ORDER BY r.valid_at DESC
      LIMIT 50
    `;
    const rows = await this.run((s) =>
      s.run(cypher, { query, validAt: validAt ?? null })
    );
    return rows.records.map((r) => ({
      uuid: r.get("uuid"),
      fact: r.get("fact"),
      source_uuid: r.get("source_uuid"),
      source_name: r.get("source_name"),
      target_uuid: r.get("target_uuid"),
      target_name: r.get("target_name"),
      valid_at: r.get("valid_at"),
      invalid_at: r.get("invalid_at"),
      expired_at: r.get("expired_at"),
      episodes: r.get("episodes") as string[],
    }));
  }

  async getEntityTimeline(entityId: string): Promise<FactRow[]> {
    const cypher = `
      MATCH (a:Entity { uuid: $entityId })-[r:RELATES_TO]-(b:Entity)
      RETURN r.uuid AS uuid, r.fact AS fact,
             a.uuid AS source_uuid, a.name AS source_name,
             b.uuid AS target_uuid, b.name AS target_name,
             toString(r.valid_at) AS valid_at,
             toString(r.invalid_at) AS invalid_at,
             toString(r.expired_at) AS expired_at,
             coalesce(r.episodes, []) AS episodes
      ORDER BY r.valid_at DESC
    `;
    const rows = await this.run((s) => s.run(cypher, { entityId }));
    return rows.records.map((r) => ({
      uuid: r.get("uuid"),
      fact: r.get("fact"),
      source_uuid: r.get("source_uuid"),
      source_name: r.get("source_name"),
      target_uuid: r.get("target_uuid"),
      target_name: r.get("target_name"),
      valid_at: r.get("valid_at"),
      invalid_at: r.get("invalid_at"),
      expired_at: r.get("expired_at"),
      episodes: r.get("episodes") as string[],
    }));
  }

  async getEntityRelationships(
    entityId: string,
    depth: number
  ): Promise<EntityRelationshipRow[]> {
    // Clamp depth — unbounded expansion on a temporal KG is a footgun.
    const clamped = Math.max(1, Math.min(depth, 3));
    // Emit one row per edge along the path, with peer = the node at the OTHER
    // end of THAT specific edge (not the terminal node of the walk).
    const cypher = `
      MATCH (root:Entity { uuid: $entityId })
      CALL {
        WITH root
        MATCH path = (root)-[:RELATES_TO*1..${clamped}]-(leaf:Entity)
        WITH relationships(path) AS rels, nodes(path) AS ns
        UNWIND range(0, size(rels) - 1) AS i
        WITH rels[i] AS r, ns[i] AS u, ns[i + 1] AS v, i + 1 AS d
        WHERE r.expired_at IS NULL
        RETURN DISTINCT r, u, v, d
      }
      WITH r, u, v, d,
           CASE WHEN startNode(r).uuid = u.uuid THEN 'out' ELSE 'in' END AS direction,
           CASE WHEN startNode(r).uuid = u.uuid THEN v ELSE u END AS peer
      RETURN direction, d AS depth,
             peer.uuid AS peer_uuid, peer.name AS peer_name,
             r.fact AS fact,
             toString(r.valid_at) AS valid_at,
             toString(r.invalid_at) AS invalid_at,
             toString(r.expired_at) AS expired_at
      ORDER BY d ASC, peer.name ASC
      LIMIT 200
    `;
    const rows = await this.run((s) => s.run(cypher, { entityId }));
    return rows.records.map((r) => ({
      direction: r.get("direction") as "out" | "in",
      depth: Number(r.get("depth")),
      peer_uuid: r.get("peer_uuid"),
      peer_name: r.get("peer_name"),
      fact: r.get("fact"),
      valid_at: r.get("valid_at"),
      invalid_at: r.get("invalid_at"),
      expired_at: r.get("expired_at"),
    }));
  }

  /**
   * Look up an episode by its externally-computed content_hash. Graphiti does
   * not natively dedupe on external identifiers — this exists so backfill and
   * batch-consume retries can skip already-ingested material.
   */
  async episodeExists(contentHash: string): Promise<{ episode_id: string } | null> {
    const cypher = `
      MATCH (e:Episodic { content_hash: $contentHash })
      RETURN e.uuid AS uuid
      LIMIT 1
    `;
    const rows = await this.run((s) => s.run(cypher, { contentHash }));
    const rec = rows.records[0];
    if (!rec) return null;
    return { episode_id: rec.get("uuid") as string };
  }

  /**
   * Stamp the content_hash onto the Episodic node after Graphiti's service
   * creates it. Graphiti does not persist external hashes by default.
   */
  async stampEpisodeHash(episodeUuid: string, contentHash: string): Promise<void> {
    const cypher = `
      MATCH (e:Episodic { uuid: $episodeUuid })
      SET e.content_hash = $contentHash
    `;
    await this.run((s) => s.run(cypher, { episodeUuid, contentHash }));
  }

  /**
   * Write a fact directly (bypasses Graphiti's extraction). Used by the NREM
   * A-MEM / Nemori loops which already know the triple they want to persist.
   * Entities are merged by name; edges are keyed by subject+predicate+object+valid_from.
   */
  async addFact(
    subject: string,
    predicate: string,
    object_: string,
    validFrom: string | null,
    validTo: string | null,
    evidenceEpisodeIds: string[]
  ): Promise<{ fact_id: string }> {
    const cypher = `
      MERGE (a:Entity { name: $subject })
      ON CREATE SET a.uuid = randomUUID(), a.created_at = datetime()
      MERGE (b:Entity { name: $object })
      ON CREATE SET b.uuid = randomUUID(), b.created_at = datetime()
      CREATE (a)-[r:RELATES_TO {
        uuid: randomUUID(),
        fact: $predicate,
        valid_at: CASE WHEN $validFrom IS NULL THEN null ELSE datetime($validFrom) END,
        invalid_at: CASE WHEN $validTo IS NULL THEN null ELSE datetime($validTo) END,
        expired_at: null,
        episodes: $evidence,
        created_at: datetime()
      }]->(b)
      RETURN r.uuid AS uuid
    `;
    const rows = await this.run((s) =>
      s.run(cypher, {
        subject,
        predicate,
        object: object_,
        validFrom,
        validTo,
        evidence: evidenceEpisodeIds,
      })
    );
    const rec = rows.records[0];
    if (!rec) throw new Error("addFact: no row returned");
    return { fact_id: rec.get("uuid") as string };
  }

  async invalidateFact(
    factId: string,
    reason: string,
    invalidatedAt: string
  ): Promise<void> {
    const cypher = `
      MATCH ()-[r:RELATES_TO { uuid: $factId }]->()
      SET r.invalid_at = datetime($invalidatedAt),
          r.expired_at = datetime($invalidatedAt),
          r.invalidation_reason = $reason
    `;
    await this.run((s) => s.run(cypher, { factId, invalidatedAt, reason }));
  }

  async listCommunities(): Promise<CommunityRow[]> {
    // Communities are optional in Graphiti. We match loosely so the tool
    // returns an empty list rather than erroring when the label isn't there.
    const cypher = `
      MATCH (c:Community)
      OPTIONAL MATCH (c)<-[:MEMBER_OF]-(m:Entity)
      RETURN c.uuid AS uuid, c.name AS name, c.summary AS summary, count(m) AS member_count
      ORDER BY member_count DESC
      LIMIT 100
    `;
    const rows = await this.run((s) => s.run(cypher));
    return rows.records.map((r) => ({
      uuid: r.get("uuid"),
      name: r.get("name"),
      summary: r.get("summary"),
      member_count: Number(r.get("member_count")),
    }));
  }

  /**
   * Dumps the entire graph via `apoc.export.json.all` to a string. The caller
   * uploads the string to Supabase Storage. APOC writes to a local file on
   * the Neo4j host; to stream it back we use `stream: true` which returns
   * a single row with a `data` field containing the JSON payload.
   *
   * Reference: apoc.export.json.all(file, {stream:true}) returns
   *   { file, source, format, nodes, relationships, properties, time, rows, batchSize, batches, done, data }
   */
  async exportSnapshotJson(): Promise<{
    data: string;
    nodes: number;
    relationships: number;
  }> {
    const cypher = `
      CALL apoc.export.json.all(null, { stream: true, useTypes: true })
      YIELD data, nodes, relationships
      RETURN data, nodes, relationships
    `;
    const rows = await this.run((s) => s.run(cypher));
    const rec = rows.records[0];
    if (!rec) throw new Error("exportSnapshotJson: no row returned");
    return {
      data: rec.get("data") as string,
      nodes: Number(rec.get("nodes")),
      relationships: Number(rec.get("relationships")),
    };
  }
}
