# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.11.0] - 2026-04-30

Theme: **Trust & Cost** — five user-visible signals that answer "is memory still worth it?" with numbers a skeptical user can read in <30 seconds.

### Added

- **Token budget telemetry** — every successful SessionStart context injection now records an estimated `context_tokens` count on its `activity_events` row. Surfaced three ways:
  - Dashboard Trust panel emits a `token_budget` block with p50/p95/avg/sample_size over the last 30 days, so the JSON dashboard endpoint and any downstream consumer answer "what does memory cost per session?"
  - `claude-memory digest` includes a "Context cost" subsection between activity and new-knowledge so the weekly report shows the price tag next to the value.
  - `claude-memory stats --tokens [--since DAYS]` reports total sessions, p50/p95/avg/min/max, and a histogram across <500 / 500-1k / 1-2k / 2-5k / 5k+ buckets.
- Pure additive — no schema migration. Historical events written before this release simply contribute zero samples until new injections accumulate.
- First 0.11.0 milestone item from the 1.0 punchlist (Trust & Cost). Closes the "what % of my SessionStart token budget does memory consume?" gap.
- **Hallucination rate metric** — the dashboard now quantifies how clean the fact base is, not just how full it is. `Distill::BareConclusionDetector` is the production-side mirror of the SessionStart prompt's reason-clause requirement (decision/convention facts must embed "because…" / "so that…" / "to avoid…"). Surfaced two ways:
  - Dashboard Trust panel emits a `quality_score` block aggregating across project + global active facts: `suspect_count` (predicate=reference, retagged by ReferenceMaterialDetector), `bare_conclusion_count`, percentages, and an overall 0–100 score (higher = cleaner). Returns 100 on empty stores so fresh installs aren't penalized.
  - `claude-memory digest` includes a "Quality" section showing the score breakdown plus the in-window rejection rate ("of facts created in the last 7 days, X% have been rejected since"), so calibration drift is visible.
- Second 0.11.0 milestone item. Pairs with token-budget telemetry to answer "is memory still worth its cost?" via two skeptic-friendly numbers.
- **`claude-memory show`** — new CLI command prints what memory would inject at the next SessionStart in plain Markdown. Runs the exact `Hook::ContextInjector` path real sessions use, so output matches what Claude actually receives. Footer reports fact count, ~token estimate, and char count so users see the SessionStart cost at a glance.
  - Default suppresses the raw-transcript "Pending Knowledge Extraction" dump (intended for LLM distillation, not human reading); pass `--pending` to include it.
  - `--source SOURCE` (startup/resume/clear) simulates each fresh-session entrypoint so users can preview which sections would appear.
- Third 0.11.0 milestone item. Closes the inspectability gap — trust requires being able to see what memory will inject, the same way `cat CLAUDE.md` works.
- **First-week ROI nudge** — at SessionEnd, memory now prints `memory contributed N facts this session, %used = X` for the first 10 sessions, then quiets. New users get user-visible proof memory is doing work for them without having to know about the dashboard. Once trust is established (or it isn't), the nudge gets out of the way.
  - New `claude-memory hook nudge` subcommand + `Hook::Handler#nudge`. SessionEnd config now wires `[ingest, sweep, nudge]` in order.
  - Silent on `CLAUDE_MEMORY_NO_NUDGE=1` opt-out, missing session_id, n=0 contributions, and after MAX_NUDGES emissions. The empty-session silent path doesn't burn a slot — quiet sessions don't count toward the 10.
  - Activity event `roi_nudge` records `{n, used, pct, prior_count}` per emission so a future migration could change the threshold without re-counting from raw events.
- Fourth 0.11.0 milestone item. Cold-start trust signal that pairs with #47 (token cost) and #48 (quality) to make the first-week answer to "is this worth it?" visible without effort.
- **Harm benchmark prototype** — `spec/benchmarks/dataset/harm_scenarios.yml` + `spec/benchmarks/e2e/harm_bench_spec.rb`. Three hand-written cases spanning the riskiest harm classes (stale_tech, mismatched_scope, superseded_undetected). The first ClaudeMemory benchmark that measures whether memory can make Claude *wrong* — every other benchmark only measures whether memory helps.
  - Structure validation (regex compile, fact loadability, harm-class coverage) runs in stub mode as part of `:benchmark` tag.
  - Real-mode runner: `EVAL_MODE=real bundle exec rspec spec/benchmarks/e2e/harm_bench_spec.rb` — needs `claude` CLI on PATH, ~$2-8 per run. Reports harm rate; doesn't enforce a threshold yet (that's the 0.12 release gate).
- 0.11.0 risk-de-risking item. If even one of these three surfaces a harm now, the full 10-15-case benchmark planned for 0.12 will likely reveal a fundamental issue — better to learn that at 0.11 than at 0.12. **Real-mode prototype run on 2026-04-30 reported 0/3 harm** — green light to expand to the full corpus in 0.12.

### Changed

