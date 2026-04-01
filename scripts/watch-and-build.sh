#!/bin/bash
# watch-and-build.sh — Watch Sources/ for .swift changes, auto-build + screenshot.
# Run in Terminal 3. Requires fswatch (brew install fswatch).
# Initial build runs immediately on start.

REPO="/Users/integrale/time-manager-desktop"
cd "$REPO"

echo "👀 Watching Sources/ for changes… (Ctrl+C to stop)"
echo ""

# Run initial build immediately
bash scripts/build-preview.sh

# Then watch for changes
fswatch -o Sources/ | while read; do
    echo ""
    echo "── Change detected ──────────────────────────────"
    bash scripts/build-preview.sh
done
