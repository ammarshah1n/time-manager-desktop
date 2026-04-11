# Extraction: v2-10 — Behavioural Prediction Layer

Source: `research/perplexity-outputs/v2/v2-10-behavioural-prediction.md`

---

## DECISIONS

### Avoidance Detection Architecture
- **Signal model:** Three-stream detection — email response latency (sender-specific), calendar rescheduling (meeting-type-specific), document engagement (topic-specific). Each stream maps to a distinct avoidance mechanism: experiential avoidance (Hayes), cognitive avoidance/worry (Borkovec), approach-avoidance conflict (Lewin/Miller).
- **Baseline:** All signals normalised against personalised rolling baselines, not population norms. An executive who always replies slowly is not avoiding; one whose latency spikes 2+ sigma for a specific sender/topic cluster is.
- **Threshold:** Avoidance flagged when >=2 of 3 streams show simultaneous deviation from personal baseline for the same decision domain.
- **Strategic delay vs avoidance distinction:** Strategic delay involves continued information gathering (new sources consulted, new stakeholders contacted). Avoidance involves re-processing the same material, absence of new information sources, and topic-specific communication withdrawal. Network analysis of information flow is the discriminator — expanding information network = strategic; contracting or static network = avoidance.

### Burnout Prediction Pipeline
- **Leading indicators (in temporal order of appearance):** After-hours email ratio increase → response time distribution widening → calendar buffer erosion → voice prosody flattening (F0 range compression) → keystroke dynamics degradation (increased error rate, slower inter-key intervals) → communication network contraction.
- **Temporal aggregation:** Weekly rolling windows for fast signals (email, keystroke), monthly rolling windows for slow signals (voice prosody, network structure). Daily granularity stored but not used for prediction directly — too noisy.
- **Model:** LSTM + XGBoost ensemble. LSTM captures temporal trajectory shape; XGBoost handles cross-signal feature interactions at each time step. Ensemble weighting learned from validation set.
- **Triple gate for false positive control:** (1) 3-week minimum duration criterion — no alert on transient spikes, (2) 3-stream consistency — signals from >=3 different modalities must converge, (3) 2-of-3 MBI dimension convergence — emotional exhaustion + depersonalisation, or emotional exhaustion + reduced accomplishment must both show signal.

### Decision Reversal Prediction
- **Approach:** Cox proportional hazards survival model for time-to-reversal probability, combined with a 4-state Hidden Markov Model (Committed -> Consolidating -> Wavering -> Reversing) for state tracking post-decision.
- **Key features:** Time-to-initial-decision (fast decisions reversed more often), post-decision information seeking volume, communication pattern about the decision (re-explaining to stakeholders = consolidating; silence about it = potential wavering), consultation pattern breadth (narrow consultation -> higher reversal risk).
- **Temporal horizon:** Strongest predictive signal in T+4 to T+14 day window after initial decision. Before T+4, insufficient post-decision behaviour; after T+14, most reversals have already occurred or the decision has consolidated.
- **Healthy reconsideration vs problematic vacillation:** Discriminated via network analysis — new external information sources entering the picture = healthy reconsideration. Re-processing same material with no new inputs = vacillation. Svenson's Differentiation and Consolidation (DiffCon) theory provides the theoretical grounding.

### Bayesian Individual Decision Model
- **Architecture:** Hierarchical Bayesian model (Griffiths & Tenenbaum framework). Population-level priors from executive decision-making literature (Upper Echelons theory — Hambrick), individual-level parameters updated per observed decision.
- **Granularity:** Per-decision-domain models (financial, personnel, strategic, operational), NOT one unified model. Decision style varies by domain — an executive decisive on personnel may be deliberative on financial.
- **Context features:** Stakeholders involved (count + power dynamics), financial magnitude (log-scaled), time pressure (deadline proximity), domain familiarity (inferred from historical frequency), reversibility of the decision.
- **Concept drift handling:** Exponential forgetting factor on older observations. Recent decisions weighted more heavily. Changepoint detection (Bayesian Online Changepoint Detection) triggers model reset for a domain when a genuine style shift is detected, rather than gradual drift corrupting the model.
- **Confidence tracking:** Model tracks its own posterior variance per domain. High variance = insufficient data, suppress predictions. Low variance = stable model, predictions surfaced. Effective sample size >= 10 decisions in a domain before any prediction is made.