- **Hallucination-rate metric calibration** — `Dashboard::Trust#quality_score` now reports a windowed (last 30d) "live" score as the headline plus a "historical" block over all active facts. Production verification on 2026-04-30 (recorded in `docs/quality_review.md`) showed the unwindowed metric was technically correct but pragmatically misleading: 97% of bare-conclusion facts pre-dated the 2026-04-20 reason-clause prompt commit, and the entire 7-day rejection cluster was a single-class systemic failure (a `/study-repo` burst), not ongoing noise. The split makes the metric actionable: live score = ongoing extraction quality, historical = legacy data. The digest's "Quality" section uses the live score as the headline.

### Fixed

- Real-eval CLI runner now passes `allowed_tools` through explicitly so the harm benchmark and other real-mode benches can pre-allow MCP memory tools without per-test wiring.

### Upgrade Notes

- No schema migration. All new features ship purely additive.
- Hooks run the installed gem from PATH, not the working tree. After upgrading, `bundle exec rake install` (or `gem install claude_memory`) is required for the new SessionEnd nudge, `claude-memory show` command, `--tokens` stats flag, and `context_tokens` activity-event field to actually fire on real hook events.
- Existing `quality_score` consumers will see additional fields (`window_days`, `historical`) in the snapshot. The original keys (`score`, `total_active`, `suspect_count`, `bare_conclusion_count`, `suspect_pct`, `bare_pct`) remain at the top level and now reflect the 30-day live window — historical numbers move to the `historical` sub-hash.

## [0.10.0] - 2026-04-28

### Added

**Dashboard — feed-first redesign with observability built in**

- New feed-first dashboard UI with scope-aware moments, fact detail modal, query tester, and activity drilldown. Reuse, Trust, Knowledge, Conflicts, and Moments panels each backed by a dedicated module (`Dashboard::{Reuse, Trust, Knowledge, Conflicts, Moments}`) under unit tests, replacing the prior all-in-API-class layout.
- 👍/👎 feedback on individual moments with persisted verdicts (schema v16, `moment_feedback` table). Trust panel surfaces a 30-day up/down ratio so the dashboard can answer "when memory surfaces something, are users marking it useful?".
- Utilization ratio panel — of facts extracted in the last 30 days, how many has Claude actually used in a recall or context injection? Color-coded (green ≥40%, yellow ≥15%, red below). Hidden on fresh installs to avoid misleading zeros.
- Conflict deduping at the display layer: identical (subject, predicate, object_pair) detections collapse into one row with a `×N` badge. Sidebar "Needs review" count now reflects distinct contradictions, not raw row count.
- Activity events drilldown: each moment opens a payload modal with prettified JSONL, recall trigger correlation (which user prompt motivated this lookup), and linked-fact resolution scoped per database.
- Vector index health threshold and clickable remediation hints in the health dashboard.

**CLI — observability surfaces and one-shot cleanups**

- `claude-memory digest [--since DAYS] [--output FILE]` — weekly markdown report. Sections: Activity, New knowledge by predicate, Utilization (extracted vs used), Conflicts, Feedback. No new schema; renders from existing aggregates.
- `claude-memory census [--root DIR]` — privacy-safe cross-project vocabulary scan. Aggregates per-DB predicate × status counts, novel predicates, synonym candidates. Suppresses object literals, entity names, and paths; per-DB IDs are SHA256-prefixed.
- `claude-memory dedupe-conflicts [--scope SCOPE] [--dry-run]` — one-shot cleanup for historical conflict-row duplication that predates the Resolver dedup fix (commit f571ba4). Groups by (subject, predicate, normalized object pair), keeps the earliest, migrates provenance to the keeper.
- `claude-memory reclassify-references [--scope SCOPE] [--dry-run]` — retags active convention facts that the new `Distill::ReferenceMaterialDetector` flags as reference material (LOC counts, star counts, "X is a plugin..." templates, "by Firstname Lastname" attributions).

**Memory quality**

