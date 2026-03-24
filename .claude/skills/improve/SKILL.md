---
name: improve
description: Incrementally implement feature improvements from docs/improvements.md with tests and atomic commits. Focuses on new functionality rather than refactoring.
agent: general-purpose
allowed-tools: Read, Grep, Edit, Write, Bash
arguments:
  - name: mode
    description: "Execution mode: 'sub-agent' (default, sequential) or 'agent-team' (parallel via agent teams)"
    required: false
    default: "sub-agent"
---

# Feature Improvements - Incremental Implementation

Systematically implement feature improvements from `docs/improvements.md`, making tested, atomic commits for each feature addition.

## Execution Modes

This skill supports two modes, passed as the first argument:

- **`sub-agent`** (default): A single agent works through improvements sequentially. Best for small batches (1-3 features) or features with dependencies.
- **`agent-team`**: Spawns a coordinated team of agents that implement independent features in parallel. Best for larger batches (3+) of independent features.

---

## Mode: agent-team

When invoked with `agent-team`, follow this process:

### Step 1: Read and Assess Improvements

Read `docs/improvements.md` and identify all implementable features using the same feasibility criteria as sub-agent mode (skip Categories D-F, "Features to Avoid", "If Requested" items).

### Step 2: Group Independent Features

Partition implementable features into independent groups:
- Features touching **different files** can be parallelized
- Features sharing files or with dependencies must be sequential
- Aim for 3-5 teammates maximum

### Step 3: Create the Agent Team

Create an agent team. For each teammate:

1. **Assign one or two related features** per teammate
2. **Provide full context** — teammates don't share your conversation history
3. **Include these instructions for each teammate**:
   - Read relevant existing code before making changes
   - Follow the project's code style (Standard Ruby, frozen_string_literal)
   - Write tests for all new functionality
   - Run `bundle exec rake standard:fix` before committing
   - Run relevant spec file after each edit, full suite before committing
   - Run `bundle exec rspec` to verify all tests pass
   - Make atomic commits with `[Feature]` prefix format
   - Update `docs/improvements.md` to mark features as implemented
   - Reference `.claude/skills/improve/feature-patterns.md` for implementation recipes

### Step 4: Monitor and Coordinate

- Wait for all teammates to complete their tasks
- If a teammate reports a blocker or conflict, help resolve it
- Do NOT implement tasks yourself — let teammates do the work

### Step 5: Validate and Report

After all teammates finish:

1. Run the full test suite: `bundle exec rspec`
2. Run the linter: `bundle exec rake standard:fix`
3. If any failures, fix them or coordinate with the relevant teammate
4. Provide a consolidated progress report (same Final Report format as sub-agent mode)

---

## Mode: sub-agent (default)

## Process Overview

1. **Check memory health** by calling `memory.check_setup` to verify the system is operational
2. **Read the improvements document** from `docs/improvements.md`
3. **Identify unimplemented features** from "Remaining Tasks" section
4. **Prioritize by stated priority** (Medium → Low)
5. **Assess feasibility** (skip if too complex or requires external services)
6. **Implement features incrementally** (one logical feature at a time)
7. **Run tests after each change** to ensure nothing breaks
8. **Make atomic commits** that capture the feature and its purpose
9. **Update improvements.md** to mark features as implemented

## Detailed Steps

### Step 0: Verify Memory Health

Before starting, confirm the memory system is operational:

```
memory.check_setup
```

If status is not "healthy", address any issues before proceeding.

### Step 1: Read and Parse Improvements Document

```bash
# Read the improvements document
Read docs/improvements.md
```

Focus on these sections:
1. **Remaining Tasks** - Unimplemented features
2. **Medium Priority** - Higher value features
3. **Low Priority** - Nice-to-have features
4. **Features to Avoid** - Do NOT implement these

### Step 2: Prioritize Features

**Priority Order:**
1. Medium Priority items first
2. Low Priority items second
3. Skip items marked "If Requested" or "Features to Avoid"

**Feasibility Assessment:**
- ✅ **Can implement**: Pure Ruby, no external services, clear scope
- ⚠️ **Consider carefully**: Requires API integration, new dependencies
- ❌ **Skip**: Requires external services, architectural changes, unclear requirements

### Step 3: Assess Each Feature

Before implementing, check:

**✅ Safe to implement automatically:**
- Small database schema additions (new columns, tables)
- New CLI commands with clear behavior
- Utility methods and helpers
- Enhanced output formatting
- Statistics and reporting features

