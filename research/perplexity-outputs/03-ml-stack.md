# Timed ML Stack — Single-User Productivity Optimization

## Executive Summary

This document answers six concrete ML implementation questions for a single-user (N=1), sparse-data productivity app with 15–20 tasks/day. The core recommendation across all six areas: **favour lightweight Bayesian methods over complex ML** — they converge with dozens of observations rather than thousands, provide calibrated uncertainty, and degrade gracefully when data is thin. Avoid gradient-boosted trees and deep models entirely at this scale. Contextual Thompson sampling with a linear reward model is the recommended task-ordering backbone; conformalized quantile regression gives calibrated duration intervals; inverse reward weighting via pairwise ranking replaces hardcoded scoring; and a simple harmonic regression on hourly bins detects the chronotype within 3–4 weeks. The signal set should be expanded with four high-value extras: deferral count, context-switch distance, estimation calibration ratio, and meeting-density load.

***

## 1. Task Ordering Algorithm: What Converges Fastest?

### Algorithm Comparison

For a single user with 15–20 tasks/day, the number of ordering decisions accumulates at roughly 15–20 per day, giving ~420–560 observations over 4 weeks — too sparse for tree-based models, marginally viable for logistic regression, and ideal for Bayesian bandit methods.[^1][^2]

| Algorithm | Data to converge | Handles context | Uncertainty | Recommendation |
|---|---|---|---|---|
| Per-bucket Thompson sampling (current) | ~20–30/bucket | No | Bayesian β | Good baseline, but blind to task features |
| Contextual Thompson sampling (LinTS) | ~50–100 total | Yes (linear) | Bayesian | **Recommended upgrade** |
| LinUCB | ~50–100 total | Yes (linear) | Deterministic UCB | Good, but greedy bias risk[^3] |
| Logistic regression (online SGD) | ~200–400 | Yes | None (point) | Viable week 3+, no cold-start |
| Gradient-boosted trees | 1000+ | Yes | None | Far too data-hungry at N=1 |

**Why LinTS beats per-bucket Thompson sampling:** Per-bucket TS treats bucket type as the only context. Contextual TS incorporates all task features (estimated minutes, hour_of_day, times_deferred, sender_importance) as a feature vector, producing a reward model \( r = \mathbf{w}^T \mathbf{x} \) that generalises across buckets. The Beta distribution becomes a Gaussian posterior over weights — this is the key architectural change.[^4][^5]

**Why not logistic regression:** Logistic regression has no principled uncertainty quantification. It will confidently order tasks incorrectly in weeks 1–2 because it has no mechanism to say "I don't know enough yet" and explore.[^6][^1]

**Why not GBTs:** Gradient-boosted trees require hundreds to thousands of samples to form reliable splits; they will overfit to the first 2 weeks' noise and show no improvement in the target window.[^7]

### Cold-Start Strategy

Before any data exists, fall back to the hardcoded scoring weights as a deterministic prior (urgency > deadline > overdue). In LinTS, this translates to a non-zero prior mean \( \mu_0 \) that encodes your domain knowledge, rather than a zero-mean uninformative prior. This prevents random initial ordering and gives week 1 reasonable behaviour.

***

## 2. Time Estimation: Calibrated Prediction Intervals

### The Core Problem with EMA

EMA gives a single point estimate with implicit assumption of symmetric error — wrong for task durations, which are highly right-skewed (tasks routinely run long, rarely run short). A 15-minute estimate with an EMA might be accurate on average, but the user needs to know the realistic worst-case (P90) to plan slack. EMA provides neither a credible interval nor a calibrated one.[^8][^9]

### Method Comparison

| Method | Sparse data (<100 obs) | Gives intervals | Calibrated | Handles skew | Complexity |
|---|---|---|---|---|---|
| EMA (current) | ✓ fast convergence | ✗ | ✗ | ✗ | Trivial |
| Hierarchical Bayes (user/category priors) | ✓✓ borrows strength | ✓ credible interval | ✓ | Partial | Moderate |
| Kernel density estimation | ✗ needs 30–50+ | ✓ | ✓ empirically | ✓ | Low |
| Conformalized quantile regression (CQR) | ✓ (5–20 cal points) | ✓ guaranteed | ✓ finite-sample | ✓ | Low–moderate |

**Recommended: Hierarchical Bayesian duration model + CQR calibration**

Hierarchical Bayesian models are specifically designed for sparse individual data: they borrow statistical strength across task categories (do_first, reply, etc.) so that a new email task seen twice still gets a reasonable estimate anchored on all other email tasks. The posterior is a log-normal distribution (duration is positive and skewed), giving a natural credible interval.[^10][^11]

