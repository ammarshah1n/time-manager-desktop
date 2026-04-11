# Extract 11 — Privacy Architecture, Trust-Earning & Consent Framework

Source: `research/perplexity-outputs/v2/v2-11-privacy-trust.md`

---

## DECISIONS

### Local vs cloud processing boundary per data type
- **Keystroke dynamics**: NEVER leave device. Process entirely on-device into feature vectors (typing cadence, pause patterns, decision hesitation signals). Raw keystrokes stay in-process memory only — not even persisted to disk. Intelligence value fully preserved as feature vectors.
- **Voice audio**: NEVER leave device. Use Apple Speech framework (on-device Whisper/Neural Engine) for transcription + acoustic feature extraction. Raw audio never written to disk. Only extracted features (speech rate, pause duration, vocal energy contours — NOT emotional inference) sent as feature vectors.
- **Application usage patterns**: Process on-device into session summaries (app name, duration, switching frequency). Raw window titles/URLs never leave device — too much PII leakage risk. Only aggregate behavioural features (focus duration, context-switching rate, deep-work blocks) sent to Supabase.
- **Email metadata** (via Microsoft Graph): Can be processed in Supabase with RLS. Already exists in Microsoft's cloud. Metadata only (sender, recipient, timestamp, subject line, thread structure) — never email body content. Encrypted at rest in Supabase with user-held keys.
- **Calendar data** (via Microsoft Graph): Can be processed in Supabase with RLS. Lowest sensitivity tier. Meeting patterns, scheduling density, time allocation. Encrypted at rest.
- **Cognitive model / reflection outputs**: Stored in Supabase encrypted with user-held keys. Claude API processes feature vectors + metadata to produce reflections. The cognitive model is the most valuable asset — zero-knowledge encryption mandatory.

### Encryption architecture
- **At rest (on-device)**: FileVault for full-disk encryption. App-level encryption using Keychain-stored keys for the local data store. Biometric-gated Keychain access (Touch ID) for unlocking local cognitive data.
- **At rest (Supabase)**: AES-256-GCM client-side encryption before data leaves the device. User-held Key Encryption Keys (KEKs) derived via PBKDF2, stored in Secure Enclave. Supabase never holds plaintext — zero-knowledge model (Signal/ProtonMail pattern).
- **In transit**: TLS 1.3 mandatory for all connections. Certificate pinning for Supabase and Claude API endpoints. No fallback to lower TLS versions.
- **Key management hierarchy**: Master password → PBKDF2 → KEK stored in Secure Enclave → per-data-type Data Encryption Keys (DEKs) wrapped by KEK. Device-bound: decryption requires both the password AND the specific hardware Secure Enclave. A Supabase breach yields only AES-256-GCM ciphertext that is computationally useless without both factors.

### Trust-earning sequence (week-by-week permission expansion)
- **Week 1 — Calendar only**: Lowest creepiness threshold. Request only calendar access via Microsoft Graph. Demonstrate value: meeting load analysis, time allocation insights, scheduling pattern recognition. No behavioural data. Goal: establish Timed as useful and non-threatening.
- **Week 2 — Add email metadata**: After demonstrating calendar intelligence, request email metadata access. Show communication pattern insights (response time trends, thread complexity, stakeholder mapping by frequency). Still metadata only, never content.
- **Week 3 — Add application usage**: Request Accessibility API permissions. Show focus/fragmentation analysis, deep work block identification, context-switching costs. This is the first on-device behavioural signal — present it as "focus analytics" not "screen monitoring."
- **Week 4 — Add voice analysis + keystroke dynamics**: Highest creepiness threshold — requested last, only after 3 weeks of demonstrated value. Present as "decision rhythm analysis" not "keystroke logging." Voice framed as "meeting energy patterns" not "voice surveillance." By this point, the cognitive model's irreplaceability is the primary retention mechanism.

