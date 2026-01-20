# ClaudeMemory Plugin for Claude Code

ClaudeMemory integrates with Claude Code as a plugin, providing long-term memory capabilities powered by Claude's own intelligence.

## Installation

### Prerequisites

The `claude-memory` gem must be installed and available in your PATH:

```bash
gem install claude_memory
```

### Install the Plugin

From within Claude Code:

```bash
# Add the marketplace (use the path to your claude_memory directory)
/plugin marketplace add /path/to/claude_memory

# Install the plugin
/plugin install claude-memory
```

### Verify Installation

```bash
# Check plugin is loaded
/plugin
# Go to "Installed" tab - should see claude-memory

# Check MCP tools are available
# Ask Claude: "check memory status"
```

## How It Works

### Claude-Powered Fact Extraction

Unlike traditional approaches that require a separate API key, ClaudeMemory uses **prompt hooks** to leverage Claude Code's own session:

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code Session                       │
├─────────────────────────────────────────────────────────────┤
│  1. User has conversation with Claude                       │
│  2. Session stops (user done, timeout, etc.)                │
│  3. Stop hook triggers prompt hook                          │
│  4. Claude reviews session, extracts durable facts          │
│  5. Claude calls memory.store_extraction MCP tool           │
│  6. Facts stored in SQLite with truth maintenance           │
└─────────────────────────────────────────────────────────────┘
```

### Benefits

| Feature | Traditional API | Claude-Powered |
|---------|-----------------|----------------|
| API Key Required | ✅ Yes | ❌ No |
| Extra Cost | ✅ Per-token | ❌ None |
| Context Awareness | Limited | Full session context |
| Extraction Quality | Template-based | Intelligent |

## Plugin Components

### MCP Server

The plugin exposes these tools to Claude:

| Tool | Description |
|------|-------------|
| `memory.recall` | Search facts by query |
| `memory.explain` | Get fact details with provenance |
| `memory.store_extraction` | Store extracted facts |
| `memory.promote` | Promote project fact to global |
| `memory.status` | Check database health |
| `memory.changes` | Recent fact updates |
| `memory.conflicts` | Open contradictions |
| `memory.sweep_now` | Run maintenance |

### Hooks

| Event | Hook Type | Action |
|-------|-----------|--------|
| `Stop` | command | Ingest transcript delta |
| `Stop` | prompt | Ask Claude to extract facts |
| `SessionStart` | command | Ingest any missed content |
| `PreCompact` | command + prompt | Ingest, extract, then publish |
| `Notification` (idle) | command | Run sweep maintenance |
| `SessionEnd` | command | Publish snapshot |

### Skill

The `/memory` skill provides manual access:

```bash
/memory
# Shows available memory commands and usage
```

## Configuration

### Database Locations

| Database | Path | Purpose |
|----------|------|---------|
| Global | `~/.claude/memory.sqlite3` | User-wide facts |
| Project | `.claude/memory.sqlite3` | Project-specific facts |

### Scope System

Facts are scoped to control where they apply:

- **project**: Only this project (e.g., "this app uses PostgreSQL")
- **global**: All projects (e.g., "I prefer 4-space indentation")

Claude automatically detects scope signals:
- "always", "in all projects", "my preference" → global
- Project-specific tech choices → project

## Usage Examples

### Natural Conversation

Just talk to Claude naturally. Facts are extracted automatically:

```
User: "We're using PostgreSQL for the database and deploying to Vercel"
Claude: [works on task]
# On session stop, extracts:
# - uses_database: postgresql (project scope)
# - deployment_platform: vercel (project scope)
```

### Check What's Remembered

```
User: "What do you remember about our tech stack?"
Claude: [calls memory.recall] "Based on my memory, this project uses..."
```

### Promote to Global

```
User: "I always prefer 4-space indentation - remember that globally"
Claude: [stores with scope_hint: global]
```

### View Conflicts

```
User: "Are there any conflicting facts?"
Claude: [calls memory.conflicts] "I found 2 conflicts..."
```

## Troubleshooting

### MCP Tools Not Appearing

1. Check `claude-memory` is in PATH: `which claude-memory`
2. Verify plugin is installed: `/plugin` → Installed tab
3. Check for errors: `/plugin` → Errors tab
4. Restart Claude Code

### Facts Not Being Extracted

1. Prompt hooks require session to stop (not just pause)
2. Check if hooks are registered: Run with `claude --debug`
3. Verify database exists: `claude-memory doctor`

### Database Issues

```bash
# Check health
claude-memory doctor

# Reinitialize if needed
claude-memory db:init
```

## File Structure

```
claude_memory/
├── .claude-plugin/
│   ├── plugin.json        # Plugin manifest
│   └── marketplace.json   # Marketplace definition
├── .mcp.json              # MCP server config
├── hooks/
│   └── hooks.json         # Hook definitions
└── skills/
    └── memory/
        └── SKILL.md       # /memory skill
```

## See Also

- [README.md](../README.md) - Full project documentation
- [CLAUDE.md](../CLAUDE.md) - Development guidance
- [updated_plan.md](updated_plan.md) - Architecture deep dive
