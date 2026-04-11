<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# I am building an application called Timed — a macOS application for C-suite executives that passively observes email metadata, calendar structure, keystroke dynamics, on-device voice, and application usage. Timed never takes any action on the world — it never sends emails, modifies calendars, or does anything. The human always decides and executes. The system builds a compounding cognitive model that gets qualitatively smarter every month. It is built in Swift/macOS with a Supabase backend, Microsoft Graph API for email and calendar, and Claude API (Haiku/Sonnet/Opus 4.6) for intelligence processing. Critical constraint: there is no cost cap — the only metric is intelligence quality. Do not suggest cheaper alternatives or smaller models. The goal is to build the most intelligent executive operating system ever created. One of Timed's most powerful capabilities will be understanding WHEN the executive thinks best, WHEN their energy depletes, and WHEN to surface intelligence versus hold it. This requires modelling the individual executive's cognitive performance curve from passive digital behaviour — not self-reports, not questionnaires, not wearable data — purely from the digital signals Timed already observes. I need comprehensive research across chronobiology, ultradian rhythms, energy depletion science, and cognitive scheduling to build this capability. Research the following in depth:

1. Current state of chronotype science and individual cognitive performance variation. What does the peer-reviewed literature say about chronotypes beyond the simple morning-lark/night-owl binary? I need the full spectrum — Roenneberg's Munich Chronotype Questionnaire findings, Adan \& Almirall's typology, intermediate chronotypes, and critically the magnitude of cognitive performance variation across the day for each type. How much does an individual's peak versus trough performance actually differ? What specific cognitive functions vary most — executive function, creative thinking, analytical reasoning, social judgment, risk assessment? What does Wieth \& Zacks (2011) show about insight problem solving at non-optimal times? How stable is chronotype across months and years — does it shift with season, age, workload, travel? For a system observing an executive over 12 months, how frequently should the chronotype model be re-estimated? What are the most reliable INFERRED markers of chronotype from digital behaviour — email send times, first-activity-of-day timing, response latency patterns across the day, error rate variation, message length variation, creative output timing? Specifically: which of these signals have been validated in research as chronotype proxies, and which are reasonable but unvalidated inferences?
2. Ultradian rhythms and intra-day cognitive cycling. Beyond the circadian cycle, research the 90-120 minute Basic Rest-Activity Cycle (BRAC) first described by Kleitman. What is the current scientific consensus on ultradian rhythms in waking cognitive performance? How strong is the evidence? Peretz Lavie's ultrashort sleep-wake cycle research — what does it show about attentional peaks and troughs within a single day? Can ultradian peaks and troughs be detected from digital behaviour — specifically from patterns in keystroke velocity, application switching frequency, email response clustering, or pauses in activity? What does the research say about the cost of working through an ultradian trough versus taking a break? How would you build a computational model that estimates where in the ultradian cycle an executive currently sits, using only passively observed digital signals? What features would such a model use, and what temporal resolution is realistic?
3. Energy depletion science — causes, signatures, and detection. Research the mechanisms by which executive cognitive energy depletes over a workday. Baumeister's ego depletion model — what survived the replication crisis and what didn't? The resource model versus the motivation-shift model of mental fatigue. What does the literature say about specific depletion drivers for executives — meeting load (consecutive meetings without breaks), decision density (number of substantive decisions per hour), context-switching frequency (jumping between unrelated domains), emotional labour (difficult conversations, conflict management), and information overload? For each driver, what are the detectable digital signatures? A meeting-heavy morning shows up in calendar data — but what does the POST-meeting behavioural change look like in email patterns, response quality, and activity tempo? Can you detect the difference between productive fatigue (deep work that depleted energy on something worthwhile) and waste fatigue (energy drained by low-value activities)? Research on decision quality degradation as a function of prior decision load — Danziger et al.'s parole board study and subsequent critiques. What does a computational energy budget model look like — inputs, decay functions, recovery rates?
4. Cognitive scheduling research for executives. What does the empirical research say about how time allocation patterns correlate with decision quality and executive effectiveness? Porter and Nohria's Harvard study tracking CEO time allocation — what did it reveal about the relationship between schedule structure and effectiveness? Graham, Harvey, and Puri's research on CEO decision-making patterns. Paul Graham's maker-schedule versus manager-schedule framework — is there empirical support for this beyond anecdote? Research on meeting-free blocks, focus time protection, and their impact on executive output quality. What does the chronobiology literature say about matching cognitive task demands to circadian peaks — analytical work during peak alertness, creative work during off-peak, routine work during troughs? Is there research specifically on C-suite executives (not students, not knowledge workers generally) and optimal daily structure? Research on the 'first decision of the day' effect — does the first substantive decision anchor cognitive patterns for the rest of the day? Batching theory — which types of executive work benefit from batching (email, approvals, one-on-ones) and which suffer from it (strategic thinking, creative problem-solving)?
5. Inferring and refining an individual's chronotype model from months of passive observation. This is the implementation question. Given that Timed observes: email send times (with second-level precision), calendar events, keystroke dynamics (typing speed, error rate, pause patterns), application switching patterns, and voice characteristics (when available) — what is the optimal approach to building a personalised chronotype and energy model? What signals serve as the most reliable features? How much data is needed before the model becomes useful — days, weeks, months? What machine learning or statistical approach is most appropriate — Bayesian updating of chronotype priors, hidden Markov models for state estimation, simple regression on performance proxies versus time of day, or something else? How should the model handle confounders — jet lag, illness, weekends versus weekdays, seasonal shifts, daylight saving transitions? How should it detect and adapt to genuine lifestyle changes (new exercise routine, changed sleep schedule) versus temporary disruptions? What validation approach can confirm the model is actually tracking something real — can you construct a ground truth from the executive's own retrospective assessment of their good-thinking versus bad-thinking times?
6. Chronotype-aware insight delivery — when to surface versus hold. Given a calibrated model of when the executive thinks best, how should the system decide when to deliver different types of intelligence? Research on optimal timing for information delivery — when are people most receptive to new information, most capable of integrating complex data, most open to uncomfortable feedback? Is there research on 'decision readiness' as a measurable state? The system needs a decision rule: given an insight of type X (routine briefing, uncomfortable pattern, urgent alert, strategic recommendation, relationship warning), and the executive is currently at energy level Y at time Z in their cycle, should the system deliver now or hold? What frameworks exist for this kind of delivery timing optimisation? Research on notification timing and receptivity. Research on interruptibility estimation from behavioural signals. How do you distinguish between 'hold because they're depleted' and 'hold because they're in flow and shouldn't be interrupted' — these require opposite responses to the same outward signal of sustained focus?

