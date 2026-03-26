#!/usr/bin/env bun
/**
 * Ralph Loop Live Dashboard
 * Serves a real-time viewer for the Codex Ralph loop running on Timed.
 * Usage: bun scripts/ralph-dashboard.ts
 */

import { readFileSync, existsSync, watchFile } from "fs";
import { join } from "path";

const PORT = 4242;
const REPO_ROOT = join(import.meta.dir, "..");
const STATE_DIR = join(REPO_ROOT, ".codex/ralph");
const PRD_JSON = join(STATE_DIR, "prd.json");
const EVENTS_LOG = join(STATE_DIR, "events.log");
const RUN_LOG = join(STATE_DIR, "run.log");

// ── Data helpers ──────────────────────────────────────────────────────────────

function readPrd() {
  if (!existsSync(PRD_JSON)) return null;
  try { return JSON.parse(readFileSync(PRD_JSON, "utf8")); } catch { return null; }
}

function readEvents(last = 50): string[] {
  if (!existsSync(EVENTS_LOG)) return [];
  return readFileSync(EVENTS_LOG, "utf8").trim().split("\n").filter(Boolean).slice(-last);
}

function readRunLogTail(lines = 80): string {
  if (!existsSync(RUN_LOG)) return "";
  const content = readFileSync(RUN_LOG, "utf8");
  return content.split("\n").slice(-lines).join("\n");
}

function getStatus() {
  const prd = readPrd();
  const events = readEvents(100);
  const lastEvent = events[events.length - 1] ?? "";
  const isRunning = existsSync(EVENTS_LOG) && (() => {
    const stats = Bun.file(EVENTS_LOG).size;
    return stats > 0 && (Date.now() - require("fs").statSync(EVENTS_LOG).mtimeMs) < 120_000;
  })();

  const currentStoryMatch = lastEvent.match(/STORY START id=(\S+)/);
  const currentStory = currentStoryMatch?.[1] ?? null;

  if (!prd) return { running: false, project: "Timed", done: 0, total: 0, stories: [], currentStory: null, events: [] };

  const stories = prd.userStories.map((s: any) => ({
    id: s.id,
    title: s.title,
    passes: s.passes,
    active: s.id === currentStory,
  }));

  const done = stories.filter((s: any) => s.passes).length;

  return {
    running: isRunning,
    project: prd.project,
    done,
    total: stories.length,
    percent: Math.round((done / stories.length) * 100),
    stories,
    currentStory,
    events: readEvents(30),
    logTail: readRunLogTail(60),
  };
}

// ── SSE clients ───────────────────────────────────────────────────────────────

const clients = new Set<ReadableStreamDefaultController>();

function broadcast() {
  const data = `data: ${JSON.stringify(getStatus())}\n\n`;
  for (const ctrl of clients) {
    try { ctrl.enqueue(new TextEncoder().encode(data)); }
    catch { clients.delete(ctrl); }
  }
}

// Watch files for changes
if (existsSync(STATE_DIR)) {
  watchFile(PRD_JSON, { interval: 3000 }, broadcast);
  watchFile(EVENTS_LOG, { interval: 2000 }, broadcast);
}
setInterval(broadcast, 5000); // heartbeat

// ── HTML ──────────────────────────────────────────────────────────────────────

