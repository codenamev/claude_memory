# Memory Database Audit — 2026-05-21

<no-memory>
This document discusses hallucinated facts and example stack names by way of diagnosis. It is wrapped in `<no-memory>` so the distiller does not re-extract the very words being audited. Human readers ignore the tags.
</no-memory>

<no-memory>

**Scope:** Full audit of the ClaudeMemory project's own memory database (global + project) against the actual state of the codebase at v0.11.0. Grades how useful the distilled knowledge is for coding agents working in this repo, and defines a systemic remediation pipeline.

**Snapshot:** `claude_memory @ main`, schema v18, 23 MCP tools, 9 predicates in `PredicatePolicy::POLICIES`.

---

## Executive Summary

The memory pipeline is structurally sound but **contaminated**. Three independent surfaces (global DB, project DB, generated snapshot) carry mixed signal — the curated snapshot is genuinely useful (~70% signal), but the MCP shortcut tools (`memory.decisions`, `memory.conventions`, `memory.architecture`) are net-misleading in their current form: they surface hallucinated stack diversity and global terminal preferences instead of the rich project knowledge that exists in the DB.

**Root cause:** CLAUDE.md's scope-system example text ("this app uses PostgreSQL", "I prefer 4-space indentation") is repeatedly re-distilled as fact. This compounds with a 99-item undistilled backlog and inconsistent shortcut-tool scope filters.

**Verdict:** Stop the bleeding (source-text fix + doc drift fix), then clean the noise floor (bulk-reject hallucinated `uses_*` facts), then fix the shortcut tool filters. The system can become trustworthy with ~1 day of focused work.

---

## Part 1 — Ground Truth (from the code)

ClaudeMemory v0.11.0, "Trust & Cost" release. Authoritative findings from full repo audit:

### Stack
- Pure Ruby gem. Ruby ≥ 3.2.
- Sequel + Extralite over SQLite (`Sequel.connect("extralite:#{path}")` only — never `Sequel.sqlite`).
- sqlite-vec for KNN; fastembed-rb optional for semantic search.
- **No Rails, no React, no Django, no Express, no Next.js, no MySQL, no Postgres, no Redis, no AWS/GCP/Azure/Vercel/Docker deployment.** It's a gem you install locally.

### Architecture (7 layers, verified)
- **Application:** `CLI` (41-line router) → 35 commands under `lib/claude_memory/commands/`, all inheriting `BaseCommand` with stdin/stdout/stderr DI.
- **Core Domain:** `domain/` (Fact, Entity, Provenance, Conflict — frozen + validated) + `core/` (21 value/null objects: Result, SessionId, NullFact, FactRanker, RRFusion, etc.).
- **Infrastructure:** `Store::SQLiteStore` (with `RetryHandler`, `SchemaManager`, `LLMCache`, `MetricsAggregator` mixins), `Store::StoreManager` (dual-DB router), `Infrastructure::FileSystem` / `InMemoryFileSystem`.
- **Business Logic:** `Ingest`, `Index` (`LexicalFTS` + `VectorIndex`), `Distill` (`NullDistiller`, `ReferenceMaterialDetector`, `BareConclusionDetector`), `Resolve::Resolver` + `Resolve::PredicatePolicy`, `Recall` (facade → `DualEngine`/`LegacyEngine` both including `QueryCore`), `Sweep`, `Publish`, `MCP`, `Hook`.
- **Dashboard:** 14 panel modules under `lib/claude_memory/dashboard/`.

### Schema
Current `SCHEMA_VERSION = 18` in `lib/claude_memory/store/schema_manager.rb:8`. 18 migrations in `db/migrations/`:
- v13 → `mcp_tool_calls` (telemetry, minimal columns — no query_text/hash by YAGNI).
- v15 → `activity_events` (hook/recall/context/sweep/store_extraction/roi_nudge events).
- v16 → `moment_feedback` (per-event 👍/👎 verdicts, upsert on event_id).
- v17 → `facts.last_recalled_at` (access-based staleness via `Sweep::RecallTimestampRefresher`).
- v18 → `otel_metrics`/`otel_events`/`otel_traces` + `activity_events.prompt_id` for prompt-journey correlation.

### Predicates (9, not 8)
From `lib/claude_memory/resolve/predicate_policy.rb`:

