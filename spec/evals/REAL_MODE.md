# Real Claude Execution Mode

This document explains how to run evals with real Claude API calls using the Claude CLI.

## Overview

The eval framework supports two modes:

1. **Stub Mode (Default)**: Fast, free, uses pre-defined responses
2. **Real Mode**: Slow, costs money, uses actual Claude CLI

## Running Real Mode

### Prerequisites

- Claude CLI must be installed (`which claude` should succeed)
- ANTHROPIC_API_KEY environment variable must be set
- Budget for API calls (~$0.04 per test)

### Basic Usage

```bash
# Run all real eval tests
EVAL_MODE=real bundle exec rspec spec/evals/ --tag eval_real

# Run specific scenario
EVAL_MODE=real bundle exec rspec spec/evals/convention_recall_spec.rb --tag eval_real

# Run with custom budget limit (default: $0.10 per test)
# Edit spec/evals/support/claude_cli_runner.rb to change --max-budget-usd
```

### Expected Costs

- Per test: ~$0.02 (baseline) + ~$0.02 (memory) = **$0.04 total**
- 7 scenarios × 2 calls = 14 calls × $0.02 = **$0.28 per full run**

### Budget Safety

Each test call includes `--max-budget-usd 0.10` to prevent runaway costs. If a test hits this limit, it will fail with a budget error.

## How It Works

### Architecture

```
Test → ClaudeCliRunner → claude -p → Parse text → Evaluate keywords
```

### Directory Isolation

- **Baseline**: Runs in temporary directory (no `.claude/` config)
- **Memory-enabled**: Runs in project directory (with ClaudeMemory hooks)

### Output Parsing

The runner uses `--output-format text` and filters out:
- Shell reset messages (`Shell cwd was reset to...`)
- Hook errors (redirected to `/dev/null`)

### Acceptance Criteria

Tests use `SimpleAcceptanceCriteria` with keyword matching:

```ruby
criteria = SimpleAcceptanceCriteria.new(
  required_keywords: ["Sequel", "dataset", "transaction"],
  threshold: 0.75  # 75% of keywords must appear
)

evaluation = criteria.evaluate(response_text)
evaluation.passed? # => true/false
```

## Adding New Real Eval Tests

1. Create your stub test in the appropriate spec file
2. Add a CLI version with `:eval_real` and `:slow` tags
3. Define acceptance criteria with required keywords
4. Add skip conditions for stub mode and missing CLI

Example:

```ruby
def acceptance_criteria
  @criteria ||= EvalHelpers::SimpleAcceptanceCriteria.new(
    required_keywords: ["keyword1", "keyword2", "keyword3"],
    threshold: 0.75
  )
end

describe "with memory enabled (CLI)", :eval_real, :slow do
  it "uses memory context" do
    skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")
    skip "Skipped in stub mode" if eval_mode == "stub"

    result = memory_runner.run(prompt: "Your question?", context: "Context")

    expect(result[:success]).to be(true)

    evaluation = acceptance_criteria.evaluate(result[:result])

    expect(evaluation.passed?).to be(true),
      "Response should include keywords\nDetails: #{evaluation.details}"
  end
end
```

## CI Integration

### Current Setup

CI runs stub mode on every push:

```yaml
- name: Run stub evals
  run: bundle exec rspec spec/evals/
```

### Future: Real Mode on Release

```yaml
- name: Run real evals
  if: github.event_name == 'release'
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
    EVAL_MODE: real
  run: bundle exec rspec spec/evals/ --tag eval_real
```

## Troubleshooting

### "Real mode requires claude CLI"

Install Claude CLI:

```bash
npm install -g @anthropic-ai/claude-code
```

### "Skipped in stub mode"

Set EVAL_MODE:

```bash
EVAL_MODE=real bundle exec rspec ...
```

### Budget errors

The test hit the $0.10 limit. This could mean:
- The prompt is too complex
- Claude used expensive models
- Multiple tool calls were needed

Check the actual cost in the test output and adjust the limit if needed.

### Hook errors in output

Hook errors are redirected to `/dev/null` and filtered from output. If you see them, check that:
- `err: "/dev/null"` is passed to `Open3.capture2`
- `parse_output` filters `Shell cwd was reset` messages

## Design Decisions

### Why Text Format?

JSON format (`--output-format json`) is unreliable because:
- Hook errors on stderr corrupt the JSON
- No clear field for response text (varies between `content`, `text`, `result`)

Text format is simpler and more robust.

### Why Not Direct API?

Using `claude -p` instead of direct API calls:
- ✅ Tests real Claude Code behavior (not just API)
- ✅ Built-in budget control (`--max-budget-usd`)
- ✅ Easy to debug (run commands manually)
- ✅ No custom API client needed
- ❌ Slightly slower (shell overhead)

### Why Keyword Matching?

Simple keyword matching for Phase 1:
- Easy to understand and debug
- Flexible (case-insensitive, partial matches)
- Adjustable threshold
- No embedding models needed

Future phases can add semantic similarity scoring.

## Performance

### Stub Mode
- Runtime: ~0.5s for all 56 tests
- Cost: $0 (no API calls)
- Use: Development, CI on every push

### Real Mode
- Runtime: ~5-10s per test
- Cost: ~$0.04 per test
- Use: Pre-release validation, CI on releases

## Status

### Phase 1: One Scenario ✅

- [x] Implement ClaudeCliRunner
- [x] Implement SimpleAcceptanceCriteria
- [x] Add convention_recall tests
- [x] Unit tests for support classes
- [x] Verify stub mode still works
- [x] Document real mode usage

### Phase 2: Expand Coverage ✅

- [x] Add tech_stack_recall CLI tests
- [x] Add architectural_decision CLI tests
- [x] Add convention_recall CLI tests (Phase 1)
- [x] 3 scenarios with 6 CLI tests total
- [x] All tests pass in stub mode
- [x] Ready for real mode validation

**Current Coverage:**
- Convention Recall (2 CLI tests: baseline + memory)
- Tech Stack Recall (2 CLI tests: baseline + memory)
- Architectural Decision (2 CLI tests: baseline + memory)

### Phase 3: CI Integration ✅

- [x] Add GitHub Actions workflow (`.github/workflows/real-evals.yml`)
- [x] Set up API key secret (documented in CI_INTEGRATION.md)
- [x] Run on release events (automatic validation)
- [x] Add cost tracking/reporting (JSON results + release comments)
- [x] Manual trigger support (workflow_dispatch)
- [x] Helper script for local validation (`bin/run-real-evals`)

**See [CI_INTEGRATION.md](CI_INTEGRATION.md) for:**
- Setting up GitHub secrets
- Triggering workflows
- Viewing results and costs
- Troubleshooting CI issues
