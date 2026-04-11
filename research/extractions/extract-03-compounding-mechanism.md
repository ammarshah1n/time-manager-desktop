# Extract 03 — Compounding Intelligence Mechanism

Source: `research/perplexity-outputs/v2/v2-03-compounding-mechanism.md`

---

## DECISIONS

### Phase Transitions (Week 1 → Month 12)

The compounding mechanism is **structural, not volumetric**. Month-6 intelligence is impossible at month 1 because it depends on representational layers that cannot exist until earlier layers have been built and validated. Grounded in Vervaeke's recursive relevance realization and the episodic-semantic compression interplay from cognitive neuroscience.

| Period | Phase | What Becomes Possible | Why It Was Impossible Before |
|--------|-------|----------------------|----------------------------|
| Week 1–2 | Baseline establishment | Raw behavioural fingerprint — email cadence, calendar structure, keystroke baseline, app usage norms | Nothing to compare against; all observations are first-instance |
| Month 1 | Routine detection | Recurring daily/weekly rhythms, sender-response priority map, energy cycle approximation | Requires minimum 3–4 repetitions of weekly cycles to distinguish signal from noise |
| Month 3 | Deviation detection | Anomalies flagged against stable baselines, first cross-signal correlations (calendar compression + email latency = stress proxy) | Baselines must exist before deviations can be detected; cross-signal requires confirmed independent patterns first |
| Month 6 | Predictive capability | Forward-looking predictions: "Given pattern X + context Y, she will likely do Z". Trait-level model stable enough for novel-situation reasoning | Prediction requires validated trait models (month 3+), plus enough historical predictions to calibrate confidence |
| Month 12 | Deep model / anticipatory | Anticipates reactions to novel situations. Detects multi-month trajectories (becoming more risk-averse, delegation shifting). Comparable to trusted Chief of Staff or therapist after 50 sessions | Trajectory detection requires 6+ months of versioned trait snapshots. Novel-situation anticipation requires a stable, validated cognitive model |

### Multi-Stage Reflection Pipeline

Four stages. Each stage's output is the input for the next. No stage can be skipped.

1. **Observation → First-order patterns**: Raw signals aggregated into daily behavioural summaries. Summaries contain: signal type, timestamp, value, deviation from baseline (if baseline exists), context metadata (calendar state, day-of-week, known external events).
2. **First-order patterns → Second-order abstractions**: Daily patterns compared across weeks to extract recurring behaviours. Trigger: minimum 3 weeks of daily summaries for a given signal. Output: behavioural rules with confidence scores. Example: "Responds to Board members within 15 min; takes 2+ hours for internal operational emails."
3. **Second-order abstractions → Stable traits**: Recurring patterns crystallised into personality traits, decision-making heuristics, relationship maps, cognitive style profiles. Evidence threshold: pattern must pass all 4 validation gates (see Pattern Validation below). Output: structured executive model document. Example: "Pattern-interrupt decision maker — fast decisions on familiar categories, deliberately slows down and seeks external input for novel strategic choices."
4. **Stable model → Predictions**: Trait model enables forward-looking predictions. Every prediction must be **falsifiable with named observables** — "she will respond to the CFO within 30 minutes" not "she seems stressed". Predictions carry explicit confidence intervals and expiry timestamps.

### Pattern Validation Methodology — Four-Gate Protocol

Every candidate pattern must pass all four gates before promotion to a higher memory tier:

1. **Statistical significance**: ARIMA-corrected Cohen's d_z ≥ 0.5 (medium effect). The ARIMA correction removes autocorrelation from the time series before computing the effect size — raw Cohen's d on autocorrelated behavioural data inflates significance.
2. **Temporal stability**: Test-retest correlation across non-adjacent weeks ≥ 0.6. Pattern must hold in at least 3 of 4 sampled weeks, not just consecutive ones.
3. **Contextual replication**: Pattern replicates across at least 2 distinct context conditions (e.g., the response-time pattern holds on both high-meeting and low-meeting days). If a pattern only appears in one context, it's a contextual response, not a trait.
4. **Causal coherence**: The pattern must be psychologically interpretable — an LLM review (Sonnet) evaluates whether the statistical pattern maps to a known cognitive/behavioural mechanism. Pure statistical artifacts with no plausible mechanism are quarantined, not promoted.

