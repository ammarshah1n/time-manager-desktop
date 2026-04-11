# Extract 13 — Swift/macOS Architecture for Continuous Executive Observation

Source: `research/perplexity-outputs/v2/v2-13-swift-macos-architecture.md`

---

## DECISIONS

### 1. Distribution: Developer ID, Non-Sandboxed (mandatory)
- AXUIElement (accessibility observation) and CGEventTap (keystroke dynamics) are architecturally incompatible with App Store sandboxing
- Developer ID signing + notarisation is the only viable path
- No entitlement restrictions on Accessibility API, Input Monitoring, or microphone access outside sandbox
- Implication: Sparkle for updates (no App Store auto-update), manual permission grants during onboarding

### 2. Background Processing: Multi-Process XPC Mesh
- Each observation modality runs in its own XPC service process: KeystrokeXPC, VoiceXPC, CalendarXPC, EmailXPC, AppUsageXPC
- Main app process is the coordinator — receives features from XPC services, manages Supabase sync, triggers Claude API calls
- If VoiceXPC crashes during Whisper inference, keystroke and calendar observation continue uninterrupted
- XPC services register as LaunchAgents for crash recovery — launchd restarts them automatically via KeepAlive
- SMAppService (macOS 13+) for login item registration — replaces deprecated SMLoginItemSetEnabled
- NOT a LaunchDaemon (those run as root, wrong privilege level for per-user observation)

### 3. Local Processing Pipeline: Extract Locally, Synthesise in Cloud
- All raw signal capture and feature extraction happens on-device — no raw audio, keystrokes, or screen content ever leaves the Mac
- Computed features (aggregates, timing metrics, sentiment scores) sync to Supabase as structured observations
- Intelligence synthesis (pattern detection, insight generation, cognitive model updates) happens via Claude API calls from Supabase Edge Functions
- Local pipeline: Combine/AsyncSequence streams → feature extractors → SwiftData/SQLite local buffer → Supabase sync actor

### 4. Email: Microsoft Graph Delta Query Over MailKit
- MailKit extensions (macOS 14-15) physically cannot read received email metadata passively — they only process compose/display actions
- Microsoft Graph delta query API returns rich metadata (sender, recipients, subject, timestamps, folder, importance, categories) without reading email bodies
- Delta sync polls only changed messages since last sync token — minimal API calls, no body content required
- Already implemented in EmailSyncService.swift — this validates the existing architecture

### 5. Voice: Whisper.cpp with Core ML Over SFSpeechRecognizer
- Whisper-small on Apple Silicon M1+ runs at 8x real-time with Core ML acceleration on Neural Engine
- Full professional/domain vocabulary accuracy — no Apple-controlled model limitations
- SFSpeechRecognizer has 10-language on-device limit, Apple controls the model, 1-minute segment limit for on-device
- Zero network transmission — all voice processing stays local
- Note: current codebase uses SFSpeechRecognizer (VoiceCaptureService.swift) — migration to Whisper.cpp needed for continuous background voice analysis

### 6. Supabase Schema: BRIN + HNSW Indexes
- BRIN indexes for all timestamp columns — 10x+ smaller than B-tree for insert-ordered time-series data
- pgvector with HNSW indexes for semantic retrieval — sub-second RAG context selection from 12 months of synthesis history
- Partitioning by month for observation tables that grow fastest (email_observations, keystroke_aggregates, app_usage_events)

### 7. Claude API: Three-Tier Model Routing
- Haiku 3.5: real-time signal classification, quick pattern matching (sub-second latency tasks)
- Sonnet: daily synthesis, pattern detection, morning brief generation
- Opus 4.6 with extended thinking: weekly/monthly deep analysis, insight generation, cognitive model evolution
- No cost cap — always route to the model tier that gives the highest intelligence quality for the task
- Extended thinking budget maximised for weekly/monthly Opus calls — this is where compounding intelligence lives

### 8. Deployment: Sparkle Framework Outside App Store
- Sparkle for auto-updates — delta updates to minimise download size
- Update installation must not interrupt observation — XPC services continue running during main app update
- Schema migrations via Supabase CLI with additive-only changes (new columns, new tables, new indexes — never drop or rename in production)
- Data continuity is non-negotiable — the cognitive model is the product

---

## DATA STRUCTURES

### Supabase Schema SQL

