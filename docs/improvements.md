# Improvements to Consider

*Updated: 2026-02-03 - Removed Docid Short Hash System (implemented), Fact Dependency Graph, Enhanced Snippet Extraction, Line-Range References (implemented)*
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
  - Schema migration v10: Create `facts_vec` virtual table using `vec0`
  - Two-step query pattern (avoid JOINs - they hang with vec tables!)
  - Update `Embeddings::Similarity` class
  - Backfill existing embeddings
- **Trade-off**: Adds native dependency (acceptable, well-maintained, cross-platform)

---

## High Priority (Study-Inspired)

### 2. SessionStart Context Injection via Hook ⭐

Source: claude-supermemory study

- **Value**: Guarantees Claude sees memory context immediately, supplements existing `.claude/rules/` publish
- **Implementation**: Inject recalled facts into Claude's context at session start using `hookSpecificOutput.additionalContext`
- **Evidence**: `context-hook.js:72-74` — uses hook response to inject `<supermemory-context>` XML
- **Effort**: 1-2 days (hook handler, context formatter, settings)

### 3. Tool-Specific Observation Compression ⭐

Source: claude-supermemory study

- **Value**: ~70% token reduction vs raw tool I/O in provenance descriptions
- **Implementation**: Compact per-tool summarization for provenance (e.g., `Edited auth.js: "login()" → "async login()"`)
- **Evidence**: `compress.js:13-75` — 10 tool handlers with human-readable output
- **Effort**: 4-6 hours (class + tests + ingest integration)

### 4. Claude Code Plugin Distribution Format ⭐

Source: QMD study

- **Value**: 10x easier installation (one command vs multi-step gem + MCP + hook config)
- **Implementation**: Package ClaudeMemory as marketplace plugin for single-command installation
- **Evidence**: `.claude-plugin/marketplace.json` — complete plugin spec with MCP server bundling and skill definitions
- **Effort**: 2-3 days

---

## Medium Priority

### 5. Incremental Indexing with File Watching

Source: grepai study

- **Value**: Eliminates manual `claude-memory ingest` calls
- **Implementation**: Add `Listen` gem, watch `.claude/projects/*/transcripts/*.jsonl`, debounce 500ms, trigger IngestCommand automatically
- **Evidence**: `watcher/watcher.go:44` — `fsnotify` with debouncing (300ms default), gitignore respect
- **Effort**: 2-3 days
- **Trade-off**: Background process ~10MB memory overhead

### 6. Background Processing for Hooks

Source: episodic-memory study

- **Value**: Non-blocking hooks for better UX
- **Implementation**: `--async` flag on hook commands, fork and detach
- **Trade-off**: Background process management complexity, potential race conditions

### 7. LLM Response Caching

Source: QMD study

- **Value**: Reduce API costs for repeated distillation
- **Implementation**: Add `llm_cache` table (hash, result, created_at), cache key: `SHA256(operation + model + input)`
- **Consideration**: Most valuable when distiller is fully implemented

### 8. Document Chunking for Long Transcripts

Source: QMD study

- **Value**: Better embeddings for long content (>3000 chars)
- **Implementation**: 800 tokens, 15% overlap, semantic boundary detection
- **Consideration**: Only if users report issues with long transcripts

---

## Low Priority

### 9. Structured Logging

- **Value**: Better debugging with JSON logs
- **Implementation**: Add `ClaudeMemory::Logging::Logger` with structured JSON output

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

*Last updated: 2026-02-03 - Removed Docid Short Hash System (implemented). Renumbered items.*