### Consent UX design
- **Layered consent**: Broad plain-language summary at top, with drill-down detail available but not forced. Never a wall-of-text EULA.
- **Just-in-time consent**: Request each permission at the moment it becomes relevant (Week 1-4 sequence), not all upfront. Each request accompanied by evidence of value already delivered.
- **Dynamic consent**: Ongoing ability to revoke any individual data stream without losing the rest. Revocation is instant and visible. Re-granting is easy but never nagged.
- **Privacy nutrition labels** (Kelley & Cranor model): For each data type, show a simple grid: what is collected, where it is processed, how long it is retained, who can access it. Always visible in settings, not buried.
- **Language rules**: Say "calendar patterns" not "calendar surveillance." Say "typing rhythm" not "keystroke logging." Say "meeting energy" not "voice analysis." Say "focus time" not "screen monitoring." Never use the word "track" — use "observe" or "notice."

### Positioning to the executive
- **Frame as cognitive infrastructure**, not monitoring software. Timed is "your external memory and pattern recognition" — the executive equivalent of having a chief of staff who notices everything but never acts without permission.
- **Lead with control**: Every onboarding screen emphasises what Timed will NEVER do (send emails, modify calendars, share data, act autonomously). Control is the trust signal that matters most for C-suite personalities (high need for control, high self-monitoring).
- **Visible local processing indicator**: Menu bar icon shows real-time processing location — green dot for on-device, nothing for cloud features. Makes the privacy architecture tangible.
- **Audit log always accessible**: Complete record of every data access, every API call, every feature vector sent to cloud. Executive can inspect at any time. Transparency as trust architecture, not just policy.

### Data ownership and portability
- **Executive owns all data unconditionally**. Data processing agreement structured so Timed is a data processor, executive is the data controller. Cognitive model belongs to the individual, not to their employer, not to Timed.
- **Full export**: One-click export of all data in standard formats (JSON, CSV). Includes raw stored data + cognitive model + reflection history. GDPR Article 20 data portability compliance.
- **Full deletion**: One-click irreversible deletion of all cloud data. Local data deletion controlled by the executive. Deletion is cryptographic (key destruction) — not row deletion from Supabase. Destroy the KEK and all ciphertext becomes permanently unrecoverable.
- **Legal isolation from employer**: Personal cognitive model stored under personal account, not corporate SSO. Even if company owns the device, the cognitive model is encrypted with personal keys the employer cannot compel Timed to provide. Data processing agreement explicitly excludes employer access.

---

## DATA STRUCTURES

### Privacy architecture diagram

```
DEVICE (never leaves)                    SUPABASE (zero-knowledge encrypted)
┌─────────────────────────┐              ┌──────────────────────────────┐
│ Raw keystroke events     │              │ Email metadata (AES-256-GCM) │
│ Raw voice audio          │              │ Calendar data (AES-256-GCM)  │
│ Raw screen/window data   │              │ Feature vectors (AES-256-GCM)│
│ Application URLs/titles  │              │ Cognitive model (AES-256-GCM)│
│                          │              │ Reflection outputs (AES-256) │
│ ┌──────────────────────┐ │              │                              │
│ │ Feature Extraction    │ │              │ KEK: NEVER stored here       │
│ │ - Typing cadence vec  │ │  encrypted   │ RLS: per-user row isolation  │
│ │ - Voice feature vec   │ │  features    │                              │
│ │ - Focus session stats │ │ ──────────►  │                              │
│ │ - App usage aggregate │ │  only        │                              │
│ └──────────────────────┘ │              └──────────┬───────────────────┘
│                          │                         │
│ Secure Enclave           │                         │ encrypted feature
│ ├─ KEK (PBKDF2-derived) │                         │ vectors only
│ ├─ DEKs (wrapped)        │                         ▼
│ └─ Biometric gate        │              ┌──────────────────────────────┐
└─────────────────────────┘              │ CLAUDE API (stateless)        │
                                          │ Receives: feature vectors +   │
                                          │   metadata (never raw data)   │
                                          │ Returns: reflections, insights│
                                          │ Retains: nothing (no logging) │
                                          └──────────────────────────────┘
```

