# HANDOFF.md — Timed

Last updated: 2026-05-04 (PA co-edit invite shipped)

## ★ 2026-05-04 ★ — PA co-edit invite shipped

**State: SHIPPED.** Yasser can invite Karen to co-edit his Timed task list end-to-end.

**Done:**
- Migrations 20260504100000–100006: `workspace_invites`, `pa_workspace_ids()`, `tasks.created_by`, RESTRICTIVE PA deny-list, atomic `accept_workspace_invite(p_code uuid)`, PA self-delete, same-user already-member resume, RPC ambiguity fix, and non-recursive invite revoke RLS.
- Edge Function `accept-invite`: thin JWT-passing wrapper around the RPC with errcode-specific UX copy.
- Deployed `bootstrap-executive` so new Auth users receive both executive-id and auth-user-id workspace memberships before accepting PA invites.
- Swift: `TimedDeepLink`, `AcceptInviteSheet`, `WorkspaceSwitcher`, `SharingPane` Apple share sheet + active invite revoke + PA leave, `AuthService.switchWorkspace`, and cache clearing via `DataBridge`/`DataStore`.
- Web: `facilitated.com.au/timed/invite/<code>` landing page with `timed://invite/<code>` deep link and DMG fallback; `scripts/publish_dmg.sh` publishes the DMG into the facilitated repo.

**Verification:**
- `swift build` ✅; `swift test` ✅ (125 tests); `swift test --filter PARoleRLSGuardTests` ✅.
- `deno check supabase/functions/accept-invite/index.ts` ✅; `npx supabase migration up --linked` ✅; `accept-invite` OPTIONS ✅ after propagation; `accept-invite` + `bootstrap-executive` deployed ✅.
- Remote two-profile smoke ✅ (`runId=1777873949218-26e0e1e6`): Karen accepted Yasser invite as `pa`, second accept returned `already_member=true`, PA tasks count `2`, PA email/behaviour counts `0`, revoke persisted, leave-workspace deleted one PA membership.
- Negative smokes ✅: invalid JWT `401`, own invite `22023`, second PA on used invite `P0002` / "This invite has already been used.".
- DMG packaged and copied to facilitated repo: `public/downloads/Timed.dmg`, SHA-256 `c9ceb4efa4702987cc1f088f21ff0648b0ba80903c328fb14efb271228608a89`; facilitated build ✅.

**Known gaps:**
- iOS PA invite UI is not built yet; Apple Developer enrollment still blocks notarized Mac release and TestFlight/App Store URLs.
- DMG is still ad-hoc signed, so first launch may require right-click → Open or `xattr -cr /Applications/Timed.app`.
- Remote smoke Auth/workspace rows were intentionally left as non-production smoke evidence; no destructive cleanup was run.

**Next:** Apple Developer enrollment → notarized DMG/TestFlight links, then swap landing-page fallback copy to production distribution.

## ★ 2026-05-04 UTC ★ — Launch UX hardening verified, remote launch ops parked

**State: PARKED / verified working tree on `unified`.** The `docs/LAUNCH-UX-FINDINGS.md` pass is implemented and locally verified, but it is **not committed** because the repo had substantial pre-existing dirty state before this session and several touched files contain mixed-ownership hunks.

**Done:**
- Added launch-UX static guards in `Tests/LaunchUXGuardTests.swift` and fixed the design guard subprocess helper so the full Swift suite no longer pipe-deadlocks.
- Added `SyncHealthCenter`, offline replay diagnostics, queued task-delete tombstones, queued behaviour/reason replay, and Settings sync-health retry copy.
- Hardened Tasks, Today, Triage, Waiting, Morning Interview, Morning Briefing, Settings, and Task Detail UX copy/flows from the findings list.
- Hardened `generate-morning-briefing` for service-role cron plus user-scoped generation, added the daily cron migration, and changed `graph-webhook` to fail closed if enqueueing fails.
- Hardened packaging/notarization scripts so release packaging can require Developer ID and notarization instead of silently shipping ad-hoc builds.

**Verification completed:**
- `swift build` ✅
- `swift test` ✅ (110 tests)
- `swift test --filter DataBridgeTests` ✅ (23 tests)
- `swift test --filter LaunchUXGuardTests` ✅ (11 tests)
- `swift test --filter TimedDesignGuardTests` ✅
- `deno check supabase/functions/generate-morning-briefing/index.ts supabase/functions/graph-webhook/index.ts` ✅
- `git diff --check` ✅
- `bash -n scripts/package_app.sh scripts/notarize_app.sh` ✅
- `TIMED_REQUIRE_NOTARIZATION=1 TIMED_CODESIGN_IDENTITY=- bash scripts/package_app.sh` ✅ correctly exits 64
- `graphify update .` ✅ (foreground; background run hit a harness/Python bad-fd quirk)

