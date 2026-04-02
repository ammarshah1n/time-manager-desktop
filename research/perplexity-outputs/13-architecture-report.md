# Timed — AI Learning Loops Architecture Report

## Executive Summary

This report answers seven concrete architectural questions for Timed's three learning loops: email classification, time estimation, and prioritisation learning. The core recommendation across all three loops is the same: **avoid fine-tuning entirely for now** (no infrastructure, insufficient data density at early scale), and instead use a layered retrieval-augmented approach with Claude prompt caching as the primary cost lever. The total monthly API burn for 10 active users is approximately **$62/month** with caching — a rounding error relative to executive-tier willingness to pay.

***

## Question 1: Email Classification — Few-Shot vs Retrieval vs Fine-Tuning

### The Crossover Breakdown by Scale

The three architectures occupy different regions of the correction-count spectrum:

| Correction count per user | Recommended approach | Why |
|---|---|---|
| 0–200 | Flat few-shot: last 100 corrections in prompt | Simple, effective, corrections fit comfortably in context |
| 200–2,000 | Retrieval-augmented few-shot (semantic + sender lookup) | Flat few-shot degrades as corrections become noisy and repetitive; retrieval selects the *most relevant* past corrections for each incoming email |
| 2,000–10,000 | Retrieval-augmented few-shot + sender rule table | Sender-domain rules handle the deterministic 80%, Claude handles the ambiguous 20% |
| 10,000+ | Fine-tuned small classifier (DistilBERT-class) | Token cost at this volume makes LLM classification uneconomic; fine-tuned CodeBERT-class models achieve F1 of 0.91+ vs retrieval-augmented at 0.74 F1 [^1] |

For Timed at 1–50 users, **the crossover to fine-tuning never happens** during initial scale. A single executive generates ~50 emails/day and might correct 2–5 per day, reaching 2,000 corrections after ~1 year. Flat few-shot is appropriate for the first 6 months; retrieval-augmented few-shot is the right architecture to build toward from day one.

### Why Flat Few-Shot Breaks Down

At 100 corrections (~1,500 tokens), flat few-shot works well. At 1,000 corrections (~15,000 tokens), three problems emerge simultaneously: (1) token cost scales linearly with correction count, (2) early corrections become stale and mislead the model, and (3) random sampling of examples underperforms compared to selecting semantically similar ones. Retrieval-augmented prompting — embedding the incoming email and fetching the top-10–20 most similar past corrections — consistently outperforms both random few-shot and zero-shot prompting while avoiding the context explosion.[^1]

### The Architecture to Build

The classifier should implement a **three-layer decision hierarchy**:

1. **Rule layer (zero cost):** Hard rules fire first — sender in `black_hole_senders` table → BlackHole; sender in `inbox_always_senders` table → Inbox; user in TO field vs CC/BCC → CC/FYI. SaneBox uses exactly this architecture: sender header + subject line analysis, drag-to-train feedback, no email body download.[^2][^3]

2. **Retrieval layer (~10ms):** Embed the incoming email (subject + sender domain + first 200 chars) with `text-embedding-3-small`. Query pgvector for the top-20 most similar past corrections. Feed as few-shot examples into the Claude call.

3. **Claude classification (~200ms):** Claude Haiku 4.5 (not Sonnet) is appropriate here — classification is a narrow, well-defined task where the smaller model matches Sonnet accuracy at 20% of the cost. Output: `{bucket, confidence, reasoning_hint}`.[^4]

Cache the user's rule table and sender-domain map as the first cache breakpoint in each call. Cache hits cost $0.10/MTok vs $1.00/MTok base for Haiku, a 90% discount on the static portion of every request.[^5]

***

## Question 2: Time Estimation — Similarity Metric and Embedding Model

### Cold Start vs Warm State

