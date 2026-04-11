# Timed — Optimal Research Programme for Claude Code

## Preamble: Design Decisions

**Why 14 prompts, not more or fewer.**

The master session already covered the landscape at a survey level. The 14 prompts below go one layer deeper in each domain — from "what exists" to "how to build it." Each prompt is sized to produce a report dense enough to give Claude Code real architectural direction, not just background reading.

The constraint governing scope: **no cost cap, intelligence quality only.** Every prompt below assumes frontier models (Opus 4.6 or equivalent) at maximum capability. No prompt should ask for "cost-efficient alternatives," "lightweight approaches," or "smaller models where acceptable." Where model selection is discussed, the answer is always: use the most capable available.

Twelve of the fourteen prompts can run in parallel on day one. Two depend on earlier results and are flagged explicitly.

***

## The 14 Prompts

***

### Prompt 1 — AI Memory Architecture for a Single Human at Scale

**Why this prompt exists:** Claude Code cannot design the memory system — the most critical architectural component — without knowing the current state of the art in persistent, compounding AI memory at production scale.

**Core question:** What is the optimal memory architecture for a system that builds a compounding model of one specific human over 12+ months, using frontier LLMs with no cost constraints?

**Sub-questions:**
1. How do MemGPT, MemOS, and the Stanford Generative Agents architecture each implement memory tiers, retrieval, and reflection — and what are the specific data structures and algorithms used?
2. What is the right granularity of memory objects? (raw observations vs. first-order summaries vs. abstract patterns vs. personality-level traits — and how do these layers relate?)
3. How should the nightly "sleep cycle" (offline consolidation pass) be implemented — what triggers it, what does it process, what does it prune, what does it elevate, and which model should run it?
4. How should retrieval work at query time — embedding similarity, recency decay, importance weighting, and temporal reasoning across a 12-month archive?
5. What are the best embedding models and vector database schemas for this use case (single-user, high-volume, longitudinal, temporally indexed)?
6. How should the system handle contradictory observations — where new data conflicts with an established pattern — without catastrophic forgetting?

**Recommended output format:** Architecture spec with decision tables (comparing MemOS vs. MemGPT vs. custom approaches), schema designs for the memory store, pseudocode for the consolidation pipeline, and a ranked list of design decisions with rationale.

**Estimated depth:** Comprehensive

***

### Prompt 2 — Digital Signal Extraction: Every Observable Behaviour and What It Encodes

**Why this prompt exists:** The system's intelligence is only as good as the signals it can extract from passive macOS observation — Claude Code needs to know exactly what is detectable, how to extract it, and what each signal encodes at the cognitive level.

**Core question:** What cognitive, emotional, relational, and decision-quality intelligence can be extracted from passive observation of an executive's macOS behaviour — email metadata, calendar structure, keystroke dynamics, voice, application usage — and what are the extraction architectures for each?

**Sub-questions:**
1. What is the full signal taxonomy from email metadata alone — response latency, thread patterns, communication reciprocity, language complexity, send-time patterns, network topology — and what is the validated research on what each encodes (stress, relationship health, cognitive load, avoidance)?
2. What does the science say about keystroke dynamics as a real-time cognitive state biomarker — what features to extract (inter-key latency, error rate, rhythm variance), what models to run, and what accuracy is achievable?
3. What acoustic features from on-device voice (meetings, dictation, calls) encode stress, cognitive load, fatigue, and emotional valence — what are the extraction pipelines and the validated models?
4. What can calendar structure and dynamics encode — meeting density, fragmentation index, cancellation patterns, calendar compression over time — and what decision-quality and cognitive load signals are extractable?
5. What higher-order intelligence is derivable by combining signals across modalities — what multi-signal fusion architectures produce the most accurate state estimates?
6. What are the macOS-specific APIs (EventKit, Mail, ScreenTime, CoreAudio, Accessibility) and their capabilities, limitations, and privacy implications for each signal type?

**Recommended output format:** Signal taxonomy table (signal → extraction method → what it encodes → validated accuracy → macOS API), followed by architecture diagrams for each extraction pipeline, followed by a multi-signal fusion design.

**Estimated depth:** Comprehensive

***

### Prompt 3 — The Compounding Mechanism: How Month 1 Becomes Month 12

**Why this prompt exists:** The system's core value proposition is intelligence that compounds — this prompt defines exactly how that compounding is designed and what makes it qualitatively, not just quantitatively, different over time.

