#!/usr/bin/env bun
/**
 * Ralph Loop — Telegram Bot
 * Controls the Timed Ralph loop from your phone.
 *
 * Commands:
 *   /start    — register & get welcome
 *   /status   — progress summary
 *   /stories  — full story list with status icons
 *   /log      — last 15 events
 *   /skip     — force-skip current story
 *   /add <text> — add a new story to the queue
 *   /stop     — emergency stop (writes .ralph-stop flag)
 *   /resume   — remove stop flag
 *
 * On every story complete/fail: automatically sends you a notification.
 */

import { readFileSync, writeFileSync, existsSync, watchFile } from "fs";
import { join } from "path";
import { execSync } from "child_process";

const TOKEN = process.env.RALPH_TELEGRAM_BOT_TOKEN ?? "";
if (!TOKEN) {
  console.error("RALPH_TELEGRAM_BOT_TOKEN is required");
  process.exit(1);
}
const API = `https://api.telegram.org/bot${TOKEN}`;

const REPO_ROOT = join(import.meta.dir, "..");
const STATE_DIR = join(REPO_ROOT, ".codex/ralph");
const PRD_JSON = join(STATE_DIR, "prd.json");
const EVENTS_LOG = join(STATE_DIR, "events.log");
const CHAT_ID_FILE = process.env.RALPH_TELEGRAM_CHAT_ID_FILE
  ?? join(STATE_DIR, ".telegram-chat-id.local");
const STOP_FLAG = join(STATE_DIR, ".ralph-stop");

// ── Telegram API helpers ──────────────────────────────────────────────────────

async function tg(method: string, body: object): Promise<any> {
  const res = await fetch(`${API}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return res.json();
}

async function send(chatId: number, text: string, extra: object = {}): Promise<void> {
  await tg("sendMessage", { chat_id: chatId, text, parse_mode: "HTML", ...extra });
}

// ── State helpers ─────────────────────────────────────────────────────────────

function getAdminChatId(): number | null {
  if (!existsSync(CHAT_ID_FILE)) return null;
  return parseInt(readFileSync(CHAT_ID_FILE, "utf8").trim(), 10) || null;
}

function saveAdminChatId(id: number) {
  writeFileSync(CHAT_ID_FILE, String(id));
}

function readPrd(): any | null {
  if (!existsSync(PRD_JSON)) return null;
  try { return JSON.parse(readFileSync(PRD_JSON, "utf8")); } catch { return null; }
}

function writePrd(data: any) {
  writeFileSync(PRD_JSON, JSON.stringify(data, null, 2));
}

function readEvents(n = 15): string[] {
  if (!existsSync(EVENTS_LOG)) return [];
  return readFileSync(EVENTS_LOG, "utf8").trim().split("\n").filter(Boolean).slice(-n);
}

function getCurrentStory(prd: any): any | null {
  return prd?.userStories?.find((s: any) => !s.passes) ?? null;
}

function nextStoryId(prd: any): string {
  const done = prd.userStories.filter((s: any) => s.passes).length;
  return `STORY-${String(done + 1).padStart(3, "0")}`;
}

// ── Notification watcher ──────────────────────────────────────────────────────

let lastEventCount = readEvents(1000).length;
let lastDoneCount = readPrd()?.userStories?.filter((s: any) => s.passes).length ?? 0;

function checkForNewEvents() {
  const adminId = getAdminChatId();
  if (!adminId) return;

  const events = readEvents(1000);
  if (events.length <= lastEventCount) return;

  const newEvents = events.slice(lastEventCount);
  lastEventCount = events.length;

  for (const line of newEvents) {
    if (line.includes("STORY COMPLETE")) {
      const m = line.match(/id=(\S+).*title=(.+)/);
      const id = m?.[1] ?? "?";
      const title = m?.[2] ?? "";
      const prd = readPrd();
      const done = prd?.userStories?.filter((s: any) => s.passes).length ?? 0;
      const total = prd?.userStories?.length ?? 0;
      send(adminId, `✅ <b>${id} DONE</b>\n${title}\n\n<i>${done}/${total} complete</i>`);
    } else if (line.includes("STORY BLOCKED") || line.includes("STORY SKIP")) {
      const m = line.match(/id=(\S+)/);
      const id = m?.[1] ?? "?";
      send(adminId, `⚠️ <b>${id} SKIPPED</b>\nCheck log for reason.`);
    } else if (line.includes("RUN COMPLETE") || line.includes("all stories")) {
      send(adminId, `🏁 <b>RALPH LOOP COMPLETE</b>\nAll stories done. Check the app.`);
    }
  }
}

if (existsSync(EVENTS_LOG)) {
  watchFile(EVENTS_LOG, { interval: 3000 }, checkForNewEvents);
}
if (existsSync(PRD_JSON)) {
  watchFile(PRD_JSON, { interval: 4000 }, checkForNewEvents);
}

// ── Command handlers ──────────────────────────────────────────────────────────

async function cmdStart(chatId: number, username: string) {
  saveAdminChatId(chatId);
  const prd = readPrd();
  const done = prd?.userStories?.filter((s: any) => s.passes).length ?? 0;
  const total = prd?.userStories?.length ?? 0;
  await send(chatId,
    `👋 <b>Ralph Loop — Timed</b>\n\n` +
    `Registered. You'll get notifications on every story.\n\n` +
    `<b>Progress:</b> ${done}/${total} stories done\n\n` +
    `<b>Commands:</b>\n` +
    `/status — progress\n` +
    `/stories — full queue\n` +
    `/log — recent events\n` +
    `/skip — skip stuck story\n` +
    `/add &lt;idea&gt; — add to queue\n` +
    `/stop — emergency stop\n` +
    `/resume — resume after stop`
  );
}