```sql
-- Core identity
CREATE TABLE executives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID REFERENCES auth.users(id) NOT NULL,
  display_name TEXT NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  onboarded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(auth_user_id)
);

-- Email metadata observations (no body content ever stored)
CREATE TABLE email_observations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  graph_message_id TEXT NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sender_address TEXT,
  sender_name TEXT,
  recipient_count INT,
  subject_hash TEXT,  -- SHA-256 of subject, not raw subject
  folder TEXT,
  importance TEXT,
  is_reply BOOLEAN,
  is_forward BOOLEAN,
  response_latency_seconds INT,  -- NULL if not yet responded
  thread_depth INT,
  categories TEXT[],
  UNIQUE(executive_id, graph_message_id)
);
CREATE INDEX idx_email_obs_exec_time ON email_observations
  USING BRIN (executive_id, observed_at);
CREATE INDEX idx_email_obs_sender ON email_observations (executive_id, sender_address);

-- Calendar snapshots
CREATE TABLE calendar_observations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  graph_event_id TEXT NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_start TIMESTAMPTZ NOT NULL,
  event_end TIMESTAMPTZ NOT NULL,
  is_recurring BOOLEAN,
  is_all_day BOOLEAN,
  attendee_count INT,
  organiser_is_self BOOLEAN,
  response_status TEXT,  -- accepted, tentative, declined
  category TEXT,
  free_busy_status TEXT,
  was_cancelled BOOLEAN DEFAULT FALSE,
  was_rescheduled BOOLEAN DEFAULT FALSE,
  original_start TIMESTAMPTZ,  -- non-null if rescheduled
  UNIQUE(executive_id, graph_event_id, observed_at)
);
CREATE INDEX idx_cal_obs_exec_time ON calendar_observations
  USING BRIN (executive_id, observed_at);
CREATE INDEX idx_cal_obs_event_range ON calendar_observations
  USING BRIN (executive_id, event_start);

-- Keystroke dynamics aggregates (NEVER raw keystrokes)
CREATE TABLE keystroke_aggregates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  window_end TIMESTAMPTZ NOT NULL,
  window_duration_seconds INT NOT NULL DEFAULT 300,  -- 5-min windows
  mean_inter_key_interval_ms REAL,
  std_inter_key_interval_ms REAL,
  mean_hold_duration_ms REAL,
  typing_speed_wpm REAL,
  pause_frequency REAL,  -- pauses > 2s per minute
  error_rate REAL,  -- backspace ratio
  total_keystrokes INT,
  active_app_bundle_id TEXT,
  cognitive_load_score REAL,  -- computed locally, 0.0-1.0
  UNIQUE(executive_id, window_start, active_app_bundle_id)
);
CREATE INDEX idx_keystroke_exec_time ON keystroke_aggregates
  USING BRIN (executive_id, window_start);

-- Voice features (NEVER raw audio)
CREATE TABLE voice_observations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  segment_duration_seconds REAL,
  speech_rate_wpm REAL,
  pause_frequency REAL,
  mean_pitch_hz REAL,
  pitch_variability REAL,
  vocal_energy_db REAL,
  sentiment_score REAL,  -- -1.0 to 1.0, computed on-device
  confidence REAL,
  context TEXT,  -- 'morning_session', 'meeting', 'ambient'
  transcript_summary TEXT  -- LLM-summarised, not raw transcript
);
CREATE INDEX idx_voice_exec_time ON voice_observations
  USING BRIN (executive_id, observed_at);

-- Application usage events
CREATE TABLE app_usage_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  bundle_id TEXT NOT NULL,
  app_name TEXT,
  window_title_hash TEXT,  -- SHA-256, not raw title
  focus_duration_seconds INT,
  is_foreground BOOLEAN,
  app_category TEXT  -- 'communication', 'strategic', 'operational', 'creative', 'distraction'
);
CREATE INDEX idx_app_usage_exec_time ON app_usage_events
  USING BRIN (executive_id, observed_at);
CREATE INDEX idx_app_usage_bundle ON app_usage_events (executive_id, bundle_id);

-- Daily intelligence syntheses (Sonnet output)
CREATE TABLE daily_syntheses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  synthesis_date DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  energy_curve JSONB,  -- hourly energy estimates
  focus_quality_score REAL,
  communication_pattern JSONB,
  decision_quality_indicators JSONB,
  stress_indicators JSONB,
  key_observations TEXT[],
  synthesis_text TEXT NOT NULL,  -- Sonnet's full daily narrative
  model_used TEXT NOT NULL,
  prompt_tokens INT,
  completion_tokens INT,
  embedding VECTOR(1024),  -- Jina v3 embedding for RAG retrieval
  UNIQUE(executive_id, synthesis_date)
);
CREATE INDEX idx_daily_synth_exec_date ON daily_syntheses
  USING BRIN (executive_id, synthesis_date);
CREATE INDEX idx_daily_synth_embedding ON daily_syntheses
  USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- Weekly intelligence syntheses (Opus output)
CREATE TABLE weekly_syntheses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  week_start DATE NOT NULL,
  week_end DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  pattern_detections JSONB,  -- new patterns identified
  trend_analyses JSONB,  -- multi-week trends
  burnout_risk_score REAL,
  cognitive_model_updates JSONB,  -- what changed in the model
  recommendations TEXT[],
  synthesis_text TEXT NOT NULL,
  thinking_text TEXT,  -- Opus extended thinking output
  model_used TEXT NOT NULL,
  prompt_tokens INT,
  completion_tokens INT,
  thinking_tokens INT,
  embedding VECTOR(1024),
  UNIQUE(executive_id, week_start)
);
CREATE INDEX idx_weekly_synth_exec_week ON weekly_syntheses
  USING BRIN (executive_id, week_start);
CREATE INDEX idx_weekly_synth_embedding ON weekly_syntheses
  USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- Cognitive model state (the compounding intelligence)
CREATE TABLE cognitive_model (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  version INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ DEFAULT now(),
  semantic_facts JSONB NOT NULL DEFAULT '[]',  -- extracted facts
  procedural_rules JSONB NOT NULL DEFAULT '[]',  -- operating rules
  personality_profile JSONB,  -- Big Five + work style
  communication_graph JSONB,  -- relationship patterns
  energy_model JSONB,  -- chronotype, recovery patterns
  decision_model JSONB,  -- decision speed, avoidance patterns
  model_confidence REAL DEFAULT 0.0,  -- 0.0-1.0, increases over months
  UNIQUE(executive_id, version)
);

-- System insights (proactive alerts)
CREATE TABLE insights (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  executive_id UUID REFERENCES executives(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  insight_type TEXT NOT NULL,  -- 'pattern', 'anomaly', 'recommendation', 'warning'
  severity TEXT NOT NULL DEFAULT 'info',  -- 'info', 'attention', 'urgent'
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  evidence JSONB,  -- references to observations that support this
  was_delivered BOOLEAN DEFAULT FALSE,
  delivered_at TIMESTAMPTZ,
  was_dismissed BOOLEAN DEFAULT FALSE,
  was_helpful BOOLEAN,  -- executive feedback
  model_used TEXT,
  embedding VECTOR(1024)
);
CREATE INDEX idx_insights_exec_time ON insights
  USING BRIN (executive_id, created_at);
CREATE INDEX idx_insights_embedding ON insights
  USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- RLS: every table locked to the authenticated executive
ALTER TABLE executives ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE keystroke_aggregates ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_syntheses ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_syntheses ENABLE ROW LEVEL SECURITY;
ALTER TABLE cognitive_model ENABLE ROW LEVEL SECURITY;
ALTER TABLE insights ENABLE ROW LEVEL SECURITY;

-- RLS policy pattern (apply to all observation/synthesis tables)
CREATE POLICY "executives_own_data" ON executives
  FOR ALL USING (auth_user_id = auth.uid());

CREATE POLICY "email_obs_own_data" ON email_observations
  FOR ALL USING (
    executive_id IN (SELECT id FROM executives WHERE auth_user_id = auth.uid())
  );
-- Repeat this pattern for every table with executive_id FK

-- Helper function for RLS
CREATE OR REPLACE FUNCTION get_executive_id()
RETURNS UUID AS $$
  SELECT id FROM executives WHERE auth_user_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;
```

