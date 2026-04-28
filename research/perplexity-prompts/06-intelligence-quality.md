---
purpose: Prove the 5-tier memory + 4-cron engine produces useful synthesis after data starts flowing — not empty rows + Opus calls returning null.
fire: After 24h of real data through Tier 0 (gives the engine something to chew)
depends_on: tonight's deploys + 24h of usage
---

# Prompt 6 — Intelligence quality (does the engine actually compound?)

## Prompt body (paste into Perplexity Deep Research)

Repo: ammarshah1n/time-manager-desktop @ `unified`. The 5-tier memory + 4-cron nightly engine is "architecturally complete" but had zero data through it until tonight's Trigger.dev deploy + Graphiti backfill.

Audit GOAL: prove the engine produces useful synthesis after data starts flowing, not empty rows + Opus calls returning null. Identify cold-start gaps and quality-degradation paths.

Stack to audit:
- **Tier 0**: tier0_observations + Tier0Writer + Voyage 1024-dim embeddings
- **Tier 1**: tier1_daily_summaries (nightly Opus 4.6 max effort)
- **Tier 2**: tier2_behavioural_signatures (weekly, 4-gate validation)
- **Tier 3**: tier3_personality_traits (monthly Opus Stage A + Stage B)
- **ACB-FULL** (10-12K) + **ACB-LIGHT** (500-800t)
- **5-dimension retrieval engine** (recency × importance × relevance × temporal × tier_boost)
- **4-cron pipeline**:
  - 2 AM consolidation (importance Haiku+Sonnet, conflict detection, Opus daily summary, ACB gen, self-improvement loop)
  - 5:15 AM refresh (overnight importance audit, summary addendum, ACB refresh)
  - 5:30 AM briefing (Opus two-pass adversarial)
  - Sunday 3 AM pruning (T0 archival/tombstone, T2 fading)
- **BOCPD change detection** (student-t predictive, CDI)

Score each:

**A) Cold-start handling.** Day 1: 0 T0 rows. Day 7: ~1k. Day 30: ~5k. What does the 2 AM consolidation produce on Day 1? Does it skip, fail, or generate a placeholder? Does the 5:30 AM Opus briefing have anything to brief on?

**B) Prompt quality.** Read every Opus prompt in the engine (consolidation, daily summary, weekly synthesis, monthly traits, two-pass briefing). For each:
- is it specific enough to produce useful output?
- does it include cached system prompt ≥1024t (caching threshold)?
- does it enforce thinking budget appropriately?
- does it fence user-content as untrusted?
- does it tell Opus what to output if there's nothing useful to say (anti-confabulation)?

**C) Tier 2 behavioural signatures 4-gate.** What are the 4 gates? Are they tight enough to reject noise but loose enough to detect real patterns in 7 days of data? File:line.

**D) Self-improvement loop.** Where does it live? What does it update? Does it actually run or is it a stub?

**E) Adversarial briefing two-pass.** Does the second pass actually critique + improve the first, or just rubber-stamp?

**F) Engagement self-correction.** What signal triggers it?

**G) Retrieval engine 5-dimension scoring.** Are the weights tuned or hardcoded defaults? Where does tier_boost come from? Is there a way to validate retrieval quality (recall@k against ground-truth queries)?

**H) Embedding pipeline robustness.** Voyage 1024 (Tier 0) + OpenAI 3072 (Tier 1-3). What happens when one provider is down? Mixed-dimension cosine similarity is invalid — how is that boundary policed?

For each: SHIPPABLE / DEGRADED / NOT-READY + fix (no new arch, file:line).

End with: **the 5 things to verify by hand on Day 7 of Yasser's data to declare the engine "actually compounding"** — concrete queries you can run against Supabase + Graphiti + USearch to prove it.

Constraints:
- No new architecture.
- Timed never acts on the world.
- Yasser is co-founder, not a modeled subject — no name-keyed corpora.
