# Memory Audit Runbook

This runbook explains every check the audit runs, why it matters, and how to remediate findings. It is the human-readable companion to `claude-memory audit` and the `/audit-memory` skill.

## When to run

- **After a release** — before tagging, confirm no contracts were silently broken.
- **When `memory.recall` feels noisy** — if you ask for conventions and get unrelated stack facts, the shortcut filters may have regressed.
- **When ingest seems slow** — a large distillation backlog or repeating contamination loop will compound over weeks.
- **In CI on `main`** — wire `claude-memory audit --no-exit --json` into a workflow and post the output to a dashboard.

## Quick start

```bash
claude-memory audit                 # human-readable, exits non-zero on error
claude-memory audit --json          # machine-readable JSON
claude-memory audit --severity=error  # only blocking findings
/audit-memory                       # interactive walkthrough via Claude Code
```

## Output shape

JSON payload:

```json
{
  "ok": true,
  "checks_run": 10,
  "counts": {"error": 0, "warn": 1, "info": 2},
  "stats": {
    "global": {"active_facts": 4, "predicate_counts": {"convention": 4}},
    "project": {"active_facts": 68, "predicate_counts": {...}}
  },
  "findings": [
    {
      "id": "C003",
      "severity": "warn",
      "title": "27 content items not yet deeply distilled",
      "detail": "...",
      "suggestion": "claude-memory sweep --mark-all-distilled OR /distill-transcripts",
      "fact_ids": []
    }
  ]
}
```

Exit code is `0` when `ok: true`, `1` otherwise. `--no-exit` always returns `0`.

## Checks

### C001 — Open conflicts

**Severity:** error

**Triggered when:** the project or global DB has any row in `conflicts` with `status='open'`.

**Why it matters:** Conflicts pause supersession. Until they close, single-cardinality predicates can't reach a clean state. Every re-ingest of the contested content potentially adds noise.

**Remediation:**
1. List with `claude-memory conflicts`.
2. For each pair, run `claude-memory explain <fact_a>` and `claude-memory explain <fact_b>` to inspect provenance.
3. Reject the wrong claim with `claude-memory reject <fact_id> --reason "<why>"`. Rejection closes any conflict the fact was party to in the same transaction.

### C002 — Single-cardinality multiplicity

**Severity:** error

**Triggered when:** `uses_database`, `deployment_platform`, or `auth_method` has more than one active fact.

**Why it matters:** The single-cardinality contract is "at most one active value per predicate." Multiple actives mean either the resolver dropped a supersession or distillation produced contradictions. Downstream tools (snapshot publishing, `memory.architecture`) will list mutually exclusive values.

**Remediation:**
1. Identify the right value (the one the project actually uses).
2. `claude-memory reject <fact_id>` on the others.
3. Re-audit to confirm; if it keeps recurring, look at C010 (churn) and find the contamination source.

### C003 — Distillation backlog

**Severity:** warn (≥ 25) or error (≥ 100)

**Triggered when:** content items are not present in `ingestion_metrics`, indicating they haven't been deep-distilled (Layer 2/3).

**Why it matters:** Backlog grows when SessionStart distillation prompts don't get acknowledged via `memory.mark_distilled`. The same transcript text keeps getting re-extracted across sessions, multiplying hallucination opportunities.

**Remediation:**
- **Triage path (preserves signal):** `/distill-transcripts --limit 10` repeatedly until cleared. Slow, but extracts genuine facts.
- **Bulk-clear path (accepts backlog is noise):** `claude-memory sweep --mark-all-distilled`. Use when the backlog is old transcripts unlikely to add value.

### C004 — `memory.decisions` predicate leak

**Severity:** error

**Triggered when:** the `memory.decisions` MCP shortcut returns facts whose predicate is not `decision`.

**Why it matters:** The shortcut should be a clean `predicate=decision` filter. Pre-2026-05-21, it ran an FTS text search on "decision constraint rule requirement" which matched `uses_database`/`uses_framework` rows. Any leakage means the shortcut has regressed.

**Remediation:**
- Open `lib/claude_memory/shortcuts.rb` and verify `SHORTCUTS[:decisions][:predicates]` is `%w[decision]`.
- Run `bundle exec rspec spec/claude_memory/shortcuts_spec.rb`.
- File a bug if the spec passes but real output leaks.

### C005 — `memory.conventions` scope regression

**Severity:** warn

**Triggered when:** `memory.conventions` returns zero project-scoped facts despite the project DB containing active conventions.

