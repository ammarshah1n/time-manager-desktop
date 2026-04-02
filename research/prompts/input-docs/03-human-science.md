# Research Pack 03 — Human Science & Delivery Design

> Give all 5 prompts to Perplexity Deep Research, one at a time. Save each result. Bring them all back.

---

## Prompt 7 — What Elite Executive Coaches Actually Do (and What Can Be Automated)

I'm building an AI system that builds a compounding cognitive model of a C-suite executive. The closest human analogue is an elite executive coach — the kind who charges $50,000+ per engagement and works with Fortune 500 CEOs.

I need to deeply understand what these coaches actually do — not pop-psychology, the real methodology — so I can design an AI system that builds equivalent or deeper intelligence from continuous behavioural observation.

Research:
1. **Assessment frameworks** — How do elite coaches build a model of an executive? Psychometrics (Hogan, MBTI, StrengthsFinder, and beyond), 360 reviews, behavioural observation, shadowing, structured interviews. What data do they collect? What do they look for?

2. **What patterns do they identify?** — Avoidance behaviours, decision-making biases, delegation failures, communication blind spots, strategic vs tactical imbalance, energy management problems, relationship dynamics. What are the TOP 10 patterns that coaches consistently find in C-suite executives?

3. **How do they deliver insight?** — Tell vs ask? Direct feedback vs Socratic questioning? What's the mechanism of behaviour change in coaching? Miller & Rollnick's motivational interviewing applied to executives?

4. **The compounding effect of coaching** — How does a coach's understanding deepen over 12 months? What do they know at month 12 that they didn't at month 1? How does accumulated understanding change guidance quality?

5. **Specific methodologies** — Kegan & Lahey's Immunity to Change, Adaptive Leadership (Heifetz), Positive Intelligence (Chamine), Marshall Goldsmith's feedforward, David Peterson (Google), McKinsey/Egon Zehnder/Spencer Stuart coaching practices. What's common across all of them?

6. **What can't be automated?** — What fundamentally requires human presence, empathy, and intuition? What parts are actually pattern recognition that an AI with continuous observation could do BETTER than a human coach who meets the executive for 1 hour every 2 weeks?

7. **The "insight acceptance" problem** — How do coaches get powerful, busy executives to accept uncomfortable truths about their behaviour? What's the psychological mechanism? How to replicate it in an AI interaction?

The synthesis question: What would a coaching AI look like that had 24/7 behavioural observation (something no human coach has) but lacked physical presence and emotional rapport (something every human coach has)? Where would it be BETTER than human coaching and where would it be WORSE?

---

## Prompt 8 — Communication Intelligence: Deep Signals from Email and Calendar

Beyond email triage (sorting into buckets), what DEEP intelligence can you extract from an executive's communication patterns? I'm looking for second-order signals that reveal relationship dynamics, decision quality, stress levels, and organisational health.

The system has access to:
- Full email content and metadata (Outlook via Microsoft Graph, read-only)
- Calendar events, meetings, attendees
- Response timing per sender
- Email length and frequency patterns
- Meeting outcomes (post-meeting task creation, follow-up patterns)

Research:
1. **Relationship health scoring** — Can you infer professional relationship health from communication patterns? Response time trends, email length trends, tone shifts, meeting frequency changes. Research on computational relationship analysis. Aral & Van Alstyne's work at MIT?

2. **Influence and power dynamics** — Linguistic markers of power (directness, hedging, question patterns). Can you map the executive's influence network from email? Who defers to whom? Enron corpus studies applied to single-user analysis?

3. **Meeting effectiveness** — From calendar metadata + email follow-up: can you score which meetings produce outcomes vs waste time? Pre/post meeting email patterns. Decision latency after meetings.

4. **Attention allocation analysis** — Who gets the executive's attention? Response priority patterns. Does this align with stated priorities? Can you detect attention-priority misalignment?

5. **Sentiment trajectory** — How is tone changing over time? With specific people? On specific topics? What linguistic markers indicate rising tension vs increasing trust?

6. **Communication load and capacity** — How many simultaneous threads before quality drops? Thread overload detection. When to suggest batching.

7. **Information flow analysis** — What reaches the executive? What doesn't? Information bottlenecks. Filter bubbles. Who is the executive NOT hearing from?

8. **Organisational stress detection** — Can you detect when the org is under stress from changes in the executive's communication patterns? Meeting density spikes, shorter emails, late-night activity, emergency calendar adds.

9. **Decision velocity** — How fast are decisions moving through this executive? Thread back-and-forth without resolution. Time from question to answer.

For each signal: what NLP/analysis technique extracts it, what accuracy is realistic, what privacy boundaries apply, and how would this intelligence help the executive?

---

## Prompt 9 — Voice-First AI: Making the Morning Session Feel Like a Chief of Staff

The primary interaction is a voice-first morning session: the executive talks for 90 seconds, the system delivers an intelligence briefing and generates their day plan. This needs to feel like a brilliant chief of staff, not a chatbot.

