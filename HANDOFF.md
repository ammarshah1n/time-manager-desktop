# HANDOFF.md — Timed

Last updated: 2026-04-27 16:00 (post-unification — `unified` branch is now the trunk)

> **READ FIRST:** `docs/UNIFIED-BRANCH.md` — permanent reference for the consolidated architecture.
> **Narrative:** `docs/SINCE-2026-04-24.md` — full story of the weekend work.

## ★ NEW STATE ★ — `unified` is the source of truth

As of 2026-04-27, the four divergent branches have been merged into one trunk (`unified`). This branch:

- ✅ Carries TimedKit (123 shared Swift files) + TimedMacApp + TimediOS + Wave 1+2 backend + voice path + consolidated docs.
- ✅ Builds green for **swift build**, **xcodebuild TimedMac (arm64 Release)**, AND **xcodebuild TimediOS (Simulator)** — all from one branch.
- ✅ Produces `dist.noindex/Timed.dmg` (31 MB, ad-hoc signed) via `bash scripts/package_app.sh && bash scripts/create_dmg.sh`.
- ⚠️ Apple Developer Program enrollment NOT started — DMG is ad-hoc signed only; Yasser must `xattr -cr /Applications/Timed.app` after install.

## Operational reality

| Stack | Built | Merged onto `unified` | Deployed | Live |
|---|---|---|---|---|
| Wave 1+2 backend (Trigger.dev v4 + Graphiti/Neo4j + 3 services + NREM/REM engine + outcome harvester) | ✅ | ✅ via `54fe80e` | ❌ Trigger.dev cloud secrets not set; Neo4j not on Fly.io / AuraDB; Entra server-app not created | ❌ |
| 15 Wave 1+2 schema changes | ✅ | ✅ | ✅ pushed to Supabase `fpmjuufefhtlwbfinxlx` | ⚠️ tables exist; nothing writes to them yet |
| 3 new Edge Function proxies (`anthropic-proxy`, `elevenlabs-tts-proxy`, `deepgram-transcribe`) | ✅ | ✅ via `5acd23f` | ❌ not deployed; `ELEVENLABS_API_KEY` secret not set | ❌ |
| Voice path lock (ElevenLabs Agent + Opus 4.7, baked-in agent ID, Apple TTS removed) | ✅ | ✅ | n/a (client) | ✅ DMG built |
| UI overhaul (monochrome, BucketDot, Today orb, Dish Me Up rebuild, multi-user) | ✅ | ✅ | n/a | ✅ DMG built |
| TimedKit shared library + iOS scaffold (TimedMac + TimediOS + Widgets + Share extensions) | ✅ | ✅ via `54fe80e` (was already on base from `ios/port-bootstrap`) | ❌ no Apple cert | ⚠️ sim build green; not on physical iPhone |
| Mac DMG (ad-hoc signed) | ✅ | ✅ | ✅ `dist.noindex/Timed.dmg` 31 MB | ⚠️ needs `xattr -cr` to bypass Gatekeeper |
| Mac DMG (Developer ID + notarised) | ❌ | n/a | ❌ blocked on Apple enrollment | ❌ |
| iOS TestFlight | ❌ | n/a | ❌ blocked on Apple enrollment | ❌ |

## Three unblock chains

**Chain A — orb on Yasser's Mac (interim, no Apple cert needed):**

```bash
git checkout unified                                       # the trunk
bash scripts/package_app.sh                                # → dist.noindex/Timed.app
bash scripts/create_dmg.sh                                 # → dist.noindex/Timed.dmg
# Send Yasser the DMG. He drags Timed to /Applications, then:
#   xattr -cr /Applications/Timed.app
# (one-time; ad-hoc-signed apps are quarantined by Gatekeeper)

# Then deploy the voice-proxy Edge Functions:
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

**Chain C — Apple Developer enrollment (unblocks proper signing + iOS TestFlight):**

1. Visit developer.apple.com/programs/enroll → individual enrollment, $99/yr.
2. Apple identity verification (24-48h).
3. Provision Developer ID Application cert (Mac) + Apple Distribution cert (iOS).
4. `xcrun notarytool store-credentials timed-notary --apple-id ammar@facilitated.com.au --team-id <TEAM> --password <APP_PASS>`.
5. Switch `scripts/package_app.sh` `--sign -` → `--sign "Developer ID Application: …"` + `--options runtime`.
6. `bash scripts/notarize_app.sh && bash scripts/create_dmg.sh` → properly distributable DMG (no `xattr` ritual needed).
7. App Store Connect → register `com.ammarshahin.timed.ios` → provisioning profile → archive → upload to TestFlight → invite Yasser.

Full plan in `/Users/integrale/.claude/plans/ultrathink-i-need-you-cached-glade.md`.

## Current branch

`ui/apple-v1-local-monochrome` — UI / voice work + all consolidated docs. **Backend code (`trigger/`, `services/`) is on `ui/apple-v1-restore` and `ui/apple-v1-wired`, not here.** The merge to co-locate code with docs is itself a pending decision.

See `docs/SINCE-2026-04-24.md` for full track-by-track detail, /collab outcomes, branch topology, and lessons.

See `BUILD_STATE.md` for current-branch UI / voice surface inventory.

See `HANDOFF-wave2.md` for the Wave 2 deployment runbook (PRs, schemas, manual steps).

See `docs/sessions/2026-04-25-wave-1-2-shipped.md` for the full Wave 1+2 session writeup (architecture, bugs, lessons, infra stack).
