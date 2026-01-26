# Implementation Guide for Quality Updates

## Fix Categories & Approach

### Category 1: Style & Convention Fixes (Low Risk)
**Examples:**
- Moving public/private method groups
- Consistent method parentheses
- Fixing attr_reader placement
- Consolidating ENV access

**Approach:**
- Safe to do immediately
- Run standard:fix after changes
- Verify tests still pass
- Commit individually

### Category 2: Simple Refactoring (Low-Medium Risk)
**Examples:**
- Extract small methods from long methods
- Rename for clarity
- Remove duplicate code
- Add guard clauses

**Approach:**
- Read surrounding code first
- Make change incrementally
- Run tests frequently
- Commit when tests pass

### Category 3: Structural Changes (Medium Risk)
**Examples:**
- Extract new classes
- Introduce value objects
- Add null objects
- Create parameter objects

**Approach:**
- Plan the extraction first
- Create new class/file
- Move code incrementally
- Update tests as you go
- Commit the structure, then usage

### Category 4: Database Changes (Medium-High Risk)
**Examples:**
- Migration framework changes
- Schema modifications
- DateTime conversions
- Transaction additions

**Approach:**
- Test with backup database first
- Ensure backward compatibility
- Update tests for new behavior
- May need multiple commits
- Consider skipping and reporting if complex

### Category 5: Architectural Changes (High Risk)
**Examples:**
- Splitting god objects (500+ lines)
- Changing abstraction boundaries
- Introducing new patterns
- Major refactoring

**Approach:**
- **SKIP these** - too large for automated fixes
- Report that they need manual planning
- Suggest running /review-for-quality after other fixes
- These need dedicated planning sessions

## Prioritization Algorithm

### Start with Quick Wins (Appendix B)
1. Read all Quick Wins from docs/quality_review.md
2. Sort by risk (lowest first)
3. Implement in order
4. Goal: Complete all Quick Wins in first pass

### Move to High Priority Items
1. Read all High Priority items
2. Filter out Category 5 (Architectural) - skip these
3. Sort remaining by:
   - Risk (low to high)
   - Dependencies (prerequisites first)
   - Impact (high impact first if equal risk)
4. Implement sorted list
5. Goal: Complete 3-5 items before stopping

### Skip Medium/Low Priority
- Only tackle these if explicitly requested
- Focus on Quick Wins + High Priority for automated fixes

## Common Patterns & Solutions

### Pattern: God Object (500+ lines)
**Assessment:** Category 5 - Architectural
**Action:** SKIP - Report that this needs manual planning
**Reason:** Too complex for automated incremental fixes

### Pattern: Duplicate Code (DRY violation)
**Assessment:** Category 2 - Simple Refactoring
**Action:** Extract to shared method/class
**Steps:**
1. Identify all occurrences
2. Create extracted method/class
3. Replace first occurrence
4. Test
5. Replace remaining occurrences
6. Test
7. Commit

### Pattern: Nil Checks Everywhere
**Assessment:** Category 3 - Structural (Null Object)
**Action:** Introduce NullObject pattern
**Steps:**
1. Create NullObject class (e.g., NullFact)
2. Implement required interface
3. Replace `return nil` with `return NullFact.new`
4. Remove nil checks in callers
5. Test incrementally
6. Commit structure first, then usage changes

### Pattern: Raw SQL Instead of Sequel
**Assessment:** Category 2 - Simple Refactoring
**Action:** Replace with Sequel datasets
**Steps:**
1. Read the SQL query
2. Translate to Sequel dataset methods
3. Test the query returns same results
4. Replace in code
5. Test
6. Commit

### Pattern: Long Method (> 20 lines)
**Assessment:** Category 2 - Simple Refactoring
**Action:** Extract smaller methods
**Steps:**
1. Identify logical sections
2. Extract one section to private method
3. Name method clearly
4. Test
5. Commit
6. Repeat for remaining sections

### Pattern: Mixed I/O and Logic
**Assessment:** Category 3-4 - Structural
**Action:** Extract pure logic to separate method/class
**Steps:**
1. Identify pure logic (no I/O)
2. Extract to separate method/class
3. Pass data as parameters
4. Call from original method
5. Test both paths
6. Commit

## Decision Tree

```
Start with next item from review
↓
Is it Category 5 (Architectural)?
├─ YES → SKIP, report as "needs planning"
└─ NO → Continue
    ↓
    Does it have dependencies?
    ├─ YES → Are dependencies complete?
    │   ├─ NO → SKIP, note dependency
    │   └─ YES → Continue
    └─ NO → Continue
        ↓
        Can you understand the code?
        ├─ NO → SKIP, report as "unclear"
        └─ YES → Continue
            ↓
            Implement the fix
            ↓
            Run tests
            ↓
            Tests pass?
            ├─ NO → Can fix in < 15 min?
            │   ├─ YES → Fix and retry
            │   └─ NO → SKIP, report as "complex"
            └─ YES → Continue
                ↓
                Commit with quality message
                ↓
                Next item
```

