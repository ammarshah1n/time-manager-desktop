# Extract 09 — Voice Analysis & Delivery

Source: `research/perplexity-outputs/v2/v2-09-voice-analysis.md`

---

## DECISIONS

### On-device audio processing pipeline
- **Architecture:** Capture (AVAudioEngine) -> Feature extraction (eGeMAPS + SoundAnalysis) -> Model inference (Core ML, quantised WavLM/HuBERT) -> State estimation (probability vectors). Only state probability vectors leave the device. Never audio. Never transcripts.
- AVAudioEngine handles mic/system audio capture with tap configuration and buffer management for real-time spectral analysis
- SoundAnalysis framework for pre-trained classifiers + custom Core ML model deployment
- Core ML for quantised WavLM Large and HuBERT inference — confirmed feasible within Apple Silicon thermal budget for continuous background processing
- Whisper-large-v3 runs on-device for dual-purpose: transcription + encoder embeddings as downstream features

### Best model/ensemble per cognitive state
- **Primary backbone:** WavLM Large fine-tuned on MSP-Podcast corpus (IS2025 Interspeech winning architecture) — best naturalistic speech emotion model available
- **Interpretable tracking layer:** eGeMAPS (Geneva Minimalistic Acoustic Parameter Set) — 88 features, standardised, enables longitudinal deviation tracking with explainable outputs
- **Transcription + embeddings:** Whisper-large-v3 — intermediate encoder representations carry emotion-relevant information beyond transcription
- **Supplementary (with caveats):** Hume AI prosody model — measures expressive behaviour, NOT internal state. Use for behavioural observation, never claim to know what the executive "feels"
- **Arousal detection:** Robustly validated (F0 under stress: SMD=0.55 effect size). Reliable signal.
- **Valence detection:** Hard problem. Best ensemble at IS2025 naturalistic challenge: CCC=0.734. Single-model well below 0.55. Treat valence estimates as low-confidence.
- **Executive speech caveat:** Practiced suppression + low variance of C-suite speech degrades off-the-shelf models. No published study validates accuracy on executive speech specifically. Domain adaptation required.

### Voice UX design — three delivery modes
1. **Routine briefings** (morning intelligence, day plan, relationship updates):
   - Voice is optimal. Moderate pace, structured delivery.
   - Optimal information rate: ~39 bits/sec (universal cross-language constant). Translates to ~150 wpm for English at normal information density.
   - Invite response at natural break points rather than continuous monologue.
2. **Uncomfortable insights** ("you've been avoiding this decision for 12 days"):
   - For moderately challenging content: voice works, but slower pace + hedging language + lower pitch.
   - For very negative/self-concept-threatening insights: **text outperforms voice**. Absence of social presence cues reduces defensive reactions. Switch to text delivery for the hardest truths.
   - Always ask permission before delivering self-concept-threatening observations.
   - Apply motivational interviewing principles (Miller & Rollnick): question framing, not declarative statements.
   - Kluger & DeNisi's Feedback Intervention Theory: direct feedback at the task level, not the self level.
3. **Real-time alerts** (cancelled meeting, urgent email, cognitive break suggestion):
   - Time-sensitive: brief, direct, falling intonation (certainty).
   - Important-but-not-urgent: lower priority interruption, can queue.
   - Cognitive break suggestions: frame as data-backed observation, not command.

### TTS system selection
- **Primary:** OpenAI TTS or ElevenLabs — both produce professional-grade output. ElevenLabs faster latency; OpenAI more consistent voice quality.
- **Fallback/offline:** Apple AVSpeechSynthesizer — on-device, zero latency, lower quality but functional for alerts.
- **Voice characteristics for executive trust:** lower pitch range, measured pace (~140-150 wpm), minimal vocal fry, no uptalk. Formal-conversational hybrid — not robotic, not casual.
- **Uncanny valley risk:** Current frontier TTS sits at the edge. Safe zone = consistent voice identity across sessions. Danger zone = attempting emotional expressiveness in TTS (sounds fake in high-stakes contexts).

