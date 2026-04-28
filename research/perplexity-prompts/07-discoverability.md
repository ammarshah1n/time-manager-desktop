---
purpose: Find every feature that exists in code but is unfindable from the UI.
fire: Parallel with 1 / 2 / 4 (independent and cheap)
depends_on: nothing
---

# Prompt 7 — Discoverability & accessibility

## Prompt body (paste into Perplexity Deep Research)

Repo: ammarshah1n/time-manager-desktop @ `unified`. Ammar's directive: "make every feature accessible as much as possible". Audit GOAL: find every feature that exists in code but is unfindable from the UI.

Enumerate:

1. **All keyboard shortcuts** in TimedRootView, TriagePane, TasksPane, PlanPane, FocusPane, CapturePane, CalendarPane. For each: is it documented in-app? In a help menu? In an onboarding tip? Or only in source code comments? Produce a master shortcut sheet.

2. **Command palette / quick action**. Does one exist? If yes, what's in it? If no, should there be one (calm Apple-style, not Linear-loud)?

3. **Sidebar navigation completeness**. NavSection enum entries vs features that exist. Anything orphaned (in code, no nav entry)? Anything in nav but routes to a stub view?

4. **PrefsPane organisation**. 5 tabs visible by default (v1BetaMode flipped today). For each tab: are settings discoverable? Grouped sensibly? Do labels match user mental models or developer mental models? Is there a "Voice Resume" row that shows only when `pendingVoiceOnboarding=true` — what about other conditional rows?

5. **Empty states**. For every pane: when there's no data, does the empty state explain how to get data (e.g., "Sign in to Outlook to start receiving emails") or just show blank?

6. **Error messages**. Grep for every user-facing error string. Are they user-vocabulary ("We couldn't reach your email — check your internet") or developer-vocabulary ("MSAL_ERROR: token_refresh failed: -50019")?

7. **Onboarding seed**. After 10-step OnboardingFlow + voice onboarding, what features does Yasser KNOW exist? What features are silently waiting to be discovered? (e.g., does he know about DishMeUp? About Capture? About Focus timer? About InsightsPane?)

8. **iOS surface**. iOS app is now buildable from `unified`. What does the iOS UI expose vs hide? Is it a full peer to Mac or a companion (Capture + Orb only)? Is that intentional?

9. **System integrations Yasser will expect** (already in code or not):
   - Menu bar item (live? stub?)
   - Notifications (alerts wired today via AlertsPresenter — does the alert also raise a system notification?)
   - URL handler (`timed://` is registered, what URLs does it handle?)
   - Siri shortcuts / App Intents
   - Spotlight indexing of tasks

For each unfindable feature: severity + 1-line fix (add menu entry, add tooltip, add empty-state copy, add onboarding step, add help text).

Hard constraint: any new "discoverability surface" must be calm Apple aesthetic. No animated tooltips. No "💡 Did you know?" cards. No gamified onboarding.

Other constraints:
- No new architecture.
- Timed never acts on the world.
