# AI Assistant Rules

<important>
## Anti-Patterns
- NEVER suggest cheaper models for the core intelligence engine. Intelligence quality IS the product.
- NEVER revert to cost-optimisation / SaaS margin framing.
- NEVER have Timed act on the world (send email, modify calendar) without explicit user approval.
- NEVER skip the read order. Always verify infra state with CLI before trusting docs.
- NEVER treat `DataStore` as the source of truth. Supabase is the source of truth once Auth lands.
</important>

<important>
## Tool Dispatch for Timed Tasks
- 3+ files to edit -> fire `codex:codex-rescue`, do not self-execute
- Tests -> fire `codex:codex-rescue`
- Architecture decisions -> Claude reasons, then Codex executes within constraints
- Single-file targeted edits -> self-execute
</important>