### Privacy architecture
- Raw audio: never leaves device, never persisted beyond processing buffer
- Transcripts: on-device only (Whisper local or Apple Speech on-device mode), never sent to backend
- What leaves device: state probability vectors (e.g., `{fatigue: 0.72, stress: 0.45, confidence: 0.81}`) and aggregate acoustic feature statistics (mean F0, speech rate, disfluency count per session)
- Audio buffers: overwritten in circular buffer, configurable retention (default: 0 — discard immediately after feature extraction)
- macOS permissions required: Microphone access (user grant), Accessibility (for system audio capture if desired)
- Legal: one-party consent jurisdictions allow executive to record own meetings. Two-party consent jurisdictions require all-party notification. App must surface jurisdiction-aware consent flow.

---

## DATA STRUCTURES

### Acoustic feature extraction spec

| Feature | What It Indicates | Extraction Method | Validated Accuracy |
|---------|------------------|-------------------|-------------------|
| F0 (fundamental frequency) | Arousal/stress — higher F0 = higher activation | AVAudioEngine tap -> autocorrelation or YIN algorithm; eGeMAPS standardised extraction | SMD=0.55 effect size for stress (Scherer component process model) |
| F0 variance (std dev, range) | Emotional intensity, engagement. Low variance = suppressed/controlled speech | Rolling window stats on F0 contour | Reliable for arousal dimension; confounded by speaking style |
| F0 contour (rising vs falling terminal) | Confidence/certainty (falling = assertion) vs uncertainty (rising = question/hedge) | Prosodic contour analysis on utterance-final segments | Directly actionable for confidence detection |
| MFCCs (coefficients 1-13) | Speaker state classification. Lower coefficients (1-5) carry more emotional info; higher ones are speaker-identity features | Mel filterbank -> DCT; standard 25ms frames, 10ms hop | Foundation for most SER models; not interpretable alone |
| Speech rate (syllables/sec) | Cognitive load, emotional state. Acceleration = anxiety/excitement. Deceleration = fatigue/careful deliberation | Whisper word timestamps -> syllable estimation; or forced alignment | Moderate reliability; confounded by topic complexity |
| Speech rate variance | Engagement/disengagement. Monotone rate = disengagement; variable = engaged or agitated | Rolling window on speech rate | Requires personal baseline for accuracy |
| Jitter (F0 perturbation) | Vocal tension, stress, fatigue. Elevated jitter = muscle tension or fatigue | Cycle-to-cycle F0 variation; eGeMAPS jitter_local | Normal: <1.04%. Pathological: >1.04%. Stress elevates within normal range |
| Shimmer (amplitude perturbation) | Vocal fatigue, respiratory issues. Elevated shimmer = reduced vocal fold control | Cycle-to-cycle amplitude variation; eGeMAPS shimmer_local | Normal: <3.81%. Fatigue increases shimmer |
| Disfluency rate (um/uh per minute) | Cognitive overload, uncertainty, word-finding difficulty. Increased disfluencies = higher cognitive load | Whisper transcription -> disfluency token detection + pause analysis | Baseline-dependent. Population avg ~6 per 100 words; deviation from personal baseline is the signal |
| Pause structure (filled vs silent pauses) | Silent pauses before content words = word retrieval difficulty. Filled pauses (um/uh) = planning/uncertainty | VAD (voice activity detection) + Whisper timestamps | Requires longitudinal baseline |
| Spectral centroid | Voice brightness/energy. Lower spectral centroid = fatigue/sadness | FFT -> weighted frequency mean | Moderate reliability as supplementary feature |
| HNR (harmonics-to-noise ratio) | Voice quality/clarity. Lower HNR = breathy/strained voice (fatigue, stress) | eGeMAPS HNR extraction | Validated in clinical voice assessment |
| Formant frequencies (F1-F3) | Articulatory precision. Reduced formant space = fatigue, intoxication, or cognitive decline | LPC analysis or eGeMAPS formant extraction | Longitudinal deviation from personal baseline required |

### Model selection table per state