**Cold start (0–14 days):** The estimation hierarchy from FR-04 is correct as specified. Priority order: (1) subject line parsing for explicit time hints (`P1 | topic | 30 mins` format), (2) category defaults (Quick Reply = 2 min, Read = 3 min, Call = 10 min, Action = 30 min), (3) Claude Sonnet estimate based on email content length, attachment count, and detected task type. Never ask the user during cold start — defer to category defaults and let Claude calibrate from content signals.

**Warm state (14+ days, 200+ historical tasks):** Switch the primary estimator to historical similarity. The recommended similarity function is a **weighted hybrid**, not pure embedding cosine:

```
similarity_score = (0.6 × cosine_sim(embedding_a, embedding_b))
                 + (0.4 × structured_match_score)
```

Where `structured_match_score` awards partial points for: same `task_type_hint` (+0.3), same sender domain (+0.15), same source type (Email/WhatsApp/Voice) (+0.1), similar word count band (+0.05). This hybrid substantially outperforms pure embedding cosine for short task titles where semantic signal is thin.[^6]

### Embedding Model Recommendation

**`text-embedding-3-small`** is the correct choice. It costs $0.02/MTok — a 5× reduction from ada-002's $0.10/MTok — while outperforming ada-002 by 13% on multilingual retrieval benchmarks. Embedding 200 tasks/day at 100 tokens each = 20,000 tokens/day = **$0.40/month in embedding costs**. This is noise-level cost; optimising further here is premature.[^7][^8]

Use 512-dimensional embeddings (via Matryoshka dimension truncation, supported by `text-embedding-3-small`) rather than the full 1,536 dimensions. At Timed's scale, the storage and query speed difference is negligible, but the habit of dimension-trimming matters when you reach thousands of users.[^7]

### Calibration Loop Schema

The `estimation_history` table already captures `ai_estimate`, `user_override`, `actual_minutes`, and `task_type_hint`. Add one field: `embedding vector(512)` on task title + description. The calibration query becomes:

```sql
SELECT actual_minutes, user_override, ai_estimate,
       1 - (embedding <=> $1::vector) AS cosine_sim,
       task_type_hint
FROM estimation_history
WHERE user_id = $2
ORDER BY cosine_sim DESC, created_at DESC
LIMIT 10;
```

Weight recent tasks more heavily (recency decay): `final_weight = cosine_sim × (0.95 ^ days_ago)`. The final estimate is the weighted average of `COALESCE(user_override, actual_minutes)` across the top-10 matches.

***

## Question 3: Behaviour Pattern Learning Without Fine-Tuning

### The Standard Production Architecture

There are no published engineering teardowns from Motion, Reclaim, or Akiflow describing LLM-based implicit behaviour learning. Based on review of their public features: Reclaim uses **explicit user-configured scheduling windows and priority levels**, not implicit signal learning. Motion continuously re-schedules tasks based on deadlines and priorities, but does not learn user patterns over time — it executes a deterministic algorithm against user-specified constraints. Akiflow's "AI planning" is described as a beta feature using urgency, workload, and availability. None of these products appear to do what Timed's Loop 3 requires.[^9][^10][^11][^12]

The correct architecture for implicit pattern learning without fine-tuning or dedicated ML infrastructure is:

**Behaviour log → periodic LLM summarisation → compressed profile card → injected as system prompt context**

This is a production-proven pattern used in AI agent memory systems. The specifics for Timed:[^13][^14]

1. **Log every decision signal** in a `behaviour_events` table: task completed (with timestamp, position in plan, task type), task deferred (how many times, for how long), plan order override (user moved task X before task Y), estimate override (user changed X min to Y min), time-of-day completion patterns.

2. **Weekly summarisation job** (Edge Function, runs Sunday night): Fetch last 30 days of `behaviour_events` for the user. Send to Claude Sonnet with prompt: *"Analyse this user's task completion history and extract 5–8 behavioural rules about how they actually prioritise and complete work. Format as bullet points with evidence counts."* Output is stored as the `inferred_rules` field in `user_profiles`.

