# Extract 08 — Communication & Relationships Intelligence

Source: `research/perplexity-outputs/v2/v2-08-communication-relationships.md`
Extracted: 2026-04-03

---

## DECISIONS

### ONA Architecture from Email Metadata
- Build a directed multigraph from email metadata: nodes = people, edges = communication events (one edge per email, preserving directionality)
- Node attributes: name, email, inferred role, inferred organisation, department (if discoverable), first-seen date, last-seen date, communication frequency bucket, importance tier (computed, not assigned)
- Edge attributes: direction (sender→recipient), timestamp, response latency (ms), thread ID, thread depth, TO/CC/BCC position, whether initiated or reply, attachment presence (boolean, not content)
- Compute seven centrality metrics per node: degree, in-degree, out-degree, betweenness, closeness, eigenvector, PageRank — each answers a different executive question (see ALGORITHMS)
- Use Rob Cross ONA methodology (UVA): map information flow, not org chart hierarchy. Cross's core finding: influence rarely correlates with title. The network reveals who actually drives decisions
- Use Aral and Van Alstyne's diversity-bandwidth tradeoff: executives who broker between diverse clusters get novel information but at bandwidth cost. Timed should detect when brokerage load becomes unsustainable
- Use Pentland's social physics: communication patterns (not content) predict team performance. Engagement energy, exploration, and equality of contribution are measurable from metadata alone
- Use Gloor's "honest signals" framework: email pattern analysis predicts top performers with higher accuracy than self-report surveys

### Relationship Health Scoring
- Score every dyadic relationship on a 0-100 scale combining: communication frequency trend, response latency trend, reciprocity ratio, thread depth trend, CC/BCC position stability
- Reciprocity ratio healthy range: 0.35-0.65 (Avrahami and Hudson). Outside this range = asymmetric relationship worth flagging
- Response latency is the single strongest signal of relational priority. Compute RTL_z: Z-score of response time per dyad relative to that dyad's own baseline (not global average)
- Track response time trajectory per relationship over rolling 4-week windows. Increasing RTL_z = declining priority. Decreasing = increasing engagement
- Thread depth trend: shortening threads = relationship moving toward transactional. Lengthening = deepening engagement or escalating conflict (disambiguate with other signals)

### Disengagement/Avoidance Detection
- Implement two composite scores: Relationship Disengagement Index (RDI) for detecting others' disengagement, and executive self-disengagement detection for the blind spot
- RDI has five weighted components: declining response rate, increasing response delay, fewer initiated contacts, reduced CC inclusion, dropped/declined meetings
- Implement Selective Withdrawal Score (SWS) to distinguish disengagement from busyness: if a person's metrics decline only toward the executive (not globally), it's disengagement. If declining across all relationships, it's busyness/overload
- Key quiet quitting signature from Chen et al. (847-worker study): 39% lower response rates is the core measurable signal
- Executive self-disengagement detection: compare the executive's response patterns to each contact against their own historical baseline. Flag when the executive is unconsciously deprioritising a strategically important relationship

### Calendar Analytics Intelligence
- Compute eight core calendar metrics: Meeting Load Index (MLI), Focus Block Ratio (FBR), Back-to-Back Chain Index (BTBCI), Organiser-Attendee Ratio (OAR), Strategic Time Ratio (STR), Attendee Entropy, Attendee Drift, Recurring Meeting Decay (RMD)
- Calendar Health Score = weighted composite of all eight metrics, normalised 0-100
- Meeting inflation detection: track total meeting hours per week on a 12-week rolling average. Alert when trend line slope exceeds executive's personalised threshold
- Cancelled meeting pattern analysis: when specific recurring meetings start getting cancelled, correlate with relationship health scores for those attendees — often predicts relationship or priority shifts before they surface

