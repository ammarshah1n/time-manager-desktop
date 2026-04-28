# HANDOFF.md — Timed

Last updated: 2026-04-28 10:30 (Microsoft login PARKED — Supabase rejecting code exchange; Chain B/C still parked)

> **READ FIRST:** `docs/UNIFIED-BRANCH.md` — permanent reference for the consolidated architecture.
> **Narrative:** `docs/SINCE-2026-04-24.md` — full story of the weekend work.
> **Resume next session:** `~/.claude/projects/-Users-integrale-time-manager-desktop/NEXT.md`.

## ★ PARKED 2026-04-28 PM ★ — Microsoft login (~80% wired, fails at Supabase code exchange)

This session built the login surface end-to-end and got most of the OAuth round trip working. The last hop — Supabase swapping the Microsoft `code` for a session token — fails with `Unable to exchange external code: 1.AW…`. Same code value reproduces on every click, which suggests Comet (Perplexity browser) is caching the redirect URL rather than starting a fresh OAuth dance.

### What was shipped (committed `[wip]`)

- **`Sources/TimedKit/Features/Auth/LoginView.swift`** *(new)* — calm Apple-style gate screen. Single "Sign in with Microsoft" button, error display, OAuth-redirect-as-explicit-exception to the orb-led onboarding rule.
- **`Sources/TimedKit/AppEntry/TimedAppShell.swift`** — `rootContent` now branches: `LoginView` if `!auth.isSignedIn`, else the existing TimedRootView chain.
- **`Sources/TimedKit/Core/Clients/FileAuthLocalStorage.swift`** *(new)* — `AuthLocalStorage` implementation backed by JSON files in `~/Library/Application Support/Timed/_auth/`. Replaces Supabase SDK's default `KeychainLocalStorage` so ad-hoc-signed dev builds don't hit Keychain ACL prompts on every rebuild (different signature → "always allow" never sticks). Tradeoff: no encryption-at-rest. Acceptable for dev; swap back to Keychain once Developer ID signing lands.
- **`Sources/TimedKit/Core/Clients/SupabaseClient.swift`** — `live()` now passes `SupabaseClientOptions(auth: AuthOptions(storage: FileAuthLocalStorage()))`.
- **`Sources/TimedKit/Core/Platform/PlatformPaths.swift`** — `applicationSupport` is now user-scoped (`Timed/users/<uuid>/` when signed in, `Timed/_anonymous/` otherwise). Added `applicationSupportRoot` (unscoped) + `authStorage` (`Timed/_auth/`) helpers.
- **`Sources/TimedKit/Core/Services/DataStore.swift`** — `folder` is now computed every call (was cached at init). Sign-in/sign-out flips the on-disk path without restart.
- **`Sources/TimedKit/Core/Services/AuthService.swift`** — writes `executive.id` to UserDefaults `com.timed.auth.activeExecutiveID` after `bootstrapExecutive()` so PlatformPaths can scope. Clears it on `signOut()`.
- **`supabase/config.toml`** — `additional_redirect_urls = ["timed://auth/callback"]`. Pushed to remote project on 2026-04-28 via `supabase config push --project-ref fpmjuufefhtlwbfinxlx --yes`. Side effect: also pushed local defaults for `[auth.email]` (otp_length 6, max_frequency 1s, enable_confirmations false) — verify these on remote if email auth ever matters.
- **Azure secret rotation** — generated a new client secret on `Timed` Entra app (`az ad app credential reset --id 89e8f1c6-3cc4-47fb-83ae-f7e0528eb860 --append --years 2 --display-name "Supabase Auth 2026-04-28"`). Both old and new secrets are alive in Azure (`--append`). The new value was pasted into Supabase Dashboard → Auth → Providers → Microsoft → Client Secret. Confirmed via toast "Successfully updated settings".
- **LaunchServices cleanup** — `lsregister -u`'d 4 stale `Timed.app` paths (DerivedData / `dist/` / worktree) so only `/Applications/Timed.app` is now the registered handler for `timed://`. Stale copies are renamed to `*.stale-20260427-213832` on disk.
- **Yasser's seed data moved aside** — `~/Library/Application Support/Timed.backup-yasser-seed-20260427-210633/` (recoverable; nothing destroyed).

