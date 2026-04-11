<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# I am building Timed — a macOS application designed as the most intelligent executive operating system ever built. Timed passively observes a single C-suite executive's digital behaviour — email metadata via Microsoft Graph API, calendar structure, keystroke dynamics, on-device voice characteristics, and application usage patterns. It never takes any action on the world — it never sends emails, modifies calendars, schedules meetings, or does anything autonomously. The human always decides and always executes. Timed's sole purpose is to build a compounding cognitive model of this one specific human that gets qualitatively smarter every month of observation. The tech stack is Swift/macOS native, Supabase backend (Postgres + Edge Functions), Microsoft Graph API for email and calendar data, and Claude API (Haiku for triage, Sonnet for analysis, Opus 4.6 for deep reasoning) for intelligence generation. There is no cost cap on this system — the only metric that matters is intelligence quality. Do not suggest cheaper alternatives, smaller models, or cost-saving optimisations at any point in your research.

Core research question: What is the optimal memory architecture for an AI system that builds a compounding, longitudinal model of one specific human over 12+ months of continuous passive observation?

I need you to conduct deep research across the following sub-questions and synthesise a comprehensive architecture specification:

1. State-of-the-art memory systems — MemGPT, MemOS, Stanford Generative Agents, and beyond

Analyse the specific implementation details of these systems, not just their high-level concepts. For MemGPT: how does it implement its virtual context management, main context vs archival storage, and the page-in/page-out mechanism? What are the actual data structures used for each memory tier? For MemOS: what is its memory bus architecture, how does it handle memory consolidation, and what APIs does it expose? For Stanford Generative Agents (Park et al., 2023): how does the reflection mechanism work — what triggers reflection, what data structures store reflections, and how are importance scores computed? Go beyond these three — find any other relevant memory architectures from 2023-2025 research that address longitudinal single-entity modelling. For each system, I need: a) the exact data structures used, b) the retrieval algorithms, c) the consolidation/reflection mechanisms, d) scalability characteristics over months of data, and e) critical limitations when applied to modelling a single human rather than simulating many agents.

2. Memory object granularity — what should the fundamental units of memory be?

The system will ingest raw observations (email arrived at 2:47am, meeting cancelled, typing speed dropped 30%, voice stress elevated). These need to be transformed into a hierarchy of increasingly abstract memory objects. What is the right granularity for each tier? Research how cognitive science models human memory hierarchies (episodic memory, semantic memory, procedural memory) and how these map to computational implementations. Specifically: What should a raw observation record contain? What does a first-order summary look like (daily pattern)? What does a second-order abstraction capture (weekly/monthly behavioural signature)? What does a stable personality/decision-style trait look like at the top of the hierarchy? How large should each object be in tokens? What metadata must accompany each tier for effective retrieval?

3. The nightly "sleep cycle" consolidation pass.

Timed runs a nightly batch process (analogous to human sleep consolidation) that processes the day's raw observations into higher-order memory. Research the optimal architecture for this pipeline. Specifically: What triggers consolidation (time-based, volume-based, significance-based)? What processing steps occur in what order? How does the system decide what to prune vs what to elevate to a higher tier? Which model tier should run which step (Haiku for summarisation, Sonnet for pattern detection, Opus for reflection and abstraction)? I need pseudocode for this pipeline with specific decision points, model calls, and data flow between stages.

4. Retrieval at query time — how to find what matters across 12 months of accumulated memory.

When the executive asks a question or when the system needs to generate a briefing, it must retrieve the most relevant memories from potentially hundreds of thousands of stored objects spanning a year. Research the optimal retrieval strategy. How should embedding similarity, recency decay, importance weighting, and temporal reasoning be combined? What retrieval architectures handle temporal queries well ("What changed about my decision-making after Q3?")? How do you prevent recent observations from overwhelming older but more significant patterns? Research specific algorithms: hierarchical retrieval (search abstractions first, then drill into supporting evidence), temporal windowing, importance-weighted cosine similarity, and hybrid retrieval combining vector search with structured metadata queries.

5. Embedding models and vector database schema for longitudinal single-user data.

