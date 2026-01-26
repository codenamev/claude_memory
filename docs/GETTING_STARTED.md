# Getting Started with ClaudeMemory

ClaudeMemory gives Claude Code a persistent, intelligent memory across all your conversations. This guide will walk you through installation, setup, and your first project.

## Prerequisites

- **Ruby 3.2.0+** installed
- **Claude Code CLI** installed and working
- Basic familiarity with command line

## Installation

### Step 1: Install the Gem

```bash
gem install claude_memory
```

Verify installation:
```bash
claude-memory --version
# => claude_memory 0.2.0
```

### Step 2: Install the Plugin

From within Claude Code, add the marketplace and install the plugin:

```bash
# Add the marketplace (one-time setup)
/plugin marketplace add codenamev/claude_memory

# Install the plugin
/plugin install claude-memory
```

Verify the plugin is loaded:
```bash
/plugin
# Navigate to "Installed" tab - you should see "claude-memory"
```

### Step 3: Initialize Memory

Initialize both global and project-specific memory:

```bash
# From your project directory
claude-memory init
```

This creates:
- **Global database**: `~/.claude/memory.sqlite3` (user-wide knowledge)
- **Project database**: `.claude/memory.sqlite3` (project-specific facts)
- Hook configuration for automatic memory updates
- MCP server setup for Claude to access memory

Expected output:
```
✓ Created global database at ~/.claude/memory.sqlite3
✓ Created project database at .claude/memory.sqlite3
✓ Configured hooks for automatic ingestion
✓ MCP server ready
✓ Setup complete!
```

## Understanding the Dual-Database System

ClaudeMemory uses two separate databases to intelligently separate knowledge:

### Global Database (`~/.claude/memory.sqlite3`)

**Purpose**: User-wide knowledge that applies everywhere

**What gets stored:**
- Your coding preferences and conventions
- Personal style choices
- Tool preferences across projects
- General development patterns you prefer

**Examples:**
- "I prefer 4-space indentation in all my projects"
- "I always use single quotes for strings in Ruby"
- "I like descriptive variable names"

### Project Database (`.claude/memory.sqlite3`)

**Purpose**: Project-specific knowledge

**What gets stored:**
- This project's tech stack
- Architecture decisions for this codebase
- Project-specific conventions
- Team agreements and constraints

**Examples:**
- "This app uses PostgreSQL"
- "We deploy to Vercel"
- "This project follows Rails conventions"

### How Facts Get Scoped

Claude automatically detects scope signals in your conversation:

| Signal | Scope | Example |
|--------|-------|---------|
| "always", "in all projects" | Global | "I always prefer tabs over spaces" |
| "my preference", "I prefer" | Global | "My preference is verbose error messages" |
| Project tech choices | Project | "We're using React for the frontend" |
| "this app", "this project" | Project | "This app uses JWT authentication" |

You can also **manually promote** facts from project to global:

```bash
# From command line
claude-memory promote <fact_id>

# Or ask Claude
"Remember that I prefer descriptive commit messages - make that a global preference"
```

## Setting Up Your First Project

### Scenario 1: Fresh Install (New Project)

If you just installed ClaudeMemory and are starting a new project:

```bash
cd ~/projects/my-new-app
claude-memory init

# Analyze your project to bootstrap memory
# (From within Claude Code)
/claude-memory:analyze
```

The analyze skill will read your project files (Gemfile, package.json, etc.) and automatically extract:
- Languages and frameworks
- Database systems
- Build tools
- Testing frameworks

### Scenario 2: Adding Memory to Existing Project

If you already have the plugin installed globally and want to add memory to an existing project:

```bash
cd ~/projects/existing-app
claude-memory init

# Just the project database gets created
# Global database already exists from initial setup
```

Then tell Claude about your project naturally:
```
You: "This is a Rails 7 app with PostgreSQL, using Sidekiq for background jobs"
Claude: [works on your task]
# Facts automatically extracted and stored on session stop
```

### Scenario 3: Multiple Projects

Your global preferences travel with you:

```bash
# Project A
cd ~/projects/project-a
claude-memory init
# Uses: ~/.claude/memory.sqlite3 + .claude/memory.sqlite3

# Project B
cd ~/projects/project-b
claude-memory init
# Uses: ~/.claude/memory.sqlite3 + .claude/memory.sqlite3 (different file!)
```

Both projects share your global preferences but have separate project-specific knowledge.

## Using ClaudeMemory

### Natural Conversation

Memory happens automatically. Just talk to Claude normally:

