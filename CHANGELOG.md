# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Claude Code Plugin**: Full plugin structure for seamless Claude Code integration
  - `.claude-plugin/plugin.json` manifest
  - `.claude-plugin/marketplace.json` for plugin distribution
  - `hooks/hooks.json` with prompt hooks for Claude-powered extraction
  - `skills/memory/SKILL.md` for `/memory` command
- **Claude-Powered Fact Extraction**: New `memory.store_extraction` MCP tool
  - Accepts structured JSON with entities, facts, and decisions
  - Prompt hooks ask Claude to extract facts on session stop
  - No API key required - uses Claude Code's own session
  - Full schema validation with truth maintenance
- **Empty Query Handling**: FTS5 search now gracefully handles empty queries

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
