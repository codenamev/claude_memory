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

### C011 — Orphaned observations

**Severity:** warn

**Scope:** both the project and global DBs (observations may be scoped either way).

**Triggered when:** an observation has `source_content_item_id` set but no `content_items` row with that id exists.

**Why it matters:** An observation's `source_content_item_id` is its provenance link back to the transcript chunk it was distilled from. A dangling pointer means the source row was pruned (or never existed), so the observation can no longer be explained — breaking the same provenance guarantee facts enjoy. Observations with a `nil` source (e.g. consolidated ones synthesized from several sources) are *not* flagged.

**Remediation:**
- Inspect with `memory.observations` (or the dashboard Observations tab).
- The table is append-only — do **not** delete. If the provenance is genuinely unrecoverable, let the Reflector consolidate or expire the row on the next PreCompact/SessionEnd pass.

### C012 — Observation promotion consistency

**Severity:** error

**Scope:** both DBs.

**Triggered when:** any of the following promotion-state invariants is violated —
- `promoted_at` is set but `promoted_fact_id` is `NULL`;
- `promoted_fact_id` points at a fact that does not exist;
- `promoted_fact_id` points at a fact that is **not** active (rejected/superseded);
- `promoted_fact_id` is set but `promoted_at` is `NULL`.

**Why it matters:** Promotion is meant to be atomic — `mark_observation_promoted` sets both `promoted_at` and `promoted_fact_id` pointing at a freshly-created, active fact. Half-set state means the write ran partially, or the target fact was later rejected/superseded, leaving the observation pointing at nothing usable. The promotion bridge keys off these columns, so an inconsistent row either re-promotes (duplicate facts) or is silently stuck.

**Remediation:**
1. `claude-memory explain <fact_id>` on the `promoted_fact_id` to see why the fact is missing/inactive.
2. If the fact was intentionally rejected, re-open the observation for re-promotion via `memory.promote_observation`.
3. If `mark_observation_promoted` half-ran, re-run promotion so both columns are set together.

### C013 — Observation tombstone-chain validity

**Severity:** error

**Scope:** both DBs.

**Triggered when:** any of the following tombstone invariants is violated —
- `consolidated_into` points at a non-existent observation;
- `consolidated_into` is a self-link (`consolidated_into == id`);
- a row is `status='active'` yet carries a `consolidated_into` target;
- a row is `status='consolidated'` yet has no `consolidated_into` keeper.

**Why it matters:** Supersession is append-only: a merged-away observation gets `status='consolidated'` and `consolidated_into` pointing at the surviving keeper, preserving lineage instead of hard-deleting (unlike Mastra's lossy drop). A broken chain corrupts that lineage — recall could surface a tombstoned row, or a consolidated row could orphan its history. A self-link or active-but-tombstoned row is a Reflector bug, not user error.

**Remediation:**
- Inspect with `memory.observations`.
- Re-running the deterministic Reflector (fires on PreCompact/SessionEnd) re-derives consolidation for dangling links.
- A self-link or `active` + `consolidated_into` row signals a Reflector defect — file it rather than hand-editing the append-only table.

### C014 — Observation status / corroboration sanity

**Severity:** warn

**Scope:** both DBs.

**Triggered when:** an observation has a `status` outside `active`/`consolidated`/`expired`, or a `corroboration_count` less than 1.

**Why it matters:** Every observation should carry a known lifecycle status and at least one sighting (a fresh insert counts as 1; the migration default is 1). An unknown status means a migration or an external writer bypassed `insert_observation`; a `corroboration_count < 1` means `increment_corroboration` math went negative. Both break downstream behavior — recall filters key off `status`, and the promotion gate keys off `corroboration_count`.

**Remediation:**
- Inspect with `memory.observations`.
- For a bad `corroboration_count`, re-derive sighting counts via the Reflector's dedup pass.
- For an unknown status, find the writer that bypassed `insert_observation` (the only sanctioned insert path).

### C015 — Truncated source content

**Severity:** info

**Scope:** both DBs.

**Triggered when:** a `content_items` row's `raw_text` carries a host-truncation marker — e.g. `[Read output capped at N lines]`, `[Truncated: N chars]`, "output was truncated", or an "N lines omitted / N characters truncated" count form (see `Distill::TruncationDetector`).

**Why it matters:** Claude Code caps large tool output (notably Read) and leaves a marker in the transcript. Facts the distiller extracts from such a fragment were drawn from incomplete content, not complete ground truth — the same false-positive class as documentation example text the distiller takes literally. The detector deliberately does not recover the full file from disk: ingest runs after the fact and the file may have changed since, so disk recovery at ingest would be temporally unsound.

**Remediation:**
- Trace facts back with `claude-memory explain <fact_id>`.
- Reject any fact that asserts something the truncated fragment could not actually confirm.
- If you need the full content, re-run the relevant tool without truncation so the complete text is re-ingested.

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