### Local/Cloud Processing Decision Matrix

| Signal Type | Captured By | Processed Locally | Sent to Supabase | Cloud Processing |
|---|---|---|---|---|
| Keystroke timing | CGEventTap (XPC) | Inter-key intervals, hold duration, typing speed, pause freq, error rate → 5-min aggregates | Aggregates only, never raw keystrokes | Claude classifies cognitive load patterns |
| Voice/audio | AVAudioEngine + Whisper.cpp (XPC) | Speech rate, pitch, energy, pauses, on-device sentiment → segment features | Features + LLM-summarised transcript, never raw audio | Claude detects vocal stress patterns over time |
| Calendar | Microsoft Graph delta | Event structure, attendee count, free/busy, reschedule detection | Full calendar metadata | Claude analyses scheduling patterns, meeting load |
| Email metadata | Microsoft Graph delta | Response latency, thread depth, folder moves, reply patterns | Full metadata minus body content | Claude analyses communication patterns, relationship graph |
| App usage | NSWorkspace notifications (XPC) | App category classification, focus duration, switch frequency | Category + duration + hashed window title | Claude detects focus/distraction patterns |
| Screen context | AXUIElement (XPC) | Active window title → hash, document type classification | Hashed titles + classifications, never raw titles | None — privacy boundary |

### Claude API Model Routing Table

