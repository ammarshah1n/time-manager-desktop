# Timed: The Revolutionary Intelligence Architecture — Building the Most Intelligent Executive OS Ever Made

## The Right Mental Model

Stop thinking about Timed as a productivity app. Start thinking about it as a **cognitive prosthetic** — a second brain that accumulates everything about how an executive thinks, operates, and decides, then uses that knowledge to act as an active intelligence layer over their entire working life. The goal is not to help them schedule tasks better. The goal is to **reduce the cognitive load of being a leader** so fundamentally that the product becomes as indispensable as a phone.

Research is unambiguous on the problem: executives make approximately 35,000 decisions per day. Decision fatigue is biologically inevitable — each decision draws from a finite cognitive pool. The right AI intervention is not a to-do list. It is a system that absorbs the low and mid-tier cognitive burden entirely, and surfaces only the decisions that genuinely require a human mind. That is the product. That is the revolution.[^1]

The architecture to deliver that must be built on the most capable AI available — not the most cost-efficient — and must be designed around one principle: **maximum intelligence, compounding over time**.

***

## Why Opus 4.6 at Max Effort Is the Only Right Answer

Claude Opus 4.6 is the most capable reasoning model available for production agentic workflows as of 2026. Its key capabilities for Timed specifically:[^2][^3]

- **Adaptive thinking with four effort tiers** — at `effort: "max"`, Claude uses exhaustive extended reasoning with no constraints on depth or token budget. For a nightly analysis pass over a full day of executive behaviour, this is exactly the mode to use. The model revisits its reasoning, catches its own errors, and produces fundamentally higher-quality insights than standard inference[^4][^5][^6]
- **Interleaved thinking preserved across turns** — starting from Opus 4.5, thinking blocks from previous turns are preserved in context by default. In a multi-turn nightly analysis session, this means the model's reasoning from earlier analysis steps informs later ones without re-generating them[^3]
- **1M token context window** (beta) — the entire rolling 90-day history of an executive's behaviour could, in principle, fit in a single context. Even at the standard 200K window, the complete semantic user model, all episodic records from the past 30 days, and the full day's raw data fit comfortably[^4]
- **Context compaction** — for long-running multi-step analysis sessions, Opus 4.6 can auto-summarize older conversation context to sustain multi-hour sessions without hitting limits[^7][^8]
- **Superior long-context retrieval** — Opus 4.6 achieves 76% on MRCR (multi-round context retrieval) vs o3's ~45%. For a product whose entire value depends on the model accurately retrieving and applying information from weeks of stored behaviour, this benchmark is critical[^9]

The nightly analysis session should **always run at `effort: "max"`**. This is not negotiable. The entire product thesis is that Timed is smarter than anything else — and smart costs compute. The morning voice session runs at `effort: "high"` (the default — highly capable but aware of latency). Background micro-tasks run at `effort: "low"` because they are classification and logging, not reasoning.

***

## The Scientific Foundation: Generative Agent Architecture

The intellectual blueprint for Timed's intelligence layer is the **Generative Agents** paper from Stanford and Google (Park et al., 2023) — the most important work on long-running AI agent intelligence published in recent years. The architecture it describes is exactly what Timed needs to be:[^10]

> *"An architecture that extends a large language model to store a complete record of the agent's experiences using natural language, synthesize those memories over time into higher-level reflections, and retrieve them dynamically to plan behavior."*[^10]

The paper's key finding, proved through ablation study: **every component of the architecture contributes critically**. A system with memory + reflection + planning dramatically outperforms memory + planning alone, which outperforms memory alone, which outperforms a bare LLM. Removing the reflection loop — the nightly synthesis — degraded performance measurably. This is the scientific proof that the instinct to run deep nightly analysis is correct.[^11]

### The Three-Stage Memory Cycle

The Generative Agents architecture operates on three stages that map directly onto Timed:

**1. Observation** — raw event capture. Every task completion, deferral, calendar change, email interaction, manual reorder, and focus session is an observation that gets logged to the episodic memory stream. This is what the Haiku background agents handle.[^12]

**2. Reflection** — higher-order synthesis. Periodically (in the original paper, when the sum of importance scores of recent events exceeds a threshold), the agent reviews its recent observations and generates *reflections* — higher-level, more abstract thoughts. Reflections are stored back in the memory stream as first-class memories, and can inform further reflections recursively. The key insight: *"The system thinks about its own thinking."* This is the nightly Opus `effort: max` engine.[^13][^11]

