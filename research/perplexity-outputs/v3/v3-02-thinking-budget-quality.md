# Extended Thinking Budget vs Output Quality: Frontier LLM Technical Build Brief
## Timed-Brain Nightly Pipeline — Thinking Budget Optimisation

***

## Executive Summary

The empirical relationship between extended thinking token budget and output quality follows a **logarithmic curve with non-monotonic deviations** — not a smooth monotone. The first 4K–8K thinking tokens produce the largest quality gains; beyond 16K–32K, marginal improvement drops below 5% for most synthesis tasks and can actively degrade performance on classification and adversarial review tasks. For Claude Opus 4.6 specifically, the `budget_tokens` API parameter is **deprecated** in favour of `thinking: {"type": "adaptive"}` with an `output_config: {"effort": "low|medium|high|max"}` parameter, where the model dynamically allocates compute — often achieving better results than a fixed high budget by avoiding the overthinking failure mode.

**Critical API/Pricing Correction:** The query references $15/M input, $75/M output. That is Claude Opus 4.1 (legacy). Claude Opus 4.6 is **$5/M input, $25/M output** as of February 2026. This is a 67% price reduction and fundamentally changes the cost-quality frontier. All cost calculations below use corrected pricing.[^1][^2][^3]

***

## Section 1: Empirical Scaling Relationship

### 1.1 The Logarithmic Law

Anthropic's technical documentation for Claude 3.7 Sonnet explicitly states that performance on mathematical reasoning tasks improves logarithmically with thinking tokens: the first additional thinking tokens help enormously, but returns diminish predictably. This result, observed on AIME 2024 benchmarks, has been consistently reproduced across multiple independent studies.[^4][^5]

The best-documented quantitative data comes from arXiv:2512.19585 ("Increasing the Thinking Budget is Not All You Need," December 2025), which systematically varied thinking budget from 0 to 24,000 tokens on AIME24 reasoning tasks using Qwen3-8B:[^6]

| Budget (tokens) | AIME24 Accuracy | Delta from Previous |
|---|---|---|
| 0 (no thinking) | 23.33% | Baseline |
| 2,000 | 46.67% | +23pp — highest ROI range |
| 4,000 | 46.67% | 0pp — first plateau |
| 6,000 | 63.33% | +17pp — second jump |
| 8,000 | 56.67% | −7pp — non-monotonic decline |
| 10,000 | 53.33% | −3pp — continued decline |
| 12,000 | 66.67% | +13pp — recovery |
| 20,000 | 73.33% | Near-ceiling for this config |
| 24,000 | 66.67% | −7pp — non-monotonic decline again |

This table demonstrates a critical architectural implication: **simply maximising budget_tokens does not monotonically improve quality**. The non-monotonic pattern appears consistently across model sizes, with "overthinking" generating incorrect explorations that overwrite initially correct reasoning.[^7][^8][^6]

The same study found that self-consistency (3× parallel sampling) plus a 6K budget reached **80% on AIME24**, decisively outperforming a single vanilla call with 24K budget (66.67%). Compute allocation strategy — parallel vs sequential — matters as much as raw budget.[^6]

For completeness: Claude 3.7 Sonnet with extended thinking enabled reaches **84.8%** on GPQA Diamond and **80.0%** on AIME 2024 (versus 68.0% and 23.3% respectively without extended thinking). These figures required the full extended thinking range (up to 64K with 256 parallel samples for GPQA), not a conservative single-call budget.[^5][^9]

### 1.2 Three Complexity Regimes

Apple Machine Learning Research ("The Illusion of Thinking," 2025) identified three distinct behavioural regimes across task complexity levels, tested on o3-mini, DeepSeek-R1, and other reasoning models:[^10][^7]

1. **Low complexity:** Standard LLMs outperform extended-thinking models. Extended thinking causes "overthinking" — the correct answer appears early in the trace and the model continues exploring, sometimes arriving at incorrect alternatives. Running extended thinking here is wasteful and slightly harmful.[^7]
2. **Medium complexity:** Extended thinking models show clear advantage. Chain-of-thought enables correct problem decomposition. This is the primary use case for thinking budgets.[^10]
3. **High complexity (above task ceiling):** Both reasoning and standard models collapse to near-zero accuracy. Extended reasoning effort declines spontaneously despite available budget — the model detects the task exceeds its parametric knowledge and shifts to shortcut-seeking.[^10][^7]

The implication for Timed-Brain: Tier 0 observation importance scoring is a **low-complexity** task. Tier 1 daily summary synthesis is **medium-complexity**. Tier 3 monthly trait synthesis may approach a regime where more budget does not help and different architecture (multi-call, RAG) is the correct lever.

### 1.3 Overthinking and Classification Degradation

OptimalThinkingBench (arXiv:2508.13141, accepted ICLR 2026) provides the strongest quantitative evidence against using thinking budgets for classification tasks:[^8][^11][^12]

- All 33 thinking models evaluated "overthink" on simple queries — generating at least 100 thinking tokens on queries that require none, with most generating over 700[^12]
- Overthinking shows zero accuracy improvement on simple queries and can actively degrade performance[^8][^12]
- No single model in the benchmark can "optimally think" — balancing accuracy and efficiency simultaneously[^11]
- The thinking-adjusted accuracy metrics (AUCOAA scores) are substantially lower than raw accuracy, indicating that thinking tokens are being consumed without proportional quality return[^12]

