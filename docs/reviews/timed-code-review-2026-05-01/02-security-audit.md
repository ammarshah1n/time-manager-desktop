# Timed Security Audit - 2026-05-01

| ID | Severity | Status | Finding | Primary evidence | OWASP | STRIDE |
|---|---|---|---|---|---|---|
| C1 | Critical | Confirmed | Ignored local compose file contains live-looking service-role and vendor secrets | `docker-compose.local.yml:12` | A02, A05 | Information Disclosure, Elevation |
| C2 | Critical | Confirmed | Tracked handoff document leaks Graphiti and Neo4j secrets | `HANDOFF.md:181` | A02 | Information Disclosure, Elevation |
| C3 | Critical | Confirmed | Legacy Anthropic proxy is a public-anon, unbounded Anthropic API proxy | `supabase/functions/anthropic-proxy/index.ts:7` | A01, A04, A05 | Spoofing, DoS, Elevation |
| H1 | High | Confirmed | Telegram control bot token and admin chat ID are tracked | `scripts/ralph-telegram.ts:23` | A02, A05 | Spoofing, Tampering, Elevation |
| H2 | High | Confirmed | Legacy ElevenLabs proxy is public-anon and lets callers choose text, voice, and model | `supabase/functions/elevenlabs-tts-proxy/index.ts:7` | A01, A04, A05 | Spoofing, DoS, Elevation |
| H3 | High | Confirmed | Batch polling function has no auth gate while using service-role DB writes | `supabase/functions/poll-batch-results/index.ts:14` | A01, A05 | Tampering, DoS, Elevation |
| H4 | High | Confirmed | Pipeline health endpoint has no auth gate and returns/writes global health data | `supabase/functions/pipeline-health-check/index.ts:369` | A01, A05 | Information Disclosure, DoS |
| H5 | High | Confirmed | Graph subscription renewal has no auth gate and reads OAuth tokens with service role | `supabase/functions/renew-graph-subscriptions/index.ts:16` | A01, A05 | Tampering, DoS, Elevation |
| H6 | High | Confirmed | Microsoft Graph webhook does not verify `clientState` | `supabase/functions/graph-webhook/index.ts:45` | A01, A05 | Spoofing, Tampering, DoS |
| H7 | High | Confirmed | `estimate-time` trusts body-supplied workspace/profile/task IDs | `supabase/functions/estimate-time/index.ts:42` | A01 | Tampering, Information Disclosure |
| H8 | High | Confirmed | `generate-profile-card` trusts body-supplied workspace/profile IDs | `supabase/functions/generate-profile-card/index.ts:36` | A01, A04 | Information Disclosure, Tampering |
| H9 | High | Confirmed | `detect-reply` trusts body tenant IDs and builds an unsafe PostgREST `.or()` filter | `supabase/functions/detect-reply/index.ts:21` | A01, A03 | Tampering, Information Disclosure |
| H10 | High | Confirmed | `parse-voice-capture` trusts body tenant/capture IDs | `supabase/functions/parse-voice-capture/index.ts:26` | A01 | Tampering, Elevation |
| H11 | High | Confirmed | `classify-email` validates tenant IDs, then fetches and updates email rows by ID only | `supabase/functions/classify-email/index.ts:83` | A01 | Information Disclosure, Tampering |
| H12 | High | Needs verification | Graphiti core service exposes unauthenticated write/search endpoints if the Fly app is public | `services/graphiti/app/main.py:220` | A01, A05 | Tampering, Information Disclosure |
| M1 | Medium | Needs verification | Local-only Deepgram transcription proxy is deployable as a public-anon cost/SSRF surface | `supabase/functions/deepgram-transcribe/index.ts:13` | A01, A05, A10 | DoS, Information Disclosure |
| M2 | Medium | Confirmed | Supabase auth session JSON is stored on disk instead of Keychain | `Sources/TimedKit/Core/Clients/FileAuthLocalStorage.swift:6` | A02 | Information Disclosure |
| M3 | Medium | Needs verification | `verifyServiceRole` only decodes the role claim and relies on platform JWT verification | `supabase/functions/_shared/auth.ts:77` | A01, A07 | Spoofing, Elevation |
| M4 | Medium | Confirmed | Diagnostic logs in `/tmp` can include mailbox/API response data | `Sources/TimedKit/Core/Clients/GraphClient.swift:220` | A09 | Information Disclosure |
| M5 | Medium | Confirmed | Several model prompts still interpolate untrusted observations without fencing | `supabase/functions/score-observation-realtime/index.ts:99` | A04, A08 | Tampering |
| M6 | Medium | Confirmed | Missing per-user rate limits on paid provider endpoints and token issuers | `supabase/functions/deepgram-token/index.ts:23` | A04, A05 | DoS |
| L1 | Low | Confirmed | macOS package script signs ad-hoc without hardened runtime/notarization in the packaging path | `scripts/package_app.sh:150` | A05 | Tampering |
| L2 | Low | Confirmed | macOS target is unsandboxed for DMG distribution | `Platforms/Mac/Timed.entitlements:5` | A05 | Elevation |
| L3 | Low | Confirmed | Security CI is advisory and pipes installer scripts from the network | `.github/workflows/security.yml:18` | A05, A08 | Tampering |

