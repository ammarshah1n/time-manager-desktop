# Research Pack 04 — Signals, Privacy, and Product Design

> Give all 5 prompts to Perplexity Deep Research, one at a time. Save each result. Bring them all back.

---

## Prompt 12 — Every Observable Signal on macOS + Outlook and What It Reveals

I'm building a macOS-only executive intelligence system that currently observes calendar and email via Microsoft Graph. I need to exhaustively map every ADDITIONAL signal source available on macOS and what intelligence each enables.

The system must observe passively — it never acts, never modifies, never sends. It only watches and learns.

For each signal source, give me:
1. Technical feasibility on macOS (API, permissions, sandbox restrictions)
2. Signal quality (noise ratio, usefulness for personal modelling)
3. Privacy sensitivity (low/medium/high/critical)
4. What higher-order intelligence it enables
5. Whether any existing product uses this signal

**Signal sources to research:**
1. **App focus duration** — NSWorkspace notifications, Accessibility API. Time per app, switch frequency. Reveals: deep work ratio, context-switching patterns, task fragmentation.
2. **Typing patterns** — Keystroke dynamics as cognitive load proxy. Words per minute variation, error rate, pause patterns. What APIs exist on macOS? Accessibility permissions?
3. **Calendar metadata beyond events** — Cancellation patterns, rescheduling frequency, acceptance rate, meeting creation patterns, recurring vs one-off trends.
4. **File system activity** — NSFilePresenter, FSEvents. Active documents, time per file, version save frequency. Reveals: what's being actively worked on, presentation prep patterns.
5. **Screen time** — ScreenTime framework on macOS. App usage aggregates without individual keystroke tracking.
6. **Microsoft Teams/Slack signals** — If the executive uses Teams: status changes, message frequency, channel activity. Via Graph API extensions?
7. **Physical signals via Apple Watch** — HealthKit: HRV as stress proxy, sleep data, activity levels, stand/sit. Research on HRV as cognitive performance predictor. What accuracy?
8. **Location context** — WiFi network (office vs home vs travel), timezone changes. Reveals: work location patterns, travel frequency.
9. **Notification interaction** — UNUserNotificationCenter. Which notifications opened, dismissed, ignored. Reveals: priority signals.
10. **Clipboard patterns** — What's being copied between apps (aggregate, not content). Reveals: information flow patterns.
11. **Browser activity** — Safari extension or proxy. Domains visited (not content), time per domain. Privacy-preserving aggregate.
12. **Absence signals** — What the executive is NOT doing that they usually do. Missed routines, skipped regular meetings, email gaps.

