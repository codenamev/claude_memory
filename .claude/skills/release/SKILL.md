---
name: release
description: Prepare and publish a new gem release — bumps version across all required files, validates tests/linting/MCP server, commits, and creates the GitHub release. Use this skill when the user says "release", "publish a new version", "bump the version", "cut a release", "prepare for release", "ship it", or any variation of wanting to publish a new gem version. Also use when the user asks about the release process or what steps are needed to release.
agent: general-purpose
allowed-tools: Read, Grep, Edit, Write, Bash
arguments:
  - name: version
    description: "The new version number (e.g., '0.10.0'). If omitted, you'll be asked."
    required: false
---

# Release Workflow

Automate the full release lifecycle for the ClaudeMemory gem. This workflow was codified from the actual 0.9.0 release process.

The release has three phases: **prepare** (automated), **publish** (user-driven), and **announce** (automated). The middle phase requires user action because it pushes to a shared remote and publishes to RubyGems — destructive operations that must never happen without explicit confirmation.

## Phase 1: Prepare

### Step 1: Determine the new version

If a version was passed as an argument, use it. Otherwise, read the current version from `lib/claude_memory/version.rb` and ask the user what the new version should be.

### Step 2: Find and update all version references

The version lives in exactly three files. Grep to confirm there are no others:

```bash
grep -rn "CURRENT_VERSION" --include="*.rb" --include="*.json" --include="*.gemspec" . | grep -v "CHANGELOG\|node_modules\|vendor\|\.git/"
```

Update all three:

1. **`lib/claude_memory/version.rb`** — the `VERSION` constant (canonical source)
2. **`.claude-plugin/plugin.json`** — the `"version"` field
3. **`.claude-plugin/marketplace.json`** — the `"version"` field inside the plugins array

If grep reveals any additional hardcoded references, update those too and flag them to the user as something that should be DRYed up.

### Step 3: Update Gemfile.lock

```bash
bundle install
```

Verify both `claude_memory (X.Y.Z)` entries in Gemfile.lock match the new version.

### Step 4: Verify MCP server reports the new version

The MCP server reads `ClaudeMemory::VERSION` dynamically. Confirm it picks up the change:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | bundle exec claude-memory serve-mcp 2>/dev/null | grep -o '"version":"[^"]*"'
```

Expected output: `"version":"X.Y.Z"` matching the new version. If it doesn't match, something is wrong with the require chain — investigate before proceeding.

### Step 5: Run the full test suite

```bash
bundle exec rspec
```

All tests must pass. Do not proceed with any failures. Fix them first.

### Step 6: Run the pre-release hook smoke gate

```bash
bin/pre-release-smoke
```

This script:

1. Re-runs `bundle exec rake install` so the PATH-resolved `claude-memory` binary matches the working tree.
2. Triggers each gem-managed hook against a temp DB.
3. Verifies every field listed in `spec/smoke/expected_fields.yml` is populated on the resulting `activity_events.detail_json`.
4. Exits non-zero with the missing field name(s) and `since_version` if any expected field is null/absent.

**This catches the class of bug specs cannot:** a code change that adds a new `detail_json` field but forgets `rake install`, leaving the installed gem stale and production hooks silently missing the field. Sprung that trap on 2026-04-16 (ActivityLog) and again on 2026-04-30 (#47 token-budget) — the gate is here so it can't happen a third time.

If the gate fails, **stop the release**, address the missing field (usually `bundle exec rake install` followed by re-running the gate), and only proceed when it exits 0.

### Step 7: Run the benchmark scoreboard diff

```bash
bin/run-evals --benchmarks
bin/bench-diff
```

`bin/run-evals --benchmarks` writes `spec/benchmarks/results/<version>.json` — the diff-friendly snapshot of the current release's pass rates by category and per-scenario. `bin/bench-diff` then compares that snapshot against the most recent prior tagged version's scoreboard and exits non-zero if any tracked pass-rate dropped beyond the threshold (default -5%; configurable via `--threshold`).

The first release with this gate (0.12.0) has no prior scoreboard to compare against — `bench-diff` exits 0 with a "No baseline scoreboard available" note. From 0.13.0 onward it actively gates.

If the diff reports a regression, **stop the release**, investigate (the regressed metric path is named in stderr — e.g. `metrics.evals.by_scenario.tech_stack_recall.pass_rate`), and only proceed once you've either (a) fixed the regression or (b) made a deliberate decision that the lower pass rate is acceptable. If (b), document the new baseline in CHANGELOG so future-you isn't surprised.

For real-mode E2E coverage (~$2-8 per run), pass `EVAL_MODE=real`:

```bash
EVAL_MODE=real bin/run-evals --all && bin/bench-diff
```

### Step 8: Run the linter

```bash
bundle exec rake standard:fix
```

Ensure no remaining violations.

### Step 9: Verify CHANGELOG.md

The CHANGELOG should already have a release section written during development (via `/improve`, manual commits, or other workflow). **Do not auto-generate release notes** — they should reflect the actual development narrative.

Check that:
- The `## [X.Y.Z] - YYYY-MM-DD` section exists with today's date
- It has Added, Changed, Fixed subsections as appropriate
- Upgrade Notes are included if there are breaking changes or manual migration steps
- The `## [Unreleased]` section above it is empty or ready for the next cycle

