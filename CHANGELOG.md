# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

### Changed

### Fixed

### Documentation

### Internal

## [0.4.0] - 2026-01-29

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
- MCP tool descriptions now emphasize memory-first workflow
- Tool descriptions are more directive ("Check FIRST", "Use BEFORE")
- Init command now adds version markers to generated CLAUDE.md files

### Fixed
- **Critical**: Database lock contention between MCP server and hooks
  - Switched to extralite adapter for better concurrent access
  - Improved busy timeout handling
- Database busy error handling for both SQLite adapters
- Concurrent access test for extralite adapter

### Documentation
- Updated all documentation to reflect current codebase metrics
  - 20 commands (was documented as 16)
  - 18 MCP tools (was documented as 7-8)
  - 985 test examples (was documented as 583/426)
- Auto-initialization and upgrade design document (docs/auto_init_design.md)
- Multi-phase upgrade strategy documentation

### Internal
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

## [0.3.0] - 2026-01-26

### Added

**Database & Infrastructure**
- Schema version 6 with new tables:
  - `operation_progress` - Track long-running operation state (index generation, migrations)
  - `schema_health` - Record schema validation results and migration history
- WAL (Write-Ahead Logging) mode for better concurrency and crash recovery
- Incremental sync with `source_mtime` tracking to avoid re-processing unchanged files
- Atomic migrations with per-migration transactions for safety
- Configuration class for centralized ENV access and testability

**Search & Recall**
- `index` command to generate TF-IDF embeddings for semantic search
- Index command resumability with checkpoints (recover from interruption)
- Semantic search capabilities using TF-IDF embeddings
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

### Changed
- Ingestion now tracks file modification time to skip unchanged content
- Migration process now uses per-migration transactions for atomicity
- Doctor command now includes schema validation and recovery guidance
- Index operations can resume from checkpoints after interruption

### Fixed
- Public keyword placement in SQLiteStore (Ruby style conformance)
- Transaction safety for multi-step database operations
- Database locking issues during concurrent hook execution (added 5-second busy timeout)

### Documentation
- Complete getting started guide (GETTING_STARTED.md)
- Enhanced plugin documentation with setup workflows
- Comprehensive examples for all features
- Architecture documentation updates

### Internal
- Consolidated ENV access via Configuration class
- Registered new infrastructure modules in main loader
- Improved test coverage for new features

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