Key management:
```
Executive Password
       │
       ▼ PBKDF2 (100K+ iterations, random salt)
   ┌───────┐
   │  KEK  │ ← stored in Secure Enclave, biometric-gated
   └───┬───┘
       │ wraps/unwraps
       ▼
   ┌───────┐  ┌───────┐  ┌───────┐  ┌───────┐
   │DEK-cal│  │DEK-eml│  │DEK-ftr│  │DEK-cog│
   └───────┘  └───────┘  └───────┘  └───────┘
   Calendar    Email      Feature    Cognitive
   data        metadata   vectors    model
```

### Trust-earning sequence

| Week | Permissions Requested | Value Demonstrated Before Ask | Trust Checkpoint | Success Signal |
|------|----------------------|------------------------------|------------------|----------------|
| 1 | Calendar read (Graph API) | None — first ask, lowest threat | Onboarding: plain-language privacy summary, visible "on-device" indicator | Executive opens morning session 3+ times |
| 2 | Email metadata read (Graph API) | "You had 14 meetings last week, 6 with no clear agenda. Tuesday 2-5pm was your only deep-work window." | End-of-week-1 report with opt-in prompt: "Want communication pattern insights too?" | Executive reads email pattern report, doesn't revoke |
| 3 | Accessibility API (app usage) | Email response time trends, stakeholder communication map, thread complexity scoring | End-of-week-2 insight: "Your CFO emails take 3x longer to reply to than average — want to see where your focus time goes?" | Executive checks focus analytics daily |
| 4 | Microphone (voice) + Accessibility (keystroke) | Focus/fragmentation analysis, deep-work block identification, context-switching cost in hours | End-of-week-3: "I can see your calendar and communication patterns. Your decision quality likely varies by time of day — voice and typing rhythm analysis would let me show you when." | Executive grants both; opens morning session as habit |

**Transition signal — "trying" to "depending"**: Executive references Timed insights in conversations with others. Opens morning session before checking email. Mentions feeling "blind" on days Timed was paused. Measurable: >5 consecutive days of morning session engagement, >80% of proactive alerts opened.

### Adversarial threat model

| Scenario | Likelihood | Impact | Technical Mitigation | Legal Mitigation |
|----------|-----------|--------|---------------------|-----------------|
| **1. Supabase breach** | Medium (misconfigured RLS is common attack surface) | Low with encryption — attacker gets AES-256-GCM ciphertext only | Zero-knowledge client-side encryption. KEK in Secure Enclave, never on server. Per-user DEKs. RLS as defence-in-depth, not primary. | Data breach notification obligations met, but no meaningful data exposed. |
| **2. Divorce subpoena** | Low-Medium (high-net-worth executives) | High — cognitive model could reveal decision patterns, stress periods, communication habits | Cryptographic deletion capability. Executive can destroy KEK instantly, rendering all Supabase data permanently unrecoverable. Local data under FileVault + biometric. | Data processing agreement structures Timed as processor with no independent access. Executive's attorney can argue cognitive model is health data (Article 9 equivalent) exempt from discovery. |
| **3. Corporate litigation discovery** | Medium | CRITICAL — genuinely unsettled legal territory | Architectural separation: cognitive model under personal account, not corporate SSO. Corporate email metadata is already in Microsoft's systems — Timed adds no new corporate exposure. Cognitive model encrypted with personal keys. | **Novel risk**: no precedent for whether executive decision-rhythm patterns are discoverable corporate records or protected personal health data. MUST get outside counsel opinion before launch. Timed's data processing agreement should explicitly define cognitive model as personal health data. |
| **4. Corporate espionage** | Low | Extreme — cognitive model reveals decision-making patterns, blind spots, stress responses, stakeholder relationships | Zero-knowledge encryption makes server-side extraction useless. On-device data protected by FileVault + app-level encryption + biometric gate. | Trade secret protections apply to cognitive model. NDA + non-compete for all Timed employees with backend access. |
| **5. Insider threat (Timed employee)** | Medium | Should be zero if architecture is correct | Zero-knowledge: Timed employees/contractors see ONLY ciphertext in Supabase. No admin backdoor to decrypt. No master key. Server logs show access patterns but not content. Principle of least privilege for all backend access. | Employment agreements with specific data handling obligations. Background checks. Separation of duties (no single employee can modify encryption architecture). |
| **6. Government subpoena** | Low | Depends on jurisdiction | Zero-knowledge response: "We can provide the ciphertext but cannot decrypt it. Decryption requires the user's device and password." Data residency in user's jurisdiction (configurable Supabase region). | CLOUD Act applies to US-incorporated entities. Mitigation: incorporate in privacy-friendly jurisdiction. For Australian users, Privacy Act requires warrant for access. EU users: GDPR adequacy requirements limit cross-border transfer. |

