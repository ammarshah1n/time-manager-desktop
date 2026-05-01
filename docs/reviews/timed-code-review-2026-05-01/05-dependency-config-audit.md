| ID | Severity | Status | Finding | Primary evidence | Impact | Remediation |
|---|---|---|---|---|---|---|
| F-01 | critical | confirmed | Local ignored Docker compose file contains live-looking service/provider secrets. | `docker-compose.local.yml:12`, `docker-compose.local.yml:15`, `docker-compose.local.yml:18`, `docker-compose.local.yml:31`, `docker-compose.local.yml:33`, `docker-compose.local.yml:34`, `docker-compose.local.yml:54`; `.gitignore:19` | If copied, backed up, pasted into logs, or accidentally committed, the Supabase service-role token bypasses RLS and provider keys can be abused for cost or data access. | Rotate the Supabase service-role key, Anthropic key, Voyage key, MCP bearer tokens, and Neo4j password. Replace literal values with env interpolation and keep the real values only in ignored local env or a secret manager. |
| F-02 | high | confirmed | Graphiti core is published as a public Fly HTTP service while its write/search endpoints have no auth. | `services/graphiti/fly.toml:28`, `services/graphiti/app/main.py:185`, `services/graphiti/app/main.py:220`, `services/graphiti/app/main.py:244` | Anyone who can reach the Fly app can add graph episodes or query graph facts. | Remove the public `[http_service]` and expose Graphiti only over private networking, or add bearer auth to all non-health endpoints. |
| F-03 | high | confirmed | Provider-cost Edge Functions are callable with the embedded anon JWT and lack user/model/body/rate guardrails. | `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:18`, `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:31`, `supabase/functions/anthropic-proxy/index.ts:7`, `supabase/functions/anthropic-proxy/index.ts:29`, `supabase/functions/elevenlabs-tts-proxy/index.ts:7`, `supabase/functions/deepgram-transcribe/index.ts:13`, `supabase/functions/anthropic-relay/index.ts:28` | A shipped public anon key can be used as a general provider-cost proxy, especially for arbitrary Anthropic Messages payloads. | Move Swift callers to `anthropic-relay` or add `verifyAuth`, ownership checks, model/body allowlists, size caps, and per-user rate limits to the legacy proxy functions. |
| F-04 | high | confirmed | Microsoft Graph webhook does not compare `clientState`; it only checks subscription existence and skips validation when `clientState` is absent. | `Sources/TimedKit/Core/Clients/GraphClient.swift:441`, `Sources/TimedKit/Core/Clients/GraphClient.swift:446`, `supabase/functions/graph-webhook/index.ts:44`, `supabase/functions/graph-webhook/index.ts:47`, `supabase/functions/graph-webhook/index.ts:59`, `supabase/migrations/20260427000100_email_sync_state.sql:44` | Forged or replayed Graph notifications can enqueue pipeline work under the service role. | Persist `clientState` at subscription creation and require an exact timing-safe match against stored `client_state` before enqueueing work. Reject missing or mismatched values. |
| F-05 | high | needs verification | Legacy service-role Edge Functions lack explicit service-role auth checks and are not in the hardening deploy list. | `supabase/functions/poll-batch-results/index.ts:10`, `supabase/functions/poll-batch-results/index.ts:14`, `supabase/functions/renew-graph-subscriptions/index.ts:11`, `supabase/functions/renew-graph-subscriptions/index.ts:16`, `scripts/deploy_security_hardening.sh:24` | If deployed with normal anon-JWT gateway verification, any app holder can trigger service-role database writes or Graph subscription renewal attempts. | Add `verifyServiceRole(req)` or equivalent shared service-role gating, then deploy or retire the functions. Confirm remote deployment/JWT settings before relying on local code state. |
| F-06 | medium | confirmed | Public Node service containers still use Node 20, which reached end-of-life on 2026-04-30. | `services/graphiti-mcp/Dockerfile:6`, `services/graphiti-mcp/Dockerfile:23`, `services/skill-library-mcp/Dockerfile:3`, `services/skill-library-mcp/Dockerfile:17` | Public Fly services will stop receiving Node 20 security fixes after the current date. | Move Docker base images and `engines.node` to Node 22 LTS or Node 24 LTS, regenerate locks as needed, and redeploy after typechecks. |
| F-07 | medium | confirmed | Graphiti Python service pins FastAPI 0.115.0, which constrains Starlette to an affected range for CVE-2025-54121; there is no Python lockfile. | `services/graphiti/requirements.txt:3`, `services/graphiti/Dockerfile:36`, `services/graphiti/Dockerfile:37` | The public Python service can install a Starlette version affected by a network DoS advisory. The current app code does not expose file-upload routes, so exploitability should be verified against runtime middleware and generated endpoints. | Upgrade FastAPI to a version allowing Starlette >=0.47.2, add a constraints/lock file, and include the Python service in dependency scanning. |
| F-08 | medium | confirmed | Supabase Edge Function imports are not lockfile/import-map controlled; CI explicitly runs Deno with `--no-lock`. | `.github/workflows/macos-ci.yml:30`, `.github/workflows/macos-ci.yml:32`, `supabase/functions/_shared/auth.ts:6`, `supabase/functions/classify-email/index.ts:11`, `supabase/functions/estimate-time/index.ts:11`, `supabase/functions/generate-daily-plan/index.ts:10`, `supabase/functions/parse-voice-capture/index.ts:9` | Rechecks and deployments can resolve different remote module builds over time, and old Anthropic SDK imports coexist with newer TypeScript SDK surfaces. | Add `supabase/functions/deno.json` and committed `deno.lock`, pin exact remote imports, and update CI to check with the committed lock. |
| F-09 | medium | confirmed | Packaging, notarization, and CI disagree on the built app path/case. | `scripts/package_app.sh:6`, `scripts/create_dmg.sh:5`, `scripts/notarize_app.sh:5`, `scripts/notarize_app.sh:6`, `.github/workflows/macos-ci.yml:35`, `.github/workflows/macos-ci.yml:42` | CI artifact upload and notarization can fail even when packaging succeeds. | Standardize on `dist.noindex/Timed.app` or a single configurable artifact path across package, DMG, notarization, and CI upload scripts. |
| F-10 | medium | confirmed | `scripts/package_app.sh` maintains a second macOS `Info.plist` instead of reusing the XcodeGen plist. | `project.yml:55`, `Platforms/Mac/Info.plist:17`, `Platforms/Mac/Info.plist:23`, `scripts/package_app.sh:78`, `scripts/package_app.sh:99`, `scripts/package_app.sh:115` | Xcode-built and script-packaged apps can silently diverge in versioning, icons, URL schemes, privacy strings, or OAuth config. | Copy and substitute `Platforms/Mac/Info.plist` during packaging, or generate both Xcode and script plists from one source. |
| F-11 | medium | confirmed | Dependabot/workspace coverage misses service and Python dependency surfaces. | `.github/dependabot.yml:6`, `.github/dependabot.yml:16`, `.github/dependabot.yml:27`, `pnpm-workspace.yaml:1`, `services/graphiti-mcp/package.json:17`, `services/skill-library-mcp/package.json:17`, `services/graphiti/requirements.txt:1` | Public MCP services, the Graphiti Python service, and script stubs can age without automated security/update PRs. | Add Dependabot entries for `/services/graphiti-mcp`, `/services/skill-library-mcp`, `/trigger/scripts`, and `pip` under `/services/graphiti`; optionally include service packages in the pnpm workspace. |
| F-12 | low | confirmed | Trigger config and package comments still say v3/placeholder while dependencies and config use Trigger v4 and a hardcoded project ref. | `trigger/package.json:5`, `trigger/package.json:20`, `trigger/trigger.config.ts:4`, `trigger/trigger.config.ts:15`, `trigger/trigger.config.ts:16` | Deployment assumptions are easy to misread, and a missing env var can deploy to the hardcoded project. | Update the v3/placeholder comments and require explicit project refs for non-production deploys, or document the prod default as intentional. |
| F-13 | low | confirmed | `trigger/scripts` still carries a stub package and second lockfile after its README says to delete them. | `trigger/scripts/package.json:2`, `trigger/scripts/package.json:8`, `trigger/scripts/package.json:10`, `trigger/scripts/README.md:82`, `trigger/scripts/README.md:89` | Duplicate npm surfaces keep separate Zod/Supabase specs and can be missed by normal update workflows. | Delete the stub package/lock after integrating the scripts, or formally add it to dependency management if it remains active. |
| F-14 | low | needs verification | iOS APNs entitlement is still `development`. | `project.yml:84`, `project.yml:87`, `Platforms/iOS/Timed.entitlements:6`, `Platforms/iOS/Timed.entitlements:7` | TestFlight/App Store push delivery can fail unless release provisioning overrides the entitlement. | Use release-specific entitlements or confirm provisioning profiles replace `aps-environment` with `production` for distribution builds. |
| F-15 | low | confirmed | GitHub Actions posture is partly report-only, and macOS CI relies on default workflow token permissions. | `.github/workflows/macos-ci.yml:1`, `.github/workflows/macos-ci.yml:11`, `.github/workflows/security.yml:18`, `.github/workflows/security.yml:33`, `.github/workflows/security.yml:46`, `.github/workflows/security.yml:112` | Security findings may not block merges, and the build workflow may receive broader token permissions than needed depending on repo defaults. | Add top-level `permissions: contents: read` to macOS CI, then graduate security jobs from `continue-on-error`/audit mode once baselined. |

