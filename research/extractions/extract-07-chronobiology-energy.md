# Extract 07 — Chronobiology & Energy Modelling

Source: `research/perplexity-outputs/v2/v2-07-chronobiology-energy.md`

---

## DECISIONS

### Chronotype Inference from Digital Behaviour
- **Primary signal (Tier 1):** First/last keyboard activity timestamps. Correlation with sleep onset/offset r = 0.74-0.80. Use the GRSVD method (Nature npj, 2025) to extract diurnal rhythms from typing patterns — accurate enough to detect timezone desynchrony.
- **Secondary signal (Tier 2):** Email send-time distributions. Twitter/social-media send-time research validates digital activity timestamps as chronotype proxies at population level (Allbrink et al., PBS/Nova coverage). No peer-reviewed validation specifically for email response latency as executive chronotype proxy — treat as reasonable but unvalidated inference requiring per-individual calibration.
- **Tertiary signals (Tier 3, unvalidated):** Message length variation across day, creative output timing, response latency patterns. Use for model enrichment after Tier 1/2 are calibrated, not as standalone features.
- **Algorithm:** Bayesian updating of chronotype priors. Start with population prior (Roenneberg MCTQ distribution: ~40% intermediate, ~25% moderate morning, ~25% moderate evening, ~10% extreme types). Update daily with observed first-activity and last-activity timestamps. Confidence interval narrows over 2-3 weeks of observation.
- **Re-estimation cadence:** Continuous Bayesian update with exponential decay weighting (recent days weighted more). Full re-estimation trigger when 7-day rolling mean of first-activity shifts by >45 minutes from the current model midpoint.

### Ultradian Rhythm Detection
- **Approach:** Monitor 90-120 minute BRAC (Basic Rest-Activity Cycle) via keystroke velocity, application switching frequency, email response clustering, and activity pauses.
- **Detection method:** Sliding window autocorrelation over keystroke interkey interval time series. Look for periodicity in the 80-130 minute band. Supplement with activity gap detection — natural pauses >5 minutes that cluster at ~90-minute intervals.
- **Confidence:** Evidence for waking ultradian rhythms is weaker than circadian. Lavie's ultrashort sleep-wake cycle research shows attentional peaks/troughs exist but individual variation is high. Treat ultradian estimates as probabilistic, not deterministic. 15-minute temporal resolution is realistic; sub-5-minute is not.

### Energy Depletion Model
- **Inputs:** Calendar meeting density, keystroke dynamics (interkey interval mean + variance, hold time, flight time, backspace rate), application switching frequency, email response patterns, time since last detected break (>10 min inactivity).
- **Decay function:** Energy E(t) decays with each depletion driver, recovers during breaks. Model as: `E(t) = E_base - sum(driver_costs) + sum(recovery_gains)`, clamped to [0, 1].
- **Depletion driver weights (initial, calibrate per individual):**
  - Consecutive meetings without break: high cost (0.15 per 30-min meeting, compounding +0.05 per consecutive)
  - Context switching (domain jump detected from app/email topic change): 0.08 per switch
  - Decision density (proxy: email send rate of substantive messages): 0.05 per decision-class email
  - Emotional labour (proxy: meeting with flagged difficult contacts, detected from calendar attendees + historical patterns): 0.12 per instance
  - Information overload (proxy: inbox volume spike): 0.03 per standard deviation above daily mean