Decision rule: Fail any gate → pattern stays at current tier with a `validation_status: "pending"` flag. Re-evaluated at next weekly cycle.

### Change Detection — BOCPD + Quarantine

Use **Bayesian Online Change Point Detection** (Adams & MacKay, 2007) running simultaneously at three abstraction levels:

1. **Signal level**: Raw metric change points (email response time suddenly shifts)
2. **Pattern level**: Behavioural rule violations (established pattern stops holding)
3. **Trait level**: Executive model predictions systematically failing

When BOCPD flags a potential change point:
- **14-day quarantine protocol**: Do not update the trait model immediately. Mark the change as `status: "quarantine"`, timestamp it, and continue observing.
- After 14 days, compute the **Composite Deviation Index (CDI)**: weighted sum of (a) magnitude of deviation from pre-change baseline, (b) consistency of new behaviour across the quarantine window, (c) number of abstraction levels showing concordant change.
- CDI ≥ threshold → **genuine change**. Version the old trait, create new trait with `valid_from` timestamp, generate trajectory narrative.
- CDI < threshold → **transient perturbation**. Log as episodic memory, do not update trait model.

### Evaluation Framework

How to prove the system is getting smarter, not just accumulating data:

1. **Brier score tracking**: Every falsifiable prediction gets a Brier score (0 = perfect, 1 = worst). Track monthly rolling average. The system is compounding if Brier scores decrease monotonically over months.
2. **Compounding Contribution Ratio (CCR)**: The key empirical test. CCR = accuracy of predictions that **require** accumulated model (trait-based, cross-signal, trajectory-aware) divided by accuracy of predictions achievable from **raw data alone** (base-rate, last-7-days). If CCR > 1.0 and increasing, the accumulated model is adding value beyond what fresh data provides. If CCR ≤ 1.0, the compounding mechanism is broken.
3. **Implicit behavioural validation**: Track whether the executive acts on insights (opens the briefing, dwells on specific sections, follows a recommendation) rather than asking them to rate quality. Survey feedback creates confirmation bias and survey fatigue.
4. **Counterfactual testing**: Monthly, run a "fresh system" simulation — give a fresh Opus instance access to raw data but no accumulated model. Compare its insight quality to the production system's. If the fresh system matches the production system, the model is not compounding.

Four conditions that together constitute proof of compounding:
- Brier scores declining month-over-month
- CCR > 1.0 and increasing
- Counterfactual gap widening (production system increasingly outperforms fresh system)
- Insight tier distribution shifting upward (more trait-level and prediction-level outputs, fewer observation-level)

---

## DATA STRUCTURES

### Memory Objects by Tier

**Tier 0 — Raw Observation** (~50 tokens)
```json
{
  "id": "obs_uuid",
  "tier": 0,
  "signal_type": "email_response_time",
  "timestamp": "2026-04-03T14:22:00Z",
  "value": 847,
  "unit": "seconds",
  "context": {
    "sender_category": "board_member",
    "sender_id": "contact_uuid",
    "day_type": "high_meeting",
    "calendar_load": 7.5
  },
  "baseline_deviation": null,
  "importance_score": null
}
```

**Tier 1 — Daily Summary** (200–400 tokens)
```json
{
  "id": "sum_uuid",
  "tier": 1,
  "date": "2026-04-03",
  "generated_by": "haiku",
  "summary": "High-density day (8 meetings, 127 emails). Response latency to CFO elevated 2.3x vs baseline. Keystroke speed stable. Calendar showed 3 back-to-back blocks with no transition buffer. Email processing shifted to 21:00–23:00 window (unusual — normally 07:00–09:00).",
  "signals_aggregated": 342,
  "anomalies": [
    {"signal": "email_response_time", "target": "cfo", "deviation_sigma": 2.3},
    {"signal": "email_processing_window", "shift": "morning_to_evening", "confidence": 0.87}
  ],
  "source_observation_ids": ["obs_uuid_1", "obs_uuid_2", "..."]
}
```