## Detailed Findings

### F-01 - Local ignored Docker compose file contains live-looking secrets

- Severity: critical
- Status: confirmed
- Files/lines: `docker-compose.local.yml:12`, `docker-compose.local.yml:15`, `docker-compose.local.yml:18`, `docker-compose.local.yml:31`, `docker-compose.local.yml:33`, `docker-compose.local.yml:34`, `docker-compose.local.yml:54`; `.gitignore:19`
- Impact: `docker-compose.local.yml` is ignored, but it exists in the working tree and contains literal values for MCP bearer tokens, a Neo4j password, Supabase service-role JWT, Voyage API key, and Anthropic proxy key. The service-role JWT bypasses RLS if leaked; provider keys create direct cost and data-exposure risk.
- Evidence: `.gitignore:19` says the local Docker stack contains real secrets. The secret-bearing lines above hold literal values, not environment interpolation.
- Remediation: rotate every value present in this file. Replace the compose values with `${VAR:?missing}` references and keep actual values in ignored local env or a secret manager. Check shell history, logs, and backup/sync locations for copies.

### F-02 - Public Graphiti core exposes unauthenticated write/search

- Severity: high
- Status: confirmed
- Files/lines: `services/graphiti/fly.toml:28`, `services/graphiti/fly.toml:29`, `services/graphiti/app/main.py:185`, `services/graphiti/app/main.py:220`, `services/graphiti/app/main.py:244`
- Impact: `fly.toml` publishes the Graphiti core service over HTTPS. The FastAPI app defines `POST /episode` and `POST /search` with no auth middleware or dependency, so a reachable app can accept writes into the temporal graph and return graph facts.
- Evidence: `services/graphiti/fly.toml:28` declares `[http_service]`; `services/graphiti/app/main.py:220` writes via `g.add_episode`; `services/graphiti/app/main.py:244` returns search results.
- Remediation: remove the public HTTP service and put Graphiti behind private networking for the MCP service, or require bearer auth on every endpoint except `/healthz`/`/readyz`.

