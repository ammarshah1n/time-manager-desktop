---
purpose: Simulate Yasser's first 72 hours hour-by-hour and identify every cold-start / empty-state / broken moment.
fire: After prompts 1, 2, 4 produce findings (this synthesises them through a user lens)
depends_on: 1, 2, 4
---

# Prompt 3 — Yasser's first 72 hours: experience map

## Prompt body (paste into Perplexity Deep Research)

Repo: ammarshah1n/time-manager-desktop @ `unified`. Tonight's three deploys land successfully (voice proxies + Trigger.dev + Graphiti backfill). Tomorrow morning, Ammar hands `/Applications/Timed.app` to his father Yasser (CEO co-founder, executive, no patience for buggy UX, judges by intelligence + polish).

Audit GOAL: simulate Yasser's first 72 hours hour-by-hour and identify every moment where the experience breaks, feels empty, or fails to demonstrate the "compounding intelligence" narrative.

Map these checkpoints:
- T+0:00 install DMG (ad-hoc signed, requires `xattr -cr` — does the install_app.sh / install messaging hold his hand through this?)
- T+0:05 first launch, intro, login screen — email/password vs Microsoft
- T+0:10 onboarding — what does Timed know about him? What's empty?
- T+0:15 voice onboarding — is the orb's first conversation impressive or hollow?
- T+0:30 first attempt to use TodayPane — what does empty state show? Tier 0 has zero rows. ACB is empty. Does the app degrade gracefully?
- T+1:00 Yasser tries to triage his Outlook inbox — does delta sync deliver? How fast? What if his inbox is 50,000 emails (he's a CEO)?
- T+2:00 first DishMeUp — without any historical pattern data, what does the planning engine return? Composite scoring with no priors?
- T+24:00 first nightly engine run — but Tier 1 needs T0 observations to summarise and there's been one day of data. What does the 5:30 AM briefing look like for Yasser on Day 2?
- T+72:00 by Day 3, what should the orb ACTUALLY know about Yasser? What's the minimum bar to feel "compounding"?

For each checkpoint:
- Best case (everything works) — what does Yasser see/hear?
- Worst case (something fails) — what does he see/hear?
- Confused case (ambiguous empty state) — what does he see/hear?
- Cold-start gap (no historical data) — does the feature explain itself or just look broken?

Then produce a **cold-start handling punch list**: every place where Day 1 / Day 2 / Day 3 will look empty or broken because the engine hasn't had time to compound yet, and the minimum copy/empty-state/seed-data fix to make it feel intentional. No new architecture — just better empty states + onboarding seed.

Specifically map:
- What's in Tier 1 / Tier 2 / Tier 3 on Day 1, Day 2, Day 3?
- What's in ACB on Day 1?
- Does MorningBriefingPane have anything to render on Day 1?
- Does InsightsPane have anything to show on Day 1?
- Does the orb know anything about Yasser on first conversation?

Constraints:
- No new architecture.
- Timed never acts on the world.
- Yasser is co-founder, not a modeled subject — no name-keyed corpora.