**Three unblock chains:**
1. **DMG to Yasser / packaging:** PA invite fallback DMG is published on `facilitated.com.au`, but production-quality delivery still needs Apple Developer enrollment, Developer ID Application identity, Team ID, and notarization. Do not present the ad-hoc DMG as the final production release.
2. **Wave 2 nightly engine / backend:** cron/Trigger/Supabase work is deployed; current follow-up is live verification that Trigger.dev morning fan-out creates all 3 briefings without manual back-fill. TickTick has the scheduled verification task.
3. **Apple Developer enrollment:** still blocked because Ammar does not yet have the Apple developer account. This blocks notarized macOS release, iOS/TestFlight, and replacing the ad-hoc DMG fallback.

**Next:** verify the Trigger.dev 05:30 ACST fan-out task, ask Ammar before deleting any remote smoke rows, then complete Apple Developer enrollment and notarized DMG packaging.

**TickTick follow-ups created:**
- `69f7e3328f08cbca66af444b` — Deploy and smoke launch UX Supabase briefing/webhook changes.
- `69f7e33b8f08be467ea0652f` — Supersede Yasser DMG send task until Developer ID notarization passes.
- `69f7e3418f086d028b1d06b0` — Ask Ammar before deleting launch UX remote smoke data.

## ★ 2026-05-03 UTC ★ — True subagent swarm audit parked

**State: PARKED.** The requested multi-agent ship-readiness audit did not complete because `swarm spawn` created queued `/login` / `startup queued` sessions that did not attach to live Jcode clients.

- Verified auth is not the blocker: `jcode auth-test --provider openai --model gpt-5.5` passed provider and tool smoke.
- Proved manual attach works: `jcode -C /Users/integrale/time-manager-desktop --provider openai --model gpt-5.5 --resume <session_id>` moved validation session `session_crab_1777806218103_6d0ea4615ba8637b` to ready.
- Audit sessions that were spawned but not attached: `session_chicken_1777806547882_c55cabf4edbc5f5e`, `session_unicorn_1777806547870_cb9977a4db8b0baa`, `session_mouse_1777806547895_59fb572fd7141389`, `session_hippo_1777806547832_c4eaa1a7192768c7`, `session_flamingo_1777806547852_ecfacb94180e8fc9`.
- Handoff: `~/.claude/projects/-Users-integrale-time-manager-desktop/NEXT.md`.
- Basic Memory: `timed-brain/06-context/learnings/2026-05-03-jcode-swarm-spawn-requires-explicit-client-attach`.
- TickTick: `Fix Jcode swarm auto-attach, then rerun Timed ship-readiness audit` (`69f72e928f08eac4e9c2a703`).

**Next:** automate or repair Jcode swarm attach so every spawned session immediately runs a real `jcode --resume <session_id>` client, then rerun the 5-agent ship-readiness audit.

## ★ 2026-05-01 late afternoon ★ — Installed app login prompt + capture voice fixed

**State: SHIPPED.** The Dock-pinned app now points at `/Applications/Timed.app`, and `/Applications/Timed.app` was replaced with the freshly packaged build from `unified`.

- Commits: `06dc8dd fix(timed): stop launch outlook prompt`, `92514f3 fix(timed): surface capture voice permissions`, `23d297c fix(timed): package google oauth config`, `ad2f432 fix(timed): isolate voice capture audio tap`
- Root cause for repeated login: `AuthService.bootstrapExecutive()` auto-called Outlook/MSAL connection on app launch; ad-hoc builds can hit MSAL keychain `-34018`, so launch restore cascaded into repeated interactive login prompts.
- Root cause for broken Capture voice: voice permission denial only logged `Voice capture not authorised — aborting start`; Capture UI did not surface the denial or send the user to macOS privacy settings.
- Packaging fix: `scripts/package_app.sh` now includes the Google OAuth `GIDClientID` and reversed client URL scheme, matching `Platforms/Mac/Info.plist`.
- Verification: `swift build`, `swift test` (71 tests), `bash scripts/package_app.sh`, `codesign --verify --deep --strict --verbose=2 /Applications/Timed.app`.
- Installed binary hash: `/Applications/Timed.app/Contents/MacOS/timed` matches `dist.noindex/Timed.app/Contents/MacOS/timed` at `e5838964834b4e2668357313d0c8930fe65271dd4b8726b739963c2366108664`.

**Next:** launch Timed from the Dock. If Capture says microphone or speech permission is blocked, use its new Open Settings button and enable Timed under macOS Privacy.

## ★ 2026-05-01 ★ — Review remediation pass archived for Perplexity follow-up

**State: SHIPPED.** First implementation pass from the full-codebase review is committed on `unified` through `5d3ce91 chore(timed): record remediation build state`. The six review reports were copied out of `/private/tmp` into the repo so they survive the session.

- Reports: `docs/reviews/timed-code-review-2026-05-01/`
- Resume doc: `NEXT.md`
- Perplexity prompt: `docs/reviews/timed-code-review-2026-05-01/perplexity-review-prompt.md`
- Verification completed: `swift build`, `swift test` (71 tests), changed Edge Function `deno check`, Graphiti Python compile, `services/graphiti-mcp` `pnpm typecheck`, and packaging script syntax checks.

**Next:** run the Perplexity prompt against the archived reports, compare its output against `00-master-issue-list.md` and the remediation commits after `1770cb5`, then write the final implementation plan before making more code changes.

