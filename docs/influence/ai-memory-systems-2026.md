# AI Memory Systems Landscape Analysis (2026)

*Analysis Date: 2026-05-23*
*Source: "The state of AI memory systems: benchmarks, architectures, and what actually works"*
*Author: Yohei Nakajima (compiled by Claude Opus 4.6 Research)*
*Source URL: https://x.com/yoheinakajima/status/2037201711937577319*
*Type: Meta-study (article, not single repository)*

---

## Executive Summary

### What this is

This is a **field survey**, not a single-repo study. The article reviews seven memory benchmarks and ~12 open-source memory systems published 2024-2026, ranks them by performance, and extracts five architectural patterns that separate top performers from the rest. Unlike a `/study-repo` of one codebase, the unit of analysis is **architectural choices that correlate with benchmark wins**.

### Key finding from the article

> "Architecture matters more than model size. A 20B-parameter model with Hindsight's multi-strategy memory achieves 83.6% on LongMemEval, dramatically outperforming full-context GPT-4o at 60.2%."

The field is converging on a specific template: **hybrid vector+graph storage, multi-strategy retrieval with reranking, explicit temporal modeling, and active memory consolidation**. Pure vector-store approaches (Mem0) plateau around 49% on LongMemEval; graph-native systems (Zep) reach 71%; multi-strategy systems (Hindsight) break 90%.

### Why ClaudeMemory cares

ClaudeMemory sits architecturally closest to Mem0 (vector + light graph via entity_aliases and fact_links, SQLite-only, LLM-light extraction). The article quantifies the cost of that choice — 22-point gap to Zep on LongMemEval, ~42-point gap to Hindsight. We don't need to chase those numbers, but the gaps tell us where our retrieval will *predictably* fail (multi-hop, temporal reasoning, conflict resolution at scale) and what's worth adopting given our local-first, no-cloud, single-developer constraints.

### Systems surveyed in the article (for cross-reference)

| System | Architecture | LongMemEval | LoCoMo | License |
|--------|--------------|-------------|--------|---------|
| Hindsight (Vectorize) | 4 networks + 4-strategy retrieval + cross-encoder | **91.4%** | 89.61% | MIT |
| Zep / Graphiti | Bi-temporal knowledge graph | 71.2% | 75.14% (disputed) | Apache 2.0 |
| MemGPT / Letta | OS-style hierarchy + agent-controlled | n/a | 74.0% (filesystem variant) | Apache 2.0 |
| Mem0 | Vector + optional graph, LLM-orchestrated CRUD | ~49% | 66.9-68.5% | Apache 2.0 |
| Cognee | Graph + vector + relational + ontology validation | n/a | n/a (self-reported wins) | Apache 2.0 |
| HippoRAG | Hippocampal indexing + Personalized PageRank | n/a | n/a | MIT |
| Letta (filesystem) | Simple file tools + agent capability | n/a | 74.0% | Apache 2.0 |

None of these were cloned for this study — the article itself is the primary source. Source-level file:line references in this document are to **ClaudeMemory** code, for adoption assessment.

### Production readiness assessment (article-derived)

- **Most mature**: Zep/Graphiti (24K stars, enterprise customers, Apache 2.0)
- **Best-published benchmarks**: Hindsight (MIT, but optimized for Vectorize-as-a-service)
- **Best fit for local-first**: Cognee (file-based defaults, swappable to cloud DBs) and Letta (open agent file format)
- **Most disputed**: LoCoMo benchmark itself — Mem0 and Zep publicly contradict each other's scores; the article calls LoCoMo "unreliable for cross-vendor comparison."

---

## Architecture Overview

### The Five Patterns (article's central claim)

The article identifies five patterns where the correlation with benchmark performance is "nearly linear":

1. **Multi-strategy retrieval** is the single biggest differentiator. Hindsight (4 strategies, 91.4%) > Zep (3 strategies, 71.2%) > Mem0 (1-2 strategies, 49%).
2. **Graph structure is essential for complex reasoning, vector for breadth.** Every top system uses hybrid storage.
3. **Temporal modeling correlates with the largest gains.** Systems with explicit temporal models score 20-60 points higher on temporal queries.
4. **Active memory consolidation prevents degradation at scale.** Top systems all run a background "refine/invalidate/prune" pass.
5. **Agent-controlled memory can outperform specialized infrastructure.** Letta's filesystem approach beat Mem0's purpose-built memory by 5.5 points on LoCoMo.

### Comparison Table: ClaudeMemory vs. the field

