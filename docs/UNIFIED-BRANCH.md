# UNIFIED-BRANCH.md — The Single Source of Truth

**Created:** 2026-04-27
**Branch:** `unified`
**Status:** ✅ Track B delivered — ad-hoc signed DMG built and verified.

---

## TL;DR

The `unified` branch is the single source of truth for Timed. It carries:

- **TimedKit** — one shared Swift library that compiles for **both macOS 15+ and iOS 18+**. 123 Swift files in `Sources/TimedKit/`.
- **TimedMacApp** — thin Mac shim (`Sources/TimedMacApp/TimedMacAppMain.swift`) producing the macOS executable.
- **TimediOS** — iOS @main app shim (`Platforms/iOS/TimediOSAppMain.swift`), currently simulator-build/scaffold only.
- **Wave 1+2 backend** — `trigger/` (13 Trigger.dev v4 tasks), `services/` (Graphiti FastAPI, Graphiti MCP, Skill Library MCP), `supabase/` schema (59 SQL files including agent_traces, NREM/REM pipeline, executive_profile, kg_snapshots).
- **Voice path locked** — orb runs ElevenLabs Agent + Opus 4.7 via Edge Function proxies (`anthropic-proxy`, `elevenlabs-tts-proxy`, `voice-llm-proxy`); no API keys ever ship in the binary.
- **iOS extensions** — `Extensions/Widgets/` (widget + Live Activity UI scaffold), `Extensions/Share/` (share sheet queue scaffold). Main-app writers/drains/coordinators are not wired yet.
- **Platform manifests** — `Platforms/Mac/{Info.plist,Timed.entitlements}`, `Platforms/iOS/{Info.plist,PrivacyInfo.xcprivacy}`.
- **XcodeGen `project.yml`** — declarative source for `Timed.xcodeproj`. The generated `.xcodeproj` is **gitignored**; regenerate via `xcodegen generate`.
- **Consolidated docs** — `docs/SINCE-2026-04-24.md`, this file, `HANDOFF.md`, `HANDOFF-wave2.md`, `BUILD_STATE.md`.

This branch was forged on 2026-04-27 by merging four divergent branches:

| Source branch | What it contributed | Merge commit |
|---|---|---|
| `ios/port-bootstrap` | Base — TimedKit carve-out, iOS scaffold, project.yml, Platforms/, Extensions/ | (used as base) |
| `ui/apple-v1-local-monochrome` | Voice work (eb85f17), consolidated docs (aa422d3), monochrome UI, brand mockups | `5acd23f` |
| `ui/apple-v1-wired` | Wave 1+2 backend — trigger/, services/, supabase/ schema | `54fe80e` |
| (current edits) | iOS gating fix for PrefsPane, gitignore tightening | `1b8d009` |

---

## Why This Existed (The Problem)

Before 2026-04-27, Timed was split across **three+ branches** with non-overlapping content. None of them could produce both a Mac DMG AND an iOS app. They all had partial state:

| Branch | Had | Did NOT have |
|---|---|---|
| `main` | (stale) | Anything from the last 2 weeks |
| `ui/apple-v1-restore` | Old Wave-1 partial backend | TimedKit, iOS scaffold, latest UI, voice path |
| `ui/apple-v1-wired` | Wave 1+2 backend (trigger, services, schema) | TimedKit, iOS scaffold, voice path |
| `ui/apple-v1-local-monochrome` | Voice path locked, consolidated docs, monochrome UI | TimedKit, iOS scaffold, backend |
| `ios/port-bootstrap` | TimedKit carve-out, iOS scaffold, project.yml | Voice path, docs, backend |

Working from any single branch meant missing critical infrastructure. The `unified` branch fixes this by carrying **everything**, on **one** Package.swift, with **one** TimedKit library.

---

## The Architecture (How It's Wired)