### F-03 - Provider-cost Edge Functions are callable through the embedded anon key

- Severity: high
- Status: confirmed
- Files/lines: `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:18`, `Sources/TimedKit/Core/Clients/SupabaseEndpoints.swift:31`, `supabase/functions/anthropic-proxy/index.ts:7`, `supabase/functions/anthropic-proxy/index.ts:29`, `supabase/functions/anthropic-proxy/index.ts:31`, `supabase/functions/elevenlabs-tts-proxy/index.ts:7`, `supabase/functions/elevenlabs-tts-proxy/index.ts:40`, `supabase/functions/deepgram-transcribe/index.ts:13`, `supabase/functions/deepgram-transcribe/index.ts:57`, `supabase/functions/anthropic-relay/index.ts:28`, `supabase/functions/anthropic-relay/index.ts:89`
- Impact: the Swift client embeds a public anon JWT fallback and sends it as the function auth header. The legacy proxy functions document anon-JWT caller auth and then call Anthropic, ElevenLabs, or Deepgram without `verifyAuth`, ownership checks, request size caps, or rate limits. `anthropic-proxy` forwards the caller body unchanged to Anthropic.
- Evidence: active Swift callers reference these functions at `Sources/TimedKit/Core/Clients/CaptureAIClient.swift:103`, `Sources/TimedKit/Core/Clients/OnboardingAIClient.swift:170`, `Sources/TimedKit/Core/Clients/InterviewAIClient.swift:285`, and `Sources/TimedKit/Core/Services/SpeechService.swift:57`. `anthropic-relay` already shows the expected hardening pattern with model/body guardrails and `verifyAuth`.
- Remediation: migrate Swift callers from `anthropic-proxy` to `anthropic-relay`, or apply equivalent `verifyAuth`, executive ownership checks, body/audio/token caps, allowlists, and per-user rate limits to the legacy proxies. Retire unused provider proxies from remote deployment.