CQR (conformalized quantile regression) wraps any base estimator and provides **distribution-free, finite-sample guaranteed coverage** of prediction intervals. Applied on top of the Bayesian estimate, it corrects for model misspecification using only ~15–20 calibration points — achievable within 1–2 weeks.[^12][^13][^14]

### Practical Implementation

```python
# Log-normal duration model per bucket+sender pair
# With category-level hierarchical prior

import numpy as np
from scipy.stats import norm

class HierarchicalDurationModel:
    def __init__(self):
        # Category-level priors (log scale)
        # Learned from first 2 weeks of any task type
        self.category_prior = {
            'do_first': {'mu': np.log(25), 'sigma': 0.8},
            'action':   {'mu': np.log(15), 'sigma': 0.9},
            'reply':    {'mu': np.log(8),  'sigma': 0.7},
            'read':     {'mu': np.log(5),  'sigma': 0.6},
        }
        # Individual bucket+sender posteriors
        self.posteriors = {}  # key: (bucket, sender) -> (mu, sigma, n)

    def update(self, bucket, sender, actual_minutes):
        key = (bucket, sender)
        log_t = np.log(max(actual_minutes, 0.5))
        prior = self.category_prior.get(bucket, {'mu': np.log(15), 'sigma': 1.0})

        if key not in self.posteriors:
            self.posteriors[key] = {
                'mu': prior['mu'],
                'sigma': prior['sigma'],
                'obs': [],
            }

        state = self.posteriors[key]
        state['obs'].append(log_t)
        n = len(state['obs'])

        # Bayesian update: known prior variance, observed mean
        sigma_prior = prior['sigma']
        sigma_obs = 0.5  # assumed observation noise in log space
        mu_prior = prior['mu']

        # Posterior mean (precision-weighted)
        prec_prior = 1 / sigma_prior**2
        prec_obs = n / sigma_obs**2
        mu_post = (prec_prior * mu_prior + prec_obs * np.mean(state['obs'])) / (prec_prior + prec_obs)
        sigma_post = np.sqrt(1 / (prec_prior + prec_obs))

        state['mu'] = mu_post
        state['sigma'] = sigma_post

    def predict(self, bucket, sender, alpha=0.10):
        """Returns (p50, p90, lower_90_interval) in minutes."""
        key = (bucket, sender)
        prior = self.category_prior.get(bucket, {'mu': np.log(15), 'sigma': 1.0})
        state = self.posteriors.get(key, {'mu': prior['mu'], 'sigma': prior['sigma']})

        mu = state['mu']
        sigma = state['sigma']

        p50 = np.exp(mu)
        p90 = np.exp(mu + norm.ppf(0.90) * sigma)
        p10 = np.exp(mu + norm.ppf(0.10) * sigma)

        return {'p50': p50, 'p90': p90, 'p10': p10}
```

**CQR calibration layer (add after 20+ observations):**

```python
class CQRCalibrator:
    """Applies conformalized quantile regression to widen/narrow intervals."""
    def __init__(self, alpha=0.10):
        self.alpha = alpha
        self.calibration_scores = []  # store nonconformity scores

    def calibrate(self, predicted_p10, predicted_p90, actual):
        """Add a calibration point. Run after each completed task."""
        score = max(predicted_p10 - actual, actual - predicted_p90)
        self.calibration_scores.append(score)

    def conformalize(self, pred_p10, pred_p90):
        """Adjust interval to guarantee (1-alpha) coverage."""
        if len(self.calibration_scores) < 10:
            return pred_p10, pred_p90  # fall back to raw interval

        n = len(self.calibration_scores)
        # Empirical (1-alpha)(1+1/n) quantile of scores
        q_level = np.ceil((1 - self.alpha) * (n + 1)) / n
        q_level = min(q_level, 1.0)
        q_hat = np.quantile(self.calibration_scores, q_level)

        return pred_p10 - q_hat, pred_p90 + q_hat
```

This two-layer approach gives **P50 for display + P90 for scheduling slack** — far more useful than a single EMA point estimate.

***

## 3. Learning Scoring Weights Instead of Hardcoding Them

### Why Hardcoded Weights Fail

The current weights (urgency=1000, deadline=800, etc.) were likely set by intuition. A user who routinely ignores urgency flags but always completes overdue items in the morning would be poorly served. Worse, the relative magnitudes are arbitrary: is urgency really 5× more important than mood to this specific user?[^15]

### Method Comparison

| Method | N=1 viability | Convergence | Interpretable | Complexity |
|---|---|---|---|---|
| Online SGD on pairwise preferences | ✓✓ | ~50–100 pairs (3–5 days) | ✓ weight vector | Low |
| Inverse RL (MaxEnt IRL) | ✓ | ~100–200 trajectories | ✓ | Moderate |
| Bayesian optimization of weight configs | ✓ | ~30–50 evaluations (slow) | ✗ black box | Moderate |
| A/B testing weight configurations | ✗ | Weeks–months per config | ✓ | High overhead |