**Why it matters:** Pre-2026-05-21, `memory.conventions` was hardcoded to `scope=global` only. Project conventions were invisible to coding agents calling the shortcut. Resurfacing this regression means losing project knowledge.

**Remediation:**
- Inspect `Shortcuts.collect_facts` in `lib/claude_memory/shortcuts.rb` — it must query both `manager.project_store` and `manager.global_store`.
- Re-run the shortcut spec.

### C006 — Duplicate global conventions

**Severity:** info

**Triggered when:** the global DB has multiple `convention` facts whose object text normalizes to the same phrasing (after lowercasing, stripping `uses`/`prefers`/punctuation).

**Why it matters:** Duplicates pollute the global convention list and inflate the apparent size of your memory. They don't break correctness, but they waste tokens.

**Remediation:**
1. Pick the cleanest phrasing.
2. `claude-memory reject <duplicate_id>` on the rest.

### C007 — Bare-conclusion rate

**Severity:** info

**Triggered when:** ≥ 30% of active `decision`/`convention` facts lack a reason clause ("because", "so that", "to avoid", etc.).

**Why it matters:** Facts without justification are dead weight when the original context fades. A high bare-conclusion ratio means the LLM distillation is shipping low-quality extractions.

**Remediation:**
- Low-value bare facts: reject.
- Important bare facts: rewrite via `memory.store_extraction` with a `quote` that embeds the reason, then reject the bare original.
- See `Distill::BareConclusionDetector` for the canonical signal patterns.

### C008 — Project starvation

**Severity:** warn

**Triggered when:** the project DB has fewer than 5 active facts.

**Why it matters:** A nearly-empty DB suggests either a fresh install (ignore) or a broken ingest pipeline / overzealous cleanup. Distinguishing requires looking at ingest history.

**Remediation:**
- `claude-memory doctor` — verify hooks are firing.
- `claude-memory stats` — check `content_items.total` vs `facts.active`; if many content items but few facts, distillation isn't running.
- Check `.claude/settings.json` for hook configuration.

### C009 — Auto-memory unimported

**Severity:** info

**Triggered when:** `~/.claude/projects/<slug>/memory/*.md` contains more files than the project DB has `content_items` with `source='auto_memory_import'`.

**Why it matters:** Claude Code's auto-memory markdown files are durable user-curated knowledge. Until imported, they only surface transiently via `AutoMemoryMirror` at SessionStart — they're invisible to `memory.recall` and to the shortcut tools.

**Remediation:**
- Preview: `claude-memory import-auto-memory --dry-run`.
- Apply: `claude-memory import-auto-memory`.

### C010 — Single-cardinality churn

**Severity:** warn

**Triggered when:** any single-cardinality predicate has ≥ 5 historical non-active facts (superseded + disputed + rejected).

**Why it matters:** Repeated supersession on a "must be exactly one" predicate is the signature of a persistent contamination source. Common culprits:
- Example text in `CLAUDE.md` ("e.g., this app uses PostgreSQL") triggers extraction every session.
- Comments in code/docs naming alternative stacks.
- Audit/discussion documents (like this one) mentioning the contaminating value.

**Remediation:**
1. Find the trigger: `claude-memory recall "<bad_value>" --scope=project`. Inspect the matching content items and their source.
2. Wrap the trigger text in `<no-memory>` tags at the source.
3. Clean up: `claude-memory reject` the historical disputed/superseded rows (or accept them as historical record).
4. Re-audit.

## Adding a new check

The audit is extensible by design.

1. Add a method to `ClaudeMemory::Audit::Checks` returning `Array<Finding>`. Convention: pure read-only access to the StoreManager.
2. Append the method name to `Audit::Runner::CHECK_METHODS`.
3. Document the check in this runbook (this file) with the same `C###` ID.
4. Write a spec at `spec/claude_memory/audit/checks_spec.rb`.

## Integrating with CI

A minimal GitHub Actions step:

```yaml
- name: ClaudeMemory health audit
  run: bundle exec claude-memory audit --json | tee audit.json
- uses: actions/upload-artifact@v4
  with:
    name: memory-audit
    path: audit.json
```

Treat error-severity findings as build failures. Warnings can route to a Slack channel for periodic triage.

## Related

- `docs/memory_audit_2026-05-21.md` — the original audit and 4-phase remediation pipeline that established this workflow.
- `docs/api_stability.md` Section 7 — stable surface of the audit script and benchmark spec.
- `spec/benchmarks/health/database_signal_spec.rb` — runtime contract checks that mirror C001/C002/C004/C005.