**⚠️ Implement with caution:**
- Features requiring API calls (Claude API, external services)
- New gem dependencies (check compatibility first)
- Background processing (daemon/fork complexity)
- Features touching critical paths

**❌ Skip and report:**
- Web UI features (React, Sinatra, complex frontend)
- Worker service/daemon management
- Features requiring Python/Node.js
- Vector database integration (ChromaDB, external services)
- Health monitoring (unless simple)

### Step 4: Implement the Feature

For each feature:

1. **Read relevant code** to understand where feature fits
2. **Plan the implementation**:
   - Which files need changes?
   - What tests are needed?
   - Are there dependencies?
3. **Implement incrementally**:
   - Schema changes first (if needed)
   - Core functionality
   - CLI command (if applicable)
   - Tests
4. **Run linter**:
   ```bash
   bundle exec rake standard:fix
   ```
5. **Run targeted tests** after each edit:
   ```bash
   bundle exec rspec spec/claude_memory/<relevant_spec>.rb
   ```
6. **Run full suite** before committing:
   ```bash
   bundle exec rspec
   ```
7. **Fix any test failures** before proceeding

### Step 5: Make Atomic Commit

**Commit Message Format:**
```
[Feature] Brief description of what was added

- Specific implementation details
- Why this improves the system
- Reference to docs/improvements.md section

Implements: docs/improvements.md (Section: <name>)
```

**Example Commit:**
```bash
git add -A
git commit -m "[Feature] Add ROI metrics tracking for distillation

- Add ingestion_metrics table with token counts
- Track input_tokens, output_tokens, facts_extracted
- Add metrics display to stats command
- Show efficiency (facts per 1k tokens)

Implements: docs/improvements.md (Section: ROI Metrics and Token Economics)
"
```

### Step 6: Update improvements.md

After successful implementation:

1. **Move item to "Implemented Improvements"** section
2. **Add date and brief description**
3. **Update "Remaining Tasks"** to remove completed item
4. **Commit the documentation update**:
   ```bash
   git add docs/improvements.md
   git commit -m "[Docs] Mark <feature> as implemented"
   ```

### Step 7: Continue or Report

**Continue** to next feature if:
- Tests pass ✅
- Commit successful ✅
- Feature works as expected ✅
- No blockers encountered ✅

**Stop and report** if:
- Tests fail after multiple fix attempts ❌
- Feature requires external services ❌
- Complexity exceeds estimate ❌
- Unclear requirements ❌
- Time budget exceeded ❌

## Feature Categories & Approach

### Category A: Schema Additions (Low Risk)
**Examples:**
- Add metrics table
- Add columns for metadata
- Add indexes

**Approach:**
- Schema version bump
- Migration method
- Tests for new schema
- Single commit

### Category B: Statistics & Reporting (Low Risk)
**Examples:**
- Enhanced stats command
- ROI metrics display
- Better formatting

**Approach:**
- Query implementation
- Output formatting
- Tests for accuracy
- Single commit

### Category C: CLI Commands (Low-Medium Risk)
**Examples:**
- New commands (embed, stats enhancements)
- Command options

**Approach:**
- Command class
- Registry update
- Tests for command
- Help documentation
- Single commit

### Category D: Background Processing (Medium Risk)
**Examples:**
- Async hook execution
- Fork/daemon processes

**Approach:**
- **ASSESS CAREFULLY** - fork/daemon in Ruby is tricky
- Consider simple async approach first
- Test on multiple platforms
- May need multiple commits
- May skip if too complex

### Category E: External Integration (Medium-High Risk)
**Examples:**
- API calls (Claude, external services)
- New gem dependencies
- External tool integration

**Approach:**
- **ASSESS CAREFULLY** - adds dependencies
- Check gem compatibility
- Error handling critical
- May need API keys
- Consider skipping if complex

### Category F: Architectural Changes (High Risk)
**Examples:**
- Worker services
- Web UI
- New database systems

**Approach:**
- **SKIP** - too complex for automated implementation
- Report as "needs planning"
- These require design sessions

## Implementation Examples

### Example 1: ROI Metrics (Medium Priority)

**Assessment**: Category A + B (Schema + Reporting) - Safe to implement

**Steps:**
1. Add migration for ingestion_metrics table
2. Add tracking in distiller (if implemented) or stub for future
3. Add aggregation query methods
4. Enhance stats command to display metrics
5. Add tests
6. Commit
7. Update improvements.md

**Time Estimate**: 30-45 minutes

### Example 2: Background Processing (Medium Priority)

**Assessment**: Category D (Background) - Medium risk

