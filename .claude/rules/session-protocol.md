# Session Protocol

<important>
## Session Start
- **Auto-loaded via SessionStart hook** (`.claude/hooks/session-start-context.sh`): `HANDOFF.md` + last `SESSION_LOG.md` entry + `BUILD_STATE.md` architecture summary (~85 lines)
- Manual deep-dive if needed: `/session-handoff` or read protocol: `VAULT-INDEX.md` -> `HANDOFF.md` -> `Working-Context/timed-brain-state.md` -> `CLAUDE.md` -> `MASTER-PLAN.md` (STATUS section)
</important>

## Session Read Order
| Session type | Read order |
|-------------|-----------|
| New session | `CLAUDE.md` -> `BUILD_STATE.md` -> `MASTER-PLAN.md` |
| Build a component | `BUILD_STATE.md` -> relevant `docs/` -> relevant `specs/` |
| Architecture question | `docs/01-architecture.md` -> `Timed-Brain/06-Context/` |
| Research context | `research/perplexity-outputs/v2/` -> `research/extractions/` |

<important>
## Session Close Protocol
- **Close:** Run `/wrap-up` — includes `HANDOFF.md` generation via session-handoff skill
</important>

<important>
## Compaction Instructions
When compacting this session, ALWAYS preserve:
1. The exact spec file currently in scope (full list of modified functions)
2. All files modified this session — do not summarise, list each path
3. Current test suite status (passing count, any failing tests with error strings)
4. Any unresolved errors or open questions
5. The architectural decision being implemented (which ADR)

Do NOT preserve: session log file paths, exploratory grep outputs, general context already in `VAULT-INDEX.md`
</important>

<important>
## Knowledge Compounding
After any session that produces an architectural decision or bug fix:
1. Update `Working-Context/timed-brain-state.md` with current state
2. Extract decisions to permanent notes in `~/Timed-Brain/06 - Context/`
3. Auto Memory captures corrections automatically — don't duplicate
</important>