| Task | Model | Latency Tolerance | Quality Justification |
|---|---|---|---|
| Email classification (urgent/defer/archive) | Haiku 3.5 | < 1s | Simple categorisation, high volume, needs speed |
| App category classification | Haiku 3.5 | < 1s | Mapping bundle IDs to categories is mechanical |
| Signal anomaly detection (is this keystroke pattern unusual?) | Haiku 3.5 | < 2s | Binary classification against known baseline |
| Daily synthesis (what happened today + patterns) | Sonnet | < 30s | Multi-signal reasoning, needs quality but runs nightly |
| Morning brief generation | Sonnet | < 15s | Synthesises overnight analysis into actionable narrative |
| Burnout risk assessment | Sonnet | < 30s | Longitudinal pattern matching across signal types |
| Pattern detection (new recurring behaviour) | Sonnet | < 60s | Cross-modal correlation, first-order pattern extraction |
| Weekly deep analysis | Opus 4.6 + extended thinking | < 5min | Second-order insight, meta-patterns, cognitive model updates |
| Monthly cognitive model evolution | Opus 4.6 + extended thinking (max budget) | < 15min | Highest-stakes reasoning — the model rewriting itself |
| Procedural rule generation | Opus 4.6 + extended thinking | < 5min | Rules govern future intelligence — must be deeply reasoned |
| Relationship graph analysis | Opus 4.6 | < 5min | Complex social dynamics require nuanced reasoning |

### macOS API Capability Table

| API | Data Access | Permission Required | Distribution Constraint | Key Limitation |
|---|---|---|---|---|
| EventKit | Calendar events, reminders, attendees, recurrence, alarms | `NSCalendarsUsageDescription` + user grant | Any distribution | iCloud/Exchange/Google differences in available fields; EKEventStoreChanged for real-time notifications |
| MailKit (macOS 14-15) | Compose window, display view modification | Mail extension entitlement | App Store or Developer ID | Cannot read received email metadata passively — useless for observation |
| Microsoft Graph API | Email metadata, calendar, contacts, delta sync | OAuth 2.0 via MSAL, user consent | Any distribution | Requires network; polling-based (delta query); rate limits per tenant |
| CoreAudio / AVAudioEngine | Microphone audio stream | `NSMicrophoneUsageDescription` + user grant | Any distribution | macOS 15 Sequoia re-prompts screen/audio permissions monthly |
| SFSpeechRecognizer (on-device) | Real-time speech-to-text | `NSSpeechRecognitionUsageDescription` + user grant | Any distribution | 10 language limit on-device; Apple-controlled model; 1-min segment limit |
| Whisper.cpp + Core ML | Speech-to-text with custom vocabulary | Microphone permission (same as above) | Developer ID only (non-sandboxed for continuous access) | Memory footprint: ~1.5GB for Whisper-large, ~500MB for Whisper-small |
| AXUIElement (Accessibility API) | Frontmost app, window titles, active document, UI element tree | Accessibility permission in System Settings | Developer ID only (non-sandboxed) | Requires explicit user grant; some apps restrict AX access |
| CGEventTap | Keystroke timing (key-down/key-up timestamps, virtual keycodes) | Input Monitoring permission | Developer ID only (non-sandboxed) | macOS 15 tightened permissions; must NOT capture actual key values for privacy |
| IOHIDManager | USB/HID device events, alternative to CGEventTap | Input Monitoring permission | Developer ID only | Lower-level, more complex; CGEventTap preferred for timing data |
| NSWorkspace | Running apps, active app changes, app launch/terminate notifications | None | Any distribution | No per-window focus duration; combine with AXUIElement for window-level data |
| NSRunningApplication | App name, bundle ID, PID, activation state | None | Any distribution | Polling-based for activation state; use NSWorkspace notifications instead |
| ScreenTime API | App usage categories, screen time limits | Family Sharing framework | App Store only | NOT available to third-party Developer ID apps — cannot use |
| SMAppService | Login item registration (macOS 13+) | None | Developer ID or App Store | Replaces SMLoginItemSetEnabled; supports LaunchAgent and LoginItem types |

---

## ALGORITHMS

### 1. Background Observation Pipeline (per signal type)

**Event-driven (continuous):**
- Keystroke dynamics: CGEventTap callback fires on every keyDown/keyUp → records timestamp + virtual keycode to ring buffer → every 5 minutes, feature extractor computes aggregate metrics → writes to local SwiftData buffer → clears ring buffer (raw timing data never persists beyond 5-min window)
- App usage: NSWorkspace.didActivateApplicationNotification → records app switch with timestamp → AXUIElement queries window title of new frontmost app → hashes title → stores focus session end for previous app

**Periodic (polling-based):**
- Email metadata: Graph delta query every 5 minutes during business hours, every 30 minutes off-hours → process delta response → compute response latencies for replied messages → write email_observations batch to local buffer → sync to Supabase
- Calendar sync: Graph delta query every 15 minutes → diff against local calendar cache → detect reschedules/cancellations → write calendar_observations → sync

