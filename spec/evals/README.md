# ClaudeMemory Eval Framework

## Overview

Automated evaluation framework for testing ClaudeMemory's effectiveness, inspired by Vercel's blog post on agent evals. This framework tests:

1. **Tool Selection**: Whether memory tools are invoked when needed
2. **Behavioral Outcomes**: Whether memory improves response quality and accuracy

## Current Status: Week 2 Complete ✅

**Week 1** (Spike):
- Core eval infrastructure (fixture setup, memory population, scoring logic)
- 3 eval scenarios with 15 passing tests
- Stubbed Claude responses to test evaluation logic without API calls
- Comparison between baseline (no memory) vs memory-enabled scenarios

**Week 2** (Extract Patterns):
- Extracted common helpers after seeing clear repetition
- 4 reusable modules: SharedSetup, MemoryFixtureBuilder, ResponseStubs, ScoringHelpers
- Refactored all 3 evals to use helpers (clearer, more maintainable)
- Still 15/15 tests passing, faster to add new scenarios

**Scenarios implemented:**
1. **Convention Recall** - Tests memory of coding conventions (indentation, testing style) ✅ CLI tests
2. **Architectural Decision** - Tests memory of architectural choices (Sequel vs ActiveRecord) ✅ CLI tests
3. **Tech Stack Recall** - Tests memory of frameworks and databases (RSpec, SQLite) ✅ CLI tests
4. **Code Style Adherence** - Tests memory of style choices (Rubocop rules, spacing)
5. **Error Handling Patterns** - Tests memory of error handling approaches (Result pattern)
6. **Framework API Usage** - Tests memory of specific API patterns (Sequel datasets)
7. **Implementation Consistency** - Tests memory of implementation patterns (frozen strings)

## Running Evals

### Stub Mode (Default - Fast, Free)

```bash
# Run all evals
bundle exec rspec spec/evals/ --format documentation

# Run specific eval
bundle exec rspec spec/evals/convention_recall_spec.rb

# Run only eval tests (skip other tests)
bundle exec rspec --tag eval
```

### Real Mode (Slow, Costs Money)

Run evals with actual Claude CLI calls for validation:

```bash
# Run real mode tests (requires claude CLI and API key)
EVAL_MODE=real bundle exec rspec spec/evals/ --tag eval_real

# Run specific scenario
EVAL_MODE=real bundle exec rspec spec/evals/convention_recall_spec.rb --tag eval_real
```

**See [REAL_MODE.md](REAL_MODE.md) for details on:**
- Setup and prerequisites
- Cost estimates (~$0.04 per test)
- How it works (directory isolation, CLI execution)
- Adding new real eval tests
- CI integration

## Adding New Scenarios (Easy with Week 2 Helpers!)

```ruby
# frozen_string_literal: true

require_relative "support/eval_helpers"

RSpec.describe "Your New Eval", :eval do
  include EvalHelpers::SharedSetup          # Setup tmpdir, db_path, cleanup
  include EvalHelpers::ResponseStubs        # stub_success_response helper
  include EvalHelpers::ScoringHelpers       # includes_any?, score_from_checks

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_fact(
      predicate: "your_predicate",
      object: "Your value",
      text: "Full text for context",
      fts_keywords: "keywords for search"
    )

    builder.close
  end

  def stub_claude_response_with_memory
    stub_success_response("Response with memory...")
  end

  def stub_claude_response_without_memory
    stub_success_response("Generic baseline response...")
  end

  describe "with memory populated" do
    before { populate_fixture_memory }

    it "produces correct behavior" do
      result = stub_claude_response_with_memory
      # Your assertions here
    end
  end

  context "baseline (no memory)" do
    it "shows difference without memory" do
      result = stub_claude_response_without_memory
      # Your assertions here
    end
  end
end
```

**Time to create**: ~30 minutes (vs 1 hour before helpers)

## Learnings

### Week 1: Prove the Concept
- ✅ Fixture setup with `Dir.mktmpdir` for isolated test environments
- ✅ Memory population using existing `ClaudeMemory::Store::SQLiteStore` patterns
- ✅ Behavioral scoring logic (quantifies response quality)
- ✅ Baseline comparison (memory vs no memory)
- ✅ Fast tests (<1s total) by stubbing Claude responses

**Design approach** (Kent Beck):
- Started with ONE eval end-to-end (no abstractions)
- Added 2 more evals to feel pain points
- No premature extraction