Synthesis and output format I need:

- A chronotype inference model specification — which signals map to which features, what algorithm estimates the current state, how the model updates over time
- An energy depletion detection specification — input signals, depletion drivers with weights, detection thresholds, recovery modelling
- A timing decision framework for insight delivery — decision tree or rule set mapping (insight type × current cognitive state × time of day) to deliver/hold/queue decisions
- For each component: what the research validates versus what requires empirical calibration per individual
- Specific citations for every claim — I need to trace these back to primary sources

Here's the report — a comprehensive research foundation for Timed's cognitive intelligence layer.

The report covers all six dimensions of your query and delivers the three operational specifications you requested:

**What the research most strongly validates for your build:**

- **Chronotype inference from typing dynamics** is the most evidence-grounded signal you have. The correlation between first/last keyboard activity and sleep onset/offset is r = 0.74–0.80, and the GRSVD method (Nature npj, 2025) extracts diurnal rhythms from typing patterns with sufficient precision to detect timezone desynchrony — this is your primary Tier 1 signal.[^1_1][^1_2][^1_3]
- **Keystroke dynamics for fatigue detection** is validated at AUC 72–80%. The specific features that matter are: interkey interval (mean and variance), hold time, flight time, and backspace rate. Afternoon sessions show dual degradation (speed and accuracy); morning sessions show accuracy-only degradation — that asymmetry is itself a phase indicator.[^1_4][^1_5]
- **The Wieth \& Zacks inversion** is arguably the most counter-intuitive but operationally critical finding: insight problem-solving rate is 0.42 at non-optimal times versus 0.33 at peak. Timed must implement this — delivering strategic recommendations at circadian peak but creative/novel-framing content at the trough.[^1_6]

