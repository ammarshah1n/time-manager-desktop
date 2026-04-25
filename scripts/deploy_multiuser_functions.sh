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
)

echo "Deploying ${#FUNCTIONS[@]} functions to ${PROJECT_REF}..."
for fn in "${FUNCTIONS[@]}"; do
  echo "→ ${fn}"
  supabase functions deploy "${fn}" --project-ref "${PROJECT_REF}"
done

echo
echo "All deployed. The YASSER_USER_ID secret can be removed:"
echo "  supabase secrets unset YASSER_USER_ID --project-ref ${PROJECT_REF}"
