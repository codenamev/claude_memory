# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
