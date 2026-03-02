# Improvements to Consider

*Updated: 2026-03-02 - Re-studied all 5 influencer repos + new KBS study. Added new items from episodic-memory, claude-mem, updated QMD/grepai/supermemory findings.*
*Sources:*
- *[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.5.2, studied 2026-03-02)*
- *[obra/episodic-memory](https://github.com/obra/episodic-memory) - Semantic conversation search (v1.0.15, studied 2026-03-02)*
- *[yoanbernabeu/grepai](https://github.com/yoanbernabeu/grepai) - Semantic code search (v0.34.0, studied 2026-03-02)*
- *[supermemoryai/claude-supermemory](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed persistent memory (v2.0.0, studied 2026-03-02)*
- *[tobi/qmd](https://github.com/tobi/qmd) - On-device hybrid search engine (v1.1.0, studied 2026-03-02)*
- *[MadBomber/kbs](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1, studied 2026-03-02)*

This document contains only unimplemented improvements. Completed items are removed.

---

## High Priority

### 1. Native Vector Storage (sqlite-vec) ⭐ CRITICAL

Source: QMD, episodic-memory, grepai (all three use sqlite-vec)

- **Value**: 10-100x faster KNN queries, enables larger fact databases
- **Validation**: Now confirmed in 3/5 studied projects — QMD (`db.ts:52`), episodic-memory (`db.ts:5,51`), grepai (via GOB but moving to sqlite-vec). This is the ecosystem standard.
- **Current Issue**: JSON embedding storage requires loading all facts, O(n) Ruby similarity calculation
- **Solution**: sqlite-vec extension with native C KNN queries
- **Implementation**:
  - Schema migration v12: Create `facts_vec` virtual table using `vec0`
  - Two-step query pattern (avoid JOINs — they hang with vec tables! Confirmed by QMD `store.ts:1912-1915`)
  - Update `Embeddings::Similarity` class
  - Backfill existing embeddings
- **Trade-off**: Adds native dependency (well-maintained, cross-platform, v0.1.7-alpha.2)
- **Effort**: 3-5 days

### 2. Claude Code Plugin Distribution Format

Source: QMD, episodic-memory, claude-supermemory, claude-mem (all 4 use marketplace.json)

- **Value**: 10x easier installation (one command vs multi-step gem + MCP + hook config)
- **Validation**: All 4 non-gem projects distribute via Claude Code marketplace plugin format
- **Implementation**: Package ClaudeMemory as marketplace plugin for single-command installation
- **Evidence**: `.claude-plugin/marketplace.json` with MCP server bundling, skill definitions, hook registration
- **Effort**: 2-3 days

---

## Medium Priority

### 3. Incremental Indexing with File Watching

Source: grepai study (reinforced 2026-03-02)

- **Value**: Eliminates manual `claude-memory ingest` calls
- **Implementation**: Add `Listen` gem, watch `.claude/projects/*/transcripts/*.jsonl`, debounce 500ms, trigger IngestCommand automatically
- **Evidence**: `watcher/watcher.go:30-59` — fsnotify with debouncing (300ms default), gitignore respect, event deduplication
- **Effort**: 2-3 days
- **Trade-off**: Background process ~10MB memory overhead

### 4. Document Chunking for Long Transcripts

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

### 5. Signal-Based Ingestion Filtering

Source: claude-supermemory study (2026-03-02)

- **Value**: Reduce noise by prioritizing transcript sections with signal keywords
- **Evidence**: supermemory `settings.json:signalKeywords` — keyword-triggered capture with context window
- **Implementation**: During ingest, weight transcript sections containing signal keywords ("decided", "convention", "always", "never", "prefer") higher
- **Effort**: 1-2 days
- **Trade-off**: May miss important but subtly-expressed facts. Our distiller already extracts structured facts, which inherently filters noise.
- **Recommendation**: DEFER — Distiller handles this naturally

### 6. HTTP MCP Transport

Source: QMD study (2026-03-02)

- **Value**: Shared server, models stay loaded, faster subsequent queries
- **Evidence**: QMD `mcp.ts:119-137` — WebStandardStreamableHTTPServerTransport with daemon mode
- **Implementation**: Add HTTP transport option alongside stdio
- **Effort**: 2-3 days
- **Trade-off**: Process management complexity
- **Recommendation**: DEFER — Only if MCP startup latency becomes an issue

### ~~7. MCP Discovery Tools~~ ✅ Implemented 2026-03-02

Added `memory.list_projects` MCP tool. Shows global DB, current project, and discovers other projects from promoted facts/global fact paths with stats.

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
- [claude-mem GitHub](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.5.2)
- [grepai GitHub](https://github.com/yoanbernabeu/grepai) - Semantic code search (v0.34.0)
- [claude-supermemory GitHub](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed memory (v2.0.0)
- [QMD GitHub](https://github.com/tobi/qmd) - On-device hybrid search engine (v1.1.0)
- [KBS GitHub](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1)

Influence documents:
- [docs/influence/qmd.md](influence/qmd.md) - Updated 2026-03-02
- [docs/influence/episodic-memory.md](influence/episodic-memory.md) - New 2026-03-02
- [docs/influence/claude-mem.md](influence/claude-mem.md) - New 2026-03-02
- [docs/influence/grepai.md](influence/grepai.md) - Updated 2026-03-02
- [docs/influence/claude-supermemory.md](influence/claude-supermemory.md) - Updated 2026-03-02
- [docs/influence/kbs.md](influence/kbs.md) - New 2026-03-02

---

*Last updated: 2026-03-02 - Implemented: Background Processing for Hooks (--async), MCP Discovery Tools (memory.list_projects), Hook Error Classification, Dynamic MCP Server Instructions, Progressive Disclosure Documentation, Conversation Exclusion Markers.*
