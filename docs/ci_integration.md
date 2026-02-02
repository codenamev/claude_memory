# CI Integration for Eval Framework

## Current Status: ✅ Already Working

The eval framework **requires no special CI setup** and already runs in GitHub Actions.

### What's Already Running

`.github/workflows/main.yml` runs on:
- Every push to `main`
- Every pull request

It executes: `bundle exec rake` which runs:
1. `rake spec` - All 1003 tests (including 15 eval tests)
2. `rake standard` - Ruby linter

**Evals are automatically included** because they're part of the RSpec suite (`spec/evals/*.rb`).

### Why Evals Work in CI

✅ **No API calls** - Use stubbed responses (no Claude API key needed)
✅ **No external services** - Self-contained in-memory fixtures
✅ **Fast** - <1s for all 15 eval tests, 40s for full suite
✅ **Standard dependencies** - Just RSpec + ClaudeMemory gems
✅ **Temporary directories** - Use `Dir.mktmpdir` (standard in CI)
✅ **No environment variables** - No configuration needed

### Current CI Output

```
...
1003 examples, 0 failures
Took 40 seconds
```

The 15 eval tests are included in the 1003 total. They run silently unless they fail.

## Optional Enhancements

If you want to make evals more visible in CI, consider these options:

### Option 1: Separate Eval Report Step ⭐ Recommended

Add a dedicated step to show eval summary:

```yaml
# .github/workflows/main.yml
steps:
  - uses: actions/checkout@v4
  - name: Set up Ruby
    uses: ruby/setup-ruby@v1
    with:
      ruby-version: ${{ matrix.ruby }}
      bundler-cache: true

  # NEW: Run evals with summary report
  - name: Run evals with summary
    run: ./bin/run-evals

  # Existing: Run full test suite
  - name: Run tests and linter
    run: bundle exec rake
```

**Benefits:**
- Clear "EVAL SUMMARY" section in CI logs
- Shows behavioral scores prominently
- Makes eval failures obvious

**Example output in CI logs:**
```
============================================================
EVAL SUMMARY
============================================================

Total Examples: 15
Passed: 15 ✅
Failed: 0 ❌

============================================================
BEHAVIORAL SCORES
============================================================

Convention Recall:       +100% improvement
Architectural Decision:  +100% improvement
Tech Stack Recall:       +100% improvement

OVERALL: Memory improves responses by 100% on average
============================================================
```

**Trade-offs:**
- ✅ Better visibility
- ⚠️ Runs evals twice (once in summary, once in full suite)
- ⚠️ Adds ~1 second to CI time

### Option 2: Fail Fast on Eval Failures

Run evals first to catch memory issues early:

```yaml
- name: Run evals first (fail fast)
  run: bundle exec rspec spec/evals/ --fail-fast

- name: Run full test suite
  run: bundle exec rake
```

**Benefits:**
- Fails within ~1 second if evals break
- Saves CI time (skips 1003 tests if evals fail)
- Evals become "smoke tests" for memory system

**Trade-offs:**
- ⚠️ Runs evals twice (but stops fast if they fail)

### Option 3: Separate Workflow for Evals

Create `.github/workflows/evals.yml`:

```yaml
name: Evals

on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  evals:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '4.0.1'
          bundler-cache: true
      - name: Run evals
        run: ./bin/run-evals
```

**Benefits:**
- Evals have dedicated status badge
- Can schedule periodic eval runs (e.g., weekly)
- Clearer separation of concerns

**Trade-offs:**
- ⚠️ More complex (2 workflows)
- ⚠️ Runs evals 3 times (main workflow, eval workflow, scheduled)

### Option 4: Eval Results as PR Comment

Post eval summary as PR comment:

```yaml
- name: Run evals and capture results
  id: evals
  run: |
    echo "results<<EOF" >> $GITHUB_OUTPUT
    ./bin/run-evals >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT

- name: Comment eval results on PR
  if: github.event_name == 'pull_request'
  uses: actions/github-script@v7
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: '## Eval Results\n\n```\n${{ steps.evals.outputs.results }}\n```'
      })
```

**Benefits:**
- Eval results visible in PR without checking logs
- Reviewers see memory improvement metrics
- Historical record in PR comments

**Trade-offs:**
- ⚠️ More complex (requires github-script action)
- ⚠️ Creates comment on every push to PR
- ⚠️ Requires GITHUB_TOKEN (usually automatic)

## Recommendation

**Current setup is perfect for now.** Evals already run and will catch regressions.

When to add enhancements:
- **Option 1**: If you want eval results more visible in logs (simple, low cost)
- **Option 2**: If eval failures become frequent (fail fast saves time)
- **Option 3**: If you want dedicated eval status badge
- **Option 4**: If you want eval results visible to PR reviewers

Most projects should start with **Option 1** (separate step with summary) only if visibility becomes an issue.

## Testing CI Locally

Simulate CI behavior locally:

```bash
# What CI runs (default rake task)
bundle exec rake

# Just evals (what CI could run separately)
./bin/run-evals

# Just evals with RSpec (alternative)
bundle exec rspec spec/evals/ --format documentation
```

## CI Failure Scenarios

### Scenario 1: Eval Test Fails

```
Failures:

  1) Convention Recall Eval mentions stored conventions when asked
     Failure/Error: expect(mentions_indentation).to be(true)
       expected true
            got false
```

**What happened**: Memory system regressed, stored conventions not recalled

**Fix**: Investigate why memory population or recall failed

### Scenario 2: All Tests Pass But Behavioral Scores Drop

Current setup won't catch this (scores aren't checked automatically).

To catch this in future (Week 3+):
- Store expected scores in test
- Assert: `expect(score).to be >= 0.9` (allow small variance)

### Scenario 3: Fixture Setup Fails

```
Errno::EACCES: Permission denied @ dir_s_mkdir - /tmp
```

**What happened**: CI environment doesn't allow temp directory creation

**Fix**: Unlikely in GitHub Actions (has `/tmp` access), but could use `ENV['TMPDIR']` fallback

## Verification

To verify evals are running in CI:

1. **Check logs**: Look for "1003 examples, 0 failures" (includes evals)
2. **Break an eval**: Change assertion to fail, push, check CI fails
3. **Run locally**: `bundle exec rake` should match CI behavior

## Future: Real Claude Execution (Week 3+)

If you add real Claude execution (not stubbed):

**Will need:**
- `ANTHROPIC_API_KEY` in GitHub Secrets
- Tag tests as `:slow` and skip by default
- Optional: Run only on `main` branch (not PRs)
- Optional: Schedule runs (don't run on every commit)

**Example:**
```yaml
- name: Run slow evals (real Claude)
  if: github.ref == 'refs/heads/main'
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: bundle exec rspec spec/evals/ --tag slow
```

But for current stubbed evals: **no special setup needed!** ✅

## Summary

| Aspect | Status | Notes |
|--------|--------|-------|
| Already running in CI? | ✅ Yes | Part of `bundle exec rake` |
| Requires API keys? | ❌ No | Uses stubbed responses |
| Requires environment variables? | ❌ No | Self-contained |
| Requires special permissions? | ❌ No | Standard filesystem access |
| Fast enough for CI? | ✅ Yes | <1s for evals, 40s total |
| Catches regressions? | ✅ Yes | Will fail if memory system breaks |
| Visible in logs? | ⚠️ Partial | Included in total count, not highlighted |
| Recommended changes? | 🤷 Optional | Add separate summary step if desired |

**Bottom line**: Evals work in CI today. Optional enhancements can improve visibility, but aren't required.
