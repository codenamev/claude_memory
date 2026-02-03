# Improvements to Consider

*Updated: 2026-02-03*
*Sources:*
- *[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) - Memory compression system*
- *[obra/episodic-memory](https://github.com/obra/episodic-memory) - Semantic conversation search*
- *[yoanbernabeu/grepai](https://github.com/yoanbernabeu/grepai) - Semantic code search with vector embeddings*
- *[supermemoryai/claude-supermemory](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed persistent memory plugin*
- *[tobi/qmd](https://github.com/tobi/qmd) - On-device hybrid search engine (updated 2026-02-02)*

This document contains only unimplemented improvements. Completed items are removed.

---

## High Priority (QMD-Inspired)

### 1. Native Vector Storage (sqlite-vec) ⭐ CRITICAL

- **Value**: 10-100x faster KNN queries, enables larger fact databases
- **QMD Proof**: Handles 10,000+ documents with sub-second vector queries
- **Current Issue**: JSON embedding storage requires loading all facts, O(n) Ruby similarity calculation
- **Solution**: sqlite-vec extension with native C KNN queries
- **Implementation**:
  - Schema migration v8: Create `facts_vec` virtual table using `vec0`
  - Two-step query pattern (avoid JOINs - they hang with vec tables!)
  - Update `Embeddings::Similarity` class
  - Backfill existing embeddings
- **Trade-off**: Adds native dependency (acceptable, well-maintained, cross-platform)

### 2. Reciprocal Rank Fusion (RRF) Algorithm ⭐ HIGH VALUE

- **Value**: 50% improvement in Hit@3 for medium-difficulty queries (QMD evaluation)
- **Current Issue**: Naive deduplication doesn't properly fuse ranking signals
- **Solution**: Mathematical fusion of FTS + vector ranked lists with position-aware scoring
- **Formula**: `score = Σ(weight / (k + rank + 1))` with top-rank bonus
- **Implementation**:
  - Create `Recall::RRFusion` class
  - Update `Recall#query_semantic_dual` to use RRF
  - Apply weights: original query ×2, expanded queries ×1
  - Add top-rank bonus: +0.05 for #1, +0.02 for #2-3

### 3. Docid Short Hash System ⭐ MEDIUM VALUE

- **Value**: Better UX, cross-database fact references
- **Current Issue**: Integer IDs are database-specific, not user-friendly
- **Solution**: 8-character hash IDs for facts (e.g., `#abc123de`)
- **Implementation**:
  - Schema migration: Add `docid` column (indexed, unique)
  - Backfill existing facts with SHA256-based docids
  - Update CLI commands (`explain`, `recall`) to accept docids
  - Update MCP tools to accept docids
  - Update output formatting to show docids

### 4. Smart Expansion Detection ⭐ MEDIUM VALUE

- **Value**: Skip unnecessary vector search when FTS finds exact match
- **QMD Proof**: Saves 2-3 seconds on 60% of queries (exact keyword matches)
- **Current Issue**: Always runs both FTS and vector search, even for exact matches
- **Solution**: Heuristic detection of strong FTS signal
- **Thresholds**: `top_score >= 0.85` AND `gap >= 0.15`
- **Implementation**:
  - Create `Recall::ExpansionDetector` class
  - Update `Recall#query_semantic_dual` to check before vector search

---

## High Priority (Study-Inspired)

### 5. SessionStart Context Injection via Hook ⭐

Source: claude-supermemory study

- **Value**: Guarantees Claude sees memory context immediately, supplements existing `.claude/rules/` publish
- **Implementation**: Inject recalled facts into Claude's context at session start using `hookSpecificOutput.additionalContext`
- **Evidence**: `context-hook.js:72-74` — uses hook response to inject `<supermemory-context>` XML
- **Effort**: 1-2 days (hook handler, context formatter, settings)

### 6. Tool-Specific Observation Compression ⭐

Source: claude-supermemory study

- **Value**: ~70% token reduction vs raw tool I/O in provenance descriptions
- **Implementation**: Compact per-tool summarization for provenance (e.g., `Edited auth.js: "login()" → "async login()"`)
- **Evidence**: `compress.js:13-75` — 10 tool handlers with human-readable output
- **Effort**: 4-6 hours (class + tests + ingest integration)

### 7. Claude Code Plugin Distribution Format ⭐

Source: QMD study

- **Value**: 10x easier installation (one command vs multi-step gem + MCP + hook config)
- **Implementation**: Package ClaudeMemory as marketplace plugin for single-command installation
- **Evidence**: `.claude-plugin/marketplace.json` — complete plugin spec with MCP server bundling and skill definitions
- **Effort**: 2-3 days

### 8. Inline Status Check in Skills

Source: QMD study

- **Value**: Users see memory health before tool usage
- **Implementation**: Run `claude-memory doctor --brief` on skill load for immediate health feedback
- **Evidence**: `SKILL.md:18` — `!` prefix runs command during skill load
- **Effort**: 1-2 hours

---

## Medium Priority

### 9. Incremental Indexing with File Watching

Source: grepai study

- **Value**: Eliminates manual `claude-memory ingest` calls
- **Implementation**: Add `Listen` gem, watch `.claude/projects/*/transcripts/*.jsonl`, debounce 500ms, trigger IngestCommand automatically
- **Evidence**: `watcher/watcher.go:44` — `fsnotify` with debouncing (300ms default), gitignore respect
- **Effort**: 2-3 days
- **Trade-off**: Background process ~10MB memory overhead

### 10. Fact Dependency Graph Visualization

Source: grepai study

- **Value**: Invaluable for understanding why facts were superseded or conflicted
- **Implementation**: Create `memory.fact_graph <fact_id> --depth 2` tool, query `fact_links` table with BFS traversal, return JSON with nodes (facts) and edges (supersedes/conflicts/supports)
- **Effort**: 2-3 days

### 11. Configurable Tool Capture Filtering

Source: claude-supermemory study

- **Value**: Reduces noise from read-heavy tools (Read, Glob, Grep)
- **Implementation**: Skip/capture lists for controlling which tool observations are ingested
- **Evidence**: `settings.js:9-15` — `skipTools` and `captureTools` with whitelist/blacklist modes
- **Effort**: 3-4 hours

### 12. Background Processing for Hooks

Source: episodic-memory study

- **Value**: Non-blocking hooks for better UX
- **Implementation**: `--async` flag on hook commands, fork and detach
- **Trade-off**: Background process management complexity, potential race conditions

### 13. LLM Response Caching

Source: QMD study

- **Value**: Reduce API costs for repeated distillation
- **Implementation**: Add `llm_cache` table (hash, result, created_at), cache key: `SHA256(operation + model + input)`
- **Consideration**: Most valuable when distiller is fully implemented

### 14. Document Chunking for Long Transcripts

Source: QMD study

- **Value**: Better embeddings for long content (>3000 chars)
- **Implementation**: 800 tokens, 15% overlap, semantic boundary detection
- **Consideration**: Only if users report issues with long transcripts

### 15. Enhanced Snippet Extraction

Source: QMD study

- **Value**: Better search result previews with query term highlighting
- **Implementation**: Find line with most query term matches, extract 1 line before + 2 after

---

## Low Priority

### 16. Structured Logging

- **Value**: Better debugging with JSON logs
- **Implementation**: Add `ClaudeMemory::Logging::Logger` with structured JSON output

### 17. Background Processing Line-Range References

Source: episodic-memory study

- **Value**: Precise source linking for fact verification
- **Implementation**: Store line_start and line_end in provenance table

---

## Features to Avoid

- **Chroma Vector Database** — We use fastembed-rb with local ONNX model instead
- **Claude Agent SDK for Distillation** — Direct API calls via `anthropic-rb` gem
- **Worker Service Background Process** — Keep stdio-based MCP server
- **Web Viewer UI** — CLI output is sufficient. Add if users request it
- **Configuration-Driven Context** — Default config is sufficient. Add if users request it
- **Neural Embeddings (EmbeddingGemma)** — Superseded by FastEmbed (BAAI/bge-small-en-v1.5)
- **Cross-Encoder Reranking (Qwen3-Reranker-0.6B)** — Over-engineering for fact retrieval
- **Query Expansion (LLM, Qwen3-1.7B)** — No LLM in recall path, too heavy
- **Custom Fine-Tuned Query Expansion** — 1.7B model too heavy for fact retrieval
- **YAML Collection System** — Our dual-database approach is cleaner
- **Content-Addressable Storage** — Facts deduplicated by signature, not content hash
- **Virtual Path System** — Dual-database provides clear namespace

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

- [episodic-memory GitHub](https://github.com/obra/episodic-memory) - Semantic conversation search
- [claude-mem GitHub](https://github.com/thedotmack/claude-mem) - Memory compression system
- [grepai GitHub](https://github.com/yoanbernabeu/grepai) - Semantic code search
- [claude-supermemory GitHub](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed memory
- [QMD GitHub](https://github.com/tobi/qmd) - On-device hybrid search engine

---

*Last updated: 2026-02-03 - Cleaned up completed items*