| Target State | Primary Model | Accuracy (Naturalistic) | On-Device Feasible | Backup/Ensemble |
|-------------|--------------|------------------------|-------------------|-----------------|
| **Cognitive fatigue** | WavLM Large + eGeMAPS (jitter, shimmer, speech rate decline, HNR drop) | No direct benchmark on exec speech; clinical fatigue detection ~75-80% sensitivity | Yes (quantised Core ML) | Longitudinal baseline deviation on eGeMAPS features |
| **Stress/arousal** | WavLM Large fine-tuned MSP-Podcast (arousal dimension) | CCC ~0.75-0.80 on MSP-Podcast test set; F0 effect size SMD=0.55 | Yes | eGeMAPS F0 mean + variance + jitter as interpretable fallback |
| **Confidence/uncertainty** | Prosodic contour analysis (F0 terminal patterns) + disfluency rate + speech rate | No single benchmark; prosodic certainty patterns well-validated linguistically | Yes (rule-based + lightweight model) | Whisper transcription -> linguistic hedging detection |
| **Engagement/disengagement** | Speech rate variance + F0 variance + response latency (in dialogues) | Research-validated features, no unified benchmark | Yes | Attention proxy from silence ratio + backchannel frequency |
| **Frustration** | WavLM Large (valence-arousal: high arousal + negative valence) + speech rate increase + F0 spike | Valence CCC ~0.55-0.73 (hard problem); arousal more reliable | Yes | eGeMAPS arousal features + disfluency spike detection |
| **Mental clarity** | Composite: low disfluency + stable speech rate + normal F0 variance + high HNR | No direct benchmark; inferred from absence of degradation signals | Yes (composite score from other detectors) | Longitudinal trend: clarity = personal baseline on all features |

### Voice UX rules per delivery type

| Dimension | Routine Briefing | Uncomfortable Insight | Real-Time Alert |
|-----------|-----------------|----------------------|-----------------|
| **Pace** | 140-150 wpm, natural rhythm | 110-120 wpm, deliberate slowing | 160+ wpm for urgent; 140 for important-not-urgent |
| **Pitch** | Mid-range, moderate variation | Lower pitch, narrow range (gravitas) | Slightly elevated to signal salience |
| **Terminal intonation** | Falling (statements of fact) | Rising on interpretive claims; falling on data-backed | Falling (directive clarity) |
| **Confidence calibration** | High confidence for data-backed; hedged for interpretive | Always hedged. "The data suggests..." not "You are..." | High confidence. No hedging on time-sensitive facts. |
| **Framing language** | Direct statements. "Your calendar shows..." | Questions first. "Have you noticed that..." / "Would you like to hear about..." | Declarative. "Your 2pm was just cancelled." |
| **Permission** | Not needed | Always ask before self-concept-threatening observations | Not needed for time-sensitive; ask for break suggestions |
| **Pauses** | Brief pauses between topics (500ms) | Longer pauses after key points (1-2s) — let it land | Minimal pauses. Deliver and stop. |
| **Delivery channel** | Voice (optimal) | Voice for moderate; TEXT for very negative | Voice for urgent; text queue for non-urgent |
| **Length** | 2-5 min for morning session; chunk into sections | Single insight at a time. Never stack negatives. | 1-2 sentences max |
| **Interaction** | Invite response at section breaks | Wait for acknowledgment before continuing | No response expected; executive acts or ignores |

---

## ALGORITHMS

### On-device feature extraction pipeline