**3. Planning** — action generation informed by synthesised memory. The morning session pulls from both raw observations and accumulated reflections to generate a genuinely intelligent plan — one informed not just by today's data but by weeks of synthesised understanding.[^12]

Stanford researchers subsequently showed this architecture can simulate 1,052 real individuals' personalities with 85% accuracy against the individuals' own self-consistency. The architecture can hold a believable model of a specific human. Applied to Timed, this is the scientific basis for the claim that the product will feel like it genuinely *knows* the user — because structurally, it does.[^14][^15]

***

## The Full Intelligence Architecture

### Layer 1: The Episodic Memory Stream (Continuous Collection)

Every meaningful event in the user's workday is captured as a structured observation and appended to the episodic memory stream. This is the foundation — without comprehensive observation, reflection is worthless.

**What gets observed:**

```swift
enum Observation: Codable {
    // Task completion events
    case taskCompleted(TaskCompletionObservation)
    //  → task title, category, source, estimated vs actual duration,
    //    time of day, plan position vs actual completion order,
    //    focus sessions used, interruptions, energy level at completion
    
    case taskDeferred(TaskDeferralObservation)
    //  → task title, how many times deferred, original due date,
    //    reason if voice-stated, time of deferral, what replaced it
    
    case taskAbandoned(TaskAbandonObservation)
    //  → task dropped entirely, what replaced it, context
    
    // Calendar events
    case meetingAttended(MeetingObservation)
    //  → duration, type (1:1, team, external), prep done yes/no,
    //    post-meeting state (rescheduled tasks, new action items)
    
    case focusBlockViolated(FocusViolationObservation)
    //  → protected block interrupted, by what type, resolution
    
    // Email behaviour
    case emailTriaged(EmailObservation)
    //  → AI classification vs user correction, response time,
    //    sender category, time of day, action taken
    
    // Plan behaviour
    case planDeviation(PlanDeviationObservation)
    //  → morning plan vs actual execution order, reason if voiced,
    //    impact on completion rate
    
    case manualReorder(ReorderObservation)
    //  → what task was moved where, relative to what other tasks,
    //    timestamp — implicit preference signal
}
```

Each observation gets an **importance score** using Opus at `effort: low` (fast, cheap) — a 1–10 rating of how behaviourally significant this event is. High-importance observations trigger earlier reflection generation rather than waiting for the nightly cycle. This mirrors the original Generative Agents architecture where reflections are triggered by accumulated importance scores.[^13]

### Layer 2: The Reflection Engine (Nightly + Triggered)

The Reflection Engine is the heart of what makes Timed revolutionary. It runs nightly at a user-configured time (default: 11pm) using Opus 4.6 at `effort: "max"`. It also runs on-demand when the sum of importance scores from recent observations exceeds a threshold — meaning significant day patterns trigger analysis immediately rather than waiting overnight.

**The Nightly Reflection Prompt Structure:**

```
SYSTEM [Cached across sessions]:
You are the intelligence engine for [user]'s personal AI operating system, Timed.
Your role is to think like the world's sharpest executive coach and behavioural analyst.
You have complete access to [user]'s working history. You are looking for patterns,
contradictions, growth, failure modes, and opportunities that [user] cannot see
themselves because they are too close to their own behaviour.

Be direct. Be specific. Cite evidence. Name the pattern before explaining it.
Do not be encouraging for its own sake. The user pays for truth, not comfort.

ACCUMULATED KNOWLEDGE [Cached - updated weekly]:
[Full semantic memory: user model, extracted preferences, known biases,
 verified patterns, active procedural rules — ~15K tokens]

[USER CONTEXT — fresh each nightly call]:
OBSERVATIONS TODAY:
[All episodic observations from the day — structured JSON]

RECENT REFLECTION HISTORY (last 14 days):
[Previous reflections — what patterns have been named, confirmed, updated]

CURRENT SCORING MODEL:
[Active PlanningEngine weights and procedural rules]
```

The engine is instructed to perform a **three-stage reflection cycle**, matching the recursive reflection structure from the research:[^11]