## Findings

### C1 - Local compose file contains live-looking secrets

- Evidence: `.gitignore:19` says the local Docker stack contains real secrets and ignores `docker-compose.local.yml`; the ignored local file is present with `GRAPHITI_MCP_TOKEN` at `docker-compose.local.yml:12`, `NEO4J_PASSWORD` at `docker-compose.local.yml:15`, Supabase `SUPABASE_SERVICE_ROLE_KEY` at `docker-compose.local.yml:18` and `docker-compose.local.yml:33`, `VOYAGE_API_KEY` at `docker-compose.local.yml:34`, and `INFERENCE_PROXY_API_KEY` at `docker-compose.local.yml:54`.
- Exploit scenario: malware, a support bundle, a copied workspace, or accidental `git add -f` exposes service-role Supabase access, Graphiti/Neo4j access, Voyage, and Anthropic credentials.
- Impact: full Supabase RLS bypass, vendor cost abuse, knowledge graph tampering, and credential reuse against deployed infrastructure if any values are live.
- Remediation: rotate every value in the file, remove live values from the workspace, replace the file with a template-driven local secret loader, and add a pre-commit secret scanner that blocks forced-adds of ignored secret files.

### C2 - Tracked handoff leaks infrastructure secrets

- Evidence: `HANDOFF.md:181` introduces "Recovered secrets"; `HANDOFF.md:183` includes a full Graphiti MCP token and another token prefix; `HANDOFF.md:184` includes Fedora and cloud Neo4j passwords.
- Exploit scenario: anyone with repo access or a fork/CI artifact can authenticate to MCP/Neo4j infrastructure if those values remain valid.
- Impact: graph memory exfiltration/tampering and follow-on compromise of Trigger/Fly workflows that trust those services.
- Remediation: rotate the leaked tokens/passwords, remove the values from tracked docs, and rewrite/purge Git history if this branch was pushed to any remote or shared with other agents.

### C3 - Legacy Anthropic proxy is an open paid-model proxy

- Evidence: the file documents caller auth as a Supabase anon JWT at `supabase/functions/anthropic-proxy/index.ts:7`; it accepts arbitrary Anthropic bodies at `supabase/functions/anthropic-proxy/index.ts:8`; it reads the server API key at `supabase/functions/anthropic-proxy/index.ts:21`; it forwards the caller body unchanged at `supabase/functions/anthropic-proxy/index.ts:29` and `supabase/functions/anthropic-proxy/index.ts:31`.
- Exploit scenario: an attacker extracts the public anon key from the client or repo and POSTs arbitrary Messages API payloads, including expensive models, high token counts, tools, and streams.
- Impact: unbounded Anthropic spend, provider abuse attributed to Timed, and possible data exfiltration through a trusted backend egress path.
- Remediation: undeploy this legacy function or replace it with the hardened `anthropic-relay` pattern: require `verifyAuth`, resolve the executive, enforce an allowlist, cap body/tokens/tools, and rate-limit per user.

