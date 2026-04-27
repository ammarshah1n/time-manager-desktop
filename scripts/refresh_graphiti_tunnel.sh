#!/usr/bin/env bash
# refresh_graphiti_tunnel.sh
#
# Read the current Cloudflare quick-tunnel URL off the Fedora MBP and push it
# back into Supabase as the GRAPHITI_BASE_URL Edge Function secret. Run this
# whenever the Fedora box has rebooted or the cloudflared service has been
# restarted — the quick tunnel rotates its hostname every restart.
#
# Prereqs:
#   - SSH key auth to ammarshahin@192.168.0.20 (Fedora)
#   - `supabase` CLI logged in, linked to project fpmjuufefhtlwbfinxlx
#   - timed-cf-tunnel.service running on Fedora as a user systemd unit
#
# Usage: bash scripts/refresh_graphiti_tunnel.sh

set -euo pipefail

FEDORA="ammarshahin@192.168.0.20"
PROJECT_REF="fpmjuufefhtlwbfinxlx"

echo "→ pulling tunnel URL from $FEDORA …"
URL="$(ssh "$FEDORA" "grep -oE 'https://[a-z0-9-]+\\.trycloudflare\\.com' /tmp/cf-tunnel.log | tail -1" || true)"

if [[ -z "$URL" ]]; then
  echo "✗ Could not find a tunnel URL in /tmp/cf-tunnel.log on $FEDORA."
  echo "  Check the service: ssh $FEDORA 'systemctl --user status timed-cf-tunnel.service'"
  exit 1
fi

echo "→ tunnel URL: $URL"

echo "→ probing Graphiti reachability …"
HEALTH="$(curl -sS --max-time 8 "$URL/healthz" || echo "FAIL")"
if [[ "$HEALTH" != *"\"ok\":true"* ]]; then
  echo "✗ /healthz did not return ok. Got: $HEALTH"
  exit 1
fi
echo "  ✓ /healthz ok"

echo "→ updating Supabase secret GRAPHITI_BASE_URL …"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
supabase secrets set --workdir "$REPO_ROOT" "GRAPHITI_BASE_URL=$URL" >/dev/null

echo "✓ Done. voice-llm-proxy will pick up the new URL on its next cold start."
echo "  (Edge Functions cache env vars per isolate — old isolates may serve the"
echo "   stale URL for a few minutes. To force-flush: redeploy voice-llm-proxy.)"