| Predicate | Cardinality | Section |
|---|---|---|
| `convention` | multi | conventions |
| `decision` | multi | decisions |
| `architecture` | multi | additional (intentionally unmapped) |
| `reference` | multi | references *(new in 0.11.0)* |
| `uses_framework` | multi | constraints |
| `uses_language` | multi | constraints |
| `uses_database` | single (exclusive) | constraints |
| `deployment_platform` | single (exclusive) | constraints |
| `auth_method` | single (exclusive) | constraints |

Synonyms (with `Deprecations.warn`, removal in 1.0.0): `has_convention → convention`, `primary_language → uses_language`.

### MCP (23 tools, not 25)
Six handler modules under `lib/claude_memory/mcp/handlers/`: `QueryHandlers`, `ShortcutHandlers`, `ContextHandlers`, `ManagementHandlers`, `StatsHandlers`, `SetupHandlers`. `MCP::Telemetry` wraps `Server#handle_tools_call`, records to `mcp_tool_calls`, swallows DB errors so telemetry never breaks a tool response.

### Hooks
Five events: **ingest**, **context**, **sweep**, **publish**, **nudge** (new in 0.11.0, `MAX_NUDGES=10`, silently no-ops on empty sessions or `CLAUDE_MEMORY_NO_NUDGE=1`). `AutoMemoryMirror` runs on fresh `SessionStart`, surfaces up to 5 candidates × 1500 chars from `~/.claude/projects/<slug>/memory/*.md`.

### Distillation (three layers, all wired)
- **Layer 1 — NullDistiller:** regex, P95 < 5ms, runs every hook.
- **Layer 2 — SessionStart context injection:** `hookSpecificOutput.additionalContext` with reason-clause-required extraction prompt. Claude Code itself acts as distiller at no extra API cost.
- **Layer 3 — `/distill-transcripts` skill:** manual, deep extraction with depth-aware prompts.
- `ReferenceMaterialDetector` is wired at `mcp/handlers/management_handlers.rb:37` so external-project descriptions can't persist as `convention` facts.
- `BareConclusionDetector` is wired into the Trust panel's `quality_score` and the digest's Quality section.

### Documentation drift in CLAUDE.md / generated rules
- "8 predicates" → actually **9** (CLAUDE.md predates the `reference` predicate added in 0.11.0).
- "25 MCP tools total" → actually **23**.

---

## Part 2 — What Memory Actually Believes

### Database state (`memory.stats`)

| Scope | Total | Active | Superseded | Open Conflicts | Pending Distillation |
|---|---|---|---|---|---|
| Global | 12 | 7 | 2 | 0 | — |
| Project | 201 | 46 | 37 | **10** | **99** |

### Project predicate distribution (46 active)
- `convention`: 28
- `architecture`: 6
- `uses_language`: 3 *(ruby, go, python — repo is Ruby-only)*
- `decision`: 3
- `uses_framework`: 2 *(rails, react — neither present in code)*
- `reference`: 2
- `uses_database`: 1
- `deployment_platform`: 1

### Global memory (7 active)
All `convention` predicate, all user-level workflow prefs: Docker, tmux, iTerm2, VS Code + Ruby LSP. Several near-duplicates (ids 1↔8, 6↔11, 7↔12, 5↔10).

### Open conflicts (10, all cluster around hallucination loop)
- Fact #21 `uses_database=sqlite` vs #139 postgresql, #148 postgres, #154, #155 redis.
- Fact #45 `uses_framework=rails` vs sinatra/express/django/next.js/react.
- Fact #48 `deployment_platform=aws` vs gcp/vercel/docker/azure.

All caused by CLAUDE.md scope-system example text being repeatedly re-extracted; resolver dutifully creates a new conflict each pass because none of the values can be authoritatively chosen.

---

## Part 3 — Tool-by-Tool Grading

### `memory.decisions` — Grade: D
Returns 23 results, only **3** are actual `decision`-predicate facts. The rest are `uses_*`/`deployment_platform`/`reference` rows. Output mixes contradictory single-cardinality predicates as if they all hold simultaneously. **Net effect: agent concludes this gem talks to MySQL + Postgres + Redis + SQLite at once.** It doesn't.