```
You: "I'm building a Rails API with PostgreSQL, deploying to Heroku"
Claude: "I'll help you set that up..."

# Behind the scenes (on session stop):
# ✓ Transcript ingested
# ✓ Facts extracted:
#   - uses_framework: rails (project scope)
#   - uses_database: postgresql (project scope)
#   - deployment_platform: heroku (project scope)
# ✓ Stored in .claude/memory.sqlite3
# ✓ No user action needed
```

**Later, in a new conversation:**

```
You: "Help me add a background job"
Claude: [calls memory.recall]
Claude: "Based on my memory, you're using Rails with PostgreSQL on Heroku.
        I recommend using Sidekiq since it integrates well with your stack..."
```

### Analyzing Your Project

Bootstrap memory with project facts:

```
/claude-memory:analyze
```

This reads configuration files and extracts structured knowledge:
- `Gemfile` → Ruby gems and versions
- `package.json` → Node dependencies
- `docker-compose.yml` → Services and databases
- `.tool-versions` → Language versions
- And more!

### Checking What's Remembered

Ask Claude to recall knowledge:

```
You: "What do you remember about this project?"
Claude: [calls memory.recall]
Claude: "I remember this project uses:
        - Framework: Ruby on Rails 7.1
        - Database: PostgreSQL 15
        - Deployment: Heroku
        - Background Jobs: Sidekiq"
```

Or use CLI commands:

```bash
# Search for facts
claude-memory recall "database"

# Show recent changes
claude-memory changes

# Check for conflicts
claude-memory conflicts
```

### Promoting Facts to Global

When you want a project preference to apply everywhere:

```
You: "I like using descriptive variable names - remember that for all my projects"
Claude: [stores with scope_hint: global]
```

Or promote manually:

```bash
# List project facts
claude-memory recall --scope project

# Promote by ID
claude-memory promote 42
```

## Verification

### Run Doctor Command

Check system health:

```bash
claude-memory doctor
```

Expected output (healthy system):
```
ClaudeMemory Doctor Report
==========================

✓ Global database: ~/.claude/memory.sqlite3
  - Schema version: 6
  - Facts: 12
  - Entities: 8
  - Status: Healthy

✓ Project database: .claude/memory.sqlite3
  - Schema version: 6
  - Facts: 23
  - Entities: 15
  - Status: Healthy

✓ MCP server: Configured
✓ Hooks: Active (5 hooks registered)

All systems operational.
```

### Check Database Creation

Verify files exist:

```bash
# Global database
ls -lh ~/.claude/memory.sqlite3
# => -rw-r--r-- 1 user staff 128K Jan 26 10:30 /Users/user/.claude/memory.sqlite3

# Project database
ls -lh .claude/memory.sqlite3
# => -rw-r--r-- 1 user staff 64K Jan 26 10:35 .claude/memory.sqlite3
```

### Test Memory Recall

Have a conversation with Claude to test:

```
You: "What database am I using?"
Claude: [calls memory.recall]
Claude: "According to my memory, this project uses PostgreSQL."

# Success! Memory is working.
```

## Common Workflows

### Workflow 1: Setting Up a New Project (Plugin Already Installed)

You've installed the plugin globally, now you're starting a new project:

```bash
# 1. Create or enter your project directory
cd ~/projects/new-app

# 2. Initialize project memory
claude-memory init

# 3. Start Claude Code and talk about your project
claude

# 4. Let Claude know about your stack
"This is a Next.js 14 app with TypeScript, using Supabase for the database"

# 5. Verify memory
"What do you remember about this project?"
```

### Workflow 2: Moving Between Projects

Your global preferences travel with you:

```bash
# Project A
cd ~/projects/api-server
claude
"Help me add authentication"
# Claude recalls: api-server uses Express + PostgreSQL

# Project B
cd ~/projects/frontend
claude
"Help me add authentication"
# Claude recalls: frontend uses Next.js + Supabase
# Claude ALSO recalls: Your global preference for descriptive names
```

### Workflow 3: Sharing Project Memory with Team

The project database can be committed to git:

```bash
# Option 1: Commit project memory (recommended)
git add .claude/memory.sqlite3
git commit -m "Add project memory snapshot"
# Team members get bootstrapped knowledge

# Option 2: Ignore project memory (each person builds their own)
echo ".claude/memory.sqlite3" >> .gitignore
# Each developer has personal project memory
```

**Recommendation**: Commit project memory for teams to share architectural decisions and tech stack knowledge.

### Workflow 4: Privacy Control

Exclude sensitive data using privacy tags:

```
You: "My API key is <private>sk-abc123def456</private>"
Claude: [uses it during session, but won't store it]

# What gets stored: "API key configured for external service"
# What DOESN'T get stored: "sk-abc123def456"
```

