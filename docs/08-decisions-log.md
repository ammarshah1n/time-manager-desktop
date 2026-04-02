# 08 — Architectural Decisions Log

## Decision #001 — JSON + Supabase over CoreData
**Date:** Pre-audit (established in codebase)
**Decision:** Local JSON via DataStore actor + Supabase Postgres for remote
**Why:** Simpler than CoreData, no migration complexity, natural Supabase integration,
JSON files are human-readable and debuggable
**Trade-off:** No built-in relational queries locally, no CloudKit sync path
**Do NOT reverse unless:** Local query performance becomes a bottleneck requiring
indexed lookups

## Decision #002 — TCA Dependencies only, not TCA state management
**Date:** Pre-audit (established in codebase)
**Decision:** Use TCA only for @Dependency injection. All state management via
vanilla SwiftUI (@State, @Binding, @StateObject)
**Why:** Full TCA (Reducers, Stores) is heavyweight for this app. @Dependency
gives clean dependency injection without the state management overhead.
**Trade-off:** No single source of truth for app state; state lives in views
**Do NOT reverse unless:** State management becomes unmanageable across >20 views

## Decision #003 — Observation-only constraint
**Date:** 2026-04-02 (mission realignment)
**Decision:** Timed NEVER takes action on the world. No sending emails, no
modifying calendars, no executing actions without human decision.
**Why:** Every AI assistant that promised actions failed (Humane, Rabbit, Clara, x.ai).
The constraint eliminates this entire failure class. The product's value is
intelligence depth, not action execution.
**Do NOT reverse:** NEVER. This is the product boundary. Non-negotiable.

## Decision #004 — Opus 4.6 at max effort for reflection engine
**Date:** 2026-04-02 (mission realignment)
**Decision:** No cost cap on the reflection engine's intelligence quality.
Use Claude Opus 4.6 at maximum effort for nightly analysis.
**Why:** The product's value IS the quality of its intelligence. Cutting model
quality to save money destroys the reason the product exists.
**Do NOT reverse unless:** A demonstrably superior model becomes available.

## Decision #005 — Three-tier memory architecture
**Date:** 2026-04-02
**Decision:** Episodic + Semantic + Procedural memory tiers, based on MemGPT
and Stanford Generative Agents research
**Why:** Proven architecture for compounding intelligence. Episodic stores raw
events, semantic stores learned facts, procedural stores operating rules.
The reflection engine promotes episodic → semantic via synthesis.
**Do NOT reverse unless:** Research Pack 02 reveals a strictly superior architecture.

## Decision #006 — Three-axis memory retrieval with dynamic weights
**Date:** 2026-04-02
**Decision:** Retrieval scoring = recency × importance × relevance, with
ACAN-style dynamic weight adjustment based on query context
**Why:** Static retrieval weights give poor results across different query types.
Dynamic adjustment (morning briefing weights recency high, pattern reports
weight importance high) produces better intelligence.
**Do NOT reverse unless:** A simpler scoring mechanism proves equivalent in quality.

## Decision #007 — Edge Functions for reflection processing
**Date:** 2026-04-02
**Decision:** Reflection engine runs as Supabase Edge Functions, not on-device
**Why:** Opus API calls require network. Edge Functions centralise the processing,
keep the Swift client thin, and allow the reflection engine to access the
full Supabase database directly.
**Do NOT reverse unless:** On-device models become capable of equivalent reflection quality.

## Decision #008 — Jina AI embeddings (1024-dim)
**Date:** 2026-04-01
**Decision:** Jina AI jina-embeddings-v3 for all embedding operations
**Why:** High quality, 1024 dimensions, no Israeli-linked vendor constraint
**Do NOT reverse unless:** A demonstrably superior embedding model emerges.
