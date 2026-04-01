---
tags: [rules, corrections, self-improve]
created: 2026-03-29
---

# Corrections Log

> Every time Ammar corrects Claude, the correction is logged here as a permanent rule.
> These feed back into CLAUDE.md and prevent repeat mistakes.

### 2026-03-29 Correction: Suggested Codex for a task Claude should have done itself
- What I did: After completing analysis, suggested Ammar run the result in Codex instead of executing it myself via the Agent tool
- What Ammar wanted: Claude to just do the work — the whole point of 5 hours of context-building was so Claude could execute, not delegate
- Why I should have known: Ammar had been running 4 terminals simultaneously, building context in each. Suggesting Codex means losing all that context. I have the Agent tool available and could have fired it immediately.
- Rule: If you can do it in this terminal (via Agent tool or directly), do it. Only suggest external tools for genuinely parallel/async work that doesn't need current session context.
