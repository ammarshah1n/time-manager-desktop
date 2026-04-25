#!/usr/bin/env bash
# Deploys the 4 edge functions that were rewritten to use JWT auth instead of
# the YASSER_USER_ID env var. Run after pulling the multi-user commit.
#
# Usage:
#   bash scripts/deploy_multiuser_functions.sh
#
# Requires: supabase CLI logged in, project linked to fpmjuufefhtlwbfinxlx.

set -euo pipefail

PROJECT_REF="fpmjuufefhtlwbfinxlx"
FUNCTIONS=(
  "generate-dish-me-up"
  "voice-llm-proxy"
  "extract-onboarding-profile"
  "extract-voice-learnings"
  "anthropic-relay"
  "orb-conversation"
  "orb-tts"
  "deepgram-token"
)

echo "Deploying ${#FUNCTIONS[@]} functions to ${PROJECT_REF}..."
for fn in "${FUNCTIONS[@]}"; do
  echo "→ ${fn}"
  supabase functions deploy "${fn}" --project-ref "${PROJECT_REF}"
done

echo
echo "All deployed. Required server-side secrets (set via supabase secrets set):"
echo "  ANTHROPIC_API_KEY    — for orb-conversation, anthropic-relay (already set)"
echo "  ELEVENLABS_API_KEY   — for orb-tts"
echo "  DEEPGRAM_API_KEY     — for deepgram-token (your long-lived Deepgram project key)"
echo "  DEEPGRAM_PROJECT_ID  — for deepgram-token. Find it via:"
echo "      curl -H 'Authorization: Token \$DEEPGRAM_API_KEY' https://api.deepgram.com/v1/projects | jq '.projects[0].project_id'"
echo
echo "The legacy YASSER_USER_ID secret can be removed:"
echo "  supabase secrets unset YASSER_USER_ID --project-ref ${PROJECT_REF}"