## ★ 2026-04-30 evening ★ — Assistant guidance audit completed

**State: SHIPPED.** Audited Claude/Codex guidance for Timed, PFF DD, and global assistant context. Timed repo guidance is now current with the unified branch protocol, shipped Gmail/Graphiti/security-hardening state, and the remaining manual ops.

- Commit: `e3d35b0 docs(timed): refresh assistant guidance`
- Timed guidance refreshed: `CLAUDE.md`, `.claude/rules/session-protocol.md`, `.claude/rules/ai-assistant-rules.md`
- Codex local memory refreshed outside this repo under `~/.codex/memories/` and `~/.codex/AGENTS.md`
- PFF DD repo was already dirty before the audit (`BUILD_STATE.md`, `SESSION_LOG.md`, `docs/rules/corrections-log.md`, `scripts/reset-demo-profile.sh`), so no PFF repo files were edited.

**Remaining:** rotate the provider API key found in global Claude settings/backups and clean local cached copies with explicit approval; reconcile the stale comment in PFF DD `.claude/hooks/session-setup.sh` after the pre-existing dirty worktree is resolved.

## ★ 2026-04-30 mid-afternoon ★ — Graphiti backfill completed

**State: SHIPPED.** Ammar added $10 Voyage credits, then the deployed Trigger.dev Prod task was triggered and monitored to a terminal success.

- Trigger run: `run_cmol21ysj5ohl0unbrlg495f2`
- Trigger task: `graphiti-backfill`
- Agent session: `cb1ea4fa-15dd-4af2-af7f-ff3799ea468c`
- Output: `ona_nodes.scanned=0/emitted=0`, `ona_edges.scanned=0/emitted=0`, `tier0_observations.scanned=2/emitted=2`
- Invocation note: Trigger.dev 4.4.4's public CLI has no registered task-trigger command; this run used the package's internal `triggerTask()` command against the already-logged-in `default` profile and Prod project `proj_vrakwmzenqmmhrzhfqyl`.

**Remaining:** open Timed → Settings → Accounts → "Add Gmail" → sign in with `5066sim@gmail.com`; resume Apple Developer enrollment; decide whether optional local-only `deepgram-transcribe` should stay parked.

## ★ 2026-04-30 early afternoon ★ — Gmail backend live + security hardening deployed

**State: SHIPPED.** The remaining Gmail backend ops from the morning handoff are complete on Supabase project `fpmjuufefhtlwbfinxlx`.

- Applied migration `20260430120000_gmail_provider.sql` with linked-project `supabase db push`; `supabase migration list --linked` now shows it on both local and remote.
- Redeployed `voice-llm-proxy`; remote function list shows version 25 updated `2026-04-30 05:06:33 UTC`, so the `(outlook_linked OR gmail_linked)` inbox gate is live.
- Deployed the 16-function security-hardening set with `scripts/deploy_security_hardening.sh`; remote function list shows April 30 updates for the nightly, weekly, briefing, ACB, voice-feature, and relationship-card functions.
- Smoke check: unauthenticated `POST /functions/v1/nightly-phase1` returns HTTP 401 with `UNAUTHORIZED_NO_AUTH_HEADER`.
- Security WIP is no longer dirty: hardening, advisory CI checks, session-start context preload, Graphiti parked-state docs, stale specs cleanup, and related Swift test repairs are committed locally.

**Remaining:** open Timed → Settings → Accounts → "Add Gmail" → sign in with `5066sim@gmail.com`; resume Apple Developer enrollment; decide whether optional local-only `deepgram-transcribe` should stay parked. Graphiti backfill completed later the same day; see the mid-afternoon entry above.

## ★ 2026-04-30 morning ★ — Gmail integration shipped (additive)

**State: SHIPPED** (commit `4e5cf9e` on `unified`, pushed). Gmail + Google Calendar now run as a parallel set of services alongside the just-verified Microsoft pipeline. Microsoft path is **untouched** — additive only.

**New code** (4 files in `Sources/TimedKit/Core/`): `Clients/GoogleClient.swift` (GIDSignIn lifecycle), `Clients/GmailClient.swift` (Gmail v1 + Calendar v3 HTTP), `Services/GmailSyncService.swift` (history-cursor poll loop, dual-write to existing `email_messages`, classify-email trigger, Tier 0 emission), `Services/GmailCalendarSyncService.swift`. AuthService gains `signInWithGoogle` / `connectGmailIfPossible` / `makeGoogleTokenProvider` — all parallel, no edits to Microsoft methods. PrefsPane has an "Add Gmail" affordance. `TimedAppShell` defensively forwards `com.googleusercontent.apps.*` URLs to `GIDSignIn.handle`.

**Schema** (additive): migration `20260430120000_gmail_provider.sql` adds `executives.gmail_linked`, `executives.google_email`, and `connected_accounts` table (executive_id, provider, account_email, linked_at, revoked_at — RLS self-read). `voice-llm-proxy.readInboxSnapshot` gate flipped from `outlook_linked` to `(outlook_linked OR gmail_linked)`. No `provider` column added to `email_messages` — Gmail/MS message IDs don't collide and the orb's search_emails stays provider-agnostic.

