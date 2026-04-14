> **INSTRUCTIONS FOR COMET ASSISTANT**
> This file contains 3 Perplexity Deep Research prompts for the Timed Intelligence Maximisation project.
> This file is located at: `github.com/ammarshah1n/time-manager-desktop/blob/ui/apple-v1-restore/research/perplexity-outputs/v3/timed-intelligence-maximisation-prompts-01.md`
> The second prompt file is at: `github.com/ammarshah1n/time-manager-desktop/blob/ui/apple-v1-restore/research/perplexity-outputs/v3/timed-intelligence-maximisation-prompts-02.md`
> For each prompt below:
> 1. Navigate to perplexity.ai in a new browser tab
> 2. Select **Deep Research** mode (not standard search)
> 3. Copy the full prompt exactly as written — do not truncate or summarise it
> 4. Paste into the search bar and submit
> 5. Wait for the full report to complete before opening the next tab
> Run each prompt in a completely separate tab. Do not combine prompts.
> Save each completed report before closing the tab.

---

## Prompt 1: Executive Cognitive Bias Detection from Passive Digital Signals

**CONTEXT:**
This research supports a macOS application that builds a compounding cognitive model of a specific C-suite executive from passive digital behavioural observation (email metadata, calendar patterns, response latency, communication tone shifts). The system uses Claude Opus 4.6 with extended thinking (up to 128K tokens) to run nightly analysis. We are implementing a bias detection engine that identifies 9 cognitive biases — overconfidence, anchoring, sunk cost escalation, availability heuristic, confirmation bias, status quo bias, planning fallacy, escalation of commitment, and recency bias — from observable digital behaviour without self-report instruments. For project context, reference the files in github.com/ammarshah1n/Timed-Brain — especially `06 - Context/` for architectural decisions and `03 - Research/` for prior Perplexity reports. Ground your analysis against the existing tiered memory architecture documented there.

**CORE QUESTION:**
**How can each of the 9 specified cognitive biases be reliably detected from passive digital behavioural signals (email, calendar, task management) without self-report instruments, and what are the minimum evidence thresholds and false positive rates achievable?**

**SUB-QUESTIONS:**

1. For each of the 9 biases (overconfidence, anchoring, sunk cost escalation, availability heuristic, confirmation bias, status quo bias, planning fallacy, escalation of commitment, recency bias), what are the specific observable digital behaviours that serve as valid proxies? Cite validated research linking each proxy to the bias construct.

2. What NLP features and prompt engineering patterns enable frontier LLMs (Claude Opus, GPT-4) to detect cognitive biases from email text and metadata? Include specific prompt structures that have been evaluated in peer-reviewed studies or documented in technical reports.

3. What are the minimum sample sizes and observation windows required to distinguish genuine bias from noise in each case? For example, how many sequential decisions must exhibit escalation of commitment before the signal exceeds a 0.7 confidence threshold?

4. What false positive rates are documented in the literature for automated cognitive bias detection, and what are the recommended strategies for minimising false positives in high-stakes executive contexts where a wrong flag damages trust?

5. How should temporal evidence chains be constructed — what data structure captures the sequence of decisions, meetings, and communications that constitute evidence for a bias instance? Include specific schema recommendations.

6. What existing tools or systems (academic prototypes, commercial products like Humu, BetterUp, CoachHub) implement automated bias detection, and what accuracy metrics have they published?

7. How should detected biases be surfaced to a C-suite executive without triggering defensiveness? What framing, language, and timing recommendations exist in the executive coaching literature?

**OUTPUT FORMAT:**
- A decision matrix (bias × proxy signal × minimum evidence threshold × estimated false positive rate × confidence achievable)
- Pseudocode for the nightly bias detection pipeline showing input signals, evidence accumulation, threshold checks, and output format
- A table of recommended prompt structures for each bias type, with specific example prompts
- Schema recommendation for bias evidence storage (fields, types, relationships)
- Prefer primary sources: peer-reviewed research (arXiv, ACM, IEEE, PubMed), official technical documentation, and authoritative engineering references over secondary summaries. For each major claim, cite the original source.
- Do not speculate. Where evidence is absent, state the gap explicitly.
- The output will be used directly by Claude Opus 4.6 (1M context window) as a technical build brief. Write with that reader in mind — maximum technical precision, no hand-holding, no consumer-level explanation.

Produce a comprehensive, deeply cited research report — go deep on every sub-question — this output is the primary technical foundation for building a production system.

---

## Prompt 2: Optimal Extended Thinking Budget vs Output Quality for Frontier LLMs

**CONTEXT:**
We are building a cognitive intelligence system that makes multiple daily calls to Claude Opus 4.6 with extended thinking enabled. Current thinking budgets range from 8K to 65K tokens across different pipeline stages (importance scoring, daily summarisation, contradiction detection, ACB generation, self-improvement). Anthropic supports up to 128K thinking tokens. Each pipeline stage has different cognitive demands — some require deep synthesis across weeks of data, others require precise classification. We need to determine the optimal thinking budget for each task type to maximise intelligence output per dollar. At $800/week consumer price, we can afford $100-150/week in AI costs. For project context, reference github.com/ammarshah1n/Timed-Brain — especially the nightly pipeline architecture in `06 - Context/`.

**CORE QUESTION:**
**What is the empirical relationship between extended thinking token budget and output quality for frontier LLMs across different cognitive task types (synthesis, classification, anomaly detection, generation), and where do diminishing returns set in for each?**

