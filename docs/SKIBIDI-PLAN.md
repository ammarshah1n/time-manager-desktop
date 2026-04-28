# Timed — Full Front-to-Back QA + Stub Wiring + iOS Orb (Step 7)

## Context

Yasser uses Timed daily; the macOS DMG shipped 2026-04-27. We need definitive proof every wired feature works end-to-end on both platforms, that the voice path uses Deepgram + ElevenLabs + Anthropic Opus 4.7 (zero Apple TTS leak), and that previously-stubbed surfaces (morning briefing, alert firing, email classifier, iOS orb) are actually live, not placeholders. The `unified` branch is the trunk; nothing forks off the retired branches.

Static audit already confirmed:
- ✅ Voice pipeline is clean — `StreamingTTSService` → `orb-tts` Edge Function → ElevenLabs; `DeepgramSTTService` → `deepgram-token` → Deepgram WSS; `ConversationModel` → `orb-conversation` → Anthropic Opus 4.7. No `AVSpeechSynthesizer`, no `NSSpeechSynthesizer`, no `say` shell. SFSpeechRecognizer exists in `VoiceCaptureService` but for background task-parsing only, never the orb.
- ⚠️ One misleading comment at `Sources/TimedKit/Core/Services/StreamingTTSService.swift:92` claims an AVSpeechSynthesizer fallback that doesn't actually exist (the real fallback still calls `elevenlabs-tts-proxy`).
- ✅ 70 swift-testing tests, all passing; release binary fresh today.
- ⚠️ Wired-but-empty: morning briefing UI reads from DB but never invokes its Edge Function; alert UI exists but firing trigger missing; email classifier returns a mock bucket; iOS `ConversationOrbSheet` is a placeholder; 5 PrefsPane tabs hidden behind `v1BetaMode = true`.

## Approach (sequential — each phase blocks the next)

### Phase 0 — Pre-flight (session start, ~5 min)
**Blockers:** Yasser must export Supabase env vars in the launching shell, grant mic permission once during macOS exercise, and have Microsoft OAuth credentials ready.

```bash
export SUPABASE_URL="https://fpmjuufefhtlwbfinxlx.supabase.co"
export SUPABASE_ANON_KEY="<from Supabase dashboard>"
```

Verify Wave 2 backend reachability (Trigger.dev cloud + Neo4j on Fedora) — these gate stub-wiring in Phase 4. If Trigger.dev isn't reachable, we still wire the client-side calls but mark them as backend-deploy-pending in `BUILD_STATE.md`.

### Phase 1 — Static baseline (deterministic, ~5 min)
- `swift test` → confirm 70/70 pass; capture any new failures structurally.
- `swift build -c release` → clean release binary.
- `xcodegen generate` → fresh `Timed.xcodeproj`.
- `xcodebuild -scheme TimediOS -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -skipMacroValidation -skipPackagePluginValidation build` → confirm iOS clean compile.
- Re-grep for AVSpeechSynthesizer / NSSpeechSynthesizer / SFSpeechRecognizer across `Sources/` to lock the audit baseline.

### Phase 2 — Voice path hardening (~15 min)
- **Fix misleading comment** at `Sources/TimedKit/Core/Services/StreamingTTSService.swift:92` — replace "Fallback to local AVSpeechSynthesizer" with the actual behaviour (falls back to `SpeechService` which still calls `elevenlabs-tts-proxy`).
- **Add log marker** when the fallback path is hit (`os.Logger.warning("orb-tts unreachable; falling back to elevenlabs-tts-proxy one-shot")`) so silent provider drift is visible in Console.
- **Add a guard test** at `Tests/VoicePathGuardTests.swift` (new file) that fails the build if any of `AVSpeechSynthesizer`, `NSSpeechSynthesizer`, `SFSpeechRecognizer` appear in the orb call graph (`StreamingTTSService`, `SpeechService`, `ConversationModel`, `ConversationAIClient`). Static-text scan of source files is fine — this is regression insurance, not unit logic.

### Phase 3 — macOS live exercise (~45 min, needs Yasser at the keyboard for OAuth + mic prompts)
1. Repackage: `bash scripts/package_app.sh`
2. Launch `dist.noindex/Timed.app` with env exported.
3. Stream `log show --predicate 'subsystem == "com.timed"' --info --debug --last 1m` to a file while exercising.
4. Drive UI via `mcp__computer-use__*` (Mac apps are tier "full"); take screenshots at each pane for the report.
5. Test matrix (each row PASS / FAIL / NOTE in final report):

