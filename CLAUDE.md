# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeMemory is a Ruby gem that provides long-term, self-managed memory for Claude Code using hooks, MCP tools, and output styles. It ingests transcripts, distills them into facts with provenance, resolves contradictions, and publishes curated snapshots.

**Key dependencies:**
- Ruby 3.2.0+
- Sequel (~> 5.0) for database access
- SQLite3 (~> 2.0) for storage

## Development Commands

### Setup
```bash
bin/setup              # Install dependencies
```

### Testing
```bash
bundle exec rspec                              # Run all tests
bundle exec rspec spec/claude_memory/cli_spec.rb  # Run single test file
bundle exec rspec spec/claude_memory/cli_spec.rb:42  # Run specific test by line number
bundle exec rake spec                          # Alternative test command
bundle exec rake                               # Run tests + Standard linter (default task)
```

### Linting
```bash
bundle exec rake standard        # Run Standard Ruby linter
bundle exec rake standard:fix    # Auto-fix linting issues
```

### Build & Release
```bash
bundle exec rake build   # Build gem to pkg/
bundle exec rake install # Install gem locally
bundle exec rake release # Tag + push to RubyGems (requires credentials)
```

### Running the CLI
```bash
# During development, use the executable directly
./exe/claude-memory <command>

# Or via bundle exec
bundle exec claude-memory <command>
```

## Architecture

### Dual-Database System
ClaudeMemory uses two SQLite databases for memory separation:

- **Global DB** (`~/.claude/memory.sqlite3`): User-wide knowledge across all projects (preferences, conventions)
- **Project DB** (`.claude/memory.sqlite3`): Project-specific facts and decisions

The `Store::StoreManager` class manages both connections. Commands query both databases by default, with project facts taking precedence.

### Core Pipeline

```
Transcripts → Ingest → Index (FTS5)
                   ↓
             Distill → Extract entities/facts + scope hints
                   ↓
             Resolve → Truth maintenance (supersession/conflicts)
                   ↓
             Store → SQLite (facts, provenance, entities)
                   ↓
             Publish → .claude/rules/claude_memory.generated.md
```

### Module Structure

- **`Store`**: SQLite database access via Sequel (`sqlite_store.rb`, `store_manager.rb`)
  - Schema includes: content_items, entities, facts, provenance, fact_links, conflicts
  - Schema migrations in `ensure_schema!` and `migrate_to_v2!`

- **`Ingest`**: Transcript reading and delta-based ingestion (`ingester.rb`, `transcript_reader.rb`)
  - Tracks cursor position per session to avoid re-processing

- **`Index`**: Full-text search using SQLite FTS5 (`lexical_fts.rb`)
  - No embeddings required for MVP

- **`Distill`**: Fact extraction interface (`distiller.rb`, `null_distiller.rb`)
  - Pluggable distiller design (current: NullDistiller stub)
  - Extracts entities, facts, scope hints from content

- **`Resolve`**: Truth maintenance and conflict resolution (`resolver.rb`, `predicate_policy.rb`)
  - Determines equivalence, supersession, or conflicts
  - PredicatePolicy controls single-value vs multi-value predicates

- **`Recall`**: Query interface for facts (`recall.rb`)
  - Searches both global + project databases
  - Returns facts with provenance receipts

- **`Sweep`**: Maintenance and pruning (`sweeper.rb`)

- **`Publish`**: Snapshot generation to Claude Code memory files (`publish.rb`)
  - Modes: shared (repo), local (uncommitted), home (user directory)

- **`MCP`**: Model Context Protocol server and tools (`mcp/server.rb`, `mcp/tools.rb`)
  - Exposes memory tools to Claude Code: recall, explain, promote, status, conflicts, changes, sweep_now

- **`Hook`**: Hook entrypoint handlers (`hook/handler.rb`)
  - Reads stdin JSON from Claude Code hooks
  - Routes to ingest/sweep/publish commands

- **`CLI`**: Command-line interface (`cli.rb`)
  - All user-facing commands and option parsing

### Database Schema

