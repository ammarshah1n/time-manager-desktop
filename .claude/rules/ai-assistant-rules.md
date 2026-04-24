# AI Assistant Rules

<important>
## Anti-Patterns
- NEVER suggest cheaper models for the core intelligence engine. Intelligence quality IS the product.
- NEVER revert to cost-optimisation / SaaS margin framing.
- NEVER have Timed act on the world. Timed observes, reflects, and recommends — nothing else. No sending email, no CCs, no "delegations on your behalf", no booking, no scheduling, no contacting anyone. Audit every prompt against this list before shipping.
- NEVER skip the read order. Always verify infra state with CLI before trusting docs.
- NEVER treat `DataStore` as the source of truth. Supabase is the source of truth once Auth lands.
</important>

<important>
## UI Surface Rules
- Any new user-facing setup / onboarding / capture / interview flow STARTS from an orb-led voice experience. Form-based flows with typed fields and click-through wizards are a regression. Only reach for a form if voice literally cannot capture the input (e.g., OAuth redirect, file upload).
- The IntroView 72pt display type is for the cinematic intro only. Panes seen every session use the 28pt headline / body scale — calm over loud.
</important>

<important>
## Model Routing Discipline
- Match model + thinking budget to task complexity per call site. Defaults:
  - Structured extraction, classification, short conversational turns → Haiku 4.5, no thinking
  - Multi-step conversational flow with ≥3 collected fields → Haiku is brittle; use Sonnet
  - Real reasoning (Dish Me Up, morning check-in, weekly synthesis) → Opus 4.6 with extended thinking, budget 4000–10000
- `max_tokens` must exceed `thinking.budget_tokens` — otherwise Anthropic returns 400.
- Prompt caching needs ≥1024 tokens on Opus/Sonnet system prompts (≥4096 on Haiku). Smaller prompts silently skip the cache — don't panic on zero cache hits during cold-start.
</important>

<important>
## Tool Dispatch for Timed Tasks
- Implementation: self-execute (default for all sizes).
- Review / diagnosis of a completed diff: Codex via `codex:rescue` is optional.
- Architecture decisions: Ammar decides, Claude writes within constraints. Never hand architecture to Codex.
</important>
