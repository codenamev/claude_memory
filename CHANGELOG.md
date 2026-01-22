# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