**Core question:** How do you architect a system so that month 6 intelligence is qualitatively different from month 1 — not more data, but deeper understanding — and what are the specific mechanisms, data structures, and model interactions that produce this compounding?

**Sub-questions:**
1. What is the theoretical model of compounding intelligence — what transitions happen at what timescales (days → weeks → months → year) and what new capabilities emerge at each level?
2. How does the reflection loop translate raw observations into first-order patterns, first-order patterns into second-order abstractions, and those into a stable executive model — what are the prompts, data structures, and model calls at each step?
3. How do you detect that a pattern is real (statistically significant, temporally stable) versus artefactual (driven by a single event or seasonal anomaly)?
4. How should the system model change over time — when the executive changes, how does the system update its prior model without losing the historical signature?
5. What does the system know about an executive at month 1 that it cannot know at day 1 — at month 3 that it cannot know at month 1 — at month 12 that it cannot know at month 3? Map the capability curve precisely.
6. What are the best evaluation metrics for a compounding personal intelligence system — how do you measure whether the model is actually getting smarter about this specific human?

**Recommended output format:** A tiered capability model (table: time → what the system knows → what intelligence is now producible), followed by a detailed architecture of the reflection/abstraction pipeline with pseudocode, followed by a pattern validation framework.

**Estimated depth:** Comprehensive

***

### Prompt 4 — Cognitive Science of C-Suite Decision-Making at Depth

**Why this prompt exists:** The system's insight generation layer needs to know what patterns to look for, what failure modes matter most, and what interventions actually change executive decision quality.

**Core question:** What does the cognitive science, organisational psychology, and behavioural economics research say about how C-suite executives actually think, decide, and fail — and what does this mean for the design of a system that observes and models them?

**Sub-questions:**
1. What are the cognitive biases with the highest documented impact on C-suite decision quality — with specific evidence on prevalence, impact magnitude, and whether they are detectable from behavioural signals?
2. What does the research on expert decision-making (Klein's RPD model, Kahneman's System 1/2, dual-process theory) say about the conditions under which executives use fast pattern matching vs. deliberate analysis — and what behavioural signals distinguish these modes?
3. What is the science of decision fatigue in high-stakes environments — when does it set in, what are its measurable behavioural markers, and how do time-of-day and workload interact to predict decision quality?
4. What do the Harvard CEO time allocation studies, Russell Reynolds research, and McKinsey data say about the systematic gaps between how executives believe they operate and how they actually operate — and what is most useful for an observation system to track?
5. What research exists on which executive decisions are most likely to be reversed, regretted, or value-destroying — and what conditions precede them?
6. What does the science say about the most effective interventions for each major bias — what framing, timing, and delivery modality produces actual behaviour change vs. what produces acknowledgment and dismissal?

**Recommended output format:** Bias taxonomy table (bias → prevalence evidence → behavioural signal correlates → detection approach → intervention design), followed by a decision failure mode map, followed by design principles for the insight generation layer.

**Estimated depth:** Comprehensive

***

### Prompt 5 — Intelligence Delivery: Briefings, Alerts, and Voice That Change Decisions

**Why this prompt exists:** An observation system that generates perfect intelligence and delivers it badly produces zero value — the delivery architecture determines whether insights change decisions or get ignored.

**Core question:** How do you design a personal intelligence delivery system for a C-suite executive that ensures insights are engaged with, acted upon, and never ignored — covering the morning brief, real-time alerts, weekly synthesis, and voice interaction?

**Sub-questions:**
1. What does CIA PDB design, military intelligence briefing research, and high-stakes communication science say about the principles that make intelligence land versus get dismissed — format, framing, length, confidence calibration, and sequencing?
2. How should the morning brief be structured — what information architecture, what lead format (decision implication first or observation first?), what length, what is included vs. deliberately omitted?
3. What is the threshold and timing logic for real-time alerts — when should the system interrupt the executive, what salience/confidence threshold justifies interruption, and how does timing relative to cognitive state affect whether an alert is acted on?
4. What does conversational AI research say about the optimal voice interaction design for delivering uncomfortable insights — tone, pacing, framing, and the sequence of disclosure?
5. How should the system learn which delivery formats this specific executive engages with and adapts over time — what feedback signals (engagement, dismissal, follow-up queries) train the delivery model?
6. What does the attention economy and cognitive load research say about the maximum information density that lands per interaction — and how should the system ruthlessly filter signal from noise?

**Recommended output format:** A delivery design spec — briefing template with annotated structure, alert decision matrix (condition → threshold → timing → format), voice interaction design principles, and a feedback learning architecture.