**Tier 2 — Behavioural Signature** (500–1000 tokens)
```json
{
  "id": "sig_uuid",
  "tier": 2,
  "pattern_type": "communication_priority",
  "description": "Board members receive sub-15-minute responses regardless of calendar load. Internal operational emails are batched and processed in evening windows. CFO emails show variable latency correlated with financial reporting cycle — faster during prep weeks, slower post-submission.",
  "evidence_window": {"from": "2026-01-15", "to": "2026-04-03"},
  "observation_count": 847,
  "validation_gates": {
    "statistical_significance": {"cohens_dz": 0.73, "passed": true},
    "temporal_stability": {"test_retest_r": 0.71, "weeks_sampled": 8, "passed": true},
    "contextual_replication": {"contexts_tested": 3, "contexts_passed": 3, "passed": true},
    "causal_coherence": {"mechanism": "stakeholder_hierarchy_prioritisation", "passed": true}
  },
  "confidence": 0.88,
  "status": "validated",
  "supporting_summary_ids": ["sum_uuid_1", "sum_uuid_2", "..."]
}
```

**Tier 3 — Trait / Executive Model Element** (1000–2000 tokens)
```json
{
  "id": "trait_uuid",
  "tier": 3,
  "trait_type": "decision_making_style",
  "version": 2,
  "valid_from": "2026-03-01",
  "valid_to": null,
  "description": "Pattern-interrupt decision maker. Fast, low-deliberation decisions on familiar operational categories (vendor selection, hiring below VP, budget allocations under $500K). Deliberately decelerates on novel strategic choices — introduces 48–72 hour delay, consults 2–3 external advisors, requests additional data. The deceleration is intentional and productive, not avoidance.",
  "precision": 0.82,
  "evidence_signatures": ["sig_uuid_1", "sig_uuid_2", "sig_uuid_3"],
  "previous_versions": [
    {"version": 1, "valid_from": "2026-01-15", "valid_to": "2026-02-28", "delta": "Initial version lacked the $500K threshold distinction — refined after observing 4 budget decisions above this line"}
  ],
  "predictions_enabled": [
    "Given novel strategic decision + no advisor consultation within 24h → predict delay/escalation with P=0.78",
    "Given familiar operational decision + response time >4h → flag as potential avoidance (deviates from established fast-decision pattern)"
  ]
}
```

### Capability Curve Data Structure

```json
{
  "milestone": "month_3",
  "data_state": {
    "observations": "~30K",
    "daily_summaries": "~90",
    "validated_signatures": "15-25",
    "trait_elements": "3-5 (provisional)"
  },
  "memory_tier_state": {
    "tier_0": "pruned to 30-day rolling window + flagged anomalies",
    "tier_1": "full 90-day archive",
    "tier_2": "15-25 validated, 40-60 pending",
    "tier_3": "3-5 provisional traits, none fully stable"
  },
  "capabilities_unlocked": [
    "Cross-signal correlation (calendar load × email latency × keystroke speed)",
    "Deviation alerts against stable baselines",
    "First behavioural predictions (low confidence, narrow scope)",
    "Sender-relationship map with priority tiers"
  ],
  "sample_output": "Your response time to the CFO has increased 40% over the past 3 weeks, specifically on threads tagged with Q3 budget. This correlates with a 2x increase in after-hours email processing. In previous months, this pattern preceded a meeting reschedule.",
  "comparable_human": "Executive assistant after 3 months — knows the routine, starting to anticipate"
}
```

### Pattern Confidence Schema

```json
{
  "pattern_id": "sig_uuid",
  "confidence": 0.88,
  "confidence_components": {
    "statistical": {"test": "arima_corrected_cohens_dz", "value": 0.73, "threshold": 0.5},
    "temporal": {"test": "test_retest_r", "value": 0.71, "threshold": 0.6},
    "contextual": {"contexts_passed": 3, "contexts_tested": 3},
    "causal": {"mechanism_plausibility": "high"}
  },
  "observation_count": 847,
  "effective_sample_size": 42,
  "confidence_trend": [
    {"date": "2026-02-01", "confidence": 0.61},
    {"date": "2026-03-01", "confidence": 0.78},
    {"date": "2026-04-01", "confidence": 0.88}
  ],
  "next_revalidation": "2026-04-15"
}
```