### Consent state machine

```
States: DORMANT → CALENDAR_ONLY → CAL_EMAIL → CAL_EMAIL_APPS → FULL_OBSERVATION
                                                                        │
        ◄──────────────────── PARTIAL_REVOKE (any individual stream) ◄──┘
        │
        ▼
    PAUSED (all observation stopped, model frozen, data retained encrypted)
        │
        ▼
    DELETED (KEK destroyed, all cloud data permanently unrecoverable)

Transitions:
- DORMANT → CALENDAR_ONLY: Onboarding consent (just-in-time, Week 1)
- CALENDAR_ONLY → CAL_EMAIL: Trust checkpoint end-of-Week-1 (value demo required)
- CAL_EMAIL → CAL_EMAIL_APPS: Trust checkpoint end-of-Week-2 (value demo required)
- CAL_EMAIL_APPS → FULL_OBSERVATION: Trust checkpoint end-of-Week-3 (value demo required)
- Any state → PARTIAL_REVOKE: User toggles off individual stream in settings (instant)
- PARTIAL_REVOKE → previous state: User re-enables stream (no re-consent wall, just toggle)
- Any state → PAUSED: User pauses all observation (one tap, menu bar)
- PAUSED → previous state: User resumes (one tap)
- Any state → DELETED: User requests full deletion (confirmation dialog, then cryptographic KEK destruction)
- DELETED is terminal — no recovery possible
```

---

## ALGORITHMS

### Progressive permission expansion logic
```
func shouldRequestNextPermission(currentState: ConsentState, metrics: EngagementMetrics) -> PermissionRequest? {
    // Only expand if:
    // 1. Minimum time in current state elapsed (7 days)
    // 2. Engagement threshold met (user opened morning session 3+ of last 5 days)
    // 3. Value demonstration delivered (at least 1 insight the user explicitly opened/read)
    // 4. No recent revocation (user hasn't revoked anything in last 14 days)

    guard metrics.daysInCurrentState >= 7 else { return nil }
    guard metrics.morningSessionOpenRate(last: 5) >= 0.6 else { return nil }
    guard metrics.insightsEngaged(last: 7) >= 1 else { return nil }
    guard metrics.daysSinceLastRevocation >= 14 else { return nil }

    switch currentState {
    case .calendarOnly:
        return .emailMetadata(valueEvidence: metrics.topCalendarInsight)
    case .calendarEmail:
        return .appUsage(valueEvidence: metrics.topCommunicationInsight)
    case .calendarEmailApps:
        return .voiceAndKeystroke(valueEvidence: metrics.topFocusInsight)
    case .fullObservation:
        return nil // fully expanded
    }
}
```

### Trust checkpoint evaluation
- Trigger: `daysInCurrentState >= 7` AND engagement thresholds met
- Presentation: non-modal, in the morning session context. "Based on your calendar patterns, I noticed X. Email metadata would let me show Y too. Want to enable it?" Always show what value was already delivered alongside what new value is possible.
- Decline handling: accept gracefully, do not re-ask for 14 days minimum. Never nag. Record decline reason if voluntarily given.
- Approval handling: enable immediately, show first insight from new data source within 24 hours (fast reward loop — Hook Model investment phase).

