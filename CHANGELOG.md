# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