### What is broken (the resume target)

Click "Sign in with Microsoft" → browser opens → Microsoft auth completes → browser redirects to `timed://auth/callback?code=1.AW…` → app receives URL → `auth.handleAuthCallback` → `client.auth.session(from: url)` → Supabase rejects with `"Unable to exchange external code: 1.AW…"`. The same code value reproduces on every click.

The remaining diagnostic step is to read the actual Microsoft error from `auth.audit_log_entries` in the Supabase project — Supabase's wrapper error doesn't tell us why Microsoft is rejecting the token exchange. The query and full resume runbook are in TickTick (project: Timed, task: "Finish Microsoft login (start here next session)") and in `~/.claude/projects/-Users-integrale-time-manager-desktop/NEXT.md`.

### Plan for the resume

`/Users/integrale/.claude/plans/nothing-happens-how-tof-splendid-iverson.md` has the full diagnostic plan and hypothesis ranking. Most likely paths after seeing the audit log:

1. **Browser cache (most likely given identical code repeats)** — switch the Mac OAuth flow from "open in default browser" to `ASWebAuthenticationSession`, which handles custom-scheme redirects natively and doesn't share cookies with the user's browser. Cleaner long-term anyway.
2. **Scope mismatch** — narrow `signInWithMicrosoft` scopes from `email profile openid Mail.Read Calendars.Read offline_access` to just `openid email profile` and confirm.
3. **Secret still wrong** — regenerate Azure secret again, re-paste in Supabase. Both alive in Azure already (`--append`).



## ★ NEW 2026-04-28 ★ — Personal memory system + /wrap-up v2 shipped

A separate workstream from the Timed app itself. **Affects how Claude works on Timed**, not Timed's runtime:

- **basic-memory MCP** wired globally (`~/.claude/settings.json`). 8 projects registered: `timed-brain`, `aif-vault`, `brain-meta`, `comet-reports`, `pff-brain`, `pff-legal-brain`, `aif-decisions-vault`, `main`.
- **Memory Protocol** in `~/CLAUDE.md` forces read-back search before fresh research, enforces project-scoped writes, 90-day staleness gate, and **canonical-first ranking** (treats `06-context/`, `00-rules/`, `03-specs/`, `AIF/` paths as primary; `05-dev-log/sessions/` as supplementary only).
- **Per-project pin** at `~/time-manager-desktop/CLAUDE.md` → `## Memory Default`: this project searches `timed-brain` (vault) and `time-manager-desktop` (claude-mem) by default.
- **Canonical Timed-Brain docs rewritten** with cognitive-infra framing (kills the productivity-app framing): `MISSION.md`, `yasser-profile.md`, `intelligence-core.md`, `00 - Rules/never-do.md`, plus rewrites of `personas.md`, `project-overview.md`, `competitive-landscape.md`. Plus `summary:` frontmatter on 24 more 06-Context + 00-Rules docs.
- **PFF-Brain canonical docs** also written (parallel C3 pass — MISSION, personas, architecture-overview + 27 frontmatter additions).
- **Hourly noise purge** at `~/Library/LaunchAgents/com.ammar.bm-noise-purge.plist` (loaded). Keeps session-log re-adds from drowning canonical docs in retrieval.
- **`/wrap-up` v2** at `~/.claude/skills/wrap-up/SKILL.md` (global) + project extension at `~/time-manager-desktop/.claude/skills/wrap-up/SKILL.md`. 11 phases (parked/shipped/interrupted detection → 7 memory surfaces → vault state propagation → basic-memory write → corpus refresh → self-improve → TickTick → walkthrough → error log → NEXT.md → subagent verify → stop signal). Run-and-walk-away.
- **Phase D deferred** to next session: `claude-mem mcp` is wired in `~/.claude/settings.json` but the new MCP server only attaches on next session start, so `build_corpus` / `prime_corpus` will run then. Targets: `yasser-profile-brain`, `intelligence-core-brain`, `aif-decisions-brain`.

How to verify: open a fresh Claude in `~/time-manager-desktop` and ask any Timed question. The Memory Protocol should fire `mcp__basic-memory__search_notes` and Claude should answer from canonical docs (not training data, not session logs).

## ★ NEW STATE ★ — `unified` is the source of truth