Supported tags:
- `<private>content</private>` - Excludes content from memory
- `<no-memory>content</no-memory>` - Same as private
- `<secret>content</secret>` - Same as private

## Troubleshooting

### MCP Tools Not Appearing

**Problem**: Claude doesn't seem to have access to memory tools

**Solutions**:
1. Check `claude-memory` is in PATH:
   ```bash
   which claude-memory
   # Should show: /path/to/bin/claude-memory
   ```

2. Verify plugin installation:
   ```bash
   /plugin
   # Navigate to "Installed" tab, look for "claude-memory"
   ```

3. Check for errors:
   ```bash
   /plugin
   # Navigate to "Errors" tab for any issues
   ```

4. Restart Claude Code:
   ```bash
   # Exit and relaunch claude command
   ```

### Facts Not Being Stored

**Problem**: Claude doesn't remember things from previous conversations

**Possible causes**:
1. **Session didn't stop**: Prompt hooks require the session to actually stop (not just pause)
   - Solution: Exit Claude Code properly with `/exit` or Ctrl+D

2. **Hooks not registered**: Check hook configuration
   - Solution: Run `claude-memory init` again to reconfigure hooks

3. **Database not created**: Missing database files
   - Solution: Run `claude-memory doctor` to diagnose

4. **Extraction failed**: Claude couldn't parse facts
   - Solution: Be explicit: "Remember that we use PostgreSQL"

### Database Not Created

**Problem**: `.claude/memory.sqlite3` doesn't exist after init

**Solutions**:
1. Check permissions:
   ```bash
   ls -la .claude/
   # Should be writable by your user
   ```

2. Create directory manually:
   ```bash
   mkdir -p .claude
   chmod 755 .claude
   claude-memory init
   ```

3. Check disk space:
   ```bash
   df -h .
   # Ensure you have available space
   ```

### Migration Failures

**Problem**: Error messages about schema migration during upgrade

**What happens automatically**:
- Schema migrations run on first database access
- Migrations are atomic (all-or-nothing)
- Your data is safe (migrations don't delete data)

**Recovery**:
```bash
# Check current state
claude-memory doctor

# If database is corrupted, check schema
claude-memory doctor --verbose

# Last resort: reinitialize (THIS WILL ERASE DATA)
mv .claude/memory.sqlite3 .claude/memory.sqlite3.backup
claude-memory init
```

### Conflicts Between Facts

**Problem**: Claude shows conflicting information

**Solution**: Check and resolve conflicts:
```bash
# List conflicts
claude-memory conflicts

# Or ask Claude
"Are there any conflicting facts in memory?"

# Resolve by updating facts (Claude will supersede old facts)
"Actually, we switched from MySQL to PostgreSQL last week"
```

## Advanced Usage

### Manual Fact Management

```bash
# Search facts
claude-memory recall "authentication"

# Show detailed provenance
claude-memory explain <fact_id>

# List recent changes
claude-memory changes --since "2026-01-20"

# Run maintenance
claude-memory sweep
```

### Custom Hook Configuration

Modify `.claude/settings.json` to customize when memory updates:

```json
{
  "hooks": {
    "Stop": {
      "command": "claude-memory hook ingest"
    }
  }
}
```

### Debugging

Enable verbose output:

```bash
# See what's happening during ingestion
claude-memory hook ingest --verbose < ~/.claude/sessions/latest.jsonl

# Check database contents
sqlite3 .claude/memory.sqlite3 "SELECT * FROM facts LIMIT 5;"
```

## Next Steps

Now that you're up and running:

- 📖 Read [Examples](EXAMPLES.md) for common use cases
- 🔧 Explore [Plugin Documentation](PLUGIN.md) for advanced configuration
- 🏗️ Review [Architecture](architecture.md) for technical details
- 💬 Join [Discussions](https://github.com/codenamev/claude_memory/discussions) to share feedback

## Quick Reference

| Command | Purpose |
|---------|---------|
| `claude-memory init` | Initialize databases and hooks |
| `claude-memory doctor` | Check system health |
| `claude-memory recall <query>` | Search for facts |
| `claude-memory promote <fact_id>` | Make fact global |
| `claude-memory changes` | Recent updates |
| `claude-memory conflicts` | Show contradictions |
| `/claude-memory:analyze` | Bootstrap project knowledge |

## Support

- 🐛 [Report a bug](https://github.com/codenamev/claude_memory/issues)
- 💬 [Discussions](https://github.com/codenamev/claude_memory/discussions)
- 📧 Questions? Open an issue!

---

**Ready to start?** Jump back to your project and have a conversation with Claude. Memory happens automatically! 🚀
