# HANDOFF.md — Timed Intelligence System

Last updated: 2026-04-26

## Done This Session — Voice path locked + portability fixes
- **Removed Apple TTS from the voice loop**: stripped the `AVSpeechSynthesizer` fallback from `SpeechService.swift`. ElevenLabs failures now surface as visible errors instead of silently switching to Apple's robotic voice. `VoiceCaptureService.swift` (Apple `SFSpeechRecognizer`) is intentionally retained — it powers the legacy Capture/MorningInterview/OnboardingFlow panes that aren't on the orb path. Deletion deferred (cascades into rewriting ~2K lines).
- **ElevenLabs Conversational Agent locked in**: agent ID `agent_3501kpyz0cnrfj8tgbb2bmg5arfk` baked into `MorningCheckInManager.swift` as `kBakedInAgentID`. Resolution order: UserDefaults override → env var → baked-in constant. Fresh installs get a working orb with zero setup.
- **Brain bumped to Opus 4.7**: `voice-llm-proxy/index.ts` morning check-in path → `claude-opus-4-7`. Onboarding stays on Haiku 4.5 for first-token latency. Three Swift clients (`CaptureAIClient`, `OnboardingAIClient`, `InterviewAIClient`) also bumped to 4.7.
- **API keys removed from the binary**: created two new Edge Function proxies — `anthropic-proxy` (forwards Claude API calls server-side) and `elevenlabs-tts-proxy` (one-shot TTS for Capture/Dish-Me-Up). All four Swift clients now route through them. The `anthropic_api_key` and `elevenlabs_api_key` AppStorage keys are gone, and the matching fields removed from Settings → Voice. Per the rule "Third-party API keys never on client".
- **Centralized Supabase endpoints**: new `Sources/Core/Clients/SupabaseEndpoints.swift` is the single source of truth for the Supabase URL + public anon JWT. Voice path files (`MorningCheckInManager`, `VoiceOnboardingView`, `VoiceFeatureService`) now reference it. The non-voice files (`SupabaseClient`, `EmailSyncService`, `GracefulDegradation`, `SharingService`, `SharingPane`) still hold their own duplicates — left alone (working fallbacks; not in voice path).
- **Deepgram parked, not wired**: built `supabase/functions/deepgram-transcribe/index.ts` so the existing Deepgram subscription stays usable for non-conversational paths (voice memos, batch transcription) without contaminating the live conversational orb. The orb cannot use Deepgram because ElevenLabs Conversational AI locks ASR to their own models — verified via Comet.

## Current State
- Branch: `ui/apple-v1-local-monochrome`
- Voice path: ElevenLabs Conversational Agent (Scribe v2 Turbo planned) → Opus 4.7 via `voice-llm-proxy` → ElevenLabs voice. Apple is fully out of this path. Deepgram is parked (subscription preserved, not in conversational loop).
- New Edge Functions written but **not yet deployed**: `anthropic-proxy`, `elevenlabs-tts-proxy`, `deepgram-transcribe`.
- New Supabase secret needed: `ELEVENLABS_API_KEY` (and `DEEPGRAM_API_KEY` if you want the parked function callable).
- `dist/Timed.app` was last rebuilt mid-session before the API-key proxy migration. Final rebuild pending — Xcode license needs re-accept after a system update.

## Known Issues
- `swift build` errored with "Xcode license not accepted" mid-session — system Xcode was likely auto-updated. Run `sudo xcodebuild -license accept` then `bash scripts/package_app.sh && bash scripts/install_app.sh` to ship the API-key-proxy edits.
- ElevenLabs portal still has the agent's ASR set to "Original ASR" per Comet's earlier finding. Switch to **Scribe v2 Turbo** for the realtime variant.
- Legacy panes (`CapturePane`, `MorningInterviewPane`, `OnboardingFlow`) still use `VoiceCaptureService` (Apple SFSpeechRecognizer). Not in orb path; worth deleting in a follow-up sweep so the codebase has one voice idiom.
- 24 non-voice Edge Functions still hardcode `claude-opus-4-6`. Bundle into a separate fleet-wide model migration commit; not urgent.

## Next — what you need to do
**Comet/browser tasks** (1 small one):
1. ElevenLabs portal → Morning Agent → Advanced → ASR provider → switch from "Original ASR" to **"Scribe v2 Turbo"**.

**Terminal tasks** (any shell):
```bash
# 1. Re-accept Xcode license after the system update
sudo xcodebuild -license accept

# 2. Rebuild and install the .app with the API-key-proxy edits
cd ~/time-manager-desktop && bash scripts/package_app.sh && bash scripts/install_app.sh

# 3. Set the new Supabase secret(s)
supabase secrets set ELEVENLABS_API_KEY=<your_eleven_key>     --project-ref fpmjuufefhtlwbfinxlx
supabase secrets set DEEPGRAM_API_KEY=<your_deepgram_key>     --project-ref fpmjuufefhtlwbfinxlx   # optional, only needed if you want deepgram-transcribe live

# 4. Deploy the new Edge Functions
supabase functions deploy anthropic-proxy        --project-ref fpmjuufefhtlwbfinxlx
supabase functions deploy elevenlabs-tts-proxy   --project-ref fpmjuufefhtlwbfinxlx
supabase functions deploy deepgram-transcribe    --project-ref fpmjuufefhtlwbfinxlx   # optional
```

After those: launch `/Applications/Timed.app`, hit the orb, expect Scribe v2 Turbo (STT) → Opus 4.7 (LLM) → ElevenLabs voice (TTS). Zero Apple in the path. Zero per-user setup for fresh installs.

## Architecture summary (post-session)
| Layer | Tech | Where it lives |
|---|---|---|
| ASR (orb) | ElevenLabs Scribe v2 Turbo | inside the ElevenLabs Conversational Agent |
| LLM (orb) | Claude Opus 4.7 | `supabase/functions/voice-llm-proxy/index.ts` |
| TTS (orb) | ElevenLabs voice (agent-baked) | inside the ElevenLabs Conversational Agent |
| TTS (one-shot, Capture/Dish-Me-Up) | ElevenLabs (Lily voice) via proxy | `supabase/functions/elevenlabs-tts-proxy/index.ts` |
| LLM (Capture/Onboarding/Interview) | Claude Opus 4.7 via proxy | `supabase/functions/anthropic-proxy/index.ts` |
| Batch ASR (parked, future use) | Deepgram Nova-3 via proxy | `supabase/functions/deepgram-transcribe/index.ts` |
| Endpoint config | one Swift constant | `Sources/Core/Clients/SupabaseEndpoints.swift` |
| Agent ID | one Swift constant | `Sources/Features/MorningCheckIn/MorningCheckInManager.swift` |
