# NEXT.md — Timed

## Next Action

Continue the remaining review remediation after the 2026-05-01 readiness/test cleanup. Do not claim production iOS readiness until TimediOS placeholders, BGTask workers, APNs token sink, silent push sync, Share queue drain, widget snapshot writer, and Live Activity coordinator are wired.

## Reports

Saved in `docs/reviews/timed-code-review-2026-05-01/`:

- `00-master-issue-list.md`
- `01-full-directory-sweep.md`
- `02-security-audit.md`
- `03-performance-architecture.md`
- `04-production-readiness.md`
- `05-dependency-config-audit.md`
- `perplexity-review-prompt.md`

## Perplexity Prompt

Use `docs/reviews/timed-code-review-2026-05-01/perplexity-review-prompt.md`.

## Context

The first remediation pass is committed on `unified` through `5d3ce91 chore(timed): record remediation build state`. A later working-tree cleanup narrowed production claims and added static guard tests for classify-email, email upsert conflict target, app embedding readiness, and unwired iOS surfaces.

Verification already run before this later cleanup:

- `swift build`
- `swift test` — 71 tests passed
- `deno check` for changed Edge Functions
- `python3 -m py_compile services/graphiti/app/main.py`
- `pnpm typecheck` in `services/graphiti-mcp`
- `bash -n scripts/package_app.sh scripts/notarize_app.sh`

## Resume Instruction

Remaining implementation should stay aligned with `docs/reviews/timed-code-review-2026-05-01/00-master-issue-list.md`, avoid OfflineSyncQueue/DataBridge overlap unless explicitly assigned, and keep production-readiness docs in lockstep with code.
