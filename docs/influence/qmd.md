# QMD Analysis (Updated)

*Analysis Date: 2026-03-10*
*Previous Analysis: 2026-03-02, 2026-02-02*
*Repository: https://github.com/tobi/qmd*
*Version: 2.0.1 (commit ae3604c)*
*Re-studied: 2026-03-30 — v2.0.1+unreleased. One significant addition: AST-aware chunking (`src/ast.ts`, 392 lines) using web-tree-sitter with WASM grammars for TS/JS/Python/Go/Rust. Detects language from extension, parses AST, extracts break points at function/class/import boundaries (class=100, func=90, type=80, import=60). Merged with regex break points via `mergeBreakPoints()`. Opt-in via `--chunk-strategy auto`. While we ingest transcripts rather than source code, transcripts frequently contain embedded code in tool results and assistant responses. AST-aware break points could improve embedding quality for code-heavy transcripts when combined with Document Chunking (#22). Added as improvement #28 (Code-Aware Transcript Chunking).*

*Re-studied: 2026-06-30 — v2.6.3 (commit e428df7, 2026-06-24). Baseline was v2.0.1; intervening releases: v2.1.0, v2.5.0–v2.5.3, v2.6.x. The 2.5.x/2.6.x line is dominated by GGUF/llama.cpp/Metal/CUDA/Bun-launcher fixes that don't apply to our pure-Ruby/SQLite/fastembed stack — but four retrieval/concurrency refinements ported cleanly to us. AST chunking (#28) shipped as default in 2.1.0; `qmd bench` (precision@k/recall/MRR/F1, 2.1.0) is something DevMemBench already exceeds (we have Recall@k/MRR/nDCG@10). NEW adoptable patterns this round:*

*1. **`PRAGMA busy_timeout` on every connection** ⭐ HIGH — `src/db.ts:117-120` reads `QMD_SQLITE_BUSY_TIMEOUT` (default 120000ms) and runs `PRAGMA busy_timeout = <ms>` on every `openDatabase`. Rationale (CHANGELOG 2.6.3, #673-adjacent + the long concurrent-open writeup): `bun:sqlite`/`better-sqlite3` default the timeout to 0, so a writer losing a race throws `database is locked` immediately rather than queueing. This is a near-exact match for our documented gotcha [[gotcha_cli_writes_under_hook_contention]] — looping `claude-memory reject` silently no-ops under hook DB-contention. We already use WAL (which serializes readers/writers but NOT concurrent writers), and our extralite connections likewise default busy_timeout to 0. Adopting a per-connection `PRAGMA busy_timeout` (set in `SQLiteStore`'s connection setup) would make hook-vs-CLI write races queue at statement boundaries instead of no-opping. Two corollary fixes worth noting: qmd gates FTS-trigger (re)creation behind `PRAGMA user_version` inside one `BEGIN IMMEDIATE` transaction (`src/store.ts:797-845`) because `busy_timeout` serializes single statements but not a DROP+CREATE pair two processes interleave through; and the cold-DB `journal_mode=WAL` switch needs a brief exclusive lock that does NOT invoke the busy handler, so it's retried within the timeout budget (`src/db.ts:80-87`). Effort: ~0.5 day. Recommendation: **ADOPT** — directly fixes a known production gotcha, no new deps.*

*2. **Position-aware RRF weights — boost original-query evidence 2x** ⭐ HIGH — `getHybridRrfWeights()` (`src/store.ts:4715`) returns weight `2.0` for lists whose `queryType === "original"` (original FTS + original vector) and `1.0` for expansion-derived lex/vec/hyde lists, regardless of list insertion order. This fixed #591, where "weight RRF lists by query type" stopped an early lex-expansion from accidentally stealing the boost meant for original vector evidence. We already adopted RRF; this is a one-line refinement: when fusing original-query and expanded-query result lists, weight the original lists higher so query-expansion variants can re-rank but not dominate. The fusion core (`src/store.ts:3984-4024`) is the canonical `weight / (k + rank + 1)` accumulation with small same-doc co-occurrence bonuses (+0.05/+0.02). Effort: ~0.5 day if our hybrid path already separates original vs. expanded lists. Recommendation: **ADOPT** — cheap precision win for hybrid recall.*

*3. **FTS5 dotted-version + hyphen + underscore tokenization** ⭐ MEDIUM-HIGH — `src/store.ts:3367-3406`. The `porter unicode61` tokenizer splits on dots, so a sanitizer that strips dots turns `2026.4.10` into `2026410` which never matches (#563). qmd detects dotted tokens (`isDottedToken`, ≥2 non-empty alnum parts) and rewrites them as `"2026"* AND "4"* AND "10"*`; hyphenated tokens (`isHyphenatedToken`, e.g. `multi-agent`, `DEC-0054`, `gpt-4`) become phrase `"multi agent"`; and `sanitizeFTS5Term` preserves underscores/apostrophes (`[^\p{L}\p{N}'_]` strip class). This is directly relevant — our facts are full of version strings (`0.13.2`, `v2.6.3`, schema `v19`), hyphenated identifiers, and snake_case symbols, and our FTS query builder should round-trip them. Worth auditing `LexicalFTS`'s query sanitization against these three cases. Effort: ~1 day incl. tests. Recommendation: **ADOPT** (audit first — we may already handle some via Porter).*

*4. **Embedding fingerprint = model + chunking/formatting params (not just dimensions)** — MEDIUM — CHANGELOG 2.5.0: qmd fingerprints `content_vectors` by the active embedding model AND formatting/chunking parameters, so vectors become "pending" after search semantics change (not only on dimension mismatch); legacy columns migrate lazily on first vector-health/write. `qmd doctor` reports embedding-fingerprint freshness + mixed-fingerprint detection (multiple non-empty fingerprint names = a corrupted/mixed index). Our `Embeddings::DimensionCheck` only compares dimensions — switching between two providers that share a dimension count (or changing chunking) would silently leave stale vectors. A fingerprint string (provider name + key params) stored alongside vectors, surfaced in `claude-memory doctor`/`audit`, would catch provider/param drift our DimensionCheck misses. Effort: 1-2 days. Recommendation: **CONSIDER** — strengthens an existing check; lower urgency since we have fewer provider permutations.*

*Still rejected (unchanged): custom fine-tuned Qwen3 query expansion, GGUF embed/rerank models, LLM cross-encoder reranking, GPU/Metal/CUDA probing, Bun/Node dual-launcher machinery, OSC-8 editor hyperlinks (our harness already makes file:line clickable), multi-session HTTP transport. Bottom line: v2.6.3 is mostly platform/runtime hardening irrelevant to us, but the per-connection `busy_timeout` and original-query RRF boost are both small, high-value ports.*

---

## Executive Summary

### Project Purpose

QMD (Query Markup Documents) is an **on-device search engine** for markdown knowledge bases. It combines BM25 full-text search, vector semantic search, and LLM re-ranking — all running locally via node-llama-cpp with GGUF models.

### Key Innovation (What's New Since v1.1.5 Study)

1. **Stable SDK API** (`src/index.ts:1-524`): QMD 2.0 declares a stable library API via `createStore()` returning a `QMDStore` interface. Clean separation between SDK (public), CLI (consumer), and MCP (consumer). The SDK owns all search, retrieval, collection management, context management, indexing, and lifecycle operations.

2. **Unified `search()` Method** (`src/index.ts:145-164`): Replaces the old `query()`/`search()`/`structuredSearch()` split. Accepts either a simple `query` string (auto-expanded) or pre-expanded `queries` array. Clean polymorphic design.

3. **MCP Server as SDK Consumer** (`src/mcp/server.ts:1-808`): MCP server completely rewritten to consume the SDK — zero internal store access. Uses `QMDStore` interface exclusively. Multi-session HTTP transport with session map.

4. **Self-Contained Database** (`src/store.ts:699-767`): New `store_collections` and `store_config` SQLite tables make the DB self-contained. No external YAML config needed — SDK creates stores with inline config or DB-only mode.

5. **Maintenance Class** (`src/maintenance.ts:1-54`): Dedicated maintenance wrapper for cleanup operations — vacuum, orphaned content/vectors cleanup, LLM cache clearing, inactive doc deletion, embedding reset.

6. **Embedded Skills** (`src/embedded-skills.ts`): Skill definitions (SKILL.md + references) embedded as base64 in source. `qmd skill install` copies packaged skill to `~/.claude/commands/`.

7. **REST API** (`src/mcp/server.ts:626-675`): POST `/query` (alias `/search`) endpoint alongside MCP — structured search without MCP protocol overhead.

### Technology Stack

- **Runtime**: Node.js >= 22 / Bun (dual runtime, `src/db.ts:9-24`)
- **Database**: SQLite with better-sqlite3 ^12.4.5 + sqlite-vec v0.1.7-alpha.2
- **Full-Text Search**: SQLite FTS5 with Porter tokenization
- **Embeddings**: Qwen3-Embedding (configurable via `QMD_EMBED_MODEL`)
- **Reranking**: Qwen3-Reranker-0.6B (~640MB GGUF)
- **Query Expansion**: Qwen3-1.7B (custom fine-tuned, ~1.1GB)
- **MCP**: @modelcontextprotocol/sdk v1.25.1
- **Validation**: Zod v4.2.1
- **Plugin**: Claude Code marketplace format + embedded skills

### Production Readiness

- **Maturity**: Stable (v2.0.1), 5,700+ GitHub stars
- **Test Coverage**: vitest suite with 1,286-line SDK test (store, mcp, collections, formatter, cli, sdk, eval)
- **Plugin Distribution**: Claude Code marketplace + `qmd skill install`
- **Community**: Active (362+ PRs, external contributors)

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
    ↓
store_collections (self-contained collection config in DB)  [NEW in v2.0]
    ↓
store_config (key-value metadata, e.g. config_hash)  [NEW in v2.0]
```

### Key Design Patterns

1. **SDK-First Architecture** (`src/index.ts`): Public `QMDStore` interface is the contract. CLI and MCP are consumers, not peers. Internal store exposed via `.internal` for advanced use only.

2. **Per-Store LLM Instance** (`src/index.ts:361-364`): Each SDK store creates its own `LlamaCpp` instance with lazy loading and 5-min inactivity timeout. No global singletons — enables concurrent stores.

3. **Write-Through Config** (`src/index.ts:417-465`): Collection/context mutations write to both SQLite and YAML/inline config if configured. DB is source of truth; YAML is optional persistence layer.

4. **Two-Step Vector Query** (`store.ts`): JOINs with sqlite-vec virtual tables hang. Separate KNN query then batch hydration.

5. **Smart Chunking** (`store.ts:53-219`): 900 tokens/chunk, 15% overlap, markdown-aware break points with scored pattern matching.

6. **Dynamic MCP Instructions** (`src/mcp/server.ts:92-152`): `buildInstructions()` generates context-aware instructions from actual index state including collection names, document counts, capability gaps, search examples, and retrieval workflow.

7. **MCP Resource Templates** (`src/mcp/server.ts:172-207`): Documents accessible via `qmd://{+path}` URI scheme. Resources return structured content with context annotations.

### Comparison with ClaudeMemory

| Aspect | QMD (2.0.1) | ClaudeMemory | Notes |
|--------|-------------|--------------|-------|
| **API** | SDK-first (`QMDStore` interface) | CLI-first + MCP tools | QMD more composable |
| **Data Model** | Content-addressable chunks | Subject-predicate-object facts | QMD stores documents; we store knowledge |
| **Storage** | SQLite + sqlite-vec | SQLite + Sequel + sqlite-vec | Both use FTS5 + vec0 |
| **Config** | Self-contained DB + optional YAML | Dual-database (global + project) | Different scoping models |
| **Query** | Typed sub-queries (lex/vec/hyde) | Free-text + hybrid search | QMD more expressive |
| **Maintenance** | Dedicated `Maintenance` class | `Sweep` module + compact command | Similar approach |
| **Plugin Format** | marketplace.json + embedded skills | Ruby gem + MCP + hooks | QMD adds skill install |
| **MCP Transport** | stdio + HTTP + REST | stdio only | QMD more flexible |
| **Tests** | 1,286-line SDK test suite | RSpec suite + evals + benchmarks | Both comprehensive |

---

## Key Components Deep-Dive

### Component 1: SDK API (`src/index.ts`)

**Purpose**: Stable programmatic interface for all QMD operations.

**Key Design Decisions**:
- `QMDStore` interface with 20+ methods across 6 categories (Search, Retrieval, Collections, Context, Indexing, Lifecycle)
- `createStore()` factory with three modes: YAML config, inline config, DB-only
- Per-store `LlamaCpp` with lazy loading and auto-disposal
- Write-through config pattern for collection mutations
- Re-exports types for SDK consumers

**Code Example** (`src/index.ts:331-524`):
```typescript
export async function createStore(options: StoreOptions): Promise<QMDStore> {
  const internal = createStoreInternal(options.dbPath);
  const llm = new LlamaCpp({
    inactivityTimeoutMs: 5 * 60 * 1000,
    disposeModelsOnInactivity: true,
  });
  internal.llm = llm;
  // ... builds QMDStore with all methods delegating to internal
}
```

### Component 2: MCP Server as SDK Consumer (`src/mcp/server.ts`)

**Purpose**: Expose QMD search via MCP protocol, consuming only the public SDK.

**Key Design Decisions**:
- Zero internal store access — uses `QMDStore` interface exclusively
- `createMcpServer()` shared by both stdio and HTTP transports
- Multi-session HTTP with session map (`Map<string, Transport>`)
- REST `/query` endpoint alongside MCP for non-MCP clients
- Rich `buildInstructions()` with collection stats, context, capability gaps, search examples

**Code Example** (`src/mcp/server.ts:158-166`):
```typescript
async function createMcpServer(store: QMDStore): Promise<McpServer> {
  const server = new McpServer(
    { name: "qmd", version: "0.9.9" },
    { instructions: await buildInstructions(store) },
  );
  // ... registers tools using only store.search(), store.get(), etc.
}
```

### Component 3: Self-Contained Database (`src/store.ts:699-767`)

**Purpose**: Make the database self-contained so SDK consumers don't need external config files.

**Key Design Decisions**:
- `store_collections` table replaces YAML as the primary config store
- `store_config` key-value table for metadata (e.g., `config_hash` for sync optimization)
- `syncConfigToDb()` function syncs external config into SQLite on store creation
- Collection accessor functions (`getStoreCollections`, `upsertStoreCollection`, etc.) replace direct YAML reads

### Component 4: Maintenance Class (`src/maintenance.ts`)

**Purpose**: Wrap low-level store cleanup operations for CLI housekeeping.

**Key Design Decisions**:
- Takes internal `Store` in constructor — allowed direct DB access
- 6 operations: vacuum, orphaned content, orphaned vectors, LLM cache, inactive docs, clear embeddings
- Each method returns count of affected rows for reporting
- Used by CLI's `clean` subcommands

---

## Comparative Analysis

### What They Do Well

1. **SDK-First Architecture**: Clean separation between API contract and consumers (CLI, MCP). Makes QMD embeddable in other tools.
2. **Self-Contained Database**: DB stores its own config — no external files needed to reopen a store.
3. **MCP as Pure Consumer**: MCP server has zero internal knowledge, proving the SDK is complete.
4. **REST API Alongside MCP**: POST `/query` for non-MCP clients (curl, scripts, other tools).
5. **Dynamic MCP Instructions**: Rich context about collections, doc counts, capability gaps — eliminates discovery calls.
6. **Embedded Skill Distribution**: `qmd skill install` copies skill files — no manual setup.
7. **Comprehensive SDK Tests**: 1,286-line test file covers constructor, search, collections, contexts, indexing, health.

### What We Do Well

1. **Knowledge Representation**: Facts with provenance > raw document chunks
2. **Truth Maintenance**: Supersession and conflict resolution
3. **Dual-Database System**: Project/global scope separation is cleaner than single-DB
4. **Distillation Pipeline**: Extract structured knowledge from transcripts
5. **Temporal Validity**: Facts have valid_from/valid_to windows
6. **Hook Integration**: Deep integration with Claude Code lifecycle events
7. **21 MCP Tools**: More granular tool surface than QMD's 4 tools

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Dedicated Maintenance Class ⭐
- **Value**: Clean separation of maintenance operations from main store. QMD's `Maintenance` class wraps 6 cleanup operations with return counts.
- **Evidence**: `src/maintenance.ts:1-54` — constructor takes internal store, each method returns affected count
- **Implementation**: Extract our `Sweep` module operations into a `Maintenance` class. Methods: `vacuum`, `cleanup_orphaned_content`, `cleanup_orphaned_vectors`, `cleanup_expired_facts`, `cleanup_superseded_facts`, `compact`. Return affected counts for reporting.
- **Effort**: 1 day
- **Trade-off**: Minor refactoring
- **Recommendation**: **ADOPT** — Our sweep is already similar, just needs cleaner wrapping

#### 2. Dynamic MCP Instructions Enhancement ⭐
- **Value**: QMD v2.0 builds rich instructions including collection stats, document counts, capability gaps, search examples, and retrieval workflow tips. Our MCP server has a static query guide prompt but no dynamic instructions.
- **Evidence**: `src/mcp/server.ts:92-152` — `buildInstructions()` with collections, counts, gaps, examples, tips
- **Implementation**: Add `buildInstructions()` to our MCP server that generates dynamic instructions with: fact counts (global/project), active conflict count, recent decision count, convention count, database health, and usage tips.
- **Effort**: 1 day
- **Trade-off**: Minimal — enhances existing MCP server instructions
- **Recommendation**: **ADOPT** — Free context for LLMs, eliminates need for `memory.status` call

#### 3. Embedded Skill Distribution ⭐
- **Value**: `qmd skill install` copies packaged skill files to `~/.claude/commands/` — zero-config setup. Skills are embedded as base64 in source code and extracted at install time.
- **Evidence**: `src/embedded-skills.ts:1-22` — base64-encoded SKILL.md + references; `src/cli/qmd.ts` — `skill install` command
- **Implementation**: Add `claude-memory install-skill` command that writes our memory recall agent (`agents/memory-recall.md`) to `~/.claude/commands/memory-recall.md`. Embed skill content in a Ruby constant.
- **Effort**: 1-2 days
- **Trade-off**: Adds a constant with skill content to codebase
- **Recommendation**: **ADOPT** — Pairs with Search Agent Delegation Pattern (#8 in improvements.md)

#### 4. REST API Endpoint ⭐
- **Value**: QMD v2.0 adds POST `/query` alongside MCP — enables search from curl, scripts, CI, and non-MCP clients without the full MCP protocol handshake.
- **Evidence**: `src/mcp/server.ts:626-675` — `/query` and `/search` endpoints with structured JSON request/response
- **Implementation**: Add optional HTTP server mode to `claude-memory serve-mcp --http` with POST `/recall` endpoint. Accept `{ query, scope, limit }`, return JSON facts.
- **Effort**: 2 days
- **Trade-off**: Requires WEBrick or similar Ruby HTTP server dependency
- **Recommendation**: **CONSIDER** — Useful for CI/scripting, but MCP covers primary use case

### Medium Priority

#### 5. SDK-First Architecture Pattern
- **Value**: QMD's `QMDStore` interface proves the core API is complete by having MCP consume only the public surface. Our MCP server directly accesses `Store`, `Recall`, `Sweep` internals.
- **Evidence**: `src/index.ts:212-304` — full `QMDStore` interface; `src/mcp/server.ts` — zero internal imports
- **Implementation**: Define a `ClaudeMemory::API` module that wraps all public operations. Refactor MCP server to consume only this API.
- **Effort**: 3-5 days
- **Trade-off**: Significant refactoring; current approach works fine
- **Recommendation**: **CONSIDER** — Good engineering but not urgent

#### 6. Self-Contained Database Config
- **Value**: QMD v2.0 stores collection config in SQLite tables (`store_collections`, `store_config`). Database is reopenable without external files.
- **Evidence**: `src/store.ts:699-727` — `store_collections` and `store_config` tables
- **Implementation**: Store configuration metadata (last ingest, publish mode, active scope) in a `config` table in our SQLite databases.
- **Effort**: 1-2 days
- **Trade-off**: Some config is better in ENV (paths, flags)
- **Recommendation**: **CONSIDER** — Useful for metadata like last_ingest_at, schema_version already tracked

#### 7. Per-Instance Resource Management
- **Value**: QMD creates per-store `LlamaCpp` instances with lazy loading and 5-min inactivity timeout. No global singletons. Enables concurrent stores safely.
- **Evidence**: `src/index.ts:361-364` — per-store LLM with `disposeModelsOnInactivity: true`
- **Implementation**: Ensure our `StoreManager` properly manages per-instance resources. Currently it's a singleton — consider making it closeable.
- **Effort**: 1 day
- **Trade-off**: Minimal for our use case (single process)
- **Recommendation**: **CONSIDER** — Good hygiene, low effort

### Features to Avoid

- **Custom Fine-Tuned Query Expansion (Qwen3-1.7B)**: Too heavy for fact retrieval
- **EmbeddingGemma / Qwen3-Embedding**: We use fastembed-rb (BAAI/bge-small-en-v1.5) which is lighter and requires no GPU
- **Content-Addressable Storage**: Our facts are deduplicated by signature, not content hash
- **LLM Reranking (Qwen3-Reranker-0.6B)**: Cross-encoder reranking is over-engineering for our use case
- **Query Document Format**: Over-engineering for fact retrieval (lex/vec/hyde routing unnecessary for SPO facts)
- **Write-Through YAML Config**: We don't use YAML config files; dual-database is our config model
- **Multi-Session HTTP Transport**: Our MCP server is lightweight enough for stdio; no model loading latency

---

## Architecture Decisions

### What to Preserve
- **Fact-based knowledge model**: More valuable than raw document chunks
- **Dual-database system**: Clean project/global separation
- **Ruby + Sequel**: Mature, stable, well-tested
- **21 MCP tools**: More granular than QMD's 4 tools

### What to Adopt
- **Dedicated maintenance class**: Clean operation wrapping with counts
- **Dynamic MCP instructions**: Rich context about database state
- **Embedded skill distribution**: `install-skill` command for zero-config setup

### What to Reject
- **SDK-first refactor**: Over-engineering for a gem that's already well-structured
- **Self-contained DB config**: Our dual-database + ENV is already clean
- **REST API**: MCP covers our use case; REST adds complexity

---

## Key Takeaways

### Main Learnings
1. SDK-first architecture proves API completeness by having consumers use only the public surface
2. Dynamic MCP instructions with database stats eliminate discovery tool calls
3. Embedded skill distribution is a clean pattern for zero-config plugin setup
4. Dedicated maintenance class improves separation of concerns
5. REST endpoint alongside MCP is pragmatic for non-MCP consumers

### Changes Since Last Analysis (2026-03-02)
- v2.0.0 and v2.0.1 released
- Stable SDK API with `QMDStore` interface and `createStore()` factory
- MCP server rewritten as pure SDK consumer (zero internal access)
- CLI and MCP organized into `src/cli/` and `src/mcp/` subdirectories
- Self-contained database with `store_collections` and `store_config` tables
- `Maintenance` class wrapping cleanup operations
- `embedded-skills.ts` with base64-encoded skill files
- `qmd skill install` command
- REST `/query` endpoint alongside MCP
- Runtime-aware `bin/qmd` wrapper for Bun/Node compatibility
- `better-sqlite3` bumped to ^12.4.5 for Node 25
- Comprehensive 1,286-line SDK test suite
- GPU init replaced with node-llama-cpp `autoAttempt`
- Collection ignore patterns
- Configurable `candidateLimit` for reranker
- Multi-session HTTP transport

---

*Analysis completed: 2026-03-10*
*Analyst: Claude Code*
*Review Status: Draft*