- Access-based staleness scoring (improvements.md #35). Schema v17 adds `last_recalled_at` to facts. `Sweep::RecallTimestampRefresher` derives the field periodically from activity_events; `claude-memory stats --stale [--stale-days N]` lists facts that haven't been recalled inside the threshold. Replaces the prior "active facts minus seen-in-recalls" approximation.
- Auto-memory mirror (improvements.md #36). On fresh sessions, the SessionStart context hook scans `~/.claude/projects/<slug>/memory/*.md` and surfaces new or changed entries as extraction candidates so users can promote auto-memory observations into claude_memory without manual copy-paste.
- Reasoning requirement enforced in distillation (improvements.md #34). The SessionStart prompt and the `/distill-transcripts` skill now require a why clause for `decision` and `convention` predicates ("because…", "so that…", etc.). Audit found ~75% of facts were bare conclusions before this change.
- `Distill::ReferenceMaterialDetector` reclassifies convention facts whose object text matches reference patterns. New `reference` predicate registered in `PredicatePolicy` with its own `:references` snapshot section. Detector runs at write time in `ManagementHandlers#store_extraction` so mislabeling can't persist.
- Predicate census command (#30) for cross-project vocabulary audits — see CLI section above.

**Benchmarks and observability**

- Repeat-correction benchmark harness (improvements.md #32). `spec/benchmarks/e2e/repeat_correction_spec.rb` pre-loads a past correction as a memory fact, runs the prompt through real Claude under `EVAL_MODE=real`, and reports pass rate (no violation patterns matched). Starter set of 2 scenarios drawn from this project's recurring gotchas.
- Relevance ratio metric (improvements.md #31). `Hook::ContextInjector#emitted_subjects` exposes the subjects injected at SessionStart; `BenchmarkHelpers::RelevanceMetrics` measures whether they appear in Claude's response. Trend signal for memory-application quality, integrated into `devmemeval_spec.rb`.
- MCP server embeds the V=R/C ("Verify before Recommend / Correct") mental model in agent instructions so memory recommendations come with built-in verification cues.

**Schema v15 → v17 (additive only, automatic on first run)**

- Migration 015: adds `activity_events` table for hook/recall/context/sweep telemetry. Powers the dashboard timeline, moments feed, and efficacy reports.
- Migration 016: adds `moment_feedback` table (unique on event_id) for the dashboard 👍/👎 surface.
- Migration 017: adds nullable `facts.last_recalled_at` for access-based staleness scoring.

**1.0 readiness track**

- New `docs/1_0_punchlist.md` opens the path to 1.0: token-budget telemetry, hallucination-rate metric, negative-fact harm benchmark, CLAUDE.md baseline publication, `claude-memory show`, benchmark scoreboard. Ten entries (#47-56) added to `docs/improvements.md` with concrete file:line plumbing notes.

### Changed

- `Resolver#apply_conflict` no longer creates a duplicate disputed fact + conflict row when the same contradicting value is re-extracted. Looks up disputed facts in the same (subject, predicate) slot and reinforces with provenance instead.
- `Resolver` no longer treats the distiller's `scope_hint` as a scope override. `scope_hint` is advisory metadata; `fact.scope` must match the DB the row lives in. Earlier behavior caused scope leakage where global-hinted distillations landed in the project DB.
- `Hook::ContextInjector` adds `emitted_fact_ids` and `emitted_subjects` accessors so benchmark harnesses can attribute injection contributions per session.
- `SQLiteStore` decomposed via module inclusion: `LLMCache` and `MetricsAggregator` extracted into `lib/claude_memory/store/`. SQLiteStore back under 600 LOC.
- `Dashboard::API` decomposed: `FactPresenter`, `Conflicts`, `Efficacy::Reporter`, `Timeline`, `Health` extracted into dedicated classes following the boundary pattern. API now routes/delegates rather than aggregating.
- Dashboard releases DB connections after each HTTP request (was holding connections open for the lifetime of the WEBrick session).
- `Sweep::Maintenance` gains `dedupe_open_conflicts` and `reclassify_references` for the one-shot CLI commands above.
- Round-trip migration specs from v12, v13, v14 → v17 (per-version migrations covered by `spec/claude_memory/store/migrations/`). Codifies the release-blocker convention: any schema bump must round-trip from each prior major-release boundary back ~3 releases.

### Fixed

- Dashboard surfaces an actionable hint when Recall hits FTS5 corruption (run `claude-memory compact` rather than a generic error).
- Dashboard query tester unwraps the nested Recall result shape rather than printing the raw envelope.
- Dashboard health checks correctly detect the claude-memory hook installation across the two-level Claude Code hooks structure (was reporting false negatives when hooks were installed under a matcher block).
- Dashboard Efficacy "this session" correlation falls back to a time window when the recall event has no `session_id` (MCP tool calls don't thread session_id).
- Bulk-reject in the Conflicts modal now retries with an actionable message when the server-side state is stale.

### Upgrade Notes

**Schema bump v14 → v17.** Three migrations run automatically on first launch after upgrade. All three are additive (no existing data is rewritten):

1. Migration 015 creates `activity_events` (hook/recall telemetry).
2. Migration 016 creates `moment_feedback` (dashboard verdicts).
3. Migration 017 adds `facts.last_recalled_at` (NULL by default; `Sweep::RecallTimestampRefresher` populates it on the next sweep cycle from existing activity_events).

The migration delta has round-trip spec coverage in `spec/claude_memory/store/migrations/`. Forward-compatibility: 0.10.0 databases cannot be opened by 0.9.x or earlier. Downgrade is destructive — back up `~/.claude/memory.sqlite3` and `.claude/memory.sqlite3` before downgrading.

**Optional historical cleanups.** Two new admin commands address data tails left by earlier bugs that have since been fixed at the source:

```bash
claude-memory dedupe-conflicts --dry-run   # preview duplicate conflict rows
claude-memory dedupe-conflicts             # consolidate them
claude-memory reclassify-references --dry-run   # preview reference-material mislabels
claude-memory reclassify-references             # retag them
```

Both are opt-in. Neither runs in the regular sweep cycle. Use `--scope global` to clean the global DB.

**Telemetry footprint.** The `activity_events` table grows with hook activity. The dashboard surfaces this by default and powers the timeline/moments/efficacy panels. Retention pruning is not yet automatic (planned for a follow-up); manual cleanup via `DELETE FROM activity_events WHERE occurred_at < ?` is safe — the dashboard tolerates missing history.

## [0.9.1] - 2026-04-16

### Fixed

- MCP server now conforms to JSON-RPC 2.0: notifications (messages without an `id`) never receive a response. Previously, `notifications/initialized` — which Claude Code sends after every handshake — triggered a spurious `Method not found` error frame, causing strict MCP clients to mark the server failed on `/mcp` reconnect after the initial connection.

## [0.9.0] - 2026-04-16

### Added

- `claude-memory reject <id_or_docid>` command + `memory.reject_fact` MCP tool — explicitly mark distiller hallucinations as wrong, closing associated conflicts
- `claude-memory restore --predicate NAME` command — recover facts that were superseded by obsolete single-value predicate classifications (uses Jaccard-based token overlap to distinguish bug-caused supersession from real corrections)
- MCP tool-call telemetry: `mcp_tool_calls` table records every tool invocation with timing, result counts, and error classification. `claude-memory stats --tools [--since DAYS]` for usage reporting. 90-day retention via Sweep
- `CLAUDE_CONFIG_DIR` env var support for non-standard Claude Code config locations
- Predicate synonym canonicalization at insert time (`has_convention` → `convention`, `primary_language` → `uses_language`). Prevents drift from fragmenting the knowledge graph
- Novel predicate warnings at insert time — logged when the Resolver encounters a predicate not in PredicatePolicy
- NullDistiller now emits `uses_language` facts for detected language entities
- Proactive memory recall guidance in MCP instructions — Claude now checks conventions before code generation, architecture before explanations, decisions before refactoring
- YARD documentation across 13 core source files (+473 lines)

### Changed

- **`uses_framework` reclassified as multi-value** — real projects use multiple frameworks (Rails + Turbo + Tailwind). The prior single-value classification silently superseded valid facts in production databases. Run `claude-memory restore --predicate uses_framework` to recover affected facts
- `PredicatePolicy` is now the single source of truth for predicate vocabulary, snapshot section mapping, synonym canonicalization, and LLM guidance. `tool_definitions.rb`, `publish.rb`, and `distill-transcripts.md` all derive from the policy
- Predicate vocabulary curated from 13 → 8 based on multi-project usage data. Removed predicates (`preference`, `workflow`, `dependency`, `testing_strategy`, `tool_usage`, `ci_platform`, `primary_language`) had zero facts across all surveyed databases. They still work via DEFAULT_POLICY but are no longer advertised to the LLM
- `Registry::COMMANDS` stores `{class:, description:}` entries with direct class references instead of string class names
- Plugin and gem descriptions rewritten from mechanism-focused to outcome-focused

### Fixed

- **`StatsCommand` broken in production** — used `Sequel.sqlite` which requires the unlisted `sqlite3` gem. Now uses the extralite adapter consistently
- Missing `embeddings` command in shell completion output

### Upgrade Notes

**Schema**: v12 → v14 (two automatic migrations). Migration 013 adds `mcp_tool_calls` table. Migration 014 canonicalizes stale predicate names (`has_convention` → `convention`, `primary_language` → `uses_language`) in existing facts.

**Action required for `uses_framework` recovery**: If your project uses multiple frameworks (Rails + Turbo + Tailwind, etc.), past sessions may have superseded valid facts. After upgrading, run:

```bash
claude-memory restore --predicate uses_framework --dry-run   # preview
claude-memory restore --predicate uses_framework              # restore
claude-memory restore --predicate uses_framework --scope global  # if needed for global DB
```

**Pruned predicates still work**: `preference`, `workflow`, `dependency`, `testing_strategy`, `tool_usage`, `ci_platform` fall through to the default multi-value policy. Existing facts with these predicates are unaffected. They'll appear as "novel" in `memory.stats` but function normally.

## [0.8.0] - 2026-03-30

### Added

**Three-Layer Distillation Pipeline**
- Automatic distillation via NullDistiller in ingest pipeline (Layer 1: regex-based, P95 < 5ms)
- Context hook injection for LLM-based extraction at SessionStart (Layer 2: Claude Code as distiller, zero extra cost)
- `/distill-transcripts` skill for manual deep extraction (Layer 3: on-demand, depth-aware prompts)
- `memory.undistilled` and `memory.mark_distilled` MCP tools for distillation tracking
- `Hook::DistillationRunner` extracted from Handler for context hook injection
- `TaskCompleted` and `TeammateIdle` hook events for ingest triggers
- Distillation metrics backfill on database initialization
- Doctor check for undistilled content
- Pending distillation count in `memory.status` output

**Recall Enhancements**
- Intent parameter for recall query disambiguation (#3)
- Retrieval score traces for semantic search (#5)
- Configurable embedding providers with dimension checking

**Hook Enhancements**
- `statusMessage` on all hooks for descriptive spinner text during hook execution
- `StopFailure` hook to capture transcript data even on session errors (rate limits, server errors)
- `Notification` hook with `idle_prompt` matcher for opportunistic sweep during idle

**New Commands & Skills**
- `install-skill` command and `memory-recall` agent (#8, #12)
- Shell completion command for bash and zsh (#18)

**Distillation Benchmark Results**
- NullDistiller: Concept Recall 0.952, Fact Precision/Recall 1.000 (31 test cases)
- Claude Code LLM: Concept Recall 0.902 (all 41 cases), 0.900 on semantic cases (vs 0.333 for regex)
- Average 1.6 facts stored per case across LLM extraction
- E2E distillation recall benchmark and extraction quality benchmarks
- Concept-based matching for distiller-agnostic benchmark comparison

### Fixed

- `--allowedTools` added to `ClaudeCliRunner` for MCP tool permissions
- Test isolation for context hook when global database has facts

### Internal
- Extracted `RetryHandler` and `SchemaManager` modules from `SQLiteStore`
- Extracted `Recall` into engine strategy pattern with `DualEngine`, `LegacyEngine`, and shared `QueryCore`
- Extracted `Tools` god object into 6 handler modules
- Added 36 specs for 5 previously untested files
- All 3 god objects eliminated, 0 files over 500 lines

## [0.7.1] - 2026-03-17

### Added

**Three-Level Sweep Escalation**
- `Maintenance` class with light/standard/deep sweep levels for progressive database maintenance
- Exposed sweep escalation via `memory.sweep_now` MCP tool with configurable level
- Tool escalation workflow added to MCP QueryGuide documentation

**Embedding Deduplication**
- Content-addressed deduplication for embeddings using SHA256 hashing
- Deduplication before vector scoring in fallback path to prevent duplicate results

**MCP Enhancements**
- Structured error classification for MCP tools via `ErrorClassifier` module
- Dynamic knowledge summary in MCP server instructions via `InstructionsBuilder`

### Fixed

- **Plugin hook loading error**: Removed explicit `hooks` reference from `plugin.json` manifest — Claude Code auto-loads `hooks/hooks.json` from the plugin root, so declaring it caused "Duplicate hooks file detected" errors on plugin install

### Internal
- Influence study: lossless-claw v0.3.0 DAG-based lossless context management
- Marked 7 improvements as implemented (#10, #11, #14, #15, #16, #19, #20)

## [0.7.0] - 2026-03-12

### Added

**FTS5 Contentless Mode**
- FTS5 tables now created with `content=''` for ~40% smaller databases
- Auto-detection: both legacy and contentless formats work seamlessly
- `compact` command rebuilds FTS index to contentless format
- `stats` command reports FTS format and optimization hints

**Worktree-Aware Project Paths**
- Project database now resolves to main repository root across git worktrees
- Prevents duplicate project databases when using `git worktree`
- Opt-out: set `CLAUDE_MEMORY_ISOLATE_WORKTREES=1` for per-worktree isolation

**MCP Enhancements**
- Tool annotations: `readOnlyHint`, `idempotentHint`, `destructiveHint` on all 23 tools
- Stdout protection: MCP server redirects `$stdout` to `$stderr` to prevent protocol corruption from accidental `puts`/`print` calls
- Self-excluding agent conversations via `SELF_CONTEXT_MARKER` to prevent meta-pollution

**New Commands**
- `git-lfs` command for setting up git-lfs tracking of project memory databases

### Fixed

- Narrowed rescue clauses in `discover_other_projects` (was bare `rescue`, now catches specific `Sequel::DatabaseError`, `Extralite::Error`, `IOError`)
- FTS entries now cleaned up when content is pruned by sweeper (prevents orphaned index entries)
- FTS index rebuilt during `compact` for consistent state after upgrades
- Real evals CI: install gem and use correct release API

### Internal
- Resolver refactored to pass `project_path`/`scope` as parameters instead of instance variables (better thread safety)
- `SnippetExtractor` refactored to eliminate duplication between `extract` and `extract_with_lines`
- `StoreManager.promote_fact` inlined `copy_provenance` for single-transaction safety
- Influence study: QMD v2.0.1 SDK-first architecture analysis

## [0.6.0] - 2026-03-06

### Added

**Native Vector Storage (sqlite-vec)**
- Integrated [sqlite-vec](https://github.com/asg017/sqlite-vec) for native KNN vector search
  - `VectorIndex` class with vec0 virtual table for cosine similarity search
  - Dual-write: embeddings stored in both JSON column and vec0 index
  - `claude-memory index --vec` flag for backfilling existing embeddings into vec0
  - Fast path in `Recall` uses sqlite-vec KNN when available, falls back to JSON + Ruby
  - Sweeper cleans up vec0 entries for superseded/expired facts
  - Doctor and MCP status/stats report vec0 availability and coverage
  - Cross-platform support with platform-specific gem installation

**Database Maintenance**
- `compact` command for database maintenance (VACUUM + integrity check)
- `export` command for fact backup and migration to JSON

**Hook Enhancements**
- SessionStart context injection via `hookSpecificOutput.additionalContext`
  - Injects recent facts and project context at session start
- Tool-specific observation compression for reduced token usage
- `--async` flag for non-blocking hook execution
- Hook error classification for graceful degradation
- Conversation exclusion markers for session-level opt-out

**MCP Discovery**
- `memory.list_projects` MCP tool for discovering all project databases

**Developer Experience**
- Dynamic MCP server instructions with progressive disclosure documentation
- Comparative benchmark suite with QMD and grepai adapters
  - `bin/setup-competitors` for installing competitor tools
  - `bin/run-evals --comparative` for side-by-side benchmarks

### Fixed

- **Recall returned no results**: `DualQueryTemplate` accessed stores before initializing them,
  causing all recall queries to silently return empty results. Refactored to use existing
  `store_for_scope` method which handles initialization and access atomically.
- **Doctor crashed on sqlite-vec tables**: `SchemaValidator` iterated all tables including vec0
  virtual tables, which require the sqlite-vec extension. Now skips `facts_vec*` tables using
  prefix match to handle future partition tables.
- **Forward-migrated databases**: Older gem versions now gracefully handle databases migrated
  by newer versions instead of crashing.
- **Hybrid retrieval ordering**: Preserved BM25 scores and RRF ordering in hybrid search results
  instead of re-sorting by source/time.
- Fork-based concurrency tests skipped on Ruby 4.0+ (Extralite incompatibility)
- Real eval tests now run in tmpdir with fixture database

### Internal
- Refactored publish to avoid unnecessary rewrites from timestamp churn
- Skip quality-review hook when running inside Claude Code session
- Influence studies for claude-mem, episodic-memory, kbs repositories

## [0.5.1] - 2026-02-04

### Fixed

- **Database Lock Errors**: Fixed "database is locked" and "database is busy" errors when
  multiple Claude Code hooks run concurrently
  - Added application-level retry with exponential backoff (5 retries, 0.1s base delay)
  - Reduced SQLite busy_timeout from 30s to 1s for faster failure detection
  - Added `with_retry` and `transaction_with_retry` methods for concurrent access handling
  - SQLite's busy_timeout doesn't reliably detect lock release; app-level retry compensates

- **MCP Server Auto-Registration**: Added `.mcp.json` at plugin root so MCP server is
  automatically registered when plugin is installed (previously only worked in dev directory)

## [0.5.0] - 2026-02-04

### Added

**MCP Structured Content & Compact Mode**
- Dual content (text summary) + structuredContent (JSON) for all MCP tools
  - `TextSummary` module generates human-readable summaries alongside structured data
  - Compact mode (`compact: true`) omits provenance receipts for ~60% smaller responses
- MCP query guide prompt registered via `prompts/list` and `prompts/get` endpoints
  - `QueryGuide` module provides tool selection guidance to Claude

**Search & Retrieval Improvements**
- Reciprocal Rank Fusion (RRF) replacing naive merge for hybrid search
  - Better result ordering when combining FTS5 and semantic search results
- Smart expansion detection to skip unnecessary vector search
  - Reduces latency when FTS5 already provides strong matches
- Enhanced snippet extraction for search results
  - Better context windows around matched terms

**Provenance & Traceability**
- Line-range references in provenance for precise source linking
  - Facts now track exact line ranges in source transcripts
- Fact dependency graph visualization via BFS traversal
  - Trace supersession and conflict chains between facts

**User-Friendly Identifiers**
- Docid short hash system for user-friendly fact references
  - Short, memorable identifiers instead of raw integer IDs

**Caching & Performance**
- LLM response caching schema and store methods
  - Cache layer for expensive extraction operations
- Structured JSON logging with level filtering
  - Configurable log levels (debug, info, warn, error)
  - JSON format for machine-parseable log output

**Ingestion & Content Processing**
- Configurable tool capture filtering for ingestion
  - Control which tool outputs are captured during transcript processing
- ContentSanitizer now strips `system-reminder`, `local-command-caveat`, `command-message`,
  `command-name`, and `command-args` tags in addition to privacy tags
- Relative time formatting in MCP recall output
  - Progressive format: just now → Xm ago → Xh ago → Xd ago → YYYY-MM-DD

**Developer Tools**
- `--brief` flag for doctor command and health checks in skills
  - Quick pass/fail output for automated workflows

### Fixed
- Preserve SQLite PRAGMAs across connection reconnects
  - WAL mode and other pragmas now survive reconnection cycles
- Timestamp-only churn in publish output
  - Publish no longer regenerates files when only the timestamp changed

### Internal

**Code Quality Improvements**
- Extract duplicates and decompose long methods across codebase
- Extract ingester transaction body into focused methods
- Decompose `resolve_fact` into intention-revealing methods
- Extract `check_setup` and `detailed_stats` into focused helpers
- Fix N+1 query patterns in `recall.rb`
- Fix 6 quick wins from quality review (frozen strings, method sizes, naming)

**Research & Studies**
- QMD restudy (2026-02-02): adopt Claude Code plugin format, MCP structured content pattern,
  MCP query guide prompt, inline status checks
- claude-supermemory study: adopt SessionStart hook context injection, tool-specific observation
  compression, and relative time formatting

## [0.4.0] - 2026-02-02

### Added

**Semantic Search with FastEmbed**
- Integrated [fastembed-rb](https://github.com/khasinski/fastembed-rb) for high-quality local embeddings
  - Uses BAAI/bge-small-en-v1.5 model (384-dim, ~67MB ONNX, runs locally)
  - No API key required -- model downloaded once to `~/.cache/fastembed/`
  - Asymmetric query/passage encoding for better retrieval accuracy
- `FastembedAdapter` class implementing the existing `Generator` interface for drop-in replacement
- Benchmark retrieval scores jumped significantly with real embeddings:
  - Semantic easy: Recall@5 = 0.900, medium: 0.696
  - Hybrid aggregate: Recall@5 = 0.727 (was 0.266 with TF-IDF fallback)

### Documentation
- Updated benchmark results throughout README, spec/benchmarks/README, and architecture docs
- Replaced TF-IDF embedding references with FastEmbed in architecture documentation

## [0.3.0] - 2026-01-29

### Added

**Setup & Initialization**
- Version markers in CLAUDE.md files for upgrade detection
  - HTML comment format: `<!-- ClaudeMemory vX.Y.Z -->`
  - Enables version comparison and upgrade workflows
- `memory.check_setup` MCP tool for initialization detection
  - Returns status: healthy, needs_upgrade, partially_initialized, not_initialized
  - Checks databases, CLAUDE.md, version, and hooks configuration
  - Provides actionable recommendations
- `/setup-memory` skill for installation guidance
  - Comprehensive troubleshooting documentation
  - Step-by-step setup instructions
  - Links to diagnostic tools

**Database & Infrastructure**
- Schema version 6 with new tables:
  - `operation_progress` - Track long-running operation state (index generation, migrations)
  - `schema_health` - Record schema validation results and migration history
- WAL (Write-Ahead Logging) mode for better concurrency and crash recovery
- Incremental sync with `source_mtime` tracking to avoid re-processing unchanged files
- Atomic migrations with per-migration transactions for safety
- Configuration class for centralized ENV access and testability

**Search & Recall**
- `index` command to generate embeddings for semantic search
- Index command resumability with checkpoints (recover from interruption)
- Semantic search capabilities with embedding-based vector search
- Improved full-text search with empty query handling

**Session Intelligence**
- Session metadata extraction:
  - Git branch tracking (`git_branch`)
  - Working directory context (`cwd`)
  - Claude version tracking (`claude_version`)
  - Tool usage patterns (`tool_calls`)
- Session-aware fact extraction for better provenance

**Developer Tools**
- Enhanced `doctor` command with:
  - Schema validation and integrity checks
  - Migration history verification
  - Recovery suggestions for corrupted databases
- `stats` command for database statistics
- Recovery command for stuck long-running operations
- Transaction wrapper for ingestion atomicity

**Quality Improvements**
- Quality review workflow with Ruby expert perspectives:
  - `/review-for-quality` skill for comprehensive codebase review
  - Expert analysis from Sandi Metz, Jeremy Evans, Kent Beck, Avdi Grimm, Gary Bernhardt
  - Automated quality documentation generation
- Infrastructure abstractions (FileSystem, InMemoryFileSystem) for testability
- Domain model enhancements with immutable, self-validating objects

**Repository Analysis**
- `/study-repo` skill for deep analysis of external repositories
  - Systematic exploration through 6 phases (context, architecture, patterns, quality, comparison, adoption)
  - Generates comprehensive influence documents in `docs/influence/`
  - Updates `docs/improvements.md` with prioritized recommendations
  - Focus mode support for targeted analysis (testing, MCP, database, CLI, performance)
  - Integration with `/improve` workflow

**Error Handling**
- Graceful error messages when databases are missing or not accessible
- Structured error responses with recommendations
- Directs users to `memory.check_setup` for diagnosis

### Changed
- **IMPORTANT**: Switched from sqlite3 to extralite as required dependency
  - Extralite provides better concurrency and performance
  - Fixes database lock contention between MCP server and hooks
  - Extralite (~> 2.14) is now the only SQLite adapter
- Ingestion now tracks file modification time to skip unchanged content
- Migration process now uses per-migration transactions for atomicity
- Doctor command now includes schema validation and recovery guidance
- Index operations can resume from checkpoints after interruption
- MCP tool descriptions now emphasize memory-first workflow
- Tool descriptions are more directive ("Check FIRST", "Use BEFORE")
- Init command now adds version markers to generated CLAUDE.md files

### Fixed
- **Critical**: Database lock contention between MCP server and hooks
  - Switched to extralite adapter for better concurrent access
  - Improved busy timeout handling
- Database busy error handling for both SQLite adapters
- Concurrent access test for extralite adapter
- Public keyword placement in SQLiteStore (Ruby style conformance)
- Transaction safety for multi-step database operations

### Documentation
- Complete getting started guide (GETTING_STARTED.md)
- Enhanced plugin documentation with setup workflows
- Comprehensive examples for all features
- Architecture documentation updates
- Updated all documentation to reflect current codebase metrics
  - 20 commands (was documented as 16)
  - 18 MCP tools (was documented as 7-8)
  - 985 test examples (was documented as 583/426)
- Auto-initialization and upgrade design document (docs/auto_init_design.md)
- Multi-phase upgrade strategy documentation

### Internal
- Consolidated ENV access via Configuration class
- Registered new infrastructure modules in main loader
- Improved test coverage for new features
- Major code quality improvements with component extraction:
  - `Core::FactQueryBuilder` - Query construction logic from Recall
  - `Core::SetupStatusAnalyzer` - Setup status analysis from MCP Tools
  - `MCP::ToolDefinitions` - Tool definitions separated from server logic
  - `MCP::ResponseFormatter` - Response formatting with multiple query types
  - `Core::TextBuilder` - Text building utilities
  - `Core::ResultSorter` - Result sorting logic
  - `Core::EmbeddingCandidateBuilder` - Embedding candidate construction
  - `Core::FactCollector` - Fact collection logic
  - `Core::ResultBuilder` - Result building logic
- Init command test suite (19 examples)
- Setup detection test suite (25 examples)
- Error handling test suite (4 examples)
- Comprehensive test coverage (53 new tests)

## [0.2.0] - 2026-01-22

### Added

**Privacy & Security**
- Privacy tag system: `<private>`, `<no-memory>`, `<secret>` tags strip sensitive content from ingestion
- ContentSanitizer module with comprehensive sanitization logic
- ReDoS protection: Maximum 100 tags per ingestion to prevent regex attacks
- 100% test coverage for ContentSanitizer (security-critical module)

**Token Economics & Performance**
- Progressive disclosure pattern with two-phase queries:
  - `memory.recall_index` - Lightweight index with previews (~50 tokens per fact)
  - `memory.recall_details` - Full details on demand with provenance
- TokenEstimator module for accurate query result sizing
- 10x token reduction for initial memory searches
- N+1 query elimination in Recall class (reduced from 2N+1 to 3 queries via batch loading)
- IndexQuery object for cleaner full-text search logic
- QueryOptions parameter object for consistent option handling

**Semantic Shortcuts**
- `memory.decisions` - Quick access to architectural decisions and accepted proposals
- `memory.conventions` - Global coding conventions and style preferences
- `memory.architecture` - Framework choices and architectural patterns
- Shortcuts query builder with centralized predicate configuration
- Pre-configured queries eliminate manual search construction

**Claude Code Plugin**
- Full plugin structure for seamless Claude Code integration
- `.claude-plugin/plugin.json` manifest with marketplace metadata
- `hooks/hooks.json` with prompt hooks for Claude-powered extraction
- `skills/memory/SKILL.md` for `/memory` command

**Claude-Powered Fact Extraction**
- `memory.store_extraction` MCP tool for structured fact storage
- Accepts JSON with entities, facts, and decisions
- Prompt hooks trigger extraction on session stop
- No API key required - uses Claude Code's own session
- Full schema validation with truth maintenance

**Developer Experience**
- Exit code strategy for hooks with semantic constants:
  - `SUCCESS = 0` - Operation completed successfully
  - `WARNING = 1` - Completed with warnings (e.g., skipped ingestion)
  - `ERROR = 2` - Operation failed
- Comprehensive hook tests covering all event types (13 test cases)
- PrivacyTag value object for type-safe tag handling
- Empty query handling for FTS5 search

**Testing & Quality**
- 157 new test examples (grew from 426 to 583 total)
- 100% coverage for TokenEstimator (accuracy-critical)
- Comprehensive privacy tag tests including ReDoS protection
- Hook exit code verification tests

### Changed
- CLI hook commands now return standardized exit codes instead of mixed returns
- Recall queries optimized with batch loading for provenance and entities
- Index searches use QueryOptions for consistent parameter handling

### Documentation
- README restructured for clarity and quick onboarding
- New comprehensive examples documentation
- Simplified getting started experience

## [0.1.0] - 2026-01-20

### Added

- SQLite store with full MVP schema (entities, facts, provenance, conflicts)
- Transcript delta ingestion with cursor tracking
- Full-text search via SQLite FTS5
- NullDistiller for heuristic-based fact extraction
- Resolver for truth maintenance (supersession/conflict handling)
- Recall API with provenance receipts
- Sweep mechanics for time-bounded maintenance
- MCP server with memory tools
- Publish command for Claude Code memory integration
- CLI with all core commands
- Doctor command for health checks
- Hooks and output style templates
