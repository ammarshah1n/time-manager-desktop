# Timed

## Quick Start
- Repo: `/Users/integrale/time-manager-desktop`
- **Branch: `unified`** (single source of truth — TimedKit + TimedMacApp + TimediOS + Wave 1+2 backend + voice path + docs, all on one trunk as of 2026-04-27).
- Co-founders / first users: Ammar Shahin (CTO) + Yasser Shahin (CEO, Ammar's father). The prototype is built by and for both of them.
- Backend: Supabase project `fpmjuufefhtlwbfinxlx`, 29 Edge Functions ALL ACTIVE (`ls supabase/functions/` verified 2026-04-22)
- THE GAP: `AuthService.swift` is implemented (Supabase Auth + Microsoft OAuth, 30 call sites) but UI still reads/writes through local `DataStore`. Bridge to Supabase is the next priority.
- **DMG status**: ✅ Track B delivered — `dist.noindex/Timed.dmg` (31 MB, ad-hoc signed). Apple Developer enrollment pending for Track A (proper signing + iOS TestFlight).
- Read order: `docs/UNIFIED-BRANCH.md` → `CLAUDE.md` → `BUILD_STATE.md` → `MASTER-PLAN.md` (see `.claude/rules/session-protocol.md` for full protocol)

<important>
## Memory Default — ENFORCED via hooks (do not skip)

- **basic-memory project:** `timed-brain` (vault content, 1198+ notes). AIF questions: also search `aif-vault`.
- **claude-mem project:** `time-manager-desktop` (session observations, auto-loaded on SessionStart).
- **Read-back protocol:** `~/CLAUDE.md` → `## Memory Protocol`. Search BEFORE researching, BEFORE answering "what is X" / architecture questions, BEFORE claiming "I don't know about prior work".

### Enforcement (active 2026-04-28+)
- **SessionStart hook** (`.claude/hooks/session-start-context.sh`) emits the Memory-First Protocol block + live `timed-brain` snapshot at the top of every session's context. You see it before anything else.
- **PreToolUse hook** (`.claude/hooks/memory-gate.sh`) nags via stderr the FIRST time you call `WebSearch` / `WebFetch` / `Agent` / `mcp__perplexity-comet__*` without a prior `mcp__basic-memory__*` call this session. Sentinel at `/tmp/claude-memcheck-${session_id}` — touched on first basic-memory call, then nag silences for the rest of the session.
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
1. No cost cap on intelligence. Opus 4.6 at max effort for the nightly analysis engine.
2. Intelligence compounds over time. Every night Opus synthesises deeper understanding. Month 6 >> Month 1. This is the moat.
3. Nightly engine is the heart. Recursive reflection: raw observations -> first-order patterns -> second-order synthesis -> semantic model updates -> procedural rule generation (Stanford Generative Agents architecture, Park et al. 2023).
4. Morning session delivers intelligence, not a task list. Cognitive briefing, not features.
5. Cognitive layer only. Timed observes, reflects, recommends. NEVER acts on the world unilaterally.
6. User is a C-suite executive. Impressed only by a system that understands them, not features.
</important>

## AI Stack
| Layer | Model | Purpose |
|-------|-------|---------|
| Classification | Claude Haiku 3.5 | Email/task triage |
| Estimation | Claude Sonnet | Time/effort estimation |
| Nightly engine | Claude Opus 4.6 (max effort) | Recursive reflection, profile synthesis |
| Morning director | Claude Opus 4.6 (max effort) | Cognitive briefing generation |
| Profile cards | Claude Opus 4.6 (max effort) | Deep contact intelligence |
| Embeddings — Tier 0 | Voyage `voyage-3` (1024-dim) | High-volume raw observations |
| Embeddings — Tier 1–3 | OpenAI `text-embedding-3-large` (3072-dim) | Daily summaries, behavioural signatures, personality traits |

## Infrastructure
- Auth: Microsoft OAuth (`Mail.Read` + `Calendars.Read` + `offline_access`)
- Graph API methods are implemented
- Supabase queries for 12 operations are implemented
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
1. Supabase Auth (Microsoft provider) + workspace/profile bootstrap
2. Bridge UI -> Supabase (dual-write with `DataStore`)
3. `EmailSyncService` (background Graph delta sync)
4. Realtime subscriptions
5. `FR-03` task extraction, `FR-06` calendar, `FR-07` PA sharing, `FR-08` aging

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

See `BAG.md` for install + usage + risks. Audit method documented at the bottom of that file when adding a new tool.
