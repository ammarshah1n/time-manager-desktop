#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/Timed.app"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/Timed.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing app bundle at $SOURCE_APP. Run scripts/package_app.sh first."
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

echo "Installed $TARGET_APP"
