#!/bin/bash
# build-preview.sh — Build the app, launch it, screenshot it.
# Called by dev-start.sh watcher whenever a .swift file changes.

set -e
REPO="/Users/integrale/time-manager-desktop"
PREVIEW_DIR="/tmp/timed-preview"

cd "$REPO"

echo "⏳ Building…"
if swift build 2>&1 | tee /tmp/timed-build.log | tail -5 | grep -q "error:"; then
    echo "❌ Build failed — see /tmp/timed-build.log"
    # Write error to preview so iPhone shows it
    cat > "$PREVIEW_DIR/preview-status.txt" << EOF
BUILD FAILED at $(date +%H:%M:%S)
$(grep "error:" /tmp/timed-build.log | head -5)
EOF
    exit 1
fi

echo "✅ Build OK — launching…"
pkill -f "time-manager-desktop" 2>/dev/null || true
sleep 0.4
open ".build/debug/time-manager-desktop"
sleep 1.8   # let the window render

echo "📸 Screenshotting…"
mkdir -p "$PREVIEW_DIR"
screencapture -x "$PREVIEW_DIR/preview.png"

echo "$(date +%H:%M:%S)" > "$PREVIEW_DIR/preview-status.txt"
echo "✅ Preview updated at $(date +%H:%M:%S)"