3. **Inject compressed profile into planning prompt** as the first cache breakpoint: the profile card stays static for a week, so it hits cache on every daily plan generation call, costing $0.50/MTok vs $5/MTok base for Opus.[^5]

### Detecting Specific Patterns

For Timed's use case, the key pattern types to detect and encode:

| Pattern type | Detection signal | Profile encoding |
|---|---|---|
| Time-of-day preference | `completed_at` timestamps clustered by task_type | `"Completes Action tasks before 11am 78% of the time"` |
| Category avoidance | High deferral count on `task_type_hint = 'legal'` | `"Defers legal-tagged tasks average 4.2 days"` |
| Communication order preference | Calls completed before emails when both present in same session | `"Prioritises Calls before email replies regardless of deadline order"` |
| Estimate accuracy by type | `actual_minutes / ai_estimate` ratio by category | `"Email replies completed 38% faster than AI estimates"` |
| Quick-win preference | Items with `estimated_minutes < 5` completed disproportionately early | `"Tends to clear quick wins first in new sessions"` |

The summarisation prompt should explicitly ask Claude to look for these pattern types with evidence counts. If evidence count for a rule is < 5 occurrences, omit it — avoid encoding noise as signal.

***

## Question 4: User Productivity Profile Data Model

### Schema Design

The profile should be split across three stores with different update cadences:

**1. `user_profiles` table (Postgres JSONB + typed columns)** — updated weekly by summarisation job:

```sql
CREATE TABLE user_profiles (
  user_id uuid PRIMARY KEY,
  -- Typed for queryability
  timezone text,
  deep_work_start time,
  deep_work_end time,
  avg_session_length_minutes int,
  -- JSONB for flexibility
  explicit_preferences jsonb,     -- user-set rules (always first, never, etc.)
  inferred_rules jsonb,           -- LLM-extracted behavioural patterns
  estimate_calibration jsonb,     -- {task_type: actual/ai ratio} by category
  updated_at timestamptz
);
```

**`explicit_preferences`** (user-set, auditable):
```json
{
  "always_first": ["daily_update_email", "family_emails"],
  "never_schedule_before": "09:00",
  "context_preferences": {"transit": ["reads", "calls"]},
  "deferral_rules": [{"tag": "legal", "defer_days": 3}]
}
```

**`inferred_rules`** (LLM-extracted, auditable):
```json
{
  "rules": [
    {"rule": "Completes calls before emails in same session", "evidence_count": 23, "confidence": 0.87},
    {"rule": "Deep work tasks completed 60% faster on Tue/Wed mornings", "evidence_count": 14, "confidence": 0.72},
    {"rule": "Defers legal-tagged tasks average 4 days", "evidence_count": 8, "confidence": 0.65}
  ],
  "last_updated": "2026-03-23T00:00:00Z",
  "sessions_analysed": 47
}
```

**2. `classification_corrections` table (relational)** — append-only, used for Loop 1 retrieval:

```sql
CREATE TABLE classification_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id),
  email_embedding vector(512),
  sender_domain text,
  subject_snippet text,
  from_bucket text,  -- 'inbox' | 'later' | 'black_hole'
  to_bucket text,
  corrected_at timestamptz DEFAULT now()
);
CREATE INDEX ON classification_corrections USING hnsw (email_embedding vector_cosine_ops);
```

**3. `estimation_history` table (relational)** — already defined in FR-04, add embedding column:

```sql
ALTER TABLE estimation_history ADD COLUMN task_embedding vector(512);
CREATE INDEX ON estimation_history USING hnsw (task_embedding vector_cosine_ops);
```

### Representing the Profile as LLM Context

The profile injected into planning prompts should be a compressed text block, not raw JSON. The serialisation function converts `inferred_rules` and `explicit_preferences` into a ~600–800 token natural language card:

```
USER PROFILE (last updated 2026-03-23)
Work pattern: Deep work 8am–12pm. Average available session: 2.1 hours.
Behavioural rules (evidence-backed):
• Prioritises calls before email replies regardless of deadline (23 observations)
• Defers legal-tagged work average 4 days (8 observations)  
• Completes email replies 38% faster than AI estimates (31 observations)
• High completion rate for <5-min quick wins at session start (19 observations)
Estimate calibration:
• email_reply: actual = 62% of AI estimate
• action_task: actual = 104% of AI estimate  
• call: actual = 87% of AI estimate
Explicit rules: Daily Update email always first. Family emails always second.
```

This block is the first cache breakpoint in every Opus planning call. It stays static for 7 days between summarisation runs, hitting cache every time.

### Auditability Layer

The Insights screen (Feature 9) should surface `inferred_rules` directly with evidence counts. Each rule should display as: *"I've noticed you complete calls before emails 87% of the time (23 sessions). This affects how I order your daily plan."* The user should be able to toggle any inferred rule off. Toggling creates an entry in `explicit_preferences.disabled_rules` which the planning prompt respects. This creates trust, not just transparency.

***

## Question 5: pgvector vs Pinecone

**Use pgvector. There is no case for Pinecone at Timed's scale.**

Supabase's pgvector with HNSW indexing delivers 1,185% more queries per second than Pinecone s1 pods at equivalent cost on a 1M-vector dataset. At Timed's initial scale, each user generates at most a few thousand task embeddings and a few thousand correction embeddings — well under the 100K vector range where pgvector performance is essentially flat.[^15][^16]

Pinecone's advantages (managed infra, horizontal scaling) only matter above ~5M vectors or when your team lacks PostgreSQL operational expertise. Given the Supabase stack is already chosen, adding Pinecone would introduce a second operational surface, a second billing relationship, and cross-database roundtrips — with zero performance benefit.[^16]

### HNSW Configuration for Timed

```sql
-- For classification corrections
CREATE INDEX corrections_embedding_idx
ON classification_corrections
USING hnsw (email_embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- For task estimation history
CREATE INDEX estimation_embedding_idx
ON estimation_history
USING hnsw (task_embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);
```

`m = 16` (default) is appropriate for datasets under 500K vectors. `ef_construction = 64` balances build time against query accuracy. At query time, `ef_search = 40` gives accuracy@10 ≈ 0.97 — more than sufficient for task similarity matching. Unlike IVFFlat, HNSW indexes can be created on an empty table and remain optimal as data is incrementally added, which matters during early growth.[^15]

**Performance cliff:** pgvector degrades when the HNSW index no longer fits in RAM. For a Supabase Pro plan (8GB RAM), this occurs around 500K–1M 512-dimensional vectors. At 1 task embedding per task and 20 tasks/day, a single user reaches 500K vectors after ~68 years. This is not a real constraint.

***

## Question 6: Monthly Cost Model — 10 Active Users

All prices use March 2026 API rates: Claude Sonnet 4.6 at $3/$15 per MTok input/output, Claude Opus 4.6 at $5/$25, cache hits at $0.30/$0.50 per MTok respectively, `text-embedding-3-small` at $0.02/MTok.[^8][^4][^5]

| Workload | Volume (10 users/day) | Daily cost | Monthly cost |
|---|---|---|---|
| Email classification (Sonnet + caching) | 500 emails/day | $1.35 | ~$40.50 |
| Time estimation embeddings | 200 tasks/day | $0.0004 | ~$0.12 |
| Time estimation (Sonnet) | 200 tasks/day | $0.39 | ~$11.70 |
| Plan generation (Opus + caching) | 10 plans/day | $0.31 | ~$9.42 |
| **Total with prompt caching** | | **$2.05** | **~$61.63** |
| Total without prompt caching (baseline) | | ~$4.12 | ~$123.46 |