### On-device feature extraction → cloud intelligence boundary
```
Raw Signal (on-device only)          Feature Vector (can leave device)
─────────────────────────────        ──────────────────────────────────
Keystroke events (key, time)    →    Typing cadence vector: [WPM, pause_mean,
                                     pause_variance, backspace_rate,
                                     hesitation_before_send, burst_length]

Voice audio (PCM samples)      →    Acoustic features: [speech_rate,
                                     pause_duration_mean, pitch_variance,
                                     energy_contour_summary, silence_ratio]
                                     (NO emotional labels, NO speaker ID)

Window titles, URLs, app names →    Session summary: [app_category,
                                     duration_seconds, switch_count,
                                     focus_block_bool]

Screen content                 →    NEVER CAPTURED. Not even on-device.
```

Critical invariant: the feature extraction is **lossy by design** — you cannot reconstruct the raw signal from the feature vector. This is the architectural guarantee that makes the cloud boundary defensible. Typing cadence vectors cannot reveal what was typed. Acoustic features cannot reconstruct speech. Session summaries cannot reveal what was read.

### Data minimisation pipeline
```
Raw data → Feature extraction (on-device) → Feature vectors → Encrypt (AES-256-GCM with DEK) → Supabase
                                                                                                    │
                                                                                                    ▼
                                                                                            Decrypt on-demand
                                                                                                    │
                                                                                                    ▼
                                                                                            Claude API (stateless)
                                                                                                    │
                                                                                                    ▼
                                                                                            Reflection output → Encrypt → Supabase

Retention policy:
- Raw data: never persisted (in-memory only during feature extraction)
- Feature vectors: retained encrypted, rolling 90-day window for granular data
- Aggregated features: retained indefinitely (low storage, high intelligence value)
- Cognitive model + reflections: retained indefinitely (the compounding asset)
- Deletion: KEK destruction makes all encrypted data unrecoverable
```

---

## APIS & FRAMEWORKS

### Apple privacy frameworks
- **TCC (Transparency, Consent, and Control)**: macOS system-level permission framework. Timed must request: Accessibility (app usage, keystroke dynamics), Microphone (voice analysis), Contacts/Calendar if local. Each triggers a system-level consent dialog — Timed cannot bypass. Map Week 1-4 sequence to TCC permission requests.
- **App Sandbox**: Required for Mac App Store distribution. Limits file system access, network access, hardware access to declared entitlements. Each entitlement must be justified in App Store review.
- **FileVault**: Full-disk encryption. Ensure Timed's local data store benefits from FileVault — do not duplicate encryption if FileVault is active, but DO NOT rely on FileVault alone (user may disable it). App-level Keychain encryption is the independent guarantee.
- **Keychain Services / Secure Enclave**: Store KEK in Secure Enclave via `kSecAttrTokenIDSecureEnclave`. Biometric-gated access via `kSecAccessControlBiometryCurrentSet`. Keys are hardware-bound and non-exportable.
- **Core ML / Neural Engine**: Use for on-device feature extraction models (typing cadence classification, acoustic feature extraction). Apple Silicon Neural Engine is fast enough for real-time feature extraction without cloud roundtrip.

### macOS entitlements per data type
| Data Type | Entitlement | TCC Category |
|-----------|------------|--------------|
| Calendar (Graph API) | `com.apple.security.network.client` | None (API access, not local) |
| Email metadata (Graph API) | `com.apple.security.network.client` | None (API access, not local) |
| Application usage | `com.apple.security.automation.apple-events` + Accessibility | `kTCCServiceAccessibility` |
| Keystroke dynamics | Accessibility API | `kTCCServiceAccessibility` |
| Voice analysis | `com.apple.security.device.microphone` | `kTCCServiceMicrophone` |
| Local file storage | `com.apple.security.files.user-selected.read-write` | None if within sandbox container |