**Estimated depth:** Comprehensive

***

### Prompt 6 — Executive Coaching Methodology: What to Automate, What to Preserve

**Why this prompt exists:** The system must encode what the world's best executive coaches know about building a model of someone over months — including which observations matter most and how to deliver insights that produce behaviour change.

**Core question:** What do the world's best executive coaches actually do over a 6–12 month engagement that produces lasting change — what do they observe, what patterns do they build, how do they deliver hard truths, and which elements of this can be automated by a passive observation system?

**Sub-questions:**
1. What specific observational categories do elite coaches track over months — and how do they distinguish signal from noise in client behaviour patterns?
2. What does the research on coaching effectiveness say distinguishes coaches who produce lasting change from those who produce short-term compliance — and how does the insight delivery mechanism differ?
3. What is the science of psychological safety and how it affects whether feedback lands — what must a system establish before it can deliver uncomfortable observations without triggering defensive dismissal?
4. What patterns do coaches consistently report as the most transformative to surface — the observations clients most reliably say "I've never seen that about myself, but it's exactly right"?
5. How do coaches build a model of what a client avoids, deflects, or protects — and what are the behavioural signatures of avoidance that a digital system could detect?
6. What cannot be automated — what elements of coaching effectiveness are irreducibly dependent on human relationship, and how should an automated system position itself relative to those elements?

**Recommended output format:** An automation feasibility matrix (coaching function → automatable? → how → what remains human), followed by an observation priority framework (what to look for in order of insight value), followed by design principles for insight delivery framing.

**Estimated depth:** Comprehensive

***

### Prompt 7 — Chronobiology, Energy, and Cognitive Scheduling

**Why this prompt exists:** The system must know when the executive is at peak cognitive performance, when they are depleted, and use this to optimise both insight delivery timing and executive self-awareness about their own cognitive rhythms.

**Core question:** What does chronobiology, energy management, and circadian science say about how to model an individual executive's cognitive performance curve — and how can this be inferred from passive digital behaviour and used to improve both the system's insight delivery and the executive's own scheduling?

**Sub-questions:**
1. What is the current state of chronotype science — how stable are individual chronotypes, how much does cognitive performance vary across the day, and what are the most reliable inferred markers of chronotype from digital behaviour (send times, activity patterns, error rates)?
2. What is the ultradian rhythm (the 90–120 minute attention cycle) and what does the research say about using it to model intra-day cognitive performance peaks and troughs?
3. What does the science say about energy depletion — how do meeting load, decision density, and context-switching contribute to cognitive depletion, and what are the detectable signatures of approaching depletion?
4. What research exists on cognitive scheduling for executives — what time allocation patterns correlate with better decision quality, and how does the research on "maker vs. manager" schedules apply?
5. How should the system infer and refine a chronotype model for a specific individual from months of passive observation — what signals are most reliable, and how does the model update as lifestyle changes?
6. How does chronotype-aware insight delivery work in practice — what is the decision rule for when to surface an insight vs. hold it for a better window?

**Recommended output format:** A chronotype inference model (signals → features → inference algorithm), an energy depletion detection spec, and a timing decision framework for insight delivery.

**Estimated depth:** Comprehensive

***

### Prompt 8 — Communication, Relationship, and Organisational Intelligence from Email and Calendar

**Why this prompt exists:** Email and calendar are the richest behavioural data sources available, and extracting organisational network intelligence, relationship health signals, and decision-load markers from them requires deep domain-specific architecture.

**Core question:** How do you extract the maximum relationship, organisational, and cognitive intelligence from an executive's email metadata and calendar structure — using frontier models, embedding-based analysis, and graph analytics — without reading email content?

**Sub-questions:**
1. What is the full architecture of Organisational Network Analysis (ONA) from email metadata — nodes, edges, directionality, centrality metrics — and what specific intelligence is derivable (influence mapping, information bottlenecks, relationship health, disengagement signals)?
2. What signals in email metadata and threading patterns most reliably encode relationship health over time — response latency changes, reciprocity shifts, network centrality changes — and what validated research supports each?
3. How do you detect disengagement, avoidance, and deteriorating relationships from communication patterns without access to content — what are the specific features and their validated accuracy?
4. What calendar analytics produce the most valuable intelligence — fragmentation index, meeting-to-focus ratio, reactive vs. strategic time allocation, cancelled meeting patterns — and how are these computed?
5. How should the system build and maintain a relationship graph for the executive — what schema, what update mechanism, what decay functions for relationships that go quiet?
6. What frontier model capabilities (graph embeddings, temporal sequence modelling, anomaly detection) are most applicable to this domain — and what is the optimal pipeline from raw metadata to actionable insight?