**GCP wiring** (Comet drove the console + Ammar reviewed): project `timed-494900`, OAuth client `461539145615-...apps.googleusercontent.com` (iOS type, bundle id `com.ammarshahin.timed`). Stored in **1Password Timed vault → "Google OAuth — Timed macOS"** with reversed scheme + project ID + status. `Platforms/Mac/Info.plist` gained `GIDClientID` + the reversed-client-ID URL scheme. Consent screen is in **Testing**; the only working test user is `5066sim@gmail.com` (Google's validator rejected `ammar@facilitated.com.au` and `yasser@facilitated.com.au` because they're Cloudflare email forwards, not real Google accounts).

**DMG repacked** + installed at `/Applications/Timed.app`.

**Production ops completed later the same day.** The migration is remote-applied and `voice-llm-proxy` is redeployed; see the early-afternoon entry above.

Next manual step: open Timed → Settings → Accounts → "Add Gmail" → sign in with `5066sim@gmail.com`.

**Decision: Yasser stays on Microsoft.** Per Ammar's call this session, Gmail is for Ammar's own use (5066sim account); Yasser keeps the Outlook path that just verified end-to-end last night.

**Codex follow-up (deferred AIF work):** AIF decision extraction for this session is intentionally skipped — see `~/Downloads/codex-aif-followup-2026-04-30.md` for the prompt + the 1–3 candidate decisions Codex should log (additive Gmail provider; "don't touch active auth" applied to Microsoft+Gmail parallel pattern; permission-hook prod-mutation guardrail confirmed working).

## ★ 2026-04-29 LATE EVENING ★ — Microsoft pipeline end-to-end verified

**State: SHIPPED.** Four commits on `unified` (`f8c5fa1` → `ab253af` → `beb7358` → `cdd72b7`) close the loop from Microsoft sign-in through to the voice orb's context layer.

**Verified empirically** with executive `9ea0d114-71af-4790-8d5b-3a25b8f46504` and a real outlook.com test account:
- MSAL token acquired (interactive flow on consumer/MSA tenant)
- `executives.outlook_linked = true` after first successful sync (was false until tonight)
- "timed test" calendar event flows: Microsoft Graph → Swift → `calendar_observations` (with title!) → DB trigger → `tier0_observations`
- Voice orb's `voice-llm-proxy` now sees the event including the title and including in-progress events (was filtering them out)

**Five distinct fixes shipped tonight:**
1. MSAL `keychainSharingGroup = Bundle.main.bundleIdentifier` — forward-compat for when Apple Developer Program enrollment lands a Team ID. On ad-hoc builds the keychain writes still 34018, so the in-memory token band-aid in `AuthService.makeTokenProvider` stays.
2. `scripts/package_app.sh` codesigns with `--entitlements "$ROOT_DIR/Platforms/Mac/Timed.entitlements"`. The script was previously dropping the entitlements file silently — every entitlement edit was a no-op until tonight.
3. `GraphClient.fetchDeltaMessages` switched from `/me/messages/delta` (work/school only — 400s on consumer accounts with "Change tracking is not supported against 'microsoft.graph.message'") to `/me/mailFolders/inbox/messages/delta` (works on both). Skibidi 4.3's `$filter=receivedDateTime ge ...` 30-day clamp dropped at the same time — incompatible with consumer delta.
4. New migration `20260429120000_grant_get_executive_id.sql` — GRANT EXECUTE on both overloads of `get_executive_id()` to authenticated. SECURITY DEFINER alone wasn't enough; client-JWT INSERTs were getting `permission denied for function get_executive_id` against every RLS policy that called it.
5. `CalendarObservationRow` gains `title` + `description` fields (columns existed since migration 20260424000001 but the Swift writer never populated them). Plus `voice-llm-proxy` calendar query: `starts_at >= now` → `ends_at >= now` so an in-progress meeting doesn't drop out of the orb's context window.

**Diagnostic wins:** added `graphFileLog` calls to `fetchDeltaMessages`, `fetchCalendarEvents`, and both write paths in `CalendarSyncService.emitCalendarObservationsIfPossible`. On ad-hoc-signed builds where `os.Logger` is filtered out (per memory `feedback_adhoc_logs_invisible`), this is the only visible diagnostic surface — three distinct silent failures became visible the moment we wired this up.

**Gmail track completed next day** — the old Phase B plan is now historical. Gmail shipped additively on 2026-04-30; see the morning and early-afternoon entries above.

**Security-hardening pass later completed** — see the 2026-04-30 early-afternoon entry. Voice-llm-proxy's env-driven CORS is live alongside the hardened cron/system functions.

## ★ 2026-04-29 evening ★ — Memory-first hook architecture (commit 826eb58)

## ★ 2026-04-29 evening ★ — Memory-first hook architecture (commit 826eb58)

**State: SHIPPED.** Replaced broken nag-only `memory-gate.sh` (v1) with a two-layer system that actually enforces the memory-first protocol without becoming a roadblock.

### Root cause of 200K-token burn earlier this session