const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ralph Loop — Timed</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg: #0d0d0f;
    --surface: #16161a;
    --surface2: #1e1e24;
    --border: #2a2a35;
    --red: #D32F2F;
    --green: #2e7d32;
    --green-bright: #4caf50;
    --amber: #f59e0b;
    --blue: #3b82f6;
    --muted: #6b7280;
    --text: #e8e8f0;
    --text-dim: #9999aa;
    --mono: 'JetBrains Mono', 'SF Mono', monospace;
  }

  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Inter', sans-serif;
    font-size: 14px;
    min-height: 100vh;
    display: grid;
    grid-template-rows: auto 1fr auto;
  }

  /* Header */
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 24px;
    border-bottom: 1px solid var(--border);
    background: var(--surface);
    position: sticky;
    top: 0;
    z-index: 10;
  }
  .logo {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 16px;
    font-weight: 600;
    letter-spacing: -0.3px;
  }
  .logo-dot { color: var(--red); }
  .status-pill {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 500;
    border: 1px solid var(--border);
  }
  .status-pill.running { border-color: var(--green); color: var(--green-bright); }
  .status-pill.idle { border-color: var(--muted); color: var(--muted); }
  .pulse {
    width: 7px; height: 7px;
    border-radius: 50%;
    background: var(--green-bright);
    animation: pulse 1.4s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.4; transform: scale(0.7); }
  }

  /* Layout */
  main {
    display: grid;
    grid-template-columns: 320px 1fr;
    grid-template-rows: auto 1fr;
    gap: 0;
    height: calc(100vh - 57px - 40px);
    overflow: hidden;
  }

  /* Progress bar */
  .progress-bar-wrap {
    grid-column: 1 / -1;
    padding: 16px 24px 0;
    background: var(--bg);
  }
  .progress-meta {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 8px;
  }
  .progress-label { font-size: 12px; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.08em; }
  .progress-count { font-size: 28px; font-weight: 700; }
  .progress-count span { font-size: 16px; font-weight: 400; color: var(--text-dim); }
  .bar-track {
    height: 4px;
    background: var(--surface2);
    border-radius: 2px;
    overflow: hidden;
  }
  .bar-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--red), #ef5350);
    border-radius: 2px;
    transition: width 0.6s cubic-bezier(0.4, 0, 0.2, 1);
  }

  /* Story list */
  .story-list {
    padding: 16px 12px 16px 24px;
    overflow-y: auto;
    border-right: 1px solid var(--border);
  }
  .story-list h3 {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--text-dim);
    margin-bottom: 10px;
    padding-left: 4px;
  }
  .story-row {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    padding: 8px;
    border-radius: 8px;
    margin-bottom: 2px;
    transition: background 0.15s;
  }
  .story-row:hover { background: var(--surface2); }
  .story-row.active { background: rgba(211,47,47,0.08); border: 1px solid rgba(211,47,47,0.25); }
  .story-row.done { opacity: 0.5; }
  .story-icon {
    width: 20px; height: 20px;
    border-radius: 50%;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    margin-top: 1px;
  }
  .story-icon.done { background: var(--green); color: #fff; }
  .story-icon.active { background: var(--red); color: #fff; animation: pulse 1.4s ease-in-out infinite; }
  .story-icon.pending { background: var(--surface2); color: var(--muted); border: 1px solid var(--border); }
  .story-info { flex: 1; min-width: 0; }
  .story-id { font-size: 10px; color: var(--muted); font-family: var(--mono); margin-bottom: 2px; }
  .story-title { font-size: 13px; line-height: 1.35; color: var(--text); }
  .story-row.active .story-title { color: #fff; font-weight: 500; }

  /* Right panel: events + log */
  .right-panel {
    display: grid;
    grid-template-rows: 1fr 1fr;
    overflow: hidden;
  }
  .panel-section {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    border-bottom: 1px solid var(--border);
  }
  .panel-section:last-child { border-bottom: none; }
  .panel-header {
    padding: 10px 20px 8px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--text-dim);
    border-bottom: 1px solid var(--border);
    background: var(--surface);
    display: flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
  }
  .live-badge {
    background: var(--red);
    color: #fff;
    font-size: 9px;
    padding: 1px 5px;
    border-radius: 3px;
    font-weight: 600;
    letter-spacing: 0.05em;
  }
  .log-content {
    flex: 1;
    overflow-y: auto;
    padding: 12px 20px;
    font-family: var(--mono);
    font-size: 12px;
    line-height: 1.6;
    color: var(--text-dim);
    background: var(--bg);
  }
  .log-content::-webkit-scrollbar { width: 4px; }
  .log-content::-webkit-scrollbar-track { background: transparent; }
  .log-content::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

  .event-line { margin-bottom: 2px; }
  .event-time { color: #444; }
  .event-type { font-weight: 600; }
  .event-type.start { color: var(--blue); }
  .event-type.pass { color: var(--green-bright); }
  .event-type.skip { color: var(--amber); }
  .event-type.blocked { color: var(--red); }
  .event-type.run { color: var(--muted); }
  .event-type.warn { color: var(--amber); }

  /* Footer */
  footer {
    padding: 8px 24px;
    border-top: 1px solid var(--border);
    font-size: 11px;
    color: var(--muted);
    display: flex;
    gap: 16px;
    background: var(--surface);
  }
  footer span { font-family: var(--mono); }

  .empty { color: var(--muted); font-style: italic; padding: 8px 0; }
</style>
</head>
<body>

<header>
  <div class="logo">
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
      <circle cx="11" cy="11" r="10" stroke="#D32F2F" stroke-width="1.5"/>
      <path d="M11 6v5l3 3" stroke="#D32F2F" stroke-width="1.5" stroke-linecap="round"/>
    </svg>
    Timed<span class="logo-dot"> — Ralph Loop</span>
  </div>
  <div id="status-pill" class="status-pill idle">
    <span id="pulse-dot" style="display:none" class="pulse"></span>
    <span id="status-text">Connecting…</span>
  </div>
</header>

<main>
  <div class="progress-bar-wrap">
    <div class="progress-meta">
      <span class="progress-label">Stories complete</span>
      <div class="progress-count"><span id="done-count">0</span><span> / <span id="total-count">15</span></span></div>
    </div>
    <div class="bar-track"><div id="bar-fill" class="bar-fill" style="width:0%"></div></div>
  </div>

  <div class="story-list">
    <h3>Queue</h3>
    <div id="story-list"></div>
  </div>

  <div class="right-panel">
    <div class="panel-section">
      <div class="panel-header">
        Events <span class="live-badge">LIVE</span>
      </div>
      <div class="log-content" id="events-log"><span class="empty">Waiting for events…</span></div>
    </div>
    <div class="panel-section">
      <div class="panel-header">
        Codex Output (last 60 lines)
      </div>
      <div class="log-content" id="run-log"><span class="empty">No output yet…</span></div>
    </div>
  </div>
</main>

<footer>
  <span>Project: <b id="footer-project">Timed</b></span>
  <span id="footer-time"></span>
</footer>

<script>
function formatEvent(line) {
  const m = line.match(/^\\[([^\\]]+)\\] (\\S+)(.*)/);
  if (!m) return \`<div class="event-line">\${line}</div>\`;
  const [, ts, type, rest] = m;
  const time = ts.split('T')[1]?.replace(/\\+.*/, '') ?? ts;
  const typeClass = type.toLowerCase().includes('pass') ? 'pass'
    : type.toLowerCase().includes('start') && type !== 'RUN' ? 'start'
    : type.toLowerCase().includes('skip') || type.toLowerCase().includes('blocked') ? (type.includes('BLOCKED') ? 'blocked' : 'skip')
    : type.toLowerCase().includes('run') ? 'run'
    : type.toLowerCase().includes('warn') ? 'warn'
    : '';
  return \`<div class="event-line"><span class="event-time">\${time}</span> <span class="event-type \${typeClass}">\${type}</span><span style="color:#888">\${rest}</span></div>\`;
}

function render(data) {
  // Status pill
  const pill = document.getElementById('status-pill');
  const pulse = document.getElementById('pulse-dot');
  const statusText = document.getElementById('status-text');
  pill.className = 'status-pill ' + (data.running ? 'running' : 'idle');
  pulse.style.display = data.running ? 'block' : 'none';
  statusText.textContent = data.running ? 'Running' : 'Idle';

  // Progress
  document.getElementById('done-count').textContent = data.done;
  document.getElementById('total-count').textContent = data.total;
  document.getElementById('bar-fill').style.width = (data.percent ?? 0) + '%';

  // Stories
  const list = document.getElementById('story-list');
  list.innerHTML = (data.stories ?? []).map(s => {
    const iconClass = s.passes ? 'done' : s.active ? 'active' : 'pending';
    const rowClass = s.passes ? 'done' : s.active ? 'active' : '';
    const icon = s.passes ? '✓' : s.active ? '▶' : s.id.replace('STORY-', '');
    return \`<div class="story-row \${rowClass}">
      <div class="story-icon \${iconClass}">\${icon}</div>
      <div class="story-info">
        <div class="story-id">\${s.id}</div>
        <div class="story-title">\${s.title}</div>
      </div>
    </div>\`;
  }).join('');

  // Events
  const eventsEl = document.getElementById('events-log');
  if (data.events?.length) {
    eventsEl.innerHTML = data.events.map(formatEvent).join('');
    eventsEl.scrollTop = eventsEl.scrollHeight;
  }

  // Run log
  const logEl = document.getElementById('run-log');
  if (data.logTail) {
    logEl.textContent = data.logTail;
    logEl.scrollTop = logEl.scrollHeight;
  }

  // Footer
  document.getElementById('footer-project').textContent = data.project ?? 'Timed';
  document.getElementById('footer-time').textContent = 'Last update: ' + new Date().toLocaleTimeString();
}

// SSE
const es = new EventSource('/events');
es.onmessage = e => render(JSON.parse(e.data));
es.onerror = () => {
  document.getElementById('status-text').textContent = 'Reconnecting…';
};

// Initial load
fetch('/api/status').then(r => r.json()).then(render).catch(() => {});
</script>
</body>
</html>`;

// ── Server ────────────────────────────────────────────────────────────────────

const server = Bun.serve({
  port: PORT,
  fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/") {
      return new Response(HTML, { headers: { "Content-Type": "text/html; charset=utf-8" } });
    }

    if (url.pathname === "/api/status") {
      return Response.json(getStatus());
    }

    if (url.pathname === "/events") {
      let ctrl: ReadableStreamDefaultController;
      const stream = new ReadableStream({
        start(controller) {
          ctrl = controller;
          clients.add(ctrl);
          // Send initial data immediately
          const data = `data: ${JSON.stringify(getStatus())}\n\n`;
          ctrl.enqueue(new TextEncoder().encode(data));
        },
        cancel() {
          clients.delete(ctrl);
        },
      });
      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    return new Response("Not found", { status: 404 });
  },
});

console.log(`\n  Ralph Dashboard running at http://localhost:${PORT}\n`);