What are the best embedding models as of 2025-2026 for encoding behavioural observations, patterns, and personality models? Compare text-embedding-3-large, Voyage AI models, Cohere embed v3, and any others relevant to this domain. What dimensionality is optimal for this use case? Design the optimal Supabase/pgvector schema for storing multi-tier memory objects with temporal indexing, importance scores, confidence levels, and cross-references between memory tiers. How should indexes be structured for combined vector similarity + temporal range + importance threshold queries?

6. Handling contradictory observations without catastrophic forgetting.

An executive's behaviour changes over time — sometimes permanently (they become more risk-averse after a bad quarter), sometimes temporarily (stress spike during a crisis). How should the memory system handle contradictions between old patterns and new observations? Research approaches from continual learning, Bayesian updating, and cognitive science. How do you maintain a historical record of who the person was while updating the model of who they are now?

Required output format:
Structure your response as an architecture specification document with:

- A decision table comparing MemGPT, MemOS, Stanford Generative Agents, and any other relevant systems across: data structures, retrieval mechanisms, consolidation approach, scalability, and suitability for single-user longitudinal modelling
- A complete memory tier schema with example objects at each level
- Pseudocode for the nightly consolidation pipeline with model assignments
- A retrieval algorithm specification with weighting formulas
- A pgvector/Supabase schema design with indexes
- Ranked design decisions: what to adopt from each system and why, what to reject and why

Do not provide surface-level overviews. I need implementation-depth detail for every component.

Here's the full architecture specification for Timed. It's one of the most complex single-user memory problems you can design for, and the report covers every sub-question at implementation depth. Here's the structure at a glance:

**What the report contains:**

1. **Decision Table** — All 7 systems (MemGPT, Stanford Generative Agents, MemOS, Zep, MAGMA, O-Mem, and the ICLR 2026 neuroscience architecture) compared across data structures, retrieval, consolidation, scalability, and single-user suitability. Plus explicit adopt/reject verdicts for each.
2. **5-Tier Memory Schema** — Full JSON examples at every level: Tier 0 (raw observation, ~50 tokens), Tier 1 (daily summary, 200-400 tokens), Tier 2 (behavioural signature, 500-1000 tokens), Tier 3 (personality trait with valence vector and precision scalar), and the active context buffer.
3. **Nightly Consolidation Pipeline** — Full pseudocode with 6 phases: importance scoring (Haiku), conflict detection (Haiku), daily summary generation (Haiku), weekly pattern detection (Sonnet), monthly trait reflection (Opus), pruning. Includes multi-trigger logic (time + volume + significance).
4. **Retrieval Algorithm** — Intent classification table (WHAT/WHEN/WHY/PATTERN/CHANGE), hierarchical retrieval pseudocode (traits first, then signatures, then drill down), and a 5-dimension weighted scoring formula with intent-type-adjusted weight tables.
5. **Full pgvector/Supabase Schema** — Production-ready SQL for all 5 tables with HNSW indexes tuned per tier (m=16 for tier 0, m=48 for tier 3), partial indexes, GIN array indexes, composite indexes, and a combined vector+temporal+importance query function.
6. **Contradiction Architecture** — The three cases (temporary deviation, permanent shift, novel emergence), the bi-temporal model, and the precision-scalar cathartic update formula.

**The core architectural synthesis**: Zep's bi-temporal fact model + Stanford's importance scoring + MAGMA's intent-aware multi-graph traversal + the ICLR 2026 neuroscience precision scalar for trait stability + SleepGate's conflict tagger in the consolidation pipeline + voyage-context-3/voyage-3-large for embeddings. No single existing system was adequate — this is a purpose-built composition.
<span style="display:none">[^1_1][^1_10][^1_100][^1_101][^1_102][^1_103][^1_104][^1_105][^1_106][^1_107][^1_108][^1_109][^1_11][^1_110][^1_111][^1_112][^1_12][^1_13][^1_14][^1_15][^1_16][^1_17][^1_18][^1_19][^1_2][^1_20][^1_21][^1_22][^1_23][^1_24][^1_25][^1_26][^1_27][^1_28][^1_29][^1_3][^1_30][^1_31][^1_32][^1_33][^1_34][^1_35][^1_36][^1_37][^1_38][^1_39][^1_4][^1_40][^1_41][^1_42][^1_43][^1_44][^1_45][^1_46][^1_47][^1_48][^1_49][^1_5][^1_50][^1_51][^1_52][^1_53][^1_54][^1_55][^1_56][^1_57][^1_58][^1_59][^1_6][^1_60][^1_61][^1_62][^1_63][^1_64][^1_65][^1_66][^1_67][^1_68][^1_69][^1_7][^1_70][^1_71][^1_72][^1_73][^1_74][^1_75][^1_76][^1_77][^1_78][^1_79][^1_8][^1_80][^1_81][^1_82][^1_83][^1_84][^1_85][^1_86][^1_87][^1_88][^1_89][^1_9][^1_90][^1_91][^1_92][^1_93][^1_94][^1_95][^1_96][^1_97][^1_98][^1_99]</span>