**The hardest unsolved problem** in your architecture is the flow/fatigue disambiguation — both produce sustained-focus signals that look identical from the outside. The report proposes a trajectory slope approach (velocity declining = fatigue; flat/rising = flow candidate) combined with the energy budget `E(t)` as the disambiguation engine.

**Where the research is genuinely thin:** No peer-reviewed study validates email response latency as a chronotype proxy for executives specifically, and the C-suite population is almost entirely absent from chronotype-performance studies (all research is on students and shift workers). You will be generating original empirical data here.
<span style="display:none">[^1_10][^1_100][^1_101][^1_102][^1_103][^1_104][^1_105][^1_106][^1_107][^1_108][^1_109][^1_11][^1_110][^1_111][^1_112][^1_113][^1_114][^1_115][^1_116][^1_117][^1_118][^1_119][^1_12][^1_120][^1_121][^1_122][^1_123][^1_124][^1_125][^1_126][^1_127][^1_128][^1_129][^1_13][^1_130][^1_131][^1_132][^1_133][^1_134][^1_135][^1_136][^1_137][^1_138][^1_139][^1_14][^1_140][^1_141][^1_142][^1_143][^1_144][^1_145][^1_146][^1_147][^1_148][^1_149][^1_15][^1_150][^1_151][^1_152][^1_153][^1_154][^1_155][^1_156][^1_157][^1_158][^1_159][^1_16][^1_160][^1_161][^1_162][^1_163][^1_164][^1_165][^1_166][^1_167][^1_168][^1_169][^1_17][^1_170][^1_171][^1_172][^1_173][^1_174][^1_175][^1_176][^1_177][^1_178][^1_179][^1_18][^1_180][^1_181][^1_182][^1_183][^1_184][^1_185][^1_186][^1_187][^1_188][^1_189][^1_19][^1_190][^1_191][^1_192][^1_193][^1_194][^1_195][^1_196][^1_197][^1_198][^1_199][^1_20][^1_200][^1_201][^1_21][^1_22][^1_23][^1_24][^1_25][^1_26][^1_27][^1_28][^1_29][^1_30][^1_31][^1_32][^1_33][^1_34][^1_35][^1_36][^1_37][^1_38][^1_39][^1_40][^1_41][^1_42][^1_43][^1_44][^1_45][^1_46][^1_47][^1_48][^1_49][^1_50][^1_51][^1_52][^1_53][^1_54][^1_55][^1_56][^1_57][^1_58][^1_59][^1_60][^1_61][^1_62][^1_63][^1_64][^1_65][^1_66][^1_67][^1_68][^1_69][^1_7][^1_70][^1_71][^1_72][^1_73][^1_74][^1_75][^1_76][^1_77][^1_78][^1_79][^1_8][^1_80][^1_81][^1_82][^1_83][^1_84][^1_85][^1_86][^1_87][^1_88][^1_89][^1_9][^1_90][^1_91][^1_92][^1_93][^1_94][^1_95][^1_96][^1_97][^1_98][^1_99]</span>

<div align="center">⁂</div>

[^1_1]: https://pmc.ncbi.nlm.nih.gov/articles/PMC6784249/

[^1_2]: https://www.thewep.org/documentations/mctq

[^1_3]: https://cet.org/wp-content/uploads/2017/10/Zavada-2005-CI.pdf

[^1_4]: https://pmc.ncbi.nlm.nih.gov/articles/PMC3102480/

[^1_5]: https://pmc.ncbi.nlm.nih.gov/articles/PMC5479630/

[^1_6]: https://www.nature.com/articles/s41598-025-00893-8

[^1_7]: https://pmc.ncbi.nlm.nih.gov/articles/PMC5133733/

[^1_8]: https://bura.brunel.ac.uk/bitstream/2438/26468/4/FullText.pdf

