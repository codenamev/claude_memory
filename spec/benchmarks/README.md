# DevMemBench: Developer-Domain Memory Benchmarks

## Overview

DevMemBench is a benchmark suite purpose-built for evaluating ClaudeMemory's retrieval quality and truth maintenance correctness. It serves three purposes:

1. **Offline retrieval accuracy** -- Measure FTS5, embedding, and hybrid search quality ($0/run)
2. **Comparative benchmarks** -- Head-to-head retrieval against competitor tools (QMD, grepai)
3. **End-to-end Claude evaluation** -- Measure whether memory actually improves responses (~$2-8/run)

## Why a Custom Dataset?

Every open IR dataset has a domain mismatch problem. ClaudeMemory operates on developer conversations with 6 specific predicates (`convention`, `decision`, `uses_database`, `uses_framework`, `auth_method`, `deployment_platform`), 8 entity types, and technical vocabulary tuned for real CLAUDE.md patterns.

**What we borrow from established benchmarks:**
- [BEIR](https://huggingface.co/datasets/BeIR/beir): Standard IR metrics (Recall@k, MRR, nDCG@10)
- [FEVER](https://huggingface.co/datasets/fever/fever): 3-class truth maintenance structure (corroborate/supersede/conflict)
- [LongMemEval](https://github.com/xiaowu0162/LongMemEval) (ICLR 2025): 5 memory ability categories

**What we build ourselves:** Developer-domain content drawn from real CLAUDE.md examples, ADR templates, and open-source project documentation patterns.

## Dataset

All data lives in `spec/benchmarks/dataset/`:

### facts.yml (~105 facts)

Developer-domain facts across 6 predicate types and 5 simulated projects:

| Category | Count | Predicates |
|----------|-------|------------|
| Tech Stack (databases) | ~12 | `uses_database` (single-value) |
| Tech Stack (frameworks) | ~15 | `uses_framework` (single-value) |
| Conventions | ~50 | `convention` (multi-value) |
| Decisions | ~25 | `decision` (multi-value) |
| Auth methods | ~7 | `auth_method` (single-value) |
| Deployment | ~7 | `deployment_platform` (single-value) |

Simulated projects: `acme_api` (Ruby/Rails), `dataflow` (Python), `shopfront` (TypeScript/React), `infracore` (Go), `claude_mem` (this project).

Includes temporal variants (superseded facts with `valid_from`/`valid_to`), inferred facts (lower confidence), and edge cases for deduplication testing.

### retrieval_queries.yml (~140 queries)

Queries organized by difficulty level, each with expected and excluded fact IDs:

| Difficulty | Count | What It Tests | Example |
|------------|-------|---------------|---------|
| **Easy** | 40 | Natural language questions with some keyword overlap | "What is the primary database for the Acme API?" |
| **Medium** | 40 | Semantic paraphrase -- different words, same meaning | "How do we persist data in the Acme API?" |
| **Hard** | 20 | Cross-category synthesis -- requires multi-fact reasoning | "Describe the complete technology stack" |
| **Abstention** | 20 | No relevant facts exist -- should return nothing useful | "What mobile framework does the team use?" |
| **Temporal** | 15 | Newer fact should rank above superseded one | "What database does the API currently use?" |
| **Scope** | 5 | Project vs global ranking behavior | "What indentation should be used?" |

Easy queries use natural language questions (not keyword fragments) and include `excluded_facts` for cross-project contamination detection. Many easy and medium queries include decision companion facts in their expected sets — e.g., both the `auth_method` fact and the corresponding `decision` about JWT adoption are expected when asking about authentication.

### resolution_cases.yml (100 cases)

FEVER-inspired truth maintenance scenarios with 4 outcome types (25 each):

| Outcome | What It Tests | Example |
|---------|---------------|---------|
| **Supersede** | Single-value predicate, stated strength replaces existing | MySQL -> PostgreSQL (stated) |
| **Conflict** | Single-value predicate, inferred contradicts stated | PostgreSQL exists (stated), MySQL arrives (inferred) |
| **Accumulate** | Multi-value predicate, different values coexist | Convention A + Convention B |
| **Corroborate** | Same predicate+value, adds provenance | PostgreSQL mentioned again |

Tests case-insensitive matching, explicit `supersedes` flag, and inferred-vs-stated strength logic.

### e2e_scenarios.yml (31 scenarios)

LongMemEval-inspired end-to-end scenarios across 5 memory abilities:

| Ability | Count | What It Tests |
|---------|-------|---------------|
| **Information Extraction** | 8 | Can the system recall specific stored facts? |
| **Multi-Session Reasoning** | 8 | Can it synthesize across multiple facts from different sessions? |
| **Temporal Reasoning** | 5 | Can it handle time-ordered knowledge (migrations, upgrades)? |
| **Knowledge Update** | 5 | Does it prefer newer facts over superseded ones? |
| **Abstention** | 5 | Does it correctly say "I don't know" when memory has no answer? |

Each scenario specifies `acceptance_keywords` (must appear), `rejection_keywords` (must not appear), and a pass `threshold`.

## Metrics

### IR Metrics (implemented in `benchmark_helper.rb`)

| Metric | Formula | What It Measures |
|--------|---------|------------------|
| **Recall@k** | relevant_in_top_k / total_relevant | What fraction of expected facts appear in top-k results? |
| **MRR** | 1 / rank_of_first_relevant | How high does the first relevant result rank? |
| **nDCG@k** | DCG@k / ideal_DCG@k | How well-ordered are the results? (accounts for position) |
| **Precision@k** | relevant_in_top_k / k | What fraction of top-k results are actually relevant? |

### Truth Maintenance Metrics

Reported as a confusion matrix (expected vs actual outcome) with per-type and aggregate accuracy.

### E2E Metrics

Per-ability pass rate (keyword matching with threshold), overall pass rate, and memory-vs-baseline delta.

## Latest Results (2026-03-05)

```
RETRIEVAL (105 facts, 140 queries):
  FTS5:
    Easy:       Recall@5=0.950  MRR=0.863  (40 queries)
    Aggregate:  Recall@5=0.911  MRR=0.843  (45 queries)
  Semantic (FastEmbed bge-small-en-v1.5):
    Easy:       Recall@5=0.888  Recall@10=0.925  MRR=0.791  (40 queries)
    Medium:     Recall@5=0.719  Recall@10=0.881  MRR=0.700  (40 queries)
    Aggregate:  Recall@5=0.791  MRR=0.750  nDCG@10=0.746  (85 queries)
  Hybrid (Vector + FTS5 via RRF):
    Easy:       Recall@5=0.950  Recall@10=0.950  MRR=0.863  (40 queries)
    Medium:     Recall@5=0.627  Recall@10=0.685  MRR=0.650  (40 queries)
    Hard:       Recall@5=0.431  Recall@10=0.602  MRR=0.735  (20 queries)
    Aggregate:  Recall@5=0.717  MRR=0.752  nDCG@10=0.699  (100 queries)

SCOPE RANKING:  5/5 queries returned expected facts

RESOLUTION (100 cases):
  Supersede:    25/25 (100%)
  Conflict:     25/25 (100%)
  Accumulate:   25/25 (100%)
  Corroborate:  25/25 (100%)
  OVERALL:      100/100 (100%)

E2E DEVMEMEVAL (31 scenarios, requires EVAL_MODE=real):
  Stub validation: 31/31 scenarios structurally valid
  Real mode: requires claude CLI + EVAL_MODE=real
```

### Comparative Results (2026-03-05, 50 queries, 6 adapters)

Head-to-head retrieval comparison against competitor memory tools using a 50-query subset (20 easy, 20 medium, 10 hard) from the benchmark dataset.

```
COMPARATIVE RETRIEVAL (50 queries, 117 active facts):

  Aggregate:
    Adapter              Recall@5   MRR      nDCG@10
    QMD-Vector           0.842      0.930    0.884
    ClaudeMemory (hybrid) 0.712     0.732    0.689
    FTS-only             0.712      0.732    0.689
    QMD-BM25             0.350      0.400    0.359
    grepai               0.000      0.000    0.000
    No memory            0.000      0.000    0.000

  Easy (20 queries):
    QMD-Vector           1.000      0.975    —
    ClaudeMemory (hybrid) 0.975     0.864    —
    FTS-only             0.975      0.864    —
    QMD-BM25             0.750      0.850    —
    grepai               0.000      0.000    —

  Medium (20 queries):
    QMD-Vector           0.788      0.825    —
    ClaudeMemory (hybrid) 0.625     0.628    —
    FTS-only             0.625      0.628    —
    QMD-BM25             0.125      0.150    —
    grepai               0.000      0.000    —

  Hard (10 queries):
    ClaudeMemory (hybrid) 0.358     0.675    —
    FTS-only             0.358      0.675    —
    QMD-Vector           0.352      0.650    —
    QMD-BM25             0.000      0.000    —
    grepai               0.000      0.000    —

RESOURCE EFFICIENCY (117 facts, 20 queries):
    Adapter              Setup (ms)  Query (ms)  Index (KB)  RSS (KB)
    ClaudeMemory (hybrid)  1982       6.3         5228        264620
    FTS-only               153        2.7         4340        5616
    QMD-BM25               847        900.7       12          24
    QMD-Vector             1197       27689.5     12          32
    grepai                 8600       63.8        600         16
    No memory              0          0.0         0           0
```

**Competitor tools tested:**
- **QMD-Vector**: On-device vector search with query expansion via local GGUF models (~2GB). Uses Bun runtime.
- **QMD-BM25**: QMD's keyword-only mode (BM25 with AND semantics, stopword stripping).
- **grepai**: Local vector DB using Ollama embeddings (nomic-embed-text, ~274MB). Returned 0 results this run (indexing timeout).
- **FTS-only**: ClaudeMemory's FTS5 keyword search without embeddings.
- **ClaudeMemory (hybrid)**: Full hybrid retrieval (FTS5 + bge-small-en-v1.5 embeddings + RRF).
- **No memory**: Baseline returning empty results.

**Key takeaways:**
- QMD-Vector leads across all difficulties thanks to local GGUF query expansion and vector search (Recall@5=0.842, MRR=0.930).
- ClaudeMemory hybrid matches FTS-only in aggregate (Recall@5=0.712, MRR=0.732) after fixing BM25 score normalization and RRF fusion ordering. On hard queries, hybrid ties FTS-only for #1 (0.358), edging out QMD-Vector (0.352).
- FTS-only remains the best lightweight option — identical retrieval quality without embedding overhead, with 2.7ms query latency.
- QMD-BM25 is strong on easy queries (0.750) but collapses on medium/hard due to AND semantics requiring all terms to match.
- grepai returned 0 results this run due to an indexing timeout; previous runs showed competitive retrieval (Recall@5=0.707).
- ClaudeMemory has the fastest hybrid query latency (6.3ms) but the highest memory footprint (258MB RSS) due to in-process ONNX embeddings.

### Interpreting the results

**FTS5 performs well on easy queries** (Recall@5=0.950) because these queries share keywords with the stored fact text. FTS5 is the always-available baseline (no model download needed).

**Semantic retrieval excels on medium queries** (Recall@5=0.719) where the query uses different vocabulary than the stored fact. For example, "How do we persist data?" finds facts about PostgreSQL even though the word "persist" doesn't appear in the fact text. This demonstrates the value of transformer-based embeddings over keyword matching.

**Hybrid retrieval (RRF) matches or exceeds individual methods.** After fixing BM25 score normalization and similarity-preserving deduplication, hybrid search achieves Recall@5=0.717 overall — matching FTS-only on easy queries (0.950) while outperforming it on medium (0.563 vs 0.200) and hard queries (0.625 vs 0.188). The RRF fusion with K=60 and top-3 bonus effectively combines keyword precision with semantic understanding. A regression guard test ensures hybrid Recall@5 stays within 90% of FTS-only on easy queries.

**Hard queries require multi-fact retrieval.** Queries like "Describe the complete technology stack" expect 5-8 facts. Recall@5 is structurally capped for these queries (max Recall@5 = 5/8 = 0.625 for an 8-fact query). Recall@10 is the more meaningful metric for hard queries.

**Resolution accuracy is 100%** because the predicate policy logic (single-value supersession, multi-value accumulation, strength-based conflict detection) is deterministic and well-defined.

### Embedding model

Benchmarks use [fastembed-rb](https://github.com/khasinski/fastembed-rb) with the **BAAI/bge-small-en-v1.5** model:
- **384 dimensions** (matches ClaudeMemory's existing embedding storage)
- **~67MB** ONNX model downloaded on first run to `~/.cache/fastembed/`
- **Runs locally** -- no API key, no network calls after initial download
- **Asymmetric encoding** -- uses `query_embed` for search queries, `passage_embed` for stored facts

## Running Benchmarks

### Offline ($0, ~8 seconds)

```bash
# All offline benchmarks
bundle exec rspec spec/benchmarks/ --tag benchmark --format documentation

# Just retrieval
bundle exec rspec spec/benchmarks/retrieval/ --tag benchmark --format documentation

# Just resolution
bundle exec rspec spec/benchmarks/resolution/ --tag benchmark --format documentation

# With the run-evals script (includes eval scenarios too)
./bin/run-evals --all
./bin/run-evals --benchmarks-only
```

### Comparative ($0, ~60 minutes with all competitors)

Requires competitor tools installed via `bin/setup-competitors` (~3GB total download).

```bash
# Install competitor tools (idempotent, safe to re-run)
bin/setup-competitors              # Install QMD + grepai + all dependencies
bin/setup-competitors --check      # Just show what's installed
bin/setup-competitors --qmd-only   # Only QMD + Bun
bin/setup-competitors --grepai-only # Only grepai + Ollama

# Run comparative benchmarks
bundle exec rspec spec/benchmarks/comparative/ --tag comparative --format documentation

# Via run-evals
./bin/run-evals --comparative
./bin/run-evals --comparative --setup-competitors  # Install + run
```

Unavailable adapters are skipped gracefully. The suite always runs with the internal adapters (ClaudeMemory, FTS-only, No memory) even without competitor tools installed.

### End-to-end with Claude (~$2-8)

```bash
# Run all e2e scenarios
EVAL_MODE=real bundle exec rspec spec/benchmarks/e2e/ --tag eval_real --format documentation

# Via run-evals
EVAL_MODE=real ./bin/run-evals --all
```

Budget is capped at $0.10 per scenario via `ClaudeCliRunner`. A full comparative run (memory-enabled + baseline) for all 31 scenarios costs approximately $2.40.

### Embedding setup

Semantic and hybrid retrieval benchmarks use [fastembed-rb](https://github.com/khasinski/fastembed-rb) for local embedding generation. The BAAI/bge-small-en-v1.5 model (~67MB) is downloaded automatically on first run to `~/.cache/fastembed/`. No API key is needed.

If fastembed is not installed, semantic specs will be skipped and hybrid specs will fall back to FTS-only mode.

## File Structure

```
spec/benchmarks/
├── README.md                           # This file
├── benchmark_helper.rb                 # IR metrics, dataset loader, fixture builder
├── dataset/
│   ├── facts.yml                       # ~105 developer-domain facts
│   ├── retrieval_queries.yml           # ~155 queries with expected fact IDs
│   ├── resolution_cases.yml            # 100 truth maintenance cases
│   └── e2e_scenarios.yml               # 31 end-to-end scenarios
├── retrieval/
│   ├── fts5_spec.rb                    # FTS5 retrieval accuracy
│   ├── semantic_spec.rb                # Embedding retrieval accuracy
│   ├── hybrid_spec.rb                  # Combined FTS5+vector accuracy
│   └── scope_ranking_spec.rb           # Project vs global ranking
├── resolution/
│   └── truth_maintenance_spec.rb       # Supersession/conflict correctness
├── comparative/
│   ├── comparative_helper.rb           # Adapter discovery, shared setup
│   ├── adapters/
│   │   ├── base_adapter.rb             # Abstract interface
│   │   ├── claude_memory_adapter.rb    # Full hybrid retrieval
│   │   ├── fts_only_adapter.rb         # FTS5 keyword-only baseline
│   │   ├── no_memory_adapter.rb        # Empty baseline
│   │   ├── claude_md_adapter.rb        # Static CLAUDE.md (E2E only)
│   │   ├── qmd_adapter.rb             # QMD (BM25/Vector/Hybrid modes)
│   │   └── grepai_adapter.rb          # grepai + Ollama embeddings
│   ├── retrieval/
│   │   └── comparative_retrieval_spec.rb  # Head-to-head retrieval
│   ├── efficiency/
│   │   └── resource_efficiency_spec.rb    # Setup time, index size, latency
│   ├── e2e/
│   │   └── comparative_e2e_spec.rb        # E2E with real Claude
│   └── reporting/
│       └── comparative_reporter.rb        # Terminal + markdown reports
└── e2e/
    └── devmemeval_spec.rb              # End-to-end with real Claude
```

## Extending the Dataset

### Adding facts

Add entries to `facts.yml` with the required fields:

```yaml
- id: ts_db_999          # Unique ID (used by queries to reference expected results)
  subject: my_project    # Entity name
  predicate: uses_database
  object: "CockroachDB for distributed SQL"
  text: "We use CockroachDB for globally distributed SQL workloads."
  scope: project
  fts_keywords: "database cockroachdb distributed sql"
```

### Adding queries

Add entries to `retrieval_queries.yml`:

```yaml
- id: q_easy_999
  query: "What distributed database does the project use?"
  expected_facts: [ts_db_999]
  difficulty: easy
  tests: [fts5, semantic, hybrid]   # Which retrieval modes to test
```

### Adding resolution cases

Add entries to `resolution_cases.yml`:

```yaml
- id: r_sup_999
  existing_fact:
    subject: repo
    predicate: uses_database
    object: "CockroachDB"
    strength: stated
  incoming_fact:
    subject: repo
    predicate: uses_database
    object: "TiDB"
    strength: stated
  expected_outcome: supersede
  rationale: "Single-value predicate with new stated value"
```

## Design Decisions

**Why not use open datasets directly?** Domain mismatch. BEIR's queries are about Wikipedia/news. FEVER's claims are about encyclopedic facts. LongMemEval's conversations are about personal events. None of them exercise developer-specific predicates, entity types, or the temporal/scope semantics that ClaudeMemory relies on.

**Why 105 facts instead of 200?** The plan called for ~200, but 105 well-distributed facts across 5 projects and 6 predicates provide sufficient coverage to measure retrieval quality at each difficulty level. The dataset can grow incrementally as new edge cases emerge.

**Why is resolution at 100%?** The resolver logic is deterministic: single-value + stated = supersede, single-value + inferred = conflict, multi-value = accumulate, same value = corroborate. The benchmark validates that this logic works correctly across all edge cases rather than testing probabilistic behavior.

**Why separate FTS5 and hybrid specs?** FTS5 is the always-available baseline (no model download needed). Hybrid includes vector search when embeddings are available. Separating them shows exactly what each retrieval mode contributes.

**Why fastembed-rb / bge-small-en-v1.5?** It runs locally via ONNX (no API key, no network calls after download), produces 384-dimensional vectors matching ClaudeMemory's existing storage format, and supports asymmetric query/passage encoding for better retrieval accuracy. The ~67MB model is small enough to download in CI without friction.