**Recommended output format:** ONA architecture spec, relationship graph schema, calendar analytics computation guide, and a pipeline diagram from raw email/calendar data to insight candidate.

**Estimated depth:** Comprehensive

***

### Prompt 9 — Voice Analysis, Emotional Inference, and Conversational AI

**Why this prompt exists:** Voice is the real-time cognitive state signal that no other data source can match — and the conversational AI interface for delivering insights requires its own design discipline.

**Core question:** How do you build a voice analysis and conversational AI layer that extracts real-time cognitive and emotional state from on-device audio, and delivers personalised intelligence through voice in a way that is trusted, precise, and effective with C-suite executives?

**Sub-questions:**
1. What is the current state of voice-based cognitive and emotional state inference — what acoustic features (MFCC, pitch variance, speech rate, disfluencies, prosody) encode which states (stress, fatigue, cognitive load, emotional valence) with what validated accuracy?
2. How do you build an on-device voice processing pipeline on macOS that captures meeting audio, dictation, and calls — what APIs, what pre-processing, what privacy architecture?
3. What frontier speech models (Whisper, proprietary ASR) and acoustic analysis models produce the highest-quality state estimation from real-world executive speech — noisy environments, multiple speakers, variable acoustic quality?
4. How should conversational AI voice delivery be designed for C-suite executives — what speech synthesis style (voice, pacing, formality, confidence calibration) produces trust and engagement rather than dismissal?
5. How does the voice interaction design change when delivering uncomfortable insights vs. routine briefings vs. real-time alerts?
6. What longitudinal learning is possible from voice alone — what can month 6 infer from an executive's voice that month 1 cannot?

**Recommended output format:** On-device audio pipeline architecture, acoustic feature extraction spec, model selection table (with rationale), and voice UX design principles for high-stakes insight delivery.

**Estimated depth:** Comprehensive

***

### Prompt 10 — Behavioural Prediction, Avoidance Detection, and Burnout Forecasting

**Why this prompt exists:** The system's most transformative capability — predicting what the executive will do, avoid, or fail at before they do — requires its own research foundation in predictive behavioural modelling.

**Core question:** How do you build a behavioural prediction layer that forecasts decision reversals, avoidance patterns, and approaching burnout from longitudinal digital behavioural data — using the most capable frontier models without cost constraints?

**Sub-questions:**
1. What is the science of avoidance behaviour in executive contexts — what are the cognitive and emotional mechanisms, and what specific digital behavioural signatures most reliably indicate avoidance of a decision or task?
2. What does the research on burnout prediction from digital behavioural signals say — what are the leading indicators (weeks or months before clinical burnout) that appear in email patterns, calendar density, communication behaviour, and voice characteristics?
3. What methods produce the most accurate decision reversal prediction — what features, what model architectures, and what temporal horizon is achievable from digital behaviour alone?
4. How do you build a Bayesian or probabilistic model of an individual's decision-making that updates with each observed decision — encoding not just patterns but the confidence and stability of those patterns?
5. What does temporal sequence modelling (LSTMs, Transformer-based sequence models, state space models) offer for longitudinal behavioural prediction over individual tracking data — and what architecture is optimal for this use case?
6. How should the system communicate predictions — what confidence threshold is required before surfacing a prediction, how should uncertainty be conveyed, and how does the system build predictive credibility over time?

**Recommended output format:** Behavioural signal taxonomy for prediction (signal → what it predicts → validated lead time → model approach), burnout detection architecture, decision reversal prediction model spec, and a prediction confidence communication framework.

**Estimated depth:** Comprehensive

***

### Prompt 11 — Privacy, Trust Architecture, and the Right to Observe

**Why this prompt exists:** A system this observationally intimate will not be adopted — regardless of its intelligence quality — unless its privacy architecture is impeccable and its trust-earning mechanism is explicitly designed.

**Core question:** How do you build the privacy architecture, consent framework, and trust-earning sequence for a passive observation system that an ultra-high-stakes C-suite executive will actually adopt and sustain?