### H1 - Telegram control bot token is tracked

- Evidence: `scripts/ralph-telegram.ts:23` hardcodes the bot token; `scripts/ralph-telegram.ts:24` embeds it in the Telegram Bot API URL; `.codex/ralph/.telegram-chat-id:1` tracks the admin chat ID; `scripts/ralph-telegram.ts:126` registers the admin on `/start`; `scripts/ralph-telegram.ts:201`, `scripts/ralph-telegram.ts:226`, and `scripts/ralph-telegram.ts:236` mutate Ralph state/stop flags.
- Exploit scenario: an attacker with the token can call Telegram Bot API methods, observe/control bot traffic, or race registration if the chat ID file is absent in another checkout.
- Impact: unauthorized PRD/story mutation, stop/resume of local automation, and leakage of run logs/story titles.
- Remediation: revoke the bot token, remove it from Git, read it from an environment variable or local keychain, and keep chat IDs out of tracked files.

### H2 - Legacy ElevenLabs proxy is public-anon and unbounded

- Evidence: `supabase/functions/elevenlabs-tts-proxy/index.ts:7` documents anon JWT caller auth; `supabase/functions/elevenlabs-tts-proxy/index.ts:20` loads the server ElevenLabs key; `supabase/functions/elevenlabs-tts-proxy/index.ts:30` accepts caller JSON; `supabase/functions/elevenlabs-tts-proxy/index.ts:37` and `supabase/functions/elevenlabs-tts-proxy/index.ts:38` trust caller `voice_id` and `model_id`; `supabase/functions/elevenlabs-tts-proxy/index.ts:61` echoes upstream error detail.
- Exploit scenario: anyone with the public anon key can synthesize arbitrary text with arbitrary voices/models and consume the ElevenLabs account quota.
- Impact: provider cost abuse and possible leakage of upstream diagnostic detail.
- Remediation: undeploy this legacy function or fold it into `orb-tts`, which already requires user auth and enforces text, voice, and model limits.

### H3 - Batch polling function lacks service-role authorization

- Evidence: `supabase/functions/poll-batch-results/index.ts:14` starts the handler with no `verifyServiceRole`; `supabase/functions/poll-batch-results/index.ts:19` creates a service-role client; `supabase/functions/poll-batch-results/index.ts:25` reads pending logs globally; `supabase/functions/poll-batch-results/index.ts:61` fetches batch result URLs; `supabase/functions/poll-batch-results/index.ts:111` upserts behavioral signatures; `supabase/functions/poll-batch-results/index.ts:154` writes health logs.
- Exploit scenario: any request that reaches the function can force global batch polling and cause service-role writes based on pending Anthropic batch output.
- Impact: behavioral-signature poisoning, pipeline churn, Anthropic/result URL access, and health-log noise.
- Remediation: import `_shared/auth.ts`, require `verifyServiceRole(req)` before any work, and reject anon/authenticated user JWTs.

### H4 - Pipeline health endpoint has no auth gate

- Evidence: `supabase/functions/pipeline-health-check/index.ts:369` handles requests with no auth; `supabase/functions/pipeline-health-check/index.ts:380` runs global checks; `supabase/functions/pipeline-health-check/index.ts:388` inserts rows via admin client; `supabase/functions/pipeline-health-check/index.ts:396` sends webhook alerts; `supabase/functions/pipeline-health-check/index.ts:399` returns the results.
- Exploit scenario: a remote caller repeatedly triggers global health checks and webhook alerts.
- Impact: internal pipeline status disclosure, alert spam, noisy health data, and backend load.
- Remediation: require `verifyServiceRole(req)`, return only generic status to non-cron callers, and add rate limiting around alert dispatch.

### H5 - Graph renewal function lacks service-role authorization