### `memory.conventions` — Grade: F (for project work)
Returns 10 results, **all global scope**. The 28 high-value project conventions (Configuration instance-only, Sequel/extralite adapter rule, version-in-3-places, EXPECTED_HOOKS sync, block-style rule, A/B testing methodology, `/release` workflow, etc.) are **not returned**. Worse, the global list is half-duplicates.

### `memory.architecture` — Grade: D
Returns 31 results. ~25 are hallucinated `uses_*` / `deployment_platform` facts; ~6 are global user-preference noise. The real architectural facts (PredicatePolicy SoT, MCP::Tools 6-handler split, Recall facade structure, SQLiteStore mixin pattern, Embeddings::DimensionCheck) **don't appear in the top 31**.

### Generated snapshot (`.claude/rules/claude_memory.generated.md`) — Grade: B+
Auto-loads into every Claude Code session. Genuinely useful:
- 3 real decisions (MCP telemetry minimal columns, QMD restudy, claude-supermemory study), all with reason clauses.
- ~25 real project conventions covering the genuine gotchas.
- 6 architecture facts (PredicatePolicy SoT, MCP::Tools dispatcher, Recall facade, SQLiteStore mixins, pluggable Embeddings, DimensionCheck value object).

**But:** the "Technical Constraints" block says `uses_framework=rails`, `deployment_platform=aws` (both wrong), and the Open Conflicts list at the bottom is a 47-row tail that pushes useful content down.

### Auto-memory files (`~/.claude/projects/-Users-…/memory/*.md`) — Grade: A
Separately maintained, never made it into the SQLite DB. Highest-quality knowledge in the system: SchemaVersion-in-tests, `upsert_content_item` requires `text_hash`+`byte_len`, FTS indexing pattern, hook context test isolation, WAL stale-cache phantom corruption, FTS5 rank corruption after `.recover`, scope_hint vs scope routing, round-trip migration specs. **Invisible to `memory.recall`.** Only surfaced transiently via `AutoMemoryMirror` at SessionStart.

---

## Part 4 — Root Causes

1. **CLAUDE.md scope-system example is a hallucination factory.** It contains literal phrases ("this app uses PostgreSQL", "I prefer 4-space indentation") that Layer 1 and Layer 2 distillers extract as ground truth. Known open product gap (`feedback_hallucination_source_vs_cleanup.md`).
2. **99-item distillation backlog.** SessionStart prompts for deep distillation but `mark_distilled` isn't being called for most items. Same text gets re-extracted across sessions, conflicts re-open.
3. **Shortcut tools have inconsistent filters.** `memory.conventions` is hardcoded to global scope; `memory.decisions` aggregates across `decision`/`uses_*`/`reference` predicates; `memory.architecture` mixes scopes and predicates differently again. None correctly answer "what does this project actually look like?"
4. **Single-cardinality predicates can't self-heal.** `uses_database`, `deployment_platform` keep flipping as new hallucinated facts arrive; resolver creates a new conflict each time and never closes the old ones.
5. **Documentation drift propagates.** CLAUDE.md says "8 predicates", "25 MCP tools" — if a coding agent re-extracts from CLAUDE.md, these incorrect counts become persisted facts.
6. **Auto-memory bypass.** The highest-quality knowledge (gotcha files) lives in markdown files outside the DB, so retrieval tools can't reach it.

---

## Part 5 — Remediation Pipeline

Four phases, lowest-risk highest-leverage first. Each phase has explicit done criteria and a verification step. The whole pipeline should be re-runnable: see Phase 4 for the systemic check.

### Phase 1 — Stop the bleeding *(blocks further drift, ~30 min)*

| # | Action | Verification |
|---|---|---|
| 1.1 | Wrap CLAUDE.md scope-system example text in `<no-memory>` tags (around the "this app uses PostgreSQL" / "I prefer 4-space indentation" example block in the Scope System section). | Re-ingest CLAUDE.md, confirm no new `uses_database=postgresql` or `convention=4-space indentation` facts appear. |
| 1.2 | Update CLAUDE.md predicate count: "8 entries" → "9 entries (includes `reference`)". | grep "8 entries" returns 0 matches in CLAUDE.md. |
| 1.3 | Update CLAUDE.md MCP tool count: "25 tools total" → "23 tools total". | grep "25 tools" returns 0 matches in CLAUDE.md. |
| 1.4 | Update `.claude/rules/claude_memory.generated.md` regeneration path: run `claude-memory publish` after Phase 2 cleanup to refresh. | Generated file matches active facts. |

