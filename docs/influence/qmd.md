# QMD Analysis (Updated)

*Analysis Date: 2026-03-02*
*Previous Analysis: 2026-02-02*
*Repository: https://github.com/tobi/qmd*
*Version: 1.1.0 (commit 40610c3)*

---

## Executive Summary

### Project Purpose

QMD (Query Markup Documents) is an **on-device search engine** for markdown knowledge bases. It combines BM25 full-text search, vector semantic search, and LLM re-ranking — all running locally via node-llama-cpp with GGUF models.

### Key Innovation (What's New Since Last Study)

1. **Query Document Format** (`docs/SYNTAX.md`): Structured multi-line queries with typed sub-queries (`lex:`, `vec:`, `hyde:`) that route to different search backends. First sub-query gets 2x weight in Reciprocal Rank Fusion. This replaces the separate `search`/`vsearch`/`query` commands with a unified `query` tool.

2. **Lex Query Syntax**: Full BM25 operator support — `"exact phrase"` matching, `-term` exclusions, `-"phrase"` exclusions. Enables intent-aware disambiguation (e.g., `performance -sports -athlete`).

3. **HTTP MCP Transport** (`src/mcp.ts:10-16`): Stateless HTTP server alongside stdio. Models stay loaded in VRAM across requests. Embedding/reranking contexts disposed after 5 min idle.

4. **Unified MCP `query` tool**: Removed separate `search`, `vector_search`, `deep_search` tools. Single `query` tool handles all modes via the query document format.

5. **Collection Management Enhancements**: `include`/`exclude` collections from default queries, `update-cmd` for pre-update shell commands, multiple `-c` flags.

### Technology Stack

- **Runtime**: Node.js >= 22 / Bun (dual runtime, `src/db.ts:9-24`)
- **Database**: SQLite with better-sqlite3 + sqlite-vec extension v0.1.7-alpha.2
- **Full-Text Search**: SQLite FTS5 with Porter tokenization
- **Embeddings**: EmbeddingGemma (~300MB GGUF)
- **Reranking**: Qwen3-Reranker-0.6B (~640MB GGUF)
- **Query Expansion**: Qwen3-1.7B (custom fine-tuned, ~1.1GB)
- **MCP**: @modelcontextprotocol/sdk v1.25.1
- **Validation**: Zod v4
- **Plugin**: Claude Code marketplace format

### Production Readiness

- **Maturity**: Stable (v1.1.0), 5,700+ GitHub stars
- **Test Coverage**: vitest suite (store, mcp, collections, formatter, cli, eval)
- **Plugin Distribution**: Claude Code marketplace
- **Community**: Active (256 PRs merged, external contributors)

---

## Architecture Overview

### Data Model

```
content table (SHA256 hash → document body, deduplication)
    ↓
documents table (collection, path, title → hash, soft-delete via active flag)
    ↓
documents_fts (FTS5 full-text index, auto-synced via triggers)
    ↓
content_vectors (chunk metadata: hash, seq, pos, model)
    ↓
vectors_vec (sqlite-vec native KNN index, cosine distance)
    ↓
llm_cache (hash-keyed deterministic response cache)
```

### Key Design Patterns (New)

1. **Query Document Format** (`docs/SYNTAX.md:1-100`): EBNF grammar for structured queries. Lines typed as `lex:`, `vec:`, or `hyde:` route to different backends. Plain text defaults to `expand:` (LLM-generated variants).

2. **Two-Step Vector Query** (`store.ts:1912-1915`): JOINs with sqlite-vec virtual tables hang indefinitely. QMD uses separate queries:
   ```typescript
   // Step 1: KNN from vec table
   const vecResults = db.prepare(
     `SELECT hash_seq, distance FROM vectors_vec WHERE embedding MATCH ? AND k = ?`
   ).all(embedding, limit * 3);
   // Step 2: Join with documents separately
   ```

3. **Smart Chunking** (`store.ts:53-219`): 900 tokens/chunk, 15% overlap, markdown-aware break points with scored pattern matching (h1=100, h2=90, paragraph=20). Distance decay prevents splitting inside code fences.

4. **Dynamic MCP Instructions** (`mcp.ts:91-98`): `buildInstructions()` generates context-aware server instructions from actual index state, injected into LLM system prompt.

5. **Dual Runtime Compatibility** (`db.ts:9-24`): Cross-runtime SQLite layer that works under both Bun (bun:sqlite) and Node.js (better-sqlite3).

### Comparison with ClaudeMemory

| Aspect | QMD (1.1.0) | ClaudeMemory | Notes |
|--------|-------------|--------------|-------|
| **Data Model** | Content-addressable chunks | Subject-predicate-object facts | QMD stores documents; we store knowledge |
| **Storage** | SQLite + sqlite-vec | SQLite + Sequel + fastembed-rb | Both use FTS5 |
| **Vector Search** | sqlite-vec (native C) | JSON embeddings (Ruby) | QMD 10-100x faster |
| **Query Language** | Typed sub-queries (lex/vec/hyde) | Free-text search | QMD more expressive |
| **Chunking** | Smart (900 tok, markdown-aware) | None (fact-level) | Different granularity |
| **Plugin Format** | marketplace.json | Ruby gem + MCP + hooks | QMD easier to install |
| **MCP Transport** | stdio + HTTP | stdio only | HTTP enables shared server |

---

## Key Components Deep-Dive

### Component 1: Query Document Parser

**Purpose**: Parse structured multi-line queries into typed sub-queries for routing to appropriate search backends.

**Location**: `docs/SYNTAX.md`, `src/store.ts`

**Design Decisions**:
- Typed lines (`lex:`, `vec:`, `hyde:`) enable precise control over search routing
- First sub-query gets 2x weight in RRF fusion
- Plain text auto-expands via LLM to generate all three types
- Lex supports phrase matching and negation for disambiguation

