---
name: setup-memory
description: Guide user through ClaudeMemory installation and setup
disable-model-invocation: true
---

# ClaudeMemory Setup Guide

This skill helps you install and configure ClaudeMemory when it's not initialized.

## Quick Setup

If you see errors about databases not found or ClaudeMemory not being initialized, run:

```bash
claude-memory init
```

This will:
- ✓ Create global database (~/.claude/memory.sqlite3)
- ✓ Create project database (.claude/memory.sqlite3)
- ✓ Configure hooks for automatic transcript ingestion
- ✓ Add workflow instructions to CLAUDE.md
- ✓ Set up MCP server configuration

## Installation Modes

### Project Setup (Recommended)

For project-specific memory alongside global knowledge:

```bash
claude-memory init
```

This creates both project and global databases.

### Global Setup Only

For user-wide memory without project-specific storage:

```bash
claude-memory init --global
```

Note: Run `claude-memory init` in each project later for project memory.

## After Installation

1. **Restart Claude Code** to load the new configuration
2. **Verify setup** by running:
   ```bash
   claude-memory doctor
   ```
3. **Test memory** by asking me a question - transcripts will be ingested automatically
4. **Check status** anytime with the `memory.status` tool

## What Gets Created

### Databases
- `~/.claude/memory.sqlite3` - Global knowledge (preferences, conventions)
- `.claude/memory.sqlite3` - Project-specific facts and decisions

### Configuration Files
- `.claude/CLAUDE.md` - Workflow instructions for memory-first usage
- `.claude/settings.json` - Hooks for automatic ingestion
- `.claude.json` - MCP server configuration
- `.claude/rules/claude_memory.generated.md` - Published snapshot

### Hooks
ClaudeMemory automatically ingests transcripts on these events:
- SessionStart - Catch up on previous session
- Stop - After each response
- SessionEnd - Final ingestion before closing
- PreCompact - Before context summarization

## Troubleshooting

### Permission Denied

If you get permission errors:
```bash
chmod +x $(which claude-memory)
```

### Database Locked

If you see "database is locked" errors:
- Close other Claude sessions
- Run `claude-memory doctor` to check for stuck operations
- If needed: `claude-memory recover` to reset stuck operations

### Missing Dependencies

ClaudeMemory requires Ruby 3.2.0+. Check your version:
```bash
ruby --version
```

If you need to install or upgrade Ruby, see: https://www.ruby-lang.org/en/downloads/

### Hooks Not Firing

If transcripts aren't being ingested:

1. Check hooks are configured:
   ```bash
   cat .claude/settings.json | grep -A5 hooks
   ```

2. Manually test ingestion:
   ```bash
   claude-memory ingest --session-id test --transcript-path ~/.claude/sessions/latest.transcript
   ```

3. Re-run init to fix configuration:
   ```bash
   claude-memory init
   ```

### Check Setup Status

Run this MCP tool to diagnose issues:
```
memory.check_setup
```

This returns:
- Initialization status
- Version information
- Missing components
- Actionable recommendations

## Upgrading

If you have an old version of ClaudeMemory installed:

```bash
claude-memory doctor
```

This will detect version mismatches and recommend:
- Re-running `claude-memory init` to update CLAUDE.md
- Running `claude-memory upgrade` (when available)

## Getting Help

- **Check health**: `claude-memory doctor`
- **View all commands**: `claude-memory help`
- **Get command help**: `claude-memory <command> --help`
- **Report issues**: https://github.com/anthropics/claude-memory/issues

## What's Next?

Once installed:

1. **Use memory tools proactively**:
   - `memory.recall` - Search for facts
   - `memory.decisions` - View architectural decisions
   - `memory.conventions` - Check coding preferences

2. **Let the system learn**:
   - Keep using Claude normally
   - Transcripts are ingested automatically
   - Facts are distilled and stored

3. **Manage your knowledge**:
   - `memory.conflicts` - Resolve contradictions
   - `memory.promote <fact_id>` - Move facts to global scope
   - `claude-memory publish` - Update published snapshot

## Memory-First Workflow

After setup, remember to check memory BEFORE reading files:

1. **Query memory first**: `memory.recall "<topic>"`
2. **Review results**: Understand existing knowledge
3. **Explore if needed**: Use Read/Grep only if memory is insufficient
4. **Combine context**: Merge recalled facts with code exploration

This saves time and provides better answers by leveraging distilled knowledge from previous sessions.
