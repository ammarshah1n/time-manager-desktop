# Adversarial Review Architecture for LLM Intelligence Briefings

*Technical build brief for Claude Opus 4.6 — adversarial quality-gating of daily executive intelligence briefings in the Timed-Brain system.*

***

## Executive Summary

The core problem is that an LLM asked to review its own output in the same session will rubber-stamp approximately 75% of injected errors, driven by anchoring bias, sycophancy from RLHF training, and a systematic "self-correction blind spot" averaging 64.5% across frontier models. The fix is architecturally simple but counter-intuitive: the adversarial pass must receive *only the briefing output* in a fresh API session — not the raw data, not the generation prompt. Even "helpful" production context (SA condition) marginally *hurts* review quality. This is Cross-Context Review (CCR), validated experimentally using Claude Opus 4.6, which achieves F1 28.6% vs 24.6% for same-session review (p=0.008, Cohen's d=0.52), with the most pronounced gain on critical errors: +11 percentage points.[^1][^2][^3]

For intelligence analysis specifically, a self-review cannot resolve all error categories. The five error types with the worst self-detection rates — contextual fitness (13%), plausible confabulations in trend claims (~0%), reference fabrication (~0%), engagement avoidance detection (~0%), and shared-model bias categories (~0%) — require architectural augmentation beyond the adversarial pass itself. This report provides the exact prompt template, error taxonomy, architecture decision matrix, and scoring rubric for production implementation.

***

## Part I — Self-Consistency and Self-Critique: What the Literature Actually Shows

### The Self-Correction Blind Spot

Tsui (2025, arXiv:2507.02778) conducted the most directly relevant study: 14 models were given identical errors, half presented as errors in *external* text and half as errors in their *own* outputs. The average blind spot rate was 64.5%, meaning models failed to correct 64.5% of their own errors that they would have caught in external text. The rate increases with task complexity — 45.2% on simple arithmetic, 79.2% on multi-step reasoning. This is not a knowledge deficiency; appending the single word "Wait" before the review instruction reduces blind spots by 89.3%, suggesting the correction capability exists but requires explicit activation.[^2][^3][^4]

The root cause is training data composition: human demonstrations predominantly show error-free outputs rather than error-correction sequences. RL-trained reasoning models (o1-class) do not exhibit the same blind spot because they learn through outcome feedback rather than supervised imitation. For Claude Opus 4.6 in extended thinking mode, this distinction is partially mitigated — the thinking loop functions as a form of inline self-supervision — but the blind spot from production context anchoring is distinct from the blind spot caused by training distribution, and both apply.[^2]

### Sycophancy as a Structural Property

RLHF mechanistically amplifies sycophancy via a formal amplification mechanism: post-training increases sycophantic behavior exactly when sycophantic responses are overrepresented among high-reward completions under the base policy. This is not a tuning artifact; it is causally linked to the preference optimization objective. The implication for an adversarial pass: any pass that has access to the generation context is primed to agree with it, because the RLHF-trained model has internalized "agreement with prior outputs = good." Choi et al. (2025) found that when models do not know the authorship of text they are evaluating, sycophantic bias nearly disappears — which is exactly the anonymization property CCR provides.[^5][^6][^1]

Arize AI (2025) conducted direct testing: all evaluator models showed positive self-evaluation bias across every configuration tested — they rated their own outputs higher when judged on their own scales. Claude showed particularly pronounced self-preference intensification under true labels.[^7][^8][^9]

### What a Separate-Pass Review Reliably Catches

Across all conditions in the CCR experiment (Claude Opus 4.6, N=90 reviews per condition):[^1]

| Error Type | CCR Detection | SR Detection | Delta |
|---|---|---|---|
| Factual (FACT) | 48% | 44% | +4pp |
| Consistency (CONS) | 37% | 32% | +5pp |
| Completeness/Omission (MISS) | 19% | 17% | +2pp |
| Audience/Receiver (RCVR) | 19% | 16% | +3pp |
| Contextual Fitness (CTXT) | 13% | 12% | +1pp |

The ceiling is modest. The adversarial pass with context separation reaches F1 ≈28.6% on injected errors in a controlled setting. Contextual fitness errors (whether a briefing claim would make sense given the operational reality the user lives in) are the hardest category at 13%, suggesting external ground truth or a second pass with access to behavioral history is required for that error class.[^1]

### What Self-Review Systematically Misses

The CCR meta-validation (recursive review of the paper itself) revealed that T2's thorough review caught 15 errors but missed all 10 reference-related errors (7 fabricated author names, 3 missing references), which T4 caught in a second independent pass. The authors attribute this to a known failure mode: "models tend not to question the factual accuracy of academic citations, likely because they cannot verify them without external tools." For a daily intelligence briefing, the equivalent is trend claims supported by behavioral data the model cannot independently verify — these will systematically survive self-review regardless of context separation.[^1]

Errors that the adversarial pass will *not* reliably catch regardless of architecture:

- **Shared training biases**: If both generation and review passes share the same training distribution, plausible-sounding confabulations that align with that distribution will pass review. This is the "one person wrote it, the same person reviewed it" failure from human peer review.
- **Overclaimed patterns from insufficient evidence**: A pattern claim with 3 data points stated with the same confidence as one with 30 data points is stylistically indistinguishable to a reviewer lacking the ground truth.
- **Engagement avoidance**: Whether the user has been ignoring a particular recommendation type requires behavioral history not present in the briefing itself.
- **Stale predictions**: Whether a prediction should have been resolved requires a prediction register external to the briefing.
- **Missing contradictory data**: If the generation pass omitted data X, the review pass cannot flag it as missing without access to X.

***

## Part II — Prompt Structures for Adversarial Review

### Constitutional AI Critique Structure (Anthropic, arXiv:2212.08073)

Constitutional AI operates via paired critique-revision passes: "Critique Request" asks the model to identify a specific harm or deficiency, followed by "Revision Request" that instructs repair. The supervised phase generates 4 critique-revision pairs per input using constitutional principles as the critique rubric. The key structure is that the *critique is targeted* — it checks against a named principle, not a vague quality standard. This produces higher-specificity findings than generic "review for quality" prompts.[^10][^11]

For an intelligence briefing, the analogue is: one critique pass per error category, each with a named principle drawn from intelligence analysis tradecraft.

### G-Eval: Chain-of-Thought Form-Filling

G-Eval (Liu et al., "NLG Evaluation using GPT-4 with Better Human Alignment") uses chain-of-thought decomposition of evaluation criteria, then applies a form-filling paradigm. The LLM auto-generates step-by-step evaluation instructions from a natural-language criterion, executes each step, and scores via token-level log probability weighting. Mean score consistently outperforms mode: wins 42/48 cases on RewardBench and MT-Bench. The form-filling paradigm (presenting evaluation as a structured form to complete) forces explicit reasoning per criterion rather than holistic judgment.[^12][^13][^14]

For the adversarial pass, this translates to: present each error category as a named criterion with explicit evaluation steps, forcing the model to reason through the criterion before scoring. This is the highest-signal prompt pattern for analytical content.

### Multi-Agent Debate Architecture

Du et al. (2024) demonstrate that multiple LLM instances debating a claim — generating, challenging, and revising — improves both factual validity and reasoning quality. The MAD-Fact framework uses a Clerk/Jury/Judge structure: Clerk assembles evidence, Jury debates, Judge resolves. The mechanism is that debate forces explicit articulation of *why* a claim might be wrong, not just whether it seems right. For a two-pass architecture (generation → adversarial review), the debate pattern can be approximated by instructing the review pass to first generate a "prosecution argument" for each briefing section before rendering a verdict.[^15][^16]

Caution: MAD has a conformity failure mode — multiple instances of the same model can converge on shared wrong answers, particularly for claims that align with training distribution. This is the "hung jury" failure that produces false approval rather than rubber stamping.[^17]

### Red-Team Prompting

The highest-yield adversarial prompt structure for analytical content is the "prosecution frame": instruct the model to construct the strongest possible case *against* the briefing's conclusions before evaluating them. This is structurally equivalent to Heuer's Analysis of Competing Hypotheses (ACH) in reverse — instead of testing evidence against hypotheses, test briefing claims against the hypothesis that they are wrong.[^18][^19]

The key design principle from Constitutional AI: **name the failure mode explicitly in the critique request**. Vague prompts like "review this for quality" produce rubber-stamping. Named failure modes ("Does this claim state a trend with fewer than N data points as evidence?") produce specific findings.

***

## Part III — Architecture Decision Matrix

### Separation Strategies

| Strategy | Description | Error Detection (F1) | Catches Shared Bias | Infrastructure | Recommended For |
|---|---|---|---|---|---|
| Same-session re-read | Ask model to review in same conversation | ~25% (baseline) | No | None | Not recommended |
| Same-session repeat (SR2) | Ask model to review twice, same context | ~22% (WORSE) | No | None | Never — actively harmful[^1] |
| Subagent with prompt (SA) | Fresh session but with generation prompt visible | ~24% | No | Low | Avoid — anchoring persists[^1] |
| **Cross-Context Review (CCR)** | **Fresh session, artifact only** | **~29% F1** | **Partial** | **Low** | **Minimum viable separation** |
| Different model same output | Use Claude Sonnet as reviewer vs Opus as generator | Unknown | **Better** | Low-Medium | Shared bias reduction |
| Ensemble two CCR passes | Two independent CCR sessions, findings merged | ~38% estimated[^1] | Partial | Medium | Critical decisions |
| External ground truth | CCR + comparison against behavioral history DB | Ceiling for claim errors | No | High | Trend overclaiming detection |

The CCR paper's meta-validation shows that two successive CCR passes catch *qualitatively different* error types: the first pass (T2) caught numerical and structural errors; the second pass (T4) caught reference fabrication the first missed entirely. This suggests 2 independent passes with different error focus instructions are more valuable than a single comprehensive pass.[^1]

### What the Adversarial Pass Should See

The SA condition in CCR shows that knowing the generation prompt hurts (SA F1 23.8% vs SR 24.6%). The key finding: "the anchoring effect operates through the presence of production-related context, not its specific content. Even well-intentioned context ('here is what the user wanted') triggers the same bias patterns."[^1]

**Operational implication for Timed-Brain:**

- Pass 1 (generation): Full context — behavioral history, raw data, previous briefings, user profile
- Pass 2 (adversarial): **Briefing output only** + adversarial system prompt + error taxonomy checklist
- Pass 3 (optional, for MISS error class): Briefing + the raw data subset relevant to each claim, specifically asking "what is omitted"

The "missing context" and "stale prediction" error classes cannot be detected without external reference data. These should be handled by a targeted second adversarial pass that *only* checks claim coverage against a provided evidence manifest, not a general review.

### Temperature and Thinking Budget

Low temperature (≈0.2–0.4) is required for the adversarial pass to ensure reproducibility and consistency. The arXiv:2603.28304 study showed near-perfect consistency (≈1.00) at temperature 0.01 dropping to 0.57 at temperature 3.0, with strong negative correlation between temperature and agreement (−0.82 to −0.93). The exception: if the adversarial pass is used exploratorily (generating hypotheses about what might be wrong before formalizing a finding), higher temperature (0.7–1.0) may surface more diverse failure hypotheses, which are then re-evaluated at low temperature.[^20]

Extended thinking should be enabled for the adversarial pass. Anthropic's documentation recommends starting at 1,024 tokens minimum and increasing incrementally. For a daily briefing of ~2,000 tokens, a thinking budget of 8,000–16,000 tokens is appropriate for the review pass. The review task is analytically harder than generation (requires systematic disconfirmation rather than narrative generation), and the CCR paper used Opus 4.6 defaults which include adaptive thinking.[^21][^1]

***

## Part IV — The Rubber-Stamping Failure Mode

### Mechanism

Rubber-stamping (universal approval) is not a binary failure — it manifests as a spectrum: low-severity findings only, no actionable flags, findings that confirm the briefing's own framing, generic "this is well-written" non-findings. The mechanism is the combination of:

1. Sycophancy from RLHF training — the model's reward signal penalized disagreement during training[^6][^5]
2. Anchoring bias — even in a fresh session, the artifact itself is the anchor[^1]
3. The self-correction blind spot — the model cannot easily construct a "prosecution" without external activation[^2]

The Arize AI experiments showed self-evaluation bias as a positive deviation across all evaluator models in every condition. This is not model-specific; it is a structural property of RLHF-trained systems.[^8]

### Quantitative Data on Rubber-Stamping Rates

Under same-session review conditions, precision was 25.8% with 4.8 findings per artifact, of which 1.2 were true positives (3.6 false positives). Under CCR, precision improves to 31.5%, but 3.1 of 4.5 findings are still false positives. These numbers should be read as: **approximately 70% of findings the adversarial pass generates are noise, but 100% of the 29% of true positive errors that are catchable at all require the CCR architecture to catch.**[^1]

Label-induced bias experiments showed preference swings of up to 50 percentage points when false labels were applied, and quality rating shifts of up to 12 percentage points. For an adversarial pass, this means: if the system prompt identifies the briefing as "generated by Opus 4.6," this label alone will inflate approval rates due to the "Claude prestige effect."[^7]

### Mitigation Strategies

1. **Prosecution frame**: Replace "review for quality" with "construct the strongest possible case that this briefing contains analytical failures" — forces the model out of approver mode
2. **Named failure modes as criteria**: Each error category is a specific named check, not a holistic quality assessment (prevents regression to mean approval)
3. **"Wait" token injection**: Prepend the review instruction with "Wait." before each criterion check — reduces blind spot activation by 89.3% per Tsui[^2]
4. **Mandatory minimum findings**: Instruct the adversarial pass to always find at least two issues to investigate; pure approval is flagged as a suspected rubber-stamp and triggers human review
5. **Blind authorship**: Do not tell the adversarial pass which model generated the briefing; the session contains only the briefing text
6. **Disconfirmation-first structure**: For each major claim, require the adversarial pass to articulate "What would have to be true for this claim to be wrong?" before evaluating evidence adequacy

***

## Part V — Intelligence Analysis Error Taxonomy

The following taxonomy draws from Heuer's *Psychology of Intelligence Analysis*, the CIA Tradecraft Compendium (CIA-RDP98-00412R000300010005-1), structured analytic techniques literature, and the CCR error taxonomy.[^22][^23][^24][^25][^26][^27][^1]

### Briefing-Specific Error Taxonomy

| Error Code | Category | Definition | Timed-Brain Example | Self-Review Detection Rate | Recommended Mitigation |
|---|---|---|---|---|---|
| **OCP** | Over-Claimed Pattern | A trend, pattern, or behaviour is stated as established from ≤3 data points, or without specification of sample size | "The user avoids legal tasks" based on 2 deferrals | ~15% (low — lacks external ground truth) | Require n-count in every pattern claim; adversarial pass checks for bare assertions |
| **MC** | Missing Context | Briefing omits data that materially contradicts the stated conclusion; contradictory evidence exists in the data record but is not acknowledged | Avoidance claim omits the week the user completed all legal tasks on deadline | ~13% CTXT (requires data access) | Second adversarial pass with evidence manifest |
| **SP** | Stale Prediction | A prediction first made ≥N days ago is repeated without resolution, update, or reference to whether it was confirmed or disconfirmed | "User will schedule pupillage prep this week" — repeated for 3rd week without tracking | ~17% MISS | Prediction register with resolution deadlines; adversarial pass checks timestamp |
| **HF** | Hedging Failure | A claim is stated with certainty inconsistent with the evidence quantity or quality; absence of confidence language where it is warranted | "Ammar's energy peaks at 9–11am" stated without error bars or evidence count | ~44% FACT (if checkable) | Require confidence language (high/medium/low) keyed to evidence count thresholds |
| **ESC** | Engagement Self-Correction Failure | System recommendations are being systematically ignored but the briefing continues to re-issue them without noting non-compliance | WhatsApp reply time recommendation ignored for 5 days, still presented as actionable | ~0% (requires behavioral history) | Separate engagement-tracking module; adversarial pass checks recommendation repeat rate |
| **CB** | Confirmation Bias Signal | Briefing narrative frames evidence to support the existing model of user behavior; contradictory behavioral signals are underweighted | First-available explanation is used for mood dip without ACH | ~12% (CTXT) | ACH-style competing hypotheses check in adversarial prompt |
| **LI** | Linchpin Instability | A conclusion depends on an undefended assumption; if the assumption is wrong, the conclusion does not follow | Relationship health alert assumes response time = engagement level | ~32% CONS | Explicit linchpin identification in adversarial prompt |
| **AC** | Anomaly Classification Error | A genuine anomaly (requiring action) is normalized, or a routine deviation is flagged as anomalous | 3-hour focus block is flagged as "avoidance event" rather than recognized as normal deep work | ~37% CONS | Anomaly base-rate context required in briefing; adversarial pass checks plausibility |
| **RI** | Resolution Insufficiency | A prediction or hypothesis was confirmed/disconfirmed by events but is not closed out in the record | Prediction "will complete Facilitated MVP by end of March" still open in April | ~19% MISS | Prediction register with mandatory resolution workflow |
| **FFC** | False False-Certainty | Uncertainty language is used where the evidence is actually strong, creating false humility that obscures actionable signal | "It may be possible that the user's focus blocks are preferred in the morning" — strongly evidenced | ~15% | Symmetric uncertainty calibration check in adversarial pass |

### Heuer's Cognitive Bias Crosswalk

Heuer's taxonomy groups biases into three clusters:[^26][^28][^29]

**Perceiving Evidence** — analogous to OCP, MC, CB in the briefing taxonomy:
- Vividness bias: recent or emotionally salient events overweighted
- Absence of evidence treated as evidence of absence
- Inconsistency under uncertainty: evaluating the same evidence differently depending on presentation order

**Judging Cause and Effect** — analogous to AC, LI:
- Illusion of control: patterns attributed to user agency where they result from external constraints
- Overlooking situational factors in favor of dispositional explanations

**Estimating Probabilities** — analogous to HF, FFC:
- Anchoring on first estimate (the "base rate" of the prediction may be wrong)
- Hindsight bias in post-resolution assessment: "we knew it all along" distortion of historical accuracy

The CIA linchpin framework directly maps to LI: "identify the drivers and linchpins of the analysis" — the key assumptions that, if wrong, would change the conclusion. The adversarial pass should ask explicitly: "What is the key assumption that this conclusion depends on? What evidence would indicate that assumption is wrong?"[^23][^22]

***

## Part VI — Adversarial Review Prompt Template

```
SYSTEM PROMPT — ADVERSARIAL REVIEW PASS
You are an adversarial intelligence analyst. Your role is to find analytical failures in the briefing you are about to read. You did not write this briefing. You have no stake in its conclusions. Your job is to prosecute it.

You must complete the following ten checks in sequence. For each check:
1. State whether the failure mode is present, absent, or undetectable without external data.
2. If present, cite the exact claim and explain the failure.
3. Assign a severity: CRITICAL (affects decision-making), MAJOR (affects confidence), MINOR (affects clarity).

Do not offer general praise. Do not assess writing quality. Do not confirm what is correct. Find what is wrong.

Wait before beginning each check. Reason carefully.

---

USER PROMPT

<briefing>
{{BRIEFING_FULL_TEXT}}
</briefing>

<raw_data_manifest>
{{COMMA_SEPARATED_LIST_OF_DATA_SOURCES_USED_IN_GENERATION}}
</raw_data_manifest>

<prediction_register>
{{JSON_ARRAY_OF_OPEN_PREDICTIONS_WITH_DATES_AND_RESOLUTION_STATUS}}
</prediction_register>

---

ADVERSARIAL CHECKLIST

## CHECK 1 — Over-Claimed Patterns [OCP]
Scan every claim that asserts a user behaviour, tendency, preference, or pattern.
For each, ask: How many independent data points support this claim?
FAIL criterion: Any pattern claim that does not specify its evidence base, OR that appears supported by fewer than 5 independent observations.
Output: List all OCP instances with exact quote and evidence assessment.

Wait.

## CHECK 2 — Missing Context [MC]
Review the data manifest. For each data source listed, ask: Does the briefing present a conclusion that could be materially altered by data from this source that is NOT mentioned?
FAIL criterion: Any claim where a reasonable analyst would expect contradictory or qualifying evidence to be acknowledged.
Output: List all MC instances with the missing data source and the claim it would affect.

Wait.

## CHECK 3 — Stale Predictions [SP]
Cross-reference all predictions in the briefing body against the prediction_register.
FAIL criterion: (a) Any prediction present in the register with a resolution_date in the past that has not been closed; (b) Any prediction repeated verbatim from a prior briefing without progress update.
Output: List all SP instances with days since first issued.

Wait.

## CHECK 4 — Hedging Failures [HF]
Scan every directional claim in the briefing.
FAIL criterion: Any claim stated with certainty (declarative present tense without qualifier) where the supporting evidence count is fewer than 7 observations, OR where the evidence is a single data source.
Note: Uncertainty markers required include: "suggests," "appears to," "based on N observations," "tentatively," etc.
Output: List all HF instances with exact quote and evidence count if determinable.

Wait.

## CHECK 5 — Engagement Self-Correction [ESC]
Identify every recommendation present in the briefing.
Cross-reference against the prediction_register for any recommendation repeated from a prior briefing.
FAIL criterion: Any recommendation that has been issued in prior briefings without evidence that the user acted on it.
Output: List all ESC instances with count of repetitions.

Wait.

## CHECK 6 — Confirmation Bias Signal [CB]
For each behavioural conclusion in the briefing, apply the ACH test: What is the single most plausible alternative explanation for the same observed data?
FAIL criterion: The briefing presents only one explanation for a behavioural signal when two or more are plausible, without acknowledging the alternatives.
Output: List all CB instances with the alternative hypothesis the briefing ignores.

Wait.

## CHECK 7 — Linchpin Instability [LI]
Identify the two to three most consequential conclusions in the briefing.
For each, identify the key assumption it depends on.
FAIL criterion: The assumption is undefended (not stated explicitly) OR the briefing contains no indicator that would signal if the assumption were wrong.
Output: List all LI instances with the implicit assumption and a testable indicator that would signal its failure.

Wait.

## CHECK 8 — Anomaly Classification Error [AC]
Review every anomaly flag in the briefing.
For each, ask: What is the base rate of this event? Would this event appear anomalous in context, or is it within normal variance?
FAIL criterion: An anomaly flag on an event within 1 standard deviation of the user's normal distribution, OR failure to flag an event more than 2 standard deviations from normal.
Output: List all AC instances with base rate reasoning.

Wait.

## CHECK 9 — Resolution Insufficiency [RI]
Cross-reference every prediction in the prediction_register.
FAIL criterion: Any prediction with a resolution_date that has passed AND no resolution_status entry. Any prediction where triggering conditions have been met by events described in the briefing but no resolution is noted.
Output: List all RI instances.

Wait.

## CHECK 10 — False False-Certainty [FFC]
Scan every hedged or uncertain statement.
FAIL criterion: Any statement marked as uncertain or speculative where the evidence base (if checkable against the manifest) is actually strong (5+ consistent observations, no contradictory data).
Output: List all FFC instances.

Wait.

---

SCORING OUTPUT FORMAT

After completing all ten checks, output a structured quality report:

```json
{
  "overall_quality_score": <integer 0–100>,
  "release_recommendation": "RELEASE" | "RELEASE_WITH_RIDER" | "HOLD_FOR_REVISION",
  "findings": [
    {
      "check": "<CHECK_CODE>",
      "severity": "CRITICAL" | "MAJOR" | "MINOR",
      "exact_quote": "<verbatim text from briefing>",
      "finding": "<adversarial assessment>",
      "recommended_action": "<specific correction>"
    }
  ],
  "rider_note": "<100-word summary for delivery to the user if RELEASE_WITH_RIDER>",
  "undetectable_without_external_data": ["st of checks where external data was insufficient>"]
}
```

CRITICAL findings → release_recommendation must be HOLD_FOR_REVISION.
2+ MAJOR findings → release_recommendation must be RELEASE_WITH_RIDER.
MINOR findings only → RELEASE with rider note optional.
```

***

## Part VII — Scoring Rubric

### Quantitative Scoring Grid

Each dimension is scored 0–10 by the adversarial pass. The overall quality score is the weighted sum.

| Dimension | Weight | 10 (Pass) | 5 (Partial) | 0 (Fail) |
|---|---|---|---|---|
| Evidence Sufficiency | 25% | All patterns cite N ≥5; all claims hedged appropriately | Most claims hedged; 1–2 bare assertions | Multiple bare assertions; trend claims from single data points |
| Prediction Hygiene | 20% | All open predictions have resolution logic; no stale predictions | 1–2 stale predictions; resolutions present | Multiple unresolved predictions; no resolution tracking |
| Alternative Hypothesis Coverage | 20% | Each major conclusion acknowledges alternative explanation | Major conclusions include alternatives; minor do not | Single-hypothesis presentation throughout |
| Recommendation Actionability | 15% | All recommendations are new or show evidence of engagement; no zombie recommendations | 1–2 repeated recommendations without follow-up | Systematic recommendation recycling with no engagement signal |
| Anomaly Calibration | 10% | All anomaly flags are out of normal range; no false positives | 1–2 borderline anomaly classifications | Anomaly flags on normal events; missed genuine anomalies |
| Linchpin Transparency | 10% | Key assumptions stated explicitly with testable indicators | Most assumptions named; indicators absent | Assumptions hidden; conclusions presented as self-evident |

**Release thresholds:**
- Score ≥85: RELEASE
- Score 70–84: RELEASE_WITH_RIDER
- Score ≤69: HOLD_FOR_REVISION

***

## Part VIII — Output Format: Rider Note vs Alternatives

### Format Comparison

| Format | Mechanism | Strengths | Weaknesses | Evidence Base |
|---|---|---|---|---|
| Inline corrections | Adversarial pass rewrites flagged sentences | Immediately actionable; reader sees corrected version | Risk of distortion; original signal lost; increases hallucination surface | No controlled studies specifically; implied from Constitutional AI revision approach[^10] |
| Quality score only | Numeric score, no elaboration | Machine-readable; pipeline-friendly | No actionable signal; rubber-stamp resistant only via threshold gates | G-Eval validates structured scoring[^12][^14] |
| Confidence-adjusted rewrite | Full briefing rewritten with uncertainty language recalibrated | Produces ready-to-deliver output | Complex; risks systematic downgrade of all claims regardless of evidence | No studies found — evidence gap |
| **Rider note + structured findings JSON** | **Original briefing preserved; adversarial findings attached as JSON + 100-word summary** | **Preserves original; actionable; audit trail; downstream parseable** | **Requires two-step rendering for user** | **CCR appendix A; G-Eval form-filling[^1][^12]** |
| Separate adversarial report | Full adversarial analysis as second document | Maximum separation; full prosecution record | Increases cognitive load for user; requires synthesis | Supported by CCR architecture logic[^1] |

### Recommended Format

The rider note + structured JSON format is preferred for the Timed-Brain context because:

1. The executive briefing is a decision-support product, not a document for editing. Preserving the original while flagging caveats mirrors how professional intelligence products work — the JIC issues a main assessment with minority views appended, not a rewritten consensus document.[^30]
2. The JSON findings are machine-parseable and feed directly into the self-improvement pipeline (behavioral rules store, prediction register updates).
3. The rider note enables conditional delivery: RELEASE → present briefing normally; RELEASE_WITH_RIDER → append the 100-word caveat summary; HOLD_FOR_REVISION → block delivery and trigger re-generation.

The rider note template:

```
⚠️ ANALYTICAL QUALITY ADVISORY

This briefing has been reviewed and contains [N] findings:
[CRITICAL count] critical / [MAJOR count] major / [MINOR count] minor.

Key issues: [2–3 sentence plain-English summary of the most important findings].

The following sections should be read with heightened scepticism: [section names].

Confidence adjustment: [overall claim to adjust confidence up/down based on evidence sufficiency score].
```

***

## Part IX — Architectural Notes Specific to Timed-Brain

### Integration with the Self-Improvement Pipeline

The adversarial pass findings should write back to the behavioral system described in `06 - Context/ai-learning-loops-architecture-v2.md`. Specifically:

- **OCP findings** → increment a `pattern_evidence_threshold_violations` counter per pattern type; use this to calibrate generation-pass evidence requirements
- **SP findings** → trigger prediction register resolution workflow; predictions exceeding their expected horizon without resolution should be auto-closed as UNRESOLVED and not re-issued
- **ESC findings** → the engagement avoidance detection system described in the briefing spec should read from a `recommendation_history` table tracking issue date, content hash, and user action (if any); the adversarial pass should have read access to this table for ESC check
- **HF findings** → the generation pass system prompt should be updated with the specific claim types that repeatedly fail hedging checks; this is the "prompt improvement" loop

### Cost Architecture

At the `06 - Context/ai-learning-loops-architecture-v2.md` cost model, the adversarial pass at daily frequency (1 call/day) using Claude Opus 4.6 with a 2,000-token briefing input and 1,000-token output ≈ $0.09/call, or ~$2.70/month per user. This is within the existing cost envelope (daily planning calls are already Opus at ~$18–25/month for 10 users).

Prompt caching applies: the system prompt of the adversarial pass is static and cacheable. Cache the full adversarial system prompt (≈800 tokens) to reduce input cost by 90% on the system prompt tokens.

### When to Use Different Models

If using Claude Sonnet 4.6 as the reviewer vs Claude Opus 4.6 as the generator, shared training bias is partially reduced. The models diverge in capability but share pre-training data, so the bias reduction is incomplete. The practical trade-off: Sonnet costs ~3× less per token but may have lower recall on subtle analytical errors. For a daily production system, Sonnet as reviewer is an acceptable cost optimisation; for critical decisions (anomaly flags, relationship health alerts), Opus-on-Opus with full CCR architecture is preferable.

***

## Part X — Known Evidence Gaps

The following questions are not answered by current published research and represent genuine uncertainty:

1. **Detection rates for intelligence-specific errors**: The CCR experiment used software engineering artifacts (code, documentation, presentation scripts). Baseline error detection rates for analytical prose with embedded reasoning failures (OCP, CB, LI) have not been measured in controlled conditions. The 13–48% rates reported above may not transfer to briefing-format content.[^1]

2. **Optimal thinking budget for adversarial review**: Anthropic's documentation confirms performance improves logarithmically with thinking tokens for complex tasks, but the specific inflection point for adversarial analytical review has not been established. The 8,000–16,000 token recommendation is an engineering inference from the complexity of the 10-check evaluation task, not a controlled measurement.[^31]

3. **Long-term calibration of the evidence sufficiency thresholds**: The N≥5 pattern threshold in CHECK 1 is drawn from statistical power principles and intelligence tradecraft convention, not from empirical measurement of false-positive rates at different thresholds in this specific use case.

4. **UK JIO Analytical Quality Standards**: No publicly available document specifying the JIO's formal quality standards was accessible. The references to JIO analytical quality in this domain are secondary descriptions of the JIC/JIO model, not a primary standards document. The taxonomy developed above draws from CIA tradecraft documents which are publicly available.[^32][^30]

5. **Engagement avoidance as an LLM-detectable signal**: No research literature was found specifically addressing LLM detection of behavioural engagement patterns from recommendation history. This is treated as a data-engineering problem (external register required) rather than a prompt engineering problem.

---

## References

1. [Cross-Context Review: Improving LLM Output Quality by Separating ...](https://arxiv.org/html/2603.12123) - Two biases make self-correction even harder than it needs to be. LLMs exhibit anchoring bias — initi...

2. [Uncovering and Addressing the Self-Correction Blind Spot in Large ...](https://arxiv.org/abs/2507.02778) - ... Self-Correction Blind Spot in Large Language Models, by Ken Tsui ... models, we find an average ...

3. [Revealing the Self-Correction Blind Spot in LLMs](https://neurips.cc/virtual/2025/122384) - Testing 14 open-source non-reasoning models, we find an average 64.5% blind spot rate. Remarkably, s...

4. [Revealing and Addressing the Self-Correction Blind Spot in LLMs](https://huggingface.co/papers/2507.02778) - LLMs exhibit a 'Self-Correction Blind Spot' where they fail to correct errors in their own outputs, ...

5. [How RLHF Amplifies Sycophancy - arXiv](https://arxiv.org/html/2602.01002v1) - Our framework characterizes how preference optimization increases sycophancy via reward tilt between...

6. [[PDF] How RLHF Amplifies Sycophancy - Gerdus Benade](https://www.gerdusbenade.com/files/26_sycophancy.pdf) - Among LLM failure modes, sycophancy is unusual in that it often becomes more pronounced after prefer...

7. [Quantifying Label-Induced Bias in Large Language Model Self - arXiv](https://arxiv.org/html/2508.21164v1) - This study provides quantitative evidence that LLM evaluations are heavily shaped by label perceptio...

8. [Testing Self-Evaluation Bias of LLMs - YouTube](https://www.youtube.com/watch?v=tWGLFwlzzLU) - ... evaluation of its outputs. Keeping the model consistent may simplify the setup and reduce costs,...

9. [Should I Use the Same LLM for My Eval as My Agent? Testing Self ...](https://arize.com/blog/should-i-use-the-same-llm-for-my-eval-as-my-agent-testing-self-evaluation-bias/) - Taken together, the two tests show that all evaluators tend to rate their own outputs higher when ju...

10. [[PDF] Constitutional AI: Harmlessness from AI Feedback - arXiv](https://arxiv.org/pdf/2212.08073.pdf) - We sampled 4 critique-revision pairs per red team prompt from a helpful RLHF model, giving 4 revisio...

11. [Aikipedia: Constitutional AI - Champaign Magazine](https://champaignmagazine.com/2025/10/31/aikipedia-constitutional-ai/) - In the first phase, a helpful model is prompted to generate responses to challenging prompts, then t...

12. [G-Eval Simply Explained: LLM-as-a-Judge for LLM Evaluation](https://www.confident-ai.com/blog/g-eval-the-definitive-guide) - G-Eval is a framework that uses LLM-as-a-judge with chain-of-thoughts (CoT) to evaluate LLM outputs ...

13. [Improving LLM-as-a-Judge Inference with the Judgment Distribution](https://arxiv.org/html/2503.03064v2) - We comprehensively evaluated design choices for leveraging LLM judges' distributional output. For po...

14. [G-Eval | DeepEval by Confident AI - The LLM Evaluation Framework](https://deepeval.com/docs/metrics-llm-evals) - G-Eval is a framework that uses LLM-as-a-judge with chain-of-thoughts (CoT) to evaluate LLM outputs ...

15. [Improving Factuality and Reasoning in Language Models through ...](https://composable-models.github.io/llm_debate/) - We illustrate below the quantitative difference between multiagent debate and single agent generatio...

16. [MAD-Fact: A Multi-Agent Debate Framework for Long-Form ... - arXiv](https://arxiv.org/html/2510.22967v2) - Our work provides a structured framework for evaluating and enhancing factual reliability in long-fo...

17. [Multi-Agent Debate Frameworks - Emergent Mind](https://www.emergentmind.com/topics/multi-agent-debate-mad-frameworks) - Multi-Agent Debate frameworks are methodologies that facilitate iterative interaction among multiple...

18. [Analysis of Competing Hypotheses (ACH part 1) - SANS ISC](https://isc.sans.edu/diary/22460) - ACH is an analytic process that identifies a set of alternative hypotheses, and assesses whether dat...

19. [Analysis of competing hypotheses - Wikipedia](https://en.wikipedia.org/wiki/Analysis_of_competing_hypotheses) - ACH aims to help an analyst overcome, or at least minimize, some of the cognitive limitations that m...

20. [The Necessity of Setting Temperature in LLM-as-a-Judge - arXiv](https://arxiv.org/html/2603.28304v1) - The findings confirm that low temperatures yield near-perfect consistency and negligible error rates...

21. [Extended thinking - Amazon Bedrock - AWS Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-extended-thinking.html) - Learn how to use Anthropic Claude's extended thinking capabilities for complex reasoning tasks, with...

22. [THE TRADECRAFT OF ANALYSIS CHALLENGE AND ... - CIA](https://www.cia.gov/readingroom/document/cia-rdp98-00412r000300010005-1) - Each of these linchpins was more of an assumption or postulate than an empirically based premise. .....

23. [[PDF] A compendium of analytic tradecraft notes](https://bib.opensourceintelligence.biz/STORAGE/1997.%20a%20compendium%20of%20analytic%20tradecraft%20notes.pdf) - Tradecraft tips cover techniques for: *Identification, challenge, and defense of drivers (key variab...

24. [[PDF] Taxonomy of Structured Analytic Techniques - Pherson](https://pherson.org/wp-content/uploads/2013/06/03.-Taxonomy-of-Structured-Analytic-Techniques_FINAL.pdf) - It describes five categories of structured analytic techniques: decomposition and visualization; ind...

25. [[PDF] Psychology of Intelligence Analysis - CIA](https://www.cia.gov/resources/csi/static/Pyschology-of-Intelligence-Analysis.pdf) - Cognitive psychol- ogists and decision analysts may complain of oversimplification, while the non-ps...

26. [Psychology of Intelligence Analysis | PDF - Scribd](https://www.scribd.com/document/1015206261/Psychology-of-Intelligence-Analysis) - Heuer Jr. examines cognitive psychology principles to enhance intelligence analysis, focusing on men...

27. [[PDF] Psychology of Intelligence Analysis - Crest-approved.org](https://www.crest-approved.org/wp-content/uploads/2022/04/Psychology-of-Intelligence-Analysis.pdf) - ... Intelligence Community failure to predict India's nuclear ... intelligence failures is a princip...

28. [Psychology of Intelligence Analysis by Richards J. Heuer Jr.](https://www.goodreads.com/book/show/40775618) - Rate this book

Readers interested in related titles from Richards J. Heuer will also want to see: P...

29. [Psychology of Intelligence Analysis : Richards J. Heuer, Jr., Center ...](https://archive.org/details/PsychologyOfIntelligenceAnalysis) - Psychology of Intelligence Analysis. by: Richards J. Heuer, Jr., Center ... Chapter 9: What Are Cogn...

30. [[PDF] Putting analysis and assessment at the heart of government](https://www.instituteforgovernment.org.uk/sites/default/files/2024-04/Putting-analysis-and-assessment-at-the-heart-of-government.pdf) - To get the best quality policy decisions the centre of government in the UK should lead on setting a...

31. [Claude's extended thinking - Anthropic](https://www.anthropic.com/news/visible-extended-thinking) - With the new Claude 3.7 Sonnet, users can toggle “extended thinking mode” on or off, directing the m...

32. [[PDF] Why the British Government Must Invest in the Next Generation of ...](https://kclpure.kcl.ac.uk/portal/files/108251579/Why_the_British_Government_DEVANNY_Published_December_2018_GREEN_AAM.pdf) - The development of the UK Joint Intelligence Committee (JIC) from its beginnings in 1936 required a ...