This is directly applicable to Phase 3.03 (importance scoring): the current Haiku 3.5 / temp 0.0 / no-thinking configuration in [NO-COST-CAP-AUDIT.md](https://github.com/ammarshah1n/Timed-Brain/blob/main/06%20-%20Context/NO-COST-CAP-AUDIT.md) is architecturally correct. Adding thinking to a 1–10 integer rating would likely degrade calibration and certainly waste tokens.

***

## Section 2: Claude Opus 4.6 API — Thinking Architecture

### 2.1 Deprecation of budget_tokens

As of Claude Opus 4.6 (released 5 February 2026), `thinking.type: "enabled"` and `budget_tokens` are **deprecated** on Opus 4.6 and Sonnet 4.6. Adaptive thinking is the recommended replacement. The deprecation is confirmed in the OpenRouter Claude 4.6 migration guide, which explicitly states: "For Claude 4.6 Opus and 4.6 Sonnet, OpenRouter now uses adaptive thinking (`thinking.type: 'adaptive'`) by default instead of budget-based thinking".[^13][^14][^15]

```python
# DEPRECATED on Opus 4.6 — do not use in new code
response = client.messages.create(
    model="claude-opus-4-6",
    max_tokens=32000,
    thinking={"type": "enabled", "budget_tokens": 16000},
    messages=[...]
)

# CURRENT — Anthropic-native SDK
response = client.messages.create(
    model="claude-opus-4-6",
    max_tokens=32000,
    thinking={"type": "adaptive"},
    output_config={"effort": "high"},   # low | medium | high | max
    messages=[...]
)

# OpenRouter compatibility format
response = client.messages.create(
    model="anthropic/claude-4.6-opus",
    reasoning={"enabled": True},   # adaptive by default on 4.6
    max_tokens=32000,
    messages=[...]
)
```

Budget_tokens still functions but is scheduled for removal in a future API version. Any pipeline using `budget_tokens` will need migration.[^14][^13]

### 2.2 Effort Parameter Semantics

The `effort` parameter is a **soft behavioural signal**, not a hard token ceiling. Per the official Anthropic API documentation and community analysis:[^3][^16][^17]

| Effort Level | Thinking Behaviour | Default | Notes |
|---|---|---|---|
| `max` | Always thinks; maximum depth. Opus 4.6 and Sonnet 4.6 only | — | ARC-AGI-2 benchmark run at `max` achieves higher scores than `high`[^18] |
| `high` | Always thinks; deep reasoning on complex tasks | **Default on Opus 4.6** | "Almost always think" — primary cause of token spend variance[^17] |
| `medium` | Moderate thinking; may skip for simple queries | — | For agentic tasks with cost/speed constraints |
| `low` | Minimises thinking; skips for simple tasks | — | Classification, lookups, high-volume low-stakes calls |

The default is `high`, meaning Opus 4.6 "will almost always think" on every request unless explicitly configured otherwise. This has significant cost implications: for production systems with cost ceilings, every call at `effort="high"` will consume substantial output tokens for thinking even on simple requests. The correct architecture is explicit effort routing per pipeline stage.[^17]

Adaptive thinking automatically enables **interleaved thinking** — the model can think between tool calls, making it especially effective for agentic pipeline stages.[^13]

### 2.3 Thinking Token Billing

Extended thinking tokens are billed as **output tokens** at the standard output rate ($25/MTok for Opus 4.6). Important operational note: "thinking tokens count towards rate limits" — the OTPM (output tokens per minute) rate limit includes both visible output and internal thinking. For the nightly pipeline, this matters: a single Phase 3.05 daily summary call at `effort="high"` with 10,000–16,000 thinking tokens + 2,000 response tokens = 12,000–18,000 output tokens consumed against OTPM limits.[^19][^3][^17]

Claude 4 models return a **summarised** version of thinking by default. The full internal reasoning trace is encrypted and returned in the `signature` field. Billing is against the full internal thinking length, not the summarised output visible in the response.[^16]

```python
# Display modes for thinking output
thinking={"type": "adaptive", "display": "summarized"}   # returns summary block
thinking={"type": "adaptive", "display": "omitted"}      # faster TTFT; no visible reasoning
# "omitted" is the default on Mythos Preview
```

### 2.4 Prompt Cache Compatibility

Switching between `adaptive` and `enabled`/`disabled` modes **breaks cache breakpoints** for message turns. System prompts and tool definitions remain cached regardless of mode changes. This means the current architecture in [prompt-engineering-ai-calls.md](https://github.com/ammarshah1n/Timed-Brain/blob/main/06%20-%20Context/prompt-engineering-ai-calls.md) that caches the system prompt and correction examples block is fully compatible with adaptive thinking migration.

The ACB-FULL is ~10,000–12,000 tokens. Cache writes at 1-hour TTL cost $10.00/MTok; cache reads cost $0.50/MTok (10% of input rate). For the 5am refresh and 5:30am briefing generation calls specified in [NO-COST-CAP-AUDIT.md](https://github.com/ammarshah1n/Timed-Brain/blob/main/06%20-%20Context/NO-COST-CAP-AUDIT.md), the ACB should be cached across both calls — a 90% cost reduction on the largest input component.[^3]

### 2.5 Promptable Thinking Behaviour

Adaptive thinking triggering is promptable — system prompt text steers how often the model chooses to think. For pipeline stages where thinking is never beneficial (Phase 3.03 importance scoring, Phase 6.02 ONA entity resolution), add to the system prompt:[^17][^3]

```
Extended reasoning is not required for this task. Respond directly 
with the structured output format specified. Do not use thinking.
```

This supplements the `effort="low"` parameter and provides a second-layer guard against inadvertent thinking token consumption.

***

## Section 3: Empirical Evidence by Task Type

### 3.1 Synthesis Tasks

**Definition for Timed-Brain:** Combining 7 days of behavioural Tier 1 data (Phase 7.01 weekly pattern detection), generating the morning briefing from ACB-FULL (Phase 4.01), and monthly trait synthesis (Phases 7.03/9.03).

Synthesis is the task category where extended thinking produces the clearest, most sustained gains. The canonical benchmark evidence:[^4][^5]

- **GPQA Diamond** (Claude 3.7 Sonnet, extended thinking): 84.8% vs 68.0% without thinking — a 16.8pp gain. This is the strongest published evidence for large quality gains from extended thinking on graduate-level synthesis tasks.[^9][^5]
- **AIME 2024** (various models): logarithmic improvement from 23% (no thinking) to 73% (20K thinking, vanilla), with the steepest gain in the 0–8K range.[^6]
- **MATH-500**: DeepSeek-R1 with extended reasoning reaches 97.3%; Claude 3.7 Sonnet 96.2% — vs ~60–70% without extended reasoning.[^5]
- **ARC-AGI-2** (Claude Sonnet 4.6): `effort="max"` achieves higher scores than `effort="high"` (specific delta reported as measurable).[^18]

**Quality ceiling for long-context synthesis:** Anthropic's documentation notes that above 32K thinking tokens, the model "may not use the entire budget" for most tasks. This is precisely the behaviour that adaptive thinking formalises: at `effort="max"`, Opus 4.6 allocates what it determines necessary rather than burning toward a ceiling.

For Timed-Brain's use case (7 days of behavioural data → narrative synthesis), the quality ceiling is empirically in the **16K–32K range** for daily/weekly synthesis. The evidence for 64K outperforming 32K on a single call is limited to GPQA-style tasks with parallel sampling (256 independent completions) — not narrative generation. For Phase 7.03 monthly trait synthesis, `effort="max"` is justified, but actual thinking consumed will likely stabilise below 64K for most runs and can be monitored via `response.usage.output_tokens`.

**Evidence gap:** No published study specifically measures thinking budget vs quality for longitudinal behavioural narrative synthesis (as opposed to single-question STEM reasoning). All canonical benchmarks are STEM/mathematical with ground-truth answers. The logarithmic scaling assumption is the best available approximation.

### 3.2 Classification Tasks

**Definition for Timed-Brain:** Phase 3.03 importance scoring (1–10 integer rating), email classification (Loop 1 in [ai-learning-loops-architecture-v2.md](https://github.com/ammarshah1n/Timed-Brain/blob/main/06%20-%20Context/ai-learning-loops-architecture-v2.md)), entity resolution (Phase 6.02).

The research consensus is unambiguous: **extended thinking does not improve and often actively degrades classification accuracy**.[^8][^12][^10]

Key findings:
- OptimalThinkingBench (ICLR 2026): all 33 evaluated thinking models overthink on simple queries; thinking tokens consumed without accuracy gain[^11][^12][^8]
- Apple "Illusion of Thinking": on low-complexity tasks, standard non-thinking models outperform thinking models with more token-efficient inference[^7][^10]
- The mechanism: extended thinking on classification introduces spurious reasoning chains that reverse initially correct outputs; models pattern-match on superficial features (domain keywords, numerical tokens) rather than the underlying signal[^12][^7]

**Minimum budget where quality plateaus:** For 1–10 integer scoring and three-class email classification, the quality plateau is at **zero thinking tokens**. The correct configuration is `effort="low"` (or no `output_config` key at all with `thinking` omitted) coupled with a system prompt directive not to think. Use Haiku 4.5 rather than Opus 4.6 for these calls — same accuracy ceiling, 5× cheaper output rate.

### 3.3 Contradiction / Anomaly Detection

**Definition for Timed-Brain:** Phase 3.04 (detecting contradictions between new observations and existing Tier 2/3 memory, upgraded from Haiku to Sonnet 4 with 8K thinking in [NO-COST-CAP-AUDIT.md](https://github.com/ammarshah1n/Timed-Brain/blob/main/06%20-%20Context/NO-COST-CAP-AUDIT.md)).

Contradiction and anomaly detection is a **hybrid medium-complexity task**: it requires cross-sentence logical inference (beyond classification) but does not require the deep multi-step synthesis of pattern extraction.[^20]

Agent-centric text anomaly detection (arXiv:2602.23729, 2026) demonstrates that anomaly detection tasks "demand cross-sentence logical inference and resist pattern-matching shortcuts" — directly validating the Phase 3.04 upgrade rationale. The NO-COST-CAP-AUDIT reasoning ("Haiku flattens nuanced context-dependent deviations; Sonnet with thinking catches them") is well-supported by the medium-complexity regime evidence from Apple's study.[^20][^10]

**Recommended budget:** 4K–8K actual thinking tokens provides sufficient reasoning depth for detecting behavioural context deviations. The existing Phase 3.04 configuration of Sonnet 4 + 8K budget is well-calibrated. Migration to Sonnet 4.6 + `effort="medium"` is appropriate, with upgrade to `effort="high"` when `anomaly_count > 0` from Phase 3.03 output.

### 3.4 Adversarial Self-Critique / ACB Review

**Definition for Timed-Brain:** ACB update quality review (Phase 3.07), any self-improvement loop where the model reviews its own prior outputs.

This task type has the most complex thinking budget relationship and the highest documented risk of **rubber-stamping** — sycophantic self-approval without genuine critique.[^21][^22]

The research evidence is directionally clear:
- "Challenging the Evaluator" (ACL Findings EMNLP 2025, arXiv:2509.16533): LLMs are more likely to endorse a user's counterargument when framed as a follow-up (vs simultaneous presentation); inclusion of reasoning in feedback increases likelihood of capitulation; models with incorrect initial answers are more susceptible to persuasion[^22][^21]
- Sycophancy increases with reasoning depth: "models are more readily swayed by casually phrased feedback than by formal critiques, even when the casual input lacks justification"[^21]
- The mechanism relevant to self-critique: high thinking budgets cause the model to construct elaborate post-hoc rationalisations for the output it is reviewing, rather than maintaining independent critical distance — the longer the reasoning trace, the more internally consistent the model's justification of its own prior work[^22]

**Recommended architecture for adversarial review:** Two-call separation rather than a single call with high thinking budget:

```python
# Call 1: Generation
generation_response = client.messages.create(
    model="claude-opus-4-6",
    output_config={"effort": "high"},
    thinking={"type": "adaptive"},
    system=GENERATION_SYSTEM_PROMPT,
    messages=[{"role": "user", "content": generation_prompt}]
)
acb_draft = generation_response.content[-1].text

# Call 2: Adversarial critique — separate session, fresh context
critique_response = client.messages.create(
    model="claude-opus-4-6",
    output_config={"effort": "medium"},  # medium not high — avoids rationalisation
    thinking={"type": "adaptive"},
    system="""You are an adversarial auditor reviewing an Active Context Buffer (ACB).
    Identify: (1) patterns claimed with <3 data points, (2) over-confident trait 
    assignments (confidence >0.8 on fewer than 5 sessions), (3) contradictions 
    with Tier 3 traits that have been confirmed for >30 days, (4) missing anomalies
    that appear in the Tier 1 source data. Output as structured JSON critique.""",
    messages=[{"role": "user", "content": f"ACB to audit:\n{acb_draft}\n\nTier 1 source:\n{tier1_data}"}]
)
```

The key insight from the sycophancy literature: presenting both the original output and the critique source simultaneously (as in the two-call architecture above) produces substantially less rubber-stamping than a conversational follow-up. The "Challenging the Evaluator" paper found that the same argument is more likely to cause model capitulation when framed as a user rebuttal than when presented for simultaneous evaluation — the two-call structure exploits this.[^21][^22]

***

## Section 4: Cost-Quality Frontier for Claude Opus 4.6

### 4.1 Verified Pricing (April 2026)

| Component | Rate |
|---|---|
| Input tokens (≤200K context) | $5.00 / MTok |
| Output tokens (≤200K context) | $25.00 / MTok |
| Cache write (5 min TTL) | $6.25 / MTok |
| Cache write (1 hour TTL) | $10.00 / MTok |
| Cache reads | $0.50 / MTok (10% of input rate) |
| Batch API input | $2.50 / MTok (50% discount) |
| Batch API output | $12.50 / MTok |
| Input (>200K context) | $10.00 / MTok (full request repriced at threshold) |
| Output (>200K context) | $37.50 / MTok |
| Thinking tokens | Billed as output tokens ($25.00/MTok) |

Sources: MetaCTO pricing breakdown, PECollective rate table, Milvus Opus 4.6 reference.[^23][^1][^3]

**Rate limit interaction:** Thinking tokens count toward OTPM (output tokens per minute) rate limits. For Tier 4 API access (typical for early-stage projects), default OTPM limits are ~8,000–40,000 tokens/minute depending on tier. A single Phase 7.01 weekly pattern detection call at `effort="max"` with 30,000 thinking tokens consumes a large fraction of per-minute output capacity. Schedule high-thinking calls with rate limit headroom.[^19][^17]

### 4.2 Per-Call Cost Calculations (Corrected for Opus 4.6)

The cost formula per call is:

\[ C_{call} = \frac{I_{uncached} \times 5 + I_{cached} \times 0.5 + (T + O) \times 25}{10^6} \]

where \(I_{uncached}\) is non-cached input tokens, \(I_{cached}\) is cached input tokens, \(T\) is thinking tokens (actual consumed), and \(O\) is response output tokens.

**Phase 3.03 — Importance Scoring (Haiku 4.5, no thinking)**
- Input: ~500 tokens (cached system + observation)
- Output: ~50 tokens
- Cache read: $0.50/MTok; Haiku output: $5.00/MTok
- **Per call: ~$0.00025 + $0.00025 = $0.0005 | Weekly (7 × ~200 obs): ~$0.70**

**Phase 3.04 — Conflict Detection (Sonnet 4.6, effort=medium)**
- Input: ~2,000 tokens; Thinking (medium): est. 3,000–6,000 tokens; Output: ~500 tokens
- Sonnet 4.6 rates: $3/$15 per MTok
- **Per call: ~$0.06–0.10 | Weekly: ~$0.45–0.70**

**Phase 3.05 — Daily Summary (Opus 4.6, effort=high)**
- Input: ~3,000 tokens (200 observations + system); Thinking (high): est. 8,000–16,000 tokens; Output: ~2,000 tokens
- **Per call: ~$0.27–0.52 | Weekly: ~$1.90–3.64**

**Phase 3.07 — ACB Update (Opus 4.6, effort=high + critique call effort=medium)**
- Generation call: Input ~8,000 tokens (existing ACB + summaries); Thinking ~6,000–12,000; Output ~10,000 tokens
- Critique call: Input ~12,000 tokens (draft + source); Thinking ~3,000–6,000; Output ~1,000 tokens
- **Combined per run: ~$0.60–1.00 | Weekly: ~$4.20–7.00**

**Phase 4.01 — Morning Briefing (Opus 4.6, effort=high, ACB-FULL cached)**
- Cached input: ~12,000 tokens ACB-FULL at $0.50/MTok; Non-cached user: ~2,000 tokens
- Thinking (high): est. 12,000–20,000 tokens; Output: ~3,000 tokens
- **Per call: ~$0.44–0.65 | Weekly: ~$3.08–4.55**

**Phase 7.01 — Weekly Pattern Detection (Opus 4.6, effort=max)**
- Input: ~15,000 tokens (7 daily summaries + system); Thinking (max): est. 20,000–40,000 tokens; Output: ~5,000 tokens
- **Per call: ~$0.75–1.33 | Once weekly**

**Phase 7.03/9.03 — Monthly Trait Synthesis (Opus 4.6, effort=max)**
- Input: ~10,000 tokens; Thinking (max): est. 30,000–60,000 tokens; Output: ~5,000 tokens
- **Per call: ~$1.00–1.90 | ~4×/month = ~$1.50/week averaged**

### 4.3 Revised Weekly Pipeline Cost (Corrected from NO-COST-CAP-AUDIT)

The [NO-COST-CAP-AUDIT.md](https://github.com/ammarshah1n/Timed-Brain/blob/main/06%20-%20Context/NO-COST-CAP-AUDIT.md) estimated ~$63/week. The revised estimate at Opus 4.6 pricing is:

| Stage | Frequency | Weekly Cost (est.) |
|---|---|---|
| Phase 3.03 Importance Scoring (Haiku) | 7×/day × ~200 obs | ~$0.70 |
| Phase 3.04 Conflict Detection (Sonnet) | 7× | ~$0.55 |
| Phase 3.05 Daily Summary (Opus, effort=high) | 7× | ~$2.50 |
| Phase 3.07 ACB Update + Critique (Opus) | 7× | ~$5.40 |
| Phase 4.01 Morning Briefing (Opus, ACB cached) | 7× | ~$3.75 |
| Phase 5.04 Thin-Slice Inference (Opus) | 1× during onboarding | ~$0.50 one-time |
| Phase 7.01 Weekly Patterns (Opus, effort=max) | 1× | ~$1.00 |
| Phase 7.03 Monthly Synthesis (Opus, effort=max) | ~1×/week amortised | ~$1.50 |
| Email classification + Loop 1 (Haiku) | Daily | ~$1.50 |
| Embedding (text-embedding-3-large, Tier 1–3) | Daily | ~$1.00 |
| voyage-context-3 (Tier 0, ~200 obs/day) | Daily | ~$2.00 |
| Gemini 2.0 Flash audio (Phase 10, 8h/day) | Daily | ~$5.00 |
| Infrastructure (Supabase, etc.) | — | ~$15.00 |
| **Total** | | **~$40–45/week** |

This is ~$18–23/week lower than the NO-COST-CAP-AUDIT estimate because (a) Opus 4.6 pricing is $5/$25 not $15/$75 and (b) adaptive thinking typically consumes less than a fixed budget ceiling. Against the £100–150/week budget constraint, this leaves ~£60–90/week headroom for growth (additional users, stress testing, Phase 13 advanced intelligence).[^1]

### 4.4 Diminishing Returns Thresholds

Based on available benchmark evidence, the <5% quality improvement threshold per doubling of thinking budget occurs at approximately:

| Task Type | Approx. Threshold | Config Notes |
|---|---|---|
| Classification (importance, email) | 0 tokens | No thinking; use effort=low on Haiku |
| Simple contradiction detection | ~4K tokens | 4K→8K marginal; effort=medium covers it |
| Daily narrative synthesis (7-day) | ~16K tokens | 16K→32K likely <5% on narrative quality |
| Weekly cross-domain synthesis | ~32K tokens | effort=max appropriate; adaptive will settle here |
| Monthly trait synthesis | ~32K–48K tokens | effort=max; monitor actual consumption |
| GPQA-style scientific QA (with parallel sampling) | ~64K per sample | Only relevant with parallel completions |
| Problems above task ceiling | N/A | Zero improvement; architectural change needed |

**Critical caveat:** All thresholds are derived from STEM/mathematical benchmarks. The specific thresholds for behavioural narrative synthesis tasks have no direct peer-reviewed evidence. The practical recommendation is to deploy `effort="high"` on synthesis stages, monitor `response.usage.output_tokens` across 7–14 days, and derive the actual thinking token consumption distribution before deciding whether to upgrade to `effort="max"`.

***

## Section 5: Dynamic Budget Allocation Framework

### 5.1 Published Approaches

**DAST: Difficulty-Adaptive Slow Thinking (EMNLP 2025, arXiv:2503.04472)**: Introduces the Token Length Budget (TLB) metric — a difficulty quantification that scales target response length with problem complexity. Key results: ~58.5% length reduction on Level 1 problems; ~40.8% reduction on hardest Level 5 problems, with no accuracy degradation on complex problems. Implemented via preference optimisation (SimPO), making it a training-time solution. The TLB concept informs the prompt-level difficulty signals described in Section 5.2 below.[^24][^25][^26]

**Conformal Thinking (arXiv:2602.03814, February 2026)**: A principled risk-control framework from Johns Hopkins/Apple. Re-frames thinking budget as a statistical stopping problem: distribution-free calibration from a validation set maps user-specified error tolerance to optimal stopping criteria. Key result: same accuracy as fixed budgets with substantially fewer tokens. Directly applicable as a monitoring framework — measure confidence or output token consumption across pipeline runs, then calibrate adaptive effort settings. Note: the paper explicitly observes that "adaptive thinking does not alleviate the practical challenge of setting reasoning budget; it only converts the problem of setting a token budget into setting a threshold".[^27]

**Snell et al. (arXiv:2408.03314, 2024)**: "Scaling LLM Test-Time Compute Optimally" — foundational result that question difficulty is the correct sufficient statistic for compute-optimal allocation. Key findings: effectiveness of test-time compute strategies "critically varies depending on the difficulty of the prompt"; using difficulty as the allocation signal achieves **4× better compute efficiency** vs best-of-N baseline. For a given difficulty level, there exists an optimal ratio of sequential thinking vs parallel sampling.[^28][^29][^30]

**Budget Guidance (arXiv:2506.13752, 2025)**: Lightweight Gamma-distribution predictor modelling remaining thinking length, guiding generation without fine-tuning. Achieves 26% accuracy gain on MATH-500 under tight budgets; maintains competitive accuracy with 63% of tokens used by full-thinking model. Not directly deployable on Opus 4.6 without API access, but the underlying principle (predict remaining reasoning need from current context) is implemented natively by Opus 4.6's adaptive mode.[^31][^32]

**BudgetThinker (arXiv:2508.17196, 2025)**: Control tokens inserted during inference to enforce budget constraints. Achieves 4.2% accuracy improvement over vanilla reasoning model and 5.7% over ThinkPrune on MATH-500, with precise budget adherence. Requires SFT + RL training; not directly applicable to Opus 4.6.[^33]

### 5.2 Difficulty Signals for Timed-Brain

The `effort` parameter in Opus 4.6's adaptive thinking is the native implementation of difficulty-proportional compute allocation. Observable input signals enable routing without fine-tuned classifiers:

**Phase 3.04 Conflict Detection — effort router:**
```python
def conflict_detection_effort(context: dict) -> str:
    # Signals: prior anomaly count, number of Tier 2 records implicated
    if context["anomaly_count"] == 0 and context["tier2_records_queried"] < 3:
        return "medium"   # low novelty; standard reasoning sufficient
    return "high"         # active anomalies; full depth
```

**Phase 3.05 Daily Summary — effort router:**
```python
def daily_summary_effort(context: dict) -> str:
    # Signals: observation count, anomaly flags, new ONA entities, calendar density
    high_complexity = (
        context["anomaly_count"] > 3 or
        context["new_tier2_candidate"] is True or
        context["new_ona_entities"] > 0 or
        context["observation_count"] > 200
    )
    return "max" if high_complexity else "high"
```

**Phase 4.01 Morning Briefing — effort router:**
```python
def morning_briefing_effort(context: dict) -> str:
    # Signals: ACB delta since last briefing (low delta = low novelty day)
    # acb_delta_tokens: approximate token count of changes since prior briefing
    if context["acb_delta_tokens"] < 300:
        return "medium"   # minimal new information; deep thinking not warranted
    return "high"
```

**Phase 7.01/7.03/9.03 — always `effort="max"`** — the cross-domain compounding intelligence is the product; the asymmetry of consequence vs cost justifies maximum depth unconditionally.

### 5.3 Full Implementation Pattern

```python
import anthropic
from typing import Literal

EffortLevel = Literal["low", "medium", "high", "max"]
client = anthropic.Anthropic()

EFFORT_ROUTERS = {
    "importance_scoring": lambda ctx: "low",
    "email_classification": lambda ctx: "low",
    "entity_resolution": lambda ctx: "low",
    "conflict_detection": lambda ctx: (
        "medium" if ctx.get("anomaly_count", 0) == 0 else "high"
    ),
    "daily_summary": lambda ctx: (
        "max" if (ctx.get("anomaly_count", 0) > 3 or ctx.get("new_tier2_candidate")) 
        else "high"
    ),
    "acb_update": lambda ctx: "high",
    "morning_briefing": lambda ctx: (
        "medium" if ctx.get("acb_delta_tokens", 999) < 300 else "high"
    ),
    "weekly_patterns": lambda ctx: "max",
    "monthly_synthesis": lambda ctx: "max",
}

def build_pipeline_call(
    stage: str,
    context: dict,
    model: str,
    system: list,
    user_message: str,
    max_tokens: int = 32000,
    use_thinking: bool = True
):
    effort = EFFORT_ROUTERS.get(stage, lambda ctx: "high")(context)
    
    kwargs = {
        "model": model,
        "max_tokens": max_tokens,
        "system": system,
        "output_config": {"effort": effort},
        "messages": [{"role": "user", "content": user_message}]
    }
    
    if use_thinking and effort != "low":
        kwargs["thinking"] = {
            "type": "adaptive",
            "display": "summarized"
        }
    
    response = client.messages.create(**kwargs)
    
    # Log actual thinking consumption for calibration
    thinking_tokens_approx = response.usage.output_tokens - estimate_response_tokens(response)
    log_thinking_consumption(stage, effort, thinking_tokens_approx)
    
    return response

# Example: Phase 3.05 daily summary call
response = build_pipeline_call(
    stage="daily_summary",
    context={"anomaly_count": 1, "observation_count": 180},
    model="claude-opus-4-6",
    system=[
        {
            "type": "text",
            "text": DAILY_SUMMARY_SYSTEM_PROMPT,
            "cache_control": {"type": "ephemeral"}
        }
    ],
    user_message=tier0_observations_xml,
    max_tokens=16000
)
```

***

## Section 6: Pipeline-Stage Recommendations

### Consolidated Configuration Table

| Stage | Current (NO-COST-CAP-AUDIT) | Recommended Migration | Effort | Two-Call? | Evidence |
|---|---|---|---|---|---|
| **3.03** Importance Scoring | Haiku 3.5, no thinking | `claude-haiku-4-5`, no thinking, effort=low | `low` | No | [^8][^12] |
| **3.04** Conflict Detection | Sonnet 4 + 8K thinking | `claude-sonnet-4-6`, adaptive | `medium`/`high` (routed) | No | [^20] |
| **3.05** Daily Summary | Opus 4.5 + 16K thinking | `claude-opus-4-6`, adaptive | `high` (default), `max` on anomaly days | No | [^6][^5] |
| **3.07** ACB Update | Opus 4.5 + 8K thinking | `claude-opus-4-6`, adaptive + separate critique call | `high` + critique at `medium` | **Yes** | [^21][^22] |
| **4.01** Morning Briefing | Opus 4.5 + 32K thinking | `claude-opus-4-6`, adaptive, ACB-FULL cached | `high` (default), `medium` on low-novelty days | No | [^3] |
| **5.04** Thin-Slice Inference | Opus 4.5 + 16K thinking | `claude-opus-4-6`, adaptive | `high` | No | [^10] |
| **6.02** ONA Entity Resolution | Sonnet 4, no thinking | `claude-sonnet-4-6`, no thinking, effort=low | `low` | No | [^8][^12] |
| **7.01** Weekly Patterns | Opus 4.5 + 32K thinking | `claude-opus-4-6`, adaptive | `max` | No | [^25][^29] |
| **7.03/9.03** Monthly Synthesis | Opus 4.6 + 64K thinking | `claude-opus-4-6`, adaptive | `max` | No | [^5] |

### Critical Notes Per Stage

**Phase 3.05 Daily Summary — the Foundation Stage:**
The NO-COST-CAP-AUDIT rationale is correct: "A Haiku-generated summary that misses a nuanced anomaly poisons the entire compounding chain permanently". The adaptive `effort="high"` is the right default — equivalent to the prior 16K budget. Trigger `effort="max"` on days where Phase 3.04 detects confirmed contradictions or where `new_tier2_candidate` is flagged. The logarithmic scaling evidence suggests the quality gap between no-thinking and 8K thinking is ~40pp on AIME-class tasks; the gap between 8K and 16K narrows to ~15pp; between 16K and 32K to ~5pp. For narrative synthesis, these gaps will be smaller but the directional relationship holds.[^6]

**Phase 3.07 ACB Update — sycophancy mitigation:**
The ACB update involves synthesising the model's own prior outputs. Per the sycophancy evidence, the two-call separation prevents the model from reasoning toward justification of its own work. The critique system prompt must name **specific failure modes** (over-claimed pattern confidence, patterns with fewer than 3 data points, contradictions with confirmed Tier 3 traits) — vague critique instructions activate the sycophancy mechanism rather than suppressing it.[^22][^21]

**Phase 4.01 Morning Briefing — cache arithmetic:**
The 5am refresh and 5:30am generation calls share the same ACB-FULL. If the refresh does not modify the ACB, a 1-hour TTL cache write at 2am covers both calls. The 90% cache read discount on ~12,000 ACB input tokens saves ~$0.054/day ($0.60/week) — small but cumulative. Ensure `cache_control: {"type": "ephemeral"}` is set on the ACB block in both calls.[^3]

**Phase 7.01 Weekly Patterns — `effort=max` is unconditional:**
The cross-domain correlation signal (calendar fragmentation + slower email + shorter keystroke sessions on Tuesdays) requires the model to hold ~15,000 tokens of working context and reason across all seven daily summaries simultaneously. The Snell et al. evidence that compute-optimal allocation for hard prompts achieves 4× better efficiency than best-of-N means the single weekly `effort="max"` call is more compute-efficient than multiple smaller calls. The ~$1/week cost is irrelevant against the intelligence value.[^29]

***

## Section 7: Evidence Gaps and Open Questions

The following claims lack direct empirical validation for the Timed-Brain use case. Where stated below, do not treat as evidence.

1. **Long-context narrative synthesis at >16K thinking tokens:** All published evidence above 16K thinking tokens is for STEM reasoning with ground-truth answers. For narrative synthesis tasks (no ground truth), the quality ceiling cannot be determined from existing benchmarks. Deploy adaptive thinking, monitor actual token consumption across 14 production runs, and analyse output quality versus consumption empirically.

2. **Sycophancy in Opus 4.6 specifically:** The sycophancy/rubber-stamping literature was measured on GPT-class models and earlier LLMs. Whether Opus 4.6 with adaptive thinking is more or less susceptible than those baselines is not published. The two-call architecture is the conservative architectural mitigation regardless.[^21][^22]

3. **Adaptive thinking vs fixed budget on narrative generation:** Anthropic states that adaptive thinking can drive better performance than `budget_tokens` for "bimodal tasks," but no benchmark data quantifying this claim on narrative workloads is publicly available.[^13]

4. **Effort level → actual token consumption mapping:** There is no published mapping from effort levels to expected thinking token ranges for Opus 4.6. The consumption estimates in Section 4.2 are derived from proportional reasoning against benchmark data. Instrument `response.usage.output_tokens` in production and maintain a calibration log per stage.

5. **Non-monotonicity persistence at Opus scale:** The non-monotonic degradation pattern documented in arXiv:2512.19585 was observed on Qwen3-8B. Whether Opus 4.6 (substantially larger) exhibits the same non-monotonic dips at equivalent relative budgets is unknown. Adaptive thinking bypasses this risk by letting the model decide the budget; it does not bypass the risk of overthinking-driven quality degradation, which persists at model scale per OptimalThinkingBench.[^8][^6]

***

## Appendix A: API Quick Reference

```python
# Complete production call pattern for Opus 4.6
import anthropic

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

# ── Phase 4.01 Morning Briefing ─────────────────────────────────────────────
briefing_response = client.messages.create(
    model="claude-opus-4-6",
    max_tokens=8000,                     # hard cap: thinking + response ≤ max_tokens
    thinking={
        "type": "adaptive",
        "display": "summarized"          # returns summarised thinking block
    },
    output_config={"effort": "high"},
    system=[
        {
            "type": "text",
            "text": STATIC_SYSTEM_PROMPT,
            "cache_control": {"type": "ephemeral"}   # 5-min TTL cache
        },
        {
            "type": "text",
            "text": acb_full_xml,
            "cache_control": {"type": "ephemeral"}   # cache the ACB separately
        }
    ],
    messages=[{"role": "user", "content": daily_context_message}]
)

# Extract thinking summary and output
for block in briefing_response.content:
    if block.type == "thinking":
        thinking_summary = block.thinking
    elif block.type == "text":
        briefing_text = block.text

# Monitor actual output token consumption
actual_output_tokens = briefing_response.usage.output_tokens
# thinking_tokens_approx ≈ actual_output_tokens - len(briefing_text_tokens)


# ── Phase 3.03 Importance Scoring ─────────────────────────────────────────
scoring_response = client.messages.create(
    model="claude-haiku-4-5",            # not Opus — 5× cheaper output
    max_tokens=50,
    # No thinking parameter — omitted = disabled
    output_config={"effort": "low"},
    system=[
        {
            "type": "text",
            "text": IMPORTANCE_SYSTEM_PROMPT,
            "cache_control": {"type": "ephemeral"}
        }
    ],
    messages=[{"role": "user", "content": observation_json}],
    tools=[IMPORTANCE_SCORING_TOOL],
    tool_choice={"type": "any"}
)


# ── Phase 3.07 ACB Update — Two-Call Pattern ────────────────────────────────
# Call 1: Generate ACB draft
acb_draft_response = client.messages.create(
    model="claude-opus-4-6",
    max_tokens=16000,
    thinking={"type": "adaptive"},
    output_config={"effort": "high"},
    system=[{"type": "text", "text": ACB_GENERATION_SYSTEM}],
    messages=[{"role": "user", "content": acb_generation_prompt}]
)
acb_draft = acb_draft_response.content[-1].text

# Call 2: Adversarial critique — fresh context, separate call
critique_response = client.messages.create(
    model="claude-opus-4-6",
    max_tokens=4000,
    thinking={"type": "adaptive"},
    output_config={"effort": "medium"},   # not high — avoids rationalisation
    system=[{"type": "text", "text": ACB_CRITIQUE_SYSTEM}],
    messages=[{
        "role": "user",
        "content": f"""ACB to audit:\n{acb_draft}\n\nTier 1 source data:\n{tier1_data}
        
        Identify: patterns with <3 data points, confidence>0.8 with <5 sessions,
        contradictions with confirmed Tier 3 traits (valid_to IS NULL), 
        anomalies in Tier 1 that are absent from ACB. Return as JSON."""
    }]
)
```

### Model IDs and Pricing (April 2026)

| Model ID | Input $/MTok | Output $/MTok | Adaptive Thinking | Max Effort |
|---|---|---|---|---|
| `claude-opus-4-6` | $5.00 | $25.00 | ✅ | ✅ `max` |
| `claude-sonnet-4-6` | $3.00 | $15.00 | ✅ | ✅ `max` |
| `claude-haiku-4-5` | $1.00 | $5.00 | Limited | — |
| `claude-opus-4-5` | $5.00 | $25.00 | ❌ (use `budget_tokens`) | — |
| `claude-opus-4-1` | $15.00 | $75.00 | ❌ | — |

Sources: MetaCTO, OpenRouter, PECollective, OpenClaw GitHub issue.[^2][^34][^1][^3]

**`budget_tokens` availability:** Still accepted on Opus 4.6 and Sonnet 4.6 but deprecated and scheduled for removal. On Opus 4.5 and earlier, `budget_tokens` under `thinking.type: "enabled"` remains the correct interface — do not migrate these to `adaptive`.[^14][^13]

***

## Appendix B: Monitoring and Calibration

Deploy the following to empirically validate thinking consumption against quality across Timed-Brain pipeline runs:

```sql
-- Add to production schema
CREATE TABLE pipeline_thinking_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stage TEXT NOT NULL,
  effort_level TEXT NOT NULL,
  actual_output_tokens INT,        -- from response.usage.output_tokens
  response_text_tokens INT,        -- estimated from output text length
  thinking_tokens_approx INT,      -- actual_output_tokens - response_text_tokens
  input_tokens INT,
  cached_tokens INT,
  call_cost_usd NUMERIC(10,6),
  quality_flag TEXT,               -- NULL | 'rubber_stamp' | 'incomplete' | 'anomaly_missed'
  executive_id UUID REFERENCES executives(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Weekly calibration query: thinking token distribution by stage
SELECT 
  stage,
  effort_level,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY thinking_tokens_approx) AS p50_thinking,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY thinking_tokens_approx) AS p95_thinking,
  AVG(call_cost_usd) AS avg_cost,
  COUNT(*) FILTER (WHERE quality_flag IS NOT NULL) AS quality_issues
FROM pipeline_thinking_audit
WHERE created_at > NOW() - INTERVAL '14 days'
GROUP BY stage, effort_level
ORDER BY AVG(thinking_tokens_approx) DESC;
```

After 14 days of production data, use this table to:
1. Confirm that Phase 3.03/6.02 `effort="low"` calls are consuming zero thinking tokens
2. Verify that Phase 3.05/4.01 `effort="high"` calls are consuming 6K–20K thinking tokens (expected range)
3. Identify whether `effort="max"` on Phase 7.01 is consuming more than 32K tokens (if so, quality ceiling has been reached at a lower threshold than expected)
4. Set `effort="medium"` thresholds empirically based on actual p50 consumption matching expected ranges

---

## References

1. [Claude API Pricing 2026: Full Anthropic Cost Breakdown - MetaCTO](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration) - Claude Opus 4.6 ($5 input / $25 output per million tokens) is Anthropic's most capable model, releas...

2. [Claude Opus 4.6 - API Pricing & Providers - OpenRouter](https://openrouter.ai/anthropic/claude-opus-4.6) - Opus 4.6 is Anthropic's strongest model for coding and long-running professional tasks. $5 per milli...

3. [Claude API Pricing 2026 - Sonnet, Opus & Haiku Per Token](https://pecollective.com/tools/anthropic-api-pricing/) - Claude Sonnet 4.6: $3/$15 per 1M tokens. Opus 4.6: $5/$25. Haiku 4.5: $1/$5. Batch discounts, prompt...

4. [Claude 3.7 Sonnet debuts with “extended thinking” to ... - Ars Technica](https://arstechnica.com/ai/2025/02/claude-3-7-sonnet-debuts-with-extended-thinking-to-tackle-complex-problems/) - Anthropic announced Claude 3.7 Sonnet, a new AI language model with a simulated reasoning (SR) capab...

5. [Claude 3.7 Sonnet: How it Works, Use Cases & More | DataCamp](https://www.datacamp.com/blog/claude-3-7-sonnet) - Reasoning and math. In graduate-level reasoning (GPQA Diamond), Claude 3.7 Sonnet scores 68.0% in st...

6. [Token Budget Control Patterns for LLMs | Stop Overthinking](https://www.buildmvpfast.com/blog/token-budget-control-llm-overthinking-cost-optimization-2026) - The paper “Increasing the Thinking Budget is Not All You Need” (arXiv:2512.19585) found something co...

7. [The Illusion of Thinking: What the Apple AI Paper Says About LLM ...](https://arize.com/blog/the-illusion-of-thinking-what-the-apple-ai-paper-says-about-llm-reasoning/) - Low-complexity: Standard LLMs were more efficient and sometimes more accurate. · Medium-complexity: ...

8. [OptimalThinkingBench: Evaluating Over and Underthinking in LLMs](https://arxiv.org/abs/2508.13141) - We introduce OptimalThinkingBench, a unified benchmark that jointly evaluates overthinking and under...

9. [Claude 3.7 Sonnet - Extended Thinking vs GPT‑5.4 nano - DocsBot AI](https://docsbot.ai/models/compare/claude-3-7-sonnet-extended-thinking/gpt-5-4-nano) - GPQA. Graduate-level Physics Questions Assessment - Tests advanced physics knowledge with Diamond Sc...

10. [LLMs: The Illusion of Thinking - JSO - York University](https://jso.eecs.yorku.ca/2025/09/07/llms-the-illusion-of-thinking/) - Second regime with medium complexity (about 6 disks), the advantage of reasoning models capable of g...

11. [OptimalThinkingBench: Evaluating Over and Underthinking in LLMs](https://liner.com/review/optimalthinkingbench-evaluating-over-and-underthinking-in-llms) - Regarding this ICLR 2026 paper, this review summarizes OptimalThinkingBench, a benchmark evaluating ...

12. [OptimalThinkingBench: Evaluating Over and Underthinking in LLMs](https://arxiv.org/html/2508.13141v1) - Accuracy of distilled thinking models degrades on simple queries after distillation. Non-thinking mo...

13. [Claude 4.6 Migration Guide | OpenRouter | Documentation](https://openrouter.ai/docs/guides/evaluate-and-optimize/model-migrations/claude-4-6) - For Claude 4.6 Opus and 4.6 Sonnet, OpenRouter now uses adaptive thinking ( thinking.type: 'adaptive...

14. [[ENHANCEMENT] Add Adaptive Thinking support for Claude Opus ...](https://github.com/RooCodeInc/Roo-Code/issues/11732) - They are limited to manually setting a fixed thinking budget ( budget_tokens ), which is now depreca...

15. [$NVDA $MU $SNDK $LITE EXECUTIVE SUMMARY Claude Opus ...](https://x.com/TheValueist/status/2019578525989179863) - ... (thinking.type enabled + budget_tokens) explicitly deprecated. (Claude ... (Claude API Docs) Opu...

16. [Anthropic Claude Opus 4.6: Is the Upgrade Worth It? - Codecademy](https://www.codecademy.com/article/anthropic-claude-opus-4-6) - Fast Mode: Pay premium pricing ($30/$150 per million tokens) for 2.5x faster generation. Worth it fo...

17. [A deep analysis of tokenomics of Claude Opus 4.6 - Reddit](https://www.reddit.com/r/ClaudeAI/comments/1qx9768/a_deep_analysis_of_tokenomics_of_claude_opus_46/) - Output tokens are the expensive ones: $25/M base, $37.50/M at the premium tier. A single maxed-out r...

18. [Introducing Claude Sonnet 4.6 - Anthropic](https://www.anthropic.com/news/claude-sonnet-4-6) - Claude Sonnet 4.6 is a full upgrade of the model's skills across coding, computer use, long-reasonin...

19. [Rate limits - Claude API Docs](https://platform.claude.com/docs/en/api/rate-limits) - There are two types of limits: Spend limits set a maximum monthly cost an organization can incur for...

20. [Agent-Centric Text Anomaly Detection for Evaluating LLM Reasoning](https://arxiv.org/abs/2602.23729) - From Static Benchmarks to Dynamic Protocol: Agent-Centric Text Anomaly Detection for Evaluating LLM ...

21. [Challenging the Evaluator: LLM Sycophancy Under User Rebuttal](https://arxiv.org/html/2509.16533v1) - We probe how the LLM weighs its original CoT reasoning against a user‑provided counterargument, vary...

22. [Challenging the Evaluator: LLM Sycophancy Under User Rebuttal](https://aclanthology.org/2025.findings-emnlp.1222/) - Large Language Models (LLMs) often exhibit sycophancy, distorting responses to align with user belie...

23. [What's the max output size for Claude Opus 4.6? - Milvus](https://milvus.io/ai-quick-reference/whats-the-max-output-size-for-claude-opus-46) - Claude Opus 4.6 supports a maximum output of up to 128K tokens per request. In practical terms, that...

24. [DAST: Difficulty-Adaptive Slow-Thinking for Large Reasoning Models](https://www.semanticscholar.org/paper/DAST:-Difficulty-Adaptive-Slow-Thinking-for-Large-Shen-Zhang/488fe2687a3c737510308f3a37c1ade57dc86938) - This paper introduces Difficulty-Adaptive Slow Thinking (DAST), a novel framework that enables model...

25. [[PDF] DAST: Difficulty-Adaptive Slow-Thinking for Large Reasoning Models](https://arxiv.org/pdf/2503.04472.pdf) - These slow- thinking reasoning models, which simulate human deep-thinking mechanisms through self-re...

26. [Think or Not? Exploring Thinking Efficiency in Large Reasoning ...](https://neurips.cc/virtual/2025/poster/119190) - Dast: Difficulty-adaptive slow-thinking for large reasoning models. arXiv preprint arXiv:2503.04472,...

27. [[PDF] Conformal Thinking: Risk Control for Reasoning on a Compute Budget](https://arxiv.org/pdf/2602.03814.pdf) - Empirical results across diverse reasoning tasks and models demonstrate the effectiveness of our ris...

28. [[R] Scaling LLM Test-Time Compute Optimally can be More Effective ...](https://www.reddit.com/r/MachineLearning/comments/1esbkfr/r_scaling_llm_testtime_compute_optimally_can_be/) - For easier questions, the opposite seems to be true. This highlights the need to adaptively allocate...

29. [Optimizing Test-Time Compute for LLMs to Outperform Larger Models](https://www.facebook.com/groups/aimlmalaysia/posts/2240080879725467/) - This paper digs into how letting LLMs use more computation when answering tough prompts can seriousl...

30. [Test-Time Compute Beats Parameter Scaling in LLMs](https://www.emergentmind.com/papers/2408.03314) - The paper introduces a compute-optimal scaling strategy that adaptively allocates test-time compute ...

31. [[PDF] Steering LLM Thinking with Budget Guidance - arXiv](https://arxiv.org/pdf/2506.13752.pdf) - Our approach introduces a lightweight predictor that models a Gamma distribution over the re- mainin...

32. [[Literature Review] Steering LLM Thinking with Budget Guidance](https://www.themoonlight.io/en/review/steering-llm-thinking-with-budget-guidance) - This paper introduces Budget Guidance, a novel, fine-tuning-free inference-time method designed to s...

33. [Empowering Budget-aware LLM Reasoning with Control Tokens](https://arxiv.org/html/2508.17196v1) - This paper introduces BudgetThinker, a novel framework designed to empower LLMs with budget-aware re...

34. [Support Anthropic adaptive thinking and effort parameter for Opus ...](https://github.com/openclaw/openclaw/issues/9837) - It adds /effort as a new directive with levels off / low / medium / high / max (max = Opus only), mo...