### Versioned Trait Model

```json
{
  "trait_id": "trait_uuid",
  "current_version": 3,
  "versions": [
    {
      "version": 1,
      "valid_from": "2026-01-15",
      "valid_to": "2026-02-28",
      "precision": 0.54,
      "description": "Appears to make decisions quickly across all categories",
      "change_trigger": null
    },
    {
      "version": 2,
      "valid_from": "2026-03-01",
      "valid_to": "2026-06-15",
      "precision": 0.82,
      "description": "Pattern-interrupt decision maker — fast on familiar, deliberately slow on novel",
      "change_trigger": "Refinement: threshold distinction emerged from additional observations"
    },
    {
      "version": 3,
      "valid_from": "2026-06-16",
      "valid_to": null,
      "precision": 0.79,
      "description": "Decision style shifted post-Q2 board meeting — now seeks 2 additional external opinions even on previously-familiar categories above $200K",
      "change_trigger": "BOCPD change point detected 2026-06-02, confirmed after 14-day quarantine"
    }
  ],
  "trajectory_narrative": "Decision-making style has become progressively more consultative over 6 months. Initial fast-across-the-board pattern refined to category-dependent by month 3. Post-Q2 board meeting, the consultation threshold dropped from $500K to $200K, suggesting increased risk sensitivity in financial decisions."
}
```

---

## ALGORITHMS

### Full Reflection Pipeline — Pseudocode

```
NIGHTLY_REFLECTION_PIPELINE(date):
  // STAGE 1: Observation → Daily Summary (Haiku)
  raw_observations = fetch_observations(date)
  baselines = fetch_current_baselines()

  for each obs in raw_observations:
    obs.baseline_deviation = compute_deviation(obs, baselines)
    obs.importance_score = haiku_importance_score(obs)  // 0.0–1.0

  daily_summary = haiku_generate_summary(
    observations=raw_observations,
    baselines=baselines,
    calendar_context=fetch_calendar(date),
    prompt="Summarise today's behavioural observations. Flag anomalies >1.5σ from baseline. Note cross-signal co-occurrences. Do not interpret — describe only."
  )
  store(daily_summary, tier=1)

  // STAGE 2: Daily patterns → Behavioural Signatures (Sonnet, weekly)
  if is_end_of_week(date):
    recent_summaries = fetch_summaries(last_7_days)
    existing_signatures = fetch_signatures(status="validated" OR "pending")

    candidate_patterns = sonnet_pattern_detection(
      summaries=recent_summaries,
      existing_patterns=existing_signatures,
      prompt="Compare this week's daily summaries against previous weeks. Identify: (a) patterns that strengthen existing signatures, (b) new candidate patterns appearing for the first time, (c) existing patterns that were violated this week. For each candidate, state the observable rule and the minimum evidence needed to validate."
    )

    for each candidate in candidate_patterns:
      if candidate.is_new:
        store(candidate, tier=2, status="pending", first_observed=date)
      else:
        existing = find_matching_signature(candidate)
        existing.evidence_count += 1
        run_four_gate_validation(existing)
        if existing.passes_all_gates:
          existing.status = "validated"
          existing.confidence = compute_confidence(existing)

  // STAGE 3: Signatures → Trait Synthesis (Opus, monthly)
  if is_end_of_month(date):
    validated_signatures = fetch_signatures(status="validated")
    current_traits = fetch_traits(valid_to=null)

    updated_model = opus_trait_synthesis(
      signatures=validated_signatures,
      current_model=current_traits,
      full_history=fetch_trait_versions(),
      prompt="You are building a cognitive model of one executive. Review all validated behavioural signatures and the current trait model. For each trait: (a) does the evidence still support it? Update precision. (b) should any traits be split, merged, or retired? (c) do the signatures suggest new traits not yet in the model? (d) generate trajectory narrative: how has this person changed? Output: structured executive model document with versioned traits.",
      config={extended_thinking: true, thinking_budget: 65536}
    )

    for each trait in updated_model:
      if trait.changed_from(current_traits):
        version_and_store(trait, change_trigger="monthly_synthesis")
      else:
        update_precision(trait)

  // STAGE 4: Model → Predictions (Opus, monthly + on-demand)
  if is_end_of_month(date):
    current_model = fetch_current_traits()
    upcoming_context = fetch_calendar(next_14_days) + fetch_known_events()

    predictions = opus_generate_predictions(
      model=current_model,
      context=upcoming_context,
      prompt="Given the current executive model and the upcoming 2-week context, generate falsifiable predictions. Each prediction MUST specify: (a) the predicted observable behaviour, (b) the time window, (c) the confidence level, (d) the trait(s) that ground the prediction, (e) what observation would falsify it. Do not generate predictions where the model confidence is below 0.6.",
      config={extended_thinking: true, thinking_budget: 65536}
    )

    for each prediction in predictions:
      store(prediction, status="pending", expires=prediction.time_window_end)

  // PRUNING
  prune_tier_0(retain_days=30, retain_flagged=true)
  update_baselines(date)
```