Research the state of the art:

1. **Conversational memory across sessions** — "Last Tuesday you mentioned worrying about the Q3 pipeline — how did Thursday's meeting go?" Research on AI systems that maintain conversational continuity across sessions. What makes this feel powerful vs creepy?

2. **Voice prosody analysis** — What can you detect from HOW someone speaks? Stress, confidence, fatigue, uncertainty. Apple's SFSpeechRecognizer capabilities for prosody. What's state of the art? Privacy-preserving approaches?

3. **The chief of staff interaction model** — What does a real chief-of-staff morning briefing look like? Structure, content, tone. How long? What gets said vs written? How to model this computationally? Military/intelligence briefing design?

4. **Adaptive conversation flow** — AI that adapts its questions based on what it knows. Not a fixed script. How to make a 90-second interaction feel like a genuine dialogue, not a survey?

5. **Delivering uncomfortable truths via voice** — "You've been avoiding this for 8 days" — how to frame this in voice so it lands as insight, not judgment? Research on feedback delivery via voice interfaces.

6. **Voice output design** — Making AI-generated speech feel authoritative and trustworthy to a C-suite executive. Voice selection, pacing, emphasis. Research on trust in synthetic speech. What makes someone take AI speech seriously?

7. **Optimal interaction length** — Is 90 seconds right? Research on voice interface design for time-pressured professionals. When is shorter better? When does the system need to request more time?

8. **The "one question" technique** — The morning session ends with: "What's the thing you most need to think about today that isn't on the list?" Research on single-question techniques for surfacing hidden priorities. Coaching question design.

---

## Prompt 10 — Proactive Intelligence: Systems That Anticipate, Not React

Most AI is reactive. I want a system that ANTICIPATES — it sees patterns developing and surfaces intelligence BEFORE the executive asks. This is the difference between a tool and a chief of staff.

Research:
1. **Anticipatory computing** — Systems that predict user needs before expression. Google Now's approach. What worked? What felt creepy vs helpful? Where's the line?

2. **Predictive scheduling** — "You have a board presentation Thursday. Based on your pattern, you'll start prep Tuesday evening and feel rushed. I'm blocking Monday 2-5pm." Research on predictive task scheduling from behavioural history.

3. **Deadline risk detection** — When is a deadline likely to be missed based on current progress trajectory? How to calculate? When to alert vs when to stay silent?

4. **Relationship maintenance alerts** — "You haven't spoken to [key stakeholder] in 3 weeks. Last time this gap happened, the relationship cooled for 2 months." Relationship cadence detection.

5. **Decision quality warnings** — "You're about to make a people decision at 4:30pm after back-to-back meetings. Your data shows these decisions get revised 60% more often." Time-of-day × cognitive load × decision type risk modelling.

6. **Strategic attention allocation** — "You've spent 85% of this week on operational issues. Your Q2 priority was product strategy. You've allocated 2 hours to it in 10 business days." Stated vs revealed priority tracking.

7. **False positive tolerance** — When does proactive become annoying? What's the right alert frequency? Research on notification fatigue in professional contexts. How to calibrate over time? How to learn what this specific executive cares about?

8. **The "pattern + evidence + suggestion" format** — Research on how to structure proactive alerts so they're actionable, not just informative. Pattern (what I noticed) + Evidence (the specific data) + Suggestion (what you might consider). Decision support research.

---

## Prompt 11 — Deep Work, Attention, and Executive Focus Protection

The most valuable thing Timed can do is protect the executive's deep work time — the periods where they do their most important cognitive work. Everything else is secondary.

Research:
1. **Flow state detection** — Can you detect flow IN PROGRESS from behavioural signals and protect it? No app switching, sustained focus, reduced email checking. What signals indicate flow? Research on computational flow detection.

2. **Attention residue (Sophie Leroy)** — When you switch tasks, attention stays on the previous task. How long? How to minimise? Scheduling implications. Can an AI system reduce attention residue through better task sequencing?

3. **Interruption cost** — Gloria Mark's research. Real recovery time after interruptions. Different types of interruptions — which are most costly? Can an AI system intelligently filter interruptions based on current cognitive state?

4. **Context-switching cost for executives** — Executives manage 15+ active threads. What's the cognitive cost of switching between them? Is there research specific to executive-level context switching?

5. **Optimal deep work scheduling** — How much deep work can a CEO realistically do per day? What's the research vs the ideology? Cal Newport's claims vs actual executive data.

6. **Notification management** — Which notifications need real-time delivery vs can be batched? Optimal batching intervals. "Do not disturb" effectiveness studies. How to build an intelligent notification filter?

7. **Strategic scheduling of shallow work** — Email, quick responses, admin — they need to happen. Optimal batching strategy. Research on "shallow work windows."

8. **Environmental factors on focus** — Digital environment (open tabs, incoming messages, visible task lists) impact on cognitive performance. Can the system detect environmental conditions that impair focus?