| Capability | Hindsight | Zep | Letta | Mem0 | Cognee | **ClaudeMemory** |
|-----------|-----------|-----|-------|------|--------|------------------|
| Vector search | ✅ cosine | ✅ cosine | ✅ pgvector | ✅ Qdrant | ✅ LanceDB | ✅ sqlite-vec (vec0) |
| BM25 / FTS | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ FTS5 |
| Graph traversal | ✅ | ✅ BFS | ❌ | ✅ (graph variant) | ✅ | ⚠️ partial (entity_aliases, fact_links — no traversal API) |
| Temporal-aware retrieval | ✅ dual timestamps | ✅ bi-temporal | ❌ | ⚠️ basic | ✅ | ⚠️ valid_from/valid_to in schema, not in ranking |
| Reranking | ✅ cross-encoder | ✅ RRF/MMR/cross-encoder | ❌ | ❌ | ❌ | ✅ RRF (`lib/claude_memory/core/rr_fusion.rb:1`) |
| Reflection/consolidation | ✅ reflect op | ✅ invalidate-not-delete | ✅ sleep-time compute | ✅ LLM CRUD | ✅ memify | ⚠️ supersession + sweep TTLs; no LLM reflect step |
| Agent-controlled writes | ❌ | ❌ | ✅ core operation | ❌ | ❌ | ⚠️ `memory.store_extraction` exists but ingestion is mostly passive via hooks |
| Bi-temporal (valid+ingest time) | ✅ | ✅ 4 timestamps | ❌ | ❌ | ⚠️ | ❌ (only valid_from/valid_to + created_at) |
| Fact / opinion separation | ✅ 4 networks | ⚠️ episode vs semantic | ⚠️ human vs persona block | ❌ | ❌ | ❌ (single facts table, all predicates equal) |
| Latency target | n/a | <200ms-1s P95 | varies | 1.4s P95 | n/a | hook context + recall: typically <100ms for SQLite read |
| Ingestion cost | high (parallel strategies) | hours for large corpora (many LLM calls) | low | low | medium | **low** (Layer 1 NullDistiller is free; Layer 2 piggybacks on Claude Code session) |

ClaudeMemory's profile: **vector + FTS + light graph hints, no traversal, no temporal-aware ranking, no reflection pass, mostly passive ingestion.** Closest peer: Mem0 base variant — which the article scores at ~49% on LongMemEval. The features we've explicitly *rejected* (cross-encoder reranking, LLM query expansion, custom fine-tuned models — see `docs/improvements.md` "Features to Avoid") are the same ones Hindsight uses to break 90%. The article suggests we are correctly trading some peak benchmark score for cost/latency/local-first, but it also names two things we **didn't** trade away by choice but simply haven't built: temporal-aware ranking and explicit graph traversal.

---

## Key Components Deep-Dive

This section maps each pattern from the article to ClaudeMemory's current implementation and the gap, with `file:line` references to **our** code (the studied systems weren't cloned).

### 1. Multi-Strategy Retrieval

**The article's claim.** Hindsight runs four concurrent retrieval strategies (cosine semantic similarity, BM25 keyword matching, graph traversal across the shared memory graph, temporal reasoning) and fuses them with cross-encoder reranking. On temporal queries specifically, this took accuracy from a 31.6% baseline to 91.0% — a 60-point gain. Zep's three strategies (cosine + BM25 + BFS graph traversal) hit 71.2% on LongMemEval. Mem0's 1-2 strategies score 49%.

**What we have.**

- Vector (`lib/claude_memory/index/vector_index.rb`): sqlite-vec native KNN.
- BM25/FTS5 (`lib/claude_memory/index/lexical_fts.rb`): SQLite FTS5 full-text.
- Fusion (`lib/claude_memory/core/rr_fusion.rb:1`): Reciprocal Rank Fusion of vec + FTS, with optional `score_trace` for debugging.

**What we don't have.**

- **No graph traversal as a retrieval strategy.** We store entity relationships in `entity_aliases` and supersession/conflict edges in `fact_links`, but no MCP tool walks them from a seed entity. `memory.fact_graph` returns immediate-neighbor facts for one fact_id; it doesn't BFS from a query.
- **No temporal-aware retrieval strategy.** We have `valid_from`, `valid_to`, `last_recalled_at` columns but the ranker doesn't use them as a third RRF input.

**Why this matters per the article.** "BM25 catches exact mentions that embedding search misses; graph traversal finds multi-hop connections invisible to flat similarity; temporal filtering prevents returning outdated facts." We have two of three; the third (graph BFS) is the one Zep credits for its 22-point lead over Mem0.

