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

# Create DMG
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

echo "Created $DMG_PATH"
echo ""
echo "First launch on a new Mac:"
echo "  1. Open the DMG and drag Timed to Applications"
echo "  2. Right-click Timed.app → Open (bypasses Gatekeeper)"
echo "  3. Or run: xattr -cr /Applications/Timed.app"