If the CHANGELOG section is missing or incomplete, **stop and ask the user**. Do not fabricate release notes.

### Step 10: Commit the version bump

```bash
git add lib/claude_memory/version.rb .claude-plugin/plugin.json .claude-plugin/marketplace.json Gemfile.lock
git commit -m "[Release] Bump version to X.Y.Z"
```

Do NOT push yet. Report what was committed and proceed to Phase 2.

## Phase 2: Publish (User-Driven)

This phase involves pushing to a shared remote and publishing to RubyGems. These are **irreversible shared-state operations** — never execute them automatically.

Tell the user:

> Version X.Y.Z is prepared and committed locally. To publish:
>
> ```bash
> git push origin main
> rake release
> ```
>
> `rake release` will create the git tag, build the gem, and push to RubyGems. Let me know when that's done and I'll create the GitHub release.

Wait for the user to confirm before proceeding to Phase 3.

## Phase 3: Announce

### Step 11: Fix any stale "Latest" flags on GitHub releases

Check current release state:

```bash
gh release list --limit 5
```

If an older release is incorrectly marked "Latest" (this happens when releases are created out of order or with `--latest` set manually):

```bash
gh release edit v<old-version> --latest=false
```

### Step 12: Create the GitHub release

Extract the release notes from CHANGELOG.md — everything between `## [X.Y.Z]` and the next `## [` heading. Write to a temp file:

```bash
# Extract the section between the new version header and the next version header
sed -n '/^## \[X\.Y\.Z\]/,/^## \[/{ /^## \[X\.Y\.Z\]/d; /^## \[/d; p; }' CHANGELOG.md > /tmp/release-notes.md
```

Create the release:

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z — Short descriptive title" \
  --latest \
  --verify-tag \
  --notes-file /tmp/release-notes.md
```

The title should capture the theme of the release in a few words (e.g., "Predicate Design Overhaul, Reject/Restore, Telemetry"). Read the CHANGELOG to derive this — don't ask the user unless the theme isn't obvious.

### Step 13: Verify the release

```bash
gh release list --limit 5
```

Confirm:
- The new release appears at the top
- It's marked "Latest"
- No older release is incorrectly marked "Latest"

Report the release URL to the user.

## Error Handling

- **Smoke gate fails (`bin/pre-release-smoke` exits non-zero)**: The script names the missing `detail_json` field and `since_version` in stderr. Most common cause: code that adds a new field landed without a follow-up `bundle exec rake install`, so the installed gem is stale. Re-run `rake install`, then re-run the gate. If the field was newly added but no `rake install` was run, that's the bug the gate is designed to catch — don't bypass it. If the manifest needs updating because a field was intentionally removed, edit `spec/smoke/expected_fields.yml` AND add a CHANGELOG breaking-change note (removing a `detail_json` field is a public API change per `docs/api_stability.md` §4).
- **Bench-diff fails (`bin/bench-diff` exits 1)**: Stderr names the metric path that regressed (e.g. `metrics.evals.by_scenario.tech_stack_recall.pass_rate`). Investigate the regression — is it a real correctness issue, or a measurement-noise issue (e.g. real-mode flake)? If real, fix before releasing. If a deliberate baseline change (we knowingly traded N% in metric X for some other gain), update CHANGELOG with the new baseline and re-run with a temporarily looser `--threshold` to ship; the next release picks up the new floor automatically. **Don't bypass the gate without an explicit baseline-change note** — that defeats the entire scoreboard.
- **Tests fail**: Fix first. Never release with failing tests.
- **CHANGELOG missing**: Ask the user. Never fabricate release notes.
- **Version already tagged**: The tag may exist from a prior attempt. Ask the user whether to delete and recreate, or use a different version.
- **`gh` not available**: Tell the user to create the GitHub release manually, providing the release notes content.
- **`rake release` fails**: Common causes: not logged into RubyGems, tag already exists, uncommitted changes. Help the user diagnose but don't retry automatically.
