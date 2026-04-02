---
name: reflect
description: Context for working on the reflection engine (intelligence core)
---

Before modifying the reflection engine:
1. Read docs/05-reflection-engine.md — the full specification
2. Read docs/02-memory-system.md — what the engine reads from and writes to
3. Read docs/08-decisions-log.md #004 (Opus at max effort) and #007 (Edge Functions)

The reflection engine is the HEART of Timed. It is what makes the system
genuinely smarter over time.

Three-stage cycle:
1. First-order pattern extraction: "7 of 9 strategic docs opened but not edited"
2. Second-order insight synthesis: "correlates with post-board weeks"
3. Rule generation: "avoid scheduling strategic work 72h post-board"

Processing tiers:
- Real-time (Haiku): event classification, importance scoring, anomaly detection
- Periodic (Sonnet): daily pattern extraction, communication analysis
- Deep (Opus max effort): nightly recursive reflection, model updates, rule generation

The reflection engine:
- NEVER takes action on the world
- Only reads from memory store and writes back to memory store
- Every pattern/insight must cite specific episodic evidence
- Rules have confidence scores that increase/decrease with evidence
- Must track stability, drift, and contextual variance in patterns
- Output feeds the morning session (pattern headlines, cognitive state)

Quality bar for generated patterns:
- "You avoided the board deck for 11 days" ✅ (specific, named, evidenced)
- "You might be procrastinating" ❌ (vague, generic, no evidence)