**Continuous with local processing:**
- Voice analysis: AVAudioEngine tap on microphone input → 30-second audio segments → Whisper.cpp transcription on Neural Engine → extract speech features (rate, pitch, pauses, energy) → discard raw audio immediately → store features + summarised transcript in local buffer → sync

**Scheduled (cron-like):**
- Nightly consolidation: 2:00 AM local time → Supabase Edge Function triggers → aggregates all day's observations → calls Sonnet for daily synthesis → stores daily_syntheses row → updates cognitive_model if patterns detected
- Weekly deep analysis: Sunday 3:00 AM → Opus 4.6 with extended thinking → analyses 7 daily syntheses + raw observation patterns → generates weekly_syntheses → updates cognitive_model version
- Monthly cognitive model evolution: 1st of month, 4:00 AM → Opus 4.6 with maximum thinking budget → full cognitive model review and rewrite

### 2. Local Feature Extraction Pipeline (Swift)

```
AsyncSequence (sensor events)
  → .debounce / .throttle (rate limiting per signal type)
  → FeatureExtractor actor (per-modality)
    → Computes aggregate metrics in 5-min windows
    → Privacy filter: strips raw content, hashes identifiers
  → LocalBuffer actor (SwiftData/SQLite)
    → Batches observations (max 50 rows or 5 minutes, whichever first)
  → SyncActor
    → Writes batch to Supabase via PostgREST
    → Marks local rows as synced
    → Retries failed syncs with exponential backoff (1s, 2s, 4s, 8s, max 5min)
```

Key: Each XPC service runs its own AsyncSequence → FeatureExtractor pipeline. The main app process runs the SyncActor that collects from all XPC services via XPC connections.

### 3. Context Window Management for 12-Month History

**Hierarchical summarisation chain:**
1. Raw observations → daily aggregates (computed by Edge Function nightly)
2. Daily syntheses → weekly syntheses (7 dailies compressed to 1 weekly)
3. Weekly syntheses → monthly syntheses (4 weeklies compressed to 1 monthly)
4. Monthly syntheses → quarterly cognitive model snapshots

**RAG retrieval for Claude context assembly:**
1. Embed the current query/task using Jina v3 (1024-dim)
2. Semantic search against `daily_syntheses.embedding` and `weekly_syntheses.embedding` via pgvector HNSW
3. Retrieve top-K most relevant syntheses (K varies by task: 5 for Haiku, 15 for Sonnet, 30 for Opus)
4. Always include: last 7 daily syntheses (recency), current cognitive_model state (context), any active insights
5. For Opus weekly analysis: include all 7 daily syntheses verbatim + top 10 semantically similar past weeks + current cognitive model + last 3 monthly summaries

**Context budget allocation (Opus 200K window):**
- System prompt + cognitive model: ~10K tokens
- Current week's daily syntheses (7): ~15K tokens
- Semantically retrieved historical context: ~40K tokens
- Raw observation samples (exemplar data points): ~10K tokens
- Reserved for extended thinking: remaining ~125K tokens

### 4. Nightly Consolidation Edge Function Pipeline

```
Edge Function: nightly-consolidation (cron: 0 2 * * *)

1. LOCK: acquire advisory lock per executive_id (prevents duplicate runs)
2. FETCH: all observations for executive_id where observed_at >= today_start AND observed_at < today_end
   - email_observations
   - calendar_observations
   - keystroke_aggregates
   - voice_observations
   - app_usage_events
3. AGGREGATE: compute daily summary statistics per signal type
   - Email: total sent/received, avg response time, top 5 contacts by volume, thread depth distribution
   - Calendar: meeting hours, back-to-back count, cancelled count, avg attendee count
   - Keystroke: hourly cognitive load curve, peak/trough typing speed, total active typing minutes
   - Voice: avg speech rate, sentiment trajectory, total speaking minutes
   - App usage: time-per-category breakdown, focus session count/duration, context switch frequency
4. RETRIEVE: current cognitive_model for executive_id
5. CALL Claude Sonnet:
   - System: "You are analysing one day of executive behavioural data..."
   - User: aggregated stats + cognitive model + last 3 daily syntheses for continuity
   - Output: structured JSON (energy_curve, focus_score, patterns, observations, narrative)
6. EMBED: Jina v3 embedding of synthesis_text
7. WRITE: INSERT into daily_syntheses
8. CHECK: if any patterns cross threshold → INSERT into insights
9. RELEASE: advisory lock
10. IDEMPOTENCY: check if daily_syntheses row already exists for (executive_id, today) — skip if yes
```

Error handling: all steps wrapped in try/catch → failures logged to `consolidation_logs` table → retry via pg_cron at 2:30 AM for any failed executive_ids.

### 5. Graceful Degradation

