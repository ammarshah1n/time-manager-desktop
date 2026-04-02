# Thread 2: MorningInterviewPane — State Machine & Conversational UX
**Repo:** `ammarshah1n/time-manager-desktop` · Branch: `ui/apple-v1-restore`
**File:** `Sources/Features/MorningInterview/MorningInterviewPane.swift`

***

## Executive Summary

The current `MorningInterviewPane` implements a **linear, 4-step wizard** with a decent voice overlay but has fundamental gaps in conversational robustness. The state machine is missing interruption handling, correction intent, continuity from the previous day, adaptive step suppression, and emotional context. Benchmarked against Alexa Dialog Management, Dialogflow CX, Voiceflow, Sunsama, and Reclaim.ai, the most critical gap for a single executive user is the absence of a **correction/barge-in pathway** and a **yesterday-continuity step** — both of which would break the "coffee shop" hands-free fantasy if missing. Below are six areas of analysis with specific file changes, line estimates, and an impact ranking.

***

## 1. State Machine Design

### Current State Inventory

The `ConversationState` enum has five cases:

```swift
case idle
case appSpeaking(step: Int)
case waitingToListen
case listening(step: Int)
case processing
```

This is adequate for a happy path but collapses under real-world conversational stress. The step is a plain `Int` that only increments (`step += 1`) with a single hard back-branch (`step = 1` on plan rejection). There are no parallel context states, no rollback snapshots, and no disambiguation channel.

### Benchmark: What Best-In-Class Looks Like

Alexa's Dialog Management state machine has three canonical states — `STARTED`, `IN_PROGRESS`, and `COMPLETED` — but critically, **every transition is hookable**. Developers can intercept at any point and inject custom logic: override prompts, set defaults, or reconfirm slots. The architecture principle is that the state machine _guides_ rather than _forces_ progression.[^1]

Dialogflow CX models conversations as finite state machines where **Pages = states** and **state handlers = transition routes**. The best-practice maxim is to end every response with a question to guide the user, and to use event handlers for interruptions and escalations. Route conditions can branch non-linearly based on parameters set earlier in the session.[^2][^3]

Voiceflow's Cooperative Principle mandates that conversations **never re-ask for information the user has already provided implicitly** — using "slot requirements" that are pre-satisfied by over-answers. If a user says "I have about 4 hours and I want to skip the email review," both the time slot and the skip intent are captured in a single utterance and the state machine should not ask again.[^4]

The production voice AI pattern from industry practitioners is to decompose into **sandboxed states** — each state only loads the tool calls and intents relevant to it, preventing context bleed between steps.[^5]

### Missing States — Required Additions

| New State | Purpose | Trigger |
|-----------|---------|---------|
| `.correcting(step: Int, field: CorrectionTarget)` | User says "actually, move that to afternoon" mid-flow | `VoiceResponse.correction` matched in any step |
| `.interrupted(resumeState: ConversationState)` | User speaks while app is speaking (barge-in) | ASR detects speech during `.appSpeaking` |
| `.ambiguous(step: Int, prompt: String)` | System cannot resolve a response; asks one clarifying sub-question | Low-confidence parse from `VoiceResponseParser` |
| `.contextSwitching(from: Int, to: Int)` | User jumps a step ("skip estimates, just lock the plan") | Explicit skip intent detected |
| `.deferralReview` | Continuity review of yesterday's deferred tasks | Pre-check before step 0 |
| `.moodCheck` | Optional emotional context capture | Before or after step 0 depending on config |

**File changes:** `MorningInterviewPane.swift` — extend `ConversationState` enum (+6 cases, ~12 lines), add `handleInterruption()` function (~25 lines), extend `handleVoiceResponse()` switch to route correction and skip intents (~30 lines). Add `VoiceResponse.correction(field:newValue:)` and `VoiceResponse.skip` cases to `VoiceResponseParser` (~20 lines).

### Interruption & Correction Handling

