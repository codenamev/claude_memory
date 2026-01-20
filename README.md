# ClaudeMemory

Turn-key Ruby gem providing Claude Code with instant, high-quality, long-term, self-managed memory using **Claude Code Hooks + MCP + Output Style**, with minimal dependencies (SQLite by default).

## Features

- **Automated ingestion**: Claude Code hooks trigger delta-based transcript ingestion
- **Fact extraction**: Heuristic-based distiller extracts entities, facts, and decisions
- **Truth maintenance**: Deterministic conflict/supersession resolution
- **Full-text search**: SQLite FTS5 for fast recall without embeddings
- **MCP integration**: Memory tools accessible directly in Claude Code
- **Snapshot publishing**: Curated memory files for Claude Code's built-in system

## Installation

```bash
gem install claude_memory
```

Or add to your Gemfile:

```ruby
gem 'claude_memory'
```

## Quick Start

```bash
# Initialize in your project (project-local)
cd your-project
claude-memory init

# Or install globally for all projects
claude-memory init --global

# Verify setup
claude-memory doctor
```

## Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize ClaudeMemory in a project |
| `db:init` | Initialize the SQLite database |
| `ingest` | Ingest transcript delta |
| `hook ingest` | Hook entrypoint for ingest (reads stdin JSON) |
| `hook sweep` | Hook entrypoint for sweep (reads stdin JSON) |
| `hook publish` | Hook entrypoint for publish (reads stdin JSON) |
| `search` | Search indexed content |
| `recall` | Recall facts matching a query |
| `explain` | Explain a fact with provenance receipts |
| `conflicts` | Show open conflicts |
| `changes` | Show recent fact changes |
| `publish` | Publish snapshot to Claude Code memory |
| `sweep` | Run maintenance/pruning |
| `serve-mcp` | Start MCP server for Claude Code |
| `doctor` | Check system health |

## Usage Examples

### Ingest Content

```bash
claude-memory ingest \
  --source claude_code \
  --session-id sess-123 \
  --transcript-path ~/.claude/projects/myproject/transcripts/latest.jsonl
```

### Recall Facts

```bash
claude-memory recall "database"
# Returns facts + provenance receipts

claude-memory explain 42
# Detailed explanation with supersession/conflict links
```

### Publish Snapshot

```bash
# Publish to .claude/rules/ (shared, default)
claude-memory publish

# Publish to local file (not committed)
claude-memory publish --mode local

# Publish to user home directory
claude-memory publish --mode home
```

### MCP Tools

When configured, these tools are available in Claude Code:

- `memory.recall` - Search for relevant facts
- `memory.explain` - Get detailed fact provenance
- `memory.changes` - Recent fact updates
- `memory.conflicts` - Open contradictions
- `memory.sweep_now` - Run maintenance
- `memory.status` - System health check

## Architecture

```
Transcripts → Ingest → FTS Index
                    ↓
              Distill → Extract entities/facts/signals
                    ↓
              Resolve → Truth maintenance (conflicts/supersession)
                    ↓
              Store → SQLite (facts, provenance, entities)
                    ↓
              Publish → .claude/rules/claude_memory.generated.md
```

## Configuration

The database location defaults to `.claude_memory.sqlite3` in the project root.

Override with `--db PATH` on any command.

## Development

```bash
git clone https://github.com/codenamev/claude_memory
cd claude_memory
bin/setup
bundle exec rspec
```

## License

MIT License - see [LICENSE.txt](LICENSE.txt)

## Contributing

Bug reports and pull requests welcome at https://github.com/codenamev/claude_memory