### F-04 - Graph webhook does not validate `clientState`

- Severity: high
- Status: confirmed
- Files/lines: `Sources/TimedKit/Core/Clients/GraphClient.swift:441`, `Sources/TimedKit/Core/Clients/GraphClient.swift:446`, `supabase/functions/graph-webhook/index.ts:44`, `supabase/functions/graph-webhook/index.ts:47`, `supabase/functions/graph-webhook/index.ts:59`, `supabase/functions/graph-webhook/index.ts:77`, `supabase/migrations/20260427000100_email_sync_state.sql:44`, `supabase/migrations/20260427000100_email_sync_state.sql:50`
- Impact: Microsoft Graph webhook notifications can be spoofed or replayed into the email pipeline if the endpoint is reachable. The function uses a service-role client and queues work after only checking that a subscription ID exists when `clientState` is present.
- Evidence: `GraphClient` sends a random `clientState`; the migration has a `graph_subscriptions.client_state` column; the webhook comment says to validate against a stored secret, but the code only selects `email_accounts.id` by subscription ID and does not compare the supplied `clientState`. Missing `clientState` bypasses the block entirely.
- Remediation: store `clientState` at subscription creation, require it on every notification, compare it to the stored value with timing-safe equality, and reject before insert/queue on missing or mismatch. Align the webhook lookup with the current `graph_subscriptions` table.

### F-05 - Service-role Edge Functions lack explicit service-role gates

- Severity: high
- Status: needs verification
- Files/lines: `supabase/functions/poll-batch-results/index.ts:10`, `supabase/functions/poll-batch-results/index.ts:14`, `supabase/functions/renew-graph-subscriptions/index.ts:11`, `supabase/functions/renew-graph-subscriptions/index.ts:16`, `supabase/functions/renew-graph-subscriptions/index.ts:56`, `scripts/deploy_security_hardening.sh:24`, `scripts/deploy_security_hardening.sh:43`
- Impact: these functions create service-role Supabase clients as soon as they run. `poll-batch-results` mutates self-improvement logs and signatures; `renew-graph-subscriptions` uses stored OAuth access tokens to PATCH Microsoft Graph subscriptions. If deployed with standard anon-JWT gateway verification, a client with the embedded anon key can trigger them.
- Evidence: neither function imports or calls `verifyServiceRole`; the security hardening deploy list contains 18 other functions but not these two.
- Remediation: confirm remote deployment and JWT settings, then add explicit `verifyServiceRole(req)` gates or delete/disable the legacy functions. Add them to the hardening deployment script if retained.

### F-06 - Node 20 runtime is EOL

- Severity: medium
- Status: confirmed
- Files/lines: `services/graphiti-mcp/Dockerfile:6`, `services/graphiti-mcp/Dockerfile:23`, `services/skill-library-mcp/Dockerfile:3`, `services/skill-library-mcp/Dockerfile:17`, `services/graphiti-mcp/package.json:14`, `services/skill-library-mcp/package.json:14`
- Impact: both public MCP services build and run on `node:20-bookworm-slim`. Node's official release schedule lists Node 20 end-of-life as 2026-04-30, which is before the review date.
- Evidence: Node.js Release Working Group schedule, checked 2026-05-01: https://github.com/nodejs/Release
- Remediation: move Dockerfiles and package `engines.node` to Node 22 LTS or Node 24 LTS, run service typechecks, rebuild images, and redeploy.

### F-07 - Python Graphiti service can resolve vulnerable Starlette

- Severity: medium
- Status: confirmed
- Files/lines: `services/graphiti/requirements.txt:3`, `services/graphiti/requirements.txt:4`, `services/graphiti/Dockerfile:36`, `services/graphiti/Dockerfile:37`
- Impact: `fastapi==0.115.0` requires `starlette>=0.37.2,<0.39.0`. GitHub Advisory GHSA-2c2j-9gv5-cj73 / CVE-2025-54121 affects Starlette `<0.47.2`, so any Starlette satisfying this FastAPI pin is in the affected range. The exploit path is a multipart form parsing DoS; current audited routes are JSON-only, so practical exposure needs runtime verification.
- Evidence: PyPI FastAPI 0.115.0 metadata, checked 2026-05-01: https://pypi.org/pypi/fastapi/0.115.0/json. GitHub Advisory, checked 2026-05-01: https://github.com/advisories/GHSA-2c2j-9gv5-cj73. Current FastAPI latest metadata observed as 0.136.1, checked 2026-05-01: https://pypi.org/pypi/fastapi/json.
- Remediation: upgrade FastAPI to a release that allows Starlette >=0.47.2, add a lock/constraints file, and add a Python dependency-scanning entry.