**Recommended: Pairwise inverse reward learning via online SGD**

This is the approach from the IRL literature adapted for N=1. Every time the user completes tasks, you observe their *actual* completion order vs. your *predicted* order. Each deviation is a training signal: the user preferred task B over task A despite your model saying A first. That's a pairwise preference \( B \succ A \). You accumulate these and update the weight vector via gradient descent to maximise the log-likelihood of observed orderings.[^16][^15]

```python
import numpy as np

class RewardWeightLearner:
    """
    Online inverse reward learning via pairwise ranking.
    Maintains a weight vector over task scoring features.
    """
    def __init__(self, feature_names, lr=0.01, l2=0.001):
        self.feature_names = feature_names
        self.n_features = len(feature_names)
        # Initialize weights from domain knowledge (not zero!)
        self.weights = np.array([
            1.0,   # urgency (normalised)
            0.8,   # deadline_proximity
            0.6,   # overdue
            0.2,   # mood_match
            0.15,  # timing_score
            0.05,  # sender_importance
        ], dtype=float)
        self.lr = lr
        self.l2 = l2

    def score(self, task_features: np.ndarray) -> float:
        return float(self.weights @ task_features)

    def update_from_reorder(self, preferred_features: np.ndarray,
                             avoided_features: np.ndarray):
        """
        Call when user does task B before task A despite model preferring A.
        preferred_features: feature vector of the task user did first (B)
        avoided_features:   feature vector of the task user skipped (A)
        """
        diff = preferred_features - avoided_features  # B - A

        # Logistic loss gradient: push w·diff to be positive
        s_pref = self.weights @ preferred_features
        s_avoid = self.weights @ avoided_features
        p = 1 / (1 + np.exp(s_pref - s_avoid))  # prob model was wrong

        # Gradient step: p * diff (+ L2 regularisation)
        self.weights += self.lr * (p * diff - self.l2 * self.weights)
        # Clamp weights to be non-negative (preserve interpretability)
        self.weights = np.maximum(self.weights, 0.0)

    def get_named_weights(self):
        return dict(zip(self.feature_names, self.weights))
```

**Convergence**: With ~15 tasks/day and an average of 3–5 reordering events per day, you accumulate ~100 pairwise signals in 3–5 days — sufficient for stable weight estimates.[^2][^15]

**Weekly LLM integration**: Your weekly Claude Opus job should also output a qualitative weight adjustment suggestion (e.g., "User consistently does action items before read items regardless of urgency — consider increasing action weight relative to urgency"). Translate these into soft nudges on the weight prior, not hard overrides.

***

## 4. Energy Curve / Chronotype Detection

### What the Data Contains

From `behaviour_events` with `hour_of_day`, `actual_minutes`, and `task_type`, you can extract: completion rate per hour bin, mean efficiency (estimated_minutes / actual_minutes) per hour, and task-type distribution by hour (e.g., deep work in the morning vs. replies in the afternoon).

### Method Comparison

| Method | Minimum data | Signal extracted | Robust to noise | Complexity |
|---|---|---|---|---|
| Binned completion rate (hourly) | **1–2 weeks** | Rate, mean efficiency | Low | Trivial |
| Harmonic regression (cos/sin) | **2–3 weeks** | Period, phase, amplitude | High | Low |
| Gaussian process (periodic kernel) | **3–4 weeks** | Full shape, uncertainty | High | Moderate |
| Circadian alignment model | 4–8 weeks | Phase offset, chronotype | High | High |

**Minimum viable: Harmonic regression at 2–3 weeks**

Circadian analysis papers confirm that reliable cosinor (harmonic) fits on activity data require at minimum one full 24-hour cycle of adequate sampling, with 2–3 weeks providing stable phase estimates. A Gaussian process with periodic squared-exponential kernel can detect rhythmicity even in noisy, non-uniformly sampled data, but requires ~3–4 weeks.[^17][^18][^19][^20]

**Recommended: Two-stage approach**

- **Weeks 1–2**: Simple binned efficiency (9 bins: 07:00–09:00, 09:00–11:00, … 23:00+). Normalise each bin by tasks completed. Use this immediately to adjust timing_score.
- **Week 3+**: Fit a harmonic regression to extract a smooth chronotype curve. This smooths over day-to-day noise and generalises to hours not yet observed.