### Temporal Sequence Modelling Architecture
- **Primary choice: Temporal Fusion Transformer (TFT).** Reasons: (1) native multi-horizon forecasting, (2) built-in variable selection networks handle heterogeneous inputs (email timing, calendar structure, keystroke dynamics, voice features) without manual feature engineering, (3) interpretable attention weights — essential for executive-facing explanations of why a prediction was made, (4) handles irregularly-sampled time series natively via time-varying known inputs.
- **Bayesian head:** Replace TFT's quantile output layer with a Bayesian probabilistic head for calibrated uncertainty estimates. This gives the hybrid TFT-Bayesian architecture — neural feature extraction + probabilistic prediction.
- **State-space models (Mamba/S4):** Reserved for Phase 2 comparison. Advantage: O(n) vs O(n^2) attention. Disadvantage: less interpretable, fewer off-the-shelf multi-modal fusion patterns.
- **Foundation models (Chronos/MOIRAI):** Phase 1 — use as complementary anomaly detectors (zero-shot). Phase 2 (month 12+) — LoRA fine-tuning on accumulated individual data for personalised forecasting.

### Prediction Confidence Communication Framework
- **Phase-gated 12-month trust-building sequence:**
  - Months 1-3: Descriptive only — "here's what happened" summaries, no predictions. System learns baselines.
  - Months 4-6: Low-stakes predictions — meeting duration estimates, response time predictions, workload forecasts. Build track record.
  - Month 7+: High-stakes predictions — burnout trajectory, decision reversal risk, avoidance pattern detection. Only surfaced when P >= 0.85 AND effective sample size >= 10.
- **Confidence thresholds for surfacing:** Low-stakes predictions: P >= 0.70. Medium-stakes (workload, scheduling): P >= 0.80. High-stakes (burnout, reversal, avoidance): P >= 0.85-0.90.
- **Self-defeating prophecy resolution:** A burnout prediction that causes the executive to change behaviour is a *successful intervention*, not a false positive. System should track prediction-triggered behaviour changes as positive outcomes, not model failures.

---

## DATA STRUCTURES

### Behavioural Signal Taxonomy

| Signal | Psychological Construct | Reliability | Aggregation |
|--------|------------------------|-------------|-------------|
| Email response latency (sender-specific) | Experiential avoidance (Hayes) | High | Weekly rolling, per-sender z-score |
| After-hours email ratio | Emotional exhaustion (MBI) | High | Weekly ratio vs personal baseline |
| Calendar rescheduling frequency (meeting-type) | Approach-avoidance conflict | Medium-High | Weekly count, by meeting category |
| Calendar buffer erosion (gaps between meetings) | Reduced personal accomplishment (MBI) | Medium | Weekly, minimum gap tracking |
| Keystroke error rate | Cognitive load / fatigue | Medium | Daily session averages |
| Inter-key interval variance | Stress / decision fatigue | Medium | Per-composition-session |
| Application switching frequency | Cognitive fragmentation / avoidance | Medium | Hourly windows |
| Voice F0 (fundamental frequency) range | Emotional exhaustion (MBI) | High | Per-session, compared to personal baseline |
| Voice speech rate | Cognitive load | Medium | Per-session |
| Voice pause pattern (duration + frequency) | Deliberation vs avoidance | Medium | Per-session |
| Communication network breadth (unique contacts/week) | Depersonalisation (MBI) / social withdrawal | Medium-High | Weekly unique contact count |
| Post-decision information seeking volume | Decision instability (Svenson DiffCon) | High | Per-decision tracking window |
| Post-decision stakeholder re-explanation frequency | Decision consolidation stage | Medium-High | Per-decision |
| Time-to-decision | Decision confidence (inverse proxy) | Medium | Per-decision, domain-normalised |
| Meeting attendance vs scheduled | Disengagement / avoidance | Medium | Weekly ratio |
| Email length distribution shift | Communication effort / depersonalisation | Medium | Weekly, per-recipient-tier |
| Document open-without-edit events | Avoidance / procrastination on specific topics | Medium | Daily, topic-tagged |

### Burnout Detection Schema