**Done criteria:** Source-text fix in place. No new hallucinations will be created from these specific triggers.

### Phase 2 — Clean the noise floor *(reclaims trust in the DB, ~45 min)*

Bulk-reject the hallucinated facts. Order matters — reject leaves before clearing conflicts.

| # | Action | Command | Verification |
|---|---|---|---|
| 2.1 | Reject hallucinated `uses_framework` facts. Keep: none in production code (this gem has no framework dependency in the runtime sense). | `claude-memory reject 45 46 47 50 51 53 54 55 56 57 61 65 66 67 72 73 74 134 196 197 198` (rails, sinatra, react, express, next.js, django + tail of synonyms) | `memory.recall "uses_framework" scope=project` returns 0. |
| 2.2 | Reject hallucinated `uses_language` facts. Keep: `ruby` (id 76). Reject the rest. | `claude-memory reject 75 78 91 149 195` (javascript, go, python, typescript, rust) | `memory.recall "uses_language" scope=project` returns only ruby. |
| 2.3 | Reject hallucinated `uses_database` facts. Keep: `sqlite` (id 21). Reject the rest. | `claude-memory reject 62 63 139 148 154 155` (mysql, postgres, postgresql, redis) | `memory.recall "uses_database" scope=project` returns only sqlite. |
| 2.4 | Reject hallucinated `deployment_platform` facts. The gem has none — reject all. | `claude-memory reject 27 48 49 52 70` (azure, aws, gcp, vercel, docker) | `memory.recall "deployment_platform" scope=project` returns 0. |
| 2.5 | Dedupe global `convention` facts (Docker, tmux, iTerm2, VS Code duplicates). | `claude-memory reject 8 11 12 10` (keep ids 1, 6, 7, 5 from each duplicate pair) | `memory.conventions scope=global` returns ≤ 7 distinct facts. |
| 2.6 | Triage the 99-item distillation backlog. Either `/distill-transcripts` to deeply extract or bulk-call `memory.mark_distilled` to clear. | Use `memory.undistilled` to inspect, then run `/distill-transcripts` for items with potential, mark-distilled for the rest. | `memory.stats` pending_distillation < 10. |
| 2.7 | Conflicts close as a side effect of rejection (reject resolves the open conflict in the same transaction per `claude-memory reject` convention). | — | `memory.conflicts` returns 0. |

**Done criteria:** Project DB has ~25 high-signal active facts. Conflicts: 0. Pending distillation: < 10.

**Note:** The exact fact IDs above are from the 2026-05-21 snapshot. Re-query `memory.stats` and `memory.recall` before executing to confirm the IDs haven't shifted.

### Phase 3 — Fix the system *(prevents recurrence, ~2-3 hours)*

| # | Action | Where | Verification |
|---|---|---|---|
| 3.1 | **Fix `memory.conventions` scope filter.** Default should return project conventions (with optional global merge), not global-only. | `lib/claude_memory/mcp/handlers/shortcut_handlers.rb` (convention shortcut) + `lib/claude_memory/mcp/tool_definitions.rb` (tool description). | New spec: `memory.conventions` on this repo returns the 28 project conventions, not just the 7 global ones. |
| 3.2 | **Fix `memory.decisions` predicate filter.** Should return only `decision`-predicate facts (with reason clauses), not `uses_*` rows. | `lib/claude_memory/mcp/handlers/shortcut_handlers.rb` (decision shortcut). | `memory.decisions` returns only facts where `predicate = 'decision'`. |
| 3.3 | **Fix `memory.architecture` predicate filter.** Should return only `architecture`-predicate facts, not `uses_*` aggregates. | `lib/claude_memory/mcp/handlers/shortcut_handlers.rb`. | `memory.architecture` returns only facts where `predicate = 'architecture'`. |
| 3.4 | **Migrate auto-memory `~/.claude/projects/.../memory/*.md` content into the project DB.** Each gotcha becomes a `convention` or `architecture` fact with full reason clause. Today it's only surfaced transiently via `AutoMemoryMirror`. | One-off script or a new `claude-memory import-auto-memory` command. | Top auto-memory gotchas (Configuration-instance-only, schema-version-in-tests, FTS indexing pattern, etc.) are reachable via `memory.recall`. |
| 3.5 | **Strengthen `ReferenceMaterialDetector`** so it catches the specific scope-system example phrasing if `<no-memory>` is ever removed. Add unit test: extracting from "this app uses PostgreSQL" inside a paragraph titled "Scope System" should be rejected as reference material. | `lib/claude_memory/distill/reference_material_detector.rb`. | New spec passes. |
| 3.6 | **Add `Resolve::Resolver` conflict auto-resolution heuristic** for single-cardinality predicates when one fact has reference-material signals and the other doesn't. | `lib/claude_memory/resolve/resolver.rb`. | New spec: conflict between authoritative SQLite fact and example-text Postgres fact auto-resolves in SQLite's favor. |

