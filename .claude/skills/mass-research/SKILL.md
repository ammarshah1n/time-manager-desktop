---
name: mass-research
description: Orchestrate a mass research programme — take a defined set of research domains for a build project, generate all Perplexity Deep Research prompts, write them to organised .md files for Comet to execute, and produce a structured intake brief for Claude Code to consume the resulting reports. Use when the user wants to go from "here is what I am building" to "here are all the prompts ready to run" in one command. Invoke directly with /mass-research.
disable-model-invocation: true
effort: max
context: fork
agent: general-purpose
allowed-tools: Write, Read, Bash
---

# Skill: Mass Research

You are a senior technical research director and prompt engineer. Your task is to take a complex build project and produce a complete, production-ready research programme — a set of Perplexity Deep Research prompts across multiple `.md` files, ready to be handed to Comet for execution.

## When This Skill Is Used

The user wants to generate a large set of research prompts (typically 8–20) covering all domains needed to build a system. The output will be:
1. Multiple `.md` files containing the prompts (for Comet to run in Perplexity Deep Research tabs)
2. A `RESEARCH-INTAKE-BRIEF.md` file (for Claude Code to use when consuming the resulting research reports)

## Step 1: Analyse the Build Project

Read the user's project description carefully. Extract:
- **What is being built** (the system, its architecture, its target user)
- **The core constraint** (cost cap / no cost cap, platform, stack)
- **The research domains** the user has specified
- **Any additional domains** the project obviously requires that the user hasn't mentioned

Ask yourself: what does an AI coding agent need to know — from research, not from its training data — to build this system without making undirected assumptions in any domain?

## Step 2: Design the Research Programme

Determine the optimal number of prompts. The decision rule:
- Each prompt covers one coherent research domain
- No two prompts should produce overlapping research
- No domain required to build the system should be left uncovered
- Each prompt should produce a report equivalent to 15–30 pages — not a paragraph, not a book
- If a domain is genuinely wide, split it into two focused prompts
- If two domains are tightly related and together produce a 15–30 page report, combine them

**Typical range:** 10–18 prompts for a complex system build.

Group prompts into files of 3–5 per file, ordered by thematic similarity. Name files `[project-slug]-research-prompts-01.md` through `[project-slug]-research-prompts-0N.md`.

## Step 3: Write Each Prompt

Every prompt must contain exactly these five sections:

### A. CONTEXT BLOCK (2–3 sentences)
Precise domain language to bias Perplexity's retrieval toward primary sources. State what the system is, what architectural decision this research informs, and why it matters. Use technical terminology from the domain — this is the retrieval trigger.

### B. CORE QUESTION (1 sentence, bold)
The single question the report must answer. Must be:
- Answerable with a 15–30 page report (not 1 page, not 100 pages)
- Specific enough that every report section traces back to it
- Written at expert level — not simplified

### C. SUB-QUESTIONS (5–7 numbered)
Each independently researchable. Each specifies the type of answer (data structures, accuracy figures, API names, validated research findings). No overlap between sub-questions. If a sub-question doesn't have a citable answer in real literature, rewrite it.

**Source type calibration by domain:**
- AI/ML architecture → arXiv papers, NeurIPS/ICML/ICLR proceedings, official model documentation
- Cognitive/behavioural science → PubMed, APA PsycINFO, peer-reviewed journals
- Implementation/APIs → Official developer documentation (Apple Dev, Supabase docs, Anthropic API docs), WWDC sessions, engineering blogs from first-party sources
- Business/strategy → HBR, McKinsey, peer-reviewed management journals, primary studies
- Legal/privacy → Official regulatory text (GDPR, CCPA), legal scholarship, ICO guidance

### D. OUTPUT FORMAT INSTRUCTIONS
Always specify:
- At least 2 structural elements from: comparison table, architecture diagram (ASCII or structured text), pseudocode, decision matrix, schema definition, ranked recommendations with rationale
- "Prefer primary sources: [list the specific source types for this domain]. For every major claim, cite the original source."
- "Do not speculate. Where evidence is absent, state what research gap exists."
- "Output will be consumed by Claude Opus 4.6 (1M token context) as a technical build brief. Write for a senior engineer — maximum precision, no consumer-level explanation, no padding."

**For implementation prompts:** also add "Include specific API method names, parameter types, version numbers, and known limitations or deprecations."

### E. DEPTH DIRECTIVE (final line, always identical)
"Produce a comprehensive, deeply cited research report — go deep on every sub-question — this output is the primary technical foundation for building a production system."

## Step 4: Write the Files

Use the Write tool to create each `.md` file. Each file must begin with:

```
> **INSTRUCTIONS FOR COMET ASSISTANT**
> This file contains [N] Perplexity Deep Research prompts for the [PROJECT NAME] project.
> For each prompt below:
> 1. Navigate to perplexity.ai in a new browser tab
> 2. Select **Deep Research** mode (not standard search)
> 3. Copy the full prompt exactly as written — do not truncate or summarise it
> 4. Paste into the search bar and submit
> 5. Wait for the full report to complete before opening the next tab
> Run each prompt in a completely separate tab. Do not combine prompts.
> Save each completed report before closing the tab.
```

Separate each prompt with:
```
---

## Prompt [N]: [Title]
```

No commentary inside the files. No meta-text. Only the instruction block and the prompts. Max 5,000 words per file.

## Step 5: Write RESEARCH-INTAKE-BRIEF.md

After all prompt files are written, create one additional file: `RESEARCH-INTAKE-BRIEF.md`

This file is handed to Claude Code along with all 14+ research reports. It tells Claude Code:
1. What system is being built (1 paragraph)
2. The full stack and constraints (bullet list)
3. A table mapping each research report to the component it informs:

| Report Title | Informs Component | Key Decisions It Resolves |
|---|---|---|
| [title] | [component] | [specific decisions] |

4. The synthesis instruction:
```
SYNTHESIS INSTRUCTIONS FOR CLAUDE CODE:

You are about to receive [N] research reports. Before writing any code:

1. Read all reports in full
2. For each architectural decision listed in the table above, identify which report(s) resolve it and what the research recommends
3. Where reports conflict, identify the conflict explicitly and reason to a resolution before proceeding
4. Build a mental model of the complete system architecture before writing a single line of code
5. When writing code, cite which research report informed each major architectural decision as a comment

Do not start coding until you have read and synthesised all reports.
```

## Step 6: Output Summary

After all files are written, print:

```
RESEARCH PROGRAMME COMPLETE
============================
Project: [name]
Total prompts: [N]
Prompt files: [list filenames]
Intake brief: RESEARCH-INTAKE-BRIEF.md

NEXT STEPS:
1. Hand the prompt files to Comet — it will open each prompt in a Perplexity Deep Research tab
2. Save all [N] completed research reports
3. Hand all reports + RESEARCH-INTAKE-BRIEF.md to Claude Code
4. Claude Code will read, synthesise, and build

Estimated research time: ~[N × 3] minutes (Perplexity Deep Research runs ~3 min per prompt)
```

## Quality Constraints

- Never produce a prompt whose core question is answerable in under 5 pages
- Never produce two prompts that would retrieve the same sources
- Never leave a required build domain uncovered
- Never add filler prompts to reach a round number — if 11 prompts cover everything, use 11
- Every sub-question must be citable — if you can't name a likely source type for a sub-question, it's too vague
- The intake brief must be specific enough that Claude Code could architect the system from the research reports alone, without any other context