[^1_9]: https://pmc.ncbi.nlm.nih.gov/articles/PMC10683050/

[^1_10]: https://www.academia.edu/93338482/The_synchrony_effect_revisited_chronotype_time_of_day_and_cognitive_performance_in_a_semantic_analogy_task

[^1_11]: https://pmc.ncbi.nlm.nih.gov/articles/PMC6200828/

[^1_12]: https://pmc.ncbi.nlm.nih.gov/articles/PMC12528034/

[^1_13]: https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2025.1649396/full

[^1_14]: https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2017.00188/full

[^1_15]: https://www.nature.com/articles/s41467-021-24885-0

[^1_16]: https://www.tandfonline.com/doi/full/10.1080/07420528.2025.2490495

[^1_17]: https://creativiteach.me/wp-content/uploads/2013/12/weithzacks.pdf

[^1_18]: https://kathrynwelds.com/2014/03/02/time-of-day-affects-problem-solving-abilities/

[^1_19]: https://ink.library.smu.edu.sg/cgi/viewcontent.cgi?article=7688\&context=lkcsb_research

[^1_20]: https://www.cambridge.org/core/journals/judgment-and-decision-making/article/pretrial-release-judgments-and-decision-fatigue/85614F4520F57B10C20F7A3BB786ADF8

[^1_21]: https://www.sciencedirect.com/science/article/abs/pii/S0165032721009009

[^1_22]: https://scholarlypublications.universiteitleiden.nl/access/item:3250795/view

[^1_23]: https://www.tandfonline.com/doi/full/10.1080/07420528.2025.2611866

[^1_24]: https://pure.manchester.ac.uk/ws/files/114538999/Longitudinal_Change_of_Sleep_Timing_Association_between_Chronotype_and_Longevity_in_Older_Adults.docx

[^1_25]: https://pmc.ncbi.nlm.nih.gov/articles/PMC8519005/

[^1_26]: https://pmc.ncbi.nlm.nih.gov/articles/PMC12047923/

[^1_27]: https://pubmed.ncbi.nlm.nih.gov/40321297/

[^1_28]: https://www.pbs.org/wgbh/nova/article/track-social-jet-lag-twitter/

[^1_29]: https://www.eurekalert.org/news-releases/830798

[^1_30]: https://www.getmailbird.com/email-activity-timelines-privacy-metadata-risks/

[^1_31]: https://pmc.ncbi.nlm.nih.gov/articles/PMC11041424/

[^1_32]: https://biomedeng.jmir.org/2022/2/e41003

[^1_33]: https://en.wikipedia.org/wiki/Basic_rest%E2%80%93activity_cycle

[^1_34]: https://academic.oup.com/sleep/article-abstract/5/4/311/2753285

[^1_35]: https://pure.psu.edu/en/publications/ultradian-cognitive-performance-rhythms-during-sleep-deprivation/

[^1_36]: https://www.cannelevate.com.au/article/understanding-ultradian-rhythms-brains-90-minute-cycles-explained/

[^1_37]: https://pubmed.ncbi.nlm.nih.gov/2420557/

[^1_38]: https://www.sciencedirect.com/science/article/abs/pii/030105119505121P

[^1_39]: https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0239984

[^1_40]: https://mhealth.jmir.org/2021/3/e24465

[^1_41]: https://www.frontiersin.org/journals/behavioral-economics/articles/10.3389/frbhe.2023.1225856/full

[^1_42]: https://pmc.ncbi.nlm.nih.gov/articles/PMC8358561/

[^1_43]: https://get-alfred.ai/blog/ultradian-rhythms

[^1_44]: https://www.microsoft.com/en-us/worklab/work-trend-index/brain-research

[^1_45]: https://meassociation.org.uk/2023/05/america-rethinking-fatigue-feeling-tired-vs-being-physically-depleted/

[^1_46]: https://www.linkedin.com/pulse/unraveling-myths-ego-depletion-new-take-willpower-tomas-kucera-fgtve

[^1_47]: https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2017.01672/full