### Component 2: HTTP MCP Transport

**Purpose**: Long-lived MCP server that avoids repeated model loading.

**Location**: `src/mcp.ts:119-137`

**Design Decisions**:
- WebStandardStreamableHTTPServerTransport for stateless HTTP
- Models stay loaded in VRAM across requests
- Idle disposal after 5 min (transparent recreation ~1s)
- Health endpoint for liveness checks
- Daemon mode with PID file management

### Component 3: Smart Chunking

**Purpose**: Split documents at natural boundaries for better embeddings.

**Location**: `src/store.ts:68-219`

**Design Decisions**:
- Scored break points (h1=100 → newline=1) with distance decay
- Code fence detection prevents splitting mid-block
- 200-token search window for finding optimal cut points
- Squared distance decay for gentle early, steep late penalties

---

## Comparative Analysis

### What They Do Well

1. **Native Vector Queries**: sqlite-vec provides sub-millisecond KNN with C-level performance
2. **Typed Query Language**: Explicit control over search routing reduces ambiguity
3. **Smart Chunking**: Markdown-aware splitting produces better embeddings
4. **HTTP MCP Transport**: Shared server avoids repeated model loading
5. **Dynamic Instructions**: Index-aware MCP instructions give LLM immediate context

### What We Do Well

1. **Knowledge Representation**: Facts with provenance > raw document chunks
2. **Truth Maintenance**: Supersession and conflict resolution
3. **Dual-Database System**: Project/global scope separation
4. **Distillation Pipeline**: Extract structured knowledge from transcripts
5. **Temporal Validity**: Facts have valid_from/valid_to windows

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Native Vector Storage (sqlite-vec)
- **Value**: 10-100x faster KNN queries, eliminates O(n) Ruby similarity
- **Evidence**: `db.ts:52-54` — single function call to load extension
- **Implementation**: Add sqlite-vec gem, create `facts_vec` virtual table, two-step query pattern
- **Effort**: 3-5 days
- **Trade-off**: Native dependency (but well-maintained, cross-platform)
- **Recommendation**: **ADOPT** — Critical for scaling beyond 1000 facts

#### 2. Smart Chunking for Long Content
- **Value**: Better embeddings for transcripts > 3000 chars
- **Evidence**: `store.ts:53-219` — scored break points, code fence awareness
- **Implementation**: Port chunking algorithm to Ruby for transcript ingestion
- **Effort**: 2-3 days
- **Trade-off**: Complexity; only needed for long content
- **Recommendation**: **CONSIDER** — Adopt if users report long transcript issues

#### 3. HTTP MCP Transport
- **Value**: Shared server, models stay loaded, faster subsequent queries
- **Evidence**: `mcp.ts:119-137` — WebStandardStreamableHTTPServerTransport
- **Implementation**: Add HTTP transport option alongside stdio
- **Effort**: 2-3 days
- **Trade-off**: Process management complexity
- **Recommendation**: **CONSIDER** — Useful if MCP startup latency becomes an issue

### Medium Priority

#### 4. Dynamic MCP Server Instructions
- **Value**: Give LLM immediate context about database state without extra tool call
- **Evidence**: `mcp.ts:91-98` — builds instructions from actual index state
- **Implementation**: Generate instructions showing fact counts, recent decisions, active conflicts
- **Effort**: 1 day
- **Trade-off**: Minimal
- **Recommendation**: **ADOPT**

#### 5. Query Document Format
- **Value**: More expressive queries with explicit search routing
- **Evidence**: `docs/SYNTAX.md:1-100` — formal EBNF grammar
- **Implementation**: Support typed queries in recall (e.g., `lex: exact term` vs `vec: semantic query`)
- **Effort**: 3-5 days
- **Trade-off**: Complexity; current free-text may be sufficient
- **Recommendation**: **DEFER** — Over-engineering for fact retrieval

### Features to Avoid

- **Custom Fine-Tuned Query Expansion (Qwen3-1.7B)**: Too heavy for fact retrieval
- **EmbeddingGemma**: We use fastembed-rb (BAAI/bge-small-en-v1.5) which is lighter
- **Content-Addressable Storage**: Our facts are deduplicated by signature, not content hash
- **LLM Reranking**: Cross-encoder reranking is over-engineering for our use case

---

## Architecture Decisions

### What to Preserve
- **Fact-based knowledge model**: More valuable than raw document chunks
- **Dual-database system**: Clean project/global separation
- **Ruby + Sequel**: Mature, stable, well-tested

### What to Adopt
- **sqlite-vec**: Critical for vector query performance
- **Two-step vector query pattern**: Avoid JOIN hangs
- **Dynamic MCP instructions**: Free context for LLMs

### What to Reject
- **YAML collection system**: Our dual-database is cleaner
- **Custom fine-tuned models**: Too heavy for our use case
- **Query document format**: Over-engineering for fact retrieval

---

## Key Takeaways

### Main Learnings
1. sqlite-vec is production-ready (v0.1.7-alpha.2) and used by multiple projects
2. Two-step query pattern is mandatory (JOINs hang with vec tables)
3. Query document format is elegant but over-engineering for fact retrieval
4. HTTP MCP transport enables shared server mode

### Changes Since Last Analysis (2026-02-02)
- v1.1.0 released with query document format
- Lex syntax with phrase matching and negation
- Unified `query` MCP tool replacing 3 separate tools
- HTTP MCP transport with daemon mode
- Dual Node.js/Bun runtime support
- Collection include/exclude management

---

*Analysis completed: 2026-03-02*
*Analyst: Claude Code*
*Review Status: Draft*
