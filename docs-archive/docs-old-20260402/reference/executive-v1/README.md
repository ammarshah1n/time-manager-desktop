# Executive Timed V1 Reference Pack

This is the correct early SwiftUI frontend lineage for the executive Timed/Yasser PRD.

Do not use:
- the old student/school planner app
- `docs/assets/timed-planner.png`
- `docs/assets/timed-settings.png`
- `docs/assets/timed-quiz.png`

Those belong to the wrong product line.

Use these files as the visual source of truth:
- `TimedRootView_v1.swift`
- `TodayPane_v1.swift`
- `TriagePane_v1.swift`
- `DishMeUpSheet_v1.swift`
- `PrefsPane_v1.swift`

Chat/history anchor:
- Claude session: `/Users/integrale/.claude/projects/-Users-integrale/3c36df3f-7496-456b-9ad5-193e39f2fc97.jsonl`
- Key user message: line 19
- Meaning: "the first iteration" the user loved is this executive Timed UI lineage, not the student app.

Canonical product anchor:
- `/Users/integrale/Timed-Brain/03 - Specs/PRD.md`

Suggested prompt to Claude:

```text
Use only the files in /Users/integrale/time-manager-desktop/docs/reference/executive-v1 as the visual reference for Timed v1.

This is the executive Timed/Yasser PRD frontend the user meant when they said:
"I love the UI but the features aren't there."

Do not use any student/school/planner UI references.
Do not use docs/assets/timed-planner.png, timed-settings.png, or timed-quiz.png.

Restore this exact visual language:
- native macOS SwiftUI feel
- white/system backgrounds
- restrained color
- stock Apple controls
- minimal chrome

Keep current features and behavior, but adapt the UI to match this reference pack.
```