```
Stage 1: CAPTURE
  AVAudioEngine.inputNode.installTap(bufferSize: 4096, format: 16kHz mono)
  -> Circular buffer (configurable: 30s default, overwrite-on-full)
  -> VAD (Voice Activity Detection) gate: only process voiced segments

Stage 2: FEATURE EXTRACTION (parallel paths)
  Path A — eGeMAPS (interpretable):
    Audio buffer -> vDSP (Accelerate framework) for FFT
    -> Extract 88 eGeMAPS features per frame (25ms window, 10ms hop):
       F0 (autocorrelation), jitter, shimmer, HNR, formants (F1-F3),
       MFCCs (1-13), spectral centroid, speech rate, loudness
    -> Aggregate per utterance: mean, std, percentiles (20th, 50th, 80th)
    -> Output: VoiceFeatureVector (88 dimensions + aggregates)

  Path B — Neural embeddings:
    Audio buffer -> Core ML WavLM Large (quantised INT8)
    -> Extract layer 12-24 representations (emotion-salient layers)
    -> Mean-pool across time dimension
    -> Output: EmbeddingVector (768 or 1024 dimensions)

  Path C — Transcription (on-demand):
    Audio buffer -> Whisper-large-v3 (Core ML) OR SFSpeechRecognizer (on-device)
    -> Word-level timestamps + confidence scores
    -> Disfluency token detection (um, uh, false starts)
    -> Output: TranscriptionResult (text + timestamps + disfluency markers)

Stage 3: MODEL INFERENCE
  VoiceFeatureVector + EmbeddingVector -> Core ML emotion classifier
    -> Dimensional output: [arousal, valence, dominance] as continuous values
    -> Categorical output: probability distribution over
       [fatigue, stress, confidence, engagement, frustration, clarity]
  TranscriptionResult -> Rule-based linguistic analysis
    -> Hedging frequency, question ratio, assertive language ratio

Stage 4: STATE ESTIMATION
  Merge dimensional + categorical + linguistic signals
  -> Compare against personal rolling baseline (see longitudinal algorithm)
  -> Compute deviation z-scores per feature
  -> Output: CognitiveStateEstimate {
       states: [StateProbability],     // e.g., fatigue: 0.72
       confidence: Float,              // meta-confidence in the estimate
       deviationFromBaseline: Float,   // how unusual this is for THIS person
       timestamp: Date
     }
  -> This is what leaves the device. Everything upstream is discarded.
```

### Emotion/state inference model pipeline

```
Input: 3-5 second audio segments (utterance-level)

1. WavLM Large encoder (quantised, Core ML):
   - Input: raw waveform (16kHz)
   - Output: 24-layer hidden representations
   - Use weighted sum of layers 12-24 (emotion-salient)
   - Downstream head: 2-layer MLP -> [arousal, valence, dominance]

2. eGeMAPS feature classifier (lightweight, Core ML):
   - Input: 88-dim feature vector per utterance
   - Model: gradient-boosted trees or small MLP
   - Output: [fatigue, stress, clarity] probabilities
   - Purpose: interpretable, explainable, longitudinally stable

3. Fusion layer:
   - Late fusion: weighted combination of WavLM and eGeMAPS outputs
   - Weights learned during domain adaptation phase
   - Conflict resolution: when models disagree, report lower confidence,
     bias toward eGeMAPS (more stable for longitudinal tracking)

4. Personal calibration layer:
   - Subtract personal rolling baseline (see below)
   - Apply personal scaling factors learned from first 30 days
   - Output: calibrated state probabilities relative to THIS individual
```

### Longitudinal voice baseline building and deviation detection

```
BASELINE CONSTRUCTION (first 30 days):

Day 1-7: Collect raw feature distributions
  - Store per-session: mean, std, min, max for all 88 eGeMAPS features
  - Store per-session: WavLM embedding centroid
  - Minimum: 10 sessions of 5+ minutes voiced speech

Day 8-30: Build stable baseline
  - Compute rolling mean + std for each feature
  - Identify personal range (5th-95th percentile) for each feature
  - Flag outlier sessions (>2 std from mean) — don't include in baseline
  - Compute personal covariance matrix (which features co-vary for this person)

ONGOING DEVIATION DETECTION (day 31+):

For each new session:
  1. Extract features (same pipeline)
  2. Compute z-score per feature against personal rolling baseline
  3. Composite deviation score: weighted sum of z-scores
     (weights: F0 variance=0.20, speech rate=0.15, jitter=0.15,
      disfluency=0.15, shimmer=0.10, HNR=0.10, spectral=0.15)
  4. If composite deviation > 1.5 std: flag as "notable state change"
  5. If deviation > 2.0 std: flag as "significant — consider alerting"

BASELINE DRIFT (adaptive):
  - Rolling window: 90 days (exponential decay, recent sessions weighted higher)
  - Prevents baseline from anchoring to early data as person changes
  - Sudden baseline shift detection: if 5+ consecutive sessions show
    same-direction deviation, trigger baseline recalibration review
```

### Personal voice model adaptation over months

