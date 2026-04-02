# Research Pack 01 — The Vision

> Give this to Perplexity Deep Research. Save the result. Bring it back.

---

## Prompt 1 — How Do You Build the Most Intelligent Executive Operating System Ever Made?

I'm building a macOS application called Timed.

**The hard constraint: Timed never acts on the world. It is observation and intelligence only.** It never sends emails, modifies calendars, or takes any action without the human deciding and executing. This is non-negotiable. It is a cognitive intelligence layer — not a personal assistant, not an agent.

Timed sits on a C-suite executive's computer and builds a deep, compounding cognitive model of how that specific person thinks, decides, avoids, prioritises, communicates, and operates — and then uses that model to give them their cognitive bandwidth back, permanently.

It is not a productivity app. It is not a task manager. It is not competing with Motion, Sunsama, or any scheduling tool.

Here's what exists today:
- A voice-first morning session: the executive talks for 90 seconds, the AI builds their day plan from what it knows about them
- AI email triage: connected to Outlook via Microsoft Graph, classifies emails into action buckets, learns from corrections over time
- ML task scoring: Thompson sampling that factors urgency, deadlines, mood, energy curve, and learned behavioural rules to rank what matters
- ML time estimation: learns how long things actually take this specific person (not generic estimates) via exponential moving average over weeks
- Calendar-aware scheduling: reads Outlook calendar, finds free slots, places tasks optimally
- Focus timer that feeds completion data back into the learning loop
- Menu bar presence for glanceable awareness

What's designed but not yet built — the intelligence core:
- A three-layer memory system (episodic memories of what happened, semantic memories of what's been learned about the person, procedural memories of rules for how they operate)
- A swarm of lightweight background agents that continuously observe and log signals
- A deep reflection engine that runs periodically — takes raw observations, extracts first-order patterns, synthesises second-order insights, updates the person's cognitive model, and generates new operating rules. Inspired by the Stanford Generative Agents paper (Park et al. 2023) which proved that reflection loops compounding over time produce qualitatively superior intelligence
- A morning intelligence session that doesn't just deliver a task list — it opens with named patterns it's detected, interrogates avoidance behaviours, explains its own reasoning, and gives the executive a cognitive briefing from a system that has spent time thinking about them

The user is a C-suite executive who has tried every tool, hired coaches, has a PA. They are not impressed by features. They would be impressed by a system that understands them in a way nothing else does, and gets measurably smarter the longer they use it. Month 6 should be incomparably more intelligent than month 1.

**Here is what I need from you:**

1. **What does the conceptual architecture of the most intelligent personal AI system look like?** Not code — the components, how they interact, what processes information, when, and why. What is the right way to structure a system that continuously observes a single human, builds a compounding model of them, and delivers intelligence back? I'll do a dedicated deep dive on specific memory architectures (generative agents, MemGPT, cognitive architectures, etc.) separately — for now, give me the high-level blueprint of how the pieces fit together.

2. **What should it observe and what intelligence is extractable from those signals?** Every possible signal source — calendar, email, voice, typing patterns, app usage, meeting behaviour, communication dynamics, response patterns, energy rhythms. And from those raw signals, what higher-order intelligence can be inferred? Cognitive load, stress, relationship health, decision quality, avoidance patterns, chronotype, attention capacity, strategic vs tactical time allocation.

3. **How does intelligence genuinely compound over time, and how do you solve the retrieval problem?** This is the core question. What architectures produce intelligence that gets qualitatively better over months? What's the difference between a system that accumulates data and one that genuinely gets smarter? And critically: when the reflection engine runs, how does it decide which of 10,000+ episodic memories are relevant to surface? The Stanford Generative Agents paper uses recency × importance × relevance scoring — what else exists? What are the state-of-the-art approaches to memory retrieval in systems that model a single person over long time horizons?

4. **How do you deliver intelligence to a busy executive?** Morning briefing design. Proactive alerts vs reactive responses. Voice-first interaction that feels like a brilliant chief of staff, not a chatbot. What does the research on executive coaching, intelligence briefings, and decision support say about how to deliver insight to someone who has 30 seconds of patience?

5. **What has been tried, what worked, what failed, and why — specifically, what was the architectural or market assumption that broke?** Every AI executive tool, personal AI assistant, and failed startup that attempted anything in this space: Rewind/Limitless, Humane, Rabbit, Clara, x.ai, the meeting AI wave, the scheduling AI wave, coaching AI. For each failure, I don't want a graveyard tour — I want the specific technical limitation, architectural mistake, or market misread that killed it. What lesson does each failure teach about what NOT to do?

6. **What would make this worth $500+/month to a CEO?** Not pricing strategy — value architecture. What capabilities, what depth of intelligence, what quality of insight would make a Fortune 500 CEO say "this is the most valuable tool I've ever used"? What does the research on executive performance, decision quality, and cognitive bandwidth say about the economic value of what I'm describing?

Give me the full landscape. Hold nothing back. I will use this to design the most ambitious personal intelligence system ever attempted, and then I will build it.
