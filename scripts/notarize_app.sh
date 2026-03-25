#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/timed.app"
ZIP_PATH="$DIST_DIR/timed-notarize.zip"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing $APP_PATH. Run bash scripts/package_app.sh first." >&2
  exit 1
fi

if [[ -z "${TIMED_NOTARY_PROFILE:-}" ]]; then
  cat >&2 <<'EOF'
Missing TIMED_NOTARY_PROFILE.

Create a notarytool keychain profile first, for example:
  xcrun notarytool store-credentials "timed-notary" \
    --apple-id "<APPLE_ID>" \
    --team-id "<TEAM_ID>" \
    --password "<APP_SPECIFIC_PASSWORD>"

Then run:
  TIMED_NOTARY_PROFILE=timed-notary bash scripts/notarize_app.sh
EOF
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$TIMED_NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

echo "Notarized and stapled $APP_PATH"