### Week 2: Extract Patterns
- ✅ Extracted helpers after clear repetition emerged
- ✅ 4 modules: SharedSetup, MemoryFixtureBuilder, ResponseStubs, ScoringHelpers
- ✅ Refactored all 3 evals to use helpers
- ✅ Made adding new evals much easier

**Design approach** (Sandi Metz):
- Only extracted when we felt pain (after 3 evals)
- Each helper has single responsibility
- Declarative over imperative

## Helper Modules (Week 2)

### EvalHelpers::SharedSetup
Provides common RSpec setup for all evals:
```ruby
include EvalHelpers::SharedSetup

# Provides:
# - let(:tmpdir) - Isolated temporary directory
# - let(:db_path) - Path to .claude/memory.sqlite3
# - before/after hooks for cleanup
```

### EvalHelpers::MemoryFixtureBuilder
Simplifies memory population:
```ruby
builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

# Add single fact
builder.add_fact(
  predicate: "convention",
  object: "Use 2-space indentation",
  text: "Use 2-space indentation for Ruby files",
  fts_keywords: "coding convention style"
)

# Or add multiple facts
builder.add_facts([
  {predicate: "uses_framework", object: "RSpec", text: "..."},
  {predicate: "uses_database", object: "SQLite", text: "..."}
])

builder.close
```

### EvalHelpers::ResponseStubs
Standardizes stubbed responses:
```ruby
include EvalHelpers::ResponseStubs

stub_success_response("Response text", session_id: "stub-123")
stub_failure_response("Error message")
```

### EvalHelpers::ScoringHelpers
Common scoring utilities:
```ruby
include EvalHelpers::ScoringHelpers

includes_all?(response, "term1", "term2")   # All terms present?
includes_any?(response, "term1", "term2")   # Any term present?
score_from_checks(check1, check2, check3)   # Auto-weight boolean checks
```

## Test Structure

Each eval follows this pattern:

```ruby
describe "with memory populated" do
  before { populate_fixture_memory }

  it "produces correct behavior" do
    result = stub_claude_response_with_memory
    # Assertions about response quality
  end

  it "calculates behavioral score" do
    # Quantify how well response aligns with stored facts
  end
end

context "baseline (no memory)" do
  it "shows lower quality without memory" do
    result = stub_claude_response_without_memory
    # Compare to memory-enabled scenario
  end
end
```

## Metrics

Each eval calculates a **behavioral score** (0.0 - 1.0):

- **Convention Recall**: 1.0 with memory, 0.0 baseline
- **Architectural Decision**: 1.0 with memory, 0.0 baseline
- **Tech Stack Recall**: 1.0 with memory, 0.0 baseline

**Current pass rate:** 100% (15/15 tests passing)

## Next Steps (Week 3+)

### Option A: Add More Scenarios ⭐ Recommended
With helpers in place, adding new evals is fast (~30 min each):

**Potential scenarios**:
- **Implementation Consistency**: Does Claude follow existing code patterns?
- **Code Style Adherence**: Does Claude respect coding conventions in generated code?
- **Framework Usage**: Does Claude use correct framework APIs?
- **Error Handling**: Does Claude apply project error handling patterns?

**Why recommended**: Helpers make this easy, more scenarios = more confidence

### Option B: Add Real Claude Execution
Implement `ClaudeRunner` for integration tests (tag as `:slow`, skip by default)

**When**: If stubbed responses miss real issues
**Trade-offs**: Slow (30s+ per test), costs money, non-deterministic

### Option C: Tool Call Tracking
Verify memory tools are invoked (like Vercel's 56% skip rate)

**When**: If we need to test tool selection, not just outcomes

### Option D: Mode Comparison
Test 4 configurations: baseline, MCP only, context only, both

**When**: If we want to validate dual-mode approach

## Files

```
spec/evals/
├── README.md                          # This file
├── QUICKSTART.md                      # Quick start guide
├── support/
│   └── eval_helpers.rb                # Shared helpers (Week 2)
├── convention_recall_spec.rb          # Eval 1: Coding conventions
├── architectural_decision_spec.rb     # Eval 2: Architectural decisions
└── tech_stack_recall_spec.rb          # Eval 3: Tech stack identification

bin/
└── run-evals                          # Summary report runner

docs/
├── evals.md                           # Comprehensive documentation
├── eval_week1_summary.md              # Week 1 summary
└── eval_week2_summary.md              # Week 2 summary
```

## References

- **Plan Document**: Original implementation plan with expert reviews
- **Vercel Blog**: "Building reliable agents: What we learned from evals"
- **Testing Patterns**: `spec/claude_memory/mcp/tools_spec.rb`, `spec/claude_memory/recall_spec.rb`