### Legal frameworks
- **GDPR Article 9**: Keystroke dynamics = biometric data = special category. Requires EXPLICIT consent (not legitimate interest, not contract necessity). Voice acoustic features: only special category if used for identification — Timed uses them for cognitive state, not identity. BUT must architecturally prevent emotion inference from biometric data (EU AI Act overlap).
- **EU AI Act Article 5(1)(f)**: **In force since 2 February 2025.** Prohibits emotion inference from biometric data in workplaces. Timed's voice analysis is legal ONLY if it demonstrably infers cognitive states (focus, fragmentation, decision rhythm) from NON-IDENTIFYING acoustic features — not emotions from biometric identification. This line must be enforced architecturally: the feature extraction pipeline must provably exclude emotion classification labels.
- **EU AI Act Article 6**: Timed likely classifies as high-risk AI system (AI in employment/workforce management context, Annex III point 4). Requires: risk management system, data governance, technical documentation, transparency to users, human oversight, accuracy/robustness.
- **CCPA/CPRA**: Keystroke dynamics and biometric data are "sensitive personal information" under CPRA. Requires opt-in consent (not opt-out). Right to delete, right to know, right to limit use. No sale of data (Timed never sells).
- **UK GDPR**: Mirrors EU GDPR but post-Brexit divergence on AI provisions. Keystroke dynamics = biometric special category data. ICO guidance on workplace monitoring requires DPIA before deployment.
- **Australian Privacy Act (2024 reforms)**: New statutory tort for serious invasions of privacy — covers unauthorised surveillance. Consent architecture is legally critical for Australian market. Australian Privacy Principles (APPs) require: notification of collection, consent for sensitive information (biometrics), cross-border disclosure restrictions.

### Zero-knowledge architecture principles (Signal/ProtonMail model)
- Server stores only ciphertext — never plaintext, never keys
- Encryption/decryption happens exclusively on client device
- Server operator cannot comply with decryption requests because they cannot decrypt
- Key derivation from user password + device hardware (not server-stored)
- Forward secrecy: compromising one key does not compromise historical data
- Timed adaptation: Supabase stores AES-256-GCM ciphertext. KEK in Secure Enclave. Timed (the company) literally cannot access user data — this is architecturally enforced, not policy-based.

---

## NUMBERS