async function cmdStatus(chatId: number) {
  const prd = readPrd();
  if (!prd) { await send(chatId, "❌ No prd.json found. Is the loop started?"); return; }

  const stories = prd.userStories;
  const done = stories.filter((s: any) => s.passes).length;
  const total = stories.length;
  const current = getCurrentStory(prd);
  const pct = Math.round((done / total) * 100);
  const bar = "█".repeat(Math.round(pct / 10)) + "░".repeat(10 - Math.round(pct / 10));

  const events = readEvents(5);
  const lastEvent = events[events.length - 1] ?? "none";
  const ts = lastEvent.match(/\[([^\]]+)\]/)?.[1]?.split("T")[1]?.replace(/\+.*/, "") ?? "";

  await send(chatId,
    `<b>Timed — Ralph Loop</b>\n\n` +
    `${bar} ${pct}%\n` +
    `<b>${done}/${total}</b> stories complete\n\n` +
    (current ? `▶ <b>Now:</b> ${current.id} — ${current.title}\n` : "✅ All done!\n") +
    (ts ? `\n⏱ Last event: ${ts}` : "")
  );
}

async function cmdStories(chatId: number) {
  const prd = readPrd();
  if (!prd) { await send(chatId, "❌ No prd.json found."); return; }

  const lines = prd.userStories.map((s: any) => {
    const icon = s.passes ? "✅" : getCurrentStory(prd)?.id === s.id ? "▶️" : "⬜";
    return `${icon} <code>${s.id}</code> ${s.title}`;
  });

  await send(chatId, `<b>Story Queue</b>\n\n${lines.join("\n")}`);
}

async function cmdLog(chatId: number) {
  const events = readEvents(15);
  if (!events.length) { await send(chatId, "No events yet."); return; }

  const lines = events.map(e => {
    const ts = e.match(/\[([^\]]+)\]/)?.[1]?.split("T")[1]?.replace(/\+.*/, "") ?? "";
    const rest = e.replace(/^\[[^\]]+\] /, "");
    return `<code>${ts}</code> ${rest}`;
  });

  await send(chatId, `<b>Recent Events</b>\n\n${lines.join("\n")}`);
}

