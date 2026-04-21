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

### ~~26. CLAUDE_CONFIG_DIR Support~~ ✅ Implemented 2026-04-13

`Configuration#claude_config_dir` reads `CLAUDE_CONFIG_DIR` env var before falling back to `~/.claude`. `global_db_path` routes through it, so users with non-standard Claude Code config locations (or multiple profiles) can point the global memory DB anywhere without touching project DB resolution.

### 28. Code-Aware Transcript Chunking

Source: QMD v2.0.1+unreleased re-study (2026-03-30)

- **Value**: Better embeddings for transcripts containing code — detect fenced code blocks and apply AST-aware break points (function/class/import boundaries) rather than naive text splitting
- **Implementation**: Detect ` ```language ` fences in transcript content, parse code blocks with tree-sitter (via ruby_tree_sitter gem or shelling out), score break points (class=100, func=90, type=80, import=60), merge with markdown break points from #22
- **Evidence**: QMD `src/ast.ts` (392 lines) — web-tree-sitter with WASM grammars, `mergeBreakPoints()` combining AST + regex scores, graceful degradation on parse failure
- **Consideration**: Only useful in combination with #22 (Document Chunking). Transcripts often contain significant code in tool_use results and assistant responses
- **Effort**: 2-3 days (after #22)
- **Trade-off**: Adds tree-sitter dependency; graceful fallback to regex-only chunking when grammar unavailable

### ~~30. Predicate Census Command~~ ✅ Implemented 2026-04-20

`claude-memory census [--root DIR]` scans every `.claude/memory.sqlite3` under the root (plus the global DB unless `--no-global`), aggregates per-DB predicate × status counts, entity type counts, schema versions, novel predicates, and synonym candidates (Jaccard token overlap ≥ 0.4 against `PredicatePolicy.known_predicates`). Emits privacy-safe JSON — no object_literal, no entity names, no paths, no quotes; per-DB entries carry an SHA256-prefixed id rather than a path. Supports `--output FILE`, `--pretty`.

### ~~31. Relevance Ratio Metric for Eval Suite~~ ✅ Implemented 2026-04-20

Offline plumbing landed; the real-mode measurement will materialize the first time someone runs `EVAL_MODE=real` against the e2e suite.

- `Hook::ContextInjector` now exposes `emitted_fact_ids` / `emitted_subjects` reader accessors populated during `generate_context`. Existing callers unaffected — the context string return value is unchanged, tracking is a side channel.
- `BenchmarkHelpers::RelevanceMetrics` module in `spec/benchmarks/benchmark_helper.rb` adds `relevance_ratio(subjects, response)` — case-insensitive subject-substring match, deduped, returns 1.0 for empty-injection (keeps the metric monotone with recall semantics so it doesn't penalize abstention scenarios).
- `spec/benchmarks/e2e/devmemeval_spec.rb` captures injected subjects via a local `ContextInjector` against the scenario DB (same state in → same injection out — avoids having to scrape the running Claude process), computes the ratio against `result[:result]`, prints per-scenario `relevance=X.XX` alongside the existing score, and reports `avg relevance ratio` per ability group.

Response-side matching stays deliberately approximate — subject substring overlap. The metric is a trend signal (is memory being *applied*, not just retrieved), not a precision tool. Benchmark owner should sanity-check the first real-mode run and tighten the matcher if the ratios look implausibly high or low.

### 32. Repeat-Correction Benchmark

Source: Reflection 2026-04-17 (`docs/reflection_memory_as_accumulating_judgment.md`)

- **Value**: Cleanest memory-failure signal available. If the same correction is given twice across sessions, memory failed to propagate judgment — no retrieval metric captures this directly.
- **Implementation**: Add a multi-session scenario to `spec/benchmarks/e2e/`: session 1 applies a correction (e.g., "don't use Sequel.sqlite"), session 2 asks Claude to do something that would trigger the bad pattern and fails if it reappears. Track pass rate over time as a durable memory-health KPI.
- **Evidence**: The `feedback_hooks_run_installed_gem.md` and `gotcha_sequel_adapter.md` memories exist precisely because those corrections had to be made repeatedly. A benchmark formalizes that signal.
- **Effort**: 1 day (one scenario); 2–3 days (5–10 scenario set)
- **Trade-off**: Requires real-mode Claude runs (~cost); run nightly or on release, not per commit.

### ~~33. Conflict Cluster Audit — Fact 21 / 45 / 48~~ ✅ Implemented 2026-04-19/20

Audit completed inline during the dashboard Conflicts-tab work on 2026-04-19 and the cluster was eliminated via the resolver fixes shipped on 2026-04-20.

**Classification of the three anchor facts (all three were (b) distiller hallucination):**

- **Fact 21** (`repo uses_database sqlite`) — correct keeper. Contradictions came from CLAUDE.md example text ("this app uses PostgreSQL") being extracted as a literal claim. Fixed by rewriting the example in CLAUDE.md line 258 to self-describe the real stack ("claude_memory uses SQLite for storage") — commit `61666bc`.
- **Fact 45** (`repo uses_framework rails`) — correct keeper. Contradictions were artifacts of the `uses_framework` single→multi reclassification in 0.9.0; `claude-memory restore --predicate uses_framework` already exists for this case (0.9.0 CHANGELOG).
- **Fact 48** (`repo deployment_platform aws`) — correct keeper. Contradictions from platform-mention hallucinations; no further resolution machinery needed beyond rejecting contradicting rows.

**Delivered cleanup**: bulk-reject-similar UI in the Conflicts modal (commit `61666bc`), resolver dedup (commit `f571ba4`), scope-leakage fix (commit `50cf02e`). Project DB conflict count dropped from 31 → 15 during the session via bulk-reject, with further shrinkage from the dedup + scope passes. Going forward, the resolver's dedup and the CLAUDE.md rewrite prevent the same cluster from regenerating.

No separate `docs/conflict_audit_2026-04.md` file written — the classification and resolution are preserved in the relevant commit messages and memory entries.

### ~~34. "Why" Preservation Audit~~ ✅ Implemented 2026-04-20

Audit of 20 random project facts showed ~25% embed reasoning, ~75% are bare conclusions — a material gap. Updated two extraction surfaces to require a reason clause for `decision` and `convention` predicates:

- `lib/claude_memory/commands/skills/distill-transcripts.md` — added reasoning requirement to the Facts section, with contrasting ❌ bare / ✅ with-why examples drawn from the audit sample, plus a prefer-one-fact-with-reason-over-two-without guideline.
- `lib/claude_memory/hook/context_injector.rb#format_distillation_prompt` — added a **Reasoning requirement** block to the SessionStart extraction prompt that ships with every fresh session; locked in by a new spec assertion so the contract can't silently regress.

