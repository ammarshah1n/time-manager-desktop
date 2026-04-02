# 07 — Data Models

## Current Domain Models

### Task Models (defined in PreviewData.swift — should move to Core/Models/)

```swift
struct TimedTask {
    id, title, sender, estimatedMinutes, bucket, emailCount, receivedAt,
    priority, replyMedium, dueToday, isDoFirst, isTransitSafe, waitingOn,
    askedDate, expectedByDate, isDone, estimateUncertainty, planScore,
    scheduledStartTime
}

enum TaskBucket { reply, action, calls, readToday, readThisWeek, transit, waiting, ccFyi }
enum ReplyMedium { email, whatsApp, other }
```

### Triage Models
```swift
struct TriageItem { id, sender, subject, preview, receivedAt, emailMessageId,
    classificationConfidence, classifiedBucket }
```

### Other Domain Models
```swift
struct WOOItem { id, contact, description, category, askedDate, expectedByDate, hasReplied }
struct CaptureItem { id, inputType, rawText, parsedTitle, suggestedBucket, suggestedMinutes, capturedAt, isConverted }
struct CalendarBlock { id, title, start, end, category: BlockCategory }
struct EmailMessage { id, subject, sender, receivedAt, body, isRead }
struct BucketEstimate { bucket, meanMinutes, sampleCount, lastUpdatedAt }
struct CompletionRecord { id, taskId, bucket, estimatedMinutes, actualMinutes, completedAt }
struct FocusSessionRecord { id, taskId, taskTitle, bucket, startedAt, durationSeconds, wasCompleted }
```

### Planning Types (in PlanningEngine.swift)
```swift
struct PlanRequest, PlanTask, PlanItem, PlanResult, ScoreBreakdown, MoodContext
enum BehaviourRule { ordering, timing }
```

### Allocator Types (in TimeSlotAllocator.swift)
```swift
struct TimeSlot, ScheduleConfig, SlotAssignment, AllocationResult
struct SlotTaskInput, RepairResult, RepairNotification
enum DisruptionType
```

### Supabase Row Types (in SupabaseClient.swift)
```swift
// 14 row types for database mapping
TaskDBRow, EmailMessageRow, TriageCorrectionRow, DailyPlanRow,
PlanItemDBRow, BehaviourRuleRow, SenderRuleRow, VoiceCaptureRow,
WaitingItemRow, PipelineRunRow, BucketCompletionStat, SenderLatencyRow,
BehaviourEventInsert, WorkspaceMemberRow
```

## New Models Required (Intelligence Core)

### Memory Models
See docs/02-memory-system.md for full schemas.

```swift
// Layer 2: Memory Store
struct EpisodicMemory        // raw timestamped observations
struct SemanticFact           // distilled facts about the person
struct ProceduralRule         // operating rules from pattern analysis
struct CoreMemorySnapshot     // always-in-context essential facts

// Enums
enum SignalSource             // .email, .calendar, .voice, .behaviour, .task
enum MemoryCategory           // .communication, .work, .meeting, .avoidance, .decision
enum SemanticCategory         // .chronotype, .relationship, .preference, .capacity, .pattern
```

### Signal Models
```swift
struct SignalEvent             // raw signal from any ingestion source
struct BehaviourSignal         // app usage, focus patterns, response timing
```

### Reflection Models
```swift
struct Pattern                 // first-order pattern from episodic analysis
struct Insight                 // second-order synthesis from patterns
struct ReflectionResult        // output of a full reflection cycle
struct MorningBriefing         // structured morning session content
struct ProactiveAlert          // time-sensitive intelligence alert
```

### Intelligence Models
```swift
struct ChronotypeProfile       // personal circadian performance curve
struct RelationshipHealthScore // per-contact relationship assessment
struct CognitiveLoadState      // current cognitive load estimate
struct AvoidanceSignature      // pattern of avoidance for task/category
struct IntelligenceResponse    // response to executive query
```

### Retrieval Models
```swift
struct RetrievalQuery          // query with context for dynamic weight adjustment
struct ScoredMemory            // memory with retrieval score
enum RetrievalContext          // .morningBriefing, .patternReport, .specificQuery, .avoidanceCheck
```

## Model Migration Plan

1. Extract all domain models from PreviewData.swift → Sources/Core/Models/
2. Add memory tier models (EpisodicMemory, SemanticFact, ProceduralRule)
3. Add signal models (SignalEvent, BehaviourSignal)
4. Add reflection output models (Pattern, Insight, ReflectionResult)
5. Add intelligence models (ChronotypeProfile, etc.)
6. Add retrieval models (RetrievalQuery, ScoredMemory)
7. Add Supabase row types for all new models
