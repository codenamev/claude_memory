# CI Integration for Real Evals

This document explains how real eval validation is integrated into the CI/CD pipeline.

## Overview

Real evals run automatically on GitHub releases to validate that ClaudeMemory is working correctly before distribution. This provides confidence that the gem works as expected with actual Claude API calls.

## Workflow: `.github/workflows/real-evals.yml`

### Triggers

1. **Release Events** (automatic)
   - Runs when a new release is published on GitHub
   - Validates the release before users download it

2. **Manual Dispatch** (on-demand)
   - Can be triggered manually from GitHub Actions UI
   - Supports running specific scenarios via input parameter

### Workflow Steps

```yaml
1. Checkout code
2. Set up Ruby 4.0.1
3. Install Claude CLI (npm install -g @anthropic-ai/claude-code)
4. Run real eval tests (EVAL_MODE=real)
5. Parse results and estimate costs
6. Upload results as artifacts
7. Comment on release with summary
```

### Environment Variables

- `ANTHROPIC_API_KEY` - Required secret (set in GitHub repo settings)
- `EVAL_MODE=real` - Enables real Claude execution
- `GITHUB_TOKEN` - Automatically provided for API access

## Setting Up

### 1. Add API Key Secret

Navigate to your GitHub repository:
```
Settings → Secrets and variables → Actions → New repository secret
```

**Secret name:** `ANTHROPIC_API_KEY`
**Secret value:** Your Anthropic API key

### 2. Enable Workflow

The workflow is automatically enabled when the file exists. No additional configuration needed.

### 3. Test Manually (Optional)

Go to Actions → Real Eval Validation → Run workflow

Select:
- Branch: `main`
- Scenarios: `all` (or specific ones like `convention_recall,tech_stack_recall`)

## Usage

### Automatic Validation on Release

When you create a release:
```bash
# Create and push a tag
git tag v0.4.0
git push origin v0.4.0

# Create release on GitHub (or use gh CLI)
gh release create v0.4.0 --title "v0.4.0" --notes "Release notes..."
```

The workflow will:
1. Run automatically within 1-2 minutes
2. Execute all 6 real eval tests
3. Post results as a comment on the release
4. Upload detailed results as artifacts

### Manual Validation

Run specific scenarios before a release:
```bash
# Local validation
./bin/run-real-evals convention_recall,tech_stack_recall

# Or all scenarios
./bin/run-real-evals all
```

On GitHub Actions:
1. Go to Actions → Real Eval Validation
2. Click "Run workflow"
3. Enter scenarios (e.g., `convention_recall` or `all`)
4. Click "Run workflow"

### Viewing Results

**In Workflow Logs:**
- Click on the workflow run
- Expand "Run real eval tests" to see detailed output
- Check "Parse and report costs" for summary

**As Artifacts:**
- Scroll to bottom of workflow run
- Download `real-eval-results` artifact
- Contains `real-eval-results.json` with full details

**On Release Page:**
- Workflow posts a comment with summary
- Shows pass/fail status and estimated cost

## Cost Management

### Per-Run Costs

- **3 scenarios** × 2 tests (baseline + memory) = 6 tests
- ~$0.02 per test
- **Total: ~$0.12 per validation**

### Monthly Estimates

- 1 release/month: ~$0.12
- 2 releases/month: ~$0.24
- 4 releases/month: ~$0.48

### Cost Monitoring

The workflow tracks costs in two places:

1. **Workflow logs** (Parse and report costs step)
2. **Release comment** (visible to all users)

Example output:
```
Estimated Cost: $0.12
```

This is based on:
- 100 input tokens × $0.003/1K = ~$0.0003
- 50 output tokens × $0.015/1K = ~$0.00075
- Rounded to $0.02 per test for simplicity

### Budget Alerts

If costs exceed expectations:

1. Check `--max-budget-usd` in `ClaudeCliRunner` (currently $0.10 per test)
2. Review which tests are using more tokens
3. Consider reducing scenarios or running only on major releases