### 2. Hybrid Vector + Graph Storage

**The article's claim.** Pure-vector systems plateau at ~50% on LongMemEval; graph-native systems reach 71%+. "The specific graph implementation matters less than having one — Neo4j, FalkorDB, and custom in-memory graphs all appear in high-performing systems."

**What we have.** A subject-predicate-object fact table with entity nodes and edges between facts (`fact_links` for supersession + conflict). This is graph-shaped data but we don't expose it as a traversable graph at query time.

**What we don't have.** A `BFS from entity X over relationship type Y` capability. The article specifically calls out that this finds multi-hop connections invisible to similarity search ("Who recommended the architecture decision we're using for storage?" — needs entity-resolved hops, not text overlap).

**Why this matters per the article.** Quote: "Mem0's specific graph implementation matters less than having one." We have graph-shaped storage but no graph-shaped retrieval — the worst of both worlds if we don't fix this.

### 3. Explicit Temporal Modeling

**The article's claim.** Temporal reasoning is the hardest capability across every benchmark (up to 73% human-vs-system gap on LoCoMo). Hindsight stores **dual timestamps** (occurrence time + mention time) — "what happened when" vs "what did I learn when." Zep's **bi-temporal model** tracks four timestamps per edge:

- `valid_at` — when the fact became true in the world
- `invalid_at` — when it was superseded
- `created_at` — when Graphiti ingested it
- `expired_at` — when the record was logically replaced

This enables point-in-time queries ("What did we know about X on date Y?") and full audit trails.

**What we have.**

- `valid_from` / `valid_to` (`db/migrations/001_create_initial_schema.rb:64-65`) — world-time validity window.
- `created_at` — ingest time.
- `last_recalled_at` (schema v17) — access time.

**What we don't have.**

- No `invalid_at` / `expired_at` distinction. We set `valid_to` when superseded and `status='superseded'` — but `valid_to` conflates "world-time end" and "ingest-time supersession." A fact retroactively learned to have been false in 2023 and a fact superseded today look identical in the schema.
- No temporal-aware retrieval. `Recall` queries don't weight by recency, and `memory.recall` doesn't accept "as of <date>" filters.

**Why this matters per the article.** This is the field-wide weakness. Systems "with explicit temporal modeling consistently score 20-60 points higher on temporal queries than systems treating time as metadata." We're currently in the "metadata" camp.

### 4. Active Memory Consolidation

**The article's claim.** Systems that accumulate without consolidating suffer noise growth. The article catalogs five consolidation strategies:

- **Hindsight reflect** — updates beliefs based on new evidence.
- **Zep invalidate-not-delete** — contradicted facts are marked invalid, preserving history.
- **Cognee memify** — prunes stale nodes, strengthens frequent connections, derives new facts.
- **Letta sleep-time compute** — background agent processes facts during idle time using stronger/slower models, producing refined "learned context."
- **Mem0 LLM-CRUD** — ADD / UPDATE / DELETE / NOOP decided per-extraction by an LLM.

**What we have.**

- Supersession with provenance preservation (`lib/claude_memory/resolve/resolver.rb:126-149`) — closest to Zep's invalidate-not-delete (we set status=`superseded` and keep the row).
- Sweep with TTL escalation (`lib/claude_memory/sweep/maintenance.rb`) — closest to Cognee's pruning.
- Conflict detection — adjacent to Mem0's LLM-CRUD but rule-based, not LLM-driven.

**What we don't have.**

- **No reflect/refine pass.** We never re-examine an old fact in light of new context. A decision from January and one from May about the same subject don't get re-evaluated as a pair unless they happen to trigger supersession at insert time.
- **No background "learned context" agent.** Layer 2 distillation runs *only* on the current session's transcripts; nothing reflects on the full corpus during idle time.

**Why this matters per the article.** Without consolidation, signal-to-noise degrades as memory grows — this is the "scale" failure mode. Today our corpus is small (low hundreds of facts per project). The article suggests this will hurt at 10K+ facts.

### 5. Agent-Controlled Memory

**The article's claim.** Letta demonstrated that a simple filesystem approach (agent + file tools) hit 74% on LoCoMo with GPT-4o-mini, beating Mem0's purpose-built infrastructure at 68.5%. Quote: "Agent capability matters more than specialized memory infrastructure."

**What we have.**