### Graph Storage Approach
- Use Supabase Postgres with recursive CTEs — not a dedicated graph DB. Rationale: the relationship graph is small (hundreds to low thousands of nodes for one executive's network), not millions. PostgreSQL handles this scale trivially
- Recursive CTEs handle path-finding (shortest path between two people, transitive connections) efficiently at this scale
- Store graph in relational tables (nodes table + edges table) with proper indexes on (from_node, to_node, timestamp)
- Reserve Neo4j/dedicated graph DB only if network exceeds ~50K nodes (unlikely for single-executive ONA)
- Use pgvector for embedding-based similarity search on relationship patterns, not for graph traversal

---

## DATA STRUCTURES

### ONA Node Schema
```
ona_nodes:
  id: uuid (PK)
  email: text (unique, canonical identifier)
  display_name: text
  inferred_role: text (nullable, derived from email patterns + signatures)
  inferred_organisation: text (nullable)
  inferred_department: text (nullable)
  first_seen_at: timestamptz
  last_seen_at: timestamptz
  total_emails_sent: int (to executive)
  total_emails_received: int (from executive)
  avg_response_latency_ms: float (to executive's emails)
  communication_frequency: float (emails per week, rolling 4-week)
  importance_tier: int (1-5, computed from centrality + frequency + executive context)
  degree_centrality: float
  in_degree_centrality: float
  out_degree_centrality: float
  betweenness_centrality: float
  closeness_centrality: float
  eigenvector_centrality: float
  pagerank: float
  relationship_health_score: float (0-100)
  health_trend: text ('improving', 'stable', 'declining', 'critical')
  last_computed_at: timestamptz
```

### ONA Edge Schema
```
ona_edges:
  id: uuid (PK)
  from_node_id: uuid (FK → ona_nodes)
  to_node_id: uuid (FK → ona_nodes)
  direction: text ('sent', 'received')
  timestamp: timestamptz
  response_latency_ms: int (nullable — null if not a reply)
  thread_id: text
  thread_depth: int
  recipient_position: text ('to', 'cc', 'bcc')
  is_initiated: boolean (true if first message in thread from this sender)
  has_attachment: boolean
  message_graph_id: text (Microsoft Graph message ID for dedup)
  created_at: timestamptz
```

### Relationship Graph with Decay
```
relationships:
  id: uuid (PK)
  executive_id: uuid (FK)
  contact_node_id: uuid (FK → ona_nodes)
  relationship_type: text ('direct_report', 'peer', 'superior', 'external', 'inferred')
  strength: float (0-1, computed from decay function)
  raw_strength: float (0-1, before decay applied)
  decay_rate: float (personalised per relationship)
  reciprocity_ratio: float (0-1, where 0.5 = perfectly balanced)
  response_latency_z: float (RTL_z — Z-score vs dyad baseline)
  thread_depth_avg: float (rolling 4-week)
  thread_depth_trend: float (slope of thread depth over time)
  cc_inclusion_rate: float (how often this person CCs executive)
  dependency_direction: text ('executive_depends', 'contact_depends', 'mutual', 'unclear')
  communication_channel_mix: jsonb ({"email": 0.7, "calendar": 0.3})
  last_interaction_at: timestamptz
  days_since_contact: int (computed)
  maintenance_alert_threshold_days: int (personalised)
  rdi_score: float (Relationship Disengagement Index, 0-1)
  sws_score: float (Selective Withdrawal Score, 0-1)
  health_score: float (0-100)
  health_trajectory: float[] (last 12 weekly scores)
  is_dormant: boolean
  is_strategically_important: boolean (executive-flagged or inferred)
  updated_at: timestamptz
```

### Calendar Analytics Metrics
```
calendar_daily_metrics:
  id: uuid (PK)
  executive_id: uuid (FK)
  date: date
  total_meetings: int
  total_meeting_minutes: int
  mli: float (Meeting Load Index — meeting hours / available hours)
  fbr: float (Focus Block Ratio — uninterrupted blocks >= 90min / total available)
  btbci: float (Back-to-Back Chain Index — longest consecutive meeting chain in hours)
  oar: float (Organiser-Attendee Ratio — meetings organised / meetings attended)
  str: float (Strategic Time Ratio — self-scheduled blocks / total calendar)
  attendee_entropy: float (Shannon entropy of meeting attendee distributions)
  attendee_drift: float (change in attendee composition vs 4-week baseline)
  rmd: float (Recurring Meeting Decay — % of recurring meetings actually held)
  calendar_health_score: float (0-100, weighted composite)
  fragmentation_index: float (number of context switches / available hours)
  meetings_cancelled: int
  meetings_declined: int
  meetings_added_reactively: int (added < 24h before start)
  computed_at: timestamptz

calendar_weekly_rollup:
  id: uuid (PK)
  executive_id: uuid (FK)
  week_start: date
  avg_mli: float
  avg_fbr: float
  max_btbci: float
  avg_oar: float
  avg_str: float
  avg_health_score: float
  meeting_inflation_slope: float (trend line slope over rolling 12 weeks)
  total_meeting_hours: float
  focus_hours: float
  reactive_meeting_pct: float
```

### Pipeline: Raw Microsoft Graph Data to Insight Candidates
```
Stage 1 — Ingestion (continuous, delta queries):
  Microsoft Graph /me/messages (delta) → raw_emails table
  Microsoft Graph /me/calendarView (delta) → raw_calendar_events table
  Fields captured: see APIS section

Stage 2 — Entity Resolution (Haiku, on each batch):
  raw_emails → deduplicate contacts by email
  → resolve aliases (same person, multiple addresses)
  → upsert ona_nodes
  → insert ona_edges

Stage 3 — Graph Computation (PostgreSQL, hourly):
  Recursive CTEs for path-finding and transitive closure
  Centrality metrics recomputed (degree: every batch; betweenness/eigenvector/PageRank: daily)
  Relationship strength with decay function applied

Stage 4 — Pattern Detection (Sonnet, daily):
  Compute RTL_z per dyad (response latency Z-scores)
  Compute RDI and SWS for flagged relationships
  Compute calendar metrics from raw_calendar_events
  Detect anomalies vs 12-week personalised baselines

Stage 5 — Intelligence Synthesis (Opus 4.6, nightly):
  Feed: graph metrics + temporal trends + anomaly flags + calendar health
  Output: insight candidates with confidence scores
  GraphRAG: embed graph structure as context for LLM reasoning
  Insight candidates written to insight_queue for morning delivery
```

---

## ALGORITHMS

### Centrality Metrics — What Each Tells the Executive
- **Degree centrality** (in + out): raw communication volume. High = hub. Useful for identifying who is over-relied-upon
- **In-degree centrality**: who receives the most communication. High in-degree + low response = bottleneck
- **Out-degree centrality**: who initiates the most. High out-degree = information broadcaster or micromanager
- **Betweenness centrality**: who sits on the shortest paths between others. THE key metric for identifying information bottlenecks and single points of failure. If person X has high betweenness and leaves, communication paths break. Cross's primary ONA finding
- **Closeness centrality**: how quickly information reaches someone from anyone. Low closeness = emerging silo risk
- **Eigenvector centrality**: connected to other well-connected people. Measures influence through network position, not title. Maps "who actually drives decisions"
- **PageRank**: like eigenvector but with directionality. Identifies people whose attention is disproportionately sought. High PageRank + no formal authority = hidden influencer

### Relationship Decay Functions
- **Burt's power function (primary recommendation)**: `Y = (T + 1) ^ (gamma + kappa * KIN + lambda * WORK)` where T = time since last contact, KIN/WORK = relationship type indicators. Fits 95% of variance across 19 studies (Burt 1999)
- **Exponential decay (simpler alternative)**: `strength = initial_strength * e^(-lambda * days_since_contact)` where lambda is personalised per relationship based on historical contact frequency
- **Step function (for alerting only)**: relationship status changes at defined thresholds — "active" (<14 days), "cooling" (14-30 days), "at risk" (30-60 days), "dormant" (>60 days). Thresholds personalised from the executive's own communication cadence per relationship
- Personalisation: compute each relationship's natural cadence from the first 12 weeks of data. Alert threshold = 2x the natural inter-contact interval for that specific dyad

### Disengagement Detection
- **RDI (Relationship Disengagement Index)**: weighted sum of five normalised components:
  - Response rate decline (weight 0.25): (current_rate - baseline_rate) / baseline_rate
  - Response latency increase (weight 0.25): (current_latency - baseline_latency) / baseline_latency
  - Initiated contact decline (weight 0.20): (current_initiated - baseline_initiated) / baseline_initiated
  - CC inclusion decline (weight 0.15): change in rate of CC-ing the executive
  - Meeting participation decline (weight 0.15): declined/cancelled meetings vs baseline
  - RDI > 0.4 over 4+ weeks = flag for review. RDI > 0.6 = high confidence disengagement
- **SWS (Selective Withdrawal Score)**: distinguishes disengagement from busyness
  - Compute person's response metrics toward executive AND toward other visible contacts
  - If metrics decline only toward executive: SWS high → selective disengagement
  - If metrics decline globally: SWS low → general busyness/overload
  - SWS = |RDI_toward_executive - RDI_toward_others| / max(RDI_toward_executive, RDI_toward_others)
- **Temporal window**: minimum 4 weeks of declining trend to flag, minimum 12 weeks of baseline data before any detection activates
- **Executive self-disengagement**: same RDI computation but measuring the executive's own patterns toward each contact. Compare executive's response latency to contact X against the executive's global average. If executive's latency to X is >1.5 sigma above their own mean and trending upward, flag as potential unconscious avoidance

### Calendar Health Score Computation
- `CHS = w1*MLI_norm + w2*FBR_norm + w3*BTBCI_norm + w4*STR_norm + w5*fragmentation_norm`
- Recommended weights: MLI(0.25), FBR(0.25), BTBCI(0.15), STR(0.20), fragmentation(0.15)
- Each metric normalised 0-100 where 100 = optimal:
  - MLI_norm: 100 when MLI < 0.4 (less than 40% of day in meetings), 0 when MLI > 0.8
  - FBR_norm: 100 when FBR > 0.3 (30%+ of day in 90min+ focus blocks), 0 when FBR = 0
  - BTBCI_norm: 100 when max chain < 2 hours, 0 when max chain > 5 hours
  - STR_norm: 100 when STR > 0.3, 0 when STR < 0.05
  - fragmentation_norm: 100 when < 4 context switches/day, 0 when > 12
- Meeting inflation detection: compute slope of weekly total_meeting_hours over rolling 12 weeks. If slope > 0.5 hours/week sustained for 4+ weeks, generate insight

### Anomaly Detection for Communication Patterns
- Baseline establishment: 12-week learning window (hard requirement — no anomaly scores delivered before this)
- Per-dyad baseline: mean and standard deviation of weekly email count, response latency, thread depth, reciprocity ratio
- Anomaly score: number of standard deviations from baseline for each metric
- Compound anomaly: when 3+ metrics for the same dyad are simultaneously >1.5 sigma, flag as high-priority
- Temporal pattern: use rolling 4-week windows compared to 12-week baseline. This catches gradual drift, not just sudden changes
- Communication burst detection: >3 sigma spike in email volume with a specific person within a 48-hour window → correlate with calendar (crisis meeting?) and flag if no calendar context explains it

---

## APIS & FRAMEWORKS

### Microsoft Graph API Fields — Email
```
GET /me/messages (with delta query for incremental sync)
Fields to capture:
  - id (message ID for dedup)
  - conversationId (thread grouping)
  - conversationIndex (thread depth derivation)
  - receivedDateTime / sentDateTime
  - from.emailAddress.address
  - toRecipients[].emailAddress.address
  - ccRecipients[].emailAddress.address
  - bccRecipients[].emailAddress.address (only visible on sent items)
  - isRead, isDraft
  - importance (high/normal/low — set by sender)
  - hasAttachments (boolean, never read content)
  - internetMessageHeaders (for reply chain analysis, Message-ID / In-Reply-To / References)
  - inferenceClassification ('focused' vs 'other' — Outlook's own categorisation)
  - flag.flagStatus (followUp signals)
  - bodyPreview (first 255 chars — use ONLY for length estimation, never content analysis)
```

### Microsoft Graph API Fields — Calendar
```
GET /me/calendarView (with delta query)
Fields to capture:
  - id (event ID)
  - subject (for meeting type classification only, not content)
  - start.dateTime / end.dateTime / start.timeZone
  - isAllDay
  - organizer.emailAddress.address
  - attendees[].emailAddress.address
  - attendees[].status.response ('accepted', 'declined', 'tentativelyAccepted', 'none')
  - attendees[].type ('required', 'optional', 'resource')
  - isOrganizer (boolean)
  - isCancelled
  - recurrence (pattern object — for recurring meeting tracking)
  - onlineMeeting (presence/absence signals remote vs in-person)
  - showAs ('busy', 'tentative', 'free', 'oof', 'workingElsewhere')
  - responseStatus.response (executive's own response)
  - createdDateTime (when was meeting created — for reactive vs planned classification)
  - lastModifiedDateTime (for tracking changes/rescheduling)
  - sensitivity ('normal', 'personal', 'private', 'confidential')
```

### Research Frameworks
- **Rob Cross ONA (UVA)**: organisational network analysis methodology. Core insight: mapping actual information flow (not org chart) reveals bottlenecks, silos, hidden influencers. Primary method: email metadata analysis. Key publication: "Beyond Collaboration Overload" (HBR Press)
- **Aral and Van Alstyne (MIT)**: diversity-bandwidth tradeoff. Brokers who span structural holes get novel information but can't maintain deep ties across all clusters. Directly applicable to executive overextension detection
- **Pentland social physics (MIT Media Lab)**: communication patterns predict team outcomes better than content. "Honest signals" — measurable behavioural patterns that encode social dynamics. Email metadata captures a subset of these signals
- **Gloor creative swarms**: collaborative innovation through network analysis. Email patterns predict top performers. Relevant for identifying which of the executive's contacts drive the most productive collaborations
- **Burt structural holes**: relationships decay predictably without maintenance. The power function model is the gold standard for professional relationship decay. Directly implementable
- **Dunbar's number**: cognitive limit on stable relationships (~150). For executives, the active relationship set is typically 20-40 people. Timed should track this number and alert when it exceeds the executive's demonstrated capacity
- **Granovetter weak ties**: dormant relationships with low-frequency contacts are disproportionately valuable for novel information. Timed should distinguish dormant-important from dormant-unimportant

### Graph Embedding for LLM Reasoning
- Do NOT use graph neural networks for this scale. LLMs can reason over graph structures when metrics are pre-computed and serialised as structured text
- GraphRAG approach (Microsoft Research): embed graph structure + computed metrics as context for LLM. LLM generates narrative interpretations
- Optimal division of labour: PostgreSQL computes graph metrics → time-series analysis detects anomalies → LLM (Opus 4.6) synthesises narrative insight from structured metric feeds
- Feed format for Opus: JSON with node attributes, edge summaries, temporal trends, anomaly flags. NOT raw adjacency matrices
- LLM accuracy on anomaly narration: reliable when given pre-computed metrics and explicit trend directions. Hallucination risk increases when LLM must infer trends from raw numbers — always pre-compute the trend direction and magnitude

### Temporal Sequence Modelling
- For communication pattern anomaly detection, classical statistical methods (Z-scores, rolling means, trend slopes) outperform neural approaches at this data scale
- Reserve neural temporal models only if the executive's network exceeds ~500 active contacts with daily interaction data
- The 12-week baseline + 4-week rolling window comparison is sufficient for detecting all relevant patterns

---

## NUMBERS

### ONA Accuracy: Email vs Survey
- Passive ONA (email metadata) captures ~60-70% of the communication network that survey-based ONA captures (Pentland)
- Email-only ONA misses 30-40% of productivity variance because face-to-face and chat channels are not captured
- Passive ONA captures ~80% of strong ties but only ~40% of weak ties (weak ties often maintained through non-email channels)
- For executive-level ONA (where email is the dominant formal channel), accuracy is higher: estimated 75-85% of true network structure
- Augmenting email with calendar data (co-attendance) recovers an additional 10-15% of missed relationships

### Response Latency Benchmarks
- Avrahami and Hudson: 90.1% accuracy in predicting response latency from relationship features
- Median executive email response time: 2-4 hours for important contacts, 24-48 hours for routine
- Response time <1 hour consistently correlates with high relational priority
- Response time >48 hours (absent vacation/OOF) correlates with low priority or avoidance
- A 2x increase in response latency to a specific person over 4 weeks is a reliable early warning signal

### Calendar Density Thresholds
- McKinsey: only 9% of executives are satisfied with their time allocation
- MLI > 0.6 (60%+ of day in meetings): cognitive overload zone, executive decision quality degrades
- MLI > 0.8: crisis territory — schedule is unsustainable
- FBR < 0.1 (less than 10% of day in 90min+ focus blocks): deep work impossible
- BTBCI > 4 hours (4+ consecutive hours of back-to-back meetings): cognitive fatigue threshold
- Executives with FBR > 0.25 report significantly higher strategic thinking capacity

### Meeting Inflation Detection
- Average meeting inflation rate: 2-5% increase in meeting hours per quarter (compounding)
- Detectable after 8 weeks of data with rolling average comparison
- A sustained slope of >0.5 additional meeting hours per week over 4+ weeks = statistically significant inflation
- Meeting inflation is the #1 silent productivity killer for C-suite — most executives don't notice until it's severe

### Disengagement Detection Accuracy
- Chen et al. (847 workers): 39% lower response rates as core quiet quitting signature
- Temporal window for reliable inference: minimum 4 weeks of pattern to distinguish from noise
- False positive rate with single-signal detection (response time only): ~30-40%
- False positive rate with compound RDI (5 signals): estimated 10-15%
- SWS (selective vs global withdrawal) reduces false positives by an additional ~50%
- 12-week baseline required before ANY disengagement scores are generated

---

## ANTI-PATTERNS

### Surface-Level Analytics to Avoid
- "You received 200 emails today" — zero intelligence value. Never report raw counts without context
- "You spent 6 hours in meetings" — useless without comparison to baseline, trend, and quality decomposition
- "Your busiest day was Wednesday" — trivial pattern recognition. The executive already knows this
- Any metric without a temporal trend is noise. Always show trajectory, not snapshots
- Generic benchmarks ("executives average 5 hours of meetings") — Timed must personalise to THIS executive's patterns, not industry averages

### ONA Biases from Email-Only Data
- Email captures formal communication disproportionately. Informal influence networks (hallway conversations, Slack DMs, phone calls) are invisible
- Email overrepresents hierarchical communication and underrepresents peer-to-peer collaboration
- External contacts are underrepresented — the executive may have critical relationships maintained entirely through phone/in-person
- Pentland's finding: email-only ONA misses 30-40% of productivity variance. Mitigate by augmenting with calendar co-attendance data
- Cultural bias: some organisations and individuals prefer email; others use Teams/Slack. ONA accuracy varies by organisational communication culture
- Recency bias: centrality metrics weight recent communication. A strategically important but dormant relationship appears unimportant in the graph

### False Positives in Disengagement Detection
- **Vacation/leave**: person goes silent for 2 weeks — not disengagement. Must cross-reference with OOF status and global communication drop
- **Project cycles**: end of a project naturally reduces communication with that project's team. Must track project context
- **Role changes**: person moves to a new role and naturally communicates with different people. Not disengagement from executive specifically
- **Seasonal patterns**: Q4 crunch, holiday periods, fiscal year boundaries all create communication pattern shifts unrelated to relationship health
- **Single-signal reliance**: using only response time OR only email frequency produces 30-40% false positives. Always use compound RDI with 5+ signals
- **Short observation windows**: less than 4 weeks of declining trend is insufficient to distinguish signal from noise. The 12-week baseline + 4-week detection window exists for a reason

### Relationship Asymmetry Blind Spots
- The executive may consider someone critically important but rarely email them (relationship maintained through in-person meetings, phone, or delegation)
- Conversely, high email volume may indicate operational dependency, not strategic importance
- Timed must allow the executive to flag relationships as "strategically important" regardless of email volume — these get monitored with different thresholds
- Dormant-but-important relationships (Granovetter weak ties) should never trigger decay alerts if executive has flagged them
- The executive's own self-disengagement is the hardest blind spot: they don't notice they've stopped responding promptly to someone they used to prioritise. SWS applied to the executive's own patterns is the only detection mechanism