[^1_48]: https://www.frontiersin.org/journals/neuroergonomics/articles/10.3389/fnrgo.2024.1375913/full

[^1_49]: https://www.speakandregret.michaelinzlicht.com/p/the-collapse-of-ego-depletion

[^1_50]: https://lupinepublishers.com/psychology-behavioral-science-journal/fulltext/ego-depletion-is-the-best-replicated-finding-in-all-of-social-psychology.ID.000234.php

[^1_51]: https://www.nytimes.com/2011/08/21/magazine/do-you-suffer-from-decision-fatigue.html

[^1_52]: https://www.newpowerlabs.org/equity-shots-blog/decision-fatigue

[^1_53]: https://pmc.ncbi.nlm.nih.gov/articles/PMC3198355/

[^1_54]: https://drcharlesmrusso.substack.com/p/decision-fatigue-and-its-impact-on

[^1_55]: https://www.cannelevate.com.au/article/context-switching-productivity-hidden-cost-modern-work/

[^1_56]: https://get-alfred.ai/blog/attention-residue/

[^1_57]: https://www.hbs.edu/faculty/Pages/item.aspx?num=54691

[^1_58]: https://www.mckinsey.com/about-us/new-at-mckinsey-blog/how-do-ceos-manage-their-time-the-winners-of-the-60th-annual-hbr-mckinsey-award-explain

[^1_59]: https://www.cnbc.com/2018/06/20/harvard-study-what-ceos-do-all-day.html

[^1_60]: https://www.forbes.com/sites/markhall/2018/06/25/how-ceo-spend-time/

[^1_61]: https://www.pbahealth.com/elements/time-management-techniques-from-successful-ceos/

[^1_62]: https://www.mgma.com/articles/test-of-time-harvard-study-reveals-how-ceos-spend-their-days-on-and-off-work

[^1_63]: https://get-alfred.ai/blog/makers-schedule-vs-managers-schedule

[^1_64]: https://www.paulgraham.com/makersschedule.html

[^1_65]: https://fs.blog/maker-vs-manager/

[^1_66]: https://www.uwb.edu/business/faculty/sophie-leroy/attention-residue

[^1_67]: https://www.mindspacex.com/post/copy-of-context-switching-the-hidden-productivity-killer-how-to-avoid-it

[^1_68]: https://meetingminutes.io/meeting-free-days-benefits/

[^1_69]: https://sloanreview.mit.edu/article/the-surprising-impact-of-meeting-free-days/

[^1_70]: https://www.sunsama.com/blog/task-batching

[^1_71]: https://tandemcoach.co/optimal-work-rhythm-chronotypes/

[^1_72]: https://psychotricks.com/rule-of-batching/

[^1_73]: https://www.elsevier.com/about/press-releases/researchers-identify-speech-latency-as-a-key-biomarker-for-predicting

[^1_74]: https://arxiv.org/pdf/2207.03405.pdf

[^1_75]: https://etheses.bham.ac.uk/7440/1/Mehrotra17PhD.pdf

[^1_76]: https://www.interruptions.net/literature/Fischer-PhD_Thesis.pdf

[^1_77]: https://pmc.ncbi.nlm.nih.gov/articles/PMC7983950/

[^1_78]: https://arxiv.org/html/2406.07067v1

[^1_79]: https://pmc.ncbi.nlm.nih.gov/articles/PMC10882474/

[^1_80]: https://www.innovativehumancapital.com/article/dynamic-behavior-readiness-systems-a-multi-state-framework-for-sustainable-organizational-performan

[^1_81]: https://betterhumans.pub/avoid-burnout-and-increase-awareness-using-ultradian-rhythms-5e64158e7e19

[^1_82]: https://www.hustleescape.com/cycle-thinking/

[^1_83]: https://pmc.ncbi.nlm.nih.gov/articles/PMC11100432/

[^1_84]: https://www.thelearningzone.com.au/articles-and-insights/scientific-proof-that-90-minute-learning-is-better-for-you

[^1_85]: https://pubmed.ncbi.nlm.nih.gov/2595175/