**Steps:**
1. Research Ruby async options (Process.fork vs Thread)
2. Add --async flag to hook commands
3. Simple fork approach (not full daemon)
4. Output logging
5. Tests on Unix systems (may skip Windows)
6. Commit
7. Update improvements.md

**Time Estimate**: 45-60 minutes
**Risk**: May skip if too complex

### Example 3: Web UI (Low Priority, "If Requested")

**Assessment**: Category F (Architectural) - High risk

**Action**: **SKIP** - Too complex, marked "if requested"
**Report**: "Web UI requires design session, skipped per priority guidance"

## Decision Tree

```
Read next feature from improvements.md
↓
Is it marked "Features to Avoid"?
├─ YES → SKIP completely
└─ NO → Continue
    ↓
    Is it marked "If Requested"?
    ├─ YES → SKIP, note as "needs user request"
    └─ NO → Continue
        ↓
        Assess category (A-F)
        ↓
        Category F (Architectural)?
        ├─ YES → SKIP, report as "needs planning"
        └─ NO → Continue
            ↓
            Category E (External)?
            ├─ YES → Assess carefully, may skip
            └─ NO → Continue
                ↓
                Category D (Background)?
                ├─ YES → Assess carefully, may skip
                └─ NO → Continue
                    ↓
                    Does it have dependencies on other features?
                    ├─ YES → Are dependencies complete?
                    │   ├─ NO → SKIP, note dependency
                    │   └─ YES → Continue
                    └─ NO → Implement (Categories A-C safe)
                        ↓
                        Implement the feature
                    ↓
                    Run tests
                    ↓
                    Tests pass?
                    ├─ NO → Can fix in < 20 min?
                    │   ├─ YES → Fix and retry
                    │   └─ NO → SKIP, report as "complex"
                    └─ YES → Continue
                        ↓
                        Commit with [Feature] message
                        ↓
                        Update improvements.md
                        ↓
                        Commit documentation update
                        ↓
                        Next feature
```

## Time Budgets

**Per Feature:**
- Category A (Schema): Max 15 minutes — skip if stuck after 15
- Category B (Reporting): Max 20 minutes — skip if stuck after 20
- Category C (CLI): Max 30 minutes — skip if stuck after 30
- Category D (Background): Max 45 minutes (or skip at first sign of daemon complexity)
- Category E (External): Max 30 minutes (or skip at first sign of dependency issues)

**Per Debug Cycle:**
- Test failure fix: Max 15 minutes — if you can't fix it in 15 minutes, revert and skip
- Understanding code: Max 10 minutes — if unclear after 10 minutes, skip and report

**Session Total:** Max 2 hours

If time budget exceeded: SKIP remaining features and report.

## Testing Strategy

### Test Frequency
- After each file edit: Run the relevant spec file
- After schema changes: Run `spec/claude_memory/store/`
- After new command: Run `spec/claude_memory/commands/`
- Before each commit: Full test suite
- If >5 files changed: Full test suite immediately

### Test Commands
```bash
# Single relevant spec (fastest feedback)
bundle exec rspec spec/claude_memory/commands/metrics_command_spec.rb

# Module-level specs
bundle exec rspec spec/claude_memory/commands/
bundle exec rspec spec/claude_memory/store/

# Full suite (before commit)
bundle exec rspec

# With linting (final check)
bundle exec rake
```

### Test Failure Response
1. Read error message carefully
2. Check if your change caused it (vs pre-existing)
3. If your change: fix within 15 minutes or revert and skip
4. If pre-existing: note and continue
5. If unsure: revert change and skip item

### New Feature Tests

Always add tests for new features:
```ruby
# spec/claude_memory/commands/new_feature_spec.rb
RSpec.describe ClaudeMemory::Commands::NewFeature do
  it "implements the feature correctly" do
    # Test implementation
  end

  it "handles errors gracefully" do
    # Test error cases
  end
end
```

## Documentation Updates

### After Each Implementation

Update `docs/improvements.md`:

1. **Move to Implemented section**:
   ```markdown
   ## Implemented Improvements ✓

   14. **ROI Metrics Tracking** - ingestion_metrics table, stats display
   ```

2. **Remove from Remaining Tasks**:
   ```markdown
   ### Remaining Tasks

   - [x] ROI metrics table for token tracking during distillation
   - [ ] Background processing (--async flag for hooks)
   ```

3. **Update last modified date**:
   ```markdown
   *Last updated: 2026-01-26 - Added ROI metrics tracking*
   ```

## Progress Tracking