## Troubleshooting

### "ANTHROPIC_API_KEY not set"

**Problem:** Secret not configured or misspelled

**Solution:**
1. Go to Settings → Secrets → Actions
2. Verify secret name is exactly `ANTHROPIC_API_KEY`
3. Re-add secret if needed

### "claude: command not found"

**Problem:** Claude CLI installation failed

**Solution:**
Check the "Install Claude CLI" step in workflow logs. May need to:
1. Update npm version in workflow
2. Check @anthropic-ai/claude-code package availability
3. Use alternative installation method

### Tests Timing Out

**Problem:** Tests run longer than 10 minutes (GitHub default)

**Solution:**
Add timeout to workflow:
```yaml
jobs:
  real-evals:
    timeout-minutes: 20  # Increase if needed
```

### High Costs

**Problem:** Tests using more than expected budget

**Solution:**
1. Review test prompts (shorter = cheaper)
2. Reduce context in `memory_runner.run(context: ...)`
3. Lower `--max-budget-usd` to fail fast on expensive tests
4. Run fewer scenarios per release

## Release Process

Recommended workflow:

```bash
# 1. Run tests locally
bundle exec rspec

# 2. Run real evals locally (optional, costs ~$0.12)
./bin/run-real-evals all

# 3. Create release
git tag v0.4.0
git push origin v0.4.0
gh release create v0.4.0

# 4. Wait for CI validation (~2-3 minutes)
# 5. Check release page for results comment
# 6. If passed, release is validated ✅
# 7. If failed, investigate and create a patch release
```

## Workflow Customization

### Run Only on Major Releases

Edit `.github/workflows/real-evals.yml`:
```yaml
on:
  release:
    types: [published]
    # Only run on tags matching v*.0.0 (major versions)
    tags:
      - 'v[0-9]+.0.0'
```

### Run on Schedule (Weekly)

Add to workflow triggers:
```yaml
on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 9 AM UTC
```

### Send Slack Notifications

Add step after results parsing:
```yaml
- name: Notify Slack
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "Real eval validation failed for ${{ github.event.release.tag_name }}"
      }
```

## Metrics and Reporting

### Available Metrics

The workflow provides:
- **Pass rate**: Passed / Total tests
- **Duration**: Time to run all tests
- **Cost estimate**: Based on test count
- **Failure details**: Which scenarios failed

### Viewing Historical Data

GitHub Actions provides:
- Workflow run history (up to 90 days)
- Artifacts (configurable retention, default 30 days)
- Release comments (permanent)

### Exporting Data

Download artifacts and parse JSON:
```bash
# Download real-eval-results.json
unzip real-eval-results.zip

# Parse with jq
jq '.summary' real-eval-results.json
```

## Security Considerations

### API Key Security

- ✅ Stored as GitHub secret (encrypted)
- ✅ Not visible in logs
- ✅ Only accessible to workflow runs
- ⚠️ Rotated if leaked

### Rate Limiting

Claude API has rate limits. If hitting limits:
1. Space out releases
2. Use smaller batches of scenarios
3. Contact Anthropic for increased limits

### Cost Controls

Built-in safety measures:
- `--max-budget-usd 0.10` per test
- Opt-in only (EVAL_MODE=real required)
- Runs on releases only (not every push)
- Manual approval for workflow dispatch

## Future Enhancements

Potential improvements for Phase 4:

- [ ] Compare results across releases (regression detection)
- [ ] Track cost trends over time
- [ ] Add semantic similarity scoring
- [ ] Parallel test execution for speed
- [ ] Custom reporting dashboard
- [ ] Integration with external monitoring (DataDog, etc.)

## Support

For issues with CI integration:

1. Check workflow logs for detailed error messages
2. Review this documentation
3. See `spec/evals/REAL_MODE.md` for test details
4. Open GitHub issue with workflow run link