```python
import numpy as np
from scipy.optimize import curve_fit

class ChronotypeModel:
    def __init__(self, n_bins=9):
        # Hourly bins: index 0 = 07:00-09:00, etc.
        self.bins = np.zeros(n_bins)
        self.counts = np.zeros(n_bins)
        self.bin_hours = [8, 10, 12, 14, 16, 18, 20, 22, 0]  # bin centres

        # Harmonic model parameters (fit at week 3+)
        self.harmonic_params = None  # (A, phi, B) in A*cos(2pi/24 * h + phi) + B

    def log_completion(self, hour_of_day: int, efficiency: float):
        """efficiency = estimated_minutes / actual_minutes (>1 = fast, <1 = slow)"""
        bin_idx = min(int((hour_of_day - 7) / 2), len(self.bins) - 1)
        bin_idx = max(bin_idx, 0)
        n = self.counts[bin_idx]
        # EMA update to allow drift
        alpha = 0.1 if n > 5 else 0.5
        self.bins[bin_idx] = (1 - alpha) * self.bins[bin_idx] + alpha * efficiency
        self.counts[bin_idx] += 1

    def fit_harmonic(self):
        """Fit a 24-hour cosine curve. Call after >= 3 weeks of data."""
        hours = np.array(self.bin_hours, dtype=float)
        y = self.bins.copy()
        valid = self.counts > 2

        if valid.sum() < 4:
            return  # insufficient data

        def harmonic(h, A, phi, B):
            return A * np.cos(2 * np.pi / 24 * h + phi) + B

        try:
            popt, _ = curve_fit(harmonic, hours[valid], y[valid],
                                p0=[0.2, -1.0, 1.0],
                                bounds=([-1, -np.pi, 0], [1, np.pi, 2]))
            self.harmonic_params = popt
        except Exception:
            pass  # fall back to binned model

    def get_timing_score(self, hour_of_day: int, task_type: str) -> float:
        """Returns a score in [0, 1] for scheduling this task at this hour."""
        if self.harmonic_params is not None:
            A, phi, B = self.harmonic_params
            raw = A * np.cos(2 * np.pi / 24 * hour_of_day + phi) + B
        else:
            bin_idx = min(int((hour_of_day - 7) / 2), len(self.bins) - 1)
            bin_idx = max(bin_idx, 0)
            raw = self.bins[bin_idx] if self.counts[bin_idx] > 0 else 1.0

        # Normalize to [0, 1]
        return float(np.clip(raw / 2.0, 0, 1))
```

**Key insight:** The timing_score output feeds directly into your existing scoring pipeline with a learned weight (from the reward learner above), creating an end-to-end adaptive system. Research on biobehavioral rhythms shows that modelling cyclic behaviour patterns from even 1–6 weeks of data yields meaningful productivity correlations.[^21]

***

## 5. Signals Beyond Completion/Duration

These six signals are ranked by implementation difficulty vs. predictive value for a single-user app:

### High-Value, Low-Cost

**Deferral count (`times_deferred`)** is already tracked. Research on procrastination dynamics shows that repeated deferral is driven by effort-discounting — the user is weighting the subjective effort cost as too high for the current context. A task deferred 3+ times should have its estimated effort recalibrated upward (the user is implicitly signalling it feels harder than estimated) and its timing_score adjusted to match when the user eventually does complete it.[^22][^23]

**Estimation calibration ratio** (`estimated_minutes / actual_minutes` per task type): Track per-bucket systematic bias. Research confirms users overestimate task duration by a median of 45% on some task types while underestimating others. A calibration ratio of 0.6 for `reply` tasks means EMA should scale that bucket's output up by 1/0.6 before display. Crucially, track *improvement* in this ratio over time as a ML health metric.[^8]

### Moderate-Value, Moderate-Cost

**Task-switch distance** (how cognitively distant is task N from task N+1): Context-switch costs are real — APA research confirms switching between complex tasks costs up to 40% of productive time. Operationalise as a simple categorical distance: same-sender → distance 0, same-bucket → distance 1, different-bucket → distance 2, cross-domain (e.g., reply then deep-work) → distance 3. Penalise large switches in the ordering score. Track `switch_cost_incurred` as the delta between estimated completion time and actual when a high-distance switch occurred.[^24]