| Feature | Entry view | Verifies | Pass criteria |
|---|---|---|---|
| Sign-in | `OnboardingFlow.swift` | Microsoft OAuth + Supabase Auth | `executives` row created, `auth.users` populated |
| Voice onboarding | `VoiceOnboardingView.swift` | Deepgram WSS + orb-conversation + ElevenLabs | `[[ONBOARDING_COMPLETE]]` tag fires; `executives.onboarded_at` set |
| Today pane orb | `TodayPane.swift` → `ConversationView` | Real-time orb conversation | Audio in (Deepgram), audio out (ElevenLabs MP3 via `AVAudioPlayer`), reply text from Opus |
| Dish Me Up | `DishMeUpHomeView.swift` | Opus extended-thinking | Plan rendered with budget rationale |
| Email triage | `TriagePane.swift` | Keyboard nav + undo + bundle | k/j moves selection, u undoes, bundles open |
| Focus timer | `FocusPane.swift` | Countdown + Pomodoro + notification | Timer expires, notification posts, "want another task?" prompt shows |
| Calendar | `CalendarPane.swift` | Outlook delta + drag-to-create | Real events render; drag creates a block |
| PrefsPane | `PrefsPane.swift` | Accounts + Voice tabs | Sign-out works; voice toggle persists |
| Menu bar | `MenuBarStatus.swift` | Quick status display | Today's count shows |

For each FAIL or NOTE: capture log slice, screenshot, file:line — feeds Phase 4.

### Phase 4 — Wire stubs (~2-3 hours, depends on what Phase 3 surfaces)
Each item starts as a separate focused diff; rebuild + smoke-test after each.

**4a. Morning briefing generation** — `MorningBriefingViewModel` (or `MorningCheckInManager`) currently reads `briefings` table but never invokes the Edge Function. Action: identify the briefing-generation Edge Function (likely `generate-briefing` or `morning-briefing-compose` under `supabase/functions/`), add a client call from the briefing entry point gated on `executives.onboarded_at != nil`, render the streamed Opus output into the existing briefing view. If the Edge Function isn't deployed, leave the call site wired but stub the network call to return a placeholder + mark `BUILD_STATE.md` as "client wired, backend pending deploy".

**4b. Alert firing trigger** — `AlertEngine` exists with multiplicative scoring + 3/day cap (8 tests pass), but no caller invokes it after an event. Action: find the realtime subscription / scheduled tick that should drive it (likely missing in `DataBridge` or a new `AlertCoordinator`), wire so that any new email / task / signal event passes through `AlertEngine.evaluate()` and surfaces to `AlertsPane`.

**4c. Email classifier** — `EmailClassifier.swift` returns mock buckets. Action: replace mock with real Anthropic Haiku 3.5 call via existing `anthropic-relay` Edge Function (server-side key, model allowlist). Keep the existing protocol so tests still pass; add new tests for the live path with a recorded fixture.

**4d. v1BetaMode hidden tabs** — `PrefsPane.swift` has `v1BetaMode = true` hiding 5 tabs. Action: review each hidden tab's wiring; un-hide any that are actually functional. Move the flag to `UserDefaults` so we can toggle without rebuild.

### Phase 5 — iOS Step 7 (orb wiring on iPhone, ~1-2 hours)
- `ConversationOrbSheet()` in `Sources/TimedKit/AppEntry/TimediOSRootView.swift:191` is a placeholder.
- Verify voice services already compile under iOS — `StreamingTTSService`, `DeepgramSTTService`, `ConversationModel` use `AVAudioEngine`, `AVAudioPlayer`, `URLSession`, all cross-platform. The audit showed no `#if os(macOS)` guards on them. If any creep in, lift them.
- Wire `ConversationOrbSheet` to present `ConversationView` (same SwiftUI tree the macOS `TodayPane` sheet uses).
- Add `NSMicrophoneUsageDescription` to `Platforms/iOS/Info.plist` (or `project.yml` Info plist values).
- Smoke on iPhone 15 Pro sim via XcodeBuildMCP: boot sim, install app, launch, snap orb sheet, verify mic prompt fires.

