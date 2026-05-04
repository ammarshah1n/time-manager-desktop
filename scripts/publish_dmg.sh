#!/usr/bin/env bash
set -euo pipefail

DMG_SRC="${PWD}/dist.noindex/Timed.dmg"
FACILITATED_REPO="${HOME}/facilitated"
DOWNLOADS_DIR="${FACILITATED_REPO}/public/downloads"

[[ -f "$DMG_SRC" ]] || { echo "DMG not found at $DMG_SRC. Run package_app.sh && create_dmg.sh first." >&2; exit 1; }
[[ -d "$FACILITATED_REPO" ]] || { echo "facilitated repo not found at $FACILITATED_REPO" >&2; exit 1; }

mkdir -p "$DOWNLOADS_DIR"
cp -f "$DMG_SRC" "$DOWNLOADS_DIR/Timed.dmg"
SHA=$(shasum -a 256 "$DOWNLOADS_DIR/Timed.dmg" | awk '{print $1}')
SIZE_MB=$(du -m "$DOWNLOADS_DIR/Timed.dmg" | awk '{print $1}')

echo "Published Timed.dmg -> ${DOWNLOADS_DIR}/Timed.dmg"
echo "  Size:   ${SIZE_MB} MB"
echo "  SHA256: ${SHA}"
echo ""
echo "Next: cd ${FACILITATED_REPO} && git add public/downloads/Timed.dmg && git commit && git push"
