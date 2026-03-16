# Improvements to Consider

*Updated: 2026-03-16 - Studied lossless-claw (v0.3.0). New findings: depth-aware prompt templates, three-level escalation pattern, tool escalation workflow. Other 6 repos unchanged since 2026-03-10.*
*Sources:*
- *[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.5.5, studied 2026-03-09)*
- *[obra/episodic-memory](https://github.com/obra/episodic-memory) - Semantic conversation search (v1.0.15, studied 2026-03-09)*
- *[yoanbernabeu/grepai](https://github.com/yoanbernabeu/grepai) - Semantic code search (latest, studied 2026-03-09)*
- *[supermemoryai/claude-supermemory](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed persistent memory (v2.0.1, studied 2026-03-09)*
- *[tobi/qmd](https://github.com/tobi/qmd) - On-device hybrid search engine (v2.0.1, studied 2026-03-10)*
- *[MadBomber/kbs](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1, studied 2026-03-09 — no changes)*
- *[martian-engineering/lossless-claw](https://github.com/martian-engineering/lossless-claw) - DAG-based lossless context management (v0.3.0, studied 2026-03-16)*

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

### ~~4. MCP Tool Annotations~~ ✅ Implemented 2026-03-09

Added `readOnlyHint`, `idempotentHint`, `destructiveHint` annotations to all 21 MCP tools via shared constants (READ_ONLY, WRITE, WRITE_IDEMPOTENT). 17 query tools marked read-only, store_extraction/sweep_now as write, promote as write-idempotent.

### 5. Retrieval Score Traces ⭐

Source: QMD v1.1.5 study (2026-03-09)

- **Value**: Transparency into why facts were retrieved — FTS score, vector similarity, RRF contribution, final blend
- **Implementation**: Add optional `explain: true` param to recall tools, return score breakdown per result. Enhances `memory.explain` and `memory.recall_details`
- **Evidence**: QMD `store.ts:2477-2540` — `--explain` flag with per-document RRF contribution traces
- **Effort**: 2 days
- **Recommendation**: ADOPT

### ~~6. MCP Stdout Protection Audit~~ ✅ Implemented 2026-03-09

ServeMcpCommand captures real stdout for MCP transport, redirects `$stdout` to `$stderr` during serve. Accidental puts/print from gems goes to stderr. Restore via ensure block.

### ~~7. Worktree-Aware Git Root Detection~~ ✅ Implemented 2026-03-09

Configuration#project_dir uses `git rev-parse --git-common-dir` to resolve main repo root across worktrees. `CLAUDE_MEMORY_ISOLATE_WORKTREES` env var opts into per-worktree isolation. Uses Open3.capture2 with graceful fallback to Dir.pwd.

### 8. Search Agent Delegation Pattern ⭐

Source: episodic-memory study (2026-03-09)

- **Value**: Save 50-100x main-agent context by delegating memory search to a subagent that chains recall → explain → fact_graph
- **Implementation**: Create `agents/memory-recall.md` subagent definition in plugin that chains our MCP tools and synthesizes results
- **Evidence**: episodic-memory `agents/search-conversations.md:1-162` — subagent-delegated search pattern
- **Effort**: 1-2 days
- **Recommendation**: ADOPT

### ~~9. Self-Excluding Agent Conversations~~ ✅ Implemented 2026-03-09

Added `SELF_CONTEXT_MARKER` constant (`claude-memory-self`) to ClaudeMemory module. Added to ingester EXCLUSION_TAGS. Transcripts containing `<claude-memory-self>` are skipped entirely, preventing meta-conversation pollution.

### ~~10. Dedicated Maintenance Class~~ ✅ Implemented 2026-03-16

Extracted `Sweep::Maintenance` class from Sweeper with 8 individual operations, each returning affected counts: `expire_proposed_facts`, `expire_disputed_facts`, `prune_orphaned_provenance`, `prune_old_content`, `backfill_vec_index`, `cleanup_vec_expired`, `checkpoint_wal`, `vacuum`. Sweeper now delegates to Maintenance internally.

### 11. Dynamic MCP Instructions Enhancement ⭐

Source: QMD v2.0.1 study (2026-03-10)

- **Value**: QMD v2.0 builds rich MCP server instructions with collection stats, document counts, capability gaps, search examples, and retrieval workflow tips. Our MCP server has a static query guide prompt but no dynamic instructions
- **Implementation**: Add `build_instructions` to MCP server that generates dynamic instructions with: fact counts (global/project), active conflict count, recent decision count, convention count, database health, and usage tips
- **Evidence**: QMD `src/mcp/server.ts:92-152` — `buildInstructions()` with collections, counts, gaps, examples, tips
- **Effort**: 1 day
- **Recommendation**: ADOPT

### 12. Embedded Skill Distribution ⭐

Source: QMD v2.0.1 study (2026-03-10)

- **Value**: `qmd skill install` copies packaged skill files to `~/.claude/commands/` — zero-config setup. Skills are embedded as base64 in source code and extracted at install time
- **Implementation**: Add `claude-memory install-skill` command that writes our memory recall agent to `~/.claude/commands/memory-recall.md`. Embed skill content in a Ruby constant. Pairs with Search Agent Delegation Pattern (#8)
- **Evidence**: QMD `src/embedded-skills.ts:1-22` — base64-encoded SKILL.md + references; CLI `skill install` command
- **Effort**: 1-2 days
- **Recommendation**: ADOPT

### 13. Depth-Aware Prompt Templates for Distiller ⭐

Source: lossless-claw v0.3.0 study (2026-03-16)

- **Value**: Graduated extraction prompts based on context depth — fresh conversations get detailed extraction, well-established facts get consolidation prompts. Parallels lossless-claw's leaf/d1/d2/d3+ prompt hierarchy
- **Implementation**: Create prompt templates for distiller stages: initial extraction (detailed), re-extraction (consolidation), contradiction resolution (focused). Use depth/freshness to select template
- **Evidence**: `tui/prompts/leaf.tmpl`, `tui/prompts/condensed-d1.tmpl`, `condensed-d2.tmpl`, `condensed-d3.tmpl` — four distinct prompt templates with increasing abstraction
- **Effort**: 1-2 days (when building real distiller)
- **Recommendation**: ADOPT

### ~~14. Three-Level Escalation for Sweep/Maintenance~~ ✅ Implemented 2026-03-16

Added `run_with_escalation!` to Sweeper: normal (standard TTLs) → aggressive (halved TTLs) → fallback (force-expire oldest 10 proposed/disputed). Stats include `:escalation_level`. MCP `memory.sweep_now` gains `escalate: true` parameter. TextSummary shows escalation level in output.

### ~~15. Tool Escalation Workflow in MCP Instructions~~ ✅ Implemented 2026-03-16

Restructured QueryGuide with 4-tier escalation hierarchy (Fast Lookup → Broad Search → Targeted Deep Dive → Relationship Exploration). Each tool annotated with cost estimates (tokens per call). Added "Recommended Workflow" section. InstructionsBuilder usage hint updated with escalation guidance.

### 16. Structured Error Classification

Source: claude-supermemory v2.0.1 study (2026-03-09)

- **Value**: Clean error handling in MCP server and hooks — benign errors silent, retryable logged, fatal with clear messages
- **Implementation**: Three-tier classification: benign (empty results, first use), retryable (rate limits, server errors), fatal (auth failures, schema corruption)
- **Evidence**: supermemory `src/lib/error-helpers.js:1-72` — error classification with user-friendly messages
- **Effort**: 1 day
- **Recommendation**: ADOPT

### 17. Entity Context Extraction Prompts

Source: claude-supermemory v2.0.1 study (2026-03-09)

- **Value**: Structured prompt templates for distiller defining what to extract (decisions, preferences, conventions) vs what to skip
- **Implementation**: Apply when replacing NullDistiller. Rich prompt with concrete examples in table format, separate personal vs repo context
- **Evidence**: supermemory `src/lib/supermemory-client.js:21-58` — extraction prompts with examples
- **Effort**: 1-2 days (when building real distiller)
- **Recommendation**: ADOPT — template for distiller replacement

---

## Medium Priority

### 18. Shell Completion for CLI

Source: grepai study (2026-03-09)

- **Value**: Tab completion for commands and flags in zsh/bash
- **Implementation**: Generate completion scripts from OptionParser. Dynamic completions for project names
- **Evidence**: grepai `cli/completion.go` — static + dynamic completions
- **Effort**: 1-2 days
- **Recommendation**: CONSIDER

### 19. Content-Addressed Deduplication for Embeddings

Source: grepai study (2026-03-09)

- **Value**: Skip re-embedding unchanged content using existing `text_hash` in `content_items`
- **Implementation**: Check `text_hash` before computing embeddings; reuse cached vectors for identical content
- **Evidence**: grepai `store/store.go:105-109` — EmbeddingCache interface
- **Effort**: 1 day
- **Recommendation**: CONSIDER — quick win, infrastructure already exists

### 20. Deduplication Before Vector Scoring

Source: QMD v1.1.5 study (2026-03-09)

- **Value**: Free performance win — deduplicate fact texts before computing cosine similarity, map scores back
- **Implementation**: In `VectorIndex#search`, group facts by text, score unique texts only, fan out results
- **Evidence**: QMD `llm.ts:1098-1109` — reranker deduplication (identical chunks scored once, fanned out)
- **Effort**: 1 day
- **Recommendation**: CONSIDER

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
- [QMD GitHub](https://github.com/tobi/qmd) - On-device hybrid search engine (v2.0.1)
- [KBS GitHub](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1)
- [lossless-claw GitHub](https://github.com/martian-engineering/lossless-claw) - DAG-based lossless context management (v0.3.0)

Influence documents:
- [docs/influence/qmd.md](influence/qmd.md) - Updated 2026-03-10
- [docs/influence/episodic-memory.md](influence/episodic-memory.md) - Updated 2026-03-09
- [docs/influence/claude-mem.md](influence/claude-mem.md) - Updated 2026-03-09
- [docs/influence/grepai.md](influence/grepai.md) - Updated 2026-03-09
- [docs/influence/claude-supermemory.md](influence/claude-supermemory.md) - Updated 2026-03-09
- [docs/influence/kbs.md](influence/kbs.md) - Updated 2026-03-09 (no changes)
- [docs/influence/lossless-claw.md](influence/lossless-claw.md) - Updated 2026-03-16

---

*Last updated: 2026-03-16 - Implemented 3 features: Dedicated Maintenance Class (#10), Three-Level Escalation (#14), Tool Escalation Workflow (#15). Studied lossless-claw (v0.3.0), added Depth-Aware Prompt Templates (#13). Previously: Re-studied QMD (v2.0.1). Added Dynamic MCP Instructions Enhancement (#11), Embedded Skill Distribution (#12), REST API Endpoint (#23). Implemented: MCP Tool Annotations, MCP Stdout Protection, Worktree-Aware Git Root, Self-Excluding Conversations, Plugin Distribution, sqlite-vec, Database Compact, Fact Export, Background Processing, MCP Discovery Tools.*
