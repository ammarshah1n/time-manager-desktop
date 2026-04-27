# HANDOFF.md — Timed

Last updated: 2026-04-27 (consolidated since-Friday state)

> **Single source of truth for the 2026-04-24 → 04-27 work**: `docs/SINCE-2026-04-24.md`. Everything in this file is a one-page summary of that doc's operational reality.

## Operational reality — nothing is in production yet

| Stack | Built | Merged | Deployed | Live |
|---|---|---|---|---|
| Wave 1+2 backend (Trigger.dev v4 + Graphiti/Neo4j + 3 services + NREM/REM engine + outcome harvester) | ✅ | ✅ to `ui/apple-v1-restore` | ❌ Trigger.dev cloud secrets not set; Neo4j not on Fly.io / AuraDB; Entra server-app not created | ❌ |
| 15 Wave 1+2 schema changes | ✅ | ✅ | ✅ pushed to Supabase `fpmjuufefhtlwbfinxlx` | ⚠️ tables exist; nothing writes to them yet |
| 3 new Edge Function proxies (`anthropic-proxy`, `elevenlabs-tts-proxy`, `deepgram-transcribe`) | ✅ | ✅ to current branch | ❌ not deployed; `ELEVENLABS_API_KEY` secret not set | ❌ |
| Voice path lock (ElevenLabs Agent + Opus 4.7, baked-in agent ID, Apple TTS removed) | ✅ | ✅ | n/a (client) | ⚠️ needs `dist/Timed.app` rebuild — Xcode license blocked it |
| UI overhaul (monochrome, BucketDot, Today orb, Dish Me Up rebuild, multi-user) | ✅ | ✅ | n/a | ⚠️ same `dist/Timed.app` rebuild blocker |
| iOS port-bootstrap | ✅ | ✅ to `ios/port-bootstrap` | n/a | ❌ scaffold only, sim build green |

## Two unblock chains

**Chain A — get the orb working on Yasser's Mac with the new voice path:**

```bash
sudo xcodebuild -license accept
cd ~/time-manager-desktop && bash scripts/package_app.sh && bash scripts/install_app.sh
supabase secrets set ELEVENLABS_API_KEY=<key> --project-ref fpmjuufefhtlwbfinxlx
supabase functions deploy anthropic-proxy        --project-ref fpmjuufefhtlwbfinxlx
supabase functions deploy elevenlabs-tts-proxy   --project-ref fpmjuufefhtlwbfinxlx
supabase functions deploy deepgram-transcribe    --project-ref fpmjuufefhtlwbfinxlx   # optional, parked path
```

Plus one Comet/browser task: ElevenLabs portal → Morning Agent → Advanced → ASR provider → switch from "Original ASR" to **"Scribe v2 Turbo"**.

**Chain B — get the Wave 2 nightly engine actually running:**

1. Microsoft Entra ID app `Timed-Server-Graph` with app-level `Mail.Read` + `Calendars.Read`, admin consent, 24-month secret
2. Neo4j AuraDB Pro or Fly.io Neo4j (4 GB / 50 GB) with snapshots — or migrate the local Docker Neo4j to the Fedora MBP via Cloudflare Tunnel
3. Trigger.dev cloud secrets + `pnpm -F @timed/trigger deploy`
4. `UPDATE executives SET email_sync_driver='server' WHERE email='<yasser>'`
5. One-off `graphiti-backfill` task
6. Watch 3 consecutive nights of `agent_sessions` with `task_name IN ('nrem-amem-evolution','rem-synthesis')` AND `status='completed'` AND `cache_read_tokens > 0`

Until step 6 is green, **Wave 3 must not start.**

## Current branch

`ui/apple-v1-local-monochrome` — UI / voice work + all consolidated docs. **Backend code (`trigger/`, `services/`) is on `ui/apple-v1-restore` and `ui/apple-v1-wired`, not here.** The merge to co-locate code with docs is itself a pending decision.

See `docs/SINCE-2026-04-24.md` for full track-by-track detail, /collab outcomes, branch topology, and lessons.

See `BUILD_STATE.md` for current-branch UI / voice surface inventory.

See `HANDOFF-wave2.md` for the Wave 2 deployment runbook (PRs, schemas, manual steps).

See `docs/sessions/2026-04-25-wave-1-2-shipped.md` for the full Wave 1+2 session writeup (architecture, bugs, lessons, infra stack).