<div align="center">⁂</div>

[^1_1]: https://www.leoniemonigatti.com/blog/memgpt.html

[^1_2]: https://www.scribd.com/document/670367769/Paper-AI-Stanford-Experiment-Agents

[^1_3]: https://arxiv.org/abs/2603.14517

[^1_4]: https://arxiv.org/html/2601.03236v1

[^1_5]: https://huggingface.co/papers/2511.13593

[^1_6]: https://arxiv.org/abs/2501.13956

[^1_7]: https://arxiv.org/abs/2603.29023

[^1_8]: https://3dvar.com/Park2023Generative.pdf

[^1_9]: https://llmmultiagents.com/en/blogs/memos-revolutionizing-llm-memory-management-as-a-first-class-operating-system

[^1_10]: https://arxiv.org/html/2511.13593v1

[^1_11]: https://serokell.io/blog/design-patterns-for-long-term-memory-in-llm-powered-architectures

[^1_12]: https://www.themoonlight.io/en/review/magma-a-multi-graph-based-agentic-memory-architecture-for-ai-agents

[^1_13]: https://www.reddit.com/r/MachineLearning/comments/12hluz1/r_generative_agents_interactive_simulacra_of/

[^1_14]: https://www.linkedin.com/posts/omarsar_new-paper-an-operating-system-for-memory-augmented-activity-7334249509062955008-BJu9

[^1_15]: https://www.linkedin.com/posts/akshay-pachaar_build-human-like-memory-for-your-ai-agents-activity-7371526458596450304-qj9m

[^1_16]: https://arxiv.org/pdf/2601.03236.pdf

[^1_17]: https://www.youtube.com/watch?v=TPGlkaHXu0A

[^1_18]: https://arxiv.org/abs/2511.13593

[^1_19]: https://arxiv.org/html/2603.14517v1

[^1_20]: https://arxiv.org/html/2507.22925v1

[^1_21]: https://arxiv.org/abs/2310.08560

[^1_22]: https://buildwithaws.substack.com/p/agent-memory-strategies-building

[^1_23]: https://cloud.google.com/blog/products/databases/faster-similarity-search-performance-with-pgvector-indexes

[^1_24]: https://www.crunchydata.com/blog/hnsw-indexes-with-postgres-and-pgvector

[^1_25]: https://supabase.com/docs/guides/database/extensions/pgvector

[^1_26]: https://sparkco.ai/blog/mastering-supabase-vector-storage-a-2025-deep-dive

[^1_27]: https://developers.openai.com/cookbook/examples/partners/temporal_agents_with_knowledge_graphs/temporal_agents/

[^1_28]: https://blog.voyageai.com/2025/07/23/voyage-context-3/

[^1_29]: https://blog.voyageai.com/2025/01/07/voyage-3-large/

[^1_30]: https://agentset.ai/embeddings/compare/voyage-3-large-vs-cohere-embed-v3

[^1_31]: https://dataa.dev/2025/01/17/embedding-models-compared-openai-vs-cohere-vs-voyage-vs-open-source/

[^1_32]: https://agentset.ai/embeddings/compare/openai-text-embedding-3-large-vs-voyage-3-large

[^1_33]: https://pub.towardsai.net/inside-memgpt-an-llm-framework-for-autonomous-agents-inspired-by-operating-systems-architectures-674b7bcca6a5

[^1_34]: https://zilliz.com/blog/introduction-to-memgpt-and-milvus-integration

[^1_35]: https://informationmatters.org/2025/10/memgpt-engineering-semantic-memory-through-adaptive-retention-and-context-summarization/