The current architecture has a critical gap: when the app is speaking (`.appSpeaking`), the microphone is off — there is no barge-in pathway. Research shows transformer-based end-of-turn detection models can reduce unintentional interruptions by 85% compared to simple Voice Activity Detection, but any barge-in support requires the audio stack to be **full-duplex** — listening while speaking. The ASR should fire a hardware-level halt signal to TTS the moment speech is detected.[^6][^5]

For **corrections** ("actually, move that to afternoon"), the state machine needs a correction intent that can fire from _any_ listening state. The recommended pattern from voice AI literature is to save a **state snapshot** at every meaningful turn boundary — akin to database savepoints — so a soft rollback returns to the last confirmed state, keeping already-resolved slots. In Swift terms: store `var stateHistory: [ConversationState] = []`, push on every `advanceStep()`, and pop on correction.[^6]

```swift
// New CorrectionTarget enum
enum CorrectionTarget {
    case timeAvailable
    case taskInclusion(taskId: UUID)
    case timeEstimate(taskId: UUID, newMinutes: Int)
    case deferToAfternoon(taskId: UUID)
}
```

***

## 2. Conversation Flow Optimisation

### The Abandonment Problem

Survey and conversational UX research consistently shows abandonment grows exponentially once session **perceived length** exceeds expectation. The critical finding is that **cognitive complexity per question matters more than question count** — a 5-question session of simple yes/no confirmations out-completes a 3-question session with complex disambiguation. Voice interactions are even more sensitive: a voice agent should keep messages as short as possible to prevent user frustration during TTS playback.[^7][^8]

At 4 steps the current flow is at the edge of the safe zone. Sunsama's daily planning flow is designed to be entered and re-entered multiple times, and recommends targeting a planned workload significantly lower than available hours until the user builds estimation confidence. Reclaim.ai takes the most aggressive approach: it skips a morning interview entirely and uses AI priority scheduling automatically, requiring no user input to generate a day plan.[^9][^10]

### Confirm-the-AI-Plan vs. Build-from-Scratch

The "confirm AI plan" model is empirically superior for power users and is what Reclaim.ai implements. The current step 3 already moves in this direction ("Here's your plan. Ready to start?") but steps 1 and 2 are still in build-from-scratch mode. The **optimal flow for a single executive user** is:[^9]