| Failure Mode | Behaviour | Recovery |
|---|---|---|
| Offline (no network) | All XPC observation services continue normally. Local buffer accumulates. Supabase sync pauses. No Claude API calls. | On reconnect: SyncActor flushes buffered observations in chronological order. Edge Functions catch up on missed consolidations. |
| Claude API down | Cached intelligence (last daily/weekly synthesis) displayed. New observations continue collecting. Consolidation jobs queue. | On recovery: queue drains in order. No intelligence gap — delayed, not lost. |
| Supabase unreachable | Local SwiftData buffer absorbs all observations. Buffer has 7-day capacity (~50MB for typical usage). | On reconnect: batch sync with conflict resolution (server timestamp wins for syntheses, client timestamp wins for observations). |
| XPC service crash | launchd auto-restarts the crashed XPC service (KeepAlive = true). Other XPC services unaffected. Main app shows degraded indicator for that modality. | Restarted XPC service resumes observation from current moment. Gap in that signal type's data is noted in next consolidation. |
| Main app crash | XPC services continue running independently (they're separate LaunchAgent processes). Observations accumulate in their local buffers. | Main app restart picks up XPC connections, flushes their buffers, resumes sync. |
| macOS reboot/update | SMAppService re-launches all registered login items on next login. | Full pipeline restarts. First consolidation after reboot notes the gap. |
| Low battery (< 20%) | Reduce observation frequency: keystroke aggregation window 5min → 15min, email poll 5min → 30min, voice analysis pauses. | Resume normal frequency when charging detected (IOPowerSources notification). |

---

## APIS & FRAMEWORKS

### macOS Observation
- **EventKit** — EKEventStore for calendar read access; EKEventStoreChangedNotification for real-time change detection; works with iCloud/Exchange/Google but field availability varies (Exchange has richest attendee data)
- **CoreAudio / AVAudioEngine** — installTap(onBus:) for continuous microphone stream; bufferSize 4096 at 16kHz for Whisper input
- **Accessibility API (AXUIElement)** — AXUIElementCopyAttributeValue for window titles, document names; kAXFocusedWindowAttribute; AXObserver for real-time UI change callbacks
- **CGEventTap** — CGEvent.tapCreate with kCGEventKeyDown/kCGEventKeyUp; extract .timestamp and .getIntegerValueField(.keyboardEventKeycode) only — never .keyboardEventAutorepeat or character values
- **NSWorkspace** — didActivateApplicationNotification, didLaunchApplicationNotification, didTerminateApplicationNotification
- **NSRunningApplication** — bundleIdentifier, localizedName, isActive for app identification
- **IOPowerSources** — battery level and charging state for adaptive observation frequency

### Background Processing
- **SMAppService** (macOS 13+) — .mainApp.register() for login item; .agent(plistName:) for LaunchAgent XPC services
- **XPC** — NSXPCConnection with exported interfaces; Swift Concurrency compatible via withCheckedContinuation bridging
- **launchd** — KeepAlive, ThrottleInterval for XPC service crash recovery; RunAtLoad for boot persistence
- **DispatchSourceTimer** — for periodic polling (email every 5min, calendar every 15min)
- **BGTaskScheduler** — NOT recommended for macOS; it exists but is iOS-centric. Use pg_cron via Supabase Edge Functions for scheduled intelligence jobs instead.

### Storage
- **SwiftData / SQLite** — local observation buffer; 7-day rolling window; automatic pruning of synced records
- **Supabase Postgres** — primary longitudinal store; PostgREST for CRUD; Realtime for live subscription to insights
- **pgvector** — HNSW indexes on embedding columns for RAG retrieval; vector_cosine_ops for similarity search
- **Supabase Vault** — encrypted storage for API keys (Claude, Graph, Jina) server-side

### Intelligence
- **Claude API** — /v1/messages with streaming; extended thinking via `thinking` parameter; prompt caching for repeated cognitive model context
- **Jina AI** — jina-embeddings-v3 (1024-dim) for embedding syntheses and insights; used for RAG retrieval against pgvector

### Update & Distribution
- **Sparkle 2.x** — SUUpdater for auto-update checks; appcast.xml hosted on CDN; EdDSA signing for update verification; delta updates via BinaryDelta
- **Notarisation** — xcrun notarytool submit for Developer ID distribution; staple to .app bundle

### Monitoring
- **Sentry** (macOS SDK) — crash reporting + performance monitoring; PII stripping via beforeSend callback that redacts any field matching email/name/title patterns
- **os.Logger** — structured logging per XPC service; subsystem = "com.timed.[service]"; never log raw observation content

---

## NUMBERS

### Battery/CPU Budget (MacBook Pro M-series, continuous observation)

| Modality | CPU Impact | Power Draw | Memory | Acceptable Budget |
|---|---|---|---|---|
| Keystroke CGEventTap | < 0.1% CPU (event-driven, no polling) | ~5mW idle, ~15mW during active typing | < 5MB | Negligible |
| App usage NSWorkspace | < 0.1% CPU (notification-driven) | ~5mW | < 3MB | Negligible |
| Email Graph polling (5min) | ~0.5% CPU spike for 2-3s per poll | ~50mW averaged | < 20MB | 50mW continuous avg |
| Calendar Graph polling (15min) | ~0.3% CPU spike for 1-2s per poll | ~20mW averaged | < 10MB | 20mW continuous avg |
| Voice Whisper-small (continuous) | ~8-12% CPU on Neural Engine | ~800mW-1.2W during inference | ~500MB (Whisper-small model) | 1W continuous — significant |
| Voice Whisper-small (on-demand) | ~8-12% CPU during active speech only | ~200mW averaged (assuming 2h speech/day) | ~500MB | 200mW averaged — acceptable |
| Accessibility AXUIElement | < 0.2% CPU (query on app switch only) | ~10mW | < 5MB | Negligible |
| Supabase sync (batched) | ~0.3% CPU per batch | ~30mW per batch | < 15MB | Negligible |
| **Total (all modalities, voice on-demand)** | **~1.5% CPU averaged** | **~350mW averaged** | **~560MB** | ~2% battery/hour — 10h workday feasible |
| **Total (all modalities, voice continuous)** | **~10-13% CPU** | **~1.3W averaged** | **~560MB** | ~6% battery/hour — 5h on battery, fine when plugged in |

**Decision:** Voice analysis should be on-demand (during meetings/morning session) not continuous, unless plugged in. Use IOPowerSources to detect power state and switch modes.

### Whisper Performance on Apple Silicon

| Model | Size | Real-time Factor (M1) | Real-time Factor (M2 Pro) | Memory | Accuracy (WER) |
|---|---|---|---|---|---|
| Whisper-tiny | 39MB | 15x | 20x | ~150MB | ~8% WER |
| Whisper-small | 244MB | 8x | 12x | ~500MB | ~4.5% WER |
| Whisper-medium | 769MB | 3x | 5x | ~1.5GB | ~3.5% WER |
| Whisper-large-v3 | 1.55GB | 1.2x | 2x | ~3GB | ~3% WER |

**Decision:** Whisper-small is the sweet spot — 8x real-time means a 30-second segment processes in ~4 seconds. Sufficient accuracy for executive speech patterns.

### Supabase Query Performance

| Query Pattern | Expected Row Scan | Index Used | Target Latency |
|---|---|---|---|
| All email response times to person X, last 90 days | ~500-2000 rows | BRIN on (executive_id, observed_at) + B-tree on sender_address | < 50ms |
| Weekly burnout risk scores, last 6 months | ~26 rows | BRIN on (executive_id, week_start) | < 10ms |
| Calendar patterns on high-stress days | JOIN keystroke_aggregates + calendar_observations on date | BRIN on both timestamp columns | < 100ms |
| RAG semantic search (top 20 similar syntheses) | pgvector HNSW scan | HNSW on embedding column | < 50ms |
| Full daily observation fetch for consolidation | ~500-5000 rows across 5 tables | BRIN on observed_at per table | < 200ms total |

### Claude API Performance

| Task | Model | Input Tokens (typical) | Output Tokens | Streaming Latency (TTFT) | Total Time |
|---|---|---|---|---|---|
| Email classification | Haiku 3.5 | ~500 | ~50 | ~200ms | < 1s |
| Daily synthesis | Sonnet | ~15,000 | ~2,000 | ~500ms | 8-15s |
| Morning brief | Sonnet | ~10,000 | ~1,500 | ~500ms | 5-10s |
| Weekly deep analysis | Opus 4.6 + thinking | ~70,000 | ~5,000 + ~30,000 thinking | ~2s | 2-5min |
| Monthly model evolution | Opus 4.6 + max thinking | ~100,000 | ~8,000 + ~80,000 thinking | ~3s | 5-15min |

**Caching strategy:** Use Claude's prompt caching for the cognitive model system prompt (stable across calls within a day). Cache the system prompt + cognitive model as a cached prefix. Only the new observation data varies per call.

---

## ANTI-PATTERNS

### 1. App Nap Throttling Background Observation
- **Problem:** macOS App Nap suspends timer-based background processing when the app has no visible windows and isn't playing audio
- **Prevention:** Set `NSProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Continuous executive observation")` on each XPC service — this opts out of App Nap
- **Alternative:** XPC services registered as LaunchAgents are not subject to App Nap (they're separate processes managed by launchd, not the app lifecycle)
- **DO NOT** use `.background` QoS for observation tasks — macOS aggressively throttles and coalesces timers for background QoS

### 2. Storing Raw Keystroke Content
- **Problem:** Capturing actual key values (characters typed) creates a keylogger — legal liability, privacy violation, trust destruction
- **Rule:** CGEventTap must ONLY extract `.timestamp` and `.keyboardEventKeycode` (virtual keycode for timing calculations). Never call `CGEvent.keyboardCharacterStringAtIndex()` or convert keycodes to characters
- **Pipeline:** Ring buffer stores only `(timestamp_ns: UInt64, keycode: UInt16, isKeyDown: Bool)` — no character data at any stage
- **Validation:** Unit test that asserts the KeystrokeXPC service's data model has no String or Character fields

### 3. Monolithic Process vs Over-Split XPC Services
- **Problem (monolith):** Single crash kills all observation. Whisper inference spike blocks keystroke event processing. Memory pressure from one modality affects all.
- **Problem (over-split):** Too many XPC services (one per sub-feature) creates IPC overhead, debugging complexity, and state synchronisation nightmares
- **Right granularity:** 5 XPC services aligned to permission boundaries and crash domains:
  1. `KeystrokeXPC` — CGEventTap (Input Monitoring permission)
  2. `VoiceXPC` — AVAudioEngine + Whisper.cpp (Microphone permission)
  3. `AccessibilityXPC` — AXUIElement (Accessibility permission)
  4. `AppUsageXPC` — NSWorkspace (no special permission)
  5. Main app process — Graph API polling, Supabase sync, Claude API, UI

### 4. Schema Migrations That Lose Historical Data
- **Rule:** NEVER use DROP COLUMN, DROP TABLE, or ALTER COLUMN TYPE on production observation tables
- **Additive only:** New columns with DEFAULT values, new tables, new indexes
- **Renaming:** Create new column, backfill, update app code to write to new column, deprecate old column (keep it, never drop)
- **Migration testing:** Every migration runs against a clone of production data (Supabase branching) before production deployment
- **Rollback:** Every migration has a corresponding down migration that is also additive (adds back what the up migration deprecated)

### 5. App Store Distribution for This Type of App
- **Problem:** App Store sandbox prohibits CGEventTap, AXUIElement for non-assistive-technology apps, and continuous microphone access without visible recording indicator
- **Decision:** Developer ID + notarisation is the only path. Do not design for App Store compatibility — it constrains the architecture for zero benefit in the enterprise executive market
- **Implication:** No TestFlight for beta distribution (use Sparkle beta channel instead), no App Store review process (faster iteration), no App Store payment processing (use Stripe or direct licensing)

### 6. Timer Coalescing Disrupting Observation Cadence
- **Problem:** macOS coalesces timers within a tolerance window to batch wake-ups for power efficiency. A 5-minute email poll timer might fire at 5:03 or 4:57.
- **Mitigation:** For timing-sensitive observation (keystroke dynamics), use event-driven callbacks, not timers. For polling (email/calendar), coalescing is acceptable — a 3-second variance on a 5-minute poll is irrelevant.
- **DO NOT** disable timer coalescing system-wide — it wastes power for no benefit

### 7. Treating SFSpeechRecognizer as Production Voice Pipeline
- **Problem:** Apple controls the model, limits on-device languages to 10, imposes 1-minute segment limits, and can change accuracy between OS updates without notice
- **Decision:** SFSpeechRecognizer is acceptable for the morning session voice commands (short utterances, interactive). Whisper.cpp is required for continuous/background voice analysis where vocabulary coverage and segment length matter.

### 8. Using BGTaskScheduler on macOS for Scheduled Work
- **Problem:** BGTaskScheduler exists on macOS but is designed for iOS background task scheduling. On macOS it's unreliable for precise scheduling and not well-documented.
- **Decision:** Use Supabase pg_cron for all scheduled intelligence work (nightly consolidation, weekly analysis, monthly evolution). The Mac app is responsible only for continuous observation and sync — all scheduled intelligence processing runs server-side.

### 9. Sending Raw Audio to Supabase/Cloud
- **Problem:** Executive voice recordings are extremely sensitive. Any cloud transmission of raw audio is a trust-destroying event.
- **Rule:** Raw audio exists only in memory during the Whisper inference pipeline. After feature extraction (speech rate, pitch, energy, pauses, sentiment), the audio buffer is zeroed and deallocated. Only computed features and LLM-summarised transcripts sync to Supabase.
- **Validation:** VoiceXPC service must not have any file I/O for audio formats (.wav, .m4a, .mp3). Unit test asserts this.

### 10. Storing Unhashed Window Titles
- **Problem:** Window titles leak document names, URLs, email subjects, chat messages — all sensitive executive data
- **Rule:** AXUIElement window title → SHA-256 hash immediately. Only the hash and a category classification ("document", "email", "browser", "chat") are stored. The raw title exists only in memory during the classification step.
