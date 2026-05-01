# Perplexity Review Prompt — Timed Code Review Reports

Use this prompt with Perplexity after attaching or pasting the six markdown reports in this folder:

- `00-master-issue-list.md`
- `01-full-directory-sweep.md`
- `02-security-audit.md`
- `03-performance-architecture.md`
- `04-production-readiness.md`
- `05-dependency-config-audit.md`

Prompt:

```text
You are reviewing a full-codebase audit of Timed, a macOS Swift/SwiftUI/TCA/GRDB desktop app with Supabase Edge Functions, SQL migrations, Trigger.dev tasks, Graphiti services, and packaging/CI scripts.

Inputs:
- Six attached Codex review reports dated 2026-05-01.
- The repo remediation pass has already addressed an initial batch: local/tracked secret surfaces were parameterized or removed, provider/privileged Edge Functions were gated, Graphiti core endpoints gained bearer auth, several tenant ownership checks and Graph webhook clientState validation were added, email/Gmail classify-email contracts and cursor safety were repaired, Tier 0 observation idempotency was added, and macOS release artifact paths were aligned.

Task:
1. Review all six reports as a single evidence set.
2. Identify which findings remain strategically important after the initial remediation pass.
3. Produce a final implementation plan ordered by risk reduction and dependency order.
4. For each recommended work item, include:
   - severity and rationale,
   - exact files or subsystems to inspect,
   - implementation outline,
   - migration/deploy implications,
   - verification commands,
   - whether web/current package or CVE lookup is required.
5. Flag any report findings that look stale, duplicated, or superseded by the remediation batch.
6. Do not ask for or reproduce secrets. Treat any exposed credentials as requiring out-of-band rotation.

Output format:
- Top 10 remaining issues.
- 3-phase implementation plan: immediate, next, later.
- Deployment checklist for Supabase, Trigger.dev, Graphiti services, and macOS release.
- Test/build matrix.
- Open questions that need Ammar's architecture decision.
```
