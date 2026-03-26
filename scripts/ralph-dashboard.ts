#!/usr/bin/env bun
/**
 * Ralph Loop Live Dashboard + API
 * Mobile-friendly. Serves real-time status + action endpoints.
 * Usage: bun scripts/ralph-dashboard.ts
 */

import { readFileSync, writeFileSync, existsSync, watchFile } from "fs";
import { join } from "path";

const PORT = 4242;
const REPO_ROOT = join(import.meta.dir, "..");
const STATE_DIR = join(REPO_ROOT, ".codex/ralph");
const PRD_JSON = join(STATE_DIR, "prd.json");
const EVENTS_LOG = join(STATE_DIR, "events.log");
const RUN_LOG = join(STATE_DIR, "run.log");
const STOP_FLAG = join(STATE_DIR, ".ralph-stop");

// ── Data helpers ──────────────────────────────────────────────────────────────

function readPrd() {
  if (!existsSync(PRD_JSON)) return null;
  try { return JSON.parse(readFileSync(PRD_JSON, "utf8")); } catch { return null; }
}

function writePrd(data: any) {
  writeFileSync(PRD_JSON, JSON.stringify(data, null, 2));
}

function readEvents(last = 50): string[] {
  if (!existsSync(EVENTS_LOG)) return [];
  return readFileSync(EVENTS_LOG, "utf8").trim().split("\n").filter(Boolean).slice(-last);
}

function readRunLogTail(lines = 60): string {
  if (!existsSync(RUN_LOG)) return "";
  return readFileSync(RUN_LOG, "utf8").split("\n").slice(-lines).join("\n");
}

function getStatus() {
  const prd = readPrd();
  const events = readEvents(100);
  const lastEvent = events[events.length - 1] ?? "";

  const isRunning = existsSync(EVENTS_LOG) && (() => {
    try { return (Date.now() - require("fs").statSync(EVENTS_LOG).mtimeMs) < 180_000; }
    catch { return false; }
  })();

  const isStopped = existsSync(STOP_FLAG);
  const currentStoryMatch = events.slice().reverse().find(e => e.includes("STORY START"))?.match(/id=(\S+)/);
  const currentStory = currentStoryMatch?.[1] ?? null;

  if (!prd) return { running: false, stopped: isStopped, project: "Timed", done: 0, total: 0, stories: [], currentStory: null, events: [], logTail: "" };

  const stories = prd.userStories.map((s: any) => ({
    id: s.id,
    title: s.title,
    passes: s.passes,
    active: s.id === currentStory && !s.passes,
  }));

  const done = stories.filter((s: any) => s.passes).length;

  return {
    running: isRunning,
    stopped: isStopped,
    project: prd.project,
    done,
    total: stories.length,
    percent: Math.round((done / Math.max(stories.length, 1)) * 100),
    stories,
    currentStory,
    events: readEvents(30),
    logTail: readRunLogTail(60),
  };
}

// ── SSE ───────────────────────────────────────────────────────────────────────

const clients = new Set<ReadableStreamDefaultController>();

function broadcast() {
  const data = `data: ${JSON.stringify(getStatus())}\n\n`;
  for (const ctrl of clients) {
    try { ctrl.enqueue(new TextEncoder().encode(data)); }
    catch { clients.delete(ctrl); }
  }
}

if (existsSync(STATE_DIR)) {
  watchFile(PRD_JSON, { interval: 3000 }, broadcast);
  watchFile(EVENTS_LOG, { interval: 2000 }, broadcast);
}
setInterval(broadcast, 5000);

// ── HTML ──────────────────────────────────────────────────────────────────────