### F-08 - Deno Edge Function imports are not reproducible

- Severity: medium
- Status: confirmed
- Files/lines: `.github/workflows/macos-ci.yml:30`, `.github/workflows/macos-ci.yml:32`, `supabase/functions/_shared/auth.ts:6`, `supabase/functions/classify-email/index.ts:11`, `supabase/functions/estimate-time/index.ts:11`, `supabase/functions/generate-daily-plan/index.ts:10`, `supabase/functions/generate-profile-card/index.ts:11`, `supabase/functions/parse-voice-capture/index.ts:9`
- Impact: CI checks Edge Functions with `deno check --no-lock`, and the functions import major-only `@supabase/supabase-js@2` plus older exact `@anthropic-ai/sdk@0.27.0` from `esm.sh`. A future deploy/check can pull different remote module builds without a reviewed lockfile.
- Evidence: no `deno.json`, `deno.lock`, or import map was present under `supabase/functions`; imports are remote URL imports in function files; CI disables locking.
- Remediation: add `supabase/functions/deno.json`, centralize imports through an import map, commit `deno.lock`, and run CI with `deno check --lock=supabase/functions/deno.lock`.

### F-09 - Packaging/notarization/CI artifact path drift

- Severity: medium
- Status: confirmed
- Files/lines: `scripts/package_app.sh:6`, `scripts/create_dmg.sh:5`, `scripts/create_dmg.sh:6`, `scripts/notarize_app.sh:5`, `scripts/notarize_app.sh:6`, `.github/workflows/macos-ci.yml:35`, `.github/workflows/macos-ci.yml:42`
- Impact: `package_app.sh` and `create_dmg.sh` use `dist.noindex/Timed.app`, while notarization expects `dist/timed.app` and CI uploads `dist/timed.app`. This blocks artifact upload and notarization even if the package script succeeds.
- Evidence: conflicting paths and case appear in the cited scripts/workflow.
- Remediation: choose one artifact path and case, preferably `dist.noindex/Timed.app` to match current package/DMG scripts, and update notarization plus CI upload.

### F-10 - Script-packaged app duplicates `Info.plist`

- Severity: medium
- Status: confirmed
- Files/lines: `project.yml:55`, `Platforms/Mac/Info.plist:17`, `Platforms/Mac/Info.plist:23`, `Platforms/Mac/Info.plist:41`, `scripts/package_app.sh:78`, `scripts/package_app.sh:99`, `scripts/package_app.sh:115`, `scripts/package_app.sh:136`
- Impact: XcodeGen builds use `Platforms/Mac/Info.plist`, but direct SwiftPM packaging writes a separate XML plist. Version numbers, icon metadata, URL schemes, OAuth settings, and privacy usage strings can drift between app distributions.
- Evidence: the canonical plist uses build settings for bundle/version values and includes `CFBundleIconName`; the package script hardcodes `0.2.0`, URL schemes, and `GIDClientID` in a heredoc.
- Remediation: reuse `Platforms/Mac/Info.plist` in the packaging script and substitute build variables, or generate both plists from a single source.

### F-11 - Dependency automation misses service surfaces

- Severity: medium
- Status: confirmed
- Files/lines: `.github/dependabot.yml:6`, `.github/dependabot.yml:16`, `.github/dependabot.yml:27`, `pnpm-workspace.yaml:1`, `pnpm-workspace.yaml:2`, `services/graphiti-mcp/package.json:17`, `services/skill-library-mcp/package.json:17`, `services/graphiti/requirements.txt:1`
- Impact: Dependabot covers Swift, `/trigger`, and GitHub Actions only. Root pnpm workspace includes only `trigger`. The MCP services, `trigger/scripts`, and the Python Graphiti service are separate dependency surfaces with tracked locks/manifests but no update coverage.
- Evidence: dependency manifests exist in `services/graphiti-mcp`, `services/skill-library-mcp`, `trigger/scripts`, and `services/graphiti`, but none are listed in Dependabot config.
- Remediation: add npm updates for each service directory and `/trigger/scripts`, add pip updates for `/services/graphiti`, and decide whether to fold service packages into `pnpm-workspace.yaml`.