`memory-gate.sh` v1 used `exit 0 + stderr` for its nag. **stderr at exit 0 is invisible to Claude's reasoning loop** — it reaches the terminal but never the model's context. Claude saw the Agent tool call as approved and proceeded, blind to the warning. Three Explore subagents fired in parallel before user intervention. Architectural failure, not discipline failure. Pattern was structurally broken from day one.

### What shipped

**Layer 1** — `.claude/hooks/memory-preempt.sh` (new). UserPromptSubmit hook, fires once per session, injects vault-first reminder via `additionalContext` JSON (which IS visible to Claude). Routes through basic-memory before Claude considers spawning research tools.

**Layer 2** — `.claude/hooks/memory-gate.sh` (replaced). PreToolUse hook narrowed to `Agent | Task | WebSearch | WebFetch | mcp__perplexity-comet__*`. Decision tree: basic-memory call → mark sentinel; sentinel exists → inject light reminder + allow; syntax-shaped prompt (refactor/rename/format/lint) → silent allow; research-shaped + no sentinel → BLOCK exit 2 with actionable stderr; ambiguous → default-pass. Block reason explicitly tells Claude: *"if vault doesn't have it, proceed — burn the tokens, that's the point."* Self-healing roundtrip; user not pulled in.

**`.claude/settings.json`** — split PreToolUse so permission-check.sh stays on `*` matcher; memory-gate.sh narrowed to research tool matcher only.

Avoids GH #16598 (`permissionDecision: "allow"` crash) and #39814 (`updatedInput` silently dropped on Agent).

### Smoke-tested (7/7 pass)
1. Research Agent w/o sentinel → BLOCK + actionable stderr
2. Syntax Agent ("refactor X to Y") → silent allow
3. Research Agent w/ sentinel → inject reminder + allow
4. Read tool → gate doesn't fire (instant pass)
5. basic-memory call → sentinel created
6. First user prompt → memory-first reminder injected
7. Second user prompt → silent (one-shot honoured)

### Takes effect on NEW Claude Code sessions only

This session keeps cached old behaviour. Restart any session you want to test against.

### Rollback (2 commands)
```
cp .claude/hooks/memory-gate.sh.bak .claude/hooks/memory-gate.sh
git checkout .claude/settings.json
```

### Reports + plan archived
- `~/Downloads/1) Where Models Agree.md` — model-council convergence
- `~/Downloads/Smarter PreToolUse Memory-First Hooks for Claude Code.md` — full design doc
- `~/Downloads/memory-gate-hook-plan.html` — implementation plan I built before shipping

### Side note — AIF /extract crash + scheduled rerun

The earlier "Mac crash" wasn't 3 caffeinates / ccstatusline as I first claimed. **Actual culprit:** `/extract` skill (AIF Decision Extractor Stage 2) running `~/aif-vault/pipeline/02_extract_decisions.py` with `CONCURRENCY = 60` over a 132 MB corpus. Spawns 60 parallel `claude --print` subprocesses → crushes the Mac. Stage 2 is resumable (uses `.processed_sessions.txt`), so partial-completion survives.

**Scheduled rerun:** `launchd` LaunchAgent `com.ammar.aif-extract-rerun` fires once at **2026-04-30 00:30 ACST**. Plist at `~/Library/LaunchAgents/com.ammar.aif-extract-rerun.plist`. Wrapper script: `~/Desktop/aif-rerun/run-extract-stage2.sh` (logs to `~/Desktop/aif-rerun/run-<ts>.log`).

**BEFORE 00:30:** edit `~/aif-vault/pipeline/02_extract_decisions.py` and lower `CONCURRENCY` to ~10–15, otherwise it'll crash again. Cancel rerun: `launchctl unload ~/Library/LaunchAgents/com.ammar.aif-extract-rerun.plist`.

## ★ 2026-04-29 PM ★ — Morning-checklist closure (no code changes)

