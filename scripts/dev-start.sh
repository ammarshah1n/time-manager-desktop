#!/bin/bash
# dev-start.sh — Master remote dev startup. Run this once tomorrow morning.
# Opens Terminal 2 (preview server) and Terminal 3 (watcher) automatically.
# Claude Code remote = Terminal 1 (already running this).

REPO="/Users/integrale/time-manager-desktop"
cd "$REPO"

chmod +x scripts/build-preview.sh
chmod +x scripts/preview-server.sh
chmod +x scripts/watch-and-build.sh

echo "🚀 Starting Timed remote dev environment…"
echo ""

# Terminal 2 — Preview server + Cloudflare tunnel
osascript << 'OSASCRIPT'
tell application "Terminal"
    activate
    set win2 to do script "cd /Users/integrale/time-manager-desktop && bash scripts/preview-server.sh"
    set custom title of win2 to "Timed — Preview Server"
end tell
OSASCRIPT

sleep 1

# Terminal 3 — File watcher + auto-build
osascript << 'OSASCRIPT'
tell application "Terminal"
    activate
    set win3 to do script "cd /Users/integrale/time-manager-desktop && bash scripts/watch-and-build.sh"
    set custom title of win3 to "Timed — Watcher"
end tell
OSASCRIPT

echo ""
echo "✅ Started 2 background terminals:"
echo "   Terminal 2: Preview server + Cloudflare URL (check that window for iPhone URL)"
echo "   Terminal 3: File watcher + auto-build"
echo ""
echo "This terminal (Terminal 1) is yours — Claude Code is running here."
echo ""
echo "Workflow:"
echo "  1. Get the Cloudflare URL from Terminal 2"
echo "  2. Open it on iPhone — auto-refreshes every 2s"
echo "  3. Tell Claude what to change → saved → Terminal 3 auto-builds → iPhone updates"
echo ""