### F-12 - Trigger v3/v4 and project-ref drift

- Severity: low
- Status: confirmed
- Files/lines: `trigger/package.json:5`, `trigger/package.json:20`, `trigger/package.json:25`, `trigger/trigger.config.ts:4`, `trigger/trigger.config.ts:6`, `trigger/trigger.config.ts:15`, `trigger/trigger.config.ts:16`
- Impact: comments describe Trigger.dev v3 and an env-driven placeholder, while dependencies are Trigger v4 and the config hardcodes `proj_vrakwmzenqmmhrzhfqyl` when env is absent. This can cause accidental prod deploy assumptions during local work.
- Evidence: dependency specs and config contradict the descriptive text.
- Remediation: update the comments/docs to Trigger v4 and document the hardcoded project ref as intentional, or fail fast when `TRIGGER_PROJECT_REF` is missing outside production deploys.

### F-13 - `trigger/scripts` stub package remains

- Severity: low
- Status: confirmed
- Files/lines: `trigger/scripts/package.json:2`, `trigger/scripts/package.json:8`, `trigger/scripts/package.json:10`, `trigger/scripts/package-lock.json:1`, `trigger/scripts/README.md:82`, `trigger/scripts/README.md:89`
- Impact: the stub keeps another npm lockfile and duplicate dependency specs alive. It uses Zod 3 while the main Trigger package uses Zod 4, and it is not covered by the root pnpm workspace.
- Evidence: the package comment says to delete the file after merge, and the README explicitly lists `trigger/scripts/package.json` plus `trigger/scripts/package-lock.json` for deletion.
- Remediation: delete the stub package/lock once the scripts are integrated, or make it an intentional managed workspace package.

### F-14 - iOS APNs entitlement is development

- Severity: low
- Status: needs verification
- Files/lines: `project.yml:84`, `project.yml:87`, `Platforms/iOS/Timed.entitlements:6`, `Platforms/iOS/Timed.entitlements:7`
- Impact: the iOS app target uses `Platforms/iOS/Timed.entitlements`, where `aps-environment` is `development`. Distribution push can fail if release provisioning does not override this.
- Evidence: the entitlement is statically set in the committed plist.
- Remediation: add release-specific entitlements or confirm distribution provisioning replaces the entitlement with `production`.

### F-15 - GitHub Actions least-privilege/report-only gaps

- Severity: low
- Status: confirmed
- Files/lines: `.github/workflows/macos-ci.yml:1`, `.github/workflows/macos-ci.yml:11`, `.github/workflows/security.yml:18`, `.github/workflows/security.yml:33`, `.github/workflows/security.yml:46`, `.github/workflows/security.yml:82`, `.github/workflows/security.yml:102`, `.github/workflows/security.yml:112`
- Impact: the security workflow is explicitly advisory/report-only and several jobs use `continue-on-error`; `harden-runner` is in audit mode. macOS CI does not declare top-level `permissions`, so it relies on repository defaults rather than least privilege.
- Evidence: `.github/workflows/security.yml:18` documents report-only mode; cited job lines set `continue-on-error`/audit behavior. `.github/workflows/macos-ci.yml` has jobs but no workflow-level `permissions`.
- Remediation: set `permissions: contents: read` in macOS CI and remove `continue-on-error` incrementally from baselined security jobs.

## Package And Config Inventory

### SwiftPM / XcodeGen

| Surface | Source of truth | Spec | Locked / observed version |
|---|---|---|---|
| Swift tools | `Package.swift:1` | 6.1 | 6.1 |
| Platforms | `Package.swift:6`, `project.yml:46`, `project.yml:75` | macOS 15, iOS 18 | same |
| TCA | `Package.swift:16` | from 1.15.0 | `swift-composable-architecture` 1.25.4 in `Package.resolved:167` |
| Supabase Swift | `Package.swift:18` | from 2.5.0 | 2.43.0 in `Package.resolved:113` |
| MSAL ObjC | `Package.swift:20` | from 1.4.0 | 1.9.0 in `Package.resolved:95` |
| GRDB | `Package.swift:22` | from 7.0.0 | 7.10.0 in `Package.resolved:68` |
| USearch | `Package.swift:24` | from 2.16.0 | 2.24.0 in `Package.resolved:293` |
| Swift Testing | `Package.swift:26` | from 0.12.0 | 0.99.0 in `Package.resolved:284` |
| ElevenLabs Swift SDK | `Package.swift:28` | from 2.0.0 | 2.0.16 in `Package.resolved:41` |
| Google Sign-In | `Package.swift:31` | from 9.0.0 | 9.1.0 in `Package.resolved:50` |
| Mac bundle/signing | `project.yml:53`, `project.yml:55`, `project.yml:56`, `project.yml:59` | `com.ammarshahin.timed`, `Platforms/Mac/Info.plist`, `Platforms/Mac/Timed.entitlements`, hardened runtime | packaging script duplicates plist; see F-10 |
| iOS bundle/signing | `project.yml:84`, `project.yml:86`, `project.yml:87` | `com.timed.ios`, `Platforms/iOS/Info.plist`, `Platforms/iOS/Timed.entitlements` | APNs dev entitlement; see F-14 |