### N-of-1 Pattern Validation — Statistical Tests

```
FOUR_GATE_VALIDATION(signature):

  // GATE 1: Statistical significance (ARIMA-corrected Cohen's d_z)
  time_series = fetch_signal_timeseries(signature.signal_type, signature.evidence_window)
  arima_residuals = fit_arima(time_series).residuals  // remove autocorrelation
  baseline_residuals = arima_residuals[baseline_period]
  pattern_residuals = arima_residuals[pattern_period]
  cohens_dz = mean(pattern_residuals - baseline_residuals) / std(pattern_residuals - baseline_residuals)
  gate_1_pass = abs(cohens_dz) >= 0.5

  // GATE 2: Temporal stability (test-retest across non-adjacent weeks)
  weekly_values = partition_by_week(time_series)
  sample_pairs = select_non_adjacent_week_pairs(weekly_values, n_pairs=4)
  test_retest_r = mean([pearson_r(pair.week_a, pair.week_b) for pair in sample_pairs])
  gate_2_pass = test_retest_r >= 0.6

  // GATE 3: Contextual replication
  contexts = partition_by_context(time_series, context_variables=["calendar_load", "day_of_week", "meeting_density"])
  context_results = []
  for each context_group in contexts:
    if len(context_group) >= 10:  // minimum sample per context
      group_dz = compute_cohens_dz(context_group)
      context_results.append(abs(group_dz) >= 0.3)  // relaxed threshold per-context
  gate_3_pass = sum(context_results) >= 2 AND len(context_results) >= 2

  // GATE 4: Causal coherence (LLM review)
  coherence_judgment = sonnet_evaluate(
    prompt="This statistical pattern was detected: {signature.description}. Effect size: {cohens_dz}. Does this map to a known cognitive, behavioural, or organisational mechanism? If yes, name it. If no plausible mechanism exists, flag as potential artifact.",
    max_tokens=500
  )
  gate_4_pass = coherence_judgment.mechanism_identified == true

  signature.validation_gates = {gate_1_pass, gate_2_pass, gate_3_pass, gate_4_pass}
  return all_gates_pass(signature)
```

### Change-Point Detection — BOCPD