Keep running count:
- ✅ Medium Priority completed: X/Y
- ✅ Low Priority completed: X/Y
- ⏳ Currently working on: [feature name]
- ⚠️ Skipped (complex): [list]
- ❌ Blocked: [list with reasons]

## Success Criteria

Session completes successfully when:
- At least 2-3 Medium Priority features implemented ✅
- All tests pass ✅
- All commits follow [Feature] format ✅
- docs/improvements.md updated ✅
- Progress report provided ✅

## Important Notes

- **Never skip tests** - each feature must pass tests before committing
- **Stay conservative** - skip complex features, report them
- **One feature at a time** - don't combine unrelated features
- **Update documentation** - mark features as implemented
- **Read before coding** - understand existing code first
- **Check dependencies** - verify gems are compatible
- **Test incrementally** - after each logical step

## Red Flags - When to Skip

Skip feature and report if you encounter:
- 🚩 Requires external services (ChromaDB, web servers, etc.)
- 🚩 Needs background daemon/worker
- 🚩 Requires new major dependencies
- 🚩 Touches security-critical code
- 🚩 Unclear requirements or scope
- 🚩 Time budget exceeded
- 🚩 Marked "Features to Avoid"
- 🚩 Marked "If Requested" or "Only if users request"
- 🚩 Tests fail after 2 fix attempts

## Example Session

```
Session Start: 2026-01-26 14:00

1. Read docs/improvements.md
   - Found 4 Remaining Tasks
   - 2 Medium Priority, 2 Low Priority
   - Plan: Start with Medium Priority

2. Medium Priority #1: Background Processing (--async flag)
   - Category: D (Background)
   - Assessment: Medium risk, daemon complexity
   - TIME ESTIMATE: 60 minutes
   - DECISION: SKIP - Too complex, needs design
   - Reason: Ruby daemon management is tricky, fork approach needs careful testing

3. Medium Priority #2: ROI Metrics Tracking
   - Category: A + B (Schema + Reporting)
   - Assessment: Low risk
   - Implement:
     a. Add schema migration v7
     b. Add ingestion_metrics table
     c. Add aggregate_metrics method to store
     d. Enhance stats command
     e. Add tests
   - Run: bundle exec rspec ✅
   - Commit: [Feature] Add ROI metrics tracking... ✅
   - Update: docs/improvements.md ✅
   - Commit: [Docs] Mark ROI metrics as implemented ✅

4. Low Priority #1: Structured Logging
   - Category: C (CLI)
   - Assessment: Low risk
   - Implement:
     a. Add Logger configuration
     b. Add JSON formatter
     c. Add log output to commands
     d. Add --log-level flag
     e. Add tests
   - Run: bundle exec rspec ✅
   - Commit: [Feature] Add structured logging... ✅
   - Update: docs/improvements.md ✅
   - Commit: [Docs] Mark structured logging as implemented ✅

5. Low Priority #2: Embed Command
   - Category: C (CLI)
   - Started implementation...
   - TIME LIMIT EXCEEDED (45 minutes)
   - SKIP - More complex than expected

Session End: 2026-01-26 15:30
Duration: 1.5 hours

Results:
- Medium Priority: 1/2 completed (1 skipped - too complex)
- Low Priority: 1/2 completed (1 time exceeded)
- Commits: 4 (2 feature, 2 docs)
- Tests: All passing ✅
- Features added: ROI metrics, Structured logging
```

## Final Report Format

```
## Feature Implementation Session Report

### Completed ✅
1. [Medium] ROI Metrics Tracking (commit: abc123)
   - Added ingestion_metrics table
   - Enhanced stats command
   - Shows token efficiency metrics

2. [Low] Structured Logging (commit: def456)
   - JSON log formatter
   - --log-level flag for commands
   - Better debugging visibility

### Skipped ⚠️
- [Medium] Background Processing (--async flag)
  - Reason: Ruby daemon complexity, needs design session
  - Recommendation: Plan this separately with forking strategy

- [Low] Embed Command
  - Reason: Time budget exceeded (45 min)
  - Progress: 60% complete, needs embedding generation logic
  - Recommendation: Complete in focused session

### Summary
- Medium Priority: 1/2 completed (50%)
- Low Priority: 1/2 completed (50%)
- Tests: All passing ✅
- Commits: 4 total (2 features + 2 docs)
- Time: 1.5 hours

### Next Steps
1. Design session for background processing
2. Complete embed command implementation
3. Consider remaining Low Priority items
4. Run /review-for-quality to assess any code quality issues from new features
```
