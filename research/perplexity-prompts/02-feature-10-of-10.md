---
purpose: Walk every UI surface and answer "would Yasser use this for a week without my support and feel impressed, not embarrassed?"
fire: Parallel with prompts 1 / 4 / 7
depends_on: nothing
---

# Prompt 2 — Feature-by-feature 10/10 quality bar

## Prompt body (paste into Perplexity Deep Research)

Repo: ammarshah1n/time-manager-desktop @ `unified`. Audit GOAL: walk every user-facing surface and answer "would Yasser (CEO co-founder) use this for a week without my support and feel impressed, not embarrassed?"

Surfaces to audit (one section per surface):

1. LoginView (email/password + Microsoft, shipped today)
2. OnboardingFlow (10-step + voice narration)
3. VoiceOnboardingView ("Set up later" path + Resume row)
4. TimedRootView nav + sidebar (NavSection enum)
5. TodayPane
6. TriagePane (keyboard-driven, undo stack, 620 LOC)
7. TasksPane (per-bucket, bulk ops, 546 LOC)
8. PlanPane (634 LOC — flagged duplicates DishMeUp logic, audit this)
9. DishMeUpSheet ("I have X minutes", 555 LOC)
10. FocusPane (Pomodoro, 505 LOC)
11. CalendarPane (weekly grid, drag-create, Outlook sync)
12. CapturePane (voice/text quick capture, 530 LOC)
13. ConversationView / ConversationOrbSheet (iOS orb shipped today)
14. MorningBriefingPane (now reachable via sidebar)
15. WaitingForPane
16. InsightsPane
17. PrefsPane (5 tabs, including VoiceTab "Resume" row)
18. AlertDeliveryView (top-trailing overlay)

For each surface, produce:

- **What works** (3 bullets max)
- **What's stubbed / fake / placeholder** (with file:line)
- **Edge cases that break it** (empty state, no-data state, network failure, MSAL token expiry, Supabase 500, ElevenLabs rate limit)
- **Polish gap** (motion, copy, hierarchy, density, calm-vs-loud per Apple Calendar/Reminders/Settings aesthetic — see `.claude/skills/timed-design`)
- **One concrete fix** (no new architecture, file:line + 1-paragraph diff sketch)
- **10/10 verdict**: LIVE / SHIPPABLE-AFTER-FIX / NOT-READY

End with a **prioritised punch list** of all SHIPPABLE-AFTER-FIX items ordered by user-impact / effort ratio.

Aesthetic invariants (do NOT relax):
- Apple Calendar / Reminders / Settings calm. Not Linear. Not Notion.
- 28pt headline / body scale on session panes. 72pt only for IntroView.
- Onboarding/setup/capture flows START from voice orb. Forms only when voice can't capture (OAuth redirect, file upload).

Anti-patterns to flag (these are paid-for mistakes — call them out by file:line if found):
- DataStore treated as source of truth instead of Supabase.
- Productivity-app framing ("task list", "todo manager") instead of cognitive-OS framing.
- Cheaper models proposed for the core intelligence engine.
- Timed acting on the world (sending mail, booking, replying).
- Yasser-keyed personal corpora (Yasser is co-founder, peer user).
