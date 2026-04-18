# Session Handoff — 2026-04-18 GMT+2

## Done This Session
- **Cinematic first-launch intro** — new TCA `IntroFeature` (@Reducer + @ObservableState) + `IntroView` rendered edge-to-edge with `.windowStyle(.hiddenTitleBar)`
- **Animation technique** — circular mask reveal of the logo + MeshGradient (iOS 18/macOS 15) with TimelineView-driven hue drift; word-by-word tagline; exit morphs background to `BrandColor.surface` to avoid hard cut
- **Reduce Motion** — respected via `@Environment(\.accessibilityReduceMotion)`; collapses entire sequence to a 300ms cross-fade
- **Skip affordance** — top-right capsule fades in at 2s
- **Brand tokens** — `Sources/Core/Design/BrandTokens.swift`: `BrandColor` (dynamic light/dark), `BrandMotion`, `BrandType`, `BrandVersion.current = "v1"` + `introSeenKey`, `BrandAsset.logoImage()`
- **Logo asset** — `Sources/Resources/BrandLogo.png` (copied from existing white-clock AppIcon; still a placeholder per Apr 16 note)
- **App root gate** — `@AppStorage("hasSeenIntro_v1")` flips on `IntroFeature.delegate(.completed)`, then swaps to `TimedRootView` with a 0.4s cross-fade
- **Packaged + launched** — `dist/Timed.app` built in release, signed, opened successfully

## Current State
- Branch: `ui/apple-v1-restore` — new commits ahead of origin
- Build: clean (`swift build` 31.93s debug, `swift build -c release` 271s)
- TCA: first real use of `@Reducer` in this codebase; previously only `@Dependency` was referenced indirectly
- App: opens to the intro; once dismissed, falls through to onboarding (first launch) or main root

## Known Issues
- `scripts/render_app_icons.sh:74` glob bug — `"$ROOT_DIR"/Sources/*.swift` matches nothing now that `Sources/` has subdirs; causes `set -e` abort in `package_app.sh`. Worked around manually this session.
- `Assets.xcassets` at repo root is NOT in the SwiftPM target — any `Color("…")` / `Image("…")` by asset name would fail to resolve. All brand colours live in Swift; logo is loaded via `Bundle.module`.
- Real logo still pending — placeholder white clock ships for now. Drop replacement at `Sources/Resources/BrandLogo.png` and rebuild.
- Previous session's voice-conversational onboarding work still uncommitted in working tree (`VoiceCaptureService.swift`, `OnboardingFlow.swift`, `OnboardingAIClient.swift`) — intentionally untouched.

## Next
1. **Replace placeholder logo** — drop the real PNG at `Sources/Resources/BrandLogo.png`
2. **Fix render_app_icons.sh** — change glob to `Sources/**/*.swift` with globstar, or supply an explicit file list
3. **Conversational onboarding** — enable mic per step, user speaks, Opus parses (prior-session WIP already on disk)
4. **End-to-end Outlook sign-in** — first real user flow test
5. **Deploy backend** — 6 new intelligence migrations + 7 new Edge Functions

## Dev reset
Replay the intro any time:
```
defaults delete com.ammarshahin.timed hasSeenIntro_v1 && open dist/Timed.app
```