[^1_86]: https://academic.oup.com/sleep/article-pdf/12/6/522/8660914/120606.pdf

[^1_87]: https://www.asianefficiency.com/productivity/ultradian-rhythms/

[^1_88]: https://sleepmeeting.org/wp-content/uploads/2018/10/abstractbook2015.pdf

[^1_89]: https://pubmed.ncbi.nlm.nih.gov/23606612/

[^1_90]: https://www.med.upenn.edu/cbti/assets/user-content/documents/Munich Chronotype Questionnaire (MCTQ).pdf

[^1_91]: https://www.ornge.ca/Media/Ornge/Documents/Campaign Documents/ACAT/Munich-ChronoType-Questionnaire-(1).pdf

[^1_92]: https://longevity.stanford.edu/wp-content/uploads/sites/2/2016/04/2007SleepMedRevRoenneberg.pdf

[^1_93]: https://cancercontrol.cancer.gov/brp/research/group-evaluated-measures/adopt/mctq

[^1_94]: https://pmc.ncbi.nlm.nih.gov/articles/PMC5394171/

[^1_95]: https://www.reddit.com/r/slatestarcodex/comments/880h6d/belief_in_willpower_as_a_limited_resource_roy/

[^1_96]: https://www.youtube.com/watch?v=HD-dxUZxMcs

[^1_97]: https://www.facebook.com/groups/853552931365745/posts/7451644018223237/

[^1_98]: https://www.bloomberg.com/news/articles/2025-11-21/which-social-psychology-theories-survived-the-replication-crisis

[^1_99]: https://papers.ssrn.com/sol3/Delivery.cfm/SSRN_ID3741635_code1282794.pdf?abstractid=3741635

[^1_100]: https://www.pyrrhicpress.org/articles/2627701_cognitive-load-capitalism-how-modern-work-design-exhausts-executive-function-and-undermines-organizational-intelligence

[^1_101]: https://hbr.org/2018/07/how-ceos-manage-time

[^1_102]: https://www.forbes.com/sites/julianhayesii/2026/01/27/how-a-ceos-circadian-rhythm-shapes-their-health-and-leadership/

[^1_103]: https://www.youtube.com/watch?v=Z50R1fERVXs

[^1_104]: https://www.ceoupdate.com/how-ceos-manage-priorities-allocate-their-time-and-energy

[^1_105]: https://www.youtube.com/watch?v=gOWI0jWOGFw

[^1_106]: https://academic.oup.com/sleepadvances/article/6/2/zpaf019/8090424

[^1_107]: https://pac.cs.cornell.edu/pubs/social_jet_lag.pdf

[^1_108]: https://elifesciences.org/reviewed-preprints/96803v2

[^1_109]: https://pmc.ncbi.nlm.nih.gov/articles/PMC9842555/

[^1_110]: https://formative.jmir.org/2023/1/e38112

[^1_111]: https://www.aijfr.com/papers/2025/5/1370.pdf

[^1_112]: https://www.jci.org/articles/view/120874/version/3/pdf/render.pdf

[^1_113]: https://ijcrt.org/papers/IJCRT2603178.pdf

[^1_114]: https://ieeexplore.ieee.org/document/11258925/

[^1_115]: https://www.sciencedirect.com/science/article/abs/pii/S0165178121000196

[^1_116]: https://pmc.ncbi.nlm.nih.gov/articles/PMC11360591/

[^1_117]: https://esd.copernicus.org/articles/16/1539/2025/

[^1_118]: https://er.educause.edu/articles/2024/11/navigating-change-fatigue-the-energy-commitment-model-for-organizational-change

[^1_119]: https://pubmed.ncbi.nlm.nih.gov/31328571/

[^1_120]: https://arxiv.org/html/2504.03915v1

[^1_121]: https://www.sciencedirect.com/science/article/abs/pii/S0191886925000820

[^1_122]: https://www.sleepmedres.org/journal/view.php?number=18

[^1_123]: https://pmc.ncbi.nlm.nih.gov/articles/PMC7889722/

[^1_124]: https://pmc.ncbi.nlm.nih.gov/articles/PMC10757227/

