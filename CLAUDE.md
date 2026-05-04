# Timed

## Quick Start
- Repo: `/Users/integrale/time-manager-desktop`
- **Branch: `unified`** (single source of truth — TimedKit + TimedMacApp + TimediOS + Wave 1+2 backend + voice path + docs, all on one trunk as of 2026-04-27).
- Co-founders / first users: Ammar Shahin (CTO) + Yasser Shahin (CEO, Ammar's father). The prototype is built by and for both of them.
- Backend: Supabase project `fpmjuufefhtlwbfinxlx`; CLI verified 39 active remote Edge Functions on 2026-04-30. Local tree has 40 function dirs plus `_shared`; `deepgram-transcribe` is local-only.
- Current gaps: open Timed and connect Gmail with `5066sim@gmail.com`; resume Apple Developer enrollment for notarised Mac/iOS delivery; decide whether optional local-only `deepgram-transcribe` should stay parked.
- Shipped 2026-04-30: Gmail backend migration + `voice-llm-proxy` OR-gate live; Graphiti backfill completed; 16-function security-hardening set deployed.
- **DMG status**: ✅ Track B delivered — `dist.noindex/Timed.dmg` (31 MB, ad-hoc signed). Apple Developer enrollment pending for Track A (proper signing + iOS TestFlight).
- Read order: `docs/UNIFIED-BRANCH.md` → `HANDOFF.md` → `BUILD_STATE.md` → `CLAUDE.md` → `MASTER-PLAN.md` STATUS section (see `.claude/rules/session-protocol.md` for full protocol)

<important>
## Memory Default — ENFORCED via hooks (do not skip)

- **basic-memory project:** `timed-brain` (vault content, 1198+ notes). AIF questions: also search `aif-vault`.
- **claude-mem project:** `time-manager-desktop` (session observations, auto-loaded on SessionStart).
- **Read-back protocol:** `~/CLAUDE.md` → `## Memory Protocol`. Search BEFORE researching, BEFORE answering "what is X" / architecture questions, BEFORE claiming "I don't know about prior work".

### Enforcement (active 2026-04-28+)
- **SessionStart hook** (`.claude/hooks/session-start-context.sh`) emits the Memory-First Protocol block + live `timed-brain` snapshot at the top of every session's context. You see it before anything else.
- **PreToolUse hook** (`.claude/hooks/memory-gate.sh`) nags via stderr the FIRST time you call `WebSearch` / `WebFetch` / `Agent` / `mcp__comet_bridge__*` without a prior `mcp__basic-memory__*` call this session. Sentinel at `/tmp/claude-memcheck-${session_id}` — touched on first basic-memory call, then nag silences for the rest of the session.
- **The nag is non-blocking** (existing `permission-check.sh` Tier 1 auto-approves WebSearch/WebFetch). Heed the nag — cancel the call, run `mcp__basic-memory__search_notes` first, then retry.

### Required first calls (load schemas via ToolSearch if deferred)
```
mcp__basic-memory__search_notes(project="timed-brain", query="<your query>")
mcp__basic-memory__recent_activity(project="timed-brain", timeframe="14d")
```

### Corpus refresh
After major C-phase rewrites or non-incremental vault changes, run `rebuild_corpus` then `prime_corpus` for the relevant claude-mem corpus (`intelligence-core-brain`, `aif-decisions-brain`). Do NOT create a corpus keyed to a single founder's name — both founders are peer users.
</important>

## What Timed Is
Timed is the most intelligent executive operating system ever built. NOT a productivity app. NOT competing with Motion/Sunsama.
It builds a deep, compounding model of how its executive users think and operate, giving them cognitive bandwidth back permanently. The prototype models both co-founders (Yasser + Ammar) symmetrically — there is no single "subject".

<important>
## Design Principles
1. No cost cap on intelligence. Use the strongest Opus-class model available for the nightly analysis engine; Trigger.dev Wave 2 aliases route Opus work to 4.7, while legacy Supabase Edge Functions still include direct 4.6 IDs.
2. Intelligence compounds over time. Every night Opus synthesises deeper understanding. Month 6 >> Month 1. This is the moat.
3. Nightly engine is the heart. Recursive reflection: raw observations -> first-order patterns -> second-order synthesis -> semantic model updates -> procedural rule generation (Stanford Generative Agents architecture, Park et al. 2023).
4. Morning session delivers intelligence, not a task list. Cognitive briefing, not features.
5. Cognitive layer only. Timed observes, reflects, recommends. NEVER acts on the world unilaterally.
6. User is a C-suite executive. Impressed only by a system that understands them, not features.
7. Cognitive load is the budget. The exec already runs a company; we don't add another tab in their head. No empty rows, no decorative chrome, no "—" placeholders, no "(none)" fallbacks. If a field has no value, HIDE the row entirely. If a section is informational-only and rare, fold it into another. When in doubt, cut. Enforcement details: `docs/UI-RULES.md` rules 14–15 + `Tests/TimedDesignGuardTests.swift`.
</important>

## AI Stack
| Layer | Model | Purpose |
|-------|-------|---------|
| Classification | Claude Haiku 3.5 | Email/task triage |
| Estimation | Claude Sonnet | Time/effort estimation |
| Nightly engine | Claude Opus-class (Trigger aliases route to 4.7) | Recursive reflection, profile synthesis |
| Morning director | Claude Opus-class | Cognitive briefing generation |
| Profile cards | Claude Opus-class | Deep contact intelligence |
| Embeddings — Tier 0 | Voyage `voyage-3` (1024-dim) | High-volume raw observations |
| Embeddings — Tier 1–3 | OpenAI `text-embedding-3-large` (3072-dim) | Daily summaries, behavioural signatures, personality traits |

## Infrastructure
- Auth: Microsoft OAuth (`Mail.Read` + `Calendars.Read` + `offline_access`) plus additive Google OAuth for Ammar's Gmail path
- Microsoft Graph and Gmail API methods are implemented in separate client/service paths
- Supabase queries and Edge Functions are the only AI/backend boundary from Swift
- Distribution: Direct DMG + Sparkle, not App Store

## File Map
| What | Path |
|------|------|
| Codebase root | `~/time-manager-desktop/` |
| Swift sources | `~/time-manager-desktop/Sources/` |
| Architecture docs | `~/time-manager-desktop/docs/` (01-10) |
| Feature specs | `~/time-manager-desktop/specs/` (56 specs) |
| Implementation plan | `~/time-manager-desktop/specs/IMPLEMENTATION_PLAN.md` |
| Build state | `~/time-manager-desktop/BUILD_STATE.md` |
| v1 research | `~/time-manager-desktop/research/perplexity-outputs/` |
| v2 research (intelligence core) | `~/time-manager-desktop/research/perplexity-outputs/v2/` (14 reports) |
| Obsidian vault | `~/Timed-Brain/` |

## Vault & Search
- Obsidian vault: `~/Timed-Brain/` (144 notes)
- Session start: `~/Timed-Brain/VAULT-INDEX.md` -> `HANDOFF.md` -> `Working-Context/timed-brain-state.md`
- Navigate: Use folder `index.md` files, not raw folder scans
- Search: `qmd search "keyword" -c timed-brain`; `qmd query "natural language question" -c timed-brain`; `obsidian search query="term" vault="Timed-Brain"`; `obsidian backlinks file="NoteName" vault="Timed-Brain"`
- Cross-vault: `qmd search "term"` (no `-c` flag) searches all vaults
- Session close: Update `Working-Context/timed-brain-state.md`, extract decisions to `06 - Context/`
- Typed links: Use `supersedes::`, `implements::`, `caused-by::`, `learned-from::` in notes

## Build & Test Tools
See `.claude/rules/coding-standards.md` and `.claude/rules/testing-rules.md`.

<important>
## MANDATORY SESSION RULES (post 2026-04-27 unification)
Read these every session. Mirror copy at `~/Desktop/timed-future-session-tips.md`.

1. **Always work on `unified`.** First action of any session: `git checkout unified && git pull`. Do NOT branch off `ui/apple-v1-restore`, `ui/apple-v1-local-monochrome`, `ui/apple-v1-wired`, or `ios/port-bootstrap` — those are superseded backups.
2. **Read order on session start:** `docs/UNIFIED-BRANCH.md` → `HANDOFF.md` → `BUILD_STATE.md` → this file.
3. **Code organisation:** new Swift files go in `Sources/TimedKit/Features/<area>/` or `Sources/TimedKit/Core/<area>/`. Mac-only code wraps in `#if os(macOS)`. iOS @main: `Platforms/iOS/TimediOSAppMain.swift`. Mac @main: `Sources/TimedMacApp/TimedMacAppMain.swift`. Never put feature code in `Sources/TimedMacApp/` — breaks iOS build.
4. **Xcode project is generated, not committed.** Edit `project.yml`; run `xcodegen generate` to materialise `Timed.xcodeproj` (gitignored).
5. **Required xcodebuild flags:** `-skipMacroValidation -skipPackagePluginValidation` always. For Mac: also `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` (usearch's Float16 doesn't compile for x86_64).
6. **DMG production:** `bash scripts/package_app.sh && bash scripts/create_dmg.sh` → `dist.noindex/Timed.dmg`. Currently ad-hoc signed (Track B). Track A (Developer ID + notarised) is blocked on Apple Developer Program enrollment.
7. **Do NOT retire stale branches yet** — they're escape hatches until Track A is verified working end-to-end.
8. **Permission-hook caveats:** `.claude/hooks/permission-check.sh` hard-denies tool inputs containing dot-env file paths, or the combination of `supabase/migrations/` with remove/rm/unlink keywords. Split Edits to avoid these substrings co-occurring.
9. **OrbStack closed on this Mac.** Wave 2 backend services (Graphiti, Neo4j, Trigger.dev v4) run on the Linux machine. Trigger.dev tasks deploy to their cloud — no local Docker needed.
</important>

## Next Priorities
1. Open Timed → Settings → Accounts → Add Gmail with `5066sim@gmail.com`
2. Resume Apple Developer enrollment for notarised Mac/iOS delivery
3. Decide whether optional local-only `deepgram-transcribe` should stay parked
4. Keep Microsoft auth/sync untouched while exercising the additive Gmail path

- See `.claude/rules/coding-standards.md` for code conventions.
- See `.claude/rules/testing-rules.md` for testing workflow and framework rules.
- See `.claude/rules/session-protocol.md` for session start, close, and compaction rules.
- See `.claude/rules/ai-assistant-rules.md` for anti-patterns and tool dispatch rules.
- See `.claude/rules/naming-conventions.md` for the naming examples referenced here.

## Toolkit / Bag (Timed relevant)

Master bag: `/Users/integrale/Documents/toolkit-bag/BAG.md`. Tools that matter for Timed:

- **VoxCPM** (open-source TTS, OpenBMB) — voice output for morning briefings / nightly briefings. Open-source, runs locally, no per-call cost. Drop-in alternative to ElevenLabs. Respects the "Timed observes, reflects, recommends — never acts" rule because TTS is one-way output.
- **claude-video-vision** — ingest your own demo recordings (and Yasser's) to extract feature feedback, qualitative signal, UI friction points. Useful for the nightly engine if recordings are part of the corpus.
- **openscreen** — record demo videos for the App Store / launch / TestFlight comms.
- **Open-Generative-AI** — UI asset generation (icons, marketing graphics, App Store screenshots).
- **gpt-researcher-claude-cli** — self-hosted Deep Research using CC subscription + private SearxNG instance. Reach for it for technical deep-dives on AI infra, embedding models, agent frameworks, MCP ecosystem, anything where you'd otherwise burn Perplexity Pro quota. Launch: `~/Documents/toolkit-bag/gpt-researcher/start_all.sh`. Full notes in `BAG.md` §9.

See `BAG.md` for install + usage + risks. Audit method documented at the bottom of that file when adding a new tool.