**Calendar fragmentation index**: The ratio of meeting hours to available work hours, with a specific focus on block sizes between meetings. A day with 4 × 30-minute meetings has the same total meeting time as 2 × 60-minute meetings, but dramatically less deep work capacity. Calculate: `fragmentation = meetings / min_block_minutes` where min_block is the shortest contiguous focus window. When fragmentation > 2.0, automatically deprioritise deep-work `do_first` tasks (they won't complete anyway) and surface `reply` and `read` tasks instead.[^25][^26]

### Lower-Priority

**Deferral-time pattern**: Not just how many times a task is deferred, but *at what hour* it gets deferred and *at what hour* it eventually gets done. This refines the chronotype model — if tasks are always deferred at 14:00 and done at 10:00 the next day, that's an energy signal, not a difficulty signal.[^22]

**Email/message load correlation**: Track the count of incoming messages in the 30 minutes before task start. High inbox volume before starting correlates with higher actual_minutes (attention fragmentation). This can be captured as a context feature in the LinTS model without separate modelling.[^27][^26]

### Signal Tracking Schema

```sql
-- Add to behaviour_events
ALTER TABLE behaviour_events ADD COLUMN times_deferred INTEGER DEFAULT 0;
ALTER TABLE behaviour_events ADD COLUMN deferral_hours REAL[];  -- hours at which deferrals happened
ALTER TABLE behaviour_events ADD COLUMN prev_task_bucket TEXT;  -- for switch distance
ALTER TABLE behaviour_events ADD COLUMN estimation_ratio REAL;  -- estimated/actual
ALTER TABLE behaviour_events ADD COLUMN calendar_frag_score REAL;  -- fragmentation at task start
ALTER TABLE behaviour_events ADD COLUMN inbox_load_30m INTEGER;  -- messages in prior 30min
```

***

## 6. Contextual Thompson Sampling — Full Implementation

This is the primary upgrade from per-bucket Beta TS to feature-aware ordering.

### Algorithm Design

**Reward model:** Task completion quality is a linear function of features: \( r_t = \mathbf{w}^T \mathbf{x}_t + \epsilon \) where \( \epsilon \sim \mathcal{N}(0, \sigma^2) \).

**Posterior:** Maintain a Gaussian posterior over \( \mathbf{w} \): \( \mathbf{w} | \text{data} \sim \mathcal{N}(\mu_n, \Sigma_n) \).

**Thompson step:** Sample \( \tilde{\mathbf{w}} \sim \mathcal{N}(\mu_n, \Sigma_n) \), then score each task \( \hat{r}_k = \tilde{\mathbf{w}}^T \mathbf{x}_k \), and rank by \( \hat{r}_k \).

### Feature Vector Specification

```python
def build_feature_vector(task, current_hour: int, user_state: dict) -> np.ndarray:
    """
    Returns a normalised feature vector for contextual Thompson sampling.
    All features should be in [0, 1] range.
    """
    # Urgency: binary flag (0 or 1) from task metadata
    urgency = float(task.get('is_urgent', 0))

    # Deadline proximity: 1.0 = overdue, 0.5 = due today, 0.0 = due in 7+ days
    days_until = task.get('days_until_due', 99)
    deadline_prox = max(0.0, 1.0 - days_until / 7.0) if days_until >= 0 else 1.2  # overdue > 1

    # Times deferred: sigmoid to bound to [0, 1]
    n_defer = task.get('times_deferred', 0)
    defer_signal = 1 / (1 + np.exp(-0.5 * (n_defer - 2)))

    # Estimated duration: longer tasks get lower score (bucket into short/med/long)
    est_mins = task.get('estimated_minutes', 15)
    duration_inv = 1.0 - min(est_mins / 60.0, 1.0)

    # Timing score: from ChronotypeModel
    timing = user_state['chronotype'].get_timing_score(current_hour, task['bucket'])

    # Sender importance: pre-calculated score [0, 1] from sender_importance table
    sender_imp = task.get('sender_importance', 0.5)

    # Calendar fragmentation: pre-calculated for current day
    frag_penalty = 1.0 - min(user_state.get('frag_score', 0), 1.0)

    # Bucket type one-hot (4 buckets)
    bucket_oh = [
        float(task['bucket'] == 'do_first'),
        float(task['bucket'] == 'action'),
        float(task['bucket'] == 'reply'),
        float(task['bucket'] == 'read'),
    ]

    return np.array([
        urgency,
        deadline_prox,
        defer_signal,
        duration_inv,
        timing,
        sender_imp,
        frag_penalty,
        *bucket_oh,
    ])

FEATURE_DIM = 11  # 7 scalar + 4 bucket one-hot
```

### Full LinTS Implementation

```python
import numpy as np

class ContextualThompsonSampler:
    """
    Linear Thompson Sampling for task ordering.
    Maintains a Gaussian posterior over reward weights.
    """
    def __init__(self, feature_dim: int = FEATURE_DIM,
                 prior_variance: float = 1.0,
                 noise_variance: float = 0.5):
        self.d = feature_dim
        self.noise_var = noise_variance

        # Prior: N(mu0, Sigma0)
        # mu0 encodes domain knowledge (not zero-mean)
        self.mu = np.array([
            1.0,   # urgency
            0.8,   # deadline_proximity
            0.3,   # defer_signal (defer is weak signal on its own)
            0.2,   # duration_inv (shorter preferred)
            0.5,   # timing_score
            0.3,   # sender_importance
            0.4,   # frag_penalty
            0.5, 0.5, 0.5, 0.5,  # bucket one-hots (neutral start)
        ])
        self.Sigma = np.eye(self.d) * prior_variance

        # Sufficient statistics for online Bayesian update
        self.A = np.eye(self.d) / prior_variance   # precision matrix
        self.b = self.A @ self.mu                  # precision-weighted mean

    def sample_weights(self) -> np.ndarray:
        """Sample w ~ N(mu_n, Sigma_n) for Thompson step."""
        mu_n = np.linalg.solve(self.A, self.b)
        Sigma_n = np.linalg.inv(self.A)
        return np.random.multivariate_normal(mu_n, Sigma_n)

    def rank_tasks(self, task_features: list[np.ndarray]) -> list[int]:
        """
        Returns indices of tasks in recommended order (highest score first).
        Call once per day when building the daily plan.
        """
        w_sample = self.sample_weights()
        scores = [float(w_sample @ x) for x in task_features]
        return sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)

    def update(self, completed_feature: np.ndarray, reward: float):
        """
        Update posterior after observing a completion.
        reward: float in [0, 1] — encode completion quality.
          1.0 = completed on time, in correct order, fast
          0.7 = completed but slow
          0.3 = completed but badly deferred
          0.0 = not completed (carry-over)
        """
        x = completed_feature
        # Online Bayesian linear regression update
        self.A += np.outer(x, x) / self.noise_var
        self.b += x * reward / self.noise_var

    def get_posterior_mean(self) -> np.ndarray:
        return np.linalg.solve(self.A, self.b)
```

### Reward Signal Design

The `reward` scalar is the most important design decision. Encoding options:

```python
def compute_reward(task, actual_minutes: float, position_in_plan: int,
                   position_completed: int) -> float:
    """
    Compose a reward scalar from multiple signals.
    """
    # 1. Completion: did the task get done today?
    if not task.get('completed_today', False):
        return 0.0

    # 2. Efficiency: was it faster than estimated?
    est = task.get('estimated_minutes', actual_minutes)
    efficiency = min(est / actual_minutes, 2.0) / 2.0  # clamp to [0, 1]

    # 3. Order alignment: was it done near its recommended position?
    order_penalty = abs(position_in_plan - position_completed) / 10.0
    order_signal = max(0.0, 1.0 - order_penalty)

    # 4. No deferral bonus
    defer_bonus = 0.1 if task.get('times_deferred', 0) == 0 else 0.0

    reward = 0.5 * efficiency + 0.4 * order_signal + 0.1 * 1.0 + defer_bonus
    return float(np.clip(reward, 0.0, 1.0))
```

### Convergence Requirements & Timeline

With 15 tasks/day and ~0.7 completion rate, you generate ~10 reward observations/day and ~3–5 reordering events/day.

| Week | Events | State | Expected improvement |
|---|---|---|---|
| 1 | 0–70 obs | Cold start: prior dominates | Ordering = domain heuristics, baseline |
| 2 | 70–140 obs | Posterior begins to update | 10–15% reduction in task reordering by user |
| 3 | 140–210 obs | Weights personalised | Timing + sender preferences visible in weights |
| 4 | 210–280 obs | Stable posterior | Chronotype curve fitted; P90 duration intervals active |

**Convergence test:** Check weekly if `np.linalg.norm(Sigma_n) < 0.3` — when posterior uncertainty falls below this threshold, the model has converged and exploration can be reduced (temperature parameter decreased).

### Cold-Start Strategy

```python
def cold_start_rank(tasks: list, scoring_weights: dict) -> list:
    """
    Pure deterministic fallback for first 7 days.
    Uses hardcoded weights until LinTS posterior has >= 30 updates.
    """
    def score(task):
        return (
            scoring_weights['urgency']  * float(task.get('is_urgent', 0)) +
            scoring_weights['overdue']  * float(task.get('days_until_due', 99) < 0) +
            scoring_weights['deadline'] * max(0, 1 - task.get('days_until_due', 7) / 7) +
            scoring_weights['timing']   * 0.5  # neutral timing before chronotype
        )
    return sorted(tasks, key=score, reverse=True)

# Blend cold-start and LinTS
def hybrid_rank(tasks, features, sampler, n_updates: int,
                scoring_weights: dict, blend_threshold: int = 30) -> list:
    if n_updates < blend_threshold:
        alpha = n_updates / blend_threshold  # 0 → 1 linear blend
        cold_order = cold_start_rank(tasks, scoring_weights)
        ts_order = sampler.rank_tasks(features)
        # Blend by scoring position in each list
        blended_scores = {}
        for i, idx in enumerate(cold_order):
            blended_scores[idx] = (1 - alpha) * (len(tasks) - i)
        for i, idx in enumerate(ts_order):
            blended_scores[idx] = blended_scores.get(idx, 0) + alpha * (len(tasks) - i)
        return sorted(range(len(tasks)), key=lambda i: blended_scores[i], reverse=True)
    else:
        return sampler.rank_tasks(features)
```

***

## Integration Architecture

### Data Flow

```
Daily task list
    ↓
build_feature_vector() × N tasks
    ↓
hybrid_rank() → recommended order
    ↓
User works through list
    ↓
On each completion:
  ├── HierarchicalDurationModel.update()
  ├── CQRCalibrator.calibrate()
  ├── ChronotypeModel.log_completion()
  ├── ContextualThompsonSampler.update()
  └── RewardWeightLearner.update_from_reorder() [if out-of-order]
    ↓
Weekly:
  ├── ChronotypeModel.fit_harmonic()
  ├── Claude Opus: read behaviour_events → update qualitative rules
  └── Log posterior weights for audit trail
```

### Supabase pg_cron Integration

```sql
-- Daily snapshot of ML model state (for debugging + rollback)
SELECT cron.schedule('snapshot-ml-state', '0 23 * * *', $$
  INSERT INTO ml_model_snapshots (date, model_state)
  SELECT NOW(), row_to_json(t) FROM (
    SELECT
      (SELECT weights FROM linsts_state LIMIT 1) as linsts_weights,
      (SELECT params FROM chronotype_state LIMIT 1) as chronotype_params,
      (SELECT calibration_scores FROM cqr_state LIMIT 1) as cqr_scores
  ) t;
$$);
```

***

## Implementation Roadmap

### Week 1: Infrastructure
- Deploy `HierarchicalDurationModel` and replace EMA display with P50/P90 output
- Add `times_deferred`, `estimation_ratio` columns to `behaviour_events`
- Instrument `calendar_frag_score` from calendar integration
- Keep existing Thompson sampling + hardcoded weights as primary ordering

### Week 2: Ordering Upgrade
- Deploy `ContextualThompsonSampler` in shadow mode (log scores but don't act)
- Begin `hybrid_rank()` with alpha=0 (cold start phase)
- Start CQR calibration data collection

### Week 3: Activate Learning
- Increase alpha in `hybrid_rank()` to 0.5 — blend cold start with LinTS
- Activate `RewardWeightLearner.update_from_reorder()` on detected out-of-order completions
- Deploy `ChronotypeModel` binned version; feed timing_score into feature vector

### Week 4: Full Activation
- `hybrid_rank()` alpha → 1.0 if n_updates >= 30
- `ChronotypeModel.fit_harmonic()` first run
- CQR conformalize() active (20+ calibration points collected)
- Weekly Claude Opus job reads new signals (deferral_hours, estimation_ratio) for qualitative rule generation

The most critical implementation insight across all six questions: with N=1 and sparse data, **Bayesian methods are not optional** — they are the only approach that provides calibrated uncertainty, graceful cold-start behaviour, and monotonic improvement from day 1 rather than requiring a burn-in period of weeks before any personalisation occurs.[^11][^1][^10]

---

## References

1. [[PDF] A Tutorial on Thompson Sampling - Stanford University](https://web.stanford.edu/~bvr/pubs/TS_Tutorial.pdf) - ABSTRACT. Thompson sampling is an algorithm for online decision prob- lems where actions are taken s...

2. [[PDF] Analysis of Thompson Sampling for the Multi-armed Bandit Problem](http://proceedings.mlr.press/v23/agrawal12/agrawal12.pdf) - The Thompson Sampling algorithm initially assumes arm i to have prior Beta(1,1) on µi, which is natu...

3. [Contextual Bandits Analysis of LinUCB Disjoint Algorithm with Dataset](https://kfoofw.github.io/contextual-bandits-linear-ucb-disjoint/) - A contextual multi-armed bandit solution where the expected pay off r_{t,a} of an arm a is linear in...

4. [Action Centered Contextual Bandits - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC5719505/) - ... Thompson sampling is particularly suited to our regression approach. We follow the basic framewo...

5. [[PDF] Balanced Linear Contextual Bandits](https://www.tse-fr.eu/sites/default/files/TSE/documents/ChaireJJL/wp/balance_contextual_bandits.pdf) - To re- duce bias, we have proposed new contextual bandit algo- rithms, BLTS and BLUCB, which build o...

6. [[PDF] Preference Learning and Ranking](https://cs.uni-paderborn.de/fileadmin/informatik/fg/is/Publications/PL16.pdf) - Preference learning refers to the task of learning to predict (contextualized) preferences on a coll...

7. [Prediction Intervals for Gradient Boosting Regression - Scikit-learn](https://scikit-learn.org/stable/auto_examples/ensemble/plot_gradient_boosting_quantile.html) - This example shows how quantile regression can be used to create prediction intervals. See Features ...

8. [Time-on-task estimation for tasks lasting hours spread over multiple ...](https://pmc.ncbi.nlm.nih.gov/articles/PMC12445496/) - Time duration estimation, where a person estimates how much time elapsed during an interval or while...

9. [Improving Integrated Master Schedule (IMS) Task Duration Estimates](https://blog.humphreys-assoc.com/ims-task-duration-estimates/) - Improve IMS task duration estimates with proven strategies from earned value consultants to reduce s...

10. [A hierarchical Bayesian approach for calibration of stochastic ...](https://www.cambridge.org/core/journals/data-centric-engineering/article/hierarchical-bayesian-approach-for-calibration-of-stochastic-material-models/E420658DD082F486522BEEFCC697EC92) - This article recasts the traditional challenge of calibrating a material constitutive model into a h...

11. [Hierarchical Bayesian inference for concurrent model fitting and ...](https://journals.plos.org/ploscompbiol/article?id=10.1371%2Fjournal.pcbi.1007043) - Model comparison by HBI is robust against outliers and is not biased towards overly simplistic model...

12. [Conformalized quantile regression - ML without tears](https://mlwithouttears.com/2024/01/17/conformalized-quantile-regression/) - In this post we show how to achieve goals #1 and #2 via conformal quantile regression (CQR), first p...

13. [[PDF] Conformalized Quantile Regression - NeurIPS](https://papers.neurips.cc/paper/8613-conformalized-quantile-regression.pdf) - Conformal prediction is a technique for constructing prediction intervals that at- tain valid covera...

14. [Calibrated Conformal Prediction Intervals for Microphysical Process ...](https://arxiv.org/html/2603.27699v1) - Both conformal prediction methods yield well-calibrated and sharp prediction intervals on average, b...

15. [A Survey of Foundational Methods in Inverse Reinforcement Learning](https://www.lesswrong.com/posts/wf83tBACPM9aiykPn/a-survey-of-foundational-methods-in-inverse-reinforcement) - We get to assume that the true reward function is a weighted combination of these features, and we a...

16. [Learning from humans: what is inverse reinforcement learning?](https://thegradient.pub/learning-from-humans-what-is-inverse-reinforcement-learning/) - Inverse RL: learning the reward function. In a traditional RL setting, the goal is to learn a decisi...

17. [Application of Gaussian processes in circadian rhythm detection](https://aaltodoc.aalto.fi/items/1b53b6b3-cb38-4f4e-829c-ac94d7cf149e) - Here, we show that Gaussian processes can also identify rhythmic features (eg, period, phase, amplit...

18. [[PDF] Detecting periodicities with Gaussian processes - PeerJ](https://peerj.com/articles/cs-50.pdf) - Our approach provides a flexible framework for inferring both the periodic and aperiodic components ...

19. [Circadian Research in Mothers and Infants: How Many Days ... - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC2774919/) - In circadian work, a minimum of one complete cycle (24-hour period) is desired for cosinor analysis....

20. [Data-driven modelling approach to circadian temperature rhythm ...](https://www.nature.com/articles/s41598-021-94522-9) - We used data-driven, unsupervised time series modelling to characterize distinct profiles of the cir...

21. [Identifying Links Between Productivity and Biobehavioral Rhythms ...](https://pmc.ncbi.nlm.nih.gov/articles/PMC11066747/) - To analyze the data, we modeled cyclic human behavior patterns based on multimodal mobile sensing da...

22. [A neuro-computational account of procrastination behavior - Nature](https://www.nature.com/articles/s41467-022-33119-w) - The predicted delay for task completion (i.e., procrastination duration) is the one that maximizes t...

23. [A neuro-computational account of procrastination behavior - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9513091/) - The predicted delay for task completion (i.e., procrastination duration) is the one that maximizes t...

24. [Multitasking: Switching costs - American Psychological Association](https://www.apa.org/topics/research/multitasking) - By comparing how long it takes for people to get everything done, the psychologists can measure the ...

25. [Calendar Fragmentation: Why You're Busy All Day but Get Nothing ...](https://reclaim.ai/blog/calendar-fragmentation) - Four meetings may cost you 2 hours. The fragmentation between them costs 3 more. Learn why scattered...

26. [Calendar Analytics Tactics that Reclaim 8 Focus Hours per Week](https://www.worklytics.co/resources/slashing-meeting-overload-calendar-analytics-tactics-reclaim-8-focus-hours-per-week) - Meeting Load Index. The Meeting Load Index provides a standardized way to measure meeting density ac...

27. [How to Spot “Calendar Fatigue” Before It Kills Team Productivity](https://yaware.com/blog/how-to-spot-calendar-fatigue-before-it-kills-team-productivity/) - Back-to-back meetings don't mean progress. Learn how to detect calendar fatigue with time tracking a...