- **Recovery:** Break of 10-20 min recovers 0.10-0.15. Lunch break (>30 min inactivity) recovers 0.25-0.35. Overnight reset to 1.0 (modulated by previous day's terminal energy — if previous day ended at E < 0.3, next day starts at 0.85 not 1.0).
- **Ego depletion note:** Baumeister's resource model largely failed replication. Use the motivation-shift model instead: fatigue does not drain a literal resource but shifts motivation toward low-effort choices. This means depletion manifests as task avoidance and satisficing, not inability — the model should detect these behavioural shifts rather than assuming a hard capacity limit.

### Cognitive Scheduling Recommendations
- **Analytical/executive-function work:** Schedule during circadian peak (morning for morning types, evening for evening types). Performance variation peak-to-trough is 15-30% on executive function tasks.
- **Insight/creative work (Wieth & Zacks inversion):** Deliver at NON-optimal circadian time. Insight problem-solving rate is 0.42 at non-optimal vs 0.33 at peak. The inhibitory-control reduction at off-peak times enables broader associative thinking.
- **Routine/administrative work:** Schedule during ultradian troughs or post-meeting recovery windows. Low cognitive demand, high completion satisfaction.
- **Strategic decisions:** Protect first 2 hours of peak period. Porter & Nohria's Harvard CEO study: executives who allocated uninterrupted blocks to strategy reported higher effectiveness. No "first decision of the day" anchoring effect validated in literature.
- **Batching:** Email, approvals, one-on-ones benefit from batching (reduced context-switching cost of ~23 minutes attention residue per switch, Leroy 2009). Strategic thinking and creative problem-solving suffer from batching — require incubation periods between sessions.

### Timing-Aware Insight Delivery Rules
- **Routine briefings:** Deliver during morning ramp-up or post-lunch recovery. Low cognitive demand.
- **Strategic recommendations:** Deliver during circadian peak, high E(t). Require analytical processing capacity.
- **Creative/novel framings:** Deliver during off-peak per Wieth & Zacks. Executive's reduced inhibition enables receptivity to unconventional patterns.
- **Uncomfortable patterns / relationship warnings:** Deliver during peak E(t), NOT during troughs. Emotional regulation capacity is highest when energy is high. Never deliver after 3+ consecutive meetings.
- **Urgent alerts:** Override timing rules. Deliver immediately with context note: "Surfacing this now despite non-optimal timing because urgency exceeds timing benefit."
- **Flow protection:** If sustained focus detected (keystroke velocity stable or rising, low app switching, E(t) > 0.5), hold ALL non-urgent insights. Flow state is more valuable than optimal delivery timing.

---

## DATA STRUCTURES

### Chronotype Model Schema
```
ChronotypeModel {
  user_id: UUID
  estimated_chronotype: Float        // MSFsc (mid-sleep on free days, corrected) — continuous scale, not categorical
  chronotype_category: Enum          // extreme_morning | moderate_morning | intermediate | moderate_evening | extreme_evening
  confidence: Float                  // 0.0-1.0, increases with observation days
  observation_days: Int              // days of data collected
  features: {
    first_activity_mean: Time        // rolling 14-day mean of first keyboard/email activity
    first_activity_std: Duration     // variability — lower = more reliable
    last_activity_mean: Time
    last_activity_std: Duration
    email_send_peak_hour: Float      // hour with highest email send density
    keystroke_rhythm_phase: Float    // GRSVD-extracted phase angle from typing patterns
    weekend_vs_weekday_shift: Duration // social jet lag indicator
  }
  prior_distribution: {              // Bayesian prior, updated daily
    mean: Float
    variance: Float
  }
  last_updated: DateTime
  re_estimation_trigger: Bool        // true if 7-day rolling mean shifted >45 min
}
```

### Energy Budget Model
```
EnergyState {
  user_id: UUID
  timestamp: DateTime
  current_energy: Float              // 0.0-1.0
  phase: Enum                        // ramp_up | peak | plateau | declining | depleted | recovering
  depletion_drivers: [
    {
      driver_type: Enum              // meeting_load | context_switch | decision_density | emotional_labour | info_overload
      weight: Float                  // individual-calibrated weight
      accumulated_cost: Float        // cost accrued today from this driver
      last_event: DateTime
    }
  ]
  ultradian_estimate: {
    cycle_position: Float            // 0.0-1.0 within current 90-120 min cycle
    minutes_to_next_trough: Int
    confidence: Float                // low until ~2 weeks of data
  }
  recovery_events_today: [
    {
      type: Enum                     // micro_break | short_break | lunch | overnight
      start: DateTime
      duration: Duration
      energy_recovered: Float
    }
  ]
  keystroke_fatigue_signals: {
    interkey_interval_zscore: Float   // current session vs personal baseline
    backspace_rate_zscore: Float
    hold_time_zscore: Float
    degradation_asymmetry: Enum      // accuracy_only | speed_and_accuracy | none
  }
  terminal_energy_yesterday: Float   // for next-day start calibration
}
```

### Timing Decision Framework
```
DeliveryDecision {
  insight_id: UUID
  insight_type: Enum                 // routine_briefing | strategic_recommendation | creative_framing | uncomfortable_pattern | relationship_warning | urgent_alert
  cognitive_state: {
    energy_level: Float              // from EnergyState.current_energy
    circadian_phase: Enum            // peak | off_peak | trough
    ultradian_phase: Enum            // ascending | peak | descending | trough
    flow_detected: Bool              // sustained focus with stable/rising velocity
    consecutive_meetings: Int        // count of back-to-back meetings just ended
  }
  decision: Enum                     // deliver_now | hold_for_peak | hold_for_off_peak | queue_for_tomorrow | deliver_with_caveat
  reasoning: String                  // logged for model validation and user trust
  hold_expiry: DateTime?             // if held, when to force-deliver regardless
}
```

---

## ALGORITHMS

### Chronotype Inference
1. **Collect:** First keyboard activity timestamp and last keyboard activity timestamp daily. Separate weekdays from weekends.
2. **Initialise prior:** Roenneberg population distribution (MSFsc mean ~4:00 AM, SD ~1.5h). If age known, shift prior (chronotype advances ~30 min per decade after age 20).
3. **Daily Bayesian update:** Observe first-activity time. Likelihood function: Normal(observed_first_activity | MSFsc - sleep_duration/2, sigma_observation). Update posterior via conjugate Normal-Normal update.
4. **Weekend/weekday correction:** Weekend first-activity times are closer to true chronotype (less alarm-driven). Weight weekend observations 2x in the Bayesian update.
5. **GRSVD extraction (weekly):** Apply Generalised Regularised SVD to the past 7 days of keystroke timing data. Extract the dominant diurnal component. Phase angle of this component cross-validates the Bayesian MSFsc estimate.
6. **Convergence criterion:** Model is "useful" when posterior SD < 45 minutes. Typically reached at 10-14 days of observation.
7. **Drift detection:** If 7-day rolling mean of first-activity shifts >45 min from current model midpoint AND sustained for 5+ days, trigger re-estimation with widened prior (prior SD doubled).

### Ultradian Cycle Estimation
1. **Feature stream:** Compute 5-minute rolling statistics of keystroke interkey interval, app-switch count, and activity gap duration.
2. **Autocorrelation:** Every 30 minutes, compute autocorrelation of the interkey interval time series over the past 4 hours. Look for peaks in the 80-130 minute lag band.
3. **Phase estimation:** If a reliable period P is detected (autocorrelation peak > 0.3), estimate current phase as `(minutes_since_last_trough mod P) / P`.
4. **Trough detection:** A trough is signalled when interkey interval z-score > 1.5 AND app-switch rate drops below baseline AND a natural pause > 5 minutes occurs.
5. **Confidence:** Report confidence as the autocorrelation peak value. Below 0.2, suppress ultradian estimates entirely.

### Energy Level Estimation Pipeline
1. **Morning initialisation:** E(0) = 1.0, or 0.85 if previous day's terminal energy was < 0.3.
2. **Continuous depletion:** Every 5 minutes, compute depletion increment: `delta_E = -sum(active_driver_weights * driver_intensity)`.
   - Meeting intensity: 1.0 during meetings, compounding +0.33 per consecutive meeting without break.
   - Context switching: detected from app-switch to different domain (email -> spreadsheet -> browser -> different email thread). Count per 30-min window.
   - Decision density: count of sent emails classified as substantive (not replies, not forwarding) per 30-min window.
3. **Recovery detection:** Inactivity > 10 minutes triggers recovery accrual. Recovery rate: 0.01/min for first 10 min, 0.005/min thereafter (diminishing returns).
4. **Keystroke cross-validation:** Compare current E(t) estimate with keystroke fatigue signals. If keystroke signals indicate fatigue (interkey interval z-score > 1.0, backspace rate elevated) but E(t) > 0.6, the model is likely underweighting a depletion driver — log for calibration.
5. **Output:** E(t) as float 0-1, plus qualitative phase label (ramp_up/peak/plateau/declining/depleted/recovering).

### Delivery Timing Decision Tree
```
IF insight_type == urgent_alert:
  → deliver_now (with caveat note if E(t) < 0.4)

IF flow_detected == true AND insight_type != urgent_alert:
  → hold_for_peak (hold_expiry = flow_end + 15 min)

IF insight_type == creative_framing:
  IF circadian_phase == off_peak AND E(t) > 0.3:
    → deliver_now
  ELSE:
    → hold_for_off_peak

IF insight_type IN [strategic_recommendation, uncomfortable_pattern, relationship_warning]:
  IF circadian_phase == peak AND E(t) > 0.6 AND consecutive_meetings < 2:
    → deliver_now
  ELIF E(t) > 0.6:
    → deliver_now (non-peak acceptable if energy is high)
  ELSE:
    → hold_for_peak (hold_expiry = end_of_next_business_day)

IF insight_type == routine_briefing:
  IF E(t) > 0.3 AND flow_detected == false:
    → deliver_now
  ELSE:
    → queue_for_tomorrow (morning ramp-up slot)

DEFAULT:
  → hold_for_peak
```

---

## APIS & FRAMEWORKS

### Roenneberg's Chronotype Framework
- Munich Chronotype Questionnaire (MCTQ): gold standard for chronotype assessment. Defines chronotype as MSFsc (mid-sleep on free days, sleep-corrected). Continuous scale, not categorical bins.
- Timed cannot administer MCTQ but can infer MSFsc from digital behaviour. First-activity and last-activity timestamps approximate sleep offset and onset. Weekend data approximates free-day sleep timing.
- Population distribution: MSFsc peaks around 4:00 AM with SD ~1.5 hours. Skews later for younger populations, earlier for older.

### BRAC Detection Methods
- Kleitman's Basic Rest-Activity Cycle: ~90-minute oscillation in arousal/attention during waking hours.
- Detection from behaviour: look for periodicity in keystroke tempo, activity bursts, and natural pauses. Autocorrelation of activity time series is the standard computational approach.
- Lavie's ultrashort sleep-wake paradigm validated ~90-min attentional cycling but with high individual variability. Some individuals show no detectable ultradian rhythm in waking data.

### Bayesian Updating for Chronotype Priors
- Conjugate Normal-Normal model: prior N(mu_0, sigma_0^2), likelihood N(x | mu, sigma_obs^2), posterior is Normal with updated mean and precision.
- Update rule: `mu_post = (mu_0/sigma_0^2 + x/sigma_obs^2) / (1/sigma_0^2 + 1/sigma_obs^2)`, `sigma_post^2 = 1 / (1/sigma_0^2 + 1/sigma_obs^2)`.
- sigma_obs encodes observation noise (alarm-driven waking, social obligations). Weekend observations get lower sigma_obs (more informative).
- Alternative: Hidden Markov Model with states {morning_type, intermediate, evening_type} and emission probabilities tied to activity timing. HMM is heavier but handles multimodal schedules (e.g., executive with Mon-Wed early, Thu-Fri late). Only worth it if Bayesian Normal model shows poor fit after 30+ days.

### macOS APIs for Activity Timing Capture
- **Keystroke timing:** `CGEvent` tap (requires Accessibility permission) or `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`. Capture timestamps only, not content. Interkey interval, hold time, flight time derivable from keyDown/keyUp pairs.
- **Application switching:** `NSWorkspace.shared.runningApplications` polling or `NSWorkspace.didActivateApplicationNotification`. Log app bundle ID + timestamp.
- **Activity/inactivity:** `IOKit` idle time via `IOServiceGetMatchingService` for `IOHIDSystem`. Poll every 60 seconds. Inactivity > 10 minutes = break candidate.
- **Email metadata:** Microsoft Graph API `/me/messages` with `$select=sentDateTime,receivedDateTime,from,toRecipients,subject` (no body). Polling interval: 5 minutes.
- **Calendar:** Microsoft Graph API `/me/calendarview` for meeting density and attendee lists.

---

## NUMBERS

- **Peak-to-trough cognitive performance variation:** 15-30% on executive function tasks (inhibition, working memory). Up to 20% on analytical reasoning. Wieth & Zacks: insight problem-solving is 27% BETTER at non-optimal time (0.42 vs 0.33 solve rate).
- **Ultradian cycle duration:** 80-120 minutes (Kleitman's original estimate 90 min, subsequent research shows 80-120 range with individual variation). Attentional fluctuation amplitude within ultradian cycle: 5-15% of peak.
- **Minimum observation window for chronotype inference:** 10-14 days for Bayesian posterior SD < 45 min (useful estimate). 5-7 days for coarse categorical assignment. 30+ days for high-confidence continuous MSFsc.
- **Email send-time as chronotype proxy:** Twitter activity timing correlates with MCTQ chronotype at population level (validated). Individual email send-time has not been peer-reviewed as a chronotype proxy for executives — reasonable inference, not validated. First keyboard activity correlates with sleep offset at r = 0.74-0.80 (validated).
- **Keystroke fatigue detection:** AUC 72-80% for fatigue classification from typing dynamics. Key features: interkey interval (mean, variance), hold time, flight time, backspace rate.
- **Context-switching cost:** ~23 minutes of attention residue per switch between unrelated tasks (Leroy, 2009). Cumulative: 4 context switches in a morning = ~90 minutes of degraded attention.
- **Meeting fatigue compounding:** Microsoft Research brain-scan study (2021): back-to-back meetings without breaks produce cumulative beta-wave stress accumulation. 4+ consecutive 30-min meetings without a break = measurable cognitive impairment.
- **Decision fatigue (Danziger et al.):** Parole board study showed favourable decisions dropped from ~65% to ~0% within each decision session, resetting after food breaks. Subsequent critiques (Weinshall-Margel & Shapard) argue case ordering was confounded. Use the pattern (depletion over decision sequences, reset with breaks) but not the specific magnitudes.
- **Chronotype stability:** Test-retest reliability of MCTQ over 3-6 months: r > 0.85. Chronotype advances ~30 min per decade after age 20. Seasonal variation: ~15-30 minutes shift in MSFsc between winter and summer. Sufficient stability for a model that re-estimates continuously.

---

## ANTI-PATTERNS

### Confounders That Break Chronotype Inference
- **Jet lag:** Disrupts first-activity timing for 1-3 days per timezone crossed. Detection: calendar shows travel or multi-timezone meetings. Mitigation: flag travel days, exclude from chronotype updates for N days = timezones crossed.
- **Illness:** Irregular activity patterns, extended inactivity. Detection: sudden drop in total daily activity volume + irregular timing. Mitigation: pause chronotype updates when daily activity drops below 50% of 14-day rolling mean.
- **DST transitions:** 1-hour shift in clock-referenced activity that is NOT a chronotype shift. Mitigation: use UTC internally, convert to local time only for display. Apply known DST transitions as clock corrections, not model updates.
- **Alarm-driven waking:** Weekday first-activity times reflect alarm clock, not chronotype. Mitigation: weight weekend/free-day observations 2x. The weekday-weekend gap itself (social jet lag) is a chronotype signal — larger gap = more evening chronotype.
- **Seasonal light exposure:** MSFsc shifts 15-30 min between summer and winter. This is real biological variation, not noise. Allow the model to track it but flag it as seasonal, not lifestyle change.

### Conflating Sustained Focus with Flow vs Fatigue
- Sustained keyboard activity with low app switching can mean flow (high value) OR fatigue-driven tunnel vision (low value). Identical surface signal.
- **Disambiguation rule:** Check keystroke velocity trajectory. Flow: velocity stable or rising, error rate stable. Fatigue: velocity declining, error rate rising. Cross-reference with E(t) — if energy budget estimates E < 0.3, "sustained focus" is almost certainly fatigue-driven perseveration, not flow.
- Never interrupt flow. Always offer recovery prompts during detected fatigue. Getting this wrong in either direction destroys trust.

### Population Norms Applied to Individuals
- Roenneberg's distribution, Wieth & Zacks' insight timing, and all depletion research are population-level findings. An individual executive may not match.
- Use population data ONLY to initialise priors. All weights, thresholds, and timing rules must be individually calibrated within 30 days of observation.
- Never tell the executive "you're a morning type" based on population statistics. Wait for individual data to converge.

### Over-Precise Energy Estimates from Noisy Signals
- E(t) is an estimate, not a measurement. Keystroke fatigue detection AUC is 72-80% — that means 20-28% of fatigue states are missed or falsely detected.
- Never present energy level as a precise number to the executive. Use qualitative bands: high / moderate / low / depleted.
- Internal model uses continuous float for computation. External presentation uses 4-level categorical.
- Recalibrate driver weights monthly by comparing E(t) trajectory against behavioural outcomes (email quality proxies, decision timing, self-reported "good days" if available).