**Sub-questions:**
1. What privacy architecture is required — local processing vs. cloud, what data never leaves the device, what data is encrypted at rest vs. in transit, what is stored in Supabase vs. kept on-device — for a system processing email metadata, calendar, keystrokes, and voice?
2. What are the legal frameworks that govern this type of behavioural data collection for an individual user on their own device — GDPR Article 9, CCPA, UK GDPR, and enterprise-level considerations if the device is company-issued?
3. What is the psychological research on how ultra-high-trust relationships are established with surveillance-adjacent technology — what sequence of permission granting, value demonstration, and control provision builds rather than erodes trust?
4. What does the research on informed consent and data transparency say about how the system should communicate what it observes, what it stores, and what it infers — without overwhelming the user or triggering defensive rejection?
5. How should the trust-earning sequence be designed — what does the system demonstrate in weeks 1–4 before it earns access to more intimate signals (voice, keystroke analysis, avoidance detection)?
6. What adversarial scenarios must the architecture defend against — data breach by a hostile party, divorce proceedings, litigation discovery, corporate espionage — and what is the right architecture for each?

**Recommended output format:** Privacy architecture diagram (data flow, storage locations, encryption), legal compliance framework, trust-earning sequence design (week-by-week), and adversarial threat model with mitigations.

**Estimated depth:** Comprehensive

***

### Prompt 12 — Cold Start: Maximum Value Before Any Learning Has Occurred

**Why this prompt exists:** The system must be impressive from day one, before it has observed anything about this executive — and the cold start architecture determines whether executives retain the system through the first critical weeks.

**Core question:** How do you make a personal cognitive intelligence system genuinely valuable from day 1, before it has learned anything specific about this executive — using frontier models, intelligent defaults, and rapid baseline establishment?