```
time-manager-desktop/                          ← unified branch root
│
├── Package.swift                              # platforms: [.macOS(.v15), .iOS(.v18)]
│                                                # products:
│                                                #   - TimedKit (library, shared)
│                                                #   - time-manager-desktop (executable, Mac only)
│
├── Sources/
│   ├── TimedKit/                              # 123 files — ALL shared application code
│   │   ├── AppEntry/                          #   - iOS root view, push/BG task scaffolds, intents
│   │   ├── Core/                              #   - Agents, Audio, Clients, Design, Models, Platform, Services
│   │   └── Features/                          #   - Briefing, Calendar, Capture, CommandPalette, Conversation,
│   │                                           #     DishMeUp, Focus, MenuBar (Mac-only), MorningCheckIn,
│   │                                           #     Onboarding, Plan, Prefs (Mac-only), Tasks, Today, Triage,
│   │                                           #     Waiting, Sharing (Mac-only)
│   │                                           # Mac-only files use #if os(macOS) gate.
│   │
│   └── TimedMacApp/                           # Mac executable shim
│       └── TimedMacAppMain.swift              #   @main, instantiates TimedAppShell from TimedKit
│
├── Platforms/
│   ├── Mac/                                   # Mac-specific config
│   │   ├── Info.plist                         #   bundle ID, URL schemes, mic/speech/etc usage
│   │   └── Timed.entitlements                 #   hardened runtime, sandbox exemptions
│   │
│   └── iOS/                                   # iOS-specific config
│       ├── TimediOSAppMain.swift              #   @main for iOS, hosts TimedAppShell from TimedKit
│       ├── Info.plist                         #   iOS-specific keys
│       └── PrivacyInfo.xcprivacy              #   App Store privacy manifest
│
├── Extensions/
│   ├── Widgets/                               # widget + Live Activity UI scaffolds
│   └── Share/                                 # iOS share extension queue scaffold
│
├── trigger/                                   # Wave 1+2 backend (Trigger.dev v4)
│   ├── src/inference.ts                       # Anthropic inference helper
│   ├── src/tasks/                             # 13 tasks: graph-delta-sync, NREM pipeline,
│   │                                           # REM synthesis, outcome-harvester, kg-snapshot, …
│   ├── trigger.config.ts
│   └── package.json                           # pnpm-managed
│
├── services/                                  # Long-running services (Docker / fly.io)
│   ├── graphiti/                              # FastAPI temporal-graph service
│   ├── graphiti-mcp/                          # MCP wrapper
│   └── skill-library-mcp/                     # MCP for skill library
│
├── supabase/
│   ├── migrations/                            # 59 SQL files
│   ├── functions/                             # Edge Functions (39 active remote; local tree has parked extras)
│   └── scripts/
│
├── docs/                                      # Consolidated documentation
│   ├── SINCE-2026-04-24.md                    # Source of truth for Apr 24-27 work
│   ├── UNIFIED-BRANCH.md                      # THIS FILE — permanent architecture reference
│   ├── 01-architecture.md … 08-decisions-log.md
│   ├── sessions/                              # Per-session writeups
│   └── planning-templates/
│
├── scripts/
│   ├── package_app.sh                         # swift build → dist.noindex/Timed.app (ad-hoc signed)
│   ├── create_dmg.sh                          # → dist.noindex/Timed.dmg
│   ├── notarize_app.sh                        # gated on $TIMED_NOTARY_PROFILE (Track A pending)
│   └── install_app.sh                         # → /Applications/Timed.app
│
├── project.yml                                # XcodeGen — SOURCE OF TRUTH for Xcode project
└── Timed.xcodeproj/                           # GENERATED, gitignored. Run `xcodegen generate`.
```

### How code is shared between Mac and iOS

