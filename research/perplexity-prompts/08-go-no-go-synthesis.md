---
purpose: Synthesise prompts 1-7 into the binary go/no-go ship list.
fire: LAST — after 1-7 produce findings
depends_on: 1, 2, 3, 4, 5, 6, 7
---

# Prompt 8 — Pre-ship go/no-go checklist (the synthesis)

## Prompt body (paste into Perplexity Deep Research)

Repo: ammarshah1n/time-manager-desktop @ `unified`. This prompt RUNS LAST — after prompts 1-7 have produced findings.

Audit GOAL: produce the binary go/no-go checklist for "install on Yasser's MacBook tomorrow, let him use it for 7 days unsupervised."

Synthesise across the prior 7 audits + the existing repo state:
- `HANDOFF.md` "Held for tonight" section (3 deploys)
- `BUILD_STATE.md` status summary
- `docs/UNIFIED-BRANCH.md`
- `SESSION_LOG.md` last 5 entries
- Open commits + uncommitted changes
- TickTick "Timed" project task list

Produce a single ranked checklist:

| # | Item | Source (which prior audit raised it) | Severity (P0/P1/P2) | Effort (15min/1h/half-day/day) | Dependency (what blocks this, what does this block) | Owner (Ammar / agent / external) |

Rules:
- **P0** = blocks ship. Yasser will hit this in first 24h.
- **P1** = ship is risky. Yasser will hit this in first 7 days.
- **P2** = polish. Can land after Yasser starts using.
- No item is "build new architecture". All items are file:line fixes or ops actions on existing infra.
- If an item is already on a TickTick task or in HANDOFF.md, link it.
- If an item is contradicted by Timed's invariants (Timed never acts, Yasser is not a modeled subject, no productivity-app framing, server-side keys only), reject it.

Then produce three tables:

**TABLE A — P0s in dependency order**: do these in sequence, starting tonight after the 3 onsite deploys land.

**TABLE B — P1s grouped by area** (Voice, Auth, Engine, UI Polish, Reliability, Discoverability): so Ammar can pick a session theme.

**TABLE C — What we explicitly won't fix before Yasser** + the 1-line excuse he gets when he hits it. (Setting expectations is ship-quality.)

End with: **the single sentence Ammar will type into TickTick at the end of the ship-prep session that says "we're done, hand the DMG to Yasser"**.

Constraints:
- No new architecture.
- Timed never acts on the world.
- Yasser is co-founder, not a modeled subject — no name-keyed corpora.
