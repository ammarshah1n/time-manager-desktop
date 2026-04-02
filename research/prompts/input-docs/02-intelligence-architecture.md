# Research Pack 02 — Intelligence Architecture Deep Dive

> Give all 5 prompts to Perplexity Deep Research, one at a time. Save each result. Bring them all back.

---

## Prompt 2 — The Memory Architecture: MemGPT vs Generative Agents vs Everything Else

Research Pack 01 identified two key architectures: Stanford Generative Agents (Park et al., 2023) and MemGPT (UC Berkeley, 2023). It also surfaced the ACAN dynamic cross-attention retrieval model from 2025. I need to go 10x deeper on all of these and every other relevant system.

I'm building a system that maintains a compounding model of a single C-suite executive over months. The memory system is the foundation — get this wrong and nothing compounds.

For each architecture below, I need: how it stores memories, how it retrieves them, how it reflects/consolidates, how quality compounds over time, strengths and weaknesses for modelling ONE PERSON over months, and what I should steal from it.

Go deep on:
1. **Stanford Generative Agents (Park et al., 2023)** — The original reflection loop. Memory stream, retrieval (recency × importance × relevance with 0.995 hourly decay), reflection triggers (cumulative importance threshold), planning from reflection. What exactly makes the reflection compound? How many reflection cycles before qualitative improvement? What are the measured limitations?

2. **MemGPT / Letta (UC Berkeley, 2023-2025)** — OS-inspired memory management. Core memory (always in context), recall memory (searchable), archival memory (vector store). Self-editing memory, interrupt-driven writeback. How does it decide what stays in core vs gets archived? What's the context pollution problem and how does it solve it? Latest Letta developments?

3. **ACAN Dynamic Cross-Attention (2025)** — Adaptive retrieval weights that change based on agent state. How exactly does the cross-attention mechanism work? How does it outperform static retrieval? Implementation details?

4. **Cognitive architectures (SOAR, ACT-R)** — Decades of research on modelling human cognition. What can we steal? SOAR's chunking mechanism, ACT-R's activation-based retrieval (base-level activation + spreading activation + noise). How do these map to LLM-based personal modelling?

5. **Reflexion (Shinn et al., 2023)** — Self-reflection in LLM agents. Verbal reinforcement learning. How does this apply to LONG-TERM personal modelling vs single-task reflection?

6. **CLIN (Continual Learning from Interactions)** — Systems that learn from ongoing interaction. Any work on continuous personal model updating?

7. **Hierarchical memory consolidation** — Inspired by human sleep consolidation (hippocampal replay). Any AI systems that implement staged consolidation? How does the brain decide what to keep vs forget? Can this inform our episodic → semantic promotion strategy?

8. **Personal LLMs and fine-tuning** — Is there research on fine-tuning small models to approximate a larger model's understanding of a specific person? When does prompting with personal context outperform fine-tuning? What's the crossover point?

9. **OpenAI's Context Engineering (2026)** — Stability, drift, and contextual variance in personal data. How to detect each? How to handle model updates when drift is detected vs when variance is contextual?

The synthesis question: **If you were designing a memory system for ONE PERSON that needs to get genuinely smarter over 6 months of continuous observation, what would you combine from all of the above? What's the optimal hybrid?**

---

## Prompt 3 — The Retrieval Problem: How to Find the Right Memory at the Right Time

Research Pack 01 established that retrieval precision beats retrieval volume — surfacing 3-5 high-signal memories is better than loading 50 facts. But retrieval is the hardest unsolved problem in personal AI. Go deep.

The system will accumulate thousands of episodic memories per month. When the reflection engine runs nightly, it needs to find the RIGHT memories to synthesise. When the morning session prepares a briefing, it needs to surface the RIGHT patterns. When the executive asks a question, it needs to retrieve the RIGHT context.

Research every retrieval approach:

1. **Three-axis scoring (Park et al.)** — recency × importance × relevance. What are the failure modes? When does recency domination miss important old patterns? When does importance scoring by an LLM at write-time produce bad scores? How sensitive is the system to the α/β/γ weight ratios?