```
BurnoutAssessment {
  executive_id: UUID
  assessment_date: Date
  observation_window_weeks: Int  // minimum 8
  
  mbi_dimensions: {
    emotional_exhaustion: {
      score: Float  // 0.0 - 1.0 normalised
      signals: [
        { signal: "after_hours_email_ratio", value: Float, z_score: Float, trend: "rising|stable|falling" },
        { signal: "voice_f0_range", value: Float, z_score: Float, trend: String },
        { signal: "keystroke_error_rate", value: Float, z_score: Float, trend: String }
      ]
      confidence: Float  // posterior variance inverse
    }
    depersonalisation: {
      score: Float
      signals: [
        { signal: "communication_network_breadth", ... },
        { signal: "email_length_distribution", ... },
        { signal: "meeting_attendance_ratio", ... }
      ]
      confidence: Float
    }
    reduced_accomplishment: {
      score: Float
      signals: [
        { signal: "calendar_buffer_erosion", ... },
        { signal: "document_open_without_edit", ... },
        { signal: "time_to_decision_trend", ... }
      ]
      confidence: Float
    }
  }
  
  triple_gate: {
    duration_met: Bool       // 3+ weeks sustained
    stream_consistency: Int  // number of converging modalities (need >= 3)
    mbi_convergence: Bool    // 2-of-3 dimensions flagged
  }
  
  burnout_probability: Float      // 0.0 - 1.0
  lead_time_estimate_weeks: Int?  // weeks before projected clinical threshold
  surfaceable: Bool               // all gates passed + P >= 0.85 + month >= 7
}
```

### Decision Reversal Model Features

```
DecisionReversalAssessment {
  decision_id: UUID
  executive_id: UUID
  decision_date: Date
  domain: "financial" | "personnel" | "strategic" | "operational"
  
  initial_features: {
    time_to_decision_minutes: Float
    consultation_breadth: Int           // unique stakeholders consulted
    consultation_depth: Float           // avg interaction count per stakeholder
    financial_magnitude_log: Float
    time_pressure_score: Float          // 0-1, deadline proximity
    domain_familiarity: Float           // historical frequency in domain
    reversibility: Float               // 0-1, estimated
  }
  
  post_decision_tracking: {
    days_since_decision: Int
    information_seeking_volume: Int     // new searches, docs opened on topic
    new_information_sources: Int        // previously unconsulted sources
    same_source_revisits: Int           // re-processing indicator
    stakeholder_re_explanations: Int    // mentions/discussions of the decision
    communication_sentiment_shift: Float
  }
  
  hmm_state: "committed" | "consolidating" | "wavering" | "reversing"
  hmm_state_probability: [Float]        // 4-element probability vector
  
  survival_model: {
    reversal_probability_7d: Float
    reversal_probability_14d: Float
    reversal_probability_30d: Float
    hazard_rate: Float
  }
  
  is_healthy_reconsideration: Bool      // network analysis: expanding info sources
  confidence: Float
}
```

### Prediction Confidence Schema for UX

```
PredictionSurface {
  prediction_id: UUID
  prediction_type: "burnout" | "reversal" | "avoidance" | "workload" | "schedule"
  stakes_level: "low" | "medium" | "high"
  
  probability: Float
  confidence_interval: (lower: Float, upper: Float)
  effective_sample_size: Int
  model_maturity_months: Int
  
  surfacing_decision: {
    meets_probability_threshold: Bool   // low: 0.70, medium: 0.80, high: 0.85-0.90
    meets_sample_threshold: Bool        // ESS >= 10 for high-stakes
    meets_phase_threshold: Bool         // high-stakes only after month 7
    approved_to_surface: Bool           // all three true
  }
  
  explanation: {
    primary_signal: String              // most influential signal (from TFT attention)
    secondary_signals: [String]
    temporal_context: String            // "over the past 3 weeks..."
    confidence_language: String         // "likely" | "very likely" | "emerging pattern"
  }
  
  outcome_tracking: {
    prediction_resolved: Bool
    actual_outcome: String?
    behaviour_change_detected: Bool     // self-defeating prophecy = success
    calibration_error: Float?
  }
}
```

---

## ALGORITHMS

### Avoidance Detection

1. **Per-sender email response latency tracking:** Maintain rolling 30-day baseline per sender. Compute z-score for each new response. Flag when z > 2.0 for a specific sender cluster persists > 5 business days.
2. **Calendar rescheduling pattern detection:** Tag each meeting with type (board, 1:1, client, internal). Track reschedule count per type per week. Flag when reschedule rate for a specific type exceeds 2 sigma above personal baseline for 2+ consecutive weeks.
3. **Document engagement avoidance:** Track document-open events by topic tag. Flag when a document is opened 3+ times without meaningful edit (< 5% content change) within a decision deadline window.
4. **Cross-stream fusion:** Avoidance declared when >= 2 of 3 streams flag simultaneously for the same decision domain (domain inferred from sender/meeting/document topic clustering).
5. **Strategic delay discriminator:** On each flag, check information network expansion — are new sources being consulted? If yes, reclassify as strategic delay. If information network is static or contracting, confirm avoidance.