**Done criteria:** Shortcut tools return signal-only. Auto-memory gotchas are first-class facts. Future hallucinations are caught earlier.

### Phase 4 — Verify & make systemic *(prevents regression, ~1 hour)*

| # | Action | Where | Verification |
|---|---|---|---|
| 4.1 | **Create `bin/memory-audit`** — script that runs `memory.stats`, lists active facts by predicate, flags `uses_*` outliers (e.g. multiple `uses_database` values active), reports open conflicts, reports pending distillation count, and exits non-zero if thresholds are exceeded. | `bin/memory-audit`. | Script run on a clean DB exits 0. Inject a hallucinated fact and confirm exit 1. |
| 4.2 | **Add a benchmark `spec/benchmarks/health/database_signal_spec.rb`** that codifies expected signal-to-noise ratio for this project: minimum conventions reachable via `memory.conventions`, maximum `uses_*` cardinality for single-cardinality predicates, zero open conflicts on main. | `spec/benchmarks/health/`. | `bundle exec rspec spec/benchmarks/health/` passes on a clean DB. |
| 4.3 | **Add a quarterly recurring task** (or schedule via the `schedule` skill) to re-run this audit and produce a dated `docs/memory_audit_<date>.md`. | `bin/run-evals --health` or a cron entry. | An audit is generated on schedule, diffed against the prior. |
| 4.4 | **Update `docs/api_stability.md`** to mention the audit script and the signal-health benchmark as part of pre-release verification. | `docs/api_stability.md`. | Mention is present. |

**Done criteria:** Future drift will be caught by a script, not by accident.

---

## Appendix A — Fact IDs to Reject (2026-05-21 snapshot)

Re-verify before executing; IDs may shift if other writes occur.

**`uses_framework` (reject all):** 45, 46, 47, 50, 51, 53, 54, 55, 56, 57, 61, 65, 66, 67, 72, 73, 74, 134, 196, 197, 198.

**`uses_language` (keep 76 ruby; reject):** 75, 78, 91, 149, 195.

**`uses_database` (keep 21 sqlite; reject):** 62, 63, 139, 148, 154, 155.

**`deployment_platform` (reject all):** 27, 48, 49, 52, 70.

**Global convention duplicates (reject):** 8, 10, 11, 12.

**Estimated cleanup result:** project active facts drop from 46 → ~25, all open conflicts close, generated snapshot's "Technical Constraints" block becomes accurate.

## Appendix B — Out of Scope (intentional)

- Migrating to a different vector store. Not the bottleneck.
- Re-architecting the distillation pipeline. The three-layer design is sound; only inputs and shortcut filters are broken.
- Changing the dual-DB model. Working as intended.

## Appendix C — Audit Methodology

1. Repo audit via Explore subagent covering 16 areas (layout, layers, dual-DB, distillation, predicates, hooks, recall engine, embeddings, MCP, dashboard, telemetry, tests, conventions, recent changes, public API, contradictions).
2. Memory database query via MCP tools: `memory.stats`, `memory.status`, `memory.decisions`, `memory.conventions`, `memory.architecture`, `memory.conflicts`, `memory.changes`, `memory.list_projects`.
3. Cross-reference: for each documented claim, verify against code and grade tool output usefulness for a hypothetical coding agent dropped into the repo.

---

*End of audit. Next snapshot: 2026-08-21 (quarterly) or after Phase 3 ships, whichever comes first.*