```
Month 1: CALIBRATION PHASE
  - Collect baseline across contexts (meetings, dictation, calls)
  - Learn context-specific baselines (meeting voice != dictation voice)
  - Initial accuracy: population-level model + personal baseline offset
  - Key metric: establish per-feature personal ranges

Month 2-3: PATTERN DISCOVERY
  - Correlate voice features with known events (calendar, email patterns)
  - Discover personal stress signature: which features deviate FIRST for
    this specific person under stress (not population averages)
  - Learn time-of-day patterns (morning voice != afternoon voice)
  - Fine-tune WavLM downstream head on accumulated personal data
    (few-shot adaptation, ~100 labelled segments from reflection engine
     feedback loop: "was the system's state estimate accurate?")

Month 4-6: PREDICTIVE CAPABILITY
  - Voice features predict meeting outcomes (engagement level predicts
    follow-through on commitments)
  - Decision quality correlation: map voice state before decisions
    to decision outcomes tracked longitudinally
  - Cross-modal validation: voice stress + email pattern changes +
    calendar avoidance = converging evidence

Month 7-12: DEEP PERSONALISATION
  - Personal vocal biomarker library: unique-to-this-person indicators
  - Health baseline established: detect gradual changes in voice quality
    that may indicate health issues (vocal fatigue patterns, respiratory
    changes, neurological indicators per clinical voice biomarker research)
  - Predictive state modelling: forecast likely cognitive state for
    upcoming contexts based on historical voice patterns in similar situations
  - Conversation pattern evolution: track how executive's engagement
    with the AI voice changes over time (trust trajectory)
```

---

## APIS & FRAMEWORKS

### macOS APIs

| API | Purpose | Key Classes/Methods | Notes |
|-----|---------|-------------------|-------|
| **AVAudioEngine** | Audio capture and real-time processing | `inputNode.installTap()`, `AVAudioPCMBuffer`, `AVAudioFormat` | 16kHz mono for ML; 44.1kHz for quality. Tap buffer size 4096 frames. |
| **SFSpeechRecognizer** | On-device speech transcription | `SFSpeechRecognizer(locale:)`, `recognitionTask(with:)`, `requiresOnDeviceRecognition = true` | Set `requiresOnDeviceRecognition = true` to guarantee no cloud. Word-level timestamps via `SFTranscriptionSegment`. macOS 13+. |
| **SoundAnalysis** | Sound classification + custom model hosting | `SNAudioStreamAnalyzer`, `SNClassifySoundRequest`, custom `SNClassificationResult` | Can deploy custom Core ML sound classifiers. Built-in: 300+ sound categories. |
| **Core ML** | Model inference | `MLModel`, `MLMultiArray`, `MLFeatureProvider` | Quantised INT8 models for WavLM/HuBERT. Use `MLComputeUnits.all` to leverage Neural Engine. |
| **Accelerate (vDSP)** | FFT, spectral analysis | `vDSP.FFT`, `vDSP_meanSquare`, `vDSP_rmsqv` | Use for real-time eGeMAPS feature extraction. Hardware-accelerated on Apple Silicon. |
| **CoreAudio** | Low-level audio routing | `AudioDeviceID`, `AudioObjectPropertyAddress` | Needed for system audio capture (meeting audio from calls). Requires Accessibility permission. |

### ML Models

| Model | Purpose | Size (quantised) | On-Device | Licence |
|-------|---------|------------------|-----------|---------|
| **WavLM Large** | Primary emotion backbone | ~300MB (INT8 Core ML) | Yes — Neural Engine | MIT |
| **HuBERT Large** | Alternative/ensemble member | ~300MB (INT8 Core ML) | Yes — Neural Engine | MIT |
| **Whisper-large-v3** | Transcription + encoder embeddings | ~800MB (INT8 Core ML) | Yes — Neural Engine | MIT |
| **eGeMAPS** (openSMILE) | Interpretable acoustic features | N/A (algorithmic extraction) | Yes — CPU (Accelerate) | Open-source (audEERING) |
| **SpeechBrain emotion-wav2vec2-IEMOCAP** | Pre-trained emotion classifier | ~360MB | Yes (needs Core ML conversion) | Apache 2.0 |
| **Hume AI prosody** | Expressive behaviour measurement | Cloud API only | No — cloud only | Commercial API |