### Burnout Risk Scoring Pipeline

1. **Signal ingestion:** Continuous collection of all 17 signals into time-indexed store.
2. **Personalised baseline normalisation:** 8-week bootstrap period to establish individual baselines. All signals converted to z-scores against personal rolling baseline (not population).
3. **MBI dimension scoring:** Map each signal to its MBI dimension (see taxonomy). Within each dimension, weighted average of constituent signal z-scores. Weights learned from LSTM feature importance.
4. **LSTM temporal trajectory:** Feed weekly MBI dimension score vectors into LSTM. LSTM outputs trajectory shape classification: stable, deteriorating, recovering, volatile.
5. **XGBoost cross-signal interaction:** At each weekly time step, feed all 17 raw z-scores + LSTM hidden state into XGBoost classifier. Output: burnout probability.
6. **Triple gate filtering:** Only surface if (a) deteriorating trajectory sustained 3+ weeks, (b) signals from 3+ modalities converge, (c) 2-of-3 MBI dimensions show elevation.
7. **False positive analysis:** Primary false positive source is high-workload sprints (intense but not burnout). Distinguish via: sprint has a known end date on calendar + communication network stays intact (no social withdrawal) + voice prosody remains variable (not flattened).

### Decision Stability Model

- **Features:** Time-to-decision, consultation breadth, financial magnitude, domain familiarity, reversibility, time pressure.
- **Architecture:** Cox proportional hazards for time-to-reversal baseline. Hidden Markov Model (4 states) for post-decision state tracking, updated daily with post-decision behavioural observations.
- **Training:** Cox model trained on historical decisions where outcomes are known. HMM transition probabilities initialised from literature (Svenson DiffCon stage durations), then updated via Baum-Welch from observed data.
- **Temporal horizon:** Predictions most reliable in T+4 to T+14 window. Before T+4, HMM has insufficient observations. After T+14, most decisions have consolidated or reversed.
- **Confidence calibration:** Cox model outputs are Platt-scaled. HMM state probabilities are inherently calibrated. Ensemble combines both via stacking.

### Bayesian Updating for Individual Decision Patterns

1. **Prior initialisation:** Hierarchical prior from population-level executive decision data (Upper Echelons literature). Weakly informative — dominated by individual data after ~5 observations per domain.
2. **Likelihood function:** For each observed decision, compute P(observed_features | decision_style_parameters). Features: time-to-decision, consultation pattern, outcome quality (if observable).
3. **Posterior update:** Standard Bayesian update per domain after each decision. Store full posterior distribution, not point estimates.
4. **Concept drift detection:** Run Bayesian Online Changepoint Detection (Adams & MacKay, 2007) in parallel. When changepoint probability > 0.8, reset domain prior to weakly informative and begin relearning.
5. **Prediction suppression:** Track effective sample size (ESS) per domain. If ESS < 10, do not surface predictions for that domain. Report model uncertainty instead.

### Temporal Fusion of Multi-Modal Behavioural Signals

1. **Input encoding:** Each signal type gets its own encoder. Continuous signals (email latency, keystroke intervals): temporal convolutional layer. Categorical signals (meeting type, decision domain): embedding layer. Irregular sampling handled via time-since-last-observation feature.
2. **Variable selection network:** TFT's built-in variable selection learns per-time-step which signals are most informative. This handles the heterogeneous reliability problem — unreliable signals get down-weighted automatically.
3. **Multi-head interpretable attention:** Attention mechanism over the temporal dimension. Attention weights are extractable and serve as explanations ("this prediction is primarily driven by your email patterns over the last 2 weeks").
4. **Bayesian output head:** Replace quantile regression output with a Bayesian layer (variational inference or MC dropout). Outputs: mean prediction + calibrated uncertainty interval.
5. **Foundation model anomaly detection:** Run Chronos/MOIRAI in parallel on each signal stream (zero-shot). Flag when foundation model anomaly score diverges from TFT prediction — indicates distribution shift or novel pattern.

---

## APIS & FRAMEWORKS

### Temporal Fusion Transformer (TFT)
- Reference: Lim et al., 2021 — "Temporal Fusion Transformers for Interpretable Multi-horizon Time Series Forecasting"
- Why for Timed: native multi-modal input handling, interpretable attention (critical for executive-facing explanations), handles irregularly-sampled series, built-in variable selection network removes need for manual feature engineering.
- Implementation: PyTorch Forecasting library or custom Swift/Python bridge. TFT runs in the nightly Opus reflection pipeline (Python sidecar), not on-device real-time.