Key tables (defined in `sqlite_store.rb`):
- `content_items`: Ingested transcript chunks with cursor tracking
- `entities`: Named entities (people, repos, concepts)
- `entity_aliases`: Alternative names for entities
- `facts`: Subject-predicate-object triples with validity windows and scope
- `provenance`: Links facts to source content_items
- `fact_links`: Supersession and conflict relationships
- `conflicts`: Open contradictions

Facts include:
- `scope`: "global" or "project" (determines applicability)
- `project_path`: Set for project-scoped facts
- `valid_from`/`valid_to`: Temporal validity window

### Scope System

Facts are scoped to control where they apply:
- **project**: Current project only (e.g., "this app uses PostgreSQL")
- **global**: All projects (e.g., "I prefer 4-space indentation")

Distiller detects signals like "always", "in all projects", "my preference" and sets `scope_hint: "global"`. Users can manually promote facts via `claude-memory promote <fact_id>` or the `memory.promote` MCP tool.

## Testing Strategy

Tests are in `spec/claude_memory/` organized by module. Use RSpec's `--format documentation` for readable output.

When writing tests:
- Mock external dependencies (file I/O, database where appropriate)
- Use `let` blocks for shared test data
- Focus on behavior, not implementation details

## Common Development Tasks

### Adding a New CLI Command

1. Add command name to `CLI#run` case statement
2. Implement private method (e.g., `my_command_cmd`)
3. Add parser method (e.g., `parse_my_command_options`)
4. Update `print_help` output
5. Add corresponding tests in `spec/claude_memory/cli_spec.rb`

### Adding a New MCP Tool

1. Add tool definition to `MCP::Tools::TOOLS` hash
2. Implement handler in `MCP::Server#handle_tool_call`
3. Ensure tool queries appropriate database(s) via StoreManager
4. Add tests in `spec/claude_memory/mcp/`

### Modifying Database Schema

1. Increment `SCHEMA_VERSION` in `sqlite_store.rb`
2. Add migration method (e.g., `migrate_to_v3!`)
3. Call migration in `run_migrations!`
4. Test migration on existing database files
5. Update documentation if schema changes affect external interfaces

### Adding a New Predicate Policy

Single-value predicates (like "uses_database") supersede old values. Multi-value predicates (like "depends_on") accumulate. Modify `PredicatePolicy.single?` to adjust behavior.

## Important Files

- `lib/claude_memory.rb`: Main module, requires, database path helpers
- `lib/claude_memory/cli.rb`: All CLI command implementations (800+ lines)
- `lib/claude_memory/store/store_manager.rb`: Dual-database connection manager
- `lib/claude_memory/resolve/resolver.rb`: Truth maintenance logic
- `lib/claude_memory/recall.rb`: Fact query and merging logic
- `docs/updated_plan.md`: Comprehensive architectural plan and milestones
- `claude_memory.gemspec`: Gem metadata and dependencies

## MCP Integration

The gem includes an MCP server (`claude-memory serve-mcp`) that exposes memory operations as tools. Configuration should be in `.mcp.json` at project root.

Available MCP tools:
- `memory.recall` - Search for relevant facts (scope filtering supported)
- `memory.explain` - Get detailed fact provenance
- `memory.promote` - Promote project fact to global
- `memory.status` - Health check for both databases
- `memory.changes` - Recent fact updates
- `memory.conflicts` - Open contradictions
- `memory.sweep_now` - Run maintenance

## Hook Integration

ClaudeMemory integrates with Claude Code via hooks in `.claude/settings.json`:

- **Ingest hook**: Triggers on Stop/SessionStart/PreCompact events
  - Calls `claude-memory hook ingest` with stdin JSON
  - Reads transcript delta and updates both global and project databases

- **Sweep hook**: Triggers on idle_prompt and safety events
  - Runs time-bounded maintenance on both databases

- **Publish hook**: Optional, on SessionEnd/PreCompact
  - Publishes curated snapshot to `.claude/rules/`

Hook commands read JSON payloads from stdin for robustness.

## Code Style

This project uses [Standard Ruby](https://github.com/standardrb/standard) for linting. Run `bundle exec rake standard:fix` before committing.

Key conventions:
- Use `frozen_string_literal: true` at top of all Ruby files
- Prefer explicit returns only when control flow is complex
- Use Sequel's dataset methods (avoid raw SQL where possible)
- Keep CLI commands focused; extract complex logic to dedicated classes