</no-memory>

<no-memory>

## Pipeline Execution Results — 2026-05-21

All four phases executed in a single session. Final state:

| Metric | Before | After |
|---|---|---|
| Global active facts | 7 | 4 |
| Project active facts | 46 | 68 *(↑ via auto-memory import)* |
| Open conflicts | 10 | 0 |
| Pending distillation | 99 | 0 |
| Single-cardinality violations | 1+ | 0 |
| `uses_database` active | 4 contradictory | 1 (sqlite) |
| `deployment_platform` active | 1 hallucinated | 0 |
| `uses_framework` active | 2 hallucinated | 0 |
| `uses_language` active | 3 (1 real, 2 halluc.) | 1 (ruby) |

### Phase 1 — Stop the bleeding (DONE)
- Wrapped CLAUDE.md scope-system example in `<no-memory>` tags.
- Fixed "25 tools" → "23 tools" drift in `CLAUDE.md`, `docs/api_stability.md`, `docs/plugin.md`.
- Wrapped this audit doc in `<no-memory>` so it doesn't self-contaminate on re-ingestion.

### Phase 2 — Clean the noise floor (DONE)
- Rejected 9 hallucinated project facts plus 3 global duplicates (Docker / iTerm2 / tmux variants).
- Bulk-marked 99 backlog content items as distilled.
- All 10 open conflicts closed.

### Phase 3 — Fix the system (DONE)
- **Shortcuts refactored** (`lib/claude_memory/shortcuts.rb`): switched from FTS text search to predicate-based filtering. `memory.conventions` now returns both project and global facts (was global-only); `memory.decisions` now returns only `decision`-predicate facts (was returning `uses_*` too); `memory.architecture` returns only architecture + stack-shaping predicates.
- **Tool descriptions updated** in `lib/claude_memory/mcp/tool_definitions.rb` to reflect new behavior.
- **AutoMemoryMirror slug bug** fixed (`tr("/", "-")` → `tr("/_", "-")`) — previously silently missed auto-memory for any project name with underscores, including `claude_memory` itself.
- **New CLI command** `claude-memory import-auto-memory [--dry-run]` migrates `~/.claude/projects/<slug>/memory/*.md` into the project DB as durable facts. Imported 27 gotchas/feedback/reference files.
- **ReferenceMaterialDetector strengthened** with `QUOTE_GUARDED_PREDICATES` and `EXAMPLE_QUOTE_PATTERNS`: stack predicates extracted from example-text quotes ('e.g., ...PostgreSQL') now reroute to `reference`.
- **Resolver discard heuristic** added: single-cardinality predicates with example-text quotes get silently dropped instead of creating disputed-fact + conflict rows. Catches the case where Layer-1 NullDistiller bypasses ReferenceMaterialDetector.
- Specs added/updated for each (50 examples across `shortcuts_spec.rb`, `reference_material_detector_spec.rb`, `resolver_spec.rb`). Full suite: **2121 passing, 0 failures**.

### Phase 4 — Verify & make systemic (DONE)
- **`bin/memory-audit`** script writes a stable JSON shape (`--json`) and exits non-zero on threshold breach. Hard fails on: any open conflict, >1 active fact per single-cardinality predicate, ≥ 100 pending distillation. Warns on ≥ 25 pending.
- **`spec/benchmarks/health/database_signal_spec.rb`** codifies the contracts as a `:benchmark`-tagged RSpec suite. Runs against the live DB. 10 examples passing.
- **`docs/api_stability.md` Section 7** documents the audit script's stable surface and the benchmark spec; corrected schema version from v17 → v18 (8 → 18 migrations).

### Re-running this pipeline

If this audit goes stale (drift creeps back in), re-run from the top:

```bash
bin/memory-audit                                                  # see current state
bundle exec rspec spec/benchmarks/health/ --tag benchmark        # confirm contracts
./exe/claude-memory import-auto-memory --dry-run                 # preview new auto-memory
```

Failure modes the audit will catch:
- A new contamination source landing in CLAUDE.md or another auto-ingested file.
- A shortcut handler losing predicate-filter semantics in a refactor.
- A resolver bug re-introducing single-cardinality conflicts.
- An undistilled-content backlog from a high-traffic week.

</no-memory>