**Stage 1 — First-Order Reflections** (raw pattern observation):
- What happened today that was notable or unexpected?
- What diverged from the morning plan, and what does that suggest?
- What tasks were completed vs deferred, and is there a pattern in the type?

**Stage 2 — Second-Order Reflections** (pattern synthesis across days):
- What patterns are now confirmed across multiple observations?
- What first-order reflections from previous days are now synthesising into a higher-level understanding?
- What is the model's current hypothesis about this user's most important behavioural tendencies?

**Stage 3 — Procedural Updates** (action generation from synthesis):
- What scoring rules should be updated based on confirmed patterns?
- What should tomorrow's morning brief specifically address?
- What does the model now know about this user that it didn't know before?

The output is structured JSON that writes directly back to three memory layers:

```json
{
  "episodic_additions": [
    { "event": "...", "importance": 8, "timestamp": "..." }
  ],
  "semantic_updates": [
    {
      "fact": "User's creative output degrades sharply after 3 consecutive meetings",
      "confidence": 0.87,
      "evidence_count": 12,
      "replaces": null
    }
  ],
  "procedural_rule_updates": [
    {
      "rule_id": "post_triple_meeting_deep_work_ban",
      "action": "upsert",
      "rule": "After 3 or more consecutive meetings, remove all creative/strategic tasks from the next 90-minute window and replace with admin/email triage",
      "trigger": "3+ consecutive meeting blocks detected in calendar",
      "confidence": 0.87
    }
  ],
  "second_order_reflections": [
    {
      "reflection": "This user systematically underestimates interpersonal tasks — anything requiring political navigation takes 2-3x their estimate. This is not a time estimation problem; it is a cognitive avoidance pattern.",
      "evidence": ["task_id_23", "task_id_45", "task_id_67"],
      "importance": 9
    }
  ],
  "tomorrow_briefing_directives": {
    "open_with": "You deferred the board update for the third time. This is worth 3 minutes of honest conversation before we plan your day.",
    "critical_flags": ["Board update avoidance pattern", "Energy crash risk at 3pm based on today's meeting load"],
    "recommended_focus_blocks": ["7:00-8:30am (before first call)", "5:00-6:30pm (your second wind)"]
  }
}
```

This output is the product's intelligence manifesting in real, actionable form. It is not a generic daily summary. It is a specific, evidence-backed, named analysis of *this person's* behaviour on *this specific day* in the context of *their established patterns*. That is what makes it revolutionary.

### Layer 3: The Morning Director Session (Opus High Effort)

The morning voice interview is not a planning tool. It is an **intelligence delivery mechanism**. The Opus session that powers it has the full accumulated memory and the previous night's reflection output loaded into its context. It knows more about the user's day than they do when they wake up.

**What the Morning Director should do that nothing else does:**

- **Name patterns before the user does.** Not "you have a busy day today." Instead: *"Last 4 Tuesdays you've ended the day behind. The pattern is morning optimism — you accept too many 'quick calls' before 11am and your deep work never happens. Today I've blocked 7–9am and marked it uninterruptible. Tell me if you want to override it."*

- **Interrogate avoidance.** If the nightly engine flagged a deferred task for the third time, the morning session opens with it. Not gently. The product is an executive coach, not a yes-machine.

- **Reveal the model's reasoning explicitly.** Research on AI-assisted work shows that users adhere to AI recommendations far more consistently when they can see the reasoning. Every scheduling decision in the morning brief should come with a one-line explanation: *"CFO call prep is first because you've never successfully done prep work after 10am on days with 5+ meetings, and you have 6 today."*[^16]

- **Ask one calibrating question.** Not a survey. One question about the single most ambiguous or highest-stakes item in the day. This is active preference elicitation — using the conversation to fill in the gaps in the semantic model that observation alone can't capture.[^17]

The morning session ends with the morning plan delivered through the voice — and that plan is not a static task list. It is a **cognitive briefing**: what matters most, why, in what order, with what known risks.

### Layer 4: The Semantic Memory — The User's Living Model

The semantic memory is the accumulated intelligence about the user — the distilled, synthesised, structured representation of everything the system has learned. It is the most valuable object in the entire system. As it grows, the product becomes more intelligent. As it deepens, the switching cost becomes insurmountable.[^18][^19]

**The semantic memory model:**