2. **ACAN dynamic weights** — How exactly does it adapt weights? What signals does it use to decide current agent state? Can you implement this without training a custom model?

3. **Embedding-based retrieval** — Cosine similarity for the relevance axis. What embedding model produces the best results for personal behavioural data? How to handle the embedding of structured data (task completion records, calendar events) vs natural language memories? Hybrid dense + sparse retrieval?

4. **Temporal retrieval patterns** — How to retrieve "all memories related to board meeting preparation" across months? How to detect recurring temporal patterns (every-Monday, post-board-week, end-of-quarter)?

5. **Associative retrieval** — Human memory is associative, not keyword-based. How to build associative links between memories? If I retrieve a memory about "avoiding the strategic document," it should also surface the memory about "post-board fatigue." How?

6. **Context-window management** — When the reflection engine loads memories for analysis, how many is too many? What's the optimal context-to-instruction ratio for an Opus-level model doing reflection? How to compress memories for context without losing signal?

7. **Forgetting and decay** — What should the system forget? Not delete — but deprioritise. Research on beneficial forgetting in AI systems. How does human memory's spacing effect apply?

8. **Retrieval evaluation** — How do you know your retrieval is working well? What metrics? How to evaluate retrieval quality for a personal AI system where there's no ground truth dataset?

Give me the state of the art, the trade-offs, and your recommendation for the optimal retrieval system for a single-person, months-long, compounding intelligence model.

---

## Prompt 4 — Multi-Model Orchestration: Haiku / Sonnet / Opus Processing Tiers

I'm designing a system where multiple AI models at different capability tiers work together to build intelligence about one person continuously. This is NOT a task agent — it's a continuous observation and reflection system.

Current design (validate, challenge, or replace):
- **Tier 1 (real-time, Haiku-class):** Event classification, importance scoring, anomaly detection. Runs on every new signal.
- **Tier 2 (periodic, Sonnet-class):** Daily pattern extraction, email analysis, meeting effectiveness. Runs end-of-day.
- **Tier 3 (deep, Opus at max effort):** Full recursive reflection, personality model updates, strategic insights, rule generation. Runs nightly.

Research:
1. **Model cascading and escalation** — When should Haiku escalate to Sonnet or Opus? Confidence-based routing? What signals indicate the smaller model's understanding is insufficient?

2. **Multi-model coordination** — How do different models share a unified model of the user? If Haiku classifies an event and Opus later reflects on it, how do they maintain consistency? Shared memory store as the coordination layer?

3. **Cost-quality analysis for single-user 24/7 operation** — Realistic token budget for one executive, one month. How many Haiku calls per day for real-time classification? How many Sonnet calls for daily analysis? How many Opus tokens for nightly reflection? What does this cost?

4. **Batch vs stream processing** — Should daily analysis be a single Sonnet call at end-of-day, or multiple smaller calls throughout? What's the trade-off in intelligence quality?

5. **Fine-tuning a personal model** — Could you fine-tune a small model (Haiku-class) on the executive's data to reduce the need for Opus-tier processing? How much personal data before fine-tuning outperforms prompting? Privacy implications?

6. **The reflection engine prompt** — What does the actual prompt for the nightly Opus reflection look like? How to structure the system prompt + core memory + episodic memories + previous semantic facts into a prompt that produces genuine insight, not summaries? Show me examples.

7. **Human-in-the-loop corrections** — When the executive corrects the system ("that's not why I delayed that"), how to incorporate this efficiently? Active learning? How many corrections before self-correction?

8. **Existing multi-model systems** — AutoGen, CrewAI, LangGraph, MetaGPT — any designed for continuous observation rather than task completion? What coordination patterns work?

---

## Prompt 5 — Chronobiology, Energy Management, and Cognitive Scheduling

Research Pack 01 mentioned chronotype inference and the Wharton synchrony effect. I need to go 10x deeper because this is one of the most tangible intelligence features Timed can deliver.

The system observes when the executive completes tasks, how long they take, email response times, meeting engagement — and from this data, it needs to build a personalised cognitive performance model that optimises scheduling.

