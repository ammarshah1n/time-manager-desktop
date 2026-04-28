#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist.noindex/Timed.app"
DMG_PATH="$ROOT_DIR/dist.noindex/Timed.dmg"
VOLUME_NAME="Timed"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Error: $APP_DIR not found. Run scripts/package_app.sh first."
  exit 1
fi

rm -f "$DMG_PATH"

# Create temporary DMG directory
STAGING="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Drop the README onto the DMG so first-launch Gatekeeper instructions ride
# along with the .app — users who skip install_app.sh still get the xattr step.
cat > "$STAGING/README - OPEN ME FIRST.txt" <<'TXT'
Welcome to Timed.

Before opening Timed for the first time, run this in Terminal:

    xattr -cr /Applications/Timed.app

Then double-click Timed in /Applications.

Why: this build is signed for development distribution, not the App Store.
The Apple Developer Program enrollment lands shortly — once that is done,
this step disappears.
TXT

# Create DMG
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

echo "Created $DMG_PATH"
echo ""
echo "First launch on a new Mac:"
echo "  1. Open the DMG and drag Timed to Applications"
echo "  2. Run: xattr -cr /Applications/Timed.app  (or use install_app.sh which does this)"
echo "  3. Double-click Timed in /Applications"
