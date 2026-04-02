# 03 — ML Models Specification

## Overview

All ML/scoring models in Timed. These exist in Layer 3 (Reflection Engine)
but are used by Layer 4 (Delivery) for plan generation and intelligence output.

## 1. Thompson Sampling — Task Scoring

**Location:** PlanningEngine.swift
**Status:** ✅ Implemented, 22 tests passing

Composite scoring with Beta-distribution sampling:
- Bucket type base score
- Priority weight
- Duration penalty (adaptive to session length)
- Overdue bump (1000, capped at top 3)
- Deadline proximity (500/200/100)
- Quick win bump (150 for ≤5min)
- Mood modifiers (easy wins, avoidance, deep focus)
- Behavioural rule ordering (300 × confidence)
- Timing rules (200/-100 × confidence)
- Thompson sampling (Beta(α, β) via Box-Muller, up to 250)
- Work-hour penalty (-400 outside window)

Requires 10+ samples per bucket to activate Thompson sampling.

## 2. EMA Time Estimation

**Location:** BucketEstimate model + InsightsEngine.swift
**Status:** ✅ Implemented (minimal)

Exponential moving average of actual vs estimated duration per bucket.
BucketEstimate tracks: meanMinutes, sampleCount, lastUpdatedAt.

InsightsEngine compares estimates to actuals, flags deviations >3 minutes.

## 3. TimeSlot Allocator — Energy-Aware Scheduling

**Location:** TimeSlotAllocator.swift
**Status:** ✅ Implemented (612 lines)

Calendar-aware slot allocation:
- Gap extraction from Outlook calendar
- Energy-tier matching: 8-12 high, 12-15 medium, 15+ low
- Pre/post meeting buffers
- Utilization cap at 75%
- Incremental repair for disruptions (meeting overrun, urgent insert, task ran long)

## 4. Reply Latency Social Graph

**Location:** EmailSyncService.swift
**Status:** ✅ Implemented

Tracks outbound reply latency per sender:
- < 2min = importance 1.0
- < 10min = importance 0.8
- < 60min = importance 0.5
- > 60min = importance 0.2

Feeds into relationship health scoring (future).

## 5. Sender Rule Learning

**Location:** EmailSyncService.swift
**Status:** ✅ Implemented

Detects Outlook folder moves → auto-creates sender rules:
- black_hole, inbox_always, later, delegate

## 6. Chronotype Inference (TO BUILD)

**Status:** ❌ Not started

Infer executive's circadian performance curve from:
- Task completion speed × time-of-day correlation
- Email response latency × time-of-day
- Focus session quality × time-of-day

Outputs: ChronotypeProfile with peak analytical, creative, interpersonal windows.

## 7. Avoidance Pattern Detection (TO BUILD)

**Status:** ❌ Not started

Detect avoidance vs deprioritisation from behavioural signals:
- Tasks that recur without completion
- Draft-and-delete patterns
- Deferral-without-explanation patterns
- Time between task appearance and first interaction

Output: AvoidanceSignature per task/category with historical context.

## 8. Cognitive Load Estimation (TO BUILD)

**Status:** ❌ Not started

Real-time proxy for cognitive load from:
- Email open-to-response latency
- App-switch frequency
- Meeting density in last N hours
- Draft deletion frequency

Output: CognitiveLoadState (low/moderate/high/overloaded) for scheduling decisions.

## 9. Relationship Health Scoring (TO BUILD)

**Status:** ❌ Not started

Built on reply latency social graph + email metadata:
- Response time trends per person
- Email length trends per person
- Meeting frequency changes
- Tone shifts (via Haiku classification)
- Attention allocation (fast replies vs slow)

Output: RelationshipHealthScore per key contact with trend direction.