[^1_36]: https://www.youtube.com/watch?v=nKCJ3BMUy1s

[^1_37]: https://www.linkedin.com/posts/charles-packer_introducing-memgpt-a-method-for-extending-activity-7119710815817011200-3CFP

[^1_38]: https://arxiv.org/abs/2505.22101

[^1_39]: https://www.youtube.com/watch?v=4aOLxPdx1Dg

[^1_40]: https://dev.to/cursedknowledge/memos-how-an-operating-system-for-memory-will-make-ai-smarter-and-more-adaptive-2a54

[^1_41]: https://hai.stanford.edu/policy/simulating-human-behavior-with-ai-agents

[^1_42]: https://arxiv.org/pdf/2304.03442.pdf

[^1_43]: https://dl.acm.org/doi/fullHtml/10.1145/3586183.3606763

[^1_44]: https://www.academia.edu/145567863/Cross_Session_Narrative_Memory_CSNM_A_Minimal_Longitudinal_Architecture_for_Stable_Human_AI_Interaction

[^1_45]: https://www.nature.com/articles/s41598-025-31685-9

[^1_46]: https://radical.vc/the-promise-and-perils-of-continual-learning/

[^1_47]: https://hai.stanford.edu/assets/files/hai-policy-brief-simulating-human-behavior-with-ai-agents.pdf

[^1_48]: https://www.nature.com/articles/s41562-023-01799-z

[^1_49]: https://www.semanticscholar.org/paper/Continual-Learning-and-Catastrophic-Forgetting-Ven-Soures/7556332c94d177155c7255e36ab8ea78632adce7

[^1_50]: https://academic.oup.com/brain/article/147/11/3918/7721059

[^1_51]: https://www.linkedin.com/posts/atharva-jamdar_vector-databases-for-llms-pinecone-weaviate-activity-7433020394019770368-XNgl

[^1_52]: https://www.pentestly.io/blog/supabase-security-best-practices-2025-guide

[^1_53]: https://www.instaclustr.com/education/vector-database/pgvector-key-features-tutorial-and-pros-and-cons-2026-guide/

[^1_54]: https://supabase.com/docs/guides/storage/vector/querying-vectors

[^1_55]: https://arxiv.org/abs/2507.22925

[^1_56]: https://github.com/paradoxe35/awesome-vector-databases

[^1_57]: https://arxiv.org/pdf/2507.22925.pdf

[^1_58]: https://mintlify.com/supabase/supabase/ai/pgvector

[^1_59]: https://icml.cc/virtual/2025/poster/40142

[^1_60]: https://www.sciencedirect.com/science/article/pii/S2589004225011058

[^1_61]: https://arxiv.org/html/2603.29023v1

[^1_62]: https://www.auai.org/uai2024/accepted_papers

[^1_63]: https://pmc.ncbi.nlm.nih.gov/articles/PMC12813117/

[^1_64]: https://pmc.ncbi.nlm.nih.gov/articles/PMC9347313/

[^1_65]: https://onlinelibrary.wiley.com/doi/abs/10.1111/desc.13464

[^1_66]: https://www.grin.com/document/377210

[^1_67]: https://github.com/IAAR-Shanghai/Awesome-AI-Memory

[^1_68]: https://www.reddit.com/r/LocalLLaMA/comments/1p4bkl6/experiment_multiagent_llm_sleep_cycle_with/

[^1_69]: https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2022.899371/full

[^1_70]: https://dl.acm.org/doi/abs/10.1007/s00158-025-04183-9

[^1_71]: https://www.mountsinai.org/about/newsroom/2025/new-ai-model-analyzes-full-night-of-sleep-with-high-accuracy-in-largest-study-of-its-kind

[^1_72]: https://docs.letta.com/guides/ade/archival-memory/

[^1_73]: https://forum.letta.com/t/agent-memory-letta-vs-mem0-vs-zep-vs-cognee/88

[^1_74]: https://zenn.dev/akky_tech/articles/25_12_ai_learned_with_letta?locale=en

[^1_75]: https://arxiv.org/html/2603.04740v1

[^1_76]: https://www.youtube.com/watch?v=imDi__2IllY

[^1_77]: https://github.com/letta-ai/letta/issues/381

