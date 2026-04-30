#!/usr/bin/env bash
# Deploys the 16 Edge Functions changed in the 2026-04-29 security hardening pass.
#
#   - 14 cron-triggered functions had no JWT role check; now require
#     service-role JWT (Supabase platform already verifies the JWT signature,
#     we add a role-claim check via _shared/auth.ts:verifyServiceRole).
#     The pg_cron migrations already pass the service-role key as Bearer,
#     so no migration changes are required.
#
#   - extract-voice-features and generate-relationship-card called verifyAuth
#     but ignored its return value; both now perform an executives-table
#     ownership check (auth_user_id → owned executive id == body.executive_id).
#
# All other behaviour (CORS, body shape, response format) is unchanged.
#
# Usage:
#   bash scripts/deploy_security_hardening.sh
#
# Requires: supabase CLI logged in, project linked to fpmjuufefhtlwbfinxlx.

set -euo pipefail

PROJECT_REF="fpmjuufefhtlwbfinxlx"
FUNCTIONS=(
  # Cron-triggered (now require service-role JWT)
  "nightly-phase1"
  "nightly-phase2"
  "nightly-consolidation-full"
  "nightly-consolidation-refresh"
  "nightly-bias-detection"
  "weekly-pattern-detection"
  "weekly-avoidance-synthesis"
  "weekly-pruning"
  "weekly-strategic-synthesis"
  "monthly-trait-synthesis"
  "multi-agent-council"
  "thin-slice-inference"
  "generate-morning-briefing"
  "acb-refresh"
  # User-facing (now enforce executive ownership)
  "extract-voice-features"
  "generate-relationship-card"
)

echo "Deploying ${#FUNCTIONS[@]} hardened functions to ${PROJECT_REF}..."
for fn in "${FUNCTIONS[@]}"; do
  echo "→ ${fn}"
  supabase functions deploy "${fn}" --project-ref "${PROJECT_REF}"
done

echo
echo "Done. To verify rejection of unauthenticated calls:"
echo
echo "  curl -X POST https://${PROJECT_REF}.supabase.co/functions/v1/nightly-phase1 \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"executive_id\":\"test\"}'"
echo "  → expect 401 (no Authorization header)"
echo
echo "  curl -X POST https://${PROJECT_REF}.supabase.co/functions/v1/nightly-phase1 \\"
echo "    -H \"Authorization: Bearer \${SUPABASE_ANON_KEY}\" \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"executive_id\":\"test\"}'"
echo "  → expect 403 (anon JWT, role !== service_role)"
