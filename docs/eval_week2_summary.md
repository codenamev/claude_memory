# Week 2 Summary: Extract Patterns

**Date**: 2026-01-30
**Status**: ✅ Complete
**Duration**: ~1 hour

## What We Built

### Extracted Patterns

After implementing 3 eval scenarios in Week 1, clear patterns emerged. Week 2 focused on extracting these patterns without losing simplicity.

**Created**: `spec/evals/support/eval_helpers.rb`

This module provides 4 reusable components:

#### 1. SharedSetup Module
Common RSpec setup for all evals:
```ruby
include EvalHelpers::SharedSetup

# Provides:
# - let(:tmpdir) - Isolated temp directory
# - let(:db_path) - Memory database path
# - before/after hooks for cleanup
```

**Before** (repeated in each eval):
```ruby
let(:tmpdir) { Dir.mktmpdir("eval_name_#{Process.pid}") }
let(:db_path) { File.join(tmpdir, ".claude/memory.sqlite3") }

before { FileUtils.mkdir_p(File.dirname(db_path)) }
after { FileUtils.rm_rf(tmpdir) }
```

**After** (single include):
```ruby
include EvalHelpers::SharedSetup
```

**Lines saved**: ~6 per eval × 3 evals = 18 lines

#### 2. MemoryFixtureBuilder Class
Simplifies memory population:

**Before** (verbose, repetitive):
```ruby
store = ClaudeMemory::Store::SQLiteStore.new(db_path)
entity_id = store.find_or_create_entity(type: "repo", name: "test-project")

content_id = store.upsert_content_item(...)
fact_id = store.insert_fact(...)
store.insert_provenance(...)
fts = ClaudeMemory::Index::LexicalFTS.new(store)
fts.index_content_item(...)

store.close
```

**After** (declarative, clear intent):
```ruby
builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

builder.add_fact(
  predicate: "convention",
  object: "Use 2-space indentation",
  text: "Use 2-space indentation for Ruby files",
  fts_keywords: "coding convention style"
)

builder.close
```

**Benefits**:
- Single responsibility (fact creation)
- Hides implementation details (content items, provenance, FTS)
- Supports single fact (`add_fact`) or batch (`add_facts`)
- **Lines saved**: ~15-20 per eval

#### 3. ResponseStubs Module
Standardizes stubbed responses:

**Before**:
```ruby
{
  success: true,
  result: "Response text here...",
  session_id: "stub-session-123"
}
```

**After**:
```ruby
stub_success_response(
  "Response text here...",
  session_id: "stub-session-convention-memory"
)
```

**Benefits**:
- Consistent response format
- Explicit success/failure handling
- Less boilerplate

#### 4. ScoringHelpers Module
Simplifies common checks:

**Before**:
```ruby
mentions_indentation = response.include?("2-space") || response.include?("2 space")
mentions_rspec = response.include?("expect syntax") || response.include?("expect")

score = 0.0
score += 0.5 if mentions_indentation
score += 0.5 if mentions_rspec
```

**After**:
```ruby
mentions_indentation = includes_any?(response, "2-space", "2 space")
mentions_rspec = includes_any?(response, "expect syntax", "expect")

score = score_from_checks(mentions_indentation, mentions_rspec)
```

**Benefits**:
- `includes_all?` - All terms present
- `includes_any?` - Any term present
- `score_from_checks` - Automatic equal weighting

### Refactored All 3 Evals

Updated all eval specs to use helpers:
- `convention_recall_spec.rb`: 124 lines → 123 lines (cleaner, not shorter)
- `architectural_decision_spec.rb`: 130 lines → 120 lines (-10 lines)
- `tech_stack_recall_spec.rb`: 157 lines → 146 lines (-11 lines)

**Total reduction**: ~21 lines, but more importantly: **clearer intent**.

## Code Quality Improvements

### Before: Inline Everything (Week 1)
```ruby
def populate_fixture_memory
  store = ClaudeMemory::Store::SQLiteStore.new(db_path)
  entity_id = store.find_or_create_entity(type: "repo", name: "test-project")

  fact_id_1 = store.insert_fact(
    subject_entity_id: entity_id,
    predicate: "convention",
    object_literal: "Use 2-space indentation for Ruby files",
    scope: "project"
  )

  content_id_1 = store.upsert_content_item(
    source: "test",
    session_id: "test-session",
    text_hash: Digest::SHA256.hexdigest("2-space indentation"),
    byte_len: 20,
    raw_text: "Use 2-space indentation for Ruby files"
  )

  store.insert_provenance(
    fact_id: fact_id_1,
    content_item_id: content_id_1,
    quote: "2-space indentation",
    strength: "stated"
  )

  fts = ClaudeMemory::Index::LexicalFTS.new(store)
  fts.index_content_item(content_id_1, "Use 2-space indentation...")

  # Repeat for fact_id_2...

  store.close
end
```

### After: Extracted Helpers (Week 2)
```ruby
def populate_fixture_memory
  builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

  builder.add_facts([
    {
      predicate: "convention",
      object: "Use 2-space indentation for Ruby files",
      text: "Use 2-space indentation for Ruby files",
      fts_keywords: "coding convention style"
    },
    {
      predicate: "convention",
      object: "Prefer RSpec's expect syntax over should syntax",
      text: "Prefer RSpec's expect syntax over should syntax",
      fts_keywords: "convention style pattern"
    }
  ])

  builder.close
end
```

**Improvements**:
- ✅ Declarative (what, not how)
- ✅ Readable (clear intent)
- ✅ DRY (no repetition)
- ✅ Hides complexity (content items, provenance, FTS)