## Time Budgets

Set time limits to avoid getting stuck:

- **Quick Win**: Max 15 minutes per item
- **High Priority**: Max 30 minutes per item
- **Debug test failure**: Max 15 minutes
- **Understand code**: Max 10 minutes

If time limit exceeded: SKIP and report reason

## Testing Strategy

### Test Frequency
- After every file edit: Run relevant spec file
- After every commit: Run full suite
- If >5 files changed: Run full suite

### Test Commands
```bash
# Single file
bundle exec rspec spec/claude_memory/store/sqlite_store_spec.rb

# Full suite
bundle exec rspec

# With linting
bundle exec rake
```

### Test Failure Response
1. Read error message carefully
2. Check if your change caused it
3. If yes: Fix the change
4. If no: Might be pre-existing, note and continue
5. If unsure: Revert change and skip item

## Git Best Practices

### Before Committing
```bash
# Check status
git status

# Review changes
git diff

# Stage specific files (not -A if unnecessary)
git add lib/claude_memory/store/sqlite_store.rb

# Or stage all if appropriate
git add -A

# Commit with quality message
git commit -m "[Quality] ..."
```

### Commit Message Template
```
[Quality] <what was fixed in <50 chars>

- <specific change>
- <why this improves quality>
- <expert principle>

Addresses: docs/quality_review.md (<section>)
```

### After Committing
```bash
# Verify commit
git log -1 --oneline

# Continue to next item
```

## Red Flags - When to Stop

Stop implementing and report if you encounter:
- 🚩 Tests fail after 2 fix attempts
- 🚩 Change requires modifying >10 files
- 🚩 Change requires new gem dependencies
- 🚩 Change touches critical path (authentication, data integrity)
- 🚩 Unclear what the correct fix should be
- 🚩 Time budget exceeded
- 🚩 Git conflicts or merge issues

## Success Metrics

Good session results:
- ✅ 5+ commits made
- ✅ All tests passing
- ✅ All Quick Wins completed
- ✅ 3-5 High Priority items completed
- ✅ Clear report of progress
- ✅ No broken code left behind

## Example Full Session

```
Session Start: 2026-01-26 10:00

1. Read docs/quality_review.md
   - Found 5 Quick Wins
   - Found 6 High Priority items
   - Plan: Complete all Quick Wins first

2. Quick Win #1: Fix public keyword in SQLiteStore
   - Read lib/claude_memory/store/sqlite_store.rb
   - Moved public methods to top (lines 10-350)
   - Moved private methods to bottom (lines 351-542)
   - Run: bundle exec rspec spec/claude_memory/store/sqlite_store_spec.rb ✅
   - Commit: [Quality] Fix public keyword placement... ✅

3. Quick Win #2: Consolidate ENV access
   - Read lib/claude_memory/configuration.rb
   - Added global_db_path and project_db_path methods
   - Updated 3 files to use Configuration
   - Run: bundle exec rspec ✅
   - Commit: [Quality] Consolidate ENV access via Configuration ✅

4. Quick Win #3: Extract BatchQueryBuilder
   - Created lib/claude_memory/recall/batch_query_builder.rb
   - Extracted logic from batch_find_facts and batch_find_receipts
   - Updated recall.rb to use new class
   - Run: bundle exec rspec ✅
   - Commit: [Quality] Extract BatchQueryBuilder from Recall ✅

5. Quick Win #4: Fix boolean logic in option parsing
   - Found in lib/claude_memory/commands/recall_command.rb
   - Simplified double-negative logic
   - Run: bundle exec rspec ✅
   - Commit: [Quality] Simplify boolean logic in option parsing ✅

6. Quick Win #5: Extract Formatter from MCP Tools
   - Created lib/claude_memory/mcp/formatter.rb
   - Moved formatting methods
   - Updated tools.rb to use Formatter
   - Run: bundle exec rspec ✅
   - Commit: [Quality] Extract Formatter from MCP Tools ✅

7. High Priority #1: Extract DatabaseCheck from DoctorCommand
   - Started work...
   - TIME LIMIT EXCEEDED (45 minutes)
   - SKIP - Too complex, needs planning

Session End: 2026-01-26 11:30
Duration: 1.5 hours

Results:
- Quick Wins: 5/5 completed ✅
- High Priority: 0/6 completed (1 attempted)
- Commits: 5 atomic commits
- Tests: All passing ✅
- Issues: High Priority items need more planning time
```
