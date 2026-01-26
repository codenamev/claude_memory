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

## Setting Up a New Project

After installing the plugin, you'll need to set up memory for each project. There are two scenarios:

### Scenario A: First-Time Setup (Fresh Install)

If this is your first time using ClaudeMemory:

```bash
# 1. Navigate to your project
cd ~/projects/my-app

# 2. Initialize both global and project databases
claude-memory init

# Expected output:
# ✓ Created global database at ~/.claude/memory.sqlite3
# ✓ Created project database at .claude/memory.sqlite3
# ✓ Configured hooks for automatic ingestion
# ✓ MCP server ready
```

This creates:
- **Global DB** (`~/.claude/memory.sqlite3`) - One-time, user-wide
- **Project DB** (`.claude/memory.sqlite3`) - Per-project

### Scenario B: Plugin Already Installed

If you already have ClaudeMemory installed globally and are adding it to a new project:

```bash
# 1. Navigate to your new project
cd ~/projects/another-app

# 2. Initialize project memory (global already exists)
claude-memory init

# Expected output:
# ✓ Global database exists at ~/.claude/memory.sqlite3
# ✓ Created project database at .claude/memory.sqlite3
# ✓ Hooks already configured
# ✓ Ready to use
```

The global database is reused; only the project database gets created.

### Quick Start Workflow

After initialization:

```bash
# 3. Start Claude Code
claude

# 4. Let Claude analyze your project (optional but recommended)
/claude-memory:analyze

# 5. Or just talk naturally
"This is a Rails app with PostgreSQL, deploying to Heroku"

# Behind the scenes:
# - Facts extracted automatically on session stop
# - Stored in .claude/memory.sqlite3 (project scope)
# - Available in future conversations
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

Both databases are queried on every recall. Project facts take precedence over global facts when there's overlap.

### When to Use Global vs Project Memory

Understanding scope helps Claude remember the right things in the right places:

| Memory Type | Use For | Examples |
|-------------|---------|----------|
| **Global** | Personal preferences, coding style, tool choices that apply everywhere | "I prefer descriptive variable names"<br>"I always use single quotes in Ruby"<br>"I like verbose error messages" |
| **Project** | Tech stack, architecture decisions, project-specific conventions | "This app uses PostgreSQL"<br>"We deploy to Vercel"<br>"This project uses React 18" |

**Workflow Examples:**

```bash
# Setting global preferences
You: "I always prefer tabs over spaces - remember that for all projects"
Claude: [stores with scope_hint: global]

# Project-specific facts (automatic)
You: "This app uses Next.js and Supabase"
Claude: [stores with scope: project]

# Promoting project facts to global
claude-memory promote <fact_id>
# Or: "Remember that I prefer using Supabase for all my projects"
```

### Scope System

Facts are scoped to control where they apply:

- **project**: Only this project (e.g., "this app uses PostgreSQL")
- **global**: All projects (e.g., "I prefer 4-space indentation")

Claude automatically detects scope signals:
- "always", "in all projects", "my preference" → global
- Project-specific tech choices → project

You can manually promote facts:
```bash
# From command line
claude-memory promote <fact_id>

# Or naturally in conversation
"Make that a global preference"
```

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

**Problem**: Claude doesn't seem to have access to memory tools

**Solutions**:
1. Check `claude-memory` is in PATH:
   ```bash
   which claude-memory
   # Should output: /path/to/bin/claude-memory
   ```

2. Verify plugin is installed:
   ```bash
   /plugin
   # Navigate to "Installed" tab, look for "claude-memory"
   ```

3. Check for errors:
   ```bash
   /plugin
   # Navigate to "Errors" tab for any issues
   ```

4. Verify MCP configuration:
   ```bash
   cat .mcp.json
   # Should reference claude-memory serve-mcp
   ```

5. Restart Claude Code:
   ```bash
   # Exit and relaunch
   ```

### Facts Not Being Extracted

**Problem**: Claude doesn't remember things from previous conversations

**Possible causes**:

1. **Session didn't stop**: Prompt hooks require the session to actually stop (not just pause)
   - Solution: Exit Claude Code properly with `/exit` or Ctrl+D

2. **Hooks not registered**: Check if hooks are configured
   - Solution: Run `claude-memory init` to reconfigure hooks
   - Verify: Check `.claude/settings.json` for hook entries

3. **Database not created**: Missing database files
   - Solution: Run `claude-memory doctor` to diagnose
   - Check: `ls -la .claude/memory.sqlite3`

4. **Extraction failed**: Claude couldn't parse facts from conversation
   - Solution: Be more explicit in your language
   - Instead of: "maybe we could use postgres"
   - Say: "We're using PostgreSQL for the database"

### Project Database Not Created

**Problem**: `.claude/memory.sqlite3` doesn't exist after running `claude-memory init`

**Solutions**:

1. Check if directory exists:
   ```bash
   ls -la .claude/
   # If missing, create it
   mkdir -p .claude
   ```

2. Check permissions:
   ```bash
   ls -ld .claude
   # Should be writable by your user
   chmod 755 .claude
   ```

3. Verify you're in project root:
   ```bash
   pwd
   # Should be your project directory
   ```

4. Re-run init:
   ```bash
   claude-memory init
   ```

### Facts Going to Wrong Database

**Problem**: Project-specific facts stored globally (or vice versa)

**Diagnosis**:
```bash
# Check where facts are stored
claude-memory recall --scope project "database"
claude-memory recall --scope global "database"
```

**Solutions**:

1. If facts are in wrong scope, use promote/demote:
   ```bash
   # Move project fact to global
   claude-memory promote <fact_id>
   ```

2. Be explicit in your language:
   - Global: "I **always** prefer X" or "In **all** my projects"
   - Project: "**This app** uses X" or "**We're** using X"

### Verifying Dual-Database Setup

**Check that both databases exist and are working**:

```bash
# 1. Check global database
ls -lh ~/.claude/memory.sqlite3
# Should exist with file size > 0

# 2. Check project database
ls -lh .claude/memory.sqlite3
# Should exist in current project

# 3. Run health check
claude-memory doctor

# Expected output:
# ✓ Global database: ~/.claude/memory.sqlite3
# ✓ Project database: .claude/memory.sqlite3
# ✓ Both databases healthy

# 4. Test recall from both
claude-memory recall --scope global "preference"
claude-memory recall --scope project "database"
```

### Database Migration Issues

**Problem**: Error during schema migration after gem update

**What happens automatically**:
- Schema migrations run on first access after update
- Migrations are atomic (all-or-nothing)
- Your data is preserved

**If migration fails**:

```bash
# 1. Check current state
claude-memory doctor --verbose

# 2. Check schema version
sqlite3 ~/.claude/memory.sqlite3 "PRAGMA user_version;"
# Should show current schema version

# 3. View migration history
sqlite3 .claude/memory.sqlite3 "SELECT * FROM schema_health;"

# 4. If corrupted, try recovery
claude-memory doctor --recover

# 5. Last resort: backup and reinitialize
mv .claude/memory.sqlite3 .claude/memory.sqlite3.backup
claude-memory init
# NOTE: This erases memory for this project
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
