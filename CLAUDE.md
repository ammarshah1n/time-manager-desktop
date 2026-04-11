# Timed

## Quick Start
- Repo: `/Users/integrale/time-manager-desktop`
- Branch: `ui/apple-v1-restore`
- Primary user: Yasser Shahin (C-suite executive, Ammar's dad)
- Backend: Supabase project `fpmjuufefhtlwbfinxlx`, 8 Edge Functions ALL ACTIVE
- THE GAP: No Supabase Auth. UI still uses local `DataStore`. `SupabaseClient` + `GraphClient` are implemented but not yet called from UI.
- Read order: `CLAUDE.md` → `BUILD_STATE.md` → `MASTER-PLAN.md` (see `.claude/rules/session-protocol.md` for full protocol)

## What Timed Is
Timed is the most intelligent executive operating system ever built. NOT a productivity app. NOT competing with Motion/Sunsama.
It builds a deep, compounding model of how a specific C-suite executive (Yasser Shahin) thinks and operates, giving him cognitive bandwidth back permanently.

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
| Embeddings | Jina AI `jina-embeddings-v3` (1024-dim) | Semantic search |

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
