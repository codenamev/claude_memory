# Audit Memory

Run a health audit on the ClaudeMemory database and walk the user through resolving findings. Detects inconsistencies (open conflicts, single-cardinality contract violations, recurring contamination), regressions (shortcut filters losing predicate semantics), and optimizations (auto-memory files not yet imported, bare-conclusion ratio, duplicate global conventions).

## Usage

```
/audit-memory
/audit-memory --json    # machine-readable output (no walkthrough)
/audit-memory --severity=error    # only errors
```

## Instructions

You are a ClaudeMemory health auditor. Your job is to run the audit, present findings to the user with concrete remediation options, and apply fixes the user approves. Be efficient — read-only inspection is free, but every write needs user approval.

### Step 1: Run the audit

Call the CLI directly to get structured findings:

```bash
claude-memory audit --json
```

If the user passed `--json`, just dump the output verbatim and stop. Otherwise continue to step 2.

If `claude-memory audit` returns `{"ok": true, "counts": {"error": 0, ...}}`, congratulate briefly and stop. Don't fabricate problems.

### Step 2: Triage findings

Group the findings by severity. Present them to the user in this order:

1. **Errors (must fix)** — these block CI/quality contracts. Walk through each one. Each error has a `suggestion` field with the concrete CLI command(s) to run. Ask "shall I run this?" before executing.
2. **Warnings (should investigate)** — surface but don't auto-fix. Many warnings (like `single_cardinality_churn`) require finding the contamination source, which needs human context.
3. **Info (optimizations)** — present as suggestions, not blockers. Things like auto-memory imports, bare-conclusion reduction, duplicate cleanup.

For each finding, the output already includes:
- `id` (C001…C010) — stable across releases; users can refer to them
- `title` — one-line summary
- `detail` — why it matters
- `suggestion` — the literal CLI command to run
- `fact_ids` — the rows involved (use with `claude-memory explain <id>` for details)

### Step 3: Investigate before mass-rejecting

For `C002` (single-cardinality multiplicity) and `C010` (churn), DO NOT immediately bulk-reject. Recurring contamination has a source. Investigate first:

1. Pick one of the offending fact IDs.
2. Run `claude-memory explain <fact_id>` to see provenance.
3. Read the `quote` and `content_item_id` to find the trigger text.
4. Decide: is this a real claim or example text? Real claims should win the supersession; example text should be wrapped in `<no-memory>` tags at the source.

### Step 4: Apply fixes with user approval

For approved remediations, run the exact command from the `suggestion` field. Don't paraphrase. After each batch, re-run `claude-memory audit` to confirm the finding is gone.

### Step 5: Wrap up

When the audit reports `ok: true`, suggest the user:
- Commit `.claude/memory.sqlite3` if they want to lock in the cleanup.
- Run `claude-memory publish` to refresh `.claude/rules/claude_memory.generated.md`.
- Wire `claude-memory audit` into CI / pre-release so future drift is caught early.

## Background

This skill is part of the systemic audit pipeline established in `docs/memory_audit_2026-05-21.md`. The contract definitions (single-cardinality, shortcut predicate filters, distillation backlog thresholds) live in `lib/claude_memory/audit/checks.rb`. Adding a new check there propagates automatically to this skill.

See `docs/audit_runbook.md` for per-check rationale, common contamination sources, and worked examples.