Research with full citations:

1. **Circadian performance curves by task type** — How does cognitive performance vary for different work types? Analytical thinking peaks when? Creative thinking? Interpersonal tasks? Administrative? What does the research show about the magnitude of the difference (is it 10% or 50%)?

2. **Inferring chronotype from behavioural signals** — Can you infer someone's chronotype from their digital behaviour WITHOUT asking them? Email timestamps, first-activity time, response latency patterns, task completion speed × time-of-day. What accuracy is achievable? How many days of data needed?

3. **Ultradian rhythms (90-120 min BRAC cycle)** — How well-supported in current research? Can it be detected from work patterns? Should scheduling align with ultradian cycles?

4. **Post-lunch cognitive dip** — How universal? How severe? What work types survive the dip? Can you detect an individual's dip timing from their behaviour?

5. **Meeting impact on cognitive performance** — Recovery time after meetings. Which meeting types are most draining? Back-to-back meeting degradation curves. Research on "no meeting" blocks.

6. **Individual variation** — How much does attention capacity and chronotype vary between individuals? The research gives population averages — how quickly can you learn a SPECIFIC person's curve? Days? Weeks?

7. **The scheduling algorithm** — Given a personalised chronotype model + calendar + task list, what does the optimal scheduling algorithm look like? How does it balance chronotype alignment with practical constraints (meetings are when they are)?

8. **Yesterday's sleep and today's performance** — How much predictive power does last night's sleep, yesterday's exercise, and yesterday's stress have over today's cognitive capacity? Can you infer sleep quality from morning behaviour patterns?

Give me everything. This feature — "Your best analytical window today is 9:30-11:00, schedule the strategy doc there" — is one of the most tangible ways Timed proves it understands the executive.

---

## Prompt 6 — Behavioural Prediction and Avoidance Pattern Detection

The system observes an executive for months and needs to predict their behaviour — specifically, when they're about to procrastinate, when they're avoiding something important, and when their decision quality is degraded.

This is the feature that makes executives say "this thing knows me better than I know myself."

Research:
1. **Procrastination detection from behavioural signals** — Can you detect procrastination BEFORE the person is consciously aware of it? What digital signals predict avoidance? Task deferral patterns, draft-and-delete, re-scheduling without engagement, time-between-appearance-and-first-interaction. Research on computational procrastination detection. The hybrid brain model from PMC9508313 — what accuracy did it achieve?

2. **Avoidance vs deprioritisation** — How to distinguish "I'm avoiding this because it's emotionally uncomfortable" from "I'm correctly deprioritising this"? What signal separates the two? Can you build a classifier?

3. **Decision quality prediction** — Can you predict when an executive is about to make a BAD decision? Time-of-day effects (Thursday afternoon after meetings), cognitive load indicators, emotional state proxies. Kahneman's decision hygiene — what specific conditions degrade decision quality?

4. **Burnout trajectory prediction** — Can you detect burnout trajectory from behavioural signals before it becomes clinical? Maslach Burnout Inventory dimensions mapped to digital behaviour. How far in advance? What's the intervention window?

5. **Habit detection and routine modelling** — Identifying stable routines from behavioural data. Detecting routine disruptions as anomalies. Predicting behaviour from routine models. How to update routines when they genuinely change vs temporarily disrupted?

6. **Self-report calibration** — How much to trust what the executive SAYS vs what they DO? Research on self-report accuracy. Executives overestimate strategic time by how much? How to build a calibration model between stated and revealed preferences?

7. **Longitudinal individual modelling** — How to build a model that captures what's unique about THIS person vs population averages? Transfer learning from population priors to individual posterior? Bayesian personalisation approaches?

8. **The "exactly right" moment** — Research Pack 01 identified the conversion moment: when the system names a pattern about the executive's behaviour that is exactly right. What does the research say about insight acceptance? When do people accept uncomfortable truths about their patterns? How to deliver insight without triggering defensiveness?

Give me everything on predicting human behaviour from continuous digital observation of a single person.