const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>Ralph — Timed</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  :root {
    --bg: #0d0d0f;
    --surface: #16161a;
    --surface2: #1e1e24;
    --border: #2a2a35;
    --red: #D32F2F;
    --red-soft: rgba(211,47,47,0.12);
    --green: #2e7d32;
    --green-bright: #4caf50;
    --amber: #f59e0b;
    --blue: #3b82f6;
    --muted: #6b7280;
    --text: #e8e8f0;
    --text-dim: #9999aa;
    --mono: 'JetBrains Mono','SF Mono',monospace;
    --radius: 10px;
  }
  html, body { height: 100%; }
  body { background: var(--bg); color: var(--text); font-family: -apple-system,BlinkMacSystemFont,'Inter',sans-serif; font-size: 14px; }

  /* ── Header ── */
  header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 14px 16px;
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    position: sticky; top: 0; z-index: 20;
  }
  .logo { display: flex; align-items: center; gap: 8px; font-size: 15px; font-weight: 600; }
  .logo svg { flex-shrink: 0; }
  .logo-dot { color: var(--red); }
  .status-pill {
    display: flex; align-items: center; gap: 5px;
    padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 500;
    border: 1px solid var(--border);
  }
  .status-pill.running { border-color: var(--green); color: var(--green-bright); }
  .status-pill.stopped { border-color: var(--amber); color: var(--amber); }
  .status-pill.idle { color: var(--muted); }
  .pulse { width: 7px; height: 7px; border-radius: 50%; background: currentColor; animation: pulse 1.4s ease-in-out infinite; }
  @keyframes pulse { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:.4;transform:scale(.7)} }

  /* ── Progress ── */
  .progress-section { padding: 16px 16px 0; }
  .progress-meta { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 8px; }
  .progress-label { font-size: 11px; color: var(--text-dim); text-transform: uppercase; letter-spacing: .08em; }
  .progress-count { font-size: 26px; font-weight: 700; }
  .progress-count span { font-size: 15px; font-weight: 400; color: var(--text-dim); }
  .bar-track { height: 4px; background: var(--surface2); border-radius: 2px; overflow: hidden; }
  .bar-fill { height: 100%; background: linear-gradient(90deg, var(--red), #ef5350); border-radius: 2px; transition: width .6s cubic-bezier(.4,0,.2,1); }

  /* ── Actions ── */
  .actions { display: flex; gap: 8px; padding: 14px 16px; overflow-x: auto; }
  .actions::-webkit-scrollbar { display: none; }
  .btn {
    flex-shrink: 0;
    display: flex; align-items: center; gap: 6px;
    padding: 8px 14px; border-radius: 8px; font-size: 13px; font-weight: 500;
    border: 1px solid var(--border); background: var(--surface2);
    color: var(--text); cursor: pointer; transition: all .15s; white-space: nowrap;
  }
  .btn:hover, .btn:active { background: var(--surface); border-color: #444; }
  .btn.danger { border-color: var(--red); color: #ef5350; }
  .btn.danger:hover { background: var(--red-soft); }
  .btn.primary { background: var(--red); border-color: var(--red); color: #fff; }
  .btn.primary:hover { background: #b71c1c; }

  /* ── Tabs ── */
  .tabs { display: flex; border-bottom: 1px solid var(--border); padding: 0 16px; background: var(--surface); }
  .tab { padding: 10px 14px; font-size: 13px; color: var(--text-dim); cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; transition: color .15s; }
  .tab.active { color: var(--text); border-bottom-color: var(--red); }

  /* ── Story list ── */
  .story-list { padding: 10px 16px; }
  .story-row {
    display: flex; align-items: flex-start; gap: 10px;
    padding: 10px; border-radius: 10px; margin-bottom: 4px; transition: background .15s;
  }
  .story-row:active { background: var(--surface2); }
  .story-row.active { background: var(--red-soft); border: 1px solid rgba(211,47,47,.25); }
  .story-row.done { opacity: .45; }
  .story-icon {
    width: 22px; height: 22px; border-radius: 50%; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center; font-size: 11px; margin-top: 1px;
  }
  .story-icon.done { background: var(--green); color: #fff; }
  .story-icon.active { background: var(--red); color: #fff; animation: pulse 1.4s ease-in-out infinite; }
  .story-icon.pending { background: var(--surface2); color: var(--muted); border: 1px solid var(--border); font-size: 10px; }
  .story-info { flex: 1; min-width: 0; }
  .story-id { font-size: 10px; color: var(--muted); font-family: var(--mono); margin-bottom: 2px; }
  .story-title { font-size: 13px; line-height: 1.35; }
  .story-row.active .story-title { color: #fff; font-weight: 500; }

  /* ── Log ── */
  .log-section { padding: 10px 16px; }
  .log-header { font-size: 11px; text-transform: uppercase; letter-spacing: .1em; color: var(--text-dim); margin-bottom: 8px; display: flex; align-items: center; gap: 6px; }
  .live-badge { background: var(--red); color: #fff; font-size: 9px; padding: 1px 5px; border-radius: 3px; font-weight: 600; }
  .log-box { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 12px; font-family: var(--mono); font-size: 11px; line-height: 1.6; color: var(--text-dim); max-height: 240px; overflow-y: auto; }
  .log-box::-webkit-scrollbar { width: 3px; }
  .log-box::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }
  .event-time { color: #444; }

  /* ── Output ── */
  .output-box { background: #0a0a0c; border: 1px solid var(--border); border-radius: var(--radius); padding: 12px; font-family: var(--mono); font-size: 11px; line-height: 1.6; color: #7a7a8a; max-height: 300px; overflow-y: auto; white-space: pre-wrap; word-break: break-all; }

  /* ── Modal ── */
  .modal-bg { display: none; position: fixed; inset: 0; background: rgba(0,0,0,.7); z-index: 100; align-items: flex-end; }
  .modal-bg.open { display: flex; }
  .modal { background: var(--surface); border-radius: 16px 16px 0 0; padding: 20px 16px 32px; width: 100%; border-top: 1px solid var(--border); }
  .modal h3 { font-size: 16px; font-weight: 600; margin-bottom: 4px; }
  .modal p { font-size: 13px; color: var(--text-dim); margin-bottom: 14px; }
  .modal textarea {
    width: 100%; padding: 10px 12px; border-radius: 8px; font-size: 14px; font-family: inherit;
    background: var(--surface2); border: 1px solid var(--border); color: var(--text); resize: none;
    outline: none; min-height: 80px;
  }
  .modal textarea:focus { border-color: var(--red); }
  .modal-actions { display: flex; gap: 8px; margin-top: 10px; }
  .modal-actions .btn { flex: 1; justify-content: center; }

  /* ── Toast ── */
  #toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%) translateY(20px); opacity: 0; background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 10px 16px; font-size: 13px; transition: all .25s; z-index: 200; white-space: nowrap; pointer-events: none; }
  #toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

  /* ── Tab panels ── */
  .tab-panel { display: none; }
  .tab-panel.active { display: block; }
</style>
</head>
<body>

<header>
  <div class="logo">
    <svg width="20" height="20" viewBox="0 0 22 22" fill="none">
      <circle cx="11" cy="11" r="10" stroke="#D32F2F" stroke-width="1.5"/>
      <path d="M11 6v5l3 3" stroke="#D32F2F" stroke-width="1.5" stroke-linecap="round"/>
    </svg>
    Timed<span class="logo-dot">.</span> Ralph
  </div>
  <div id="status-pill" class="status-pill idle">
    <span id="pulse-dot" class="pulse" style="display:none"></span>
    <span id="status-text">Connecting…</span>
  </div>
</header>

<div class="progress-section">
  <div class="progress-meta">
    <span class="progress-label">Stories complete</span>
    <div class="progress-count" id="done-count">0<span> / <span id="total-count">15</span></span></div>
  </div>
  <div class="bar-track"><div id="bar-fill" class="bar-fill" style="width:0%"></div></div>
</div>

<div class="actions">
  <button class="btn primary" onclick="openAddModal()">＋ Add Story</button>
  <button class="btn danger" onclick="skipStory()">⏭ Skip Current</button>
  <button class="btn" onclick="toggleStop()" id="stop-btn">🛑 Stop</button>
  <button class="btn" onclick="refreshNow()">↻ Refresh</button>
</div>

<div class="tabs">
  <div class="tab active" onclick="switchTab('queue', this)">Queue</div>
  <div class="tab" onclick="switchTab('events', this)">Events</div>
  <div class="tab" onclick="switchTab('output', this)">Output</div>
</div>

<div id="tab-queue" class="tab-panel active">
  <div class="story-list" id="story-list"></div>
</div>

<div id="tab-events" class="tab-panel">
  <div class="log-section">
    <div class="log-header">Events <span class="live-badge">LIVE</span></div>
    <div class="log-box" id="events-log">Waiting…</div>
  </div>
</div>

<div id="tab-output" class="tab-panel">
  <div class="log-section">
    <div class="log-header">Codex Raw Output</div>
    <div class="output-box" id="run-log">No output yet…</div>
  </div>
</div>

<!-- Add Story Modal -->
<div class="modal-bg" id="add-modal">
  <div class="modal">
    <h3>Add Story to Queue</h3>
    <p>Describe the feature. Codex will pick it up after the current story.</p>
    <textarea id="add-text" placeholder="e.g. Add spaced repetition to quiz mode so questions repeat at increasing intervals"></textarea>
    <div class="modal-actions">
      <button class="btn" onclick="closeAddModal()">Cancel</button>
      <button class="btn primary" onclick="submitAdd()">Add to Queue</button>
    </div>
  </div>
</div>

<div id="toast"></div>

<script>
let isStopped = false;

function toast(msg) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 2800);
}

function switchTab(name, el) {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
  el.classList.add('active');
  document.getElementById('tab-' + name).classList.add('active');
}

function openAddModal() {
  document.getElementById('add-modal').classList.add('open');
  setTimeout(() => document.getElementById('add-text').focus(), 100);
}
function closeAddModal() {
  document.getElementById('add-modal').classList.remove('open');
  document.getElementById('add-text').value = '';
}

async function submitAdd() {
  const text = document.getElementById('add-text').value.trim();
  if (!text) return;
  closeAddModal();
  const res = await fetch('/api/add', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({text}) });
  const data = await res.json();
  toast(data.ok ? '✅ Story added to queue' : '❌ ' + (data.error ?? 'Failed'));
}

async function skipStory() {
  if (!confirm('Skip the current story?')) return;
  const res = await fetch('/api/skip', { method: 'POST' });
  const data = await res.json();
  toast(data.ok ? '⏭ Story skipped' : '❌ ' + (data.error ?? 'Failed'));
}

async function toggleStop() {
  const endpoint = isStopped ? '/api/resume' : '/api/stop';
  const res = await fetch(endpoint, { method: 'POST' });
  const data = await res.json();
  toast(data.ok ? (isStopped ? '▶️ Resumed' : '🛑 Stop flag set') : '❌ Failed');
}

function refreshNow() { fetch('/api/status').then(r => r.json()).then(render); }

function render(data) {
  isStopped = data.stopped;

  // Status pill
  const pill = document.getElementById('status-pill');
  const pulse = document.getElementById('pulse-dot');
  const statusText = document.getElementById('status-text');
  if (data.stopped) {
    pill.className = 'status-pill stopped';
    pulse.style.display = 'none';
    statusText.textContent = 'Stopped';
  } else if (data.running) {
    pill.className = 'status-pill running';
    pulse.style.display = 'block';
    statusText.textContent = 'Running';
  } else {
    pill.className = 'status-pill idle';
    pulse.style.display = 'none';
    statusText.textContent = 'Idle';
  }

  // Stop button label
  document.getElementById('stop-btn').textContent = data.stopped ? '▶ Resume' : '🛑 Stop';

  // Progress
  const doneEl = document.getElementById('done-count');
  doneEl.innerHTML = data.done + '<span> / <span id="total-count">' + data.total + '</span></span>';
  document.getElementById('bar-fill').style.width = (data.percent ?? 0) + '%';

  // Stories
  const list = document.getElementById('story-list');
  list.innerHTML = (data.stories ?? []).map(s => {
    const iconClass = s.passes ? 'done' : s.active ? 'active' : 'pending';
    const rowClass = s.passes ? 'done' : s.active ? 'active' : '';
    const icon = s.passes ? '✓' : s.active ? '▶' : s.id.replace('STORY-','');
    return \`<div class="story-row \${rowClass}">
      <div class="story-icon \${iconClass}">\${icon}</div>
      <div class="story-info">
        <div class="story-id">\${s.id}</div>
        <div class="story-title">\${s.title}</div>
      </div>
    </div>\`;
  }).join('');

  // Events
  const evEl = document.getElementById('events-log');
  if (data.events?.length) {
    evEl.innerHTML = data.events.map(e => {
      const ts = e.match(/\\[([^\\]]+)\\]/)?.[1]?.split('T')[1]?.replace(/\\+.*/,'') ?? '';
      const rest = e.replace(/^\\[[^\\]]+\\] /,'');
      return \`<div><span class="event-time">\${ts}</span> \${rest}</div>\`;
    }).join('');
    evEl.scrollTop = evEl.scrollHeight;
  }

  // Run log
  const logEl = document.getElementById('run-log');
  if (data.logTail) {
    logEl.textContent = data.logTail;
    logEl.scrollTop = logEl.scrollHeight;
  }
}

// SSE
const es = new EventSource('/events');
es.onmessage = e => render(JSON.parse(e.data));

// Initial
fetch('/api/status').then(r => r.json()).then(render).catch(() => {});

// Close modal on bg tap
document.getElementById('add-modal').addEventListener('click', function(e) {
  if (e.target === this) closeAddModal();
});
</script>
</body>
</html>`;

// ── Server ────────────────────────────────────────────────────────────────────

const server = Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/") return new Response(HTML, { headers: { "Content-Type": "text/html; charset=utf-8" } });

    if (url.pathname === "/api/status") return Response.json(getStatus());

    if (url.pathname === "/api/skip" && req.method === "POST") {
      const prd = readPrd();
      if (!prd) return Response.json({ ok: false, error: "No prd.json" });
      const current = prd.userStories.find((s: any) => !s.passes);
      if (!current) return Response.json({ ok: false, error: "No active story" });
      current.passes = true;
      writePrd(prd);
      broadcast();
      return Response.json({ ok: true, skipped: current.id });
    }

    if (url.pathname === "/api/add" && req.method === "POST") {
      const body = await req.json() as any;
      const text: string = body?.text?.trim() ?? "";
      if (!text) return Response.json({ ok: false, error: "No text" });
      const prd = readPrd();
      if (!prd) return Response.json({ ok: false, error: "No prd.json" });
      const newId = `STORY-${String(prd.userStories.length + 1).padStart(3, "0")}`;
      prd.userStories.push({
        id: newId,
        title: text.slice(0, 80),
        description: text,
        acceptanceCriteria: ["Feature implemented, swift build passes with zero errors"],
        priority: prd.userStories.length + 1,
        passes: false,
        notes: `Added via dashboard. Implement in the Timed macOS SwiftUI app. Follow existing code patterns. Run swift build to verify.`,
      });
      writePrd(prd);
      broadcast();
      return Response.json({ ok: true, id: newId });
    }

    if (url.pathname === "/api/stop" && req.method === "POST") {
      writeFileSync(STOP_FLAG, new Date().toISOString());
      broadcast();
      return Response.json({ ok: true });
    }

    if (url.pathname === "/api/resume" && req.method === "POST") {
      if (existsSync(STOP_FLAG)) { const { unlinkSync } = await import("fs"); unlinkSync(STOP_FLAG); }
      broadcast();
      return Response.json({ ok: true });
    }

    if (url.pathname === "/events") {
      let ctrl: ReadableStreamDefaultController;
      const stream = new ReadableStream({
        start(controller) {
          ctrl = controller;
          clients.add(ctrl);
          ctrl.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(getStatus())}\n\n`));
        },
        cancel() { clients.delete(ctrl); },
      });
      return new Response(stream, {
        headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "Connection": "keep-alive", "Access-Control-Allow-Origin": "*" },
      });
    }

    return new Response("Not found", { status: 404 });
  },
});

console.log(`\n  Ralph Dashboard → http://localhost:${PORT}\n`);
