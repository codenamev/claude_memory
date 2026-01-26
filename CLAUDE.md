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

#### Application Layer

- **`CLI`**: Thin command router (`cli.rb`) - 41 lines
  - Routes commands to dedicated command classes via Registry
  - No business logic (pure dispatcher)

- **`Commands`**: Individual command classes (`commands/`)
  - Each command is a separate class (HelpCommand, DoctorCommand, etc.)
  - All commands inherit from BaseCommand
  - Dependency injection for I/O (stdout, stderr, stdin)
  - 16 commands total, each focused on single responsibility

- **`Configuration`**: Centralized ENV access (`configuration.rb`)
  - Single source of truth for paths and environment variables
  - Testable with custom ENV hash

#### Core Domain Layer

- **`Domain`**: Rich domain models with business logic (`domain/`)
  - `Fact`: Facts with validation, status checking (active?, superseded?)
  - `Entity`: Entities with type checking (database?, framework?)
  - `Provenance`: Evidence with strength checking (stated?, inferred?)
  - `Conflict`: Conflicts with status tracking (open?, resolved?)
  - All domain objects are immutable (frozen) and self-validating

- **`Core`**: Value objects and null objects (`core/`)
  - Value objects: SessionId, TranscriptPath, FactId (type-safe primitives)
  - Null objects: NullFact, NullExplanation (eliminates nil checks)
  - Result: Success/Failure pattern for consistent error handling

#### Infrastructure Layer

- **`Store`**: SQLite database access via Sequel (`store/`)
  - `SQLiteStore`: Database operations
  - `StoreManager`: Dual-database connection manager
  - Schema includes: content_items, entities, facts, provenance, fact_links, conflicts
  - Transaction safety for multi-step operations

- **`Infrastructure`**: I/O abstractions (`infrastructure/`)
  - `FileSystem`: Real filesystem wrapper
  - `InMemoryFileSystem`: Fast in-memory testing without disk I/O

#### Business Logic Layer

- **`Ingest`**: Transcript reading and delta-based ingestion (`ingest/`)
  - Tracks cursor position per session to avoid re-processing

- **`Index`**: Full-text search using SQLite FTS5 (`index/`)
  - Optimized with batch queries to eliminate N+1 issues

- **`Distill`**: Fact extraction interface (`distill/`)
  - Pluggable distiller design (current: NullDistiller stub)
  - Extracts entities, facts, scope hints from content

- **`Resolve`**: Truth maintenance and conflict resolution (`resolve/`)
  - Determines equivalence, supersession, or conflicts
  - PredicatePolicy controls single-value vs multi-value predicates
  - Transaction safety for atomic operations

- **`Recall`**: Query interface for facts (`recall.rb`)
  - Searches both global + project databases
  - Batch queries to avoid N+1 performance issues
  - Returns facts with provenance receipts

- **`Sweep`**: Maintenance and pruning (`sweep/`)

- **`Publish`**: Snapshot generation (`publish.rb`)
  - Uses FileSystem abstraction for testability
  - Modes: shared (repo), local (uncommitted), home (user directory)

- **`MCP`**: Model Context Protocol server and tools (`mcp/`)
  - Exposes memory tools to Claude Code
  - Tools: recall, explain, promote, status, conflicts, changes, sweep_now

- **`Hook`**: Hook entrypoint handlers (`hook/`)
  - Reads stdin JSON from Claude Code hooks
  - Routes to ingest/sweep/publish commands

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

1. Create new command class in `lib/claude_memory/commands/` (e.g., `my_command.rb`)
2. Inherit from `BaseCommand` and implement `call(args)` method
3. Add command to `Commands::Registry::COMMANDS` hash
4. Add corresponding tests in `spec/claude_memory/commands/my_command_spec.rb`
5. Use dependency injection for I/O (stdout, stderr, stdin) for testability

Example:
```ruby
class MyCommand < BaseCommand
  def call(args)
    opts = parse_options(args, {flag: false}) do |o|
      OptionParser.new do |parser|
        parser.on("--flag", "Enable flag") { o[:flag] = true }
      end
    end
    return 1 if opts.nil?

    stdout.puts "Command executed!"
    0  # Exit code
  end
end
```

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
- `lib/claude_memory/cli.rb`: Thin command router (41 lines)
- `lib/claude_memory/commands/`: Individual command classes (16 commands)
- `lib/claude_memory/configuration.rb`: Centralized configuration and ENV access
- `lib/claude_memory/domain/`: Domain models (Fact, Entity, Provenance, Conflict)
- `lib/claude_memory/core/`: Value objects and null objects
- `lib/claude_memory/infrastructure/`: I/O abstractions (FileSystem)
- `lib/claude_memory/store/store_manager.rb`: Dual-database connection manager
- `lib/claude_memory/resolve/resolver.rb`: Truth maintenance with transaction safety
- `lib/claude_memory/recall.rb`: Optimized fact query with batch loading
- `docs/quality_review.md`: Quality improvements and refactoring notes
- `claude_memory.gemspec`: Gem metadata and dependencies

## MCP Integration

The gem includes an MCP server (`claude-memory serve-mcp`) that exposes memory operations as tools. Configuration should be in `.mcp.json` at project root.

Available MCP tools:
- `memory.recall` - Search for relevant facts (scope filtering supported)
- `memory.check_setup` - Check initialization status and version (diagnostics)
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

## Custom Commands

### `/review-for-quality`

Runs a comprehensive quality review of the entire codebase.

**What it does:**
1. Launches a Plan agent to thoroughly explore the codebase
2. Critically reviews code for Ruby best-practices, idiom use, and overall quality
3. Analyzes through the perspectives of 5 Ruby experts:
   - **Sandi Metz** - POODR principles, single responsibility, small objects
   - **Jeremy Evans** - Sequel best practices, performance, simplicity
   - **Kent Beck** - Test-driven development, simple design, revealing intent
   - **Avdi Grimm** - Confident Ruby, explicit code, null objects, tell-don't-ask
   - **Gary Bernhardt** - Boundaries, functional core/imperative shell, fast tests
4. Updates `docs/quality_review.md` with findings including:
   - Specific file:line references for every issue
   - Which expert's principle is violated
   - Concrete improvement suggestions with code examples
   - Priority levels (Critical 🔴 / High / Medium 🟡 / Low)
   - Metrics comparison showing progress since last review
   - Quick wins that can be done immediately

**Usage:**
```
/review-for-quality
```

**Output:** Updated `docs/quality_review.md` with dated review and actionable refactoring recommendations.