[^1_125]: https://www.nature.com/articles/s41746-025-02254-1

[^1_126]: https://pmc.ncbi.nlm.nih.gov/articles/PMC9225607/

[^1_127]: https://acrpnet.org/2025/08/19/unlocking-the-power-of-digital-biomarkers-in-clinical-trials

[^1_128]: https://www.jmir.org/2024/1/e56144/PDF

[^1_129]: https://wellcomeopenresearch.org/articles/9-64/pdf

[^1_130]: https://magazine.washington.edu/theres-no-such-thing-as-multitasking-according-to-business-expert-sophie-leroy/

[^1_131]: https://www.forbes.com/sites/traversmark/2026/02/27/the-no-1-habit-that-hurts-your-productivity-by-a-psychologist/

[^1_132]: https://pmc.ncbi.nlm.nih.gov/articles/PMC9003457/

[^1_133]: https://onlinelibrary.wiley.com/doi/full/10.1111/tops.12669

[^1_134]: https://www.sciencedirect.com/science/article/abs/pii/S1053811919300990

[^1_135]: https://pmc.ncbi.nlm.nih.gov/articles/PMC11644966/

[^1_136]: https://web.math.princeton.edu/~rvan/orf557/hmm080728.pdf

[^1_137]: https://www.techscience.com/cmc/v79n1/56317/html

[^1_138]: https://oecs.mit.edu/pub/bq8p3lmb

[^1_139]: https://www.nature.com/articles/s41598-024-66839-8

[^1_140]: https://www.sciencedirect.com/science/article/pii/S2405844022024926

[^1_141]: https://pmc.ncbi.nlm.nih.gov/articles/PMC8455015/

[^1_142]: https://onehealthtrust.org/publications/peer-reviewed-articles/adolescents-cognitive-performance-peaks-in-the-evening-isolating-time-of-day-effects/

[^1_143]: https://www.neurologyadvisor.com/news/sleep-duration-chronotype-cognitive-function-adults/

[^1_144]: https://pmc.ncbi.nlm.nih.gov/articles/PMC4547044/

[^1_145]: https://elifesciences.org/articles/53060

[^1_146]: https://kuscholarworks.ku.edu/server/api/core/bitstreams/e10bb604-ed06-455c-a77b-7884668a80aa/content

[^1_147]: https://www.linkedin.com/posts/carolynlyden_this-week-i-had-two-days-with-almost-no-meetings-activity-7438305101490020353-zqdw

[^1_148]: https://www.sciencedirect.com/science/article/pii/S0149763426000710

[^1_149]: https://online.ucpress.edu/collabra/article/7/1/21939/116750/Circadian-Rhythm-and-Memory-Performance-No-Time-Of

[^1_150]: https://www.superpowers.school/p/research-into-meeting-free-days

[^1_151]: https://openresearch.surrey.ac.uk/view/pdfCoverPage?instCode=44SUR_INST\&filePid=13140508750002346\&download=true

[^1_152]: https://www.sciencedirect.com/science/article/abs/pii/S0149763423000830

[^1_153]: https://journals.sagepub.com/doi/abs/10.1177/2158244017728321

[^1_154]: https://aithority.com/ait-featured-posts/neuroadaptive-ai-systems-that-change-behavior-based-on-your-cognitive-load/

[^1_155]: https://sleepandhypnosis.org/wp-content/uploads/2024/07/e178071f39874f958f6a0ca04039a483.pdf

[^1_156]: https://www.tandfonline.com/doi/full/10.1080/10447318.2021.1913860

[^1_157]: https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod4/Module-4-Morningness-Eveningness-Questionnaire.pdf

[^1_158]: https://arxiv.org/html/2201.03074v3

[^1_159]: https://pubmed.ncbi.nlm.nih.gov/30085831/

[^1_160]: https://www.jmir.org/2025/1/e77066

[^1_161]: https://community.metaspike.com/t/hidden-timestamps/474

[^1_162]: https://registeredemail.com/product/legalproof/proof-of-email-receipt-timestamps