```
BOCPD_MONITOR(signal_stream):
  // Adams & MacKay (2007) Bayesian Online Change Point Detection
  // Run at three levels simultaneously

  levels = [SIGNAL, PATTERN, TRAIT]

  for each level in levels:
    run_length_distribution = initialize_uniform()
    hazard_rate = 1/250  // expect a change every ~250 observations (tunable)

    for each new_observation in signal_stream[level]:
      // Compute predictive probability under each run length
      for each r in run_length_distribution:
        predictive_prob[r] = student_t_predictive(
          observation=new_observation,
          sufficient_stats=stats[r]
        )

      // Growth probability (no change point)
      growth = run_length_distribution * predictive_prob * (1 - hazard_rate)

      // Change point probability
      changepoint = sum(run_length_distribution * predictive_prob * hazard_rate)

      // Update
      run_length_distribution = normalize(append(changepoint, growth))
      update_sufficient_stats(new_observation)

      // Detection
      if changepoint_probability > 0.7:  // threshold
        trigger_quarantine(level, new_observation.timestamp)

QUARANTINE_PROTOCOL(level, change_timestamp):
  quarantine_window = 14 days
  pre_change_data = fetch(change_timestamp - 30d, change_timestamp)
  post_change_data = fetch(change_timestamp, change_timestamp + 14d)

  CDI = (
    0.4 * magnitude_of_shift(pre_change_data, post_change_data) +
    0.35 * consistency_in_quarantine(post_change_data) +
    0.25 * cross_level_concordance(levels_flagging_change)
  )

  if CDI >= 0.65:
    // Genuine change
    old_trait = fetch_current_trait(level)
    version_trait(old_trait, valid_to=change_timestamp)
    new_trait = synthesize_new_trait(post_change_data, old_trait)
    store(new_trait, valid_from=change_timestamp)
    generate_trajectory_narrative(old_trait, new_trait)
  else:
    // Transient perturbation
    store_episodic_event(change_timestamp, "transient_deviation", post_change_data)
    // Do NOT update trait model
```

### Prediction Emergence

```
GENERATE_PREDICTIONS(executive_model, upcoming_context):
  // Only callable when model has >= 3 validated traits with precision >= 0.7

  active_traits = [t for t in executive_model if t.precision >= 0.7]
  predictions = []

  for each trait in active_traits:
    // Match trait to upcoming context
    relevant_contexts = match_trait_to_context(trait, upcoming_context)

    for each context in relevant_contexts:
      prediction = opus_predict(
        trait=trait,
        context=context,
        history=fetch_similar_historical_contexts(context),
        prompt="Given trait '{trait.description}' and upcoming context '{context}', what specific observable behaviour do you predict? State: the behaviour, the time window, your confidence (0-1), what would falsify this."
      )

      if prediction.confidence >= 0.6:
        predictions.append(prediction)

  // Cross-trait predictions (higher value, require multiple traits)
  trait_combinations = generate_pairs(active_traits)
  for each (trait_a, trait_b) in trait_combinations:
    cross_prediction = opus_predict(
      traits=[trait_a, trait_b],
      context=upcoming_context,
      prompt="These two traits interact: '{trait_a.description}' and '{trait_b.description}'. Given upcoming context, does their interaction predict something neither trait alone would predict?"
    )
    if cross_prediction.confidence >= 0.7:  // higher bar for cross-trait
      predictions.append(cross_prediction)

  return predictions
```

---

## APIS & FRAMEWORKS

### Model Tier Assignments

| Pipeline Stage | Model | Why |
|---------------|-------|-----|
| Observation importance scoring | Haiku 3.5 | High volume (~300+ observations/day), classification-only task, latency-sensitive |
| Daily summary generation | Haiku 3.5 | Summarisation of structured data, no reasoning required |
| Weekly pattern detection | Sonnet 4 | Requires cross-day comparison and pattern recognition, moderate reasoning |
| Four-gate causal coherence check | Sonnet 4 | Needs domain knowledge to evaluate mechanism plausibility |
| Monthly trait synthesis | Opus 4.6 | Deep reasoning across dozens of validated signatures, extended thinking enabled (64K thinking tokens), generates the executive model document |
| Prediction generation | Opus 4.6 | Requires multi-trait reasoning about novel future contexts, extended thinking enabled (64K thinking tokens) |
| Counterfactual evaluation | Opus 4.6 | Fresh instance with no model context, same prompt structure as production |

### Statistical Approaches

