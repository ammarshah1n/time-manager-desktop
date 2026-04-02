---
tags: [decisions, human-evidence, chat-log, aif]
created: 2026-03-29
source-files:
  - Downloads/How do proffesionals plan an app after being given.md
  - Downloads/_Go to portal.azure.com, create a new App Registra.md
---

# Perplexity Chat Decisions — Human Evidence Log

Extracted from two Perplexity Comet chat transcripts. All entries are Ammar's inputs only — prompts, decisions, corrections, and steering moments.

---

## File 1: `How do proffesionals plan an app after being given.md`

---

**[PROMPT]**
> Ammar said: "How do professionals plan an app after being given a 30 minute long voice recording with an idea from someone, this is a time management app and it has a comprehensive list of the things it must achieve and I am wondering where to even start in terms of planning the build of this, is Claude optimal for this?"
Context: Opening question — Ammar had a raw voice recording from a client/user and was figuring out how to convert it into a buildable plan.
Decision type: PROBLEM-SOLVING

---

**[CHAT-DECISION]**
> Ammar said: "Is Opus 4.6 thinking the best for PRDs, what do people online use"
Context: After receiving the planning workflow, Ammar narrowed to a specific model selection question — evaluating whether to use extended thinking mode vs standard Opus, and what the community actually does.
Decision type: TOOL

---

**[CHAT-DECISION]**
> Ammar said: "What is the best prompt or skill online for making PRDs, crawl through Reddits and forums and GitHub etc and just overall experts to find how to make the best PRD from raw transcripts"
Context: Ammar directed the AI to do a web crawl for community-validated PRD prompts rather than accepting the generic advice given — wanted battle-tested prompts specifically for raw transcripts.
Decision type: PROBLEM-SOLVING

---

**[PROMPT]**
> Ammar said: [Pastes the full 30-minute voice recording transcript — client monologue about email triage, time-boxing, "Dish Me Up" planning engine, SaneBox, tasks, WhatsApp, transit work, PA collaboration, etc.] "Run all of those against this transcript"
Context: Ammar fed the actual client voice transcript into the AI after researching optimal PRD extraction prompts — executing the pipeline he had just learned.
Decision type: ARCHITECTURAL

---

**[CHAT-DECISION]**
> Ammar said: "Outlook is the provider, and we will use Action and just Read for now with subfolders, but I need you to make sure the core of this is not lost with the PRD"
Context: After receiving the extracted PRD, Ammar made two concrete decisions — locking Outlook/Microsoft Graph as the email backend, choosing the Action/Read taxonomy over P1/P2 — and explicitly flagged that the "Dish Me Up" core must not be diluted.
Decision type: ARCHITECTURAL

---

**[CHAT-DECISION]**
> Ammar said: "Give me the file to download"
Context: Ammar closed the PRD session by requesting downloadable artifacts rather than leaving work in chat — treating the output as a document to move into the build pipeline.
Decision type: PROBLEM-SOLVING

---

**[PROMPT]**
> Ammar said: "Is Supabase the right tool for this, is it what pros use when making startups"
Context: After locking the email stack, Ammar independently questioned the backend choice — checking whether Supabase was the right call for this specific app before committing.
Decision type: ARCHITECTURAL

---

## File 2: `_Go to portal.azure.com, create a new App Registra.md`

---

**[PROMPT]**
> Ammar said: "Go to portal.azure.com, create a new App Registration called TimeBlock, set redirect URI to msauth.com.timeblock.app://auth, add Mail.ReadWrite and offline_access permissions, then copy the Client ID and Tenant ID into a note for me."
Context: Ammar wrote a Comet browser automation command — showing he already knew the exact Azure configuration required for Microsoft Graph OAuth and delegated it to an agent rather than doing it manually.
Decision type: TOOL

---

**[CHAT-DECISION]**
> Ammar said: "Call it Timed"
Context: After initiating the Azure App Registration with the name "TimeBlock," Ammar immediately corrected the name to "Timed" — a product naming decision made in the moment.
Decision type: BUSINESS

---

**[CHAT-DECISION]**
> Ammar said: "Do I make a new Microsoft account for this project, use my Gmail or what's the go?"
Context: Ammar questioned whether to create a new account or reuse existing credentials — evaluating account hygiene and separation of concerns for a production app registration.
Decision type: TOOL

---

**[CHAT-DECISION]**
> Ammar said: "Will do this after."
Context: After receiving Azure account setup instructions, Ammar explicitly deferred the task — a prioritisation call to continue building the repo before setting up external services.
Decision type: BUSINESS

---

**[PROMPT]**
> Ammar said: "I need you to assess how well it will currently smash Codex, give me a prompt to give it in terms of agents and work and stuff to assess it holistically and if it's not to the best extent then we can install things like sub-agent things or something like that or will the task manager thing already do that?"
Context: After completing the taskflow build, Ammar wanted an objective measure of how well the repo was configured for Codex autonomous execution — showing awareness that "building stuff" and "building stuff Codex can run" are different problems.
Decision type: ARCHITECTURAL

---

**[CHAT-DECISION]**
> Ammar said: "I'm assessing Claude's ability to use Codex to the fullest ability, and as a result of that it involved Codex's capability and Claude's ability to use it. Find a way to measure this and improve it and judge it and assess it and make it tangible"
Context: Ammar reframed the previous question — he wasn't just asking about Codex quality, he wanted to measure the entire Claude→Codex pipeline as a system, and make that measurement tangible/scoreable.
Decision type: PROBLEM-SOLVING

---

**[CHAT-DECISION]**
> Ammar said: "Yeah give me everything to give to Claude to do in another window so it can measure all of this and then it can, we can optimise it"
Context: Ammar chose to run the CEQS assessment in a parallel Claude window rather than inline — a deliberate parallel execution decision to avoid blocking the current session.
Decision type: TOOL

---

**[CHAT-DECISION]**
> Ammar said: "While that is running what else can I optimise?"
Context: Instead of waiting for the CEQS assessment to return, Ammar asked for parallel tasks — explicitly seeking to eliminate idle time during the assessment run.
Decision type: PROBLEM-SOLVING

---

**[CHAT-DECISION]**
> Ammar said: "Give me whatever MD files you want me to give to Claude, but make sure they don't clash with the other prompts I'm giving it"
Context: Ammar accepted the AI's suggestion to create `codex.md` and FR spec files, but added a constraint — the files must not interfere with the parallel CEQS assessment prompt already running.
Decision type: TOOL

---

**[CHAT-DECISION]**
> Ammar said: "Now the full report."
Context: After the parallel CEQS assessment completed, Ammar requested the full report in the current window — consolidating the results rather than acting on partial information.
Decision type: PROBLEM-SOLVING

---

## Cross-File Patterns

The following recurring decision patterns appear across both transcripts:

- **Plan before building** — Ammar consistently researched workflows, validated tools, and resolved ambiguity before executing (PRD pipeline research → transcript → PRD; CEQS framework → assessment → fixes)
- **Name things deliberately** — "TimeBlock" → "Timed" mid-session shows Ammar treating naming as a real decision, not a placeholder
- **Parallel execution** — Ammar twice ran separate Claude windows in parallel to avoid blocking the main session
- **Constraint injection** — When accepting AI suggestions, Ammar added constraints ("don't clash with the other prompts", "make sure the core is not lost")
- **Defer non-blocking tasks** — Azure setup deferred to dead time; email extraction deferred until data access was resolved
- **Validate before committing** — Querying Supabase, model selection, account type all treated as research questions before architectural commitment