### Phase 6 — Re-verify + ship (~15 min)
- `swift test` → 70+ pass (count grows with new guard test + classifier test).
- Re-run Phase 3 macOS smoke on the rebuilt artefacts.
- `bash scripts/package_app.sh && bash scripts/create_dmg.sh` → fresh DMG.
- Update `BUILD_STATE.md`: mark Phase 4 stubs as wired (or "client wired, backend pending"); voice guard test added; iOS orb wired.
- Update `HANDOFF.md` to remove the "Wave 2 nightly engine code merged but not deployed" caveat where applicable, or refine it.
- `mcp__basic-memory__write_note` to `timed-brain` summarising the verified-working state with `summary:` line.

## Critical files

| Phase | File | Action |
|---|---|---|
| 2 | `Sources/TimedKit/Core/Services/StreamingTTSService.swift:92` | Fix misleading comment, add log warning |
| 2 | `Sources/TimedKit/Core/Services/SpeechService.swift` | Verify fallback messaging consistent |
| 2 | `Tests/VoicePathGuardTests.swift` (new) | Static-scan guard against Apple TTS regression |
| 4a | `Sources/TimedKit/Features/MorningBriefing/MorningBriefingViewModel.swift` (or similar) | Wire Edge Function call |
| 4a | `supabase/functions/<briefing-fn>/index.ts` | Confirm exists + deployed |
| 4b | `Sources/TimedKit/Core/Services/AlertEngine.swift` + new `AlertCoordinator.swift` | Add caller |
| 4c | `Sources/TimedKit/Features/Email/EmailClassifier.swift` | Replace mock with Haiku call |
| 4d | `Sources/TimedKit/Features/Settings/PrefsPane.swift` | v1BetaMode → UserDefaults; un-hide functional tabs |
| 5 | `Sources/TimedKit/AppEntry/TimediOSRootView.swift:191` | Wire `ConversationOrbSheet` to `ConversationView` |
| 5 | `Platforms/iOS/Info.plist` (or `project.yml`) | Add `NSMicrophoneUsageDescription` |
| 6 | `BUILD_STATE.md`, `HANDOFF.md` | Update status |

Reuse existing infrastructure — do not invent new services where these already exist:
- `EdgeFunctions.swift` for all Edge Function client calls (used by orb-tts, deepgram-token, orb-conversation)
- `AnthropicRelayClient` (if exists) or `EdgeFunctions.shared` for Haiku call
- `ConversationView.swift` is the cross-platform orb UI — reuse for iOS, do not fork

## Verification

End-to-end smoke commands run sequentially after Phase 6:

```bash
cd /Users/integrale/time-manager-desktop

# A. Build everything clean
swift test                                                    # 70+ tests pass
swift build -c release                                         # arm64 release binary
xcodegen generate                                              # fresh Timed.xcodeproj
xcodebuild -scheme TimediOS \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -skipMacroValidation -skipPackagePluginValidation build      # iOS clean

# B. Package + ship
bash scripts/package_app.sh                                    # dist.noindex/Timed.app
bash scripts/create_dmg.sh                                     # dist.noindex/Timed.dmg

# C. Voice regression guard
grep -r "AVSpeechSynthesizer\|NSSpeechSynthesizer" \
  Sources/TimedKit/Core/Services/StreamingTTSService.swift \
  Sources/TimedKit/Core/Services/SpeechService.swift \
  Sources/TimedKit/Features/Conversation/         # must return zero matches
```

Manual:
- Launch `dist.noindex/Timed.app`, drive Phase 3 matrix, every row PASS.
- Boot iPhone 15 Pro sim, install + launch `TimediOS`, open orb sheet, verify mic prompt + ElevenLabs reply audio.
- Console.app filter `subsystem:com.timed` shows zero "AVSpeech*" instantiation, zero unhandled errors.

## Out of scope (deferred — documented in HANDOFF.md)
- **Apple Developer Program enrollment** (Track A proper signing + notarisation). Blocks DMG distribution beyond ad-hoc; needs Yasser to purchase the membership.
- **Wave 2 cloud deployment** (Trigger.dev secrets, Neo4j on Fly/AuraDB, Entra server-app) — if these aren't live, Phase 4a stub-wires the client side but leaves the backend marked pending.
- **Whisper.cpp local STT** — research gap noted in `BUILD_STATE.md`; not a regression.
- **TestFlight / iOS distribution** — depends on Apple Developer enrollment.