**SUB-QUESTIONS:**

1. What published benchmarks, technical reports, or blog posts from Anthropic, OpenAI, or independent researchers document the relationship between thinking/reasoning budget and output quality? Include specific metrics (accuracy, coherence, factual correctness, reasoning depth) across task types.

2. For synthesis tasks (combining 7 days of behavioural data into a coherent narrative with anomaly detection), what thinking budget produces the quality ceiling? Is there empirical evidence that 128K thinking outperforms 64K for long-context synthesis?

3. For classification tasks (scoring observation importance 1-10), does extended thinking improve accuracy over zero-shot classification? What is the minimum thinking budget where classification quality plateaus?

4. For adversarial review tasks (critiquing an LLM's own output for over-claimed patterns and missing context), what thinking budget enables effective self-critique vs rubber-stamping?

5. What is the cost-quality frontier for Claude Opus 4.6 specifically? At what thinking budget does the next doubling produce <5% quality improvement? Include pricing calculations at current Anthropic rates ($15/M input, $75/M output for Opus).

6. Are there documented strategies for dynamic thinking budget allocation — spending more tokens on harder inputs and fewer on routine ones? How is input difficulty assessed?

**OUTPUT FORMAT:**
- A table: task type × recommended thinking budget × expected quality level × cost per call × evidence source
- Cost-quality curves (described in structured text) for synthesis, classification, and adversarial review tasks
- A decision framework for dynamically allocating thinking budgets based on input complexity signals
- Specific recommendations for each of our pipeline stages with rationale
- Prefer primary sources: peer-reviewed research (arXiv, ACM, IEEE), Anthropic technical documentation, and authoritative engineering references over secondary summaries. For each major claim, cite the original source.
- Do not speculate. Where evidence is absent, state the gap explicitly.
- The output will be used directly by Claude Opus 4.6 (1M context window) as a technical build brief. Write with that reader in mind — maximum technical precision, no hand-holding, no consumer-level explanation.
- Include specific API names, method signatures, and version numbers where available.

Produce a comprehensive, deeply cited research report — go deep on every sub-question — this output is the primary technical foundation for building a production system.

---

## Prompt 3: Relationship Intelligence Card Design for C-Suite Executives

**CONTEXT:**
This research supports a macOS executive OS that passively monitors email and calendar signals to build relationship health profiles for a C-suite executive's key contacts (15-20 people). When relationship health drops (reply latency increases, meeting cancellations, tone shifts), the system generates a relationship intelligence card using Claude Opus 4.6. The card must communicate nuanced interpersonal intelligence in a format that a time-poor CEO will actually read and act on. The system never acts autonomously — it observes, reflects, and recommends. For project context, reference github.com/ammarshah1n/Timed-Brain — especially `03 - Research/` for prior Perplexity reports on relationship health scoring and `06 - Context/` for the RelationshipHealthService architecture.

**CORE QUESTION:**
**What information architecture, visual format, and content structure for relationship intelligence cards maximises executive engagement and actionability for C-suite users managing 15-20 key professional relationships?**

**SUB-QUESTIONS:**

1. What do existing executive relationship intelligence tools (Gong, Clari, People.ai, Affinity CRM, LinkedIn Sales Navigator) show in their relationship health dashboards? What specific fields, metrics, and visualisations do they use? Include screenshots or detailed descriptions of their UI patterns.

2. What does the executive coaching literature say about how C-suite leaders prefer to receive interpersonal intelligence? What formats (narrative, metrics, visual, comparison) produce the highest engagement in time-constrained contexts?

3. What specific metrics should a relationship intelligence card surface? Evaluate: response latency trend, email frequency trend, meeting attendance rate, tone formality index, initiated-vs-received ratio, topic overlap/divergence, availability responsiveness. Which of these have validated predictive power for relationship deterioration?

4. How should the system handle uncertainty and multiple interpretations? When reply latency increases, it could mean disengagement, overwork, travel, or strategic distancing. What framing avoids false confidence while still being useful?

5. What are the privacy and trust considerations for surfacing relationship intelligence to executives? What ethical guardrails should the card include? What does the literature say about consent and transparency in workplace relationship monitoring?

6. What information density is optimal for a C-suite executive? How many data points per card before cognitive overload? What is the ideal reading time (15 seconds? 30 seconds? 60 seconds?) for maximum information retention?

7. What native macOS UI patterns (using SwiftUI) are appropriate for relationship intelligence cards? Reference Apple Human Interface Guidelines for card-based information display, progressive disclosure, and contextual detail.

**OUTPUT FORMAT:**
- A complete card schema (field name, data type, source signal, display format) with 12-15 fields
- Three alternative card layout wireframes described in structured text (compact/medium/detailed)
- A decision matrix: metric × predictive power × privacy risk × executive preference ranking
- Recommended progressive disclosure hierarchy (what shows at glance vs on expand vs on drill-down)
- Prefer primary sources: peer-reviewed research (arXiv, ACM, IEEE, PubMed), official technical documentation, and authoritative engineering references over secondary summaries. For each major claim, cite the original source.
- Do not speculate. Where evidence is absent, state the gap explicitly.
- The output will be used directly by Claude Opus 4.6 (1M context window) as a technical build brief. Write with that reader in mind — maximum technical precision, no hand-holding, no consumer-level explanation.

Produce a comprehensive, deeply cited research report — go deep on every sub-question — this output is the primary technical foundation for building a production system.
