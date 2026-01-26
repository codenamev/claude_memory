# Auto-Initialization and Upgrade Design

## Problem Statement

When users install ClaudeMemory (add to MCP), they must manually run `claude-memory init`. There's no:
- Automatic detection of uninitialized state
- Upgrade detection when CLAUDE.md instructions change
- Graceful degradation when not configured

## Constraints

1. **No hooks before init**: Can't use SessionStart hook to auto-init (hooks aren't configured yet)
2. **MCP server is stateless**: Starts fresh each time, no persistent memory
3. **Skills unavailable pre-init**: Can't use skills to detect/fix initialization

## Proposed Multi-Layer Solution

### Layer 1: Setup Status MCP Tool (Immediate Detection)

**Add new MCP tool: `memory.check_setup`**

```ruby
{
  name: "memory.check_setup",
  description: "Check if ClaudeMemory is properly initialized. CALL THIS FIRST if memory tools fail or on first use of ClaudeMemory.",
  result: {
    initialized: true/false,
    version: "1.2.3",
    issues: ["No CLAUDE.md found", "Hooks not configured"],
    recommendation: "Run: claude-memory init"
  }
}
```

**Implementation:**
- Check for database existence
- Check for CLAUDE.md with version marker
- Check for hooks configuration
- Return actionable recommendations

**Update other tool descriptions:**
```ruby
description: "... If this tool fails with 'database not found', run memory.check_setup for guidance."
```

### Layer 2: Version Markers (Upgrade Detection)

**Add version to CLAUDE.md:**

```markdown
<!-- ClaudeMemory v1.0.0 -->
# ClaudeMemory

...
```

**Create `claude-memory upgrade` command:**
- Detect current version in CLAUDE.md
- Compare with ClaudeMemory::VERSION
- Offer to upgrade instructions
- Preserve user customizations

**Workflow:**
```bash
$ claude-memory upgrade
Checking configuration version...
Current: v0.9.0
Latest: v1.0.0

Changes in v1.0.0:
- Added memory-first workflow instructions
- Updated tool descriptions
- New /check-memory skill

Upgrade? [y/N] y
✓ Backed up old CLAUDE.md to CLAUDE.md.backup
✓ Updated workflow instructions
✓ Preserved custom sections
```

### Layer 3: Graceful Degradation (Error Handling)

**Update MCP Tools to detect uninitialized state:**

```ruby
def recall(args)
  unless database_exists?
    return {
      error: "ClaudeMemory not initialized",
      help: "Run 'claude-memory init' to set up databases and configuration",
      documentation: "https://github.com/your-repo#installation"
    }
  end
  # ... normal recall logic
end
```

**Benefit**: Claude sees clear actionable errors instead of cryptic database failures.

### Layer 4: Setup Reminder Skill

**Create `/setup-memory` skill:**

```markdown
---
name: setup-memory
description: Guide user through ClaudeMemory installation
disable-model-invocation: true
---

# ClaudeMemory Setup Guide

ClaudeMemory is installed but not initialized.

## Quick Setup

Run this command:
```bash
claude-memory init
```

This will:
1. Create global and project databases
2. Configure hooks for automatic ingestion
3. Add workflow instructions to CLAUDE.md
4. Set up MCP server

After running, restart Claude Code to load the configuration.

## Verification

After init, run:
```bash
claude-memory doctor
```

## Need Help?

See: https://github.com/your-repo#troubleshooting
```

**Usage**: When Claude encounters "not initialized" errors, it can suggest: "Run `/setup-memory` for installation help"

### Layer 5: Doctor Command Enhancement

**Add `--fix` flag to doctor:**

```bash
$ claude-memory doctor --fix
Checking configuration...
✗ Project database missing
✗ No CLAUDE.md found

Would you like to run init? [y/N] y
Running: claude-memory init
...
```

**Add `--quiet` flag for programmatic checks:**

```bash
$ claude-memory doctor --quiet
# Exit code 0 = healthy, 1 = needs init, 2 = needs upgrade
```

## Implementation Priority

### Phase 1 (Immediate Value)
1. ✅ Add version markers to init command
2. ✅ Create `memory.check_setup` MCP tool
3. ✅ Update error messages with actionable help
4. ✅ Create `/setup-memory` skill

### Phase 2 (Enhanced UX)
5. ⬜ Create `claude-memory upgrade` command
6. ⬜ Add `doctor --fix` and `doctor --quiet`
7. ⬜ Add upgrade detection to SessionStart hook

### Phase 3 (Polish)
8. ⬜ Version migration system (v1.0.0 → v1.1.0)
9. ⬜ Preserve custom CLAUDE.md sections during upgrade
10. ⬜ Add upgrade notifications via MCP tool

## Decision: Why Not Auto-Init?

We deliberately **don't** auto-initialize because:

1. **User control**: Installation should be explicit, not magical
2. **Git hygiene**: Creates `.claude/` directory - users should understand this
3. **Global vs project**: Users choose `--global` or project-local
4. **Customization**: Users may want to review CLAUDE.md before committing

Instead, we make initialization **obvious** and **frictionless** when needed.

## Example User Journey

### First-Time User

```
User: Where are client errors handled?
Claude: Let me check memory...
Claude: (calls memory.recall)
MCP: Error - database not found. Run memory.check_setup.
Claude: (calls memory.check_setup)
MCP: Not initialized. Run: claude-memory init
Claude: "It looks like ClaudeMemory isn't set up yet. Run `claude-memory init` to configure it. Would you like me to explain what this does first?"
```

### Upgrading User

```
User: Check memory about authentication
Claude: (calls memory.recall)
MCP: Returns results with warning: "Using outdated configuration v0.9.0. Run: claude-memory upgrade"
Claude: "I found these facts about authentication: [...]. Note: You can upgrade to the latest ClaudeMemory configuration by running `claude-memory upgrade`."
```

## Testing Strategy

- Unit tests for version detection logic
- Integration tests for upgrade workflow
- Manual testing of error messages
- Test preservation of custom CLAUDE.md sections

## Documentation Updates

- Update README with upgrade instructions
- Add CHANGELOG for version history
- Document version markers in CLAUDE.md
- Add troubleshooting guide for common issues