- **All shared logic** lives in `Sources/TimedKit/`. Both Mac and iOS link the same library.
- **Mac-only code** (`#if os(macOS)`) — uses NSColor, NSStatusItem, ApplicationServices, IOKit, ServiceManagement, NSEvent monitors, `.radioGroup` picker style, etc. Currently gated:
  - `Sources/TimedKit/Features/Prefs/PrefsPane.swift`
  - `Sources/TimedKit/Features/Sharing/SharingPane.swift`
  - `Sources/TimedKit/Features/MenuBar/MenuBarManager.swift`, `GlobalHotkeyManager.swift`
  - `Sources/TimedKit/Features/{Focus,Plan,Capture,CommandPalette,DishMeUp}/...`
  - `Sources/TimedKit/Core/Agents/{KeystrokeAgent,IdleTimeAgent,AppUsageAgent}.swift`
  - `Sources/TimedKit/Core/Services/XPCServiceManager.swift`
  - `Sources/TimedKit/Core/Design/BrandTokens.swift` (uses `#if canImport(AppKit)`)
- **iOS App Entry** is `Platforms/iOS/TimediOSAppMain.swift` — instantiates `TimedAppShell` from TimedKit, currently with `PlaceholderPane` stubs for primary panes. BGTask workers, APNs token sink, silent-push sync, share queue drain, widget snapshot writer, and Live Activity lifecycle are not production-wired yet.

---

## Build Matrix (Verified 2026-04-27)

All three build paths compile from this single branch:

```bash
# Path 1: SwiftPM CLI build (fast iteration, runs in 100s)
swift build
# → .build/release/time-manager-desktop

# Path 2: Mac Release (.app bundle for distribution)
xcodegen generate
xcodebuild -project Timed.xcodeproj \
  -scheme TimedMac \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build

# Path 3: iOS Simulator compile check
xcodebuild -project Timed.xcodeproj \
  -scheme TimediOS \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  build
```

### Known build-flag requirements

| Flag | Why | Without it |
|---|---|---|
| `-skipMacroValidation` | swift-composable-architecture, swift-case-paths, swift-dependencies, swift-perception use macros that need first-run trust prompt | "Macro must be enabled before it can be used" error |
| `-skipPackagePluginValidation` | Same root cause — package plugins need explicit trust | Plugin validation prompt |
| `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` (macOS only) | The `usearch` package uses `Float16` which is iOS-only; compiling for x86_64 fails | "'Float16' is unavailable in macOS" errors |

These flags will not be needed once the project is opened in Xcode interactively (one-time trust-and-remember).

---

## Mac DMG Production (Track B — DELIVERED)

**Status: ✅ DMG built 2026-04-27, ad-hoc signed.**

```bash
bash scripts/package_app.sh    # → dist.noindex/Timed.app (31 MB) ad-hoc signed
bash scripts/create_dmg.sh     # → dist.noindex/Timed.dmg (31 MB) UDZO compressed
bash scripts/install_app.sh    # → /Applications/Timed.app
```

**Distribution to Yasser (interim):**

The DMG is ad-hoc signed because no Apple Developer Program membership is active. Yasser must run `xattr -cr /Applications/Timed.app` after installing, or right-click → Open the first time, to bypass Gatekeeper. This is the Track B path. Track A (proper Developer ID + notarisation) follows enrollment.

---

## What's NOT Done Yet (Track A — Pending Apple Enrollment)

These steps are blocked on Apple Developer Program enrollment (not yet started; ~24-48h after enrollment is initiated):

1. **Step 0** — Enroll at developer.apple.com/programs/enroll, $99/yr, individual.
2. **Step 6** — Provision Developer ID Application cert (Mac) + Apple Distribution cert (iOS) + notary profile (`xcrun notarytool store-credentials timed-notary …`).
3. **Step 7** — Switch `scripts/package_app.sh` from `--sign -` (ad-hoc) to `--sign "Developer ID Application: …"`, add `--options runtime`, embed `Platforms/Mac/Timed.entitlements`. Run notarize_app.sh + create_dmg.sh. **Output: signed + notarised + stapled DMG.**
4. **Step 8** — App Store Connect record for `com.ammarshahin.timed.ios`, provisioning profile, archive, exportArchive, altool upload to TestFlight, invite Yasser as internal tester.
5. **Step 9** (optional) — Sparkle 2.x SPM dependency, EdDSA keypair, SUFeedURL in Info.plist, `scripts/release.sh` automation.
6. **Step 10** — Merge `unified` → `main`, retire stale branches.