```swift
struct SemanticUserModel: Codable {
    // Identity and style
    var cognitiveStyle: CognitiveStyle           // deep-work dominant vs. meeting-heavy vs. hybrid
    var communicationStyle: CommunicationStyle   // direct, diplomatic, brief, detailed
    var decisionStyle: DecisionStyle             // intuitive, analytical, collaborative, delegating
    
    // Temporal patterns (calibrated from episodic data)
    var peakEnergyWindow: TimeRange              // when they do their best work
    var focusCapacity: FocusCapacity             // max uninterrupted work duration before quality degrades
    var meetingRecoveryTime: Int                 // minutes needed after heavy meeting blocks
    var secondWindPattern: TimeRange?            // late-day recovery window if it exists
    
    // Cognitive biases (named and confidence-scored)
    var knownBiases: [CognitiveBias]
    // Examples:
    // - OvercommitmentBias(magnitude: 0.4, taskTypes: [.strategic])
    //   → estimates strategic tasks take 40% less time than they do
    // - AvoidanceBias(taskCategory: .interpersonal, deferralRate: 0.73)
    //   → defers interpersonal/political tasks 73% of the time on first scheduling
    // - OptimismBias(dayOfWeek: .monday, overcommitmentRate: 0.55)
    //   → Monday plans are unrealistic 55% of the time
    
    // Task patterns
    var estimatePriors: [TaskCategory: EstimatePrior]    // EMA per category
    var completionPatterns: [CompletionPattern]           // what conditions lead to completion
    var avoidancePatterns: [AvoidancePattern]             // what they systematically avoid and when
    
    // Environmental factors
    var meetingLoadThreshold: Int                // meeting count above which deep work is unlikely
    var highPerformanceConditions: [String]      // what states lead to best output
    var lowPerformanceSignals: [String]          // early warning signs of bad execution days
    
    // Second-order reflections (the highest-level insights)
    var coreInsights: [ReflectionInsight]        // e.g., "This person confuses busy with productive"
    var activeHypotheses: [BehaviourHypothesis]  // patterns still accumulating evidence
    var confirmedPatterns: [ConfirmedPattern]    // patterns with enough evidence to act on
}
```

This model starts sparse and becomes dense. At day 1, it is populated by the onboarding archetype selection and calendar history bootstrap. By month 3, it contains confirmed patterns, calibrated biases, and second-order reflections built from 90 days of daily observation and nightly analysis. **No competitor can replicate this object for a specific user without starting from scratch.** That is the moat.

### Layer 5: Procedural Memory — Intelligence That Acts

Procedural memory is where the intelligence becomes visible in the product. It is the set of active rules — generated by the Reflection Engine, stored in the `UserIntelligenceStore`, and injected directly into `PlanningEngine.rank()` — that change how the system behaves based on what it has learned.[^18]

Procedural rules are not hardcoded. They are **dynamically generated by Opus** during nightly analysis and have confidence scores, creation dates, and evidence counts:

```json
[
  {
    "id": "no_creative_work_post_triple_meeting",
    "rule": "Remove creative/strategic tasks from slots immediately following 3+ consecutive meetings",
    "confidence": 0.91,
    "evidence_count": 17,
    "created": "2026-02-14",
    "last_confirmed": "2026-03-28"
  },
  {
    "id": "monday_plan_reduction",
    "rule": "On Mondays, reduce planned task count by 30% from user's request — user systematically overplans Mondays",
    "confidence": 0.78,
    "evidence_count": 9,
    "created": "2026-03-01"
  },
  {
    "id": "board_materials_morning_only",
    "rule": "Schedule all board-related tasks exclusively in pre-10am windows — zero successful completions after 10am in 26 observations",
    "confidence": 0.96,
    "evidence_count": 26,
    "created": "2026-02-20"
  }
]
```

These rules are what make Timed feel prescient rather than reactive. When the user sees a plan that already accounts for their known failure modes — before they've even thought about them — the product stops being a tool and starts being an intelligence layer that understands them better than they understand themselves.

***

## The Self-Improvement Loop

The architecture described above is not static. It is **self-improving** — each cycle produces better intelligence for the next cycle. The loop works as follows:[^20]