- Evidence: `supabase/functions/renew-graph-subscriptions/index.ts:16` ignores the request and has no auth gate; `supabase/functions/renew-graph-subscriptions/index.ts:22` reads all active account subscriptions; `supabase/functions/renew-graph-subscriptions/index.ts:24` selects OAuth access tokens; `supabase/functions/renew-graph-subscriptions/index.ts:61` sends them to Graph; `supabase/functions/renew-graph-subscriptions/index.ts:83` can mark accounts as needing reauth.
- Exploit scenario: an attacker invokes renewals repeatedly, burning Microsoft Graph quota and possibly causing accounts to be marked for reauth on upstream failures.
- Impact: sync disruption, token-bearing code path exposure, noisy logs, and tenant count inference from the JSON summary at `supabase/functions/renew-graph-subscriptions/index.ts:110`.
- Remediation: require `verifyServiceRole(req)` and migrate to the newer `graph_subscriptions`/Trigger.dev renewal path or decrypt stored tokens only inside an explicitly authorized server job.

### H6 - Graph webhook does not validate `clientState`

- Evidence: `supabase/functions/graph-webhook/index.ts:45` says it validates `clientState`, but `supabase/functions/graph-webhook/index.ts:46` only checks presence; `supabase/functions/graph-webhook/index.ts:48` looks up the subscription ID only; `supabase/functions/graph-webhook/index.ts:60` inserts webhook events; `supabase/functions/graph-webhook/index.ts:77` queues processing. The client creates a random `clientState` at `Sources/TimedKit/Core/Clients/GraphClient.swift:446`, and the newer schema has a storage column at `supabase/migrations/20260427000100_email_sync_state.sql:50`.
- Exploit scenario: a forged notification with a known subscription ID, or a notification omitting `clientState`, is accepted and queued as a real mail event.
- Impact: forged email-pipeline events, queue spam, and possible downstream message fetch attempts under privileged workers.
- Remediation: persist `clientState` with the subscription and compare it in constant time for every notification; reject missing/mismatched values before inserting or queueing.

### H7 - `estimate-time` trusts tenant and task IDs from the body

- Evidence: `supabase/functions/estimate-time/index.ts:42` verifies auth but does not bind the user to an executive; `supabase/functions/estimate-time/index.ts:51` accepts `taskId`, `workspaceId`, and `profileId`; `supabase/functions/estimate-time/index.ts:64` reads bucket estimates by body profile; `supabase/functions/estimate-time/index.ts:234` calls a similarity RPC with body workspace/profile; `supabase/functions/estimate-time/index.ts:266` reads estimation history by body IDs; `supabase/functions/estimate-time/index.ts:357` and `supabase/functions/estimate-time/index.ts:373` update `tasks` by task ID only.
- Exploit scenario: a signed-in user supplies another executive's workspace/profile/task UUIDs and gets estimates derived from that history or writes an AI estimate onto that task.
- Impact: cross-tenant behavioral data leakage and task-estimate poisoning.
- Remediation: resolve `authUserId -> executives.id`, require `workspaceId == profileId == executiveId`, and update/read task rows with both `id` and `workspace_id`.

### H8 - `generate-profile-card` trusts tenant IDs from the body

- Evidence: `supabase/functions/generate-profile-card/index.ts:36` verifies auth only; `supabase/functions/generate-profile-card/index.ts:45` accepts body workspace/profile IDs; `supabase/functions/generate-profile-card/index.ts:60` reads behavior events/history/rules for those IDs; `supabase/functions/generate-profile-card/index.ts:90` serializes the data to the LLM; `supabase/functions/generate-profile-card/index.ts:164` upserts `user_profiles`; `supabase/functions/generate-profile-card/index.ts:187` updates/inserts rules for body IDs.
- Exploit scenario: a signed-in user calls the function with another profile ID and causes that user's behavioral data to be summarized or overwritten.
- Impact: sensitive behavior-history disclosure to the model path and profile/rule poisoning.
- Remediation: resolve the authenticated executive and reject any body IDs that do not match it before service-role reads or writes.