### Trust-building timeline benchmarks
- **Week 1-2**: "Trying it out" phase. 40-60% of users drop off if no clear value demonstrated by Day 5 (Rogers adoption curve — early majority needs evidence).
- **Week 3-4**: "Evaluating" phase. Users who reach Week 3 with daily engagement have ~80% retention through Week 8 (Hook Model investment phase — sunk cost of cognitive model).
- **Day 21-28**: Critical habit formation window. If executive opens morning session as part of daily routine by Day 21, probability of long-term retention exceeds 85% (Eyal's Hook Model + Lally et al. habit formation research: median 66 days for full automaticity, but 21 days for initial routine establishment).
- **"Point of no return"**: Approximately Week 6-8. By this point, the cognitive model contains enough compounded intelligence that the executive experiences turning it off as "losing a capability" rather than "stopping a tool." This is the retention moat.

### Privacy paradox research findings
- Privacy Calculus Theory (Culnan & Armstrong): Users disclose personal data when perceived benefits exceed perceived risks. For executives: perceived benefit must be framed as cognitive leverage and time recovery, not convenience features.
- The privacy paradox (stated concern vs actual behaviour) is WEAKER in high-stakes professional contexts — executives are more deliberate about privacy decisions than general consumers. Implication: do not assume executives will "just click accept." Each permission must be earned.
- Perceived control is the strongest moderator of privacy concern (Xu et al., 2011). Executives with high perceived control over their data are 2-3x more likely to grant sensitive permissions.

### Creepiness thresholds by data type (ordered least to most threatening)
1. **Calendar structure** — lowest perceived intimacy. "It's just my schedule." Near-zero resistance.
2. **Email metadata** (not content) — low-medium. "Just who I email and when, not what I say." Acceptable with framing.
3. **Application usage** — medium. "It knows what apps I use." First real privacy friction point. Frame as "focus analytics."
4. **Voice analysis** — high. "It listens to me." Strong emotional reaction. Must demonstrate massive value before requesting. Frame as "meeting energy," never "voice surveillance."
5. **Keystroke dynamics** — highest. "It watches me type." Maximum creepiness. Frame as "decision rhythm," never "keylogging." Only request after 3 weeks of trust.

### Data breach exposure analysis per encryption layer
| Layer Compromised | Data Exposed | Usability to Attacker |
|---|---|---|
| Supabase RLS bypassed (no encryption breach) | Row-level data visible but encrypted | None — AES-256-GCM ciphertext without KEK |
| Supabase full database dump | All ciphertext for all users | None — per-user KEKs in per-user Secure Enclaves |
| TLS intercepted (MITM) | In-transit ciphertext | None — already encrypted client-side before TLS |
| Device stolen (locked) | FileVault-encrypted disk | None without login password |
| Device stolen (unlocked, no biometric) | Local data store | Keychain items still biometric-gated (Secure Enclave) |
| Device stolen (unlocked + biometric compromised) | Full local data + ability to decrypt Supabase data | FULL EXPOSURE — this is the residual risk. Mitigation: remote KEK destruction via authenticated API call from another device. |

---

## ANTI-PATTERNS

### Requesting all permissions upfront
- Triggers immediate rejection, especially from executives (high need for control, high privacy deliberation). Research shows upfront permission dumps reduce grant rates by 50-70% compared to graduated requests. The Week 1-4 sequence exists specifically to avoid this. NEVER present a "grant all permissions" screen during onboarding.

### Storing raw audio or keystroke content
- Raw audio storage creates biometric identification capability — triggers GDPR Article 9, EU AI Act Article 5(1)(f), and Australian Privacy Act statutory tort exposure simultaneously. Raw keystroke content reveals passwords, personal messages, confidential business content. The feature extraction pipeline's lossy design is the mitigation — it is not an optimisation, it is a legal requirement. NEVER persist raw signals to disk, even temporarily. In-memory only, extracted features only.

### Enterprise device complications (employer rights to cognitive model)
- If executive uses a company-issued device, employer MDM can potentially access FileVault recovery keys, installed applications, and network traffic. The cognitive model stored under corporate SSO could be claimed as corporate property. **Mitigation**: Timed MUST use personal accounts, not corporate SSO. Personal KEK in personal Secure Enclave. Even if employer has device admin rights, they cannot compel Timed to provide decryption keys. The data processing agreement must explicitly state the cognitive model is personal data belonging to the individual, not the corporation.
- If the company has a BYOD policy, the risk is lower but still present. Timed should detect MDM enrollment and warn the executive: "This device is managed by [org]. Your cognitive model is encrypted with your personal keys, but [org] has administrative access to this device."

### Litigation discovery exposure from Supabase data
- **The unsettled legal question**: There is no direct precedent for whether an AI-generated executive cognitive model is a discoverable corporate record or protected personal health data. If a court classifies it as a corporate record, Timed could be compelled to produce it (or the executive compelled to provide decryption keys).
- **Architectural mitigation**: Zero-knowledge encryption means Timed cannot produce plaintext even if subpoenaed. The executive can be compelled to provide keys, but can also invoke Fifth Amendment (US) / privilege against self-incrimination protections.
- **Pre-launch requirement**: Get outside counsel opinion on cognitive model's evidentiary classification before launch. Structure the data processing agreement to classify the cognitive model as personal health data (analogous to therapy notes) — strongest available protection against corporate discovery.
- **Nuclear option**: Cryptographic deletion. If litigation is anticipated, executive can destroy KEK before preservation obligation attaches. Once destroyed, data is permanently unrecoverable — there is nothing to produce. (Note: destruction after a litigation hold is spoliation — timing matters.)

### Inferring emotions from biometric data
- EU AI Act Article 5(1)(f) prohibition is already in force. If Timed's voice or keystroke analysis pipeline produces ANY output that could be interpreted as emotion classification (stress, anxiety, frustration, happiness), the entire system becomes an illegal prohibited practice in the EU. The feature extraction must be architecturally constrained to cognitive states (focus, fragmentation, decision speed, energy level) — never emotional states. This is not a labeling choice; the underlying model must not be trained on or capable of emotion classification. Validate with adversarial testing before launch.

### Relying on policy instead of architecture
- "We promise not to look at your data" is worthless. The zero-knowledge architecture means Timed CANNOT look at user data — not "won't," but "can't." Every privacy guarantee must be enforced by cryptographic architecture, not by employee policy or terms of service. If a Timed engineer with full database access can read any user's cognitive model, the architecture has failed regardless of what the privacy policy says.