Notable Swift transitive lock pins from `Package.resolved`: `client-sdk-swift` 2.6.1, `webrtc-xcframework` 125.6422.32, `swift-crypto` 4.3.0, `swift-protobuf` 1.37.0, `swift-syntax` 600.0.1, `appauth-ios` 2.0.0, `app-check` 11.2.0, `gtm-session-fetcher` 3.5.0, `GTMAppAuth` 5.0.0.

### Trigger / Node

| Surface | Source of truth | Spec | Locked / observed version |
|---|---|---|---|
| Trigger package | `trigger/package.json:2` | `@timed/trigger` | private app package |
| Node engine | `trigger/package.json:7` | `>=20` | not pinned to active LTS |
| `@anthropic-ai/claude-agent-sdk` | `trigger/package.json:16` | `^0.2.119` | 0.2.119 in `trigger/pnpm-lock.yaml:11` |
| `@anthropic-ai/sdk` | `trigger/package.json:17` | `^0.91.0` | 0.91.0 in `trigger/pnpm-lock.yaml:14` |
| `@modelcontextprotocol/sdk` | `trigger/package.json:18` | `^1.29.0` | 1.29.0 in `trigger/pnpm-lock.yaml:17` |
| `@supabase/supabase-js` | `trigger/package.json:19` | `^2.104.1` | 2.104.1 in `trigger/pnpm-lock.yaml:20` |
| `@trigger.dev/sdk` | `trigger/package.json:20` | `^4.4.4` | 4.4.4 in `trigger/pnpm-lock.yaml:23` |
| `zod` | `trigger/package.json:21` | `^4.3.6` | 4.3.6 in `trigger/pnpm-lock.yaml:26` |
| TypeScript | `trigger/package.json:26` | `^5.7.2` | 5.9.3 in `trigger/pnpm-lock.yaml:36` |
| Trigger project | `trigger/trigger.config.ts:15` | env override or hardcoded project ref | see F-12 |

### Services

| Surface | Source of truth | Spec | Locked / observed version |
|---|---|---|---|
| Graphiti Python base | `services/graphiti/Dockerfile:23` | `python:3.12-slim` | tag is floating within 3.12 slim |
| Graphiti Python deps | `services/graphiti/requirements.txt:1` | `graphiti-core==0.11.6`, `fastapi==0.115.0`, `uvicorn[standard]==0.30.6`, `pydantic==2.9.2`, `httpx==0.27.2`, `anthropic>=0.39.0` | no lockfile; see F-07 |
| Graphiti MCP Node base | `services/graphiti-mcp/Dockerfile:6`, `services/graphiti-mcp/Dockerfile:23` | `node:20-bookworm-slim` | EOL; see F-06 |
| Skill Library MCP Node base | `services/skill-library-mcp/Dockerfile:3`, `services/skill-library-mcp/Dockerfile:17` | `node:20-bookworm-slim` | EOL; see F-06 |
| MCP SDK | `services/graphiti-mcp/package.json:18`, `services/skill-library-mcp/package.json:18` | `^1.20.0` | 1.29.0 in service locks |
| Supabase JS | `services/graphiti-mcp/package.json:19`, `services/skill-library-mcp/package.json:19` | `^2.45.4` | 2.104.1 in service locks |
| Express | `services/graphiti-mcp/package.json:20`, `services/skill-library-mcp/package.json:20` | `^4.21.1` | 4.22.1 in service locks |
| Neo4j driver | `services/graphiti-mcp/package.json:21` | `^5.25.0` | 5.28.3 in `services/graphiti-mcp/pnpm-lock.yaml:20` |
| Node fetch | `services/graphiti-mcp/package.json:22`, `services/skill-library-mcp/package.json:21` | `^3.3.2` | 3.3.2 in service locks |
| Zod | `services/graphiti-mcp/package.json:23`, `services/skill-library-mcp/package.json:22` | `^3.23.8` | 3.25.76 in service locks |
| pnpm via Docker | `services/graphiti-mcp/Dockerfile:10`, `services/skill-library-mcp/Dockerfile:6` | 9.12.3 | not represented in package manager field |

