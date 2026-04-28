---
created: 2026-04-28
purpose: Pre-Yasser-ship audit. 8 Deep Research prompts to get every feature to 10/10 without inventing new architecture.
runner: Perplexity Deep Research with GitHub connector pointed at `time-manager-desktop @ unified`
---

# Pre-ship audit prompts (2026-04-28)

These 8 prompts close the gap between "beta-readiness sprint shipped" (commits `bcee82b` + `ec3a7fd`) and "Timed.app on Yasser's MacBook for a week without my support".

## Setup before firing

- Perplexity → enable GitHub connector → repo `ammarshah1n/time-manager-desktop`, branch **`unified`**
- Mode: **Deep Research** (not Pro Search — Deep does the multi-source synthesis we want)
- Push the latest `unified` commit to origin BEFORE firing so Perplexity sees the latest state
- Each prompt asks for `file:line` citations — if the response is vague, re-run with `cite EVERY claim with file:line — no claim without a citation` appended

## Hard rules baked into every prompt

- **No new architecture.** Build on what exists. Identify gaps, don't invent layers.
- **Timed observes / reflects / recommends.** Never acts. Reject any suggestion involving sending mail, booking, replying, or contacting anyone.
- **Yasser is co-founder, not a modeled subject.** Reject any suggestion that builds Yasser-keyed personal corpora.
- Every finding gets `severity` (P0/P1/P2), `file:line`, `effort` (15min / 1h / half-day / day), `dependency` (what it blocks).

## Firing order

| # | File | When | Why |
|---|------|------|-----|
| 1 | `01-backend-frontend-wiring.md` | After tonight's 3 deploys land | Blocks everything else; if integration is broken nothing else matters |
| 2 | `02-feature-10-of-10.md` | Parallel with 1 | Independent |
| 4 | `04-reliability-failure-modes.md` | Parallel with 1 | Independent |
| 7 | `07-discoverability.md` | Parallel with 1 | Independent and cheap |
| 5 | `05-voice-orb-deep-dive.md` | After 1 confirms tools dispatch live | Tool dispatch findings inform this |
| 6 | `06-intelligence-quality.md` | After 24h of real data through Tier 0 | Need T0 rows to evaluate cold-start handling |
| 3 | `03-yasser-72-hours.md` | After 1, 2, 4 produce findings | Synthesises the prior |
| 8 | `08-go-no-go-synthesis.md` | LAST | Synthesises 1–7 into the binary ship list |

You can fire **1 + 2 + 4 + 7** in parallel right now (independent, no new data needed). The others chain after.

## Background Perplexity should NOT re-research

This morning already ran 3 audits (architecture, UX walkthrough, premium polish). The Beta-Ready Execution Plan integrated 8 of 6+15 items. Tonight: 3 onsite deploys (voice proxies, Trigger.dev, Graphiti backfill) — treat as "will be live in 30 min".