[^1_78]: https://www.reddit.com/r/ArtificialInteligence/comments/1q7f5z7/magma_a_multigraph_based_agentic_memory/

[^1_79]: https://blog.stackademic.com/letta-platform-for-stateful-llm-agents-a83b58a1c926

[^1_80]: https://huggingface.co/papers/2601.03236

[^1_81]: https://www.letta.com/blog/context-bench-skills

[^1_82]: https://arxiv.org/abs/2601.03236

[^1_83]: https://github.com/getzep/graphiti

[^1_84]: https://www.reddit.com/r/AIMemory/comments/1qbmffy/i_tried_to_make_llm_agents_truly_understand_me/

[^1_85]: https://docs.mem0.ai/cookbooks/essentials/choosing-memory-architecture-vector-vs-graph

[^1_86]: https://www.reddit.com/r/PostgreSQL/comments/1afs99v/how_to_optimize_vector_search_performance_with/

[^1_87]: https://www.getzep.com

[^1_88]: https://mem0.ai/blog/agentic-rag-vs-traditional-rag-guide

[^1_89]: https://ai.plainenglish.io/graphrag-how-temporal-knowledge-graphs-solve-agent-memory-problems-7d5024f2b327

[^1_90]: https://www.generational.pub/p/memory-in-ai-agents

[^1_91]: https://www.scribd.com/document/1002078642/MAGMA-Memory-Architecture-Feasibility-Analysis

[^1_92]: https://www.linkedin.com/posts/thenextgentechinsider_tech-news-activity-7415419093232607233-IwZ4

[^1_93]: https://www.linkedin.com/posts/xin-luna-dong-6820953b_emnlp2025-mmrag-iclr2026-activity-7442754922078547968-iP2E

[^1_94]: https://arxiv.org/html/2512.23343v1

[^1_95]: https://x.com/okuwaki_m/status/2009065533120106585

[^1_96]: https://arxiv.org/list/cs.AI/new

[^1_97]: https://openlayer.com/blog/post/what-are-embedding-models-complete-guide

[^1_98]: https://snowan.gitbook.io/study-notes/ai-manga-learnings/magma-agentic-memory/source-link

[^1_99]: https://arxiv.org/abs/2512.20245

[^1_100]: https://www.academia.edu/145090285/Cross_Session_Narrative_Memory_A_Cognitive_Architecture_for_Longitudinal_Human_AI_Integration

[^1_101]: https://www.academia.edu/161286766/Review_of_Cross_Session_Narrative_Memory_CSNM_A_Minimal_Longitudinal_Architecture_for_Stable_Human_AI_Interaction_by_Mario_Mart%C3%ADn_Cuniglio_2025

[^1_102]: https://www.academia.edu/145695854/Energy_Aware_Longitudinal_AI_Measuring_Computational_and_Energy_Efficiency_of_Cross_Session_Narrative_Memory_CSNM_with_Ethical_Invariants

[^1_103]: https://www.mcgill.ca/study/2024-2025/files/study.2024-2025/courselist2425.pdf

[^1_104]: https://www.academia.edu/145397684/A_Narrative_Architecture_for_Hybrid_Human_AI_Cognition

[^1_105]: https://pmc.ncbi.nlm.nih.gov/articles/PMC11449156/

[^1_106]: https://www.academia.edu/Documents/in/Cognitive_Architectures

[^1_107]: https://www.linkedin.com/posts/leadgenmanthan_what-most-think-of-memory-of-ai-agents-is-activity-7302560556161331200-z8bW

[^1_108]: https://www.academia.edu/165305608/Memory_Control_Interaction_and_the_Over_Intervention_Effect_in_Memory_Augmented_Language_Models_A_review_of_Cuniglio_M_M_and_Al_Zawahreh_M_2026

[^1_109]: https://aws.amazon.com/blogs/machine-learning/build-agents-to-learn-from-experiences-using-amazon-bedrock-agentcore-episodic-memory/

[^1_110]: https://arxiv.org/pdf/2603.14517.pdf

[^1_111]: https://www.academia.edu/116322105/A_Novel_Model_of_Narrative_Memory_for_Conscious_Agents

[^1_112]: https://github.com/IAAR-Shanghai/Awesome-AI-Memory/blob/main/README.md