async function cmdSkip(chatId: number) {
  const prd = readPrd();
  if (!prd) { await send(chatId, "❌ No prd.json found."); return; }

  const current = getCurrentStory(prd);
  if (!current) { await send(chatId, "✅ No stories to skip — all done!"); return; }

  current.passes = true;
  writePrd(prd);
  await send(chatId, `⏭ Skipped <b>${current.id}</b>: ${current.title}\n\nLoop will pick up the next story.`);
}

async function cmdAdd(chatId: number, text: string) {
  if (!text.trim()) {
    await send(chatId, "Usage: /add <story idea>\nExample: /add Add dark mode toggle to settings");
    return;
  }

  const prd = readPrd();
  if (!prd) { await send(chatId, "❌ No prd.json found."); return; }

  const newId = `STORY-${String(prd.userStories.length + 1).padStart(3, "0")}`;
  const newStory = {
    id: newId,
    title: text.trim().slice(0, 80),
    description: text.trim(),
    acceptanceCriteria: ["Feature is implemented and the app builds without errors"],
    priority: prd.userStories.length + 1,
    passes: false,
    notes: `Added via Telegram by Ammar. Implement this feature in the Timed macOS app. Use existing patterns and code style. Run swift build to verify.`,
  };

  prd.userStories.push(newStory);
  writePrd(prd);

  await send(chatId,
    `➕ <b>Story added: ${newId}</b>\n${text.trim()}\n\n` +
    `Queue: ${prd.userStories.filter((s: any) => !s.passes).length} remaining`
  );
}

async function cmdStop(chatId: number) {
  writeFileSync(STOP_FLAG, new Date().toISOString());
  await send(chatId,
    `🛑 <b>Stop flag set.</b>\n\nThe loop will stop after the current story finishes.\n` +
    `Send /resume to clear the flag and keep going.`
  );
}

async function cmdResume(chatId: number) {
  if (existsSync(STOP_FLAG)) {
    const { unlinkSync } = await import("fs");
    unlinkSync(STOP_FLAG);
  }
  await send(chatId, `▶️ Stop flag cleared. Loop will continue on next iteration.`);
}

// ── Polling loop ──────────────────────────────────────────────────────────────

let offset = 0;

async function poll() {
  try {
    const res = await tg("getUpdates", { offset, timeout: 20, allowed_updates: ["message"] });
    if (!res.ok) return;

    for (const update of res.result ?? []) {
      offset = update.update_id + 1;
      const msg = update.message;
      if (!msg?.text) continue;

      const chatId: number = msg.chat.id;
      const username: string = msg.from?.username ?? "unknown";
      const text: string = msg.text.trim();

      // Only respond to registered admin (or /start from anyone)
      const adminId = getAdminChatId();
      if (adminId && chatId !== adminId && !text.startsWith("/start")) continue;

      if (text.startsWith("/start")) await cmdStart(chatId, username);
      else if (text === "/status") await cmdStatus(chatId);
      else if (text === "/stories") await cmdStories(chatId);
      else if (text === "/log") await cmdLog(chatId);
      else if (text === "/skip") await cmdSkip(chatId);
      else if (text.startsWith("/add ")) await cmdAdd(chatId, text.slice(5));
      else if (text === "/add") await cmdAdd(chatId, "");
      else if (text === "/stop") await cmdStop(chatId);
      else if (text === "/resume") await cmdResume(chatId);
      else await send(chatId, `Unknown command. Try /status or /stories.`);
    }
  } catch (e) {
    // Network error — just keep polling
  }
}

console.log("  Ralph Telegram Bot running. Send /start to your bot.");

// Initial notification to admin if already registered
const existingAdmin = getAdminChatId();
if (existingAdmin) {
  send(existingAdmin, "🤖 <b>Ralph bot restarted.</b> Loop is running.\n\nSend /status for progress.").catch(() => {});
}

// Poll loop
while (true) {
  await poll();
  await Bun.sleep(500);
}
