/**
 * skill-library-mcp — MCP server over Supabase + pgvector + Voyage.
 *
 * Transport: Streamable HTTP, stateless. Auth: bearer (`SKILL_LIBRARY_MCP_TOKEN`).
 */

import { timingSafeEqual } from "node:crypto";

import express, { type Request, type Response, type NextFunction } from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { loadConfig } from "./config.js";
import { Db } from "./db.js";
import { registerTools } from "./tools.js";
import { createVoyageClient } from "./voyage.js";

const cfg = loadConfig();

const db = new Db(cfg);
const voyage = createVoyageClient(cfg.voyageApiKey, cfg.voyageModel);

const server = new McpServer(
  { name: "skill-library-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } }
);
registerTools(server, { db, voyage });

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
app.use(express.json({ limit: "2mb" }));

app.get("/healthz", (_req, res) => {
  res.status(200).json({ ok: true });
});

app.get("/readyz", async (_req, res) => {
  try {
    await db.ping();
    res.status(200).json({ ok: true });
  } catch (err) {
    res.status(503).json({ ok: false, error: (err as Error).message });
  }
});

app.post("/mcp", bearerAuth, async (req: Request, res: Response) => {
  try {
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on("close", () => {
      transport.close().catch(() => {
        /* swallow */
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
  console.log(`skill-library-mcp listening on :${cfg.port}`);
});

async function shutdown(signal: string): Promise<void> {
  // eslint-disable-next-line no-console
  console.log(`${signal} received, shutting down`);
  httpServer.close();
  await server.close();
  process.exit(0);
}

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});
process.on("SIGINT", () => {
  void shutdown("SIGINT");
});
