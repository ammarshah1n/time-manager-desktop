---
purpose: Enumerate every external dependency × failure mode and rank by Pr(Yasser hits this in 7 days) × user-pain.
fire: Parallel with 1 / 2 / 7
depends_on: nothing
---

# Prompt 4 — Reliability & failure-mode audit

## Prompt body (paste into Perplexity Deep Research)

Repo: ammarshah1n/time-manager-desktop @ `unified`. Audit GOAL: enumerate every external dependency and every failure mode, score how the app degrades, and produce fixes for the failures Yasser will actually hit in his first week.

External dependencies to map:
- Supabase Auth (email/password + Microsoft OAuth)
- Microsoft Graph API + MSAL token refresh
- Anthropic API (via anthropic-relay + voice-llm-proxy + anthropic-proxy)
- ElevenLabs (Conversational AI agent + elevenlabs-tts-proxy)
- OpenAI (text-embedding-3-large, Tier 1-3)
- Voyage AI (voyage-3, Tier 0)
- Deepgram (parked but referenced)
- Trigger.dev v4 cloud (4 cron tasks)
- Graphiti API on Fedora (behind Cloudflare quick tunnel — URL rotates on Fedora reboot, see `scripts/refresh_graphiti_tunnel.sh`)
- Neo4j on Fedora (podman-compose)
- Supabase Realtime (subscriptions)
- Local: USearch HNSW index, GRDB SQLite, JSON DataStore, FileAuthLocalStorage (`~/Library/Application Support/Timed/_auth/`)

For each dependency, produce:

| dependency | failure mode | what user sees | what code does | severity | fix (file:line, no new arch) | effort |

Failure modes to consider per dependency:
- Network offline
- Auth token expired
- Rate limit (429)
- 500 server error
- Cold start (first call after idle)
- Slow response (> 10s)
- Partial data (truncated stream)
- Stale cache (served from 7-day-old cache)
- Cloudflare tunnel rotated (Graphiti specific)
- Cron failure / missed run (Trigger.dev specific)

Specifically pay attention to:
- **VoiceCaptureService MainActor crash fix** (shipped today) — is the new audio-tap closure pattern actually safe under all device-route changes (AirPods connect/disconnect, Bluetooth drop)?
- **FileAuthLocalStorage** replaces Keychain for ad-hoc-signed dev builds. What happens when Yasser's app crashes mid-write? Token corruption?
- **OfflineSyncQueue** (GRDB) — what happens when queue grows to 10k items while Yasser is on a long flight?
- **MSAL token refresh** interplay with Supabase Auth session.
- **Cloudflare quick tunnel URL rotation** — how does the orb know to switch endpoints?

Output ordering: rank failures by `Pr(Yasser hits this in first 7 days) × user-pain` — fix top 10 first.

Constraints:
- No new architecture.
- Timed never acts on the world.