For each: technical implementation, privacy boundary (what's ethical vs surveillance), and the intelligence it would produce when combined with existing email + calendar data.

---

## Prompt 13 — Privacy-Preserving Deep Personal Modelling for Executives

I'm building a system that creates an intimate cognitive model of a C-suite executive — their decision patterns, blind spots, emotional triggers, avoidance behaviours, relationship dynamics. This is extremely sensitive data.

The executive must TRUST this system completely. Without trust, they won't let it observe them deeply enough to build real intelligence. Trust is the product's prerequisite.

Research every dimension:

1. **On-device vs cloud processing** — What can run locally on an M-series Mac (M1-M4)? Can you run reflection loops with local models (Llama 3, Mistral, Phi-3)? Performance gap vs cloud Opus? Apple Intelligence's approach?

2. **Data sovereignty** — Can the personal model live entirely on-device with only anonymised queries to cloud APIs? Architectures where the raw personal data never leaves the machine?

3. **Executive-specific legal concerns** — C-suite communications contain material non-public information (MNPI), M&A discussions, personnel decisions, board matters. What are the SEC/legal implications of AI processing this data? GDPR? What compliance frameworks apply?

4. **Transparent model inspection** — "Here's what I think I know about you." Research on explainable personal models. Can you let the executive SEE their model and correct it? How does this build trust?

5. **Breach risk and threat modelling** — What if the personal model is compromised? Someone gets access to an executive's cognitive patterns, decision weaknesses, relationship dynamics. How to architect for containment? Encryption at rest, per-user keys, zero-knowledge architectures?

6. **Trust-building UX patterns** — How do enterprise AI products (Microsoft Copilot, Glean) handle trust? What commitments matter? "Your data is never used to train models" — what other assurances do executives need?

7. **Selective sharing** — In the future, the executive might share some intelligence with their PA or team. Permission models, granular access control for personal intelligence.

8. **The trust spectrum** — What level of observation do executives accept at different trust levels? Day 1 (just calendar and email) vs month 6 (full behavioural observation). Gradual permission escalation?

---

## Prompt 14 — Strategic Thinking Augmentation: Beyond Daily Planning

Timed currently helps with daily planning. But the real value of a compounding intelligence system should extend to STRATEGY — helping an executive think better about long-term decisions.

Research:
1. **Decision quality tracking over time** — Can you build a system that records major decisions and their outcomes, then retrospectively analyses decision quality? Decision journals. What does the research say? Kahneman's "decision hygiene"?

2. **Pre-mortem and personalised red-teaming** — Gary Klein's pre-mortem method. Can an AI that knows the executive's SPECIFIC blind spots provide personalised red-teaming? "Given your tendency toward optimism about timelines, here are the risks you're probably underweighting."

3. **Strategic vs operational time allocation** — Beyond the Eisenhower matrix. What ratios predict long-term executive success? What do the best CEOs allocate differently? Research on executive time allocation.

4. **Pattern recognition at the strategic level** — "You've made 3 decisions this quarter following the same pattern: choosing safe over ambitious when evidence supported ambitious." Meta-cognitive pattern detection in decision-making.

5. **Scenario planning assistance** — AI-augmented scenario planning. Can a system that deeply knows the executive's mental models help them see scenarios they'd miss?

6. **Accountability and follow-through** — Research on why executives announce priorities then don't follow through. The gap between stated and revealed priorities. AI as accountability mechanism.

7. **Competitive and market intelligence integration** — How to combine personal cognitive model with external market data for more informed decisions?

8. **Executive development tracking** — Is the executive growing? New skills, perspectives, stagnation areas. Can you track development from behavioural signals?

---

## Prompt 15 — Behaviour Change Science for High-Performing Executives

An AI system can generate insights — but how do you get a busy, successful executive to actually CHANGE based on those insights? This is the hardest product problem.

Research:
1. **Why executives resist change** — Success trap, identity threat, time poverty. What's the psychology of behaviour change for people who are already at the top?

2. **Nudge theory for high-agency individuals** — Thaler & Sunstein applied to executives. Choice architecture for time management. What nudges work for people who resist being managed?

3. **Self-determination theory (SDT)** — Autonomy, competence, relatedness. Executives are high-autonomy individuals. How to frame AI guidance so it ENHANCES autonomy rather than threatening it?

4. **Implementation intentions (Gollwitzer)** — If-then planning. Can an AI create implementation intentions on behalf of the user? Research on AI-generated vs self-generated intentions.

5. **Feedback timing and format** — When is feedback most effective? Immediate vs delayed? Quantified vs qualitative? Comparative ("40% more email time than last month") vs absolute?

6. **Gamification for executives** — Does it work? Is it patronising? Streaks, scores, progress indicators in professional contexts with high-status individuals?

7. **The coaching paradox** — People who most need change resist it most. How do coaches handle this? How could AI?

8. **Sustained engagement without novelty** — Most AI tools see usage drop after 2 weeks. How to maintain daily engagement over months? The research says compounding intelligence is the answer — but is there more to it?

---

## Prompt 16 — The $500+/Month Executive Product: Pricing, Positioning, and Category Creation

Research Pack 01 established a value architecture (operational → intelligence → compounding strategic). Now I need to understand how to build a product that commands premium pricing and creates a category.

Research:
1. **Ultra-premium SaaS pricing** — Products that charge $200-$1000+/month for individual licenses. What do they have in common? How do they justify the price? Examples: Bloomberg Terminal (individual seat cost), Palantir, enterprise AI tools priced per user.

2. **Category creation** — How to create a new product category rather than competing in an existing one. What does "executive intelligence operating system" as a category look like? How to position against "productivity apps" without being compared to them?

3. **Executive software buying behaviour** — How do C-suite executives discover, evaluate, and adopt personal software? Who influences the decision? What's the trial period expectation? Direct sales vs self-serve?

4. **Concierge onboarding** — For a $500/month tool targeting CEOs: what does the onboarding experience look like? White-glove setup? Calendar analysis walkthrough? Is human-assisted onboarding required?

5. **Network effects and word-of-mouth** — Executive peer networks (YPO, Vistage, WPO). How products spread through executive communities. What creates "you HAVE to try this" conversations?

6. **Retention mechanics at premium pricing** — What keeps someone paying $500/month after the novelty wears off? The compounding intelligence model (more data = more value) as a retention mechanism. Lock-in through accumulated intelligence.

7. **The "chief of staff replacement" value frame** — A chief of staff costs $150K-$250K/year. If Timed provides 30% of a chief of staff's observational intelligence, that's $45K-$75K of value for $6K/year. Is this the right value frame?

8. **Distribution for macOS-only premium tools** — Direct DMG vs App Store? Sparkle updates? Enterprise distribution? How do premium macOS tools (Raycast, CleanShot, Things) distribute? What's different at $500/month vs $50/year?