```
Day's behaviour
    → Observation (episodic stream appended)
    → Nightly Opus reflection (max effort)
        → First-order reflections appended to episodic stream
        → Second-order reflections synthesised from first-order
        → Semantic model updated with new confirmed patterns
        → Procedural rules generated or updated
    → Morning session informed by updated semantic model
    → Better plan → better behaviour → richer observations
    → Next night's analysis is more informed
    → Loop repeats, compounding
```

Research on AI self-improvement confirms this pattern: reflection loops that persist their outputs and reuse them in future reasoning produce compounding gains over time. The key requirement is that **reflections are stored back as first-class memory** — not discarded after each session. In the original Generative Agents research, reflections that informed further reflections produced the highest-quality agent behaviour. The recursive structure matters.[^20][^11]

Context compaction in Opus 4.6 enables this loop to run indefinitely without hitting context limits — the model auto-summarises older conversation context during long-running analysis sessions, sustaining coherent multi-step reasoning across arbitrarily large knowledge bases.[^7]

***

## What This Actually Feels Like to the User

After 90 days, a user opening Timed at 6:45am should experience something like this:

*The morning voice session begins.*

**Timed:** "Good morning. Before you look at anything — I need to tell you three things.

First: the Series B prep document has been on your plan for 6 days and you've deferred it every day. Based on your pattern, you're stuck on the financial projections section, not the narrative. The last two times you got stuck like this you spent 40 minutes doing other things before coming back to it. I've blocked 6:45–8:30am for it this morning and pre-loaded the relevant financial context. The only question I need from you is: has anything changed on the round terms that would affect the projections?

Second: today is Wednesday — your historically worst day for deep work. You have 5 meetings and a pattern of accepting 'quick question' calls after your 2pm. I've blocked 4:30–6pm for follow-up work and set your status to 'unavailable'. You can override this if something comes up.

Third: you're carrying 23 tasks on your list and you've completed an average of 6 tasks per day for the past 30 days. The math doesn't work. I've hidden 14 tasks from today's view — not deleted, just invisible. The 9 you're seeing are the ones with meaningful consequence if they don't move today. We should talk about pruning the list properly on Friday."*

This is not a feature. This is what a great Chief of Staff does. It requires memory. It requires reflection. It requires Opus running at maximum effort on real accumulated data. And it cannot be faked with a rules engine — it requires genuine intelligence applied to genuine knowledge of a specific person.

***

## The Product's Core Promise

Executives make 35,000 decisions per day and experience decision fatigue that degrades judgment by end of day. HBR research shows that heavy oversight of AI outputs pushes decision fatigue up 33% — meaning bad AI design makes the problem worse, not better. The correct design is AI that **absorbs decisions entirely** rather than asking the human to review and approve them.[^21][^1]

Timed's architecture is designed around this principle: every low and mid-tier cognitive decision — what to do next, when to do it, how long it will take, what to defer, what to drop — is handled by the system invisibly, grounded in deep behavioural knowledge. The executive makes high-tier decisions: strategic direction, human judgment calls, ethical choices. Everything else is Timed's job.

That is the revolution. Not a better calendar. Not a smarter to-do list. A system that genuinely understands how a specific human being operates and uses that understanding to give them their cognitive bandwidth back — every single day, compounding over time.

---

## References

