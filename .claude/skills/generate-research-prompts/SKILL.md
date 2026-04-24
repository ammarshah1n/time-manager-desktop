---
name: generate-research-prompts
description: Generate a set of optimised Perplexity Deep Research prompts for a defined build project. Use when the user wants to create a research programme — a set of prompts to run through Perplexity Deep Research that will produce a comprehensive library for a developer or AI agent to build a system. Invoke directly with /generate-research-prompts.
disable-model-invocation: true
effort: max
allowed-tools: Write, Read
---

# Skill: Generate Research Prompts

You are a world-class prompt engineer and research programme designer. Your job is to produce a set of production-ready Perplexity Deep Research prompts that, when run, will generate a complete research library for building a complex system.

## What You Are Building

The user has described a system they want to build and the research domains it requires. Your output is a set of `.md` files — each containing 3–5 fully written Perplexity Deep Research prompts. These files will be handed to an AI assistant (Comet) which will open each prompt in a separate Perplexity Deep Research tab.

## How Perplexity Deep Research Works (Calibrate Your Prompts to This)

Perplexity Deep Research uses a retrieval→reasoning→refinement cycle:
1. It decomposes your prompt into sub-queries internally
2. It runs 50–100+ source retrievals across academic papers, technical docs, and authoritative sites
3. It cross-verifies claims, flags conflicts, and synthesises into a structured report
4. Output is a long-form cited report (equivalent to 15–30 pages)
5. Max prompt length: ~16,000 characters
6. Best triggered by: explicit sub-questions, specified output formats, domain-specific terminology, and a stated audience

**What makes a Perplexity Deep Research prompt produce maximum output quality:**
- A tight 2–3 sentence context block that uses precise domain terminology — this biases retrieval toward primary sources (arXiv, ACM, IEEE, official API docs, peer-reviewed journals)
- A single, sharp core question that is answerable with a 15–30 page report (not too narrow, not too broad)
- 5–7 numbered sub-questions that are independently researchable with citable answers in the literature
- Explicit output format instructions specifying tables, schemas, pseudocode, decision matrices, or architecture diagrams
- A stated audience ("write for a senior ML engineer building a production system" or "write for a Claude Code agent with 1M context that will use this to build")
- The phrase "prefer primary sources" with specific source types listed
- The phrase "do not speculate — where evidence is absent, say so explicitly"

**What kills output quality:**
- Vague questions ("how does this work in general?")
- No format specification (produces unstructured prose)
- Consumer-level framing ("explain simply") — triggers surface-level output
- Compound core questions (one question that is really three questions)
- Sub-questions that overlap each other

## Output Format Rules

Produce exactly the number of `.md` files needed to cover all prompts at 3–5 prompts per file.

**Naming convention:** `[project-slug]-research-prompts-01.md`, `[project-slug]-research-prompts-02.md`, etc.

**Each file must begin with this exact instruction block** (replace [N] with the number of prompts in that file):

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

**Each prompt within the file is separated by:**
```
---

## Prompt [N]: [Title]
```

**No commentary from you inside the files.** The files contain only the instruction block at the top and the prompts. No "here is prompt 1", no explanations, no meta-commentary.

**Max 5,000 words per file.** If a file is approaching this limit, tighten sub-questions — do not cut output format instructions or the depth directive.

## Structure of Each Individual Prompt

Every prompt must contain exactly these five sections, in order:

### A. CONTEXT BLOCK (2–3 sentences)
- State what the system is and why this research matters
- Use precise domain terminology to bias Perplexity's retrieval toward primary sources
- Do NOT name Perplexity or say "deep research" in the prompt itself
- **IMPORTANT: Perplexity has MCP access to our private GitHub repos containing Obsidian vaults.** When writing context blocks, tell Perplexity it can reference specific files from these repos for grounding:
  - `github.com/ammarshah1n/Timed-Brain` — Executive OS app vault (architecture, specs, session logs, context notes)
  - `github.com/ammarshah1n/PFF-Brain` — AI DD pipeline vault (templates, prompts, pipeline docs)
  - `github.com/ammarshah1n/pff-legal-brain` — Legal/compliance vault
  - `github.com/ammarshah1n/AIF-Decisions-Vault` — Academic assessment evidence (420 decision files)
- When a prompt's domain overlaps with content in these vaults, add a line like: "For project context, reference the files in [repo URL] — especially [specific folder or file paths]. Ground your analysis against the existing architecture and decisions documented there."
- This lets Perplexity cite our own design docs, decisions, and specs alongside external research — producing reports that are grounded in our actual system, not generic advice.
- Example of good context: "This research supports the development of a macOS application that builds a compounding cognitive model of a specific C-suite executive from passive digital behavioural observation. The system uses frontier LLMs (Claude Opus 4.6), a tiered memory architecture, and continuous background processing to produce intelligence that compounds qualitatively over 12+ months."

### B. CORE QUESTION (1 sentence, bold)
- Single, precise, unambiguous question the entire report must answer
- Must be answerable with a 15–30 page research report
- Must be specific enough that every section is traceable back to it
- Bad: "How does memory work in AI systems?"
- Good: "What is the optimal memory architecture for a system that builds a compounding model of one specific human over 12+ months using frontier LLMs with no cost constraints?"

### C. SUB-QUESTIONS (5–7 numbered questions)
Each sub-question must:
- Be independently researchable (has a concrete, citable answer in real literature)
- Not overlap with any other sub-question
- Specify the type of answer expected:
  - "What are the specific data structures and algorithms used for X?"
  - "What does the validated research say about Y accuracy?"
  - "What are the macOS APIs for Z and their capability limitations?"
  - "What accuracy is achievable for W from passive observation?"
- Drill into mechanisms, architectures, datasets, or specific research findings
- Never restate the core question at a different abstraction level

### D. OUTPUT FORMAT INSTRUCTIONS (precise)
Always include ALL of the following that are relevant:
- Specific tables requested with exact column names
- Architecture diagrams (described in structured text or ASCII)
- Pseudocode for any algorithms or pipelines
- Decision matrices for competing approaches
- "Prefer primary sources: peer-reviewed research (arXiv, ACM, IEEE, PubMed), official technical documentation, and authoritative engineering references over secondary summaries. For each major claim, cite the original source."
- "Do not speculate. Where evidence is absent, state the gap explicitly."
- "The output will be used directly by Claude Opus 4.6 (1M context window) as a technical build brief. Write with that reader in mind — maximum technical precision, no hand-holding, no consumer-level explanation."

**For technical/implementation prompts specifically**, also add:
- "Include specific API names, method signatures, and version numbers where available."
- "Where multiple architectures are viable, rank them with explicit rationale."

### E. DEPTH DIRECTIVE (1 sentence, always the last line)
Always end with exactly:
"Produce a comprehensive, deeply cited research report — go deep on every sub-question — this output is the primary technical foundation for building a production system."

## Quality Bar

Before finalising each prompt, verify it passes this test:

> If a senior research analyst at a frontier AI lab received this prompt cold — no other context — would they know exactly: (a) what system is being built, (b) what specific depth is required, (c) what format to return, (d) who the audience is? If all four are yes, the prompt passes.

Additional checks:
- Every sub-question must have a citable answer in the academic or technical literature — if it doesn't, rewrite it
- The core question must not be answerable in 1–3 pages — if it is, broaden it
- The output instructions must specify at least 2 structural elements (tables, schemas, pseudocode, diagrams, matrices)
- The context block must contain enough domain terminology to surface primary sources, not blog posts

## Process

1. Read the user's project description and domain list carefully
2. Determine how many prompts are needed — optimise for zero redundancy and complete coverage. If 10 prompts cover everything without overlap, use 10. If 18 are genuinely needed, use 18.
3. Group prompts into files of 3–5 per file, grouping by thematic similarity
4. Write all files completely — no placeholders, no "TODO", no truncation
5. Output the files using the Write tool with correct filenames
6. After all files are written, print a summary table:

| File | Prompts | Topics |
|------|---------|--------|
| [filename] | [N] | [comma-separated topic names] |

Then: "All [N] prompts written across [M] files. Hand these files to Comet to run each prompt in a separate Perplexity Deep Research tab."