### H9 - `detect-reply` trusts tenant IDs and builds an unsafe `.or()` filter

- Evidence: `supabase/functions/detect-reply/index.ts:21` verifies auth only; `supabase/functions/detect-reply/index.ts:27` accepts body `workspaceId` and `waitingItemId`; `supabase/functions/detect-reply/index.ts:37` fetches a waiting item by supplied IDs; `supabase/functions/detect-reply/index.ts:60` searches email messages under supplied workspace; `supabase/functions/detect-reply/index.ts:72` interpolates `subjectKeywords` into a PostgREST `.or()` clause; `supabase/functions/detect-reply/index.ts:95` updates the waiting item by ID.
- Exploit scenario: a signed-in user with a victim UUID marks a waiting item as replied, or supplies crafted subject keywords to broaden the filter.
- Impact: cross-tenant waiting-item tampering and email metadata inference.
- Remediation: bind workspace/profile from auth, escape or avoid dynamic `.or()` filters, cap keyword count/length, and update by both `id` and owned workspace.

### H10 - `parse-voice-capture` trusts tenant and capture IDs

- Evidence: `supabase/functions/parse-voice-capture/index.ts:26` verifies auth only; `supabase/functions/parse-voice-capture/index.ts:34` accepts `voiceCaptureId`, `workspaceId`, and `profileId`; `supabase/functions/parse-voice-capture/index.ts:73` inserts items for the body capture/workspace; `supabase/functions/parse-voice-capture/index.ts:92` updates `voice_captures` by ID only; `supabase/functions/parse-voice-capture/index.ts:103` writes pipeline logs with body IDs.
- Exploit scenario: a signed-in user submits a transcript against another capture UUID and injects tasks or flips parse status.
- Impact: cross-tenant capture tampering and contaminated task extraction.
- Remediation: resolve the authenticated executive, fetch the capture under that workspace, and only then insert/update.

### H11 - `classify-email` leaves an ID-only row access gap

- Evidence: `supabase/functions/classify-email/index.ts:37` resolves the executive and `supabase/functions/classify-email/index.ts:57` rejects mismatched body tenant IDs, but `supabase/functions/classify-email/index.ts:83` fetches the email by `id` only, `supabase/functions/classify-email/index.ts:112` writes the embedding by `id` only, and `supabase/functions/classify-email/index.ts:280` updates classification by `id` only.
- Exploit scenario: a signed-in user passes their own workspace/profile IDs plus a known victim `emailMessageId`; the service-role client fetches and classifies the victim row.
- Impact: victim email metadata/snippet enters the LLM path and the victim email can be reclassified/modified.
- Remediation: add `.eq("workspace_id", workspaceId)` and `.eq("profile_id", profileId)` or equivalent ownership checks to every email read/update.

### H12 - Graphiti core can be public and unauthenticated

- Evidence: `services/graphiti/app/main.py:185` creates a FastAPI app; `services/graphiti/app/main.py:220` exposes POST `/episode`; `services/graphiti/app/main.py:244` exposes POST `/search`; neither route has auth. `services/graphiti/fly.toml:28` configures an HTTP service with HTTPS, while the MCP config expects internal access at `services/graphiti-mcp/fly.toml:11`.
- Exploit scenario: if `timed-graphiti` has a public Fly hostname, anyone can add episodes to the graph or search graph facts.
- Impact: knowledge-graph poisoning, graph data disclosure, and LLM/embedder/Neo4j cost abuse.
- Remediation: make the Graphiti core service private-only, or add the same bearer-auth middleware used by `graphiti-mcp`; keep `/healthz` public only if needed.

### M1 - Deepgram transcription proxy is local-only but deployable as public-anon