**Per-user monthly API cost: ~$6.16.** Against an executive-tier willingness to pay of ~$4,000/month, the AI infrastructure cost represents 0.15% of revenue per user. Even at 1,000 users, the monthly burn would be approximately $6,160 — comfortably served by Supabase's standard compute tiers without dedicated ML infrastructure.

### Cost Optimisations Available

- **Use Claude Haiku 4.5 for email classification** (not Sonnet): $1/$5 per MTok vs $3/$15. Classification is a narrow task where Haiku matches Sonnet quality. This alone reduces email classification costs by ~66%, bringing the monthly total to ~$30.
- **Batch API for non-real-time flows**: The weekly profile summarisation job and any offline embedding generation qualify for the 50% Batch API discount.[^17]
- **Reduce plan output tokens**: The Opus planning output is the largest per-token cost driver. Structured JSON output instead of prose reduces output tokens ~40%.

***

## Question 7: What Competitors Have Actually Shipped

**Reclaim.ai** does not use implicit behaviour learning. Its personalisation model is entirely explicit: users configure scheduling windows, priority levels, habit templates, and flexibility rules. The system then executes a deterministic constraint-satisfaction algorithm against those parameters. Its "AI" is primarily in scheduling link availability calculation and calendar conflict resolution, not in learning user preferences from historical behaviour. No public engineering blog posts describe a behaviour learning ML system.[^10][^12]

**Motion** continuously re-optimises task scheduling based on deadline proximity, duration estimates, and calendar gaps. It also uses explicit user-set priorities and deadlines. There is no evidence of implicit preference learning from completion patterns. The system reruns its scheduling algorithm when inputs change, it does not update a user model.[^10]

**Akiflow** has shipped an "AI planning (Beta)" feature described as auto-prioritising based on urgency, workload, and availability. No engineering details are public. The product is primarily a keyboard-driven universal inbox aggregator, and its value proposition does not depend on behaviour learning.[^11]

**SaneBox** uses sender header and subject line analysis for classification, refined by drag-to-train corrections. It explicitly does not download email bodies (stated privacy policy). Its architecture is closest to Timed's Loop 1 — but it predates modern LLMs and is almost certainly a traditional ML classifier (logistic regression or SVM) trained on sender/subject features rather than an LLM-based system.[^3][^2]

**The honest conclusion:** No major competitor has published implementation details for LLM-based implicit behaviour learning. This is either because they haven't built it (most likely) or because it's a competitive secret. Timed's Loop 3 architecture as described — behaviour log → LLM summarisation → profile card → system prompt injection — is not derivative of any known production system. It is the architecture that several practitioners recommend for agent memory, applied to the productivity domain.[^14][^13]

***

## Architecture Decision Summary

| Loop | MVP (0–6 months) | Growth (6–18 months) | At scale (18+ months) |
|---|---|---|---|
| Email classification | Flat few-shot, last 50 corrections, Claude Haiku | Retrieval-augmented: pgvector top-20 + Haiku | Sender rule table + retrieval; fine-tune only at 10K+ corrections |
| Time estimation | Category defaults + Claude Sonnet on content | Hybrid similarity (0.6 cosine + 0.4 structured) + weighted historical average | Same, with user-specific calibration multipliers baked in |
| Prioritisation | Fixed ranking rules from PRD + explicit user prefs | Weekly LLM summarisation → profile card → Opus injection | Same, with more pattern types and session-level context |
| User profile | `user_profiles` table with JSONB blobs | Add `inferred_rules` from summarisation, auditability UI | Versioned profile history for rollback, A/B testing of rule impact |

The Supabase stack handles all of this. The cost is negligible relative to the price point. The technical risk is not in the AI layer — it is in building user trust that the system is learning *correctly*, which is why the auditability layer in the Insights screen is not a nice-to-have. It is what allows the learning loops to compound rather than erode trust.

---

## References

