# ClaudeMemory Evals - Quick Start

## TL;DR

```bash
# Run all evals with summary
./bin/run-evals
```

Expected output:
```
============================================================
OVERALL: Memory improves responses by 100% on average
============================================================
```

## What Are Evals?

Automated tests that measure ClaudeMemory's effectiveness by comparing:
- **With Memory**: Claude has access to stored facts
- **Baseline**: Claude has no memory (generic responses)

We quantify the difference with **behavioral scores** (0.0 - 1.0).

## Current Scenarios

### 1. Convention Recall
**Question**: "What are the coding conventions for this Ruby project?"

- **With Memory**: Mentions specific conventions (2-space indentation, expect syntax) → Score: 1.0
- **Baseline**: Gives generic advice → Score: 0.0

### 2. Architectural Decision
**Question**: "How should I query the database in this project?"

- **With Memory**: Recommends Sequel specifically → Score: 1.0
- **Baseline**: Lists multiple options without recommendation → Score: 0.0

### 3. Tech Stack Recall
**Question**: "What testing framework does this project use?"

- **With Memory**: Identifies RSpec confidently → Score: 1.0
- **Baseline**: Lists options but admits uncertainty → Score: 0.0

## Running Evals

### Quick Summary
```bash
./bin/run-evals
```

### Detailed Output
```bash
bundle exec rspec spec/evals/ --format documentation
```

### Specific Scenario
```bash
bundle exec rspec spec/evals/convention_recall_spec.rb
```

### Run Only Evals (skip other tests)
```bash
bundle exec rspec --tag eval
```

## Understanding Results

### Pass/Fail
Each eval has assertions like:
```ruby
expect(response).to include("2-space")  # Must mention stored convention
```

### Behavioral Scores
Quantify response quality:
```ruby
score = 0.0
score += 0.5 if mentions_indentation
score += 0.5 if mentions_rspec
# Perfect response = 1.0, baseline = 0.0
```

### Improvement Percentage
```
With Memory:    1.0 (100%)
Baseline:       0.0 (0%)
Improvement:    +100%
```

Shows how much better responses are with memory.

## Why Stub Claude Responses?

Current evals use **stubbed responses** (not real Claude API calls) because:

✅ **Fast**: Tests run in <1s (suitable for TDD)
✅ **Free**: No API costs
✅ **Deterministic**: Same results every time
✅ **Tests eval logic**: Proves scoring system works

**Future work** could add real Claude execution for integration testing (tagged `:slow`, CI only).

## Adding New Scenarios

1. Copy existing eval (e.g., `convention_recall_spec.rb`)
2. Change fixture setup (different facts)
3. Update stub responses
4. Adjust scoring logic
5. Run: `bundle exec rspec spec/evals/your_new_eval_spec.rb`

Example:
```ruby
def populate_fixture_memory
  store = ClaudeMemory::Store::SQLiteStore.new(db_path)
  entity_id = store.find_or_create_entity(type: "repo", name: "test")

  store.insert_fact(
    subject_entity_id: entity_id,
    predicate: "your_predicate",
    object_literal: "your value",
    scope: "project"
  )

  # Index for FTS...
  # Provenance...
end
```

## CI Integration (Future)

Add to `.github/workflows/test.yml`:
```yaml
- name: Run Evals
  run: ./bin/run-evals

- name: Fail if Evals Fail
  if: failure()
  run: exit 1
```

This blocks releases if evals regress.

## Learn More

- **Full docs**: `docs/evals.md`
- **Week 1 summary**: `docs/eval_week1_summary.md`
- **Implementation details**: `spec/evals/README.md`
- **Original plan**: Ask about the eval framework plan document

## Questions?

**Q: Why not test real Claude responses?**
A: Stubbed responses test evaluation logic quickly. Real execution can be added later if needed (as `:slow` tests).

**Q: How do I see what memory tools were called?**
A: Tool call tracking not yet implemented. Future work (Week 2+).

**Q: Can I test MCP-only vs context-only?**
A: Mode comparison not yet implemented. Future work (Week 2+).

**Q: What if evals start failing?**
A: Either:
1. Memory system regressed (fix it)
2. Eval expectations wrong (update eval)
3. Stub responses outdated (update stubs)

**Q: How often should I run evals?**
A:
- During development: As needed (fast tests)
- Before commits: Optional (validate changes)
- In CI: Always (prevent regressions)