- Evidence: `supabase/functions/deepgram-transcribe/index.ts:4` says unused; `supabase/functions/deepgram-transcribe/index.ts:13` documents anon JWT caller auth; `supabase/functions/deepgram-transcribe/index.ts:60` lets callers submit arbitrary `audio_url`; `supabase/functions/deepgram-transcribe/index.ts:71` base64-decodes arbitrary audio into memory.
- Exploit scenario: if deployed, an attacker with the anon key can force Deepgram to fetch attacker-chosen URLs or process large base64 payloads.
- Impact: transcription cost abuse, memory pressure, and a limited SSRF-like provider fetch path.
- Remediation: keep undeployed, or add `verifyAuth`, size limits, allowed URL schemes/hosts, and per-user quotas before deployment.

### M2 - Supabase sessions are stored in plaintext files

- Evidence: `Sources/TimedKit/Core/Clients/FileAuthLocalStorage.swift:6` states session JSON sits on disk readable by same-UID processes; `Sources/TimedKit/Core/Clients/FileAuthLocalStorage.swift:27` writes the value directly; `Sources/TimedKit/Core/Clients/SupabaseClient.swift:588` configures this storage for the live client.
- Exploit scenario: local malware or another same-user process reads the auth storage folder and reuses refresh/access tokens.
- Impact: account takeover until token revocation/expiry and possible data access through normal user JWT permissions.
- Remediation: move Supabase auth storage back to Keychain once signing is fixed, or encrypt file storage with a Keychain-held key in the interim.

### M3 - `verifyServiceRole` relies on Supabase platform JWT verification

- Evidence: `supabase/functions/_shared/auth.ts:77` documents reliance on platform-level JWT verification; `supabase/functions/_shared/auth.ts:94` splits the JWT; `supabase/functions/_shared/auth.ts:104` decodes payload with `atob`; `supabase/functions/_shared/auth.ts:109` accepts role `service_role`. Deploy scripts do not pass `--no-verify-jwt` at `scripts/deploy_security_hardening.sh:48` and `scripts/deploy_multiuser_functions.sh:27`.
- Exploit scenario: if any protected function is deployed with JWT verification disabled, a forged JWT payload with `role=service_role` would pass the in-function check.
- Impact: full access to cron/system functions that trust the service-role gate.
- Remediation: verify remote function JWT settings, make deployment fail if `verify_jwt=false`, or cryptographically verify the JWT/signature in `verifyServiceRole`.

### M4 - `/tmp` diagnostic logs expose mailbox/API details

- Evidence: `Sources/TimedKit/Core/Clients/GraphClient.swift:220` writes MSAL/Graph logs to `/tmp/timed-msal.log`; `Sources/TimedKit/Core/Clients/GraphClient.swift:243` enables verbose MSAL logging; `Sources/TimedKit/Core/Clients/GraphClient.swift:388` logs the first 400 bytes of Graph responses; `Sources/TimedKit/Core/Clients/GoogleClient.swift:62` writes Google logs to `/tmp/timed-google.log`; `Sources/TimedKit/Core/Services/AuthService.swift:78` and `Sources/TimedKit/Core/Services/GmailSyncService.swift:208` log email addresses/history IDs.
- Exploit scenario: another local user/process or crash collection tool reads `/tmp/timed-*.log`.
- Impact: mailbox metadata, email addresses, error bodies, history IDs, and possibly provider diagnostic details leak outside the app sandbox.
- Remediation: use `os.Logger` with private redaction or write logs under app support with `0600` permissions, rotate them, and remove response-body previews.

### M5 - Prompt-injection fencing is incomplete

- Evidence: `supabase/functions/score-observation-realtime/index.ts:99` builds prompt input from observation summary/raw data; `supabase/functions/generate-profile-card/index.ts:90` embeds behavior/history JSON directly; `supabase/functions/generate-relationship-card/index.ts:51` has ownership checks but later uses contact/email summaries as model input; `_shared/cors.ts:15` notes legacy inline blocks exist, and the fencing helper audit comment elsewhere indicates not all synthesis paths migrated.
- Exploit scenario: a malicious email/calendar/task value tells the model to ignore instructions or output poisoned scores/rules.
- Impact: incorrect recommendations, profile/rule poisoning, and degraded trust in the intelligence engine. Timed currently observes/recommends rather than acts, so the blast radius is data integrity rather than direct action.
- Remediation: wrap all user/email/calendar/observation/task content in explicit untrusted fences and add output validation/invariant checks before writes.