**Sub-questions:**
1. What can frontier models (Opus 4.6 with deep prompting) infer about an individual executive from their first 48 hours of observation — even with no prior history — using base-rate intelligence about C-suite cognition?
2. What is the optimal onboarding sequence — what structured interview, what initial questions, what self-reported data — that gives the system the highest-value seed information before passive observation has produced patterns?
3. What does the research on rapid rapport building and first-impression accuracy say about how quickly a skilled observer can model a new person — and what can be replicated computationally?
4. What default intelligence is universally relevant to C-suite executives (from the Porter/Nohria research, Klein's RPD work, McKinsey decision bias data) and can be delivered accurately before any personalisation?
5. How do you manage the expectation gap — the period between "impressive from day one generic intelligence" and "impressive because it knows this specific person" — so the executive stays engaged through the model-building phase?
6. What is the minimum observation period before the system can produce its first personalised, non-generic insight — and what is the trajectory from day 1 to week 4 to month 3?

**Recommended output format:** Onboarding sequence design (day-by-day for week 1, week-by-week for month 1), cold start intelligence architecture, and a value trajectory framework (what is deliverable at each stage without personalised data).

**Estimated depth:** Comprehensive

***

### Prompt 13 — Swift/macOS Architecture: Building the System That Never Sleeps

**Why this prompt exists:** The macOS application layer — the part that passively observes, processes signals locally, and communicates with the intelligence backend — is the most technically specific component and needs its own dedicated research.

**Core question:** What is the optimal Swift/macOS architecture for a background application that continuously observes an executive's digital behaviour, processes signals locally, and coordinates with a Supabase backend and Claude API — designed for maximum reliability, privacy, and intelligence quality?

**Sub-questions:**
1. What macOS system APIs (EventKit, Mail Plugin API, CoreAudio, Accessibility API, ScreenTime, NSWorkspace) are available for passive observation — their capabilities, limitations, privacy requirements, and App Store vs. non-App Store implications?
2. How should the background processing architecture work — what runs on a continuous daemon, what uses scheduled jobs, what triggers event-based processing, and how is battery/CPU impact managed on a MacBook Pro?
3. What is the optimal local processing pipeline — what signal extraction and initial feature computation happens on-device before anything goes to the backend, and what models can run locally (Core ML, on-device Whisper) to minimise latency and maximise privacy?
4. How should the Supabase schema be designed for this system — what tables, what relationships, what indexing strategy for temporal queries across months of behavioural data, and what Edge Functions handle the nightly consolidation?
5. How should the Claude API integration be structured — what calls use Haiku vs. Sonnet vs. Opus 4.6, what is the optimal prompt architecture for each type of intelligence generation (pattern detection, insight synthesis, brief generation, conversational response), and how is context window management handled for 12-month archives?
6. What is the deployment and update architecture for a macOS app with sensitive data — how are model updates, schema migrations, and feature additions handled without disrupting the running system or losing historical data?

**Recommended output format:** System architecture diagram, macOS API capability table, Supabase schema specification (SQL), Claude API integration design (what model for what task, prompt patterns), and a local/cloud processing decision matrix.

**Estimated depth:** Comprehensive

***

### Prompt 14 — What Makes This a Movement, Not Just a Product

**Why this prompt exists:** Timed's goal is not incremental improvement on existing tools — it is category creation — and this requires understanding the conditions under which a product becomes a movement and how to design for that from the first version.

**Core question:** What transforms a revolutionary product into a category-defining movement — and how should Timed be designed, positioned, and introduced to the market to create a new category that it permanently owns?

**Sub-questions:**
1. What are the documented cases of technology products that created entirely new categories (rather than competing in existing ones) — and what were the specific design, positioning, and distribution decisions that made category creation possible?
2. What does the research on executive technology adoption say — what makes a C-suite executive champion a tool, advocate it to peers, and build their identity around it?
3. What pricing architecture, exclusivity design, and scarcity mechanics are most effective for ultra-high-end software products targeting Fortune 500 CEOs — what price signals quality vs. disqualifies?
4. What does the science of word-of-mouth and peer referral in ultra-high-trust networks (CEO peer groups, board relationships, investor networks) say about how products spread at the top of the market?
5. How should the product's first 100 users be selected — what criteria, what onboarding, what relationship architecture — to maximise the probability of organic advocacy from the most credible voices?
6. What is the design of the "impressive moment" — the specific first experience that makes an executive say "I cannot imagine working without this" — and what does it need to demonstrate to create that response?

**Recommended output format:** Category creation case study analysis (table), executive adoption psychology framework, pricing and exclusivity design spec, first-100-users strategy, and the "impressive moment" design blueprint.

**Estimated depth:** Comprehensive

***

## Programme Summary

### Total: 14 Prompts

**Why 14:**
The master session produced a landscape survey. Each of the 14 prompts goes one architectural layer deeper in a specific domain. Fewer prompts would require combining domains that have genuinely different research bases and produce worse output (the technical architecture of macOS APIs should not share a prompt with the psychology of trust-building). More prompts would produce redundancy — the domains above are genuinely distinct, non-overlapping, and each requires a dedicated deep session to produce construction-grade intelligence.

### Parallelism

**Run all 14 in parallel on day one.** None of the 14 prompts depends on the output of another. The master session already established the shared conceptual foundation. Each prompt below goes deep in its own lane, and Claude Code will synthesise across all 14 simultaneously when it receives the full library.

The one minor exception worth noting: if Prompt 3 (The Compounding Mechanism) produces a specific architecture decision that changes the memory schema, you may want to review Prompt 1 (Memory Architecture) against it before finalising the Supabase schema in Prompt 13. But this is a review step, not a dependency — all 14 can run in parallel.

### What the Combined Library Gives Claude Code

No single source — not any paper, not any open-source codebase, not any existing product — combines:

- The cognitive science of how this specific type of user thinks and fails
- The behavioural signal science for every extractable data source
- The memory architecture for compounding longitudinal intelligence
- The delivery design for making intelligence actually land
- The coaching methodology for what to observe and how to surface it
- The chronobiology layer for timing everything correctly
- The privacy architecture that makes enterprise adoption possible
- The cold start design so the system earns trust before it has learned anything
- The macOS/Supabase/Claude API implementation specifics
- The movement strategy for category creation

Claude Code loaded with all 14 reports will have the most comprehensive build brief ever assembled for a personal AI system. It will not need to make undirected assumptions in any domain.

### Gaps Not Yet Covered

Three areas are worth flagging that are not fully covered by the 14 prompts above — whether to add them is a judgement call:

1. **Quantitative validation and evaluation design**: How do you measure whether the system is actually getting smarter about a specific executive? What are the ground truth signals, what are the A/B testing approaches, and how do you build a continuous improvement loop? This is a distinct research domain and could become Prompt 15 if rigorous measurement is a priority from version 1.

2. **Competitor and adjacent product intelligence at depth**: The master session covered failures at a high level. A dedicated prompt on the current competitive landscape — what products exist today (including recent 2025/2026 launches), their exact architectures, their failure modes, and the white space they leave — would sharpen the differentiation case and help Claude Code avoid architectural decisions that have already been tried and failed.

3. **Long-term behaviour change science**: The system observes and advises — but does observation and advice alone produce durable behaviour change in executives? The behavioural economics research on commitment devices, implementation intentions, and sustained habit formation in high-achievers is a distinct domain from coaching methodology and might produce important design constraints on what the system should and should not attempt.

None of these are blockers for building version 1. All three are worth adding if the goal is to build the definitive version.