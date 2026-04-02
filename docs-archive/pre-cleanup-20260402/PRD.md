# Product Requirements Document

## Product Name
Timed

## Purpose
Build a personal desktop time-management system for a school student that turns scattered work into a clear, ranked, time-boxed plan. It must load context efficiently from class transcripts, Seqta, TickTick, and personal chat, then help decide what matters most right now and what should happen next.

## Problem Statement
The user has work spread across school, personal projects, and life admin. Tasks live in different places, context is fragmented, and planning time is wasted deciding what to do instead of doing it. The product must reduce cognitive load, improve prioritisation, and make study sessions more deliberate and efficient.

## Goals
- Centralise tasks and context in one desktop-first planning surface.
- Rank work by urgency, importance, confidence, effort, and deadline pressure.
- Turn ranked work into realistic time blocks.
- Load relevant study context quickly when the user is quizzed or needs to revise.
- Keep TickTick, Seqta, transcripts, and chat history usable inside one planning workflow.
- Sync approved time blocks outward to iPhone through calendar-based sync.
- Present everything in a clean Apple-style liquid-glass UI.

## Non-Goals
- Do not build a website-first experience.
- Do not make the website the source of truth.
- Do not force the user into manual, repetitive planning steps.
- Do not require live cloud dependence for the core workflow.
- Do not make the first version a mobile app.

## Target User
- A high-performing school student who studies multiple subjects, manages deadlines, and wants a single place to decide what to work on next.

## Core Use Cases
1. The user asks what to do now and receives a ranked plan.
2. The user pastes or imports a transcript and asks for subject-specific help.
3. The user imports Seqta tasks and turns them into schedule blocks.
4. The user imports TickTick tasks and uses them inside the same prioritisation system.
5. The user chats with the system about work and uses that dialogue as planning context.
6. The user exports approved blocks to a calendar so the plan reaches iPhone.

## Product Principles
- Planner first.
- Context second.
- Desktop first.
- Local-first by default.
- Recommend before automating.
- Keep friction low.
- Make the plan visible, not hidden.

## Functional Requirements

### 1. Task Aggregation
- Import tasks from TickTick.
- Import school work from Seqta.
- Accept user-added tasks manually.
- Keep personal chat items as task signals when relevant.
- Store task metadata such as subject, estimate, deadline, source, importance, and confidence.

### 2. Context Loading
- Ingest class transcripts.
- Store and retrieve context by subject, topic, and source.
- Use chat history as durable personal context.
- Surface only the most relevant context for the current prompt or subject.

### 3. Urgency Scoring
The system must rank tasks using a weighted urgency model. At minimum, it should consider:
- Deadline proximity.
- Task importance.
- Confidence in the topic.
- Estimated effort.
- Source type.
- Subject pressure.
- Dependency risk.
- Batchability.
- Current workload.
- User intent from the latest prompt.

### 4. Time Boxing
- Turn ranked tasks into realistic study blocks.
- Prefer blocks that match the subject’s required energy level.
- Allow the user to review and approve suggested blocks.
- Produce a clear next-3-hours style plan when asked.

### 5. Promptable Interaction
- Let the user ask:
  - What should I do now?
  - Rank my tasks.
  - Plan my next 3 hours.
  - Quiz me on English.
  - Load my Maths context.
  - What is most urgent?
- Return concise, actionable answers.
- Use stored context and task state in responses.

### 6. Calendar and iPhone Sync
- Export approved time boxes to a calendar format.
- Keep the calendar output compatible with iPhone use through the user’s calendar ecosystem.
- Treat calendar export as the first sync path.

### 7. UI and Interaction
- Desktop app only.
- Apple-style design language.
- Liquid-glass surfaces.
- Sleek, elegant, minimal chrome.
- Clear rankings and obvious time boxes.
- Fast access to sources, ranked plan, and context.

## Scoring Model
The ranking engine should produce a single urgency score per task from a weighted matrix.

Recommended factor groups:
- Deadline pressure
- Importance
- Confidence gap
- Time required
- Source reliability
- Subject load
- Current prompt intent
- Dependency risk
- Batching opportunity
- Recency of related context

The model should output:
- Score
- Rank band
- Reason list
- Suggested next action

## Data Model Requirements
Each task should support:
- ID
- Title
- Source
- List or category
- Subject
- Estimate in minutes
- Confidence level
- Importance level
- Deadline
- Notes
- Energy requirement

Each context item should support:
- ID
- Title
- Source type
- Subject
- Summary
- Full detail or transcript text

Each schedule block should support:
- ID
- Title
- Start time
- End time
- Reason for inclusion

## UX Requirements
- The first screen should show the plan, not empty onboarding.
- The most urgent tasks must be visually obvious.
- The context panel must be available alongside the plan.
- The user should be able to input a prompt without navigating away.
- The interface should feel like a calm, high-end desktop planning workstation.
- Use Apple-like translucency, blur, spacing, and typography.

## Privacy and Storage
- Store data locally by default.
- Keep transcripts, task data, and chat context private.
- Cloud APIs are allowed only as helpers where needed.
- Avoid making the core workflow dependent on remote services.

## Performance Requirements
- Prompt response should feel immediate.
- Context retrieval should be fast enough for live study sessions.
- Ranking should complete in under a second for normal personal workloads.
- The app should launch quickly and remain responsive while switching between tasks and context.

## Quality Requirements
- The app should be usable without internet for the core local workflow.
- The ranking output should be explainable.
- Calendar export should be reliable and predictable.
- Imported data should not overwrite unrelated state.
- The app should support repeated daily use without reconfiguration.

## Success Criteria
- The user can open the desktop app and immediately see a useful ranked plan.
- The user can ask for help and get the right subject context quickly.
- The user can turn school and personal tasks into schedule blocks without manual spreadsheet-style work.
- The user can keep TickTick, Seqta, transcripts, and chat context in one planning loop.
- The user can export a plan to calendar and use it on iPhone.

## Phased Scope

### Phase 1
- Desktop app shell.
- Local task storage.
- Manual imports.
- Urgency ranking.
- Time boxing.
- Calendar export.

### Phase 2
- Better transcript ingestion.
- Better Seqta ingestion.
- Better TickTick sync.
- Stronger context retrieval.
- Subject-aware quiz prompts.

### Phase 3
- Smarter scheduling feedback loops.
- Deeper iPhone/calendar sync.
- Improved prompt memory and planning refinement.
- Ongoing tuning of the ranking matrix.

## Open Questions
- Should TickTick be one-way import or two-way sync?
- Should calendar export go to Apple Calendar only or also other calendars?
- What are the exact weighting values for the urgency matrix?
- What is the minimum acceptable transcript chunk size for context retrieval?
- Which parts of the plan should be auto-generated versus user-approved?