### M6 - Paid-provider endpoints lack per-user rate limits

- Evidence: `supabase/functions/deepgram-token/index.ts:23` issues temporary Deepgram keys to any authenticated user; `supabase/functions/anthropic-relay/index.ts:88` authenticates and caps body shape but does not enforce per-user quota; `supabase/functions/orb-tts/index.ts:35` authenticates and caps text but does not rate-limit; legacy proxies in C3/H2 have no user binding at all.
- Exploit scenario: a legitimate but abusive account repeatedly calls provider endpoints and consumes quota.
- Impact: provider spend, throttling for real users, and noisy usage metrics.
- Remediation: add per-user rate limits/quotas in Supabase or a lightweight edge store, with stricter budgets for TTS/STT and relay endpoints.

### L1 - Packaging path signs ad-hoc without hardened runtime

- Evidence: `scripts/package_app.sh:150` signs with `--sign -`; no `--options runtime` appears in the packaging command; `scripts/notarize_app.sh:32` has a separate notarization script but `package_app.sh` does not produce a notarized/hardened artifact.
- Exploit scenario: a distributed build is easier to tamper with and harder for Gatekeeper/notarization to validate.
- Impact: reduced supply-chain assurance for external users.
- Remediation: use Developer ID signing, `--options runtime`, notarization, and stapling in the release packaging path.

### L2 - macOS target is unsandboxed

- Evidence: `Platforms/Mac/Timed.entitlements:5` documents the DMG path; `Platforms/Mac/Timed.entitlements:7` states "No sandbox"; no `com.apple.security.app-sandbox` entitlement is present.
- Exploit scenario: if the app is compromised through a dependency or parsing bug, it runs with broad user-level filesystem/network access.
- Impact: larger local post-compromise blast radius.
- Remediation: keep unsandboxed only for dev/internal builds; create a sandboxed distribution target or document the accepted risk for DMG distribution.

### L3 - Security CI is advisory and includes network-script installers

- Evidence: `.github/workflows/security.yml:18` says report-only mode; `.github/workflows/security.yml:33`, `.github/workflows/security.yml:46`, `.github/workflows/security.yml:58`, `.github/workflows/security.yml:82`, and `.github/workflows/security.yml:102` continue on error; `.github/workflows/security.yml:80` pipes a downloaded actionlint installer to bash; `.github/workflows/macos-ci.yml:27` pipes the Deno installer to shell.
- Exploit scenario: security regressions do not block merges, and installer script compromise could affect CI jobs.
- Impact: slower detection/enforcement and CI supply-chain risk.
- Remediation: phase scanners to blocking, prefer pinned binary/action releases with checksum verification, and avoid `curl | sh`.

## False-positive notes