1. [Retrieval-Augmented Few-Shot Prompting Versus Fine-Tuning for ...](https://arxiv.org/abs/2512.04106) - Retrieval-augmented prompting outperforms both zero-shot (F1 score: 36.35%, partial match accuracy: ...

2. [How does SaneBox determine trainings?](https://www.sanebox.com/help/186-how-does-sanebox-determine-trainings) - SaneBox uses a combination of artificial intelligence (AI) and your own actions to determine how to ...

3. [How does SaneBox work?](https://www.sanebox.com/help/155-how-does-sanebox-work) - Automatically filter your email of spam and unimportant messages to only see the emails that are imp...

4. [Claude API Pricing 2026: Full Anthropic Cost Breakdown - MetaCTO](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration) - For Claude Sonnet 4.5, requests exceeding 200K input tokens are charged at $6 input / $22.50 output ...

5. [Prompt caching - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) - Claude API Documentation.

6. [[PDF] Hybrid TF-IDF and Embedding Model for Improving Similarity and ...](https://publishing-widyagama.ac.id/ejournal-v2/index.php/jointecs/article/download/7344/3818/20893) - This study addresses improving accuracy in final project document recommendation systems for student...

7. [text-embedding-3-small: High-Quality Embeddings at Scale](https://blog.promptlayer.com/text-embedding-3-small-high-quality-embeddings-at-scale/) - While ada-002 cost $0.10 per million tokens, text-embedding-3-small slashed this to just $0.02 per m...

8. [OpenAI API Pricing Per 1M Tokens - Silicon Data](https://www.silicondata.com/use-cases/openai-api-pricing-per-1m-tokens/) - Embeddings are priced far below general-purpose generation: `text-embedding-3-small` at $0.02 per mi...

9. [Overview: What Reclaim Tasks are, and how to create and use them](https://help.reclaim.ai/en/articles/5108936-overview-what-reclaim-tasks-are-and-how-to-create-and-use-them) - When you create a new Task, you will see a form where you can fill out your scheduling preferences f...

10. [Motion vs. Reclaim.ai: Which AI Scheduling Assistant is Best?](https://reclaim.ai/blog/motion-vs-reclaim) - Reclaim.ai uses goal-aware AI to protect users' priorities by flexibly scheduling focus time, tasks,...

11. [How to Prioritize Your Work: 5 Steps, 8 Methods, and the Best Tools](https://akiflow.com/blog/work-prioritization-techniques-tools-guide/) - Boost efficiency with proven prioritization techniques. Learn the 4 Ps, use the Eisenhower Matrix, a...

12. [How Reclaim manages your schedule automatically](https://help.reclaim.ai/en/articles/6207587-how-reclaim-manages-your-schedule-automatically) - Learn how Reclaim uses patent-pending intelligence to automatically schedule and reschedule events b...

13. [System Prompts vs User Prompts: Design Patterns for LLM Apps](https://tetrate.io/learn/ai/system-prompts-vs-user-prompts) - System prompts define the model's behavior, role, and constraints at the application level, while us...

14. [Context Engineering: Prompt Management, Defense, and Control](https://www.dailydoseofds.com/llmops-crash-course-part-6/) - LLMOps Part 6: Exploring prompt versioning, defensive prompting, and techniques such as verbalized s...

15. [pgvector v0.5.0: Faster semantic search with HNSW indexes](https://supabase.com/blog/increase-performance-pgvector-hnsw) - New Supabase databases will ship with pgvector v0.5.0 which adds a new type of index: Hierarchical N...

16. [pgvector vs Pinecone: cost and performance - Supabase](https://supabase.com/blog/pgvector-vs-pinecone) - pgvector demonstrated much better performance again with over 4x better QPS than the Pinecone setup,...

17. [Claude Code Pricing in 2026: Every Plan Explained (Pro, Max, API ...](https://www.ssdnodes.com/blog/claude-code-pricing-in-2026-every-plan-explained-pro-max-api-teams/)