The full plan lives in `/Users/integrale/.claude/plans/ultrathink-i-need-you-cached-glade.md`.

---

## Branch Hygiene — What To Retire When Track A Lands

Once `unified` is verified working end-to-end (Step 7 + 8), squash-merge to `main` and retire:

- `ui/apple-v1-restore` (stale, never had backend)
- `ui/apple-v1-local-monochrome` (superseded — voice + docs now on unified)
- `ui/apple-v1-wired` (superseded — backend now on unified)
- `ios/port-bootstrap` (superseded — TimedKit + iOS scaffold now on unified)
- `docs/wave-1-2-wrap-up`
- `wave2-b1-server-graph`, `wave2-b2-nrem-pipeline`, `wave2-b3-outcome-loop`, `wave2-b4-rem-synthesis` (all merged into unified via apple-v1-wired)
- `codex/parallel-tracks`
- `ui/today-feature`

Keep `main` as canonical trunk after the merge.

---

## How To Resume Work On This Branch

1. **Always start from `unified`:** `git checkout unified && git pull`
2. **Generate Xcode project locally:** `xcodegen generate` (don't commit `Timed.xcodeproj`)
3. **For Mac dev:** `swift build` for fast iteration, `bash scripts/package_app.sh` to produce a runnable .app
4. **For iOS dev:** Open `Timed.xcodeproj` in Xcode, select `TimediOS` scheme, build/run on simulator
5. **For backend dev:** `cd trigger && pnpm install && pnpm dev` (Trigger.dev local dev). Services run via Docker (OrbStack); see `services/*/README.md` for fly.io deploy.
6. **For Edge Functions:** `cd supabase && supabase functions deploy <name>` (after `supabase login` + linking)

---

## Audit Trail

| Date | Action | By |
|---|---|---|
| 2026-04-27 14:54 | Plan approved by Ammar | `/Users/integrale/.claude/plans/ultrathink-i-need-you-cached-glade.md` |
| 2026-04-27 15:18 | OrbStack closed (running on Linux machine instead) | Bash |
| 2026-04-27 15:18 | `ios/port-bootstrap` pushed to origin as backup | git push |
| 2026-04-27 15:19 | Pre-unification snapshot on `ui/apple-v1-local-monochrome` (commit `df612d1`) | git commit |
| 2026-04-27 15:20 | `unified` branch created off `ios/port-bootstrap` | git checkout -b |
| 2026-04-27 15:20 | `Timed.xcodeproj/` untracked + .gitignore tightened | commits `e2277af` + `269baef` |
| 2026-04-27 15:23 | Merged `ui/apple-v1-local-monochrome` → unified (voice + docs) | commit `5acd23f` |
| 2026-04-27 15:30 | Merged `ui/apple-v1-wired` → unified (Wave 1+2 backend) | commit `54fe80e` |
| 2026-04-27 15:35 | swift build green (99.79s) | bash |
| 2026-04-27 15:39 | Mac arm64 build green | xcodebuild |
| 2026-04-27 15:43 | iOS sim build green (after PrefsPane gating fix `1b8d009`) | xcodebuild |
| 2026-04-27 15:44 | `unified` pushed to origin | git push |
| 2026-04-27 15:51 | `dist.noindex/Timed.app` packaged (398.96s, signed ad-hoc) | scripts/package_app.sh |
| 2026-04-27 15:51 | `dist.noindex/Timed.dmg` created (31 MB, hdiutil verified) | scripts/create_dmg.sh |

---

## Reference Files

- `docs/SINCE-2026-04-24.md` — full narrative of weekend work
- `HANDOFF.md` — operational handoff
- `HANDOFF-wave2.md` — Wave 2 deployment runbook
- `BUILD_STATE.md` — current architecture summary
- `/Users/integrale/.claude/plans/ultrathink-i-need-you-cached-glade.md` — the plan that produced this consolidation
- `project.yml` — Xcode project source of truth
- `Package.swift` — SwiftPM definition

This document is permanent. Do not retire or rewrite without explicit direction.