- `memory.store_extraction` MCP tool — the agent *can* write, but in practice extraction happens passively via SessionStart hook injection (Layer 2 distillation).
- Five "shortcut" tools (`memory.decisions`, `memory.conventions`, `memory.architecture`, `memory.facts_by_tool`, `memory.facts_by_context`) the agent uses for recall.

**What we don't have.**

- No "agent decides when to remember" mode. Layer 1 (NullDistiller regex) runs unconditionally on hook events; Layer 2 runs on SessionStart; Layer 3 is user-triggered. The agent doesn't proactively decide "this thread is important, store it."

**Why this matters per the article.** This is the "autonomy vs. determinism" trade-off the article explicitly names. Letta's autonomy is non-deterministic and model-dependent; our determinism is fast and predictable. We probably don't want to flip the model — but a *partial* adoption (an explicit "save this for later" tool the agent can call mid-conversation) is consistent with our current architecture.

### 6. Benchmarks We're Not Running

**The article's claim.** Seven benchmarks now define the evaluation landscape:

| Benchmark | Year | What it tests | Notes |
|-----------|------|---------------|-------|
| LongMemEval | ICLR 2025 | 5 abilities × 500 questions, 115K-1.5M token contexts | Gold standard |
| LoCoMo | ACL 2024 | 10 conversations × 300 turns | Vendor-disputed; scores unreliable |
| MemBench | ACL 2025 | Factual vs reflective memory | Useful for our "decision vs convention" split |
| MemoryBench | Tsinghua 2025 | Continual learning from feedback | 11 datasets, 3 domains, 2 languages |
| MemoryAgentBench | ICLR 2026 | 4 competencies including conflict resolution | "No method excels at all four" |
| EverMemBench | Feb 2026 | Multi-party group conversations | Niche |
| Letta Leaderboard | 2025 | LLMs managing own memory via tools | Most relevant to our MCP design |

**What we have.** Our own eval suite (`spec/evals/`), DevMemBench (`spec/benchmarks/`), and `spec/benchmarks/comparative/` against QMD + grepai.

**What we don't have.** Any cross-comparison against LongMemEval or LoCoMo. We can't say with evidence "ClaudeMemory scores X on LongMemEval" — and given the article's framing, that's the question potential adopters will ask.

**Why this matters per the article.** LongMemEval is the only benchmark the article describes as rigorous. LoCoMo numbers are "unreliable for cross-vendor comparison" because of public scoring disputes. If we report any benchmark, it should be LongMemEval; if we cite LoCoMo it should be with the disclaimer.

---

## Comparative Analysis

### What the field does well that we don't

1. **Graph traversal at retrieval time** (Zep, Mem0 graph variant, Cognee). We store the graph; we don't walk it.
2. **Bi-temporal modeling** (Zep). We conflate world-time and ingest-time in a single `valid_to` column.
3. **Active consolidation / reflect pass** (Hindsight, Cognee memify, Letta sleep-time). We supersede at insert time only.
4. **Epistemic separation** (Hindsight 4 networks: world facts / agent experiences / entity observations / evolving opinions). We have `provenance.strength` (stated/inferred/derived) but don't route differently.
5. **Standardized benchmark scores** (LongMemEval). We have internal evals only.

### What we do well that they don't

1. **Local-first, zero-cloud-dependency.** Letta and Mem0 require PostgreSQL + (Qdrant or pgvector). Cognee defaults to file-based but is Python-heavyweight. Our gem + SQLite stack ships as a single Ruby dependency.
2. **No LLM in the retrieval path.** Zep makes this point ("no LLM calls during retrieval"), achieving 200ms-1s P95 — and so do we, even more aggressively (no inference at all, just SQL).
3. **Free Layer 2 distillation.** Mem0 calls an LLM for every extraction. Letta runs background sleep-time agents. We piggyback on the user's existing Claude Code session via context hook injection — zero additional API spend. This is genuinely novel and the article doesn't mention any equivalent.
4. **Provenance receipts on every fact.** Mem0 logs operations to SQLite for audit but doesn't tie each fact to a quoted source. Our `provenance` + `mcp_tool_calls` tables give every claim a traceable origin.
5. **Public predicate vocabulary.** PredicatePolicy is the article's missing piece for fact/opinion separation — it's an opinionated, curated set of 9 predicates with cardinality semantics, exposed publicly via `docs/api_stability.md`. Hindsight does this implicitly in code; we do it as a contract.

### Trade-offs the article explicitly names