- **Trigger.dev cloud (item 1):** upgraded to **Hobby tier ($10/mo published, $1/mo on Ammar's invoice — flagged for next-cycle verify)**. `pnpm exec trigger deploy --env prod` succeeded → **Version `20260429.2`** live with 13 detected tasks (9 schedules + 4 manual incl. `graphiti-backfill`). Idempotent: re-running with no code changes yields identical version.
- **ElevenLabs agent ASR (item 2):** agent `agent_3501kpyz0cnrfj8tgbb2bmg5arfk` was already on Scribe v2 Turbo (Alpha) — verification only, no change.
- **Graphiti backfill (item 3):** Comet handed a 4-step verification workflow (Hobby billing → 9 schedules registered → trigger backfill empty payload → monitor to terminal state). Awaiting Comet report. If failure mode is `GRAPHITI_MCP_TOKEN` mismatch, recover live token via `ssh ammarshahin@192.168.0.20 'podman inspect timed-graphiti-mcp'` and reconcile against Trigger.dev secrets dashboard.
- **No code changes this session** — `git status` clean modulo state-file updates. DMG at `dist.noindex/Timed.dmg` unchanged from `e7d2b53`. Yasser handoff still gated on item 3 result.
- **Off-Timed admin:** personal subscriptions audit reconciled to `~/Documents/SUBSCRIPTIONS.md` + `~/Desktop/Subscriptions.xlsx`. Steady-state $268/mo. Not Timed-billable; logged here only because Trigger.dev Hobby is the line item that crosses both ledgers.

> **READ FIRST:** `docs/UNIFIED-BRANCH.md` — permanent reference for the consolidated architecture.
> **Narrative:** `docs/SINCE-2026-04-24.md` — full story of the weekend work.
> **Resume next session:** `~/.claude/projects/-Users-integrale-time-manager-desktop/NEXT.md`.
> **Last night's diagnostic:** `~/Downloads/timed-onsite-deploy-handoff-2026-04-28.md` (the deploy walls + how each was diagnosed).
> **Tonight's full report:** `~/Desktop/skibidi-final-report.md` (every phase + state + Comet integration).
> **Morning checklist:** `~/Desktop/morning-checklist.txt` (3 manual clicks, ~5 min total).

## ★ 2026-04-29 ★ — Skibidi sprint shipped (autonomous overnight run)

Five commits on `origin/unified` covering Phases 1.1/1.2/1.3/1.4 (substrate), 3.1/3.2/3.4/3.5/3.6/3.7 (engine wiring), 4.1/4.2/4.3/4.4/4.5/4.6/4.7 (cold-start UX + Microsoft OAuth), 5.2/5.4/5.5/5.6/5.7/5.8/5.9 (voice/orb polish), 6.1/6.2/6.3/6.5/6.6 (reliability) plus Phase 2.1/2.5 (voice proxies deployed + tier0 trigger code-existence verified). DMG repacked at `dist.noindex/Timed.dmg` (31 MB, ad-hoc signed), launches without Gatekeeper modal.

Edge Functions deployed: `anthropic-proxy`, `elevenlabs-tts-proxy`, `orb-conversation`, `voice-llm-proxy`, `weekly-pattern-detection`. Migrations applied to `fpmjuufefhtlwbfinxlx`: `20260428120000_score_memory.sql`, `20260428130000_outlook_linked.sql`. ELEVENLABS_API_KEY secret set on the project (pulled from 1Password Timed vault).

**Held-for-morning checklist is now historical:** Trigger.dev Prod deploy is live, ElevenLabs ASR was verified on Scribe v2 Turbo, and Graphiti backfill completed on 2026-04-30. See the current 2026-04-30 entries at the top of this file.

Commits this sprint: `cf53995` substrate + 5 severed circuits → `3508abf` ASWebAuthSession + bounded sync + pre-warm + session refresh → `e785aac` Comet integration → `646ced1` doc state → `6670ade` outlook_linked + MSAL banner + 429 retry + queue skip-bad + EFs deployed → `e7d2b53` wrap-up state.

## ★ Earlier — onsite-deploy 2026-04-28 PM/overnight run

## ★ Onsite-deploy 2026-04-28 PM/overnight run

**Step 1 — voice proxies → Supabase: SHIPPED LIVE.**
`anthropic-proxy` + `elevenlabs-tts-proxy` deployed to `fpmjuufefhtlwbfinxlx` (~19:13 AEST). Both endpoints return 401 unauth-gated (correct = alive, NOT 404). Morning Interview AI + voice TTS in `/Applications/Timed.app` now reach live proxies.

**Step 2 — Trigger.dev pipeline deploy: PARKED on Free-plan schedule cap.**
- Trigger.dev project = `proj_vrakwmzenqmmhrzhfqyl` / slug `timed-overnight-3fjz` / org `timed-c259` / account `ammar@facilitated.com.au`. CLI binary is `trigger`, NOT `trigger.dev` — `pnpm run deploy` is broken; use `pnpm exec trigger deploy`.
- All required project env vars confirmed present on Trigger.dev cloud (ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GRAPHITI_MCP_URL, GRAPHITI_MCP_TOKEN, NEO4J_URI/USER/PASSWORD, MSFT_APP_*, VOYAGE_API_KEY). The HANDOFF instruction said "GRAPHITI_BASE_URL" — the code actually reads `GRAPHITI_MCP_URL` everywhere, env name is correct on cloud. No fix needed.
- Two cascading errors hit during deploy:
  1. Cloud worker container imports `trigger.config.ts` BEFORE user env is injected, and the file `throw`s on missing `TRIGGER_PROJECT_REF`. **Fix landed:** `trigger.config.ts:15` now defaults to `proj_vrakwmzenqmmhrzhfqyl` (committed in `cf53995`/`skibidi sprint phase 1`).
  2. `Error: You have created 10/10 schedules` — Free plan caps schedules ORG-WIDE (not per-env, despite per-env framing in dashboard). Codebase had 11 `schedules.task` exports. **Fix landed:** `ingestion-health-watchdog` demoted from `schedules.task` → `task` (still callable on demand) — codebase now defines exactly 10 schedules. Same commit family.
- Even after the demotion, deploy still aborts at 10/10 because Dev env on Trigger.dev cloud has 10 schedules registered from prior `trigger dev` sessions, including the now-orphaned watchdog. Schedule reconciliation isn't atomic enough to free the slot during deploy — the cap check happens BEFORE reconcile.
- **Resume options (need Ammar):** (a) Trigger.dev dashboard → Settings → Billing → upgrade plan; (b) manually delete a stale schedule via dashboard ellipsis menu (declarative-warning may or may not block; needs human-eyes verification — declarative warning says use CLI, but emergency delete may still be allowed); (c) extract a project-scoped API key from dashboard `proj_vrakwmzenqmmhrzhfqyl` settings and `curl -X DELETE -H "Authorization: Bearer <TRIGGER_API_KEY>" https://api.trigger.dev/api/v1/schedules/sched_<id>` (PAT `tr_pat_*` returns 401 — needs the project-scoped `tr_dev_*` or `tr_prod_*` key). Comet was used to investigate but reported Production = 0 schedules (correct — the 10 are in Dev env from prior local-dev runs).

**Step 3 — Graphiti backfill on Fedora: PARKED on invocation-shape mismatch.**
- Fedora (`ammarshahin@192.168.0.20`) is fully ready: `timed-graphiti`, `timed-graphiti-mcp`, `timed-neo4j`, `timed-litellm`, `timed-skill-library-mcp` all up 27h via podman. Neo4j 5.26 community + Graphiti API + Graphiti MCP all reachable on localhost (8000, 8080, 7474, 7687, 4000, 8081).
- HANDOFF's instruction `pnpm -F @timed/trigger exec ts-node trigger/src/tasks/graphiti-backfill.ts` is subtly wrong — the file exports `task({...})` from `@trigger.dev/sdk`, so ts-node imports the module but never invokes the run() body. The file's own docstring says "Triggered manually via `trigger.dev` dashboard or CLI once".
- **Resume options:** (a) once Step 2 deploy lands, hit the dashboard's "Test" button on the `graphiti-backfill` task; (b) start `trigger dev` from Fedora to register the local worker against Dev env, then trigger the task via dashboard or `tasks.trigger("graphiti-backfill")` from a tiny SDK script — but Dev env's 10/10 cap may bite again; (c) export the internal `backfillOnaNodes`/`backfillOnaEdges`/`backfillTier0` functions and write a thin wrapper script that calls them sequentially — most decoupled from Trigger.dev runtime, ~30 min of code work.

**Recovered infrastructure note:**
- Graphiti/Neo4j/MCP secret values were removed from this handoff. Recover them from the Timed vault or the relevant platform secret stores, then reconcile Fedora vs cloud values before deploying Graphiti-backed tasks.
- The pre-existing infra fork still needs resolution before cloud Trigger tasks can usefully exercise Fedora services. Or route cloud to the intended Cloudflare-tunneled Graphiti endpoint; see `scripts/refresh_graphiti_tunnel.sh`.



## ★ SHIPPED 2026-04-28 PM ★ — Beta-readiness sprint (commits `bcee82b` + `ec3a7fd`)

Three Perplexity Deep Research audits + an external Beta-Ready Execution Plan converged on the same picture: intelligence engine architecturally complete, delivery layer 5-6 caller-sites + one auth cascade away from beta. Shipped this afternoon:

**Auth + login**
- Email/password sign-up + sign-in via Supabase Auth (`AuthService.signInWithEmail`, `signUpWithEmail`, `sendPasswordReset`).
- LoginView: Sign-in / Create-account segmented picker with `TimedMotion.springy` animation, Microsoft 4-square logo asset (vector PDF in `Assets.xcassets/ms-logo.imageset/`), welcome banner pill (ultraThinMaterial) flashes 1.4s on success.
- VoiceCaptureService MainActor crash fix — audio tap closure no longer reaches through `self.recognitionRequest`; captures local + appends on the audio thread (Apple Speech `.append` is thread-safe). Resolves `_swift_task_checkIsolatedSwift` crash on fresh-signup users.
- "Set up later" path: VoiceOnboardingView dismisses with `pendingVoiceOnboarding=true`; PrefsPane VoiceTab shows "Resume" row when pending.

**Auth cascade (Beta plan Blocker 1 — root cause of "orb is email-blind")**
- `AuthService.bootstrapExecutive()` now calls `connectOutlookIfPossible()` on success: `signInWithGraph(loginHint:)` → `EmailSyncService.start` → `CalendarSyncService.start`. Best-effort; graphAccessToken stays nil for users who decline MSAL prompt. Once a Microsoft user grants Outlook, email + calendar data start flowing into Tier 0 within seconds.

**Delivery layer wiring**
- `MorningBriefingPane` reachable via new sidebar entry (`NavSection.briefing`). The 5:30 AM Opus adversarial briefing is no longer orphaned.
- `AlertsPresenter` (new MainActor bridge) instantiated in `TimedRootView` as `@StateObject`; overlay renders `AlertDeliveryView` on the top-trailing edge with springy animation when `currentAlert != nil`. AlertEngine itself unchanged — just gave it a UI mount.
- `EmailClassifier.classifyLive` async path via `anthropic-relay` (Claude Haiku 4.5). Sender rules win first; AI fills "informational" default. Falls back to rule-based on network failure. Sync `classify` preserved → all existing tests still pass.
- iOS orb sheet: `ConversationOrbSheet` placeholder replaced with `ConversationView`. NSMicrophoneUsageDescription already in iOS Info.plist.
- DishMeUp polish: `DishMeUpPlanItem.bucket: String?` resolves to `TaskBucket.dotColor`. Plan rows render bucket-coloured dots instead of universal grey. `sessionFraming` weighted `.semibold` for visual hierarchy.

**Guardrails**
- `v1BetaMode` flipped: hardcoded `private let v1BetaMode = true` → `@AppStorage("v1BetaMode") = false` in `TimedRootView` + `PrefsPane`. Triage / Waiting / Insights / 5 PrefsPane tabs visible by default.
- `StreamingTTSService:92` misleading "AVSpeechSynthesizer" comment fixed; logs `TimedLogger.voice.warning` when fallback path triggers.
- `Tests/VoicePathGuardTests.swift` (new) — build-failing regression test. Any `AVSpeechSynthesizer / NSSpeechSynthesizer / SFSpeechRecognizer` reappearing in the orb call graph fails the test. `VoiceCaptureService` exempt (separate dictation feature).

**Build green**, packaged, installed at `/Applications/Timed.app`. LSDB sole `timed://` handler.

## Held for tonight (onsite, ~30 min ops)

The intelligence engine still has zero data flowing through it because three things aren't deployed:

```bash
# 1. Voice proxies — flips Morning Interview AI + voice TTS to LIVE
supabase secrets set ELEVENLABS_API_KEY=<key> --project-ref fpmjuufefhtlwbfinxlx
supabase functions deploy anthropic-proxy elevenlabs-tts-proxy --project-ref fpmjuufefhtlwbfinxlx

# 2. Trigger.dev — fires the entire nightly intelligence pipeline (NREM, REM, ACB refresh, weekly synthesis)
cd trigger
pnpm install
# Set: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ANTHROPIC_API_KEY, GRAPHITI_BASE_URL
pnpm run deploy

# 3. Graphiti backfill — fastest path to a smart orb (one-shot from Fedora)
ssh ammarshahin@192.168.0.20
cd time-manager-desktop
pnpm -F @timed/trigger exec ts-node trigger/src/tasks/graphiti-backfill.ts
```

After all three: `/Applications/Timed.app` → Microsoft sign-in → orb knows your inbox → briefing generates → alerts start firing as email arrives.

## ★ Earlier session (2026-04-28 AM) — research + diagnosis (superseded by sprint above)

Earlier today: surfaced Microsoft login was failing at Supabase code exchange via auth-logs (`/callback | 400: OAuth state parameter missing`), audited app via three parallel Perplexity Deep Research prompts (architecture, UX walkthrough, premium polish) + integrated a Beta-Ready Execution Plan from a separate research thread. The plan converged on 6 blockers + 15 polish items; PM sprint shipped 8 of them. Microsoft auth path itself is now bypassable via email/password (the GHOST GHOST in Tab 1's audit is now LIVE), and the cascade fix means even when Microsoft auth works, the orb actually gets data.

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
- **Phase D deferred** to next session: `claude-mem mcp` is wired in `~/.claude/settings.json` but the new MCP server only attaches on next session start, so `build_corpus` / `prime_corpus` will run then. Targets: `intelligence-core-brain`, `aif-decisions-brain`. (Originally listed `yasser-profile-brain` — dropped 2026-04-28 as an architectural failure: Yasser is a co-founder, not a modeled subject. Both founders are peer prototype users; no name-keyed corpus.)

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
| Wave 1+2 backend (Trigger.dev v4 + Graphiti/Neo4j + 3 services + NREM/REM engine + outcome harvester) | ✅ | ✅ via `54fe80e` | ✅ Trigger.dev Prod `20260429.2` live; Graphiti backfill completed in run `run_cmol21ysj5ohl0unbrlg495f2` | ✅ |
| 15 Wave 1+2 schema changes | ✅ | ✅ | ✅ pushed to Supabase `fpmjuufefhtlwbfinxlx` | ⚠️ tables exist; nothing writes to them yet |
| 3 new Edge Function proxies (`anthropic-proxy`, `elevenlabs-tts-proxy`, `deepgram-transcribe`) | ✅ | ✅ via `5acd23f` | ⚠️ Anthropic/ElevenLabs/voice proxy live; `deepgram-transcribe` remains optional local-only | ⚠️ partial |
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

**Voice-proxy Edge Function redeploy reference (already done; keep for recovery):**

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
3. Trigger.dev Prod deploy is live; keep secrets reconciled before running Graphiti-backed tasks
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

`unified` — single active trunk. Historical `ui/apple-v1-*` and `ios/port-bootstrap` branches are retained only as escape hatches.

See `docs/SINCE-2026-04-24.md` for full track-by-track detail, /collab outcomes, branch topology, and lessons.

See `BUILD_STATE.md` for current-branch UI / voice surface inventory.

See `HANDOFF-wave2.md` for the Wave 2 deployment runbook (PRs, schemas, manual steps).

See `docs/sessions/2026-04-25-wave-1-2-shipped.md` for the full Wave 1+2 session writeup (architecture, bugs, lessons, infra stack).