### Mamba / S4 State-Space Models
- Reference: Gu et al., 2023 (Mamba), Gu et al., 2022 (S4)
- Why reserved for Phase 2: O(n) computational complexity vs TFT's O(n^2) attention becomes relevant when observation windows exceed 12+ months of high-frequency data. Less interpretable — attention weight explanations not available.
- Potential use: Replace TFT backbone when data volume makes attention prohibitive, OR use as secondary model in ensemble.

### Bayesian Cognitive Modelling (Griffiths & Tenenbaum)
- Reference: Griffiths & Tenenbaum, 2006 — "Optimal Predictions in Everyday Cognition"; Griffiths et al., 2008 — "Bayesian Models of Cognition" (Cambridge Handbook)
- Application: Framework for the hierarchical Bayesian individual decision model. Population-level priors + individual-level updating. Concept of "rational analysis" — model what the executive *should* do given their information, then measure deviation as a diagnostic signal.

### Maslach Burnout Inventory (MBI) Digital Correlates
- Reference: Maslach & Jackson, 1981; Maslach, Schaufeli & Leiter, 2001
- Three dimensions mapped to digital signals:
  - **Emotional exhaustion** -> after-hours email ratio, voice F0 compression, keystroke error rate
  - **Depersonalisation** -> communication network contraction, email brevity increase, meeting attendance decline
  - **Reduced personal accomplishment** -> calendar buffer erosion, increased time-to-decision, document open-without-edit patterns

### Time-Series Foundation Models (2023-2025)
- **Chronos** (Amazon, 2024): Tokenises time series for language model architecture. Use zero-shot as anomaly detector in Phase 1.
- **MOIRAI** (Salesforce, 2024): Universal forecasting model, any-variate. Use for cross-signal anomaly detection.
- **LoRA fine-tuning path:** At month 12+ with sufficient individual data, fine-tune Chronos/MOIRAI via LoRA for personalised single-executive forecasting. Compare against TFT-Bayesian hybrid.

### Bayesian Online Changepoint Detection
- Reference: Adams & MacKay, 2007
- Application: Detect genuine decision-style shifts (not noise). When changepoint probability > 0.8, reset domain model prior. Prevents concept drift from corrupting long-term individual models.

### Svenson's Differentiation and Consolidation (DiffCon) Theory
- Reference: Svenson, 1992, 2003
- Application: Theoretical basis for the 4-state HMM in decision reversal model. Maps cognitive stages (pre-decision differentiation, post-decision consolidation) to observable behavioural states.

### Russo's Predecisional Distortion
- Reference: Russo et al., 1996, 2006
- Application: Detectable in post-decision behaviour — an executive exhibiting predecisional distortion will show selective information seeking that confirms the initial decision. Absence of this pattern (equal attention to confirming/disconfirming information) predicts higher reversal risk.

### Dietvorst Algorithm Aversion
- Reference: Dietvorst, Simmons & Massey, 2015
- Application: People reject algorithmic predictions about themselves after seeing the algorithm err once. Mitigation: phase-gated credibility building (months 1-6 low-stakes predictions), and always present predictions as "patterns observed" not "you will do X".

### Logg Algorithm Appreciation
- Reference: Logg, Minson & Moore, 2019
- Application: Counterpoint to Dietvorst — people sometimes over-rely on algorithms. Risk for Timed: executive may defer too much to the system's burnout/reversal predictions. Mitigation: always frame as "input to your judgment" not "diagnosis".

---

## NUMBERS

