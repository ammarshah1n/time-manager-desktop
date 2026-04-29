# HANDOFF.md — Timed

Last updated: 2026-04-29 late evening (Microsoft pipeline verified end-to-end with real outlook.com account)

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

**Gmail track is next** — see `~/.claude/plans/we-are-doing-whats-rustling-fog.md` Phase B-1. Recommended path: open a new claude window after sleep, paste the prompt verbatim, scaffold `Sources/TimedKit/Core/Mail/*.swift` without touching AuthService. Phase B-2 (the AuthService merge + UI) is tomorrow fresh.

**Security-hardening pass remains deferred** — 32 modified Edge Functions + 5 untracked CI/lint files still WIP from a prior session. Voice-llm-proxy's CORS-tightening (`Allow-Origin: env-driven` instead of `*`) shipped tonight as a side-effect of the orb fix; the rest waits.

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

**Held for tomorrow morning (5 min total — `~/Desktop/morning-checklist.txt`):**
1. Trigger.dev cloud deploy — 10/10 schedules cap; cloud has stale Dev schedules from earlier deploy churn. Code declares 9 schedules (after demoting `outcome-harvester` alongside `ingestion-health-watchdog`). Manual dashboard cleanup before redeploy.
2. ElevenLabs agent ASR portal switch to Scribe v2 Turbo.
3. Graphiti backfill — depends on #1 then trigger via Trigger.dev tasks page.

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

**Recovered secrets (already in Trigger.dev cloud env, safe to use on Fedora when needed):**
- `GRAPHITI_MCP_URL` (Fedora-local): `http://localhost:8080` — note: cloud env has `http://localhost:8001` which is wrong if running on Fedora; cloud value was set assuming a different infra layout.
- `GRAPHITI_MCP_TOKEN` (Fedora container): `cd5f6280c427fe736e0246f7d34a4887d365a602dbba0b738b2ada385dcc22e1` — note: cloud env has a DIFFERENT token (`133832017a2f...`); they need to be reconciled before deploy or the deployed tasks will fail to authenticate against the Fedora MCP.
- `NEO4J_PASSWORD` mismatches too (Fedora container = `V5Z86JFUcrCjeRGDrEmupETS`, cloud = `timedneo4jdev`).
- These mismatches are a pre-existing infra fork — fix before the cloud deploy can usefully exercise Fedora services. (Or the intent is for cloud to talk to a Cloudflare-tunneled Graphiti — see `scripts/refresh_graphiti_tunnel.sh`).



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
