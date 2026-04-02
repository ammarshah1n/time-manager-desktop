# 05 — Reflection Engine Specification

## Overview

The reflection engine is the heart of Timed. It is the mechanism by which the
system gets genuinely smarter over time. Without it, Timed accumulates data.
With it, Timed builds intelligence.

**Status:** ❌ Not started — this is the primary build target.

## Architecture (from Research Pack 01)

Based on Stanford Generative Agents (Park et al., 2023) recursive reflection,
MemGPT tiered memory management, and ACAN dynamic retrieval.

### Three-Stage Reflection Cycle

**Stage 1 — First-Order Pattern Extraction**
Input: Raw episodic memories from the last N hours/days
Output: Named patterns with evidence

Example:
"In the last 14 days, 7 of 9 strategic documents were opened but not edited."

**Stage 2 — Second-Order Insight Synthesis**
Input: First-order patterns + existing semantic memory
Output: Insights that connect patterns to context

Example:
"The document avoidance pattern correlates with weeks following board meetings.
Inference: post-board fatigue reduces capacity for independent strategic work."

**Stage 3 — Rule Generation**
Input: Insights with sufficient confidence
Output: Procedural rules that constrain future system behaviour

Example:
"Avoid scheduling strategic document work in 72 hours post-board.
Flag this pattern in next morning session."

## Processing Tiers

### Tier 1: Real-time (Haiku-class)
- Event classification as signals arrive
- Importance scoring for new episodic memories
- Anomaly detection (behaviour significantly deviates from model)
- Trigger: every signal event

### Tier 2: Periodic (Sonnet-class)
- Daily pattern extraction from accumulated episodic memories
- Email/communication pattern analysis
- Calendar density and meeting effectiveness scoring
- Trigger: end of work day, or every N hours

### Tier 3: Deep (Opus at max effort)
- Full recursive reflection cycle (all three stages)
- Personality model updates
- Strategic insight generation
- Memory consolidation (episodic → semantic promotion)
- Procedural rule generation and confidence updates
- Trigger: nightly, or weekly for deep synthesis

## The Nightly Engine

The nightly Opus run is the most important process in the entire system.

**Input:**
- All episodic memories since last reflection
- Current semantic memory (the full person model)
- Active procedural rules
- Core memory snapshot

**Process:**
1. Retrieve all episodic memories since last run
2. Cluster by category (communication, work, avoidance, decisions, meetings)
3. Extract first-order patterns per cluster
4. Cross-reference patterns against existing semantic memory
5. Synthesise second-order insights (what do these patterns MEAN?)
6. Generate or update procedural rules
7. Detect memory behaviour: stability, drift, contextual variance
8. Update semantic facts with new confidence scores
9. Promote high-confidence episodic clusters to semantic facts
10. Generate named patterns for tomorrow's morning briefing

**Output:**
- Updated semantic memory
- New/updated procedural rules
- Morning briefing content (named patterns, cognitive state assessment)
- Anomaly flags (significant behaviour changes)

**Quality bar:**
- Named patterns must cite specific evidence ("3 times this quarter")
- Insights must show reasoning chain, not just conclusions
- Rules must have clear trigger conditions, not vague guidelines
- The morning briefing must feel like a chief of staff who watched you for months

## Edge Function Design (Supabase)

The reflection engine runs as Supabase Edge Functions:
- `reflect-nightly` — full Opus reflection cycle
- `reflect-daily` — Sonnet-level daily pattern extraction
- `reflect-classify` — Haiku real-time signal classification

These functions read from and write to Supabase tables (memory tiers).
The Swift client polls for new reflection output and updates local state.

## OpenAI Context Engineering Patterns (2026)

Track three memory behaviour categories:
- **Stability:** Preferences that rarely change (chronotype, core values)
- **Drift:** Gradual shifts (evolving relationships, changing energy patterns)
- **Contextual variance:** Context-dependent preferences (Monday vs Friday energy)

The reflection engine must detect drift and update the model accordingly,
rather than treating all patterns as stable.

## Constraints

- Opus at max effort for nightly reflection — no cost cap on intelligence quality
- The reflection engine NEVER takes action — it only updates memory and generates
  content for the delivery layer
- Every generated pattern/insight must be traceable to episodic evidence
- Procedural rules have confidence scores that increase/decrease with evidence
- The system must handle the cold start: useful from day 1 via archetype priors,
  genuinely intelligent by month 3
