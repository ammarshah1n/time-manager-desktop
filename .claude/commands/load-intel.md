---
name: load-intel
description: Load all intelligence core architecture into context. Run before any build work on memory, reflection, signals, delivery, or prediction.
---

Load the full intelligence core architecture into context. Read these files IN THIS ORDER:

1. Read `BUILD_STATE.md` — current state of what exists and what's missing
2. Read `research/ARCHITECTURE-MEMORY.md` — 5-tier memory, nightly pipeline, retrieval, prediction, evaluation, complete SQL schema
3. Read `research/ARCHITECTURE-SIGNALS.md` — 30+ signals, ONA, keystroke, voice, chronobiology, cognitive science, multi-modal fusion
4. Read `research/ARCHITECTURE-DELIVERY.md` — morning briefing, alerts, voice UX, coaching, privacy, cold start, Swift/macOS architecture, GTM

After reading all 4 files, summarise:
- What exists (from BUILD_STATE)
- What the architecture specifies (from the 3 ARCHITECTURE docs)
- The 6 build phases and which phase should come first
- Ask: "What are we building?"

IMPORTANT: Read the FULL content of each ARCHITECTURE file — they contain schemas, pseudocode, algorithms, and decision rationale that are essential for implementation. Do not skim or skip sections.