As of 2026-04-27, the four divergent branches have been merged into one trunk (`unified`). This branch:

- ✅ Carries TimedKit (123 shared Swift files) + TimedMacApp + TimediOS + Wave 1+2 backend + voice path + consolidated docs.
- ✅ Builds green for **swift build**, **xcodebuild TimedMac (arm64 Release)**, AND **xcodebuild TimediOS (Simulator)** — all from one branch.
- ✅ Produces `dist.noindex/Timed.dmg` (31 MB, ad-hoc signed) via `bash scripts/package_app.sh && bash scripts/create_dmg.sh`.
- ⚠️ Apple Developer Program enrollment **PARKED 2026-04-27** (attempted, redirected to free-tier `/account`; resume when Ammar has a clear window — see Chain C). DMG remains ad-hoc signed; Yasser must `xattr -cr /Applications/Timed.app` after install. iOS unreachable until enrolled.

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
```

**Chain A.1 — Ammar's daily-use Mac install (same artifact, locally installed):**

```bash
git checkout unified
bash scripts/package_app.sh                                # → dist.noindex/Timed.app
bash scripts/install_app.sh                                # → /Applications/Timed.app
# First launch: right-click → Open (one-time Gatekeeper unblock for ad-hoc cert)
# Re-run package_app.sh + install_app.sh after meaningful code changes to refresh.
# For active dev with rebuild-on-save: bash scripts/watch-and-build.sh
```

**Voice-proxy Edge Function deploy (one-time, supports both Chain A and A.1):**

```bash
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

**Chain C — Apple Developer enrollment (unblocks proper signing + iOS TestFlight): PARKED 2026-04-27**

Status: Ammar attempted enrollment 2026-04-27; signing in to `developer.apple.com/programs/enroll` redirects to `/account` (free-tier dev account already exists; paid Program upgrade not yet started). Parked until Ammar has a clear window to push the enrollment through identity verification + payment.

When resuming:

1. Sign in to `developer.apple.com/account`. From the account dashboard, find "Membership details" / "Join the Apple Developer Program" → click **Enroll**. (The `/programs/enroll/` URL redirects to `/account` once signed in — this is normal.)
2. Decide entity type before clicking through:
   - **Individual** ($99/yr, faster, seller name = personal). Use this if speed > entity branding.
   - **Organization** (needs D-U-N-S for Facilitated, slower verification). Right long-term, can migrate apps later but it's painful.
3. Complete Apple identity verification (24-48h for Individual; days-to-weeks for Organization).
4. Provision Developer ID Application cert (Mac) + Apple Distribution cert (iOS).
5. `xcrun notarytool store-credentials timed-notary --apple-id ammar@facilitated.com.au --team-id <TEAM> --password <APP_PASS>`.
6. Switch `scripts/package_app.sh` `--sign -` → `--sign "Developer ID Application: …"` + `--options runtime`.
7. `bash scripts/notarize_app.sh && bash scripts/create_dmg.sh` → properly distributable DMG (no `xattr` ritual needed).
8. App Store Connect → register `com.ammarshahin.timed.ios` → provisioning profile → archive → upload to TestFlight → invite Yasser.

While parked, **iPhone is unreachable** except via Track B (Xcode Personal Team signing, 7-day expiry, requires re-installing weekly via Xcode while phone is tethered). Mac daily-use is unaffected — Chain A.1 covers it.

Full plan in `/Users/integrale/.claude/plans/ultrathink-i-need-you-cached-glade.md`.

## Current branch

`ui/apple-v1-local-monochrome` — UI / voice work + all consolidated docs. **Backend code (`trigger/`, `services/`) is on `ui/apple-v1-restore` and `ui/apple-v1-wired`, not here.** The merge to co-locate code with docs is itself a pending decision.

See `docs/SINCE-2026-04-24.md` for full track-by-track detail, /collab outcomes, branch topology, and lessons.

See `BUILD_STATE.md` for current-branch UI / voice surface inventory.

See `HANDOFF-wave2.md` for the Wave 2 deployment runbook (PRs, schemas, manual steps).

See `docs/sessions/2026-04-25-wave-1-2-shipped.md` for the full Wave 1+2 session writeup (architecture, bugs, lessons, infra stack).