- **ARIMA**: For autocorrelation removal in behavioural time series before computing effect sizes. Use Swift-native implementation or call a Supabase Edge Function wrapping a statistical library.
- **Cohen's d_z**: Within-person effect size (paired/repeated measures). The subscript z indicates the standardised difference score, appropriate for single-subject designs.
- **Pearson's r**: For test-retest temporal stability across non-adjacent weeks.
- **Student's t predictive distribution**: Used inside BOCPD for computing observation likelihood under each run-length hypothesis.
- **Brier score**: For prediction calibration tracking. Brier = (1/N) * Σ(predicted_probability - outcome)^2. Range 0–1, lower is better.

No external ML frameworks needed. The statistical tests are simple enough to implement directly in Swift or TypeScript Edge Functions. BOCPD is the most complex algorithm — implement as a dedicated Edge Function with the Adams & MacKay formulation.

### Prompt Engineering Patterns

**Stage 1 (Haiku — summarisation):**
- System: "You are a behavioural observation summariser. Describe what happened. Do not interpret or explain why."
- Input: Structured observation array + baseline values
- Output: Natural language summary with anomaly flags
- Temperature: 0.0 (deterministic)

**Stage 2 (Sonnet — pattern detection):**
- System: "You are a behavioural pattern analyst. Compare this week's daily summaries against the existing pattern library. Identify strengthening patterns, new candidates, and violations."
- Input: 7 daily summaries + existing signature library
- Output: Structured pattern candidates with evidence counts
- Temperature: 0.3 (slight creativity for novel pattern identification)

**Stage 3 (Opus — trait synthesis):**
- System: "You are building the definitive cognitive model of one executive. This is your monthly synthesis. Review all validated behavioural signatures and the current trait model. Be precise. Be specific. Every claim must trace to named signatures."
- Input: All validated signatures + current trait model + version history
- Output: Updated executive model document with versioned traits and trajectory narrative
- Extended thinking: enabled, budget: 65536 tokens
- Temperature: 1.0 (extended thinking mode)

**Stage 4 (Opus — prediction):**
- System: "Generate falsifiable predictions. Every prediction MUST have: a specific observable, a time window, a confidence level, the grounding trait(s), and a falsification criterion. If you cannot specify all five, do not make the prediction."
- Input: Current executive model + upcoming 14-day context
- Output: Structured predictions array
- Extended thinking: enabled, budget: 65536 tokens
- Temperature: 1.0 (extended thinking mode)

---

## NUMBERS

### Time Requirements per Milestone

| Milestone | Minimum Data Required | What Becomes Reliable |
|-----------|----------------------|----------------------|
| 48 hours | ~500 observations | Communication energy level, email cadence fingerprint, calendar structure classification |
| Week 1 | ~2,500 observations | Daily rhythm detection, sender-priority rough ordering |
| Week 3 | ~7,500 observations | First candidate patterns pass Gate 1 (statistical significance) |
| Month 1 | ~10,000 observations | 5–10 patterns pass Gates 1+2 (significance + temporal stability). First daily summaries useful for anomaly detection |
| Month 3 | ~30,000 observations | 15–25 validated signatures (all 4 gates). 3–5 provisional traits. First low-confidence predictions |
| Month 6 | ~60,000 observations | 30–50 validated signatures. 8–12 stable traits. Prediction accuracy entering useful range (Brier < 0.3 for behavioural predictions) |
| Month 12 | ~120,000 observations | Full executive model. Trait versions with trajectory narratives. Prediction Brier < 0.2 for familiar domains. Novel-situation reasoning enabled |

### Statistical Thresholds

| Metric | Threshold | Meaning |
|--------|-----------|---------|
| Cohen's d_z (Gate 1) | ≥ 0.5 | Medium within-person effect — the pattern is meaningfully different from baseline |
| Test-retest r (Gate 2) | ≥ 0.6 | Moderate stability — pattern holds across non-adjacent weeks |
| Context replication (Gate 3) | ≥ 2 contexts with d_z ≥ 0.3 | Pattern is not context-dependent |
| BOCPD change point probability | ≥ 0.7 | Sufficient evidence to trigger quarantine |
| CDI (quarantine confirmation) | ≥ 0.65 | Change is genuine, not transient |
| Prediction surfacing minimum | confidence ≥ 0.6 | Below this, the prediction is not shown to the executive |
| Cross-trait prediction minimum | confidence ≥ 0.7 | Higher bar because cross-trait reasoning compounds uncertainty |
| Trait precision for prediction eligibility | ≥ 0.7 | Traits below this are too uncertain to generate predictions from |