## Test Results

```bash
$ bundle exec rspec spec/evals/ --format documentation

Tech Stack Recall Eval
  with memory populated
    ✓ calculates accuracy score
    ✓ correctly identifies the testing framework
  fixture setup
    ✓ creates memory database with tech stack facts
  baseline (no memory)
    ✓ has lower accuracy score
    ✓ cannot identify the specific framework without memory

Convention Recall Eval
  fixture setup
    ✓ creates memory database with conventions
  baseline (no memory)
    ✓ does not mention specific project conventions
    ✓ has lower behavioral score than memory-enabled
  with memory populated
    ✓ mentions stored conventions when asked
    ✓ calculates behavioral score

Architectural Decision Eval
  fixture setup
    ✓ creates memory database with architectural decision
  with memory populated
    ✓ mentions the stored architectural decision
    ✓ calculates behavioral score for decision adherence
  baseline (no memory)
    ✓ has lower decision adherence score
    ✓ gives generic advice without knowing the decision

Finished in 0.23s
15 examples, 0 failures ✅
```

## Design Principles Applied

### Sandi Metz: Extract Only When Painful

> "Extract collaborators only when you feel pain"

**Week 1**: Inline everything, no abstractions
**Week 2**: Felt pain after 3 evals, extracted patterns
✅ **Right timing**: Extracted based on real needs, not speculation

### Kent Beck: Incremental Design

> "Make it work, make it right, make it fast"

**Week 1**: Make it work (3 evals passing)
**Week 2**: Make it right (extract patterns)
✅ **Emerged design**: Abstraction emerged from real usage

### Avdi Grimm: Tell, Don't Ask

**Before**:
```ruby
store = ClaudeMemory::Store::SQLiteStore.new(db_path)
entity_id = store.find_or_create_entity(...)
fact_id = store.insert_fact(...)
# ... more imperative steps
```

**After**:
```ruby
builder.add_fact(predicate: "convention", object: "...", text: "...")
```

✅ **Declarative**: Tell builder what to create, not how

## Files Modified

```
spec/evals/support/
└── eval_helpers.rb                    # NEW: Extracted helpers (145 lines)

spec/evals/
├── convention_recall_spec.rb          # REFACTORED: Uses helpers
├── architectural_decision_spec.rb     # REFACTORED: Uses helpers
└── tech_stack_recall_spec.rb          # REFACTORED: Uses helpers
```

## What We Learned

### Extraction Was Worth It

**Benefits**:
1. ✅ Less duplication (DRY)
2. ✅ Clearer intent (declarative)
3. ✅ Easier to add new evals (reuse helpers)
4. ✅ Single place to fix bugs (MemoryFixtureBuilder)

**Trade-offs**:
1. ⚠️ More indirection (need to understand helpers)
2. ⚠️ Slightly more complex (4 modules vs inline code)

**Verdict**: Worth it. Adding a 4th eval will be much easier now.

### When to Extract

**Right time to extract**:
- After 2-3 similar implementations
- When duplication causes pain
- When pattern is clear and stable

**Wrong time to extract**:
- Before any implementation (speculation)
- After only 1 implementation (too early)
- When pattern is still evolving

### What NOT to Extract Yet

We deliberately **did not** extract:
1. ❌ Base `EvalCase` class - Not enough common interface yet
2. ❌ `ClaudeRunner` - Not using real Claude execution
3. ❌ `MetricsCollector` - Not tracking results over time
4. ❌ `ResultStore` - Not needed yet

**Reason**: No pain yet. Extract when needed.

## Next Steps (Week 3+)

### Option A: Add More Scenarios (Recommended)

Now that helpers exist, adding new evals is easy:

```ruby
require_relative "support/eval_helpers"

RSpec.describe "New Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)
    builder.add_fact(...)
    builder.close
  end

  # ... rest of eval
end
```

**Potential scenarios**:
- Implementation Consistency (follows existing patterns)
- Code Style Adherence (respects conventions)
- Framework Usage (uses correct APIs)

### Option B: Add Real Claude Execution

Implement `ClaudeRunner` for integration tests:

```ruby
module EvalHelpers
  class ClaudeRunner
    def run(prompt, working_dir)
      # Shell out to claude -p --output-format json
      # Parse response
      # Extract tool calls from transcript
    end
  end
end
```

**When**: If stubbed responses miss real issues

### Option C: Tool Call Tracking

Add ability to verify memory tools were invoked:

```ruby
it "invokes memory.conventions tool" do
  result = run_claude(prompt, tmpdir)
  tool_calls = result[:tool_calls]

  expect(tool_calls).to include(tool: "memory.conventions")
end
```

**When**: If we need to test tool selection (like Vercel's 56% skip rate)

## Summary

**Week 2 achieved**:
- ✅ Extracted 4 helper modules from repeated patterns
- ✅ Refactored all 3 evals to use helpers
- ✅ Maintained 100% test pass rate (15/15)
- ✅ Improved code clarity and maintainability
- ✅ Made adding new evals easier

**Lines of code**:
- Added: 145 lines (helpers)
- Removed: ~21 lines (duplication)
- Net: +124 lines, but much clearer intent

**Velocity impact**:
- Adding 4th eval: ~30 minutes (vs 1 hour in Week 1)
- Changing fixture setup: 1 place (vs 3 places)

**Quality improvement**:
- Declarative > Imperative
- DRY > Repetitive
- Clear > Verbose

**Ready for**: Week 3 (add more scenarios or advanced features)
