---
name: upgrade-dependencies
description: "Upgrade all Ruby gem dependencies to their latest versions with release note review and codebase alignment checks. Use this skill whenever the user asks to update, upgrade, or bump dependencies, gems, or packages — even casually like 'update my gems' or 'are my deps up to date?'"
agent: general-purpose
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent, WebFetch
---

# Dependency Upgrade Skill

Systematically upgrade Ruby gem dependencies by researching latest versions, reviewing release notes for breaking changes, updating version constraints, verifying with tests, and confirming codebase alignment.

The goal is a *thoughtful* upgrade — not blindly bumping versions, but understanding what changed and ensuring the codebase is compatible. This matters because a silent API change can introduce bugs that tests don't catch if the tests don't exercise the affected code path.

## Process Overview

1. **Discover** current dependencies and their constraints
2. **Research** latest versions and release notes (in parallel)
3. **Analyze** breaking changes and codebase impact
4. **Upgrade** version constraints and install
5. **Verify** with the full test suite
6. **Report** a summary table with upgrade details

## Step 1: Discover Current Dependencies

Read the gemspec and Gemfile to build a complete dependency inventory.

```
Read *.gemspec        → runtime dependencies (add_dependency)
Read Gemfile          → development dependencies (gem declarations)
Run: bundle outdated  → current vs latest versions, which are constrained
```

Build a working list with these columns:
- **Gem name**
- **Source** (gemspec or Gemfile)
- **Current constraint** (e.g., `~> 5.0`)
- **Installed version** (from `bundle outdated` or `Gemfile.lock`)
- **Latest version** (from `bundle outdated`)
- **Constrained?** (is the version constraint preventing upgrade?)

## Step 2: Research Release Notes

For each gem that has a newer version available, research what changed. Launch these as parallel Agent subagents — one per gem — to avoid sequential delays.

Each research agent should:

1. Run `gem search <name> --exact --versions` to confirm the latest version
2. Fetch the changelog or release notes from GitHub (check CHANGELOG.md, CHANGES, HISTORY.md, or GitHub Releases)
3. Summarize changes between the installed version and latest version
4. Flag any **breaking changes**, **deprecations**, or **API changes**
5. Note if it's a **major version bump** (higher risk)

For transitive dependencies (not directly declared but showing in `bundle outdated`), research is optional — focus on direct dependencies. Transitive deps are upgraded automatically when their parent gem allows it.

### What to look for in release notes

- **Removed methods or classes** the codebase might use
- **Renamed options or changed defaults** that could silently alter behavior
- **New required arguments** to methods we call
- **Deprecated features** we rely on (working now, but will break later)
- **Changed return types** or data structures
- **Minimum Ruby version bumps** that could affect CI or deployment

## Step 3: Analyze Codebase Impact

For each gem with breaking changes or API modifications:

1. **Grep the codebase** for usage of affected APIs
2. **Check test coverage** — are the affected code paths tested?
3. **Determine if changes are needed** before or after the upgrade

Classify each upgrade:

- **Safe** — no breaking changes, or breaking changes don't affect our usage
- **Needs code changes** — our code uses a deprecated or removed API
- **Held back** — a transitive dependency constraint prevents the upgrade (explain which parent gem and why)

If code changes are needed, make them *before* bumping the version constraint so the upgrade commit is clean.

## Step 4: Upgrade Dependencies

### Gemspec dependencies (runtime)

Update version constraints to target the latest version. Use `~>` with the appropriate precision:

- For stable gems (1.0+): `~> X.Y` allows patch updates (e.g., `~> 5.102` allows 5.102.x)
- For pre-1.0 gems: `~> 0.X, ">= 0.X.Y"` to pin a minimum while allowing patches
- For gems where a specific fix matters: add `">= X.Y.Z"` as an additional constraint

### Gemfile dependencies (development)

Same approach. If a major version bump is available (e.g., lefthook 1.x → 2.x), check the migration guide before bumping.

### Install

```bash
bundle update
```

If `bundle update` fails due to dependency conflicts, resolve them. Common strategies:
- Relax an overly tight constraint
- Update the conflicting parent gem first
- Accept that a gem can't be upgraded yet and document why

## Step 5: Verify with Tests

Run the full test suite:

```bash
bundle exec rspec
```

Also run the linter to catch any style issues:

```bash
bundle exec rake standard
```

If tests fail:
1. Read the failure carefully — is it caused by the upgrade or pre-existing?
2. If caused by the upgrade, fix the code to work with the new version
3. If unfixable, revert that specific gem's upgrade and note it in the report

## Step 6: Present Summary

Present a clear summary table of all changes:

```markdown
| Gem | Old Version | New Version | Old Constraint | New Constraint | Notes |
|-----|------------|-------------|----------------|----------------|-------|
| sequel | 5.100.0 | 5.102.0 | ~> 5.0 | ~> 5.102 | No breaking changes |
| lefthook | 1.13.6 | 2.1.4 | ~> 1.6 | ~> 2.1 | Major version bump, reviewed migration guide |
```

Follow the table with:

1. **Breaking changes found** — what changed and how the codebase was updated
2. **Gems held back** — which gems couldn't be upgraded and why (e.g., "diff-lcs 2.0 held back by rspec's ~> 1.4 constraint")
3. **Notable new features** — anything worth adopting from the new versions
4. **Test results** — confirmation that all tests pass

## Edge Cases

### Gems with no GitHub repository
Fall back to `gem info <name>` and the RubyGems page for release history. Note reduced confidence in the review.

### Yanked versions
If `bundle update` fails because a version was yanked, try the next most recent version.

### Pre-release versions
Do not upgrade to pre-release or alpha versions unless the user explicitly asks. Stick to stable releases.

### Monorepo gems
Some gems (like rails components) are versioned together. Upgrade them as a group.