### TTS Systems

| System | Quality | Latency | On-Device | Cost | Best For |
|--------|---------|---------|-----------|------|----------|
| **OpenAI TTS (tts-1-hd)** | Highest naturalness | 500-800ms first byte | No (API) | $15/1M chars | Morning briefings, routine delivery |
| **ElevenLabs** | High, more voice options | 200-400ms first byte | No (API) | $0.30/1K chars (Scale) | Custom voice cloning if needed |
| **Apple AVSpeechSynthesizer** | Moderate (premium voices on macOS 14+) | <50ms (local) | Yes | Free | Offline fallback, real-time alerts |

### Privacy — macOS Permission Requirements

| Capability | Permission | Grant Mechanism | User Prompt Text |
|-----------|-----------|----------------|-----------------|
| Microphone access | `NSMicrophoneUsageDescription` | System dialog on first use | "Timed analyses your voice to understand cognitive patterns. Audio never leaves your device." |
| On-device speech recognition | `NSSpeechRecognitionUsageDescription` | System dialog on first use | "Timed transcribes speech on-device to detect communication patterns. Transcripts stay on your Mac." |
| System audio (meeting calls) | Screen Recording or Audio Recording permission (macOS 15+) | System Preferences > Privacy | Requires user to manually enable in System Settings. Cannot be granted programmatically. |
| Accessibility (optional) | Accessibility permission | System Preferences > Privacy | Only needed for system-wide audio capture. |

---

## NUMBERS

### Real-world emotion recognition accuracy

| Metric | Best Reported (Naturalistic Speech) | Source |
|--------|-------------------------------------|--------|
| Arousal CCC (MSP-Podcast IS2025 challenge) | 0.80 (winning ensemble) | IS2025 MSP-Podcast Challenge |
| Valence CCC (MSP-Podcast IS2025 challenge) | 0.734 (winning ensemble); single model <0.55 | IS2025 MSP-Podcast Challenge |
| Dominance CCC (MSP-Podcast IS2025 challenge) | ~0.72 (ensemble) | IS2025 MSP-Podcast Challenge |
| F0-stress effect size | SMD = 0.55 (meta-analysis) | Scherer component process model, PMC meta-analysis |
| 4-class categorical (naturalistic) | ~55-65% UAR (unweighted average recall) | IEMOCAP, MSP-Podcast benchmarks |
| Executive speech accuracy | **UNKNOWN — no published validation.** Expect degradation from population models due to practiced suppression and low expressivity. | Research gap identified in source report |

### On-device processing on Apple Silicon

| Operation | Latency (M1/M2/M3) | Battery Impact | Notes |
|-----------|-------------------|----------------|-------|
| eGeMAPS extraction (88 features, per utterance) | <5ms | Negligible | CPU-only via Accelerate/vDSP |
| WavLM Large inference (3s audio, INT8) | 50-100ms | ~2-3% additional drain over 8hr continuous | Neural Engine. Batch processing reduces cost. |
| Whisper-large-v3 transcription (30s audio) | 3-8s | Moderate per invocation; amortised if triggered selectively | Neural Engine. Don't run continuously — trigger on voiced segments. |
| Full pipeline (capture + features + inference) | <200ms per utterance | 3-5% additional drain for continuous monitoring | Feasible within thermal budget of background app |
| VAD gate savings | N/A | Reduces processing by ~60-70% | Only process voiced segments; skip silence |

### Minimum data for personal baseline

| Milestone | Data Required | What It Enables |
|-----------|--------------|----------------|
| Initial baseline | 10 sessions, 5+ min voiced each (~50 min total) | Personal feature ranges, basic deviation detection |
| Stable baseline | 30 sessions across 30 days | Reliable z-score computation, context-specific baselines |
| Stress signature | 3-5 observed stress episodes correlated with events | Personal stress feature hierarchy (which features deviate first for THIS person) |
| Full personal model | 90 days continuous observation | Fine-tuned downstream head, time-of-day patterns, context baselines |

### Longitudinal capability milestones

