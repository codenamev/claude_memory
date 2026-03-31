# Improvements to Consider

*Updated: 2026-03-30 - Re-studied all 7 influencer repos. New recommendations: CLAUDE_CONFIG_DIR support (#26, from episodic-memory), Usage Stats / ROI Tracking (#27, from grepai v0.35.0). New Features to Avoid: AST-Aware Code Chunking (QMD), Custom Instructions via Env Var (lossless-claw v0.5.2), OpenClaw Context Injection (claude-mem v10.6.0). Repos with no changes: kbs (v0.2.1), claude-supermemory (v2.0.1), episodic-memory (v1.0.15). Previously: 14 features implemented through 2026-03-24.*
*Sources:*
- *[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.6.3, re-studied 2026-03-30)*
- *[obra/episodic-memory](https://github.com/obra/episodic-memory) - Semantic conversation search (v1.0.15, re-studied 2026-03-30 — no changes)*
- *[yoanbernabeu/grepai](https://github.com/yoanbernabeu/grepai) - Semantic code search (v0.35.0, re-studied 2026-03-30)*
- *[supermemoryai/claude-supermemory](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed persistent memory (v2.0.1, re-studied 2026-03-30 — no changes)*
- *[tobi/qmd](https://github.com/tobi/qmd) - On-device hybrid search engine (v2.0.1+unreleased, re-studied 2026-03-30)*
- *[MadBomber/kbs](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1, studied 2026-03-30 — no changes)*
- *[martian-engineering/lossless-claw](https://github.com/martian-engineering/lossless-claw) - DAG-based lossless context management (v0.5.2, re-studied 2026-03-30)*

This document contains only unimplemented improvements. Completed items are removed.

---

## High Priority

### ~~1. Native Vector Storage (sqlite-vec)~~ ✅ Implemented 2026-03-04

Schema migration v12 with `facts_vec` virtual table (vec0, cosine distance). Two-step query pattern (KNN → batch hydration). VectorIndex class with native C KNN search, fallback to O(n) Ruby. Backfill via `claude-memory index --vec` and sweeper. Doctor check with coverage stats. Cross-platform: arm64-darwin, x86_64-darwin, x86_64-linux.

### ~~2. Claude Code Plugin Distribution Format~~ ✅ Implemented 2026-03-04

Plugin packaging with `plugin.json` referencing MCP server, hooks, skills, commands, and output styles. Wrapper scripts (`scripts/serve-mcp.sh`, `scripts/hook-runner.sh`) handle gem detection gracefully. Initializers detect plugin mode via `CLAUDE_PLUGIN_ROOT` and skip hooks/MCP/output-style config. Version sync Rake task keeps plugin metadata in sync with gem version.

### ~~3. Intent Parameter for Recall~~ ✅ Implemented 2026-03-23

Optional `intent` parameter added to `Recall#query`, `#query_index`, and `#query_semantic`. Threaded through DualEngine/LegacyEngine via `QueryCore#intent_augmented_query`. Intent appended to search query (0.5x weight for chunk selection, 0.3x for semantic). Disables BM25 shortcut when intent provided so vector search always runs. Exposed via `memory.recall`, `memory.recall_index`, and `memory.recall_semantic` MCP tools.

### ~~4. MCP Tool Annotations~~ ✅ Implemented 2026-03-09

Added `readOnlyHint`, `idempotentHint`, `destructiveHint` annotations to all 23 MCP tools via shared constants (READ_ONLY, WRITE, WRITE_IDEMPOTENT). 19 query tools marked read-only, store_extraction/sweep_now/mark_distilled as write, promote as write-idempotent.

### ~~5. Retrieval Score Traces~~ ✅ Implemented 2026-03-20

Added `explain: true` parameter to `memory.recall_semantic` MCP tool. When enabled, each result includes `score_trace` with `vec_rank`, `vec_score`, `vec_rrf`, `fts_rank`, `fts_score`, `fts_rrf`, and `rrf_final`. Threaded through Recall → DualEngine/LegacyEngine → QueryCore → RRFusion. Components show nil for sources that didn't contribute.

### ~~6. MCP Stdout Protection Audit~~ ✅ Implemented 2026-03-09

ServeMcpCommand captures real stdout for MCP transport, redirects `$stdout` to `$stderr` during serve. Accidental puts/print from gems goes to stderr. Restore via ensure block.

### ~~7. Worktree-Aware Git Root Detection~~ ✅ Implemented 2026-03-09

Configuration#project_dir uses `git rev-parse --git-common-dir` to resolve main repo root across worktrees. `CLAUDE_MEMORY_ISOLATE_WORKTREES` env var opts into per-worktree isolation. Uses Open3.capture2 with graceful fallback to Dir.pwd.

### ~~8. Search Agent Delegation Pattern~~ ✅ Implemented 2026-03-20

Created `memory-recall.md` agent definition that chains recall → explain → fact_graph with 4-step workflow (fast lookup → semantic search → enrich → synthesize). Available as `/memory-recall` slash command after installation. Bundled in plugin commands directory and installable via `claude-memory install-skill memory-recall`.

### ~~9. Self-Excluding Agent Conversations~~ ✅ Implemented 2026-03-09

Added `SELF_CONTEXT_MARKER` constant (`claude-memory-self`) to ClaudeMemory module. Added to ingester EXCLUSION_TAGS. Transcripts containing `<claude-memory-self>` are skipped entirely, preventing meta-conversation pollution.

### ~~10. Dedicated Maintenance Class~~ ✅ Implemented 2026-03-16

Extracted `Sweep::Maintenance` class from Sweeper with 8 individual operations, each returning affected counts: `expire_proposed_facts`, `expire_disputed_facts`, `prune_orphaned_provenance`, `prune_old_content`, `backfill_vec_index`, `cleanup_vec_expired`, `checkpoint_wal`, `vacuum`. Sweeper now delegates to Maintenance internally.

### ~~11. Dynamic MCP Instructions Enhancement~~ ✅ Implemented 2026-03-16

Enhanced InstructionsBuilder with knowledge summary (decision/convention/entity counts by predicate pattern), vec availability detection, and dynamic usage tips that adapt based on available capabilities. Semantic search guidance included when sqlite-vec is loaded.

### ~~12. Embedded Skill Distribution~~ ✅ Implemented 2026-03-20

Added `claude-memory install-skill` command. Skills shipped as markdown files in `lib/claude_memory/commands/skills/`. Supports `--list`, `--force`, and auto-creates `~/.claude/commands/` directory. Registry-based design supports future skill additions. Paired with Search Agent Delegation (#8).

### ~~13. Depth-Aware Prompt Templates for Distiller~~ ⭐ Partially Implemented 2026-03-24

Source: lossless-claw v0.3.0 study (2026-03-16)

Three-layer automatic distillation pipeline: (1) NullDistiller wired into ingest hooks for instant regex extraction on Stop/SessionStart/PreCompact/SessionEnd/TaskCompleted/TeammateIdle, (2) Context hook injection at SessionStart includes undistilled content with extraction instructions — Claude Code acts as the LLM distiller at zero extra cost, (3) `/distill-transcripts` skill for manual deep extraction. New MCP tools: `memory.undistilled`, `memory.mark_distilled`. Depth-aware prompt selection (initial vs consolidation vs contradiction) deferred to skill enhancement — no Ruby code needed, just skill file edits.

### ~~14. Three-Level Escalation for Sweep/Maintenance~~ ✅ Implemented 2026-03-16

Added `run_with_escalation!` to Sweeper: normal (standard TTLs) → aggressive (halved TTLs) → fallback (force-expire oldest 10 proposed/disputed). Stats include `:escalation_level`. MCP `memory.sweep_now` gains `escalate: true` parameter. TextSummary shows escalation level in output.

### ~~15. Tool Escalation Workflow in MCP Instructions~~ ✅ Implemented 2026-03-16

Restructured QueryGuide with 4-tier escalation hierarchy (Fast Lookup → Broad Search → Targeted Deep Dive → Relationship Exploration). Each tool annotated with cost estimates (tokens per call). Added "Recommended Workflow" section. InstructionsBuilder usage hint updated with escalation guidance.

### ~~16. Structured Error Classification~~ ✅ Implemented 2026-03-16

Added `MCP::ErrorClassifier` with three-tier classification: benign (empty results, first use — no alarm), retryable (DB locked, I/O errors — retry flag), fatal (disk full, corruption — recommendations). MCP tools use classified errors with severity, retry hints, and actionable recommendations.

### ~~17. Entity Context Extraction Prompts~~ ✅ Implemented 2026-03-24

Source: claude-supermemory v2.0.1 study (2026-03-09)

Extraction instructions embedded in `/distill-transcripts` skill and context hook injection prompt. Defines what to extract (technology decisions, conventions, preferences, architecture, entities by type) vs what to skip (debugging steps, code output, transient errors). Scope detection for global vs project facts. Claude Code itself performs extraction — no separate API call needed.

---

## Medium Priority

### ~~18. Shell Completion for CLI~~ ✅ Implemented 2026-03-20

Added `claude-memory completion` command generating zsh and bash completion scripts. Auto-detects shell from `$SHELL`. Includes all 25 CLI commands, hook subcommands (ingest/sweep/publish/context), and context-aware flag completions for scope, index, and install-skill. Usage: `eval "$(claude-memory completion)"`.

### ~~19. Content-Addressed Deduplication for Embeddings~~ ✅ Implemented 2026-03-16

IndexCommand builds text→embedding cache from already-embedded facts before indexing. Identical fact texts reuse cached vectors, skipping generation. Cache hits tracked and reported (e.g., "Cache hits: 3/10 (30% dedup)").

### ~~20. Deduplication Before Vector Scoring~~ ✅ Implemented 2026-03-16

In Ruby fallback path (`search_by_vector_fallback`), facts are grouped by `embedding_json` before cosine similarity computation. Unique embeddings scored once, results fanned out to all matching fact_ids. Native sqlite-vec path unaffected (handles own dedup).

### 21. Incremental Indexing with File Watching

Source: grepai study (reinforced 2026-03-02)

- **Value**: Eliminates manual `claude-memory ingest` calls
- **Implementation**: Add `Listen` gem, watch `.claude/projects/*/transcripts/*.jsonl`, debounce 500ms, trigger IngestCommand automatically
- **Evidence**: `watcher/watcher.go:30-59` — fsnotify with debouncing (300ms default), gitignore respect, event deduplication
- **Effort**: 2-3 days
- **Trade-off**: Background process ~10MB memory overhead

### 22. Document Chunking for Long Transcripts

Source: QMD study (updated 2026-03-02)

- **Value**: Better embeddings for long content (>3000 chars)
- **Implementation**: 900 tokens/chunk, 15% overlap, markdown-aware break points
- **Evidence**: QMD v1.1.0 `store.ts:53-219` — scored break point patterns (h1=100 → newline=1), code fence detection, squared distance decay
- **Consideration**: Only if users report issues with long transcripts
- **Effort**: 2-3 days

### ~~5. Background Processing for Hooks~~ ✅ Implemented 2026-03-02

`--async` flag on hook ingest/sweep/publish subcommands. Fork+detach for non-blocking execution, fallback to sync when fork unavailable.

### 26. CLAUDE_CONFIG_DIR Support

Source: episodic-memory re-study (2026-03-30)

- **Value**: Support users with multiple Claude Code profiles or non-standard config locations
- **Implementation**: Check `ENV["CLAUDE_CONFIG_DIR"]` in `Configuration#global_db_path` before falling back to `~/.claude`
- **Evidence**: episodic-memory `src/paths.ts:20-22` — `process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')`
- **Effort**: 0.5 days
- **Trade-off**: None — purely additive, backwards compatible

### 28. Code-Aware Transcript Chunking

Source: QMD v2.0.1+unreleased re-study (2026-03-30)

- **Value**: Better embeddings for transcripts containing code — detect fenced code blocks and apply AST-aware break points (function/class/import boundaries) rather than naive text splitting
- **Implementation**: Detect ` ```language ` fences in transcript content, parse code blocks with tree-sitter (via ruby_tree_sitter gem or shelling out), score break points (class=100, func=90, type=80, import=60), merge with markdown break points from #22
- **Evidence**: QMD `src/ast.ts` (392 lines) — web-tree-sitter with WASM grammars, `mergeBreakPoints()` combining AST + regex scores, graceful degradation on parse failure
- **Consideration**: Only useful in combination with #22 (Document Chunking). Transcripts often contain significant code in tool_use results and assistant responses
- **Effort**: 2-3 days (after #22)
- **Trade-off**: Adds tree-sitter dependency; graceful fallback to regex-only chunking when grammar unavailable

### 27. Usage Stats / ROI Tracking

Source: grepai v0.35.0 re-study (2026-03-30)

- **Value**: Demonstrate memory value to users — track recall hits, fact counts, query latency, and show ROI over time
- **Implementation**: NDJSON stats file (`.claude/memory-stats.json`), fire-and-forget recording in MCP tool calls, `claude-memory stats` command for summary
- **Evidence**: grepai `stats/` package — `stats.Recorder` with file-locking, goroutine recording with 100ms timeout, `stats.Summarize()` aggregation, per-day history
- **Effort**: 2-3 days
- **Trade-off**: Minor disk I/O per query; use fire-and-forget pattern to avoid latency impact

---

## Low Priority / Defer

### 23. REST API Endpoint

Source: QMD v2.0.1 study (2026-03-10)

- **Value**: POST `/query` alongside MCP — enables search from curl, scripts, CI, and non-MCP clients without the full MCP protocol handshake
- **Implementation**: Add optional HTTP server mode to `claude-memory serve-mcp --http` with POST `/recall` endpoint. Accept `{ query, scope, limit }`, return JSON facts
- **Evidence**: QMD `src/mcp/server.ts:626-675` — `/query` and `/search` endpoints with structured JSON
- **Effort**: 2 days
- **Trade-off**: Requires WEBrick or similar Ruby HTTP server dependency
- **Recommendation**: CONSIDER — Useful for CI/scripting, but MCP covers primary use case

### 24. Signal-Based Ingestion Filtering

Source: claude-supermemory study (2026-03-02)

- **Value**: Reduce noise by prioritizing transcript sections with signal keywords
- **Evidence**: supermemory `settings.json:signalKeywords` — keyword-triggered capture with context window
- **Implementation**: During ingest, weight transcript sections containing signal keywords ("decided", "convention", "always", "never", "prefer") higher
- **Effort**: 1-2 days
- **Trade-off**: May miss important but subtly-expressed facts. Our distiller already extracts structured facts, which inherently filters noise.
- **Recommendation**: DEFER — Distiller handles this naturally

### 25. HTTP MCP Transport

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
- **Claude Agent SDK for Distillation** — Direct API calls via `anthropic-rb` gem. Instead, Claude Code itself serves as the distiller via context hook injection and `/distill-transcripts` skill — zero extra cost
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
- **SDK-First Architecture Refactor** — QMD v2.0 refactored to SDK-first with `QMDStore` interface consumed by CLI and MCP. Our gem + MCP architecture is already well-structured; major refactor for marginal gain
- **Write-Through YAML Config** — QMD v2.0 writes collection mutations to both SQLite and YAML. We don't use YAML config; dual-database is our config model
- **Multi-Session HTTP Transport** — QMD v2.0 supports concurrent MCP sessions via session map. Our MCP server is lightweight enough for stdio; no model loading latency to amortize
- **DAG-Based Conversation Compaction** — lossless-claw compresses conversations into a summary hierarchy; we distill structured facts. Fundamentally different paradigms that are complementary, not competing
- **LLM-Heavy Compaction Pipeline** — Every compaction in lossless-claw requires LLM summarization calls. Our no-LLM retrieval path is a significant cost and latency advantage
- **Go TUI for Debugging** — Adding a second language for an interactive debugging tool is over-engineering. CLI commands are sufficient (lossless-claw)
- **Per-Conversation Scoping** — lossless-claw scopes knowledge per-conversation only. Our dual-database (global/project) is more useful for knowledge spanning conversations
- **Sub-Agent Delegation for Deep Recall** — lossless-claw spawns sub-agents for DAG traversal. Adds latency and complexity; our direct MCP tool responses are simpler and faster
- **Message Parts Polymorphism** — lossless-claw's 10-column message_parts for tool calls, reasoning, patches. We don't store raw messages, so irrelevant
- **OpenClaw ContextEngine Interface** — Tight framework coupling. Our MCP + hooks approach is more portable
- **Chunk Strategy Option** — QMD's `--chunk-strategy auto` for code files. ClaudeMemory has no standalone chunking pipeline to configure (QMD v0.35.0)
- **Custom Instructions via Env Var** — lossless-claw's `LCM_CUSTOM_INSTRUCTIONS` config stub exists but is never wired to summarization prompts. Incomplete pattern; our skill-based prompts are better (lossless-claw v0.5.2)
- **OpenClaw Context Injection** — claude-mem v10.6.0's `appendSystemContext` with 60s cache replaces MEMORY.md writes. Our SessionStart hook context injection already does this (claude-mem v10.6.0)
- **Message Parts Polymorphism** — lossless-claw's 10-column message_parts for tool calls, reasoning, patches. We don't store raw messages, so irrelevant
- **OpenClaw ContextEngine Interface** — Tight framework coupling. Our MCP + hooks approach is more portable

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
- [claude-mem GitHub](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.6.3)
- [grepai GitHub](https://github.com/yoanbernabeu/grepai) - Semantic code search (v0.35.0)
- [claude-supermemory GitHub](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed memory (v2.0.1)
- [QMD GitHub](https://github.com/tobi/qmd) - On-device hybrid search engine (v2.0.1+unreleased)
- [KBS GitHub](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1)
- [lossless-claw GitHub](https://github.com/martian-engineering/lossless-claw) - DAG-based lossless context management (v0.5.2)

Influence documents:
- [docs/influence/qmd.md](influence/qmd.md) - Re-studied 2026-03-30
- [docs/influence/episodic-memory.md](influence/episodic-memory.md) - Re-studied 2026-03-30
- [docs/influence/claude-mem.md](influence/claude-mem.md) - Re-studied 2026-03-30
- [docs/influence/grepai.md](influence/grepai.md) - Re-studied 2026-03-30
- [docs/influence/claude-supermemory.md](influence/claude-supermemory.md) - Re-studied 2026-03-30
- [docs/influence/kbs.md](influence/kbs.md) - Re-studied 2026-03-30 (no changes)
- [docs/influence/lossless-claw.md](influence/lossless-claw.md) - Re-studied 2026-03-30

---

*Last updated: 2026-03-30 - Re-studied all 7 influencer repos. New improvements: CLAUDE_CONFIG_DIR support (#26), Usage Stats / ROI Tracking (#27). 7 new Features to Avoid entries. 14 features previously implemented through 2026-03-24.*