- Supabase anon keys in the client are expected public credentials, not secrets: see `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:18` to `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:22` and `Sources/TimedKit/Core/Clients/SupabaseClient.swift:570` to `Sources/TimedKit/Core/Clients/SupabaseClient.swift:585`. The risk is only when RLS/functions treat anon as privileged.
- The modern OAuth callback path is reasonably constrained: `Sources/TimedKit/Core/Services/AuthService.swift:95` to `Sources/TimedKit/Core/Services/AuthService.swift:114` uses `ASWebAuthenticationSession`, `Sources/TimedKit/Core/Services/AuthService.swift:155` to `Sources/TimedKit/Core/Services/AuthService.swift:162` uses the `timed` callback scheme with an ephemeral browser session, and `Sources/TimedKit/AppEntry/TimedAppShell.swift:54` to `Sources/TimedKit/AppEntry/TimedAppShell.swift:63` drops unrelated URL schemes/hosts.
- Newer paid-provider relays are materially safer than the legacy proxies: `supabase/functions/anthropic-relay/index.ts:88` to `supabase/functions/anthropic-relay/index.ts:103` verifies auth and enforces model/body limits; `supabase/functions/orb-tts/index.ts:35` to `supabase/functions/orb-tts/index.ts:58` verifies auth and enforces text/voice/model constraints; `supabase/functions/deepgram-token/index.ts:27` to `supabase/functions/deepgram-token/index.ts:47` issues short-lived scoped keys.
- Recent RLS hardening is directionally sound: `supabase/migrations/20260425230000_production_security_hardening.sql:19` to `supabase/migrations/20260425230000_production_security_hardening.sql:49` forces RLS on behavior events and service-only inserts; `supabase/migrations/20260425230000_production_security_hardening.sql:71` to `supabase/migrations/20260425230000_production_security_hardening.sql:87` hardens SECURITY DEFINER function privileges; `supabase/migrations/20260425230000_production_security_hardening.sql:114` to `supabase/migrations/20260425230000_production_security_hardening.sql:120` removes broad pipeline health reads.
- `connected_accounts`, `graph_subscriptions`, `email_sync_state`, `backfill_watermark`, and `skills` are service-role-only or owner-scoped in the reviewed migrations: examples include `supabase/migrations/20260430120000_gmail_provider.sql:47` to `supabase/migrations/20260430120000_gmail_provider.sql:63`, `supabase/migrations/20260427000100_email_sync_state.sql:61` to `supabase/migrations/20260427000100_email_sync_state.sql:70`, and `supabase/migrations/20260426000000_skill_library.sql:173` to `supabase/migrations/20260426000000_skill_library.sql:179`.
- The two MCP services use bearer-token checks with `timingSafeEqual`: `services/graphiti-mcp/src/server.ts:39` to `services/graphiti-mcp/src/server.ts:52` and `services/skill-library-mcp/src/server.ts:29` to `services/skill-library-mcp/src/server.ts:42`. This is acceptable if tokens are rotated after the leaks above.
- CORS is intentionally locked down for native-client usage: `_shared/cors.ts:20` to `_shared/cors.ts:25` defaults `Access-Control-Allow-Origin` to `null`.

## Verification commands after fixes

Not run in this review per review-only constraints.

- Secret rotation and history checks:
  - `gitleaks detect --source . --redact --no-banner`
  - `git log --all -S 'GRAPHITI_MCP_TOKEN' -- HANDOFF.md docker-compose.local.yml scripts/ralph-telegram.ts`
  - `git log --all -S '8644245004' -- scripts/ralph-telegram.ts`
- Supabase function deployment and auth checks:
  - `supabase functions deploy anthropic-proxy elevenlabs-tts-proxy poll-batch-results pipeline-health-check renew-graph-subscriptions graph-webhook estimate-time generate-profile-card detect-reply parse-voice-capture classify-email --project-ref fpmjuufefhtlwbfinxlx`
  - `supabase functions list --project-ref fpmjuufefhtlwbfinxlx`
  - `curl -i -X POST https://fpmjuufefhtlwbfinxlx.supabase.co/functions/v1/poll-batch-results -H 'Content-Type: application/json' -d '{}'` should return 401.
  - `curl -i -X POST https://fpmjuufefhtlwbfinxlx.supabase.co/functions/v1/poll-batch-results -H "Authorization: Bearer $SUPABASE_ANON_KEY" -H 'Content-Type: application/json' -d '{}'` should return 403.
- Database/RLS verification:
  - `supabase db push --linked`
  - Query `pg_policies` for affected tables and verify tenant predicates are present.
  - Query `pg_proc` for `prosecdef` functions and verify `search_path` and `EXECUTE` grants.
- Swift/macOS verification:
  - `swift build`
  - `swift test`
  - `bash scripts/package_app.sh`
  - `codesign -dvvv --entitlements :- dist.noindex/Timed.app`
  - `spctl --assess --type execute --verbose dist.noindex/Timed.app`
- Service exposure checks:
  - `fly status -a timed-graphiti`
  - `curl -i https://timed-graphiti.fly.dev/search -H 'Content-Type: application/json' -d '{"query":"test"}'` should return 401/403 or be unreachable from the public internet.