1. [Decision Fatigue in the Age of AI: How Critical Thinking Keeps ...](https://c-suitenetwork.com/decision-fatigue-in-the-age-of-ai-how-critical-thinking-keeps-leaders-ahead/) - AI promises to analyze more data, faster, without the biological constraints of human cognition. Yet...

2. [Introducing Claude Opus 4.6 - Anthropic](https://www.anthropic.com/news/claude-opus-4-6) - On the API, Claude can use compaction to summarize its own context and perform longer-running tasks ...

3. [Building with extended thinking - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/extended-thinking) - To turn on extended thinking, add a thinking object, with the type parameter set to enabled and the ...

4. [Claude Opus 4.6 Review (2026) — 1M Context & Benchmarks](https://webscraft.org/blog/claude-opus-46-detalniy-oglyad-flagmanskoyi-modeli-anthropic-2026?lang=en) - Claude Opus 4.6 operates as a hybrid reasoning model, fusing standard inference outputs with extende...

5. [Claude Opus 4.6: Features, Benchmarks, Tests, and More | DataCamp](https://www.datacamp.com/blog/claude-opus-4-6) - Anthropic's Claude Opus 4.6 brings a 1M context window, adaptive thinking, and top scores on coding ...

6. [The Only Opus 4.6 Breakdown That's Actually About YOU.](https://limitededitionjonathan.substack.com/p/the-only-opus-46-breakdown-thats) - The model sustains agentic coding tasks for longer. In autonomous coding workflows — where the model...

7. [Opus 4.6: The Vibe Working Inflection - Emergent Minds | paddo.dev](https://paddo.dev/blog/opus-4-6-vibe-working-inflection/) - Adaptive thinking: The model decides when extended reasoning helps. No more toggling between thinkin...

8. [Claude Opus 4.6 Introduces Adaptive Reasoning and Context ...](https://www.infoq.com/news/2026/03/opus-4-6-context-compaction/) - Best applied to complex tasks across coding, knowledge work, and agent-driven workflows, supporting ...

9. [Anthropic Claude Opus 4.6: Is the Upgrade Worth It? - Codecademy](https://www.codecademy.com/article/anthropic-claude-opus-4-6) - Opus 4.6 leads in long-context retrieval (76% vs o3's ~45% on MRCR), agentic workflows, and sustaine...

10. [Generative Agents: Interactive Simulacra of Human Behavior - arXiv](https://arxiv.org/abs/2304.03442) - In this paper, we introduce generative agents--computational software agents that simulate believabl...

11. [The Stanford Paper That Created AI People | Ditto](https://askditto.io/news/the-stanford-paper-that-created-ai-people) - A deep explanation of 'Generative Agents: Interactive Simulacra of Human Behavior' by Park et al. (2...

12. [Stanford U & Google's Generative Agents Produce Believable ...](https://syncedreview.com/2023/04/12/stanford-u-googles-generative-agents-produce-believable-proxies-of-human-behaviours/) - The agent can retrieve relevant information from its memory stream, reflect on this, and plan action...

13. [[R] Generative Agents: Interactive Simulacra of Human Behavior](https://www.reddit.com/r/MachineLearning/comments/12hluz1/r_generative_agents_interactive_simulacra_of/) - In this paper, we introduce generative agents--computational software agents that simulate believabl...

14. [AI Agents Simulate 1052 Individuals' Personalities with Impressive ...](https://hai.stanford.edu/news/ai-agents-simulate-1052-individuals-personalities-with-impressive-accuracy) - Scholars hope these generative agents based on real-life interviews can solve society's toughest pro...

15. [Simulating Human Behavior with AI Agents | Stanford HAI](https://hai.stanford.edu/policy/simulating-human-behavior-with-ai-agents) - Using this architecture, we created generative agents that simulate 1,000 individuals, each using an...

16. [Generative AI at Work* | The Quarterly Journal of Economics](https://academic.oup.com/qje/article/140/2/889/7990658) - Our findings show that access to generative AI suggestions can increase the productivity of individu...

17. [[PDF] Active Preference Inference using Language Models and ... - arXiv](https://arxiv.org/pdf/2312.12009.pdf) - Actively inferring user preferences, for example by asking good questions, is important for any huma...

18. [The 3 Types of Long-term Memory AI Agents Need](https://machinelearningmastery.com/beyond-short-term-memory-the-3-types-of-long-term-memory-ai-agents-need/) - The roles of episodic, semantic, and procedural memory in autonomous agents · How these memory types...

19. [Long-Term Memory: Unlocking Smarter, Scalable AI Agents](https://aipractitioner.substack.com/p/long-term-memory-unlocking-smarter-38d) - This article explores how to incorporate long-term memory into LangGraph agent architectures. It dis...

20. [Better Ways to Build Self-Improving AI Agents - Yohei Nakajima](https://yoheinakajima.com/better-ways-to-build-self-improving-ai-agents/) - The simplest form of self-improvement is reflection at inference time: Reflexion (Shinn et al., 2023...

21. [14% of Workers Experience Cognitive Fog, 33% Decision Fatigue](https://www.linkedin.com/posts/hirelucius_new-hbr-research-puts-a-number-on-what-a-activity-7437911044792057856-lTSN) - 1,500 workers surveyed. 14% report cognitive fog from AI use. Heavy oversight of AI outputs pushes d...