### Expected Prediction Accuracy Trajectories

| Period | Brier Score (behavioural) | Brier Score (strategic) | CCR |
|--------|--------------------------|------------------------|-----|
| Month 1 | No predictions yet | — | — |
| Month 3 | 0.35–0.40 | — | 1.0–1.1 (barely above baseline) |
| Month 6 | 0.25–0.30 | 0.40–0.45 | 1.3–1.5 |
| Month 9 | 0.20–0.25 | 0.30–0.35 | 1.7–2.0 |
| Month 12 | 0.15–0.20 | 0.25–0.30 | 2.0–2.5 |

Behavioural predictions (will she respond within X hours, will she reschedule this meeting) improve faster than strategic predictions (will she reverse this decision, will she escalate to the board). Strategic predictions require deeper trait models and more historical context.

---

## ANTI-PATTERNS

### Accumulation vs Genuine Compounding

**Accumulation** = more data → more examples of the same patterns → marginally higher confidence. A system that has 100K observations but produces the same tier of insight as one with 30K observations is accumulating, not compounding.

**Genuine compounding** = more data → new representational layers → qualitatively different intelligence. Month 6 can do things month 3 cannot — not just the same things with more confidence. The test: can the system produce insights at month 6 that are structurally impossible to produce at month 3, regardless of data volume? If yes, it's compounding. If no, it's accumulating.

Failure modes that produce accumulation instead of compounding:
- Flat memory: all observations stored at same tier, no abstraction hierarchy
- Missing Stage 3: patterns detected but never synthesised into traits
- Missing Stage 4: traits exist but never used for prediction
- No version history: model updates overwrite history, destroying trajectory detection
- No cross-signal correlation: each signal analysed independently, never combined

### Catastrophic Forgetting Risks

- **Overwriting traits without versioning**: If a change-point updates the trait model and deletes the old version, the system loses the ability to detect trajectories and reason about who the executive used to be.
- **Aggressive pruning of Tier 0**: Raw observations are needed for re-analysis when new patterns are hypothesised retroactively. Prune to 30-day rolling window + flagged anomalies, never delete entirely.
- **Monthly synthesis without history context**: If the Opus synthesis prompt only sees current signatures and current traits (not historical versions), it cannot detect gradual drift — only abrupt changes.

Mitigation: Every trait is versioned with `valid_from` / `valid_to`. The synthesis prompt always includes the full version history. Tier 0 pruning retains anomalies indefinitely.

### Overfitting to Noise in Early Observations

The first 2 weeks are the highest risk for false pattern detection. The system has no baselines, so any regularity looks like a pattern. Mitigations:

- **No pattern promotion before week 3**: The four-gate protocol cannot run Gate 2 (temporal stability) until at least 3 non-adjacent weeks exist. This is a hard architectural constraint, not a tunable parameter.
- **Baseline establishment period**: Week 1–2 observations are explicitly flagged as `period: "baseline_establishment"`. No anomaly detection runs against them. They ARE the baseline.
- **Conservative early importance scoring**: During weeks 1–2, Haiku importance scoring is calibrated to assign lower scores across the board. The system should be listening, not reacting.

### Evaluation Pitfalls

- **Survey-based validation creates confirmation bias**: If you ask the executive "Was this insight useful?", they will say yes to be polite or because they anchored on the insight. Use implicit behavioural signals (dwell time, action taken, briefing opened) instead.
- **Measuring raw prediction count instead of accuracy**: A system that makes 100 predictions with 50% accuracy is worse than one that makes 10 predictions with 90% accuracy. Track Brier scores, not volume.
- **Ignoring the counterfactual**: If a fresh system with raw data access can produce the same insights, the compounding mechanism has failed. The CCR metric exists specifically to catch this.
- **Conflating model complexity with model quality**: A trait model with 50 traits is not necessarily better than one with 12 high-precision traits. Precision per trait matters more than trait count.
