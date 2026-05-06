#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist.noindex/Timed.app"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/Timed.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing app bundle at $SOURCE_APP. Run scripts/package_app.sh first."
  exit 1
fi

mkdir -p "$TARGET_DIR"

# Quit any running Timed instance so the bundle can be replaced cleanly.
# Required after every build so the Dock icon reflects the latest binary.
osascript -e 'tell application "Timed" to quit' 2>/dev/null || true
sleep 1

rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

# Strip the macOS quarantine flag so Gatekeeper does not block first launch.
# Required for ad-hoc-signed builds. Once the Apple Developer Program enrollment
# lands and the DMG is notarised, this step becomes a no-op.
echo "Stripping macOS quarantine flag (required for ad-hoc signed builds)…"
xattr -cr "$TARGET_APP" || true

echo "Installed $TARGET_APP"
echo "Launch from /Applications/Timed.app or Spotlight."
