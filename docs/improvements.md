# Improvements to Consider

*Updated: 2026-03-09 - Re-studied all 6 influencer repos. New findings from QMD v1.1.5 (intent parameter, score traces), claude-mem v10.5.5 (mode system, stdout protection), claude-supermemory v2.0.1 (context extraction, worktree support, error classification), grepai (shell completion, skills, dedup), episodic-memory (tool annotations, agent delegation, self-exclusion). KBS unchanged.*
*Sources:*
- *[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.5.5, studied 2026-03-09)*
- *[obra/episodic-memory](https://github.com/obra/episodic-memory) - Semantic conversation search (v1.0.15, studied 2026-03-09)*
- *[yoanbernabeu/grepai](https://github.com/yoanbernabeu/grepai) - Semantic code search (latest, studied 2026-03-09)*
- *[supermemoryai/claude-supermemory](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed persistent memory (v2.0.1, studied 2026-03-09)*
- *[tobi/qmd](https://github.com/tobi/qmd) - On-device hybrid search engine (v1.1.5, studied 2026-03-09)*
- *[MadBomber/kbs](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1, studied 2026-03-09 — no changes)*

This document contains only unimplemented improvements. Completed items are removed.

---

## High Priority

### ~~1. Native Vector Storage (sqlite-vec)~~ ✅ Implemented 2026-03-04

Schema migration v12 with `facts_vec` virtual table (vec0, cosine distance). Two-step query pattern (KNN → batch hydration). VectorIndex class with native C KNN search, fallback to O(n) Ruby. Backfill via `claude-memory index --vec` and sweeper. Doctor check with coverage stats. Cross-platform: arm64-darwin, x86_64-darwin, x86_64-linux.

### ~~2. Claude Code Plugin Distribution Format~~ ✅ Implemented 2026-03-04

Plugin packaging with `plugin.json` referencing MCP server, hooks, skills, commands, and output styles. Wrapper scripts (`scripts/serve-mcp.sh`, `scripts/hook-runner.sh`) handle gem detection gracefully. Initializers detect plugin mode via `CLAUDE_PLUGIN_ROOT` and skip hooks/MCP/output-style config. Version sync Rake task keeps plugin metadata in sync with gem version.

### 3. Intent Parameter for Recall ⭐

Source: QMD v1.1.5 study (2026-03-09)

- **Value**: Disambiguate ambiguous queries (e.g., "database" with intent "migration" vs "performance")
- **Implementation**: Add `intent` param to `Recall#query`, `DualQueryTemplate`, and MCP recall tools. Intent steers expansion/reranking but doesn't replace the query itself. Weight differently per stage (0.5x for chunk selection, 0.3x for snippets)
- **Evidence**: QMD `store.ts:3103-3110` — disables BM25 shortcut when intent provided; `llm.ts:993-994` — expansion prompt includes intent; `store.ts:2383-2384` — intent prepended to rerank query
- **Effort**: 2-3 days
- **Recommendation**: ADOPT

### 4. MCP Tool Annotations ⭐

Source: episodic-memory study (2026-03-09)

- **Value**: Tell Claude which tools are read-only, idempotent, or destructive for better tool selection
- **Implementation**: Add `readOnlyHint`, `idempotentHint`, `destructiveHint` annotations to all 21 MCP tools in `MCP::Tools::TOOLS`
- **Evidence**: episodic-memory `src/mcp-server.ts:144-150` — tool annotations on search/show tools
- **Effort**: 0.5 days
- **Recommendation**: ADOPT — zero trade-off, immediate benefit

### 5. Retrieval Score Traces ⭐

Source: QMD v1.1.5 study (2026-03-09)

- **Value**: Transparency into why facts were retrieved — FTS score, vector similarity, RRF contribution, final blend
- **Implementation**: Add optional `explain: true` param to recall tools, return score breakdown per result. Enhances `memory.explain` and `memory.recall_details`
- **Evidence**: QMD `store.ts:2477-2540` — `--explain` flag with per-document RRF contribution traces
- **Effort**: 2 days
- **Recommendation**: ADOPT

### 6. MCP Stdout Protection Audit ⭐

Source: claude-mem v10.5.5 study (2026-03-09)

- **Value**: Prevent accidental `puts` or `$stdout.write` from corrupting stdio JSON-RPC transport
- **Implementation**: Audit MCP server for any stdout leaks. Add `$stdout` interception or redirect to `$stderr` during MCP serve mode
- **Evidence**: claude-mem `src/servers/mcp-server.ts:19-22` — `console.log` interception to prevent protocol corruption
- **Effort**: 0.5 days
- **Recommendation**: ADOPT

### 7. Worktree-Aware Git Root Detection ⭐

Source: claude-supermemory v2.0.1 study (2026-03-09)

- **Value**: Prevent duplicate project databases when using git worktrees
- **Implementation**: Use `git rev-parse --git-common-dir` to resolve main repo root. Add opt-in `CLAUDE_MEMORY_ISOLATE_WORKTREES` env var for worktree isolation
- **Evidence**: supermemory `src/lib/git-utils.js:5-50` — worktree detection with `--git-common-dir`
- **Effort**: 0.5 days
- **Recommendation**: ADOPT

### 8. Search Agent Delegation Pattern ⭐

Source: episodic-memory study (2026-03-09)

- **Value**: Save 50-100x main-agent context by delegating memory search to a subagent that chains recall → explain → fact_graph
- **Implementation**: Create `agents/memory-recall.md` subagent definition in plugin that chains our MCP tools and synthesizes results
- **Evidence**: episodic-memory `agents/search-conversations.md:1-162` — subagent-delegated search pattern
- **Effort**: 1-2 days
- **Recommendation**: ADOPT

### 9. Self-Excluding Agent Conversations

Source: episodic-memory study (2026-03-09)

- **Value**: Prevent ClaudeMemory's own meta-conversations (distiller, sweeper) from polluting the knowledge base
- **Implementation**: Add context marker to hook output; skip ingestion when marker detected in transcript
- **Evidence**: episodic-memory `src/constants.ts:6-7`, `src/sync.ts:6-10` — SUMMARIZER_CONTEXT_MARKER exclusion
- **Effort**: 0.5 days
- **Recommendation**: ADOPT

### 10. Structured Error Classification

Source: claude-supermemory v2.0.1 study (2026-03-09)

- **Value**: Clean error handling in MCP server and hooks — benign errors silent, retryable logged, fatal with clear messages
- **Implementation**: Three-tier classification: benign (empty results, first use), retryable (rate limits, server errors), fatal (auth failures, schema corruption)
- **Evidence**: supermemory `src/lib/error-helpers.js:1-72` — error classification with user-friendly messages
- **Effort**: 1 day
- **Recommendation**: ADOPT

### 11. Entity Context Extraction Prompts

Source: claude-supermemory v2.0.1 study (2026-03-09)

- **Value**: Structured prompt templates for distiller defining what to extract (decisions, preferences, conventions) vs what to skip
- **Implementation**: Apply when replacing NullDistiller. Rich prompt with concrete examples in table format, separate personal vs repo context
- **Evidence**: supermemory `src/lib/supermemory-client.js:21-58` — extraction prompts with examples
- **Effort**: 1-2 days (when building real distiller)
- **Recommendation**: ADOPT — template for distiller replacement

---

## Medium Priority

### 12. Shell Completion for CLI

Source: grepai study (2026-03-09)

- **Value**: Tab completion for commands and flags in zsh/bash
- **Implementation**: Generate completion scripts from OptionParser. Dynamic completions for project names
- **Evidence**: grepai `cli/completion.go` — static + dynamic completions
- **Effort**: 1-2 days
- **Recommendation**: CONSIDER

### 13. Content-Addressed Deduplication for Embeddings

Source: grepai study (2026-03-09)

- **Value**: Skip re-embedding unchanged content using existing `text_hash` in `content_items`
- **Implementation**: Check `text_hash` before computing embeddings; reuse cached vectors for identical content
- **Evidence**: grepai `store/store.go:105-109` — EmbeddingCache interface
- **Effort**: 1 day
- **Recommendation**: CONSIDER — quick win, infrastructure already exists

### 14. Deduplication Before Vector Scoring

Source: QMD v1.1.5 study (2026-03-09)

- **Value**: Free performance win — deduplicate fact texts before computing cosine similarity, map scores back
- **Implementation**: In `VectorIndex#search`, group facts by text, score unique texts only, fan out results
- **Evidence**: QMD `llm.ts:1098-1109` — reranker deduplication (identical chunks scored once, fanned out)
- **Effort**: 1 day
- **Recommendation**: CONSIDER

### 15. Incremental Indexing with File Watching

Source: grepai study (reinforced 2026-03-02)

- **Value**: Eliminates manual `claude-memory ingest` calls
- **Implementation**: Add `Listen` gem, watch `.claude/projects/*/transcripts/*.jsonl`, debounce 500ms, trigger IngestCommand automatically
- **Evidence**: `watcher/watcher.go:30-59` — fsnotify with debouncing (300ms default), gitignore respect, event deduplication
- **Effort**: 2-3 days
- **Trade-off**: Background process ~10MB memory overhead

### 16. Document Chunking for Long Transcripts

Source: QMD study (updated 2026-03-02)

- **Value**: Better embeddings for long content (>3000 chars)
- **Implementation**: 900 tokens/chunk, 15% overlap, markdown-aware break points
- **Evidence**: QMD v1.1.0 `store.ts:53-219` — scored break point patterns (h1=100 → newline=1), code fence detection, squared distance decay
- **Consideration**: Only if users report issues with long transcripts
- **Effort**: 2-3 days

### ~~5. Background Processing for Hooks~~ ✅ Implemented 2026-03-02

`--async` flag on hook ingest/sweep/publish subcommands. Fork+detach for non-blocking execution, fallback to sync when fork unavailable.

---

## Low Priority / Defer

### 17. Signal-Based Ingestion Filtering

Source: claude-supermemory study (2026-03-02)

- **Value**: Reduce noise by prioritizing transcript sections with signal keywords
- **Evidence**: supermemory `settings.json:signalKeywords` — keyword-triggered capture with context window
- **Implementation**: During ingest, weight transcript sections containing signal keywords ("decided", "convention", "always", "never", "prefer") higher
- **Effort**: 1-2 days
- **Trade-off**: May miss important but subtly-expressed facts. Our distiller already extracts structured facts, which inherently filters noise.
- **Recommendation**: DEFER — Distiller handles this naturally

### 18. HTTP MCP Transport

Source: QMD study (2026-03-02)

- **Value**: Shared server, models stay loaded, faster subsequent queries
- **Evidence**: QMD `mcp.ts:119-137` — WebStandardStreamableHTTPServerTransport with daemon mode
- **Implementation**: Add HTTP transport option alongside stdio
- **Effort**: 2-3 days
- **Trade-off**: Process management complexity
- **Recommendation**: DEFER — Only if MCP startup latency becomes an issue

### ~~7. MCP Discovery Tools~~ ✅ Implemented 2026-03-02

Added `memory.list_projects` MCP tool. Shows global DB, current project, and discovers other projects from promoted facts/global fact paths with stats.

### ~~8. Database Compact Command~~ ✅ Implemented 2026-03-02

Added `claude-memory compact` command. Runs SQLite VACUUM with optional integrity check (`--check`). Supports `--scope` for global/project/all. Reports size before/after with savings.

### ~~9. Fact Export Command~~ ✅ Implemented 2026-03-02

Added `claude-memory export` command. Dumps facts with entities and provenance to JSON. Supports `--scope`, `--status` (active/all), `--output` (file), `--pretty`. Includes version metadata for import compatibility.

---

## Features to Avoid

- **Chroma Vector Database** — We use fastembed-rb with local ONNX model. sqlite-vec is the better upgrade path (claude-mem uses Chroma, but QMD/episodic-memory prove sqlite-vec is simpler and sufficient)
- **Claude Agent SDK for Distillation** — Direct API calls via `anthropic-rb` gem
- **Worker Service Background Process** — Keep stdio-based MCP server. claude-mem's worker architecture adds significant complexity and failure modes.
- **Web Viewer UI** — CLI output is sufficient. Add if users request it
- **Neural Embeddings (EmbeddingGemma)** — Superseded by FastEmbed (BAAI/bge-small-en-v1.5)
- **Cross-Encoder Reranking (Qwen3-Reranker-0.6B)** — Over-engineering for fact retrieval
- **Query Expansion (LLM, Qwen3-1.7B)** — No LLM in recall path, too heavy
- **Custom Fine-Tuned Query Expansion** — 1.7B model too heavy for fact retrieval
- **YAML Collection System** — Our dual-database approach is cleaner
- **Content-Addressable Storage** — Facts deduplicated by signature, not content hash
- **Virtual Path System** — Dual-database provides clear namespace
- **Cloud Storage Dependency** — Local-first is superior (supermemory's weakness)
- **Tree-Sitter AST Code Navigation** — Out of scope for memory/fact retrieval (claude-mem's Smart Explore)
- **RPG Semantic Code Graph** — Wrong domain; code structure graph vs fact knowledge graph (grepai)
- **AGPL Licensing** — Too restrictive for developer tools (claude-mem)
- **Multiple AI Providers (Gemini/OpenRouter)** — Over-engineering; anthropic-rb is sufficient
- **Bubble Tea TUI** — CLI output is sufficient (grepai)
- **Query Document Format (lex/vec/hyde)** — Over-engineering for fact retrieval (QMD)
- **Team Memory via Cloud Sync** — Our dual-database handles scope well; cloud sync adds complexity (supermemory)
- **Raw Conversation Storage** — We distill into structured facts (episodic-memory stores raw exchanges)
- **KBS as Dependency (RETE inference engine)** — KBS (MadBomber/kbs) provides RETE inference, but solves a fundamentally different problem (forward-chaining rules vs knowledge recall). Architectural mismatch, schema incompatibility (JSON blobs vs normalized triples), performance regression (raw sqlite3 vs Sequel+Extralite), low adoption (2 stars, sole maintainer). See `docs/influence/kbs.md`.
- **KBS Redis Backend** — Redis store adds operational complexity; SQLite + Extralite is fast enough for our use case
- **KBS Message Queue** — Hook ordering already handles coordination; message queue adds unnecessary complexity
- **KBS Declarative Rule DSL** — Expressive but wrong paradigm for knowledge recall; our query/search approach is more appropriate
- **Mode/Domain System** — claude-mem v10.5.5 adds JSON-based mode profiles for domain-specific observation types. Our SPO fact model already generalizes across domains; only pursue if users request domain-specific support
- **Config Inheritance Pattern** — claude-mem's `parent--override` naming with deep merge. Not enough configuration variants to justify the complexity
- **HMAC Request Signing** — supermemory's `validate.js` uses HMAC but hardcodes the secret in a minified bundle. Security through obscurity, and we have no cloud API to protect
- **Codebase Indexing Command** — supermemory's `/index` actively explores codebases. Our hook-based passive capture is more appropriate; active indexing risks generating low-quality facts from code structure

---

## Design Decisions

### No Tag Count Limit (2026-01-23)

**Decision**: Removed MAX_TAG_COUNT limit from ContentSanitizer.

**Rationale**:
- The regex pattern `/<tag>.*?<\/tag>/m` is provably safe from ReDoS attacks
- Performance is O(n) and excellent even with 1000+ tags (~0.6ms)
- Real-world usage legitimately produces 100-200+ tags in long sessions
- No other similar tool enforces tag count limits

**Do not reintroduce**: Tag count validation is unnecessary and harmful.

---

## References

- [episodic-memory GitHub](https://github.com/obra/episodic-memory) - Semantic conversation search (v1.0.15)
- [claude-mem GitHub](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.5.5)
- [grepai GitHub](https://github.com/yoanbernabeu/grepai) - Semantic code search (latest)
- [claude-supermemory GitHub](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed memory (v2.0.1)
- [QMD GitHub](https://github.com/tobi/qmd) - On-device hybrid search engine (v1.1.5)
- [KBS GitHub](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1)

Influence documents:
- [docs/influence/qmd.md](influence/qmd.md) - Updated 2026-03-09
- [docs/influence/episodic-memory.md](influence/episodic-memory.md) - Updated 2026-03-09
- [docs/influence/claude-mem.md](influence/claude-mem.md) - Updated 2026-03-09
- [docs/influence/grepai.md](influence/grepai.md) - Updated 2026-03-09
- [docs/influence/claude-supermemory.md](influence/claude-supermemory.md) - Updated 2026-03-09
- [docs/influence/kbs.md](influence/kbs.md) - Updated 2026-03-09 (no changes)

---

*Last updated: 2026-03-09 - Re-studied all 6 influencer repos. Added 9 new high-priority items (#3-11): Intent Parameter, MCP Tool Annotations, Retrieval Score Traces, MCP Stdout Protection, Worktree-Aware Git Root, Search Agent Delegation, Self-Excluding Conversations, Structured Error Classification, Entity Context Extraction Prompts. Added 3 medium-priority items (#12-14): Shell Completion, Content-Addressed Dedup, Vector Scoring Dedup. Added 4 new Features to Avoid. Previous: Claude Code Plugin Distribution Format, sqlite-vec, Database Compact, Fact Export, Background Processing, MCP Discovery Tools.*
