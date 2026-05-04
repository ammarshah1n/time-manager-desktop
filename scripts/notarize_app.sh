#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${TIMED_APP_PATH:-$ROOT_DIR/dist.noindex/Timed.app}"
DMG_PATH="${TIMED_DMG_PATH:-$ROOT_DIR/dist.noindex/Timed.dmg}"
NOTARY_PROFILE="${TIMED_NOTARY_PROFILE:-}"
APPLE_ID="${TIMED_NOTARY_APPLE_ID:-}"
APPLE_TEAM_ID="${TIMED_APPLE_TEAM_ID:-}"
APPLE_PASSWORD="${TIMED_NOTARY_PASSWORD:-}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: app not found at $APP_DIR. Run scripts/package_app.sh first." >&2
  exit 66
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "$APPLE_ID" && -n "$APPLE_TEAM_ID" && -n "$APPLE_PASSWORD" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_PASSWORD" \
    --wait
else
  echo "ERROR: set TIMED_NOTARY_PROFILE or TIMED_NOTARY_APPLE_ID/TIMED_APPLE_TEAM_ID/TIMED_NOTARY_PASSWORD." >&2
  exit 64
fi

xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --verbose=4 "$DMG_PATH"