| Tension | Their pole | Our pole |
|---------|-----------|----------|
| Richness vs. latency | Zep: hours of ingestion for richer graph | NullDistiller P95 <5ms; minutes for Layer 3 manual |
| Autonomy vs. determinism | Letta: agent-controlled, model-dependent | Deterministic SQL queries |
| Completeness vs. compression | Zep preserves raw episodes | We distill into structured facts only (raw transcript chunks live in `content_items` until swept) |

These poles match the design decisions we've already made and recorded. The article validates them, including specifically what we *gave up* (peak benchmark score on LongMemEval) for what we *gained* (sub-100ms recall, no cloud cost, no LLM in critical path).

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Graph Traversal as a Third Retrieval Strategy ⭐

- **Value.** The article credits graph-BFS as the difference between Mem0 (49% on LongMemEval) and Zep (71.2%). We already store the graph; we just don't traverse it at query time. This is the highest-leverage gap in our retrieval — work we've already done 80% of, exposed differently.
- **Evidence.** Article Pattern 1 + Pattern 2. ClaudeMemory has `fact_links` (supersession/conflict edges) and `entities`/`entity_aliases` (entity nodes) but `lib/claude_memory/recall.rb` doesn't BFS over them.
- **Implementation.** Add a `Recall::GraphTraversal` strategy: resolve the query to seed entities via the existing entity matcher, BFS one or two hops over `entities` ↔ `facts` ↔ `entities` (using `subject_id` and `object_entity_id` if present), score by hop distance × edge type. Fuse into the existing RRF in `Core::RRFusion` (`lib/claude_memory/core/rr_fusion.rb`) as a third source alongside vec + FTS. Bound BFS depth (1-2 hops) so latency stays sub-100ms.
- **Effort.** Medium — 2-3 days. The data is already shaped correctly; this is a new strategy class + RRF integration + tests.
- **Trade-off.** Adds a third source to RRF tuning. Empty graphs (early-project use) will simply contribute zero rerank weight — degrades gracefully.
- **Recommendation.** **ADOPT** in 0.12.0 or 0.13.0. Aligns with our existing hybrid retrieval; no new dependencies; demonstrably the field's biggest accuracy lever.

#### 2. Temporal-Aware Retrieval Strategy ⭐

- **Value.** The article says temporal reasoning shows the largest performance gaps across every benchmark (up to 73% on LoCoMo). Adding even basic recency weighting and "as-of" filtering would close part of this.
- **Evidence.** Article Pattern 3. Schema already has `valid_from`, `valid_to`, `created_at`, `last_recalled_at`. None are used in ranking.
- **Implementation.** Two pieces:
  1. **Recency boost in RRF.** Add a `temporal_rank` input to `Core::RRFusion`: facts with newer `valid_from` get a small rank boost (decay factor configurable). Doesn't replace lexical/semantic — it's a third (or fourth, with graph) RRF source.
  2. **`as_of` parameter on `memory.recall`.** Optional ISO 8601 timestamp; filters to facts where `valid_from <= as_of AND (valid_to IS NULL OR valid_to > as_of)`. Enables "what did we know about X on date Y" queries the article credits Zep with.
- **Effort.** Small — 1-2 days. Existing columns; just thread the new parameter and ranker.
- **Trade-off.** Recency weighting can over-rank ephemeral facts (e.g., a debugging note from yesterday vs. a long-standing convention). Cap the boost at low weight (e.g., 0.1× of vec contribution) and tune via the existing eval harness.
- **Recommendation.** **ADOPT** in 0.12.0 alongside #1. Tiny change, big article-validated upside, no new dependencies.

#### 3. Bi-Temporal Schema Cleanup (`world_invalid_at` vs `ingest_expired_at`)