### Supabase

| Surface | Source of truth | Observed |
|---|---|---|
| Project ref | `supabase/config.toml:1` | `fpmjuufefhtlwbfinxlx` |
| Local auth URL | `supabase/config.toml:28` | `http://localhost:3000` |
| Auth redirect URLs | `supabase/config.toml:29` | `timed://auth/callback` |
| Edge runtime | `supabase/config.toml:33` | enabled |
| Functions | filesystem inventory | 40 function directories plus `_shared` |
| Migrations | filesystem inventory | 64 SQL migration files |
| Deno locks/import maps | filesystem inventory | none found under `supabase/functions`; see F-08 |
| Hardened deploy script | `scripts/deploy_security_hardening.sh:24` | 18 selected functions; does not include F-05 functions |

### Lockfiles / Generated / Ignored

| Surface | Status | Evidence |
|---|---|---|
| `Package.resolved` | tracked source of Swift lock pins | `git ls-files` includes `Package.resolved` |
| `trigger/pnpm-lock.yaml` | tracked | `git ls-files` includes it |
| `services/graphiti-mcp/pnpm-lock.yaml` | tracked | `git ls-files` includes it |
| `services/skill-library-mcp/pnpm-lock.yaml` | tracked | `git ls-files` includes it |
| `trigger/scripts/package-lock.json` | tracked | `git ls-files` includes it |
| root `pnpm-lock.yaml` | ignored as stray root install | `.gitignore:22`, `.gitignore:24` |
| `Timed.xcodeproj/` | ignored generated XcodeGen output | `.gitignore:7` |
| `.build/`, `dist/`, `dist.noindex/` | ignored build artifacts | `.gitignore:2`, `.gitignore:3`, `.gitignore:4` |
| `docker-compose.local.yml` | ignored local secret file but present locally | `.gitignore:19`, `.gitignore:20`; see F-01 |

## External Sources Checked

- Node.js Release Working Group schedule, checked 2026-05-01: https://github.com/nodejs/Release
- GitHub Advisory GHSA-2c2j-9gv5-cj73 / CVE-2025-54121 for Starlette, checked 2026-05-01: https://github.com/advisories/GHSA-2c2j-9gv5-cj73
- FastAPI 0.115.0 PyPI metadata, checked 2026-05-01: https://pypi.org/pypi/fastapi/0.115.0/json
- Current FastAPI PyPI metadata, checked 2026-05-01: https://pypi.org/pypi/fastapi/json

No live web source was used for generic code-review claims; web checks were limited to runtime/package/CVE currency.

## Verification Commands Needed After Fixes

- Secret remediation: rotate keys in Supabase/provider dashboards, then confirm no literal secrets remain with `rg -n "SERVICE_ROLE|sk-ant|VOYAGE|API_KEY|TOKEN|PASSWORD" --glob '!*.md' .`.
- Swift app/package drift: `swift build`, `swift test`, `xcodegen generate`, `bash scripts/package_app.sh`, `bash scripts/create_dmg.sh`, and the corrected notarization command.
- Edge Functions: `deno check --lock=supabase/functions/deno.lock supabase/functions/*/index.ts`, then deploy changed functions with `supabase functions deploy <name> --project-ref fpmjuufefhtlwbfinxlx`.
- Trigger: `pnpm --dir trigger install --lockfile-only`, `pnpm --dir trigger typecheck`, and `pnpm --dir trigger deploy --dry-run` if available.
- MCP services: `pnpm --dir services/graphiti-mcp install --lockfile-only`, `pnpm --dir services/graphiti-mcp typecheck`, `pnpm --dir services/skill-library-mcp install --lockfile-only`, `pnpm --dir services/skill-library-mcp typecheck`, then Docker builds using the upgraded Node image.
- Graphiti Python: build the service image after adding a lock/constraints file, then verify `/healthz`, `/readyz`, `/episode`, and `/search` with auth/private-network expectations.
- GitHub Actions: run `actionlint` after workflow permission/path edits and confirm the macOS CI artifact upload path matches the package script output.