| Timeframe | Capability | Confidence |
|-----------|-----------|------------|
| **Month 1** | Personal feature ranges established. Population-level state estimates calibrated to personal baseline. Basic deviation detection ("you're more stressed than your normal"). | Low-moderate. Model is generic + personal offset. |
| **Month 3** | Personal stress signatures discovered. Context-specific baselines (meeting voice vs dictation). Time-of-day vocal patterns. Few-shot fine-tuning of WavLM downstream head on ~100 validated segments. | Moderate. Personal patterns emerge. |
| **Month 6** | Decision-state correlation mapped (voice state before decisions -> outcomes). Cross-modal convergence (voice + email + calendar = high-confidence state estimation). Predictive engagement modelling. | Moderate-high. Converging evidence from multiple signals. |
| **Month 12** | Predictive state modelling (forecast cognitive state for upcoming contexts). Personal vocal biomarker library. Subtle health change detection (gradual voice quality shifts). Conversation pattern evolution tracking. | High for established patterns. Experimental for health biomarkers. |

---

## ANTI-PATTERNS

### Acted emotion datasets inflate accuracy
- RAVDESS, SAVEE, EmoDB, and Berlin datasets use actors performing emotions in isolated utterances
- Models trained/evaluated on these report 85-95% accuracy — this is meaningless for real deployment
- Real-world naturalistic speech (MSP-Podcast, IEMOCAP): accuracy drops to 55-65% categorical UAR
- Valence detection drops most severely: acted valence is trivially distinguishable; naturalistic valence is near-chance for single models
- **Rule:** Never cite acted-dataset accuracy. Only MSP-Podcast, IEMOCAP, or real-world deployment studies.

### Executive speech degrades generic models
- C-suite executives practice vocal control: suppressed emotional expression, measured pace, deliberate prosody
- This low-variance speech pattern is adversarial to emotion recognition models trained on general population data
- Off-the-shelf models will systematically underestimate arousal and overestimate confidence in executive speech
- No published study validates SER models on executive/professional speech specifically
- **Rule:** Treat all population-level accuracy numbers as upper bounds for executive speech. Plan for domain adaptation from day 1. Use personal baseline deviation, not absolute model outputs.

### Uncanny valley in TTS for high-stakes contexts
- TTS that attempts emotional expressiveness (sad, excited, empathetic tones) sounds fake to executives who are expert at reading vocal cues
- Consistent, measured, neutral-professional voice is safer than attempting emotional modulation
- Voice identity must be consistent across all sessions — even subtle changes break trust
- **Rule:** Use a single, consistent, neutral-professional TTS voice. Never attempt emotional expressiveness in synthesis. Convey nuance through word choice and pacing, not vocal emotion.

### Two-party consent legal exposure
- 13 US states + many international jurisdictions require all-party consent for recording
- Professional settings add corporate policy layer: many companies prohibit recording without disclosure
- Ambient meeting capture without explicit consent from all participants is illegal in two-party consent jurisdictions even if the executive consents
- Audio analysis of others' voices without their knowledge raises additional ethical/legal issues
- **Rule:** Default to processing only the executive's own speech. For multi-party meetings, implement jurisdiction-aware consent flow. Consider acoustic source separation to isolate the executive's voice only. Never store or analyse other participants' audio without explicit consent framework.

### Claiming to know internal states from behavioural signals
- Hume AI and similar systems measure expressive behaviour (what someone sounds like), not internal experience (what someone feels)
- The inference gap between expression and experience is large, especially for executives who manage their expression professionally
- Framing inferences as "you feel stressed" triggers pushback from executives who value emotional control
- **Rule:** Always frame as behavioural observation: "your vocal patterns show elevated arousal" not "you're stressed." Let the executive interpret their own internal state. The system observes; the human concludes.

### Over-relying on single features
- F0 alone is confounded by speaking loudly, asking questions, or excitement (not just stress)
- Speech rate alone is confounded by topic complexity, audience, and cultural norms
- Disfluency alone varies by 3x between individuals at baseline
- **Rule:** Never infer state from a single acoustic feature. Always require convergence of 3+ features before surfacing a state estimate. Weight composite signals, not individual features.