- **Value.** Today, `valid_to` does double duty: "fact ceased to be true in the world" *and* "we superseded this fact during ingestion." The article calls this out specifically as Zep's most important innovation. With both columns, point-in-time queries work correctly — without them, we silently corrupt the temporal axis.
- **Evidence.** Article: "Every entity edge tracks four timestamps: valid_at (when the fact became true in the world), invalid_at (when it was superseded), created_at (when Graphiti ingested it), expired_at (when the record was logically replaced)."
- **Implementation.** Schema v18 migration: rename `valid_to` → `world_invalid_at`; add `ingest_expired_at` (datetime, nullable). Update `Resolver` to set `ingest_expired_at` on supersession and leave `world_invalid_at` for explicit user-supplied "this fact stopped being true on date X" updates. Backfill: copy existing `valid_to` into both columns (we can't recover the distinction historically).
- **Effort.** Medium — schema migration + resolver update + MCP tool surface (optional `world_invalid_at` parameter on `memory.reject_fact` and friends) + tests. 2-3 days.
- **Trade-off.** API surface change — `valid_to` is part of the public schema per `docs/api_stability.md`. Needs a deprecation cycle (alias `valid_to` to `world_invalid_at` in the Sequel model for one minor version).
- **Recommendation.** **ADOPT** in 0.13.0 (after #1 and #2). Lower urgency than the retrieval changes, but it's the foundation for any future "as of" reasoning, audit trail, and historical reasoning. Cheaper to do before our corpus grows.

#### 4. LongMemEval Benchmark Integration

- **Value.** The article calls LongMemEval the "gold standard." Without an external benchmark score, we can't credibly position ClaudeMemory against the field. Internal evals (which we have) don't answer "is this competitive with Zep/Mem0?"
- **Evidence.** Article: "LongMemEval has emerged as the gold standard… Three-stage framework (Indexing → Retrieval → Reading) with LLM-as-judge scoring provides the most rigorous evaluation available."
- **Implementation.** Add `spec/benchmarks/longmemeval/` adapter. Dataset is public (Wu et al. arXiv). Wire it into `bin/run-evals --longmemeval`. Report Recall@k, MRR, nDCG@10 the way DevMemBench already does.
- **Effort.** Medium — 2-4 days. Mostly dataset wrangling + adapter code. The existing DevMemBench pipeline already has the right shape.
- **Trade-off.** LongMemEval_S is ~115K tokens; ingesting all 500 questions will be slow and cost real API spend if we use Claude Code in the inner loop. Mitigation: stub mode for the retrieval-only portion (no LLM-judge), real mode opt-in.
- **Recommendation.** **ADOPT** in 0.12.0 or 0.13.0. This is what we'd cite in a release blog post; the article makes it clear it's the only number that matters.

### Medium Priority

#### 5. Reflect Pass — Background Consolidation on Idle

- **Value.** Hindsight's reflect operation and Letta's sleep-time compute both run a background process that re-examines stored facts using a stronger/slower model. The article credits this with preventing noise growth at scale. We don't have it; today our corpus is small enough to not need it; we will need it once any single project exceeds ~5K facts.
- **Evidence.** Article Pattern 4.
- **Implementation.** Extend `Sweep::Maintenance` with a `reflect` operation that runs during the SessionEnd hook when N facts have accumulated since last reflect. The reflect operation is an MCP-callable prompt: "Given these N facts about subject X, produce: (a) a consolidated summary fact, (b) any contradictions, (c) any facts that should be marked obsolete." Like Layer 2 distillation, this can piggyback on the user's Claude Code session — no extra API cost.
- **Effort.** Large — 5-7 days. Touches sweep, hooks, MCP, and skill design. Needs a careful prompt + good eval to prove we're not introducing hallucinated consolidations.
- **Trade-off.** Risk of consolidating away real distinctions. Mitigation: every consolidated fact links to the source facts via `fact_links` (already supported); manual `claude-memory reject` undoes a bad consolidation.
- **Recommendation.** **CONSIDER** for 1.0.0 or later. The article validates the direction; we don't have the scale problem yet. Track when largest project DB crosses 5K facts.

#### 6. `memory.save_this` Tool — Agent-Initiated Storage

- **Value.** Letta's striking result (74% vs Mem0's 68.5%) suggests that giving the agent explicit "save this" capability beats passive extraction in some scenarios. We already have `memory.store_extraction`, but it's framed as "report an extraction you found," not "I (the agent) want to remember this for later." A friendlier surface might increase use.
- **Evidence.** Article Pattern 5 + Letta filesystem result.
- **Implementation.** Add `memory.save_this` as a thin wrapper over `memory.store_extraction` with simpler prompt: "Save the most important fact from this turn for future sessions. Tag with `subject`, `predicate`, `object`, and a brief reason." Document it in the MCP `memory_guide` prompt as the agent's "I want to remember this" tool.
- **Effort.** Small — 1 day. Mostly MCP surface + prompt updates + tests.
- **Trade-off.** Could drive low-quality "save everything" behavior. Mitigation: existing `BareConclusionDetector` already gates against poor extractions.
- **Recommendation.** **CONSIDER** in 0.13.0 if first-week usage shows agents rarely use `store_extraction` proactively. Cheap to try; cheap to remove.

#### 7. Provenance Strength Routing (light epistemic separation)

- **Value.** Hindsight's 4-network architecture (world facts / agent experiences / entity observations / evolving opinions) gives different retrieval characteristics to different fact types. We have a similar axis — `provenance.strength` ∈ {stated, inferred, derived} — but the ranker doesn't use it.
- **Evidence.** Article: "Epistemic separation — structurally distinguishing evidence from inference — is a key innovation."
- **Implementation.** Add a small weight in `Core::RRFusion`: `stated` facts get full weight, `inferred` get 0.7×, `derived` get 0.5×. Surface a `strength_filter` parameter on `memory.recall` for "only stated facts" use cases.
- **Effort.** Small — 1 day. We already store the data.
- **Trade-off.** Minor — could under-rank inferred facts that are nonetheless useful. Tune via eval harness.
- **Recommendation.** **CONSIDER**. Already covered partially by improvement #57 (Provenance-Strength-Aware Retrieval Ranking) in `docs/improvements.md`. This article *strongly validates* that improvement; promoting #57 from Medium to High is the right move.

### Low Priority / Defer

#### 8. Ontology Validation Layer (Cognee-style)

- **Value.** Canonicalizes "car manufacturer," "automobile maker," "vehicle producer" into one entity. Reduces graph fragmentation.
- **Evidence.** Article: Cognee uses RDF/OWL ontologies + `difflib.get_close_matches()`.
- **Trade-off.** We already do this for predicates via `PredicatePolicy::SYNONYMS`. Extending to entities means defining ontologies per project — heavyweight for a single-developer tool.
- **Recommendation.** **DEFER**. Our entity_aliases mechanism is the lightweight version of this. Adopt only if entity fragmentation shows up as a real failure mode in benchmarks.

#### 9. LoCoMo Benchmark

- **Value.** Cross-comparison with other memory systems.
- **Evidence.** Article: "Vendor disputes about proper implementation… Mem0 and Zep have publicly contradicted each other's reported scores, making LoCoMo rankings unreliable for cross-vendor comparison."
- **Recommendation.** **DEFER**. The article specifically discredits LoCoMo as a comparison axis. LongMemEval (recommendation #4) is the right benchmark to invest in. If we cite LoCoMo at all, cite our own number standalone, not against vendor-reported scores.

### Features to Avoid (article-derived)

These are confirmed by the article as either over-engineering, mismatched, or solving problems we don't have:

- **Cross-encoder reranking** — Already in our avoid list. Article confirms: "Hindsight's four parallel retrieval strategies with cross-encoder reranking are expensive." No LLM in retrieval path is one of our key advantages.
- **Bi-temporal complexity beyond a second column** — Zep tracks four timestamps per edge. The article doesn't quantify the value of `expired_at` separately from `invalid_at`. Recommendation #3 above adopts the simpler 3-timestamp model (world_invalid_at + ingest_expired_at + created_at) rather than the full 4-column Graphiti schema.
- **Custom fine-tuned models for any pipeline stage** — Already in our avoid list. Hindsight's results require Gemini-3 Pro for the 91.4% number; their 20B open variant scores 83.6%. We can't and shouldn't compete with model size; per-the-article, architecture (which we can fix) matters more anyway.
- **Cloud-required architecture** — Letta requires PostgreSQL + pgvector; Cognee defaults to local but production runs PostgreSQL + Neo4j + Qdrant. Our SQLite-only stack is a real differentiator the article doesn't address.
- **Multi-network epistemic separation as a hard schema split** (full Hindsight 4-network model) — Over-complex for our scale. Recommendation #7 above adopts the soft version (weight by `provenance.strength`).
- **Conversation-level memory (Letta filesystem approach as primary mode)** — Article reports 74% on LoCoMo for filesystem-only, but the read/write loop consumes user-visible tokens on every interaction. Our hook-based passive ingestion is cheaper per session.
- **Sleep-time compute as a separate service** — Letta runs background agents. We can achieve the same effect on the next SessionStart for free (recommendation #5). No separate process needed.

---

## Implementation Recommendations

### Phase 1 — Validate the architecture pattern (0.12.0)

- **Graph traversal strategy** (recommendation #1, ⭐). Highest leverage; data is ready.
- **Temporal recency in RRF + `as_of` parameter** (recommendation #2, ⭐). Tiny code, big benchmark-validated upside.
- **LongMemEval integration** (recommendation #4, ⭐). Get a baseline number before we start tuning, so we can measure each subsequent change.

### Phase 2 — Foundation cleanup (0.13.0)

- **Bi-temporal schema cleanup** (recommendation #3). Schema change is easier now than later.
- **Promote improvement #57 to High and ship it** (recommendation #7). Already-tracked work; this article strongly validates it.
- **`memory.save_this` tool** (recommendation #6) if eval data suggests agents under-use `memory.store_extraction`.

### Phase 3 — Scale concerns (1.0.0 or later)

- **Reflect pass** (recommendation #5). Only when a real project DB crosses ~5K facts; until then, premature.

### What to skip

- **LoCoMo benchmark** (recommendation #9). Article explicitly discredits it for cross-vendor use.
- **Ontology validation** (recommendation #8). Our existing `entity_aliases` + `PredicatePolicy::SYNONYMS` are the right-sized version.

---

## Architecture Decisions

### What to preserve (validated by the article)

1. **Local-first, SQLite-only** — competitive differentiator vs. Letta/Cognee cloud stacks.
2. **No LLM in retrieval path** — Zep makes this same choice and credits it for <200ms-1s latency; we go further with no LLM at all.
3. **Hook-based passive ingestion via Claude Code session** — zero-API-cost Layer 2 distillation; the article surveys no equivalent.
4. **RRF over vec+FTS** — same pattern Zep uses (cosine + BM25 + BFS), we just need to add the third source.
5. **Publicly-versioned predicate vocabulary** (`PredicatePolicy` + `docs/api_stability.md`) — light, opinionated, stable. Field-wide there's no equivalent contract.
6. **Provenance receipts on every fact** — comparable systems log operations to SQLite but don't tie each fact to a quoted source.

### What to adopt (article-validated)

1. **Graph traversal as third retrieval strategy** — closes the largest article-named gap.
2. **Temporal-aware RRF + `as_of` queries** — closes the second-largest gap.
3. **Bi-temporal columns** — `world_invalid_at` separate from `ingest_expired_at`.
4. **LongMemEval as the comparison benchmark** — the only number the article describes as rigorous.

### What to reject

1. **Cross-encoder LLM reranking** — already rejected; the article confirms cost is the reason.
2. **Cloud-required graph DB** (Neo4j, FalkorDB) — SQLite + our existing schema is sufficient; recommendation #1 traverses the graph we already have.
3. **4-network hard epistemic split** — recommendation #7 adopts the soft (weight-by-strength) version.
4. **LoCoMo benchmark** — the article itself discredits cross-vendor comparison.

---

## Key Takeaways

1. **We are architecturally closer to Mem0 (49% on LongMemEval) than to Zep (71.2%) or Hindsight (91.4%).** That's mostly a deliberate trade for local-first / no-LLM-in-retrieval. But two pieces of the gap — graph traversal and temporal-aware retrieval — are unforced. We already store the data; we just don't query it.

2. **The biggest single improvement we can make is adding graph traversal as a third RRF source.** Article-validated as the difference between Mem0-class and Zep-class systems. We have the data shape; we don't have the strategy class.

3. **Layer 2 distillation (free LLM via Claude Code session) is genuinely novel.** No system the article surveys does this. We should keep emphasizing it in documentation and in any benchmark write-up.

4. **Our existing improvement #57 (Provenance-Strength-Aware Retrieval Ranking) is the soft version of Hindsight's epistemic separation.** This article promotes it from "nice to have" to "fits the field-wide pattern." Recommend moving #57 to High Priority.

5. **Temporal reasoning is the field's hardest problem.** We've under-invested here. Schema-level fix (recommendation #3) and ranker-level fix (recommendation #2) together cost about a week's work.

6. **We should benchmark against LongMemEval before tuning any of this.** Without a baseline, we can't tell which adopted changes help.

7. **Article's clearest negative result: pure vector approaches plateau at ~50% on LongMemEval.** Anything we do that doubles down on vector-only retrieval is investing in the wrong axis.

---

## Cross-References

- **`docs/improvements.md`** — recommendations #1, #2, #3, #4, #6 should be added as new entries. Recommendation #7 promotes existing #57 from Medium to High.
- **`docs/influence/qmd.md`**, **`docs/influence/grepai.md`** — these are the other single-repo studies in the same architectural space (hybrid vec+FTS, no graph, no temporal). The article suggests their tradeoffs match ours.
- **`docs/api_stability.md`** — schema changes in recommendation #3 (bi-temporal cleanup) need to land in the same commit as updates here. `valid_to` rename is a public-API break with deprecation aliasing.
- **`spec/benchmarks/README.md`** — recommendation #4 (LongMemEval integration) belongs in this directory.
- **`lib/claude_memory/core/rr_fusion.rb`** — recommendations #1, #2, #7 all add new sources to this fusion. Touching this file once for all three is cheaper than three separate passes.