No schema change. Reasoning rides in `object_literal`. The plugin-copy mirror (`.claude-plugin/commands/distill-transcripts.md`) was left alone — it's already out of sync with the source skill on the predicate list and is manually maintained; a separate improvement should reconcile it.

### 36. Auto-Mirror Auto-Memory Observations into claude_memory on SessionStart

Source: Session 2026-04-20 retrospective

- **Value**: Close the loop between the two memory systems. Today, auto-memory files (`~/.claude/projects/.../memory/*.md`) are the authoritative, prose-shaped home for gotchas and feedback, but they don't flow into the gem's fact DB unless someone explicitly calls `memory.store_extraction`. Claude (the model) can't reach auto-memory observations via `memory.conventions` / `memory.recall` / semantic recall until they're mirrored. Proactive guidance in the MCP instructions tells Claude to "check memory before writing code" — but it only checks claude_memory, not auto-memory. The gap means high-signal observations (WAL stale-cache, FTS5 rank rot, scope_hint not routing, four-surface staleness) sit unsearchable in auto-memory until a session happens to touch the same code path and I remember to mirror them.
- **Implementation**: Extend `Hook::ContextInjector` (the SessionStart hook that's already doing three-layer distillation). Today Layer 2 injects undistilled transcript content with an extraction prompt. Add a companion pass: diff `~/.claude/projects/.../memory/MEMORY.md` + the linked files against the last run's snapshot, emit new/changed entries as a targeted `memory.store_extraction` candidate list (subject + predicate + compact-object + scope_hint). Claude then confirms/declines via the normal extraction flow — same review discipline applies, no blind mirror. State file: `.claude/auto_memory_mirror.json` with the last-seen mtime + md5 per file. Idempotent — unchanged files are skipped. Runs once per session.
- **Evidence**: This session mirrored 6 high-signal gotchas manually (`memory.store_extraction` call in commit window after the retrospective). Before the mirror, `memory.conventions` didn't surface the WAL-stale-cache or FTS5-rank findings — future sessions would re-encounter the same "malformed" errors with no memory hit. After the mirror, they surface alongside the other conventions.
- **Effort**: 1 day (diff + state file + extraction-candidate emitter); 0.5 day test coverage (fixture auto-memory file, assert extraction suggested once, not on re-run). 0.5 day for a dashboard indicator showing "N auto-memory entries awaiting mirror" so the user knows when there's pending catch-up to review.
- **Trade-off**: (1) Mirror requires LLM extraction per new entry — real session cost, though bounded to new/changed files. (2) Two sources of truth risk: claude_memory mirror drifts from auto-memory authoritative. Mitigation: mirror is one-way (auto-memory → claude_memory), never the reverse; auto-memory stays canonical for human-readable prose with full `**Why:**` / `**How to apply:**` structure. (3) Confirmation prompt cost — extraction candidates should be high-quality so the user isn't burned by false positives. Bias conservative (suggest fewer, higher-signal) rather than aggressive.
- **Prior context**: improvement #34 ("Why" preservation audit) and this improvement are related — both about making sure the reasoning structure survives extraction. If #34 lands first, the extraction candidates emitted here should inherit its require-a-reason-clause discipline.

### 35. Access-Based Staleness Scoring — **Deferred, pending concrete signal**

Source: Reflection 2026-04-17 (Theory 2: decisions have half-lives)

**Prior context that makes this a harder call than it looks:** the 0.9.0 telemetry design deliberately dropped `query_text` / `query_hash` from `mcp_tool_calls` (CHANGELOG 0.9.0; memory `decisions`: *"deliberately no query_text or query_hash. YAGNI — hashes are write-only without the raw text, and raw text adds privacy concerns without clear value beyond existing shortcut tools"*). Adding per-fact access timestamps reopens the same privacy/value tension — we'd be recording "this user looked at this fact at this time," which is telemetry shaped roughly like what we already rejected.

- **Value (if the signal materializes)**: Today `valid_from`/`valid_to` gate facts binarily; nothing tracks whether a fact is *used*. Access-based decay would turn staleness from passive (wait for supersession) into measurable (facts untouched in N sessions flagged as sweep candidates).
- **Trigger to revisit**: a `memory.stats --stale` or similar report that *without* access data shows facts nobody is touching but nobody has superseded either — i.e. concrete dead weight we can't diagnose with current telemetry. If stats show the problem, the trade-off shifts.
- **If built**: `last_recalled_at` column on `facts`, updated via an update-buffer (not per-recall writes — WAL contention on a 100-writes-per-session pattern is real, not hand-wavy). Flags surface via `memory.stats`; no auto-deletion. Effort ~3 days with the write-buffer honestly scoped.
- **For now**: deferred. The gap this would close (stale-but-not-superseded facts) is not yet a documented pain — we have plenty of hallucination-driven conflict pain which a separate, already-listed improvement addresses. Revisit after #32 (repeat-correction benchmark) produces data on whether stale facts are actually hurting.

### ~~27. Usage Stats / ROI Tracking~~ ✅ Implemented 2026-04-15

Schema migration v13 adds `mcp_tool_calls` telemetry table (tool_name, called_at, duration_ms, result_count, scope, error_class). `MCP::Telemetry` wraps `Server#handle_tools_call` with monotonic-clock timing, captures errors, and records to the project DB; DB errors are swallowed so telemetry never fails a real tool call. `StatsCommand` gains `--tools` and `--since DAYS` flags showing total calls, error rate, and per-tool breakdown (calls, avg ms, p95 ms, error rate). `Sweep::Maintenance#prune_old_mcp_tool_calls` enforces a 90-day retention window, wired into `Sweeper#run!`. Rejected NDJSON in favor of SQLite for schema/query consistency with the rest of the gem. Dropped query-text capture (YAGNI — the dedup insight the hash would enable also needs raw text). Also fixed a latent bug where `StatsCommand` opened the DB via `Sequel.sqlite` (requiring the unlisted `sqlite3` gem); now uses the extralite adapter consistently.

---

## Low Priority / Defer

### ~~29. Derive CompletionCommand Descriptions from Registry~~ ✅ Implemented 2026-04-15

`Registry::COMMANDS` now stores `{class:, description:}` entries as the single source of truth. New `Registry.description` and `Registry.descriptions` accessors. `CompletionCommand` reads descriptions via `Registry.descriptions` instead of maintaining its own parallel hash. `Registry.find` also simplified — class references stored directly since command files are required before the Registry, eliminating `const_get` string indirection. Drift between the command list and completion output is now impossible without a deliberate edit to a single file.

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

*Last updated: 2026-04-15 - Predicate retrospective: fixed uses_framework cardinality bug, curated vocabulary to 8 predicates, added synonym canonicalization + novel-predicate warnings. Also: reject/restore commands, #26 CLAUDE_CONFIG_DIR, #27 telemetry, #29 Registry descriptions.*