[^1_163]: https://learn.microsoft.com/en-us/answers/questions/5788555/timestamp-in-received-email-header-and-on-outlook

[^1_164]: https://www.zoho.com/eprotect/articles/what-is-email-metadata.html

[^1_165]: https://www.washingtonpost.com/wellness/2023/05/04/fatigue-tired-coping/

[^1_166]: https://pmc.ncbi.nlm.nih.gov/articles/PMC9924280/

[^1_167]: https://stackoverflow.com/questions/17057471/sending-notification-emails-based-on-each-db-record-timestamp

[^1_168]: https://journals.sagepub.com/doi/abs/10.1177/2633489520933896

[^1_169]: https://www.meridiandiscovery.com/articles/email-attachment-timestamps-forensics-outlook/

[^1_170]: https://lsa.umich.edu/psych/news-events/all-news/faculty-news/rethinking-fatigue--feeling-tired-vs--being-physically-depleted.html

[^1_171]: https://www.linkedin.com/posts/ashleygoodall_last-week-i-wrote-about-decision-fatigue-activity-7429540156220735488-ZONd

[^1_172]: https://www.reddit.com/r/brasil/comments/1n3on5y/pesquisa_cronotipo_jet_lag_social_e_direito_%C3%A0/

[^1_173]: https://journals.sagepub.com/doi/10.1177/0748730412475042

[^1_174]: https://www.nielsvanberkel.com/files/publications/mobilehci17a.pdf

[^1_175]: https://neurosciencenews.com/social-jet-lag-twitter-10214/

[^1_176]: https://interruptions.net/literature/Turner-HBU15.pdf

[^1_177]: https://phys.org/news/2018-11-twitter-social-seasons-daylight.html

[^1_178]: https://www.garbageday.email/p/twitter-is-about-12-hours-slower

[^1_179]: https://doaj.org/article/2d10bd5ce7ec48998afa759d222ee3e5

[^1_180]: https://pubmed.ncbi.nlm.nih.gov/41444764/

[^1_181]: https://academic.oup.com/rfs/article/31/5/1605/4708267?login=true

[^1_182]: https://www.brainfacts.org/thinking-sensing-and-behaving/thinking-and-awareness/2022/flow-the-science-behind-deep-focus-090122

[^1_183]: https://www.jmir.org/2024/1/e50149/PDF

[^1_184]: https://people.duke.edu/~charvey/Research/Published_Papers/P109_Managerial_attitudes_and.pdf

[^1_185]: https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2023.1248474/full

[^1_186]: https://scholar.google.com/citations?user=K8n58csAAAAJ\&hl=en

[^1_187]: https://corpgov.law.harvard.edu/2013/04/08/managerial-attitudes-and-corporate-actions/

[^1_188]: https://ideas.repec.org/a/eee/jfinec/v109y2013i1p103-121.html

[^1_189]: https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0335711

[^1_190]: https://pmc.ncbi.nlm.nih.gov/articles/PMC9012385/

[^1_191]: https://doi.org/10.1007/s40675-026-00366-y

[^1_192]: https://pmc.ncbi.nlm.nih.gov/articles/PMC9868093/

[^1_193]: https://www.nature.com/articles/s43856-026-01380-5_reference.pdf

[^1_194]: https://e-m-mccormick.github.io/static/longitudinal-primer/03-time.html

[^1_195]: https://www.linkedin.com/posts/nicole-l-petty-646008a6_research-proves-your-brain-needs-breaks-activity-7353923537629323264-wFZw

[^1_196]: https://hc.mountsinai.org/understanding-your-chronotype/

[^1_197]: https://pure.eur.nl/ws/portalfiles/portal/202730898/1-s2.0-S0013935125001252-main.pdf

[^1_198]: https://www.upskillspecialists.com/post/task-batching

[^1_199]: https://pubmed.ncbi.nlm.nih.gov/19250799/

[^1_200]: https://www.bmj.com/content/389/bmj-2024-081660

[^1_201]: https://pmc.ncbi.nlm.nih.gov/articles/PMC12730932/

