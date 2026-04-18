# Learnings Log
<!-- Append new entries at the bottom. Format: [LRN-YYYYMMDD-XXX] -->

### [LRN-20260418-001] Assets.xcassets is NOT wired into the SwiftPM target
- **Context:** Building the first-launch intro, I tried to plan `Color("BrandPrimary")` and `Image("BrandLogo")` via Asset Catalog entries at the repo-root `Assets.xcassets`.
- **Discovery:** `Package.swift` has `resources: [.copy("Resources")]` pointing at `Sources/Resources/`. It does NOT `.process("Assets.xcassets")`, and `Assets.xcassets` is outside the `path: "Sources"` target root. `AppIcon.appiconset` only works because `scripts/package_app.sh` runs `iconutil` on its PNGs directly — the runtime bundle has no compiled `Assets.car`.
- **Implication:** Any `Color("…")` / `Image("…")` by asset name will return a magenta placeholder at runtime. Branded colours must be Swift-defined (use `NSColor(name:)` dynamic adapter on macOS). Logos must ship under `Sources/Resources/` and load via `Bundle.module.url(forResource:withExtension:)`.
- **See:** `Sources/Core/Design/BrandTokens.swift` — `BrandColor.dynamic(light:dark:)` + `BrandAsset.logoImage()` for the pattern.

### [LRN-20260418-002] scripts/render_app_icons.sh glob bug aborts package_app.sh
- **Context:** `bash scripts/package_app.sh` failed after release build.
- **Cause:** `scripts/render_app_icons.sh:74` uses `"$ROOT_DIR"/Sources/*.swift` which matches zero files since `Sources/` is now subdirectory-organised (`Core/`, `Features/`, `Legacy/`, `Resources/`). `set -euo pipefail` propagates the swiftc failure up the call chain.
- **Workaround used:** Inline the rest of `package_app.sh` manually, skipping icon regen (existing PNGs are fine).
- **Proper fix:** Change the glob to `"$ROOT_DIR"/Sources/**/*.swift` with `shopt -s globstar`, OR collect files with `find "$ROOT_DIR/Sources" -name '*.swift' -not -path '*/Legacy/*'`.