- **Burnout prediction earliest reliable window:** 8-12 weeks of observation before any burnout prediction is meaningful.
- **Burnout prediction lead time:** 4-8 weeks before the executive would self-report or clinically acknowledge burnout. This is the intervention window.
- **False positive rate in existing digital burnout systems:** 20-35% without gating. Triple gate (3-week duration + 3-stream consistency + 2-of-3 MBI convergence) reduces to estimated 8-12%.
- **Decision reversal prediction horizon:** T+4 to T+14 days post-decision is the strongest predictive window. After T+14, most decisions have consolidated or already reversed.
- **Minimum observation for burnout predictions:** 8 weeks baseline + 3 weeks sustained signal = 11 weeks minimum before first burnout alert.
- **Minimum decisions per domain for Bayesian model:** Effective sample size >= 10 before surfacing domain-specific predictions.
- **Confidence thresholds for surfacing predictions:** Low-stakes >= 0.70, medium-stakes >= 0.80, high-stakes >= 0.85-0.90.
- **Trust-building timeline:** Descriptive-only months 1-3, low-stakes predictions months 4-6, high-stakes predictions month 7+.
- **Population prior dominance:** Hierarchical Bayesian prior dominated by individual data after ~5 observations per domain.
- **Changepoint detection threshold:** Bayesian Online Changepoint probability > 0.8 triggers domain model reset.
- **Avoidance detection persistence threshold:** Signal must persist > 5 business days for email latency, > 2 consecutive weeks for calendar rescheduling.
- **17 behavioural signals** in the full taxonomy mapped to psychological constructs.
- **4 HMM states** for decision reversal tracking: Committed, Consolidating, Wavering, Reversing.
- **3 MBI dimensions** each with distinct digital signal mappings.

---

## ANTI-PATTERNS

### Strategic Delay vs Avoidance (Hard Boundary)
- **The problem:** An executive taking 2 weeks on a decision could be doing deep analysis or avoiding it. Misclassification in either direction destroys trust.
- **The discriminator:** Information network analysis. Strategic delay = expanding information network (new sources, new stakeholders, new documents). Avoidance = static or contracting network (re-reading same material, no new consultations, topic-specific communication withdrawal).
- **Implementation rule:** NEVER flag avoidance if information network is expanding. Default to "strategic delay" when ambiguous. False negatives (missing avoidance) are cheaper than false positives (wrongly accusing an executive of avoiding).

### Self-Defeating Prophecy Risk
- **The problem:** Telling an executive "you are approaching burnout" may cause them to change behaviour, making the prediction appear wrong.
- **The resolution:** Reframe in the model. A prediction that triggers behaviour change is a *successful intervention*, not a false alarm. Track prediction-triggered behaviour changes as positive outcomes. Calibration metrics must account for this — a system where 50% of burnout predictions "don't happen" because the executive acted is a 50% intervention success rate, not a 50% false positive rate.
- **UX implication:** Never frame burnout predictions as "you will burn out." Frame as "patterns consistent with increasing load — here's what's driving it" with actionable levers.

### Algorithm Aversion (Dietvorst)
- **The problem:** Executives reject predictions about themselves after seeing one error. A single visible false positive can destroy months of credibility.
- **Mitigation:** Phase-gated credibility building — 6 months of low-stakes correct predictions before any high-stakes prediction. Never present predictions as certainties. Use "patterns observed" language, not "you will" language. Give the executive control — they can dismiss a prediction and the system learns from the dismissal.
- **Recovery protocol:** After a visible error, the system should acknowledge it explicitly ("last week's pattern didn't play out — here's what was different") rather than silently moving on. Transparent error acknowledgment rebuilds trust faster than pretending it didn't happen.

### Overfitting to Early Data
- **The problem:** First 2-3 months of data may not be representative (executive may be in an unusual period — board season, M&A, personal stress). Models trained on this window will be miscalibrated.
- **Mitigation:** 8-week baseline period with NO predictions surfaced. Effective sample size tracking per domain — suppress predictions until ESS >= 10. Hierarchical Bayesian priors prevent early observations from dominating — population prior provides regularisation until sufficient individual data accumulates.
- **Hard rule:** Never present a prediction in months 1-3 regardless of apparent signal strength. The system has not earned the right to predict yet.

### Conflating Workload Spikes with Burnout Trajectory
- **The problem:** A 3-week sprint with long hours, fast emails, and compressed calendar looks like burnout signals but is a normal workload spike.
- **Discriminator:** Sprint has a known end date visible on calendar. Communication network stays intact (no social withdrawal). Voice prosody remains variable (burnout flattens it; sprints may increase variability). Executive's own framing of the period (if captured via voice notes) indicates challenge, not depletion.
- **Implementation rule:** If a workload spike has a visible end date within 4 weeks AND communication network breadth is stable, suppress burnout scoring for that period.

### Model Confidence Inflation
- **The problem:** As models accumulate data, confidence intervals narrow. But executive behaviour genuinely changes — concept drift means narrow confidence intervals may be overfit to an obsolete pattern.
- **Mitigation:** Bayesian Online Changepoint Detection running in parallel. Mandatory confidence recalibration every 90 days. Never let effective sample size alone drive confidence — recency-weighted ESS is the correct metric.
