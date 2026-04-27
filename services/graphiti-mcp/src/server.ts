/**
 * graphiti-mcp — MCP server exposed as a Fly.io HTTP service with bearer auth.
 *
 * Transport: Streamable HTTP (stateless). Every POST /mcp spins up a fresh
 * transport wired to the same `McpServer` instance — simpler than session
 * management and plenty for our single-tenant load.
 *
 * Auth: Bearer token matched against `GRAPHITI_MCP_TOKEN`. We do NOT use
 * Express's JSON middleware for /mcp because the MCP SDK's transport is a
 * Node http handler and prefers the pre-parsed body shortcut via
 * `transport.handleRequest(req, res, req.body)`. We adopt that shortcut and
 * keep the JSON body parsed by Express.
 */

import { timingSafeEqual } from "node:crypto";

import express, { type Request, type Response, type NextFunction } from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { loadConfig } from "./config.js";
import { GraphitiClient } from "./graphitiClient.js";
import { Neo4jClient } from "./neo4j.js";
import { SnapshotService } from "./snapshot.js";
import { registerTools } from "./tools.js";

const cfg = loadConfig();

const neo4j = new Neo4jClient(cfg);
const graphiti = new GraphitiClient(cfg.graphitiUrl);
const snapshot = new SnapshotService(cfg, neo4j);

const server = new McpServer(
  { name: "graphiti-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } }
);
registerTools(server, { neo4j, graphiti, snapshot });

function bearerAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.header("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }
  const provided = Buffer.from(match[1]!);
  const expected = Buffer.from(cfg.mcpToken);
  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }
  next();
}

const app = express();
app.use(express.json({ limit: "32mb" })); // add_episode inbound payloads can be chunky

app.get("/healthz", (_req, res) => {
  res.status(200).json({ ok: true });
});

app.get("/readyz", async (_req, res) => {
  try {
    await neo4j.ping();
    res.status(200).json({ ok: true });
  } catch (err) {
    res.status(503).json({ ok: false, error: (err as Error).message });
  }
});

// Every MCP request creates a fresh stateless transport that shares the
// singleton McpServer. This is the pattern recommended by the SDK for
// service-style deployments.
app.post("/mcp", bearerAuth, async (req: Request, res: Response) => {
  try {
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on("close", () => {
      transport.close().catch(() => {
        /* swallow — client already gone */
      });
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error("mcp handler failed", err);
    if (!res.headersSent) {
      res.status(500).json({ error: (err as Error).message });
    }
  }
});

const httpServer = app.listen(cfg.port, () => {
  // eslint-disable-next-line no-console
  console.log(`graphiti-mcp listening on :${cfg.port}`);
});

async function shutdown(signal: string): Promise<void> {
  // eslint-disable-next-line no-console
  console.log(`${signal} received, shutting down`);
  httpServer.close();
  await server.close();
  await neo4j.close();
  process.exit(0);
}

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});
process.on("SIGINT", () => {
  void shutdown("SIGINT");
});
