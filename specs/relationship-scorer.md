# Relationship Health Scorer Spec

**System:** Timed — Cognitive Intelligence Layer for C-Suite Executives
**Layer:** Semantic Memory (learned facts about the executive's professional network)
**Models:** Haiku 3.5 (per-message signal extraction), Sonnet (weekly aggregation), Opus (nightly relationship analysis)
**Stack:** Swift 5.9+, CoreData, Supabase, Claude API
**Status:** Implementation-ready

---

## 1. Purpose

Build and maintain a per-contact model of every professional relationship in the executive's network. Compute a continuous health score per contact. Detect improving, stable, and deteriorating relationships. Surface relationship intelligence in the morning briefing before the executive notices the change themselves.

An executive manages 50-200 active professional relationships. They cannot track the health of all of them consciously. Small signals (response latency creeping up, email length shortening, meetings becoming less frequent) compound into relationship degradation that becomes visible only when it's a crisis. Timed detects the drift early.

---

## 2. Scientific Foundation

### 2.1 Computational Relationship Analysis

- **Kossinets & Watts (2006, Science)**: Analysed 43,000+ email users' communication patterns. Found that email frequency, response time, and reciprocity are strong predictors of relationship strength. Relationships that cool show predictable patterns: response latency increases first, then email frequency drops, then meeting frequency drops.
- **Aral & Van Alstyne (2012)**: Information workers maintain communication patterns that reveal relationship strength more accurately than self-report. "Revealed preference" from communication behaviour is the best relationship strength measure available.
- **Wuchty & Uzzi (2011)**: Email network analysis can predict professional outcomes (promotions, departures, project success) by tracking communication patterns between individuals.

### 2.2 Relationship Maintenance Theory

- **Dunbar (1992, Dunbar's Number)**: Cognitive limit on active relationships is ~150, with an inner circle of ~15 high-maintenance relationships. For C-suite executives, the inner circle is typically 8-12 people (board members, direct reports, key clients, key peers).
- **Burt (2004, Structural Holes)**: The value of a relationship is partly determined by its structural position — does this contact bridge to a network the executive otherwise can't access? Timed can infer structural importance from communication patterns.
- **Granovetter (1973, Weak Ties)**: Weak ties (infrequent but maintained contacts) provide novel information and opportunities. Timed should track weak-tie health separately from strong-tie health — different maintenance cadences, different deterioration signals.

### 2.3 Sentiment Analysis in Professional Communication

- **Pennebaker (2011, "The Secret Life of Pronouns")**: Pronoun usage, word length, and function words reveal relationship dynamics more accurately than content analysis. "I/we" ratio shifts, formal → informal language transitions, and hedging patterns are strong relationship health indicators.
- **Mohammad & Turney (2013)**: Emotion lexicon-based sentiment analysis achieves ~70% accuracy in professional email. For trend detection (not absolute classification), this is sufficient — we need direction of change, not absolute sentiment.

---

## 3. Signal Sources

### 3.1 Per-Contact Signals

#### Signal 1: Response Latency Trend

**What it measures:** How quickly the executive responds to this contact, and how quickly this contact responds to the executive. The absolute value matters less than the trend.

**Implementation:**
```swift
struct ResponseLatencySignal {
    let contactId: UUID
    let direction: Direction       // .outbound (exec → contact) or .inbound (contact → exec)
    let latencyMinutes: Double
    let timestamp: Date
    
    enum Direction { case outbound, inbound }
}

// Compute trend: 14-day rolling average vs 60-day rolling average
func latencyTrend(contact: UUID, direction: Direction) -> TrendResult {
    let recent = rollingAverage(contact: contact, direction: direction, days: 14)
    let baseline = rollingAverage(contact: contact, direction: direction, days: 60)
    
    let ratio = recent / baseline
    // ratio > 1.5 = significantly slower (deteriorating)
    // ratio 0.8-1.2 = stable
    // ratio < 0.7 = significantly faster (improving or urgency)
    
    return TrendResult(ratio: ratio, direction: classifyTrend(ratio))
}
```

**Key nuance:** A sudden decrease in outbound latency (executive responding much faster) could mean the relationship is improving OR that a crisis requires urgent responses. Disambiguate using other signals.

#### Signal 2: Email Length Trend

**What it measures:** Communication investment. Shorter emails over time = declining engagement. Longer emails = increasing investment or increasing complexity.

**Implementation:**
```swift
struct EmailLengthSignal {
    let contactId: UUID
    let direction: Direction
    let wordCount: Int
    let timestamp: Date
}

// Track 14-day vs 60-day rolling average word count per contact per direction
// Normalise by email type (quick reply vs substantive email)
```

**Important:** Normalise for email type. A one-line "Approved" reply is not the same signal as a one-line response to a substantive question. Haiku classifies email type (quick-reply, acknowledgement, substantive, detailed) before length comparison.

#### Signal 3: Thread Depth Changes

**What it measures:** How many back-and-forth exchanges happen in a conversation. Declining thread depth = fewer exchanges needed (efficiency?) or less engagement (deterioration?). Increasing thread depth = richer discussion or growing conflict.

**Implementation:** Track average thread depth (number of messages in a thread) per contact, rolling 30-day window. Combine with sentiment to disambiguate: deep threads + positive sentiment = healthy engagement; deep threads + negative sentiment = unresolved conflict.

#### Signal 4: Meeting Frequency

**What it measures:** How often the executive meets with this contact. For direct reports and key stakeholders, regular meeting frequency is expected. A drop signals relationship cooling or deprioritisation.

**Implementation:**
```swift
struct MeetingFrequencySignal {
    let contactId: UUID
    let meetingsLast30Days: Int
    let meetingsLast60Days: Int    // Normalised to 30-day equivalent
    let cancellationCount: Int     // Meetings scheduled but cancelled
    let cancellationInitiator: String? // "executive" or "contact"
    
    var frequencyTrend: Float {
        let recent = Float(meetingsLast30Days)
        let baseline = Float(meetingsLast60Days) / 2.0
        guard baseline > 0 else { return 0.0 }
        return (recent - baseline) / baseline // Positive = more meetings, negative = fewer
    }
}
```

**Cancellation analysis:** WHO cancels matters. Executive cancelling on a direct report repeatedly is a relationship health concern. The contact cancelling on the executive might signal their disengagement.

#### Signal 5: Tone/Sentiment Drift

**What it measures:** Directional change in the emotional tone of communication with a specific contact.

**Implementation:**
```swift
struct SentimentSignal {
    let contactId: UUID
    let direction: Direction
    let messageId: String
    let sentimentScore: Float     // -1.0 (negative) to +1.0 (positive)
    let formalityScore: Float     // 0.0 (casual) to 1.0 (very formal)
    let hedgingScore: Float       // 0.0 (direct) to 1.0 (heavily hedged)
    let timestamp: Date
}
```

Haiku classifies each email exchange on three dimensions:
- **Sentiment:** Positive/neutral/negative (not content-based — tone-based. "Thanks for the update" vs "Please advise on the timeline")
- **Formality:** Casual ("Hey, quick thought") vs formal ("Dear X, Further to our discussion"). Increasing formality = relationship cooling.
- **Hedging:** Direct ("We should do X") vs hedged ("Perhaps it might be worth considering X"). Increasing hedging = decreasing confidence/trust.

**Trend detection:** 14-day rolling average vs 60-day baseline on each dimension. The combination matters:
- Sentiment declining + formality increasing = relationship deteriorating
- Sentiment stable + formality decreasing = relationship deepening
- Hedging increasing = trust declining or power dynamic shifting

#### Signal 6: CC/BCC Patterns

**What it measures:** Communication transparency and trust indicators.

**Implementation:**
```swift
struct CCPatternSignal {
    let contactId: UUID
    let ccAdditions: Int          // Times others CC'd on threads with this contact (that weren't before)
    let bccUsage: Int             // Times BCC used on threads with this contact
    let ccByContact: Int          // Times the contact adds CCs to their replies
    let escalationCCs: Int        // Times a manager/superior is CC'd into thread
    let timestamp: Date
}
```

**Key patterns:**
- Executive starts CC'ing their boss on threads with contact = escalation/protection behaviour
- Contact starts CC'ing their boss = same in reverse
- New people being CC'd into established threads = trust breakdown or formality increase
- BCC usage = political behaviour, significant signal

---

## 4. Relationship Health Score

### 4.1 Score Architecture

```swift
struct RelationshipHealthScore {
    let contactId: UUID
    let contactName: String
    let overallScore: Float        // 0.0-1.0 (0 = severely deteriorated, 1 = excellent)
    let trend: RelationshipTrend   // .improving, .stable, .declining, .rapidly_declining
    let trendVelocity: Float       // Rate of change per week
    let confidence: Float          // Based on signal density
    let signalBreakdown: [String: Float]  // Per-signal contribution
    let lastInteraction: Date
    let daysSinceLastInteraction: Int
    let contactTier: ContactTier   // .inner_circle, .active, .maintenance, .dormant
    let alerts: [RelationshipAlert]
}

enum RelationshipTrend {
    case improving            // Score increased > 0.05 over 14 days
    case stable               // Score change < 0.05 over 14 days
    case declining            // Score decreased 0.05-0.15 over 14 days
    case rapidlyDeclining     // Score decreased > 0.15 over 14 days
}

enum ContactTier {
    case innerCircle    // Top 12 contacts by interaction frequency + importance
    case active         // Regular interaction (at least weekly)
    case maintenance    // Periodic interaction (monthly)
    case dormant        // No meaningful interaction in 30+ days
}
```

### 4.2 Score Computation

Each signal contributes to the overall health score. Weights are calibrated per contact based on the relationship type:

```swift
func computeHealthScore(contact: UUID) -> Float {
    let weights = contactWeights(for: contact) // Varies by relationship type
    
    let latencyComponent = latencyHealthScore(contact) * weights.latency
    let lengthComponent = lengthHealthScore(contact) * weights.length
    let depthComponent = threadDepthHealthScore(contact) * weights.depth
    let meetingComponent = meetingHealthScore(contact) * weights.meeting
    let sentimentComponent = sentimentHealthScore(contact) * weights.sentiment
    let ccComponent = ccHealthScore(contact) * weights.ccPattern
    let recencyComponent = recencyHealthScore(contact) * weights.recency
    
    return latencyComponent + lengthComponent + depthComponent + 
           meetingComponent + sentimentComponent + ccComponent + recencyComponent
}
```

**Weight profiles by relationship type:**

| Signal | Direct Report | Board Member | Client | Peer |
|--------|--------------|--------------|--------|------|
| Latency | 0.15 | 0.20 | 0.25 | 0.15 |
| Length | 0.10 | 0.15 | 0.15 | 0.10 |
| Thread Depth | 0.15 | 0.10 | 0.10 | 0.15 |
| Meeting Freq | 0.25 | 0.20 | 0.15 | 0.20 |
| Sentiment | 0.20 | 0.15 | 0.20 | 0.20 |
| CC Pattern | 0.05 | 0.10 | 0.10 | 0.10 |
| Recency | 0.10 | 0.10 | 0.05 | 0.10 |

Relationship type is classified by Haiku from email content and calendar patterns during onboarding, and updated as new evidence accumulates.

### 4.3 Trend Detection

Trend is computed from the health score time series:

```swift
func detectTrend(contact: UUID) -> RelationshipTrend {
    let scores14d = healthScores(contact: contact, lastNDays: 14)
    let scores60d = healthScores(contact: contact, lastNDays: 60)
    
    guard scores14d.count >= 3, scores60d.count >= 10 else {
        return .stable // Insufficient data
    }
    
    let recentSlope = linearRegressionSlope(scores14d)
    let baselineScore = scores60d.map(\.score).average()
    let recentScore = scores14d.map(\.score).average()
    let delta = recentScore - baselineScore
    
    switch delta {
    case 0.15...: return .improving
    case 0.05..<0.15: return recentSlope > 0 ? .improving : .stable
    case -0.05..<0.05: return .stable
    case -0.15 ..< -0.05: return .declining
    default: return .rapidlyDeclining
    }
}
```

---

## 5. Network-Level Analysis

### 5.1 Alliance Patterns

Beyond individual relationships, detect network-level patterns:

**Communication clusters:** Groups of contacts who are frequently CC'd together, appear in the same meeting series, or are referenced in the same email threads. These represent the executive's operational alliances.

**Cluster health:** If an entire cluster's communication patterns shift simultaneously (e.g., all board members' response latency increases), this signals an organisational event, not individual relationship issues.

**Implementation:**
```swift
struct CommunicationCluster {
    let id: UUID
    let contacts: [UUID]
    let clusterLabel: String      // Opus-generated: "Board", "Product Team", "Investors"
    let cohesion: Float           // How tightly the group communicates
    let avgHealthScore: Float
    let trend: RelationshipTrend
}
```

### 5.2 Communication Channel Switching

**Detection:** Contact previously communicated via email but conversations shift to phone (detected from calendar "call" events) or messaging. Channel switching to less-traceable channels can indicate:
- Increasing trust (moving to casual channels)
- Decreasing trust (moving to unrecorded channels for sensitive topics)
- Relationship deepening (moving to higher-bandwidth channels)

**Disambiguation:** Combine with sentiment trend. Channel switch + positive sentiment = deepening. Channel switch + negative sentiment = political manoeuvring.

### 5.3 Attention Allocation vs Stated Priority

Cross-reference the executive's communication attention (who gets responses, how fast, how substantive) with their stated priorities:

> "You told me Sarah is your most important hire this quarter, but your response latency to her has increased 2.5x over the past two weeks and your last three emails to her were under 30 words. Meanwhile, you're spending 3x more time in email threads with Tom (operations). Your attention and your stated priority are misaligned."

---

## 6. Privacy Considerations

### 6.1 Core Privacy Architecture

Relationship health scoring is the most privacy-sensitive feature in Timed. Principles:

1. **No content storage for scoring:** The health score is computed from metadata (timing, length, frequency) and Haiku-classified tone. Raw email content is NOT stored in the relationship model. Haiku processes content in-flight for sentiment classification, then only the classification score is retained.

2. **No monitoring of personal contacts:** Relationship scoring applies only to professional contacts. Classify contacts as professional vs personal based on domain, calendar context, and email patterns. Personal contacts are excluded entirely.

3. **No sharing of individual scores:** The relationship health model is visible only to the executive. No "relationship leaderboard." No sharing with HR. No export.

4. **Transparent model inspection:** The executive can view any contact's health score and the signals contributing to it. "Show me why you think my relationship with the CTO is declining" → system shows: response latency up 3x, meeting frequency down 40%, formality index increased.

### 6.2 Ethical Boundaries

| Permitted | Not Permitted |
|-----------|---------------|
| Detecting relationship health trends from metadata | Reading/summarising personal email content |
| Noting that response patterns have changed | Making judgments about WHY the relationship changed |
| Surfacing that the exec hasn't spoken to someone in 3 weeks | Suggesting the exec is "neglecting" someone |
| Tracking professional network dynamics | Building a model of contacts' behaviour when they're not emailing the exec |

### 6.3 Consent Model

Relationship scoring is opt-in at the feature level. On first enable:

> "Relationship Health Scoring analyses your email and calendar patterns to detect changes in your professional relationships. It uses timing, frequency, and tone — not email content. You can view, modify, or delete any contact's model at any time. Enable?"

The executive can exclude specific contacts ("Never score my relationship with X").

---

## 7. Surfacing in Morning Session

### 7.1 Relationship Alerts

Alerts are generated when a relationship crosses a threshold:

**Declining Alert (threshold: score dropped > 0.15 in 14 days):**
> "Your communication pattern with [CTO Name] has shifted over the past three weeks. Response latency from them has increased 3x, your meetings have gone from weekly to every two weeks, and the tone has become more formal. This pattern is similar to what happened with [Previous Contact] in January."

**Dormancy Alert (threshold: no interaction with inner-circle contact in 14+ days):**
> "You haven't had a meaningful interaction with [Board Chair Name] in 16 days. Your historical pattern is weekly contact. Last time there was a gap this long was in November, and it took three weeks to re-establish the regular cadence."

**Improving Alert (threshold: score increased > 0.10 in 14 days):**
> "Your relationship with [CFO Name] appears to be strengthening — response times are down 40%, and your recent exchanges have been longer and more substantive than your baseline."

### 7.2 Attention Misalignment

Surfaced weekly (not daily — to avoid nagging):

> "This week's attention allocation: 35% of your email investment went to Operations (Tom, Sarah, Mike), 25% to Board relations, 20% to Client (Acme Corp), 20% to Product. Last week you said the Acme contract renewal was your top priority but only 8% of your communication time went there."

### 7.3 Network Health Dashboard (Weekly in Morning Session)

> "Network health this week: 3 relationships improving, 8 stable, 2 declining, 1 dormant. The two declining relationships are both on the Product team — this might be a team-level signal rather than individual. The dormant contact is [Investor Name] — you haven't connected since the board meeting on March 15th."

---

## 8. Data Model (CoreData)

```swift
@Model
class Contact {
    var id: UUID
    var name: String
    var emailAddresses: [String]
    var tier: String               // "inner_circle", "active", "maintenance", "dormant"
    var relationshipType: String   // "direct_report", "board", "client", "peer", "vendor", "other"
    var excluded: Bool             // Opted out of scoring
    var firstSeen: Date
    var lastInteraction: Date
}

@Model
class RelationshipSignal {
    var id: UUID
    var contactId: UUID
    var signalType: String         // "latency", "length", "depth", "meeting", "sentiment", "cc_pattern"
    var direction: String          // "outbound", "inbound", "mutual"
    var value: Float               // Signal-specific value
    var timestamp: Date
}

@Model
class RelationshipScore {
    var id: UUID
    var contactId: UUID
    var overallScore: Float
    var trend: String              // "improving", "stable", "declining", "rapidly_declining"
    var trendVelocity: Float
    var confidence: Float
    var signalBreakdown: Data      // JSON
    var scoredAt: Date
}

@Model
class RelationshipAlert {
    var id: UUID
    var contactId: UUID
    var alertType: String          // "declining", "dormant", "improving", "attention_misalignment"
    var message: String
    var severity: String           // "info", "warning", "critical"
    var acknowledged: Bool
    var createdAt: Date
}

@Model
class CommunicationCluster {
    var id: UUID
    var label: String
    var contactIds: [UUID]
    var cohesion: Float
    var avgHealthScore: Float
    var trend: String
    var lastComputed: Date
}
```

### Supabase Schema

```sql
create table contacts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    name text not null,
    email_addresses text[] not null default '{}',
    tier text not null default 'active',
    relationship_type text not null default 'other',
    excluded boolean not null default false,
    first_seen timestamptz not null default now(),
    last_interaction timestamptz,
    unique(user_id, name)
);

create table relationship_signals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    contact_id uuid references contacts(id) not null,
    signal_type text not null,
    direction text not null,
    value real not null,
    created_at timestamptz not null default now()
);

create index idx_rel_signals_contact on relationship_signals(contact_id, signal_type, created_at desc);

create table relationship_scores (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    contact_id uuid references contacts(id) not null,
    overall_score real not null,
    trend text not null,
    trend_velocity real not null default 0.0,
    confidence real not null,
    signal_breakdown jsonb not null default '{}',
    scored_at timestamptz not null default now()
);

-- Keep daily scores for 90 days, then weekly aggregates
create index idx_rel_scores_contact on relationship_scores(contact_id, scored_at desc);

create table relationship_alerts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    contact_id uuid references contacts(id) not null,
    alert_type text not null,
    message text not null,
    severity text not null default 'info',
    acknowledged boolean not null default false,
    created_at timestamptz not null default now()
);

create table communication_clusters (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    label text not null,
    contact_ids uuid[] not null default '{}',
    cohesion real not null default 0.0,
    avg_health_score real not null default 0.5,
    trend text not null default 'stable',
    last_computed timestamptz not null default now()
);

-- RLS
alter table contacts enable row level security;
alter table relationship_signals enable row level security;
alter table relationship_scores enable row level security;
alter table relationship_alerts enable row level security;
alter table communication_clusters enable row level security;

create policy "own_data" on contacts for all using (auth.uid() = user_id);
create policy "own_data" on relationship_signals for all using (auth.uid() = user_id);
create policy "own_data" on relationship_scores for all using (auth.uid() = user_id);
create policy "own_data" on relationship_alerts for all using (auth.uid() = user_id);
create policy "own_data" on communication_clusters for all using (auth.uid() = user_id);
```

---

## 9. Processing Pipeline

### 9.1 Real-Time (Haiku — per email/calendar event)

**On email sent or received:**
1. Identify contact (from address, match to `Contact` entity — create if new)
2. Compute response latency (if it's a reply, match to parent message)
3. Compute email length (word count)
4. Haiku classifies: sentiment score, formality score, hedging score
5. Extract CC/BCC pattern
6. Store `RelationshipSignal` entries

**On calendar event:**
1. Extract attendees, match to contacts
2. Record meeting occurrence for frequency tracking
3. If meeting cancelled, record cancellation and initiator

**Token cost per email:** ~300 Haiku tokens (sentiment/formality/hedging classification). At ~80 emails/day for a C-suite exec = ~24,000 Haiku tokens/day. Acceptable.

### 9.2 Nightly (Opus — during reflection engine)

During reflection Stage 2 (first-order pattern extraction) and Stage 3 (second-order synthesis):

**Stage 2 — Per-contact score update:**
1. Pull all relationship signals from the last 24 hours
2. Recompute health scores for all contacts with new data
3. Detect trend changes
4. Generate alerts for threshold crossings

**Stage 3 — Network-level analysis:**
1. Cluster contacts by co-occurrence in meetings and CC patterns
2. Detect cluster-level trends
3. Cross-reference attention allocation with stated priorities
4. Generate relationship intelligence for morning session

**Opus prompt (within reflection pipeline):**
```
Analysing relationship health for [executive name].

Today's relationship signals:
[Grouped by contact: latency, length, sentiment, meetings]

Current scores for contacts with changes:
[Contacts where today's signals differ from baseline]

Active alerts:
[Current relationship alerts]

Known clusters:
[Communication cluster definitions]

Executive's stated priorities:
[From morning session / semantic memory]

Tasks:
1. Update health scores for contacts with new signals
2. Detect any trend changes (stable → declining, etc.)
3. Generate alerts for threshold crossings
4. Analyse network-level patterns
5. Identify attention-priority misalignments
6. Produce 1-3 relationship insights for the morning briefing (only for actionable findings — don't report stable relationships)

Output as structured JSON.
```

---

## 10. Cold Start

### 10.1 Initial Contact Discovery (Day 1)

From 90-day calendar and email history:

1. Extract all unique contacts from email addresses and calendar attendees
2. Rank by interaction frequency to identify inner circle (~12 contacts)
3. Haiku classifies relationship type from email content patterns
4. Compute initial baselines from 90-day history

### 10.2 Model Maturation

| Phase | Duration | Available |
|-------|----------|-----------|
| **Bootstrap** | Day 1 | Contact list, tiers, relationship types, 90-day baselines |
| **Early Scoring** | Days 2-14 | Static health scores from baseline data. No trend detection yet. |
| **Trend Detection** | Days 15-30 | 14-day vs baseline comparison enables trend detection. First relationship alerts. |
| **Deep Model** | Day 30+ | Network-level analysis, cluster detection, attention alignment, pattern matching to past relationship trajectories |

---

## 11. Implementation Sequence

1. **Contact entity and discovery** — create `Contact` from email/calendar history, classify tier and type
2. **Per-email signal extraction** — hook into `EmailSyncService` for latency, length, Haiku sentiment/formality/hedging
3. **Per-calendar signal extraction** — meeting frequency, cancellation tracking
4. **Health score computation engine** — `RelationshipEngine` class with weighted score, trend detection
5. **Alert generation** — threshold-based alerts for declining, dormant, improving
6. **Nightly reflection integration** — relationship analysis in Opus prompt
7. **Morning briefing surfacing** — relationship alerts and insights in morning session
8. **Network-level analysis** — communication clustering, cluster health, attention alignment
9. **Contact exclusion UI** — ability to exclude specific contacts from scoring
10. **Privacy controls** — consent flow, transparent model inspection, contact-level opt-out
11. **Supabase sync** — schema migration, RLS policies, signal and score sync
12. **Data lifecycle** — daily scores for 90 days, then weekly aggregates