1. **Step 0 — Continuity (new):** "Yesterday you deferred 3 tasks — should I carry them over?"
2. **Step 1 — Time:** "You have 4.5 hours clear. Keep that?" (confirm AI's calendar read, not set from scratch)
3. **Step 2 — Plan confirmation:** Show the AI's full proposed plan; user says yes, removes items, or makes corrections.
4. **Step 3 — Estimates override (conditional):** Only if any uncertain tasks exist (`.isUncertain == true`), otherwise skip.

This collapses 4 steps to 3 (or 2 on clean days) and reframes every question as a **confirmation of AI work** rather than a data-entry form. The voice scripts in `speakForStep()` already start with confirmation framing ("I found X items...") but the slider-based time declaration in step 0 is still build-from-scratch.

**File changes:** Refactor `stepTimeDeclaration` to show calendar-derived time as primary with override as secondary (~15 lines). Reorder steps in `body` ZStack to inject deferral step at index 0 when `hasDeferrals == true`. Update `totalSteps` to be computed, not constant (~5 lines).

***

## 3. Adaptive Question Ordering

### Should the Interview Learn Which Questions to Skip?

Yes — with a threshold-based approach. Research on Ecological Momentary Assessment (EMA) adaptive question skipping found that an **information-gain model** that skips questions unlikely to provide new information reduces imputation error by 15-52% compared to random skipping. The optimal configuration in that research achieved 12.5% question omission at 87.6% prediction accuracy with a threshold of 0.2.[^11]

For a single-user app, a simpler skip-count threshold is more appropriate and more explainable than a multi-armed bandit:

- If the user accepts step 2 (estimates) without any overrides for N consecutive sessions (recommend N = 5), suppress step 2 by default and add a "Review estimates" option in the footer.
- If the user's "available time" answer matches the calendar-derived suggestion within 15% for N sessions, auto-confirm step 0 and announce it: "Assuming your usual 4 hours today."

### Multi-Armed Bandit: When To Use It

Multi-armed bandits (e.g., Thompson Sampling) are optimal for **population-level personalization** where rewards are observable and arms represent meaningfully different experiences. For a single-user app, the "population" is one person and exploration is wasteful — you are not balancing exploration vs. exploitation across users, you are building a profile. Dynamic Question Ordering (DQO) that selects the next question to most reduce prediction uncertainty is closer to the right model, but the simplest correct implementation is:[^12][^13]

```swift
// SkipProfile persisted to AppStorage
struct QuestionSkipProfile: Codable {
    var step2ConsecutiveNoOverrides: Int = 0
    var step0MatchesCalendar: Int = 0
    // threshold: suppress after 5 consecutive unmodified passes
    var suppressStep2: Bool { step2ConsecutiveNoOverrides >= 5 }
    var autoConfirmTime: Bool { step0MatchesCalendar >= 5 }
}
```

**File changes:** New `QuestionSkipProfile` model (~20 lines). Update `applyPlan()` to record whether estimates were overridden (~10 lines). Update `body` ZStack step rendering to check `skipProfile.suppressStep2` (~5 lines). Add "Always show estimates" toggle in preferences (~8 lines). **~43 lines total.**

***

## 4. Multi-Modal Fallback: Voice ↔ Touch Switching

### Current State

Voice mode is an all-or-nothing toggle stored in `@AppStorage`. Switching mid-session (`onChange(of: voiceMode)`) stops all voice activity and resets `conversationState` to `.idle`, which means the user loses their voice-session context and must restart manually. There is no graceful handoff.

### Best Practice: Seamless Modality Switching

The industry benchmark is Apple's model — start with voice, switch to touch, receive visual feedback that mirrors the voice state. Google Home's pattern allows voice commands to initiate actions that the user then completes via touch without interrupting flow. The key principle: **state must survive a modality switch**.[^14][^15]

The fix requires separating `voiceMode` (the input channel preference) from `conversationState` (the logical position in the interview). The current implementation conflates them — disabling voice mode resets the state machine, which it should not.

```swift
// CURRENT (broken mid-session switch):
.onChange(of: voiceMode) { _, isOn in
    if !isOn {
        conversationState = .idle  // ← loses position
    }
}

// PROPOSED (state-preserving switch):
.onChange(of: voiceMode) { _, isOn in
    if !isOn {
        speechService.stop()
        stopListening()
        cancelSilenceTimer()
        // Do NOT reset conversationState — the step and confirmedIds survive
        // Touch UI renders current step natively; user picks up where voice left off
    }
}
```

The touch fallback already exists in every step as the button-based wizard — the gap is purely in the state transition logic. Additionally, a **noise-detection hint** should auto-suggest switching: if `VoiceCaptureService.audioLevel < threshold` for 10 seconds in a listening state, surface a banner: "Microphone signal weak — switch to touch?"

**File changes:** `MorningInterviewPane.swift` — fix `onChange(of: voiceMode)` handler (~3 lines removed, 5 added). Add noise-detection banner in `voiceStatusBar` (~20 lines). Add `VoiceCaptureService.audioLevel` observable property if not already present (~10 lines in `VoiceCaptureService.swift`). **~35 lines.**

***

## 5. Memory & Continuity: Yesterday's Plan

### Benchmark Analysis

Neither Todoist nor Things 3 provides proactive cross-day continuity narration. Things 3 surfaces unfinished yesterday tasks in the Today view automatically, and Todoist has a bulk "Reschedule overdue tasks" button, but neither app _speaks to the user_ about what was deferred. Sunsama supports re-entering the planning flow multiple times in a day but does not reference yesterday's deferrals narratively. This is an unoccupied design space for Timed.[^10][^16][^17]

### Proposed Continuity Step

Before step 0, a new `.deferralReview` step triggers only when `previousDayDeferrals.count > 0`. The voice script:

> "Yesterday, you deferred [N] tasks: [title1, title2]. Want to add those back today?"

This maps directly to the Transcript D4 design goal ("you could spend 10 minutes answering questions, then it creates your day plan while you make your coffee"). The executive user case is exact: overnight deferrals are the single highest-ROI continuity signal.

**Required data model changes:**

```swift
// New model — persisted via UserDefaults / @AppStorage JSON
struct DayPlanRecord: Codable {
    let date: Date
    let deferredTaskIds: [UUID]   // tasks confirmed in plan but not completed by EOD
    let completedTaskIds: [UUID]
}
```

`applyPlan()` currently only writes estimate overrides back. It needs to be called at session end _and_ at day end (via a `NotificationCenter` post from the main app's day-close flow) to record which confirmed tasks were not completed. The morning interview then reads `DayPlanRecord` for `yesterday`.

**File changes:** New `DayPlanRecord` model file (~25 lines). Extend `applyPlan()` to save a `DayPlanRecord` with the confirmed task IDs (~15 lines). New `stepDeferralReview` view (~50 lines, modelled on `stepDueTodayReview`). New `.deferralReview` ConversationState case. Add `handleDeferralResponse()` handler (~15 lines). Update `speakForStep()` to include deferral script (~10 lines). **~115 lines total.**

***

## 6. Emotional Intelligence: Mood Check Integration

### Research on Mood & Adherence

Self-monitoring of mood in app contexts increases treatment effectiveness by 20-30%. After 10 app sessions with mood-integrated activities, users are 82% more likely to report no anxious emotions and 28% more likely to report no depressive emotions. Arizona State University research found that tracking emotional state creates a momentum effect — users who felt positive today are more likely to feel positive tomorrow. The practical implication for a planning app is that a user reporting low energy should receive a lighter plan with fewer high-focus tasks, while a high-energy signal should allow scheduling demanding creative work in the first block.[^18][^19][^20]

### Implementation: Optional, Not Gating

The mood check should be **optional** (user-configurable in prefs) and **extremely fast** — a single 3-point scale, not a clinical instrument. Voiceflow's cooperative principle warns against asking for information already implicitly given, so the mood question should be skipped if the user's calendar already signals a disrupted day (travel detected, heavy meetings).[^4]

The state machine integration: mood is a **modifier on the existing plan output**, not a gating step. After the deferral review or time declaration, a quick mood capture adjusts the task ordering before step 2.

```swift
// MoodLevel enum
enum MoodLevel: Int, Codable {
    case low = 1, moderate = 2, high = 3
}

// In MorningInterviewPane
@State private var moodLevel: MoodLevel = .moderate

// Plan ordering modifier in confirmedTasks computed property:
// If moodLevel == .low, deprioritize tasks tagged .deepWork or .creative
// Surface admin/routine tasks first
```

The voice script for the mood question: "Quick check — how's your energy today? High, medium, or low?" — capped at one breath, one answer.

**File changes:** New `MoodLevel` enum (~8 lines). `@State private var moodLevel` property (~1 line). `stepMoodCheck` view with 3-button row (~30 lines). Modify `confirmedTasks` sort to apply mood weighting (~15 lines). `handleMoodResponse()` handler (~10 lines). Add `prefs.morningInterview.moodCheckEnabled` `@AppStorage` flag (~1 line). **~65 lines total.**

***

## Consolidated Impact Ranking & Change Estimates

| # | Change | File(s) | Est. Lines | Single-Executive Impact |
|---|--------|---------|-----------|------------------------|
| 1 | Correction/barge-in state + `VoiceResponse.correction` | `MorningInterviewPane.swift`, `VoiceResponseParser` | ~87 | 🔴 Critical — breaks hands-free flow when missing |
| 2 | Yesterday continuity step + `DayPlanRecord` persistence | New model file + pane | ~115 | 🔴 High — executive's core pain point is deferred tasks |
| 3 | Adaptive step suppression (skip-count threshold) | `MorningInterviewPane.swift`, new `QuestionSkipProfile` | ~43 | 🟠 High — reduces friction for daily power user |
| 4 | Fix mid-session voice↔touch handoff | `MorningInterviewPane.swift` | ~35 | 🟠 High — voice failure is common in real environments |
| 5 | Mood check (optional, 3-point) + plan reordering | `MorningInterviewPane.swift` | ~65 | 🟡 Medium — improves adherence but risky if mandatory |
| 6 | Confirm-AI-plan refactor (step 0 as calendar confirm) | `MorningInterviewPane.swift` | ~20 | 🟡 Medium — reduces cognitive load, quick win |
| 7 | Full-duplex barge-in (hardware halt signal during TTS) | `VoiceCaptureService.swift`, `SpeechService.swift` | ~60 | 🟢 Lower — requires audio architecture investment |

***

## Specific Function-Level Changes

### `speakForStep()` — Add deferral & mood scripts
Add `case -1` (deferral review) and `case -2` (mood) before the existing `case 0`, adjusting step indexing to be offset-aware if deferral/mood steps are injected.

### `handleVoiceResponse()` — Route correction intent
Add a `.correcting` branch at the top of the switch that fires before step-specific handlers, resolves `CorrectionTarget`, applies the change, and sets `conversationState = .appSpeaking(step: step)` to re-read the updated state to the user.

### `applyPlan()` — Extend to record continuity
After writing estimate overrides, save a `DayPlanRecord` with all `confirmedIds` as the "planned today" set. A `DayPlanRecord.deferredTaskIds` is computed at EOD by comparing planned set against `task.isCompleted`.

### `handleSilenceTimeout()` — Add modality switch suggestion
After the first timeout (`silenceTimeoutCount == 0`), check `voiceCapture.audioLevel` — if signal is below threshold, append "or tap to switch to button mode" to the "Still there?" prompt and show the touch fallback banner.

### `finishListening()` — Add ambiguity branch
After `VoiceResponse.parse(transcript)`, if the result is `.unknown` and confidence below threshold, set `conversationState = .ambiguous(step: step, prompt: disambiguationPrompt)` instead of `.idle`, and speak a narrowed clarifying question rather than silently failing.

***

## Architectural Note: Step Indexing

The current `step` Int + `totalSteps = 4` constant is brittle once dynamic steps (deferral, mood) are added. The recommended refactor is:

```swift
// Replace:
private let totalSteps = 4

// With:
private var activeSteps: [InterviewStep] {
    var steps: [InterviewStep] = []
    if hasDeferrals { steps.append(.deferralReview) }
    if moodCheckEnabled { steps.append(.moodCheck) }
    steps.append(.timeDeclaration)
    steps.append(.dueTodayReview)
    if !skipProfile.suppressStep2 { steps.append(.assumptionsReview) }
    steps.append(.planConfirm)
    return steps
}
```

This makes `totalSteps` computed, makes the progress bar accurate, and allows future steps to be toggled without touching layout code. The step `Int` becomes an index into `activeSteps`, and `speakForStep()` dispatches on `activeSteps[stepIndex]` rather than a raw integer.

---

## References

1. [Taking Control of the Dialog Management State Machine](https://developer.amazon.com/en-US/blogs/alexa/alexa-skills-kit/2018/03/taking-control-of-the-dialog-management-state-machine) - Each interaction between the customer and Alexa during dialog management allows to you hook into the...

2. [Dialogflow CX: Build a retail virtual agent | Google Codelabs](https://codelabs.developers.google.com/codelabs/dialogflow-cx-retail-agent) - In this codelab, you'll learn how to build a retail chatbot with Dialogflow CX, a Conversational AI ...

3. [General agent design best practices | Dialogflow CX](https://docs.cloud.google.com/dialogflow/cx/docs/concept/agent-design) - Guide the conversation. The agent should always guide the conversation with the end-user. This is ea...

4. [The best practices of conversation design - Voiceflow](https://www.voiceflow.com/pathways/conversation-design-best-practices) - Having conversations can be hard. Designing conversations for VUI & chatbots can be even harder. Her...

5. [Voice AI in Production: Conversation Flows, State Machines & Latency](https://www.youtube.com/watch?v=PuvNG0z7eAM) - Different type of videos to help explain conversational flows, state machines and latency. Used a lo...

6. [Handling Interruptions in AI Voice Assistants: Pause, Resume ...](https://www.linkedin.com/pulse/handling-interruptions-ai-voice-assistants-pause-resume-iyer-tznfe) - Mid-Stream Cut-Off & Memory Rollback: Use checkpoints in the dialog state stack10. Soft rollback ret...

7. [Survey Completion Rates: What Actually Predicts Drop-Off | Lensym](https://lensym.com/blog/survey-completion-rates-drop-off) - A 40% response rate with 95% completion means your invitation worked but your survey didn't drive pe...

8. [Voice Flow Best Practices](https://docs.glassix.com/docs/ai-voice-best-practices) - Keep messages as short as possible: Voice-based agents speak at a consistent speed, regardless of ho...

9. [How Reclaim uses Priorities to intelligently plan your workweek](https://help.reclaim.ai/en/articles/8291694-how-reclaim-uses-priorities-to-intelligently-plan-your-workweek) - Learn how to prioritize Reclaim and non-Reclaim events on your calendar to make time for your most i...

10. [Daily Planning - Setting up your Sunsama account](https://help.sunsama.com/docs/daily-planning) - Set your "when do you plan your day" setting to early morning, so you'll automatically enter daily p...

11. [Ask Less, Learn More: Adapting Ecological Momentary Assessment ...](https://pmc.ncbi.nlm.nih.gov/articles/PMC11633767/) - By strategically skipping the unselected questions that are likely to provide little new information...

12. [Beyond A/B Testing: A Practical Guide to Multi-Armed Bandits](https://www.shaped.ai/blog/multi-armed-bandits) - This article unpacks how multi-armed bandits offer a smarter alternative to A/B testing for real-tim...

13. [Dynamic Question Ordering in Online Surveys - Sage Journals](https://journals.sagepub.com/doi/pdf/10.1515/jos-2017-0030?download=true) - Online surveys have the potential to support adaptive questions, where later questions depend on ear...

14. [Mastering Multimodal UX: Best Practices for Seamless User ...](https://webdesignerdepot.com/mastering-multimodal-ux-best-practices-for-seamless-user-interactions/) - Prioritize Natural Transitions Between Modalities. Users don't want a jarring transition when switch...

15. [Multimodal Interaction Design — Voice, Touch, Gesture & Text Input ...](https://www.aiuxdesign.guide/patterns/multimodal-interaction) - Multimodal Interaction lets users communicate through voice, touch, gestures, text, and visual input...

16. [How to Use Todoist Effectively – The Complete Guide](https://www.todoist.com/inspiration/how-to-use-todoist-effectively) - Create a Todoist account, log in, and start learning how to get things done every day by adding and ...

17. [Schedulling recurring tasks on Things 3 a long digression - MPU Talk](https://talk.macpowerusers.com/t/schedulling-recurring-tasks-on-things-3-a-long-digression/27404) - The “When” is actually the Defer Date · The Upcoming list is actually a 'Deferred Until' list and I ...

18. [Association Between Improvement in Baseline Mood and Long ...](https://mental.jmir.org/2019/5/e12617/) - Unfortunately, there is little research investigating the long-term and repeated effects of apps mea...

19. [5 Ways Mood Tracking Improves Student Performance - Brightn](https://www.brightn.app/post/5-ways-mood-tracking-improves-student-performance) - A recent study found that use of mood-monitoring apps significantly reduced momentary negative mood ...

20. [The Science of Mood Tracking: Why It Works and ... - Innuora](https://www.innuora.com/content/mood-tracking/mood-tracking-benefits-guide/) - Research Evidence. Clinical Studies: Mood tracking apps show significant improvement in depression a...

