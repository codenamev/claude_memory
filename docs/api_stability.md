# API Stability

> Authoritative reference for what ClaudeMemory promises to keep stable
> across releases. If a surface is listed here as **stable**, breaking
> it without a deprecation cycle is a bug. If it's listed as **internal**
> or simply not listed, no compatibility is implied.

**Last updated:** 2026-05-01 (initial publication for 0.12.0). **Applies to:** `claude_memory` ≥ 0.12.0.

This doc is the contract `claude-memory` semver depends on. The 1.0.0 release will lock the **stable** surfaces below; subsequent minor releases (`1.x`) may grow the stable set but won't shrink it without a deprecation cycle. Earlier 0.x releases also followed semver in spirit, but the absence of this doc made it un-arbitrable. From 0.12 onward, this is the single source of truth.

---

## 1. Versioning policy

ClaudeMemory follows [SemVer 2.0](https://semver.org):

- **MAJOR** (`1.0.0`, `2.0.0`): breaking changes to **stable** surfaces below.
- **MINOR** (`0.X.0`, `1.X.0`): new features and additions; existing **stable** surfaces remain compatible.
- **PATCH** (`0.X.Y`): bug fixes only; no new features and no behavior changes to **stable** surfaces.

### Deprecation cycle

When we want to break or rename a **stable** surface in a future major:

1. Pick a `removed_in` version (typically `(N+1).0.0`).
2. Wire a runtime warning via `ClaudeMemory::Deprecations.warn(name:, replacement:, removed_in:)`. Continue accepting the old form.
3. Document in CHANGELOG under "Deprecated".
4. Keep the old surface working for **at least one minor cycle**.
5. Remove no earlier than the `removed_in` version.

Suppress deprecation noise in CI/tests with `CLAUDE_MEMORY_NO_DEPRECATIONS=1`.

### Stability tiers

Throughout this doc each surface carries one tier:

| Tier | Meaning |
|---|---|
| **stable** | Covered by semver. Breaking change requires deprecation cycle. |
| **experimental** | May change in any minor without deprecation. Use at your own risk. |
| **internal** | No guarantees. May change in any patch. Don't rely on it from external code. |

When ambiguous, default is **internal** — easier to promote later than demote.

---

## 2. Public CLI surface

All commands listed in `Commands::Registry::COMMANDS` are reachable via `claude-memory <subcommand>`. The full registered set (38 commands as of 0.12.1) is canonically stored in `lib/claude_memory/commands/registry.rb`. Stability:

### Stable commands (covered by semver)

These commands and their **documented** flags are stable. Adding new commands or new flags is non-breaking; renaming or removing requires a deprecation cycle.

| Command | Notes |
|---|---|
| `claude-memory init` | Project + global initialization. |
| `claude-memory uninstall` | Removes `.claude/settings.json` hooks and rules. |
| `claude-memory doctor` | Health check. New checks may be added; the JSON-summary mode is also stable. |
| `claude-memory dashboard [--port N] [--no-open]` | Local web UI. The dashboard's **JSON HTTP API is internal** — see §7. |
| `claude-memory recall <query>` | Fact retrieval. |
| `claude-memory promote <fact_id>` | Promote project → global. |
| `claude-memory reject <id_or_docid>` | Reject + close associated conflicts. |
| `claude-memory restore --predicate NAME` | Recover supersession from obsolete single-value classifications. |
| `claude-memory explain <fact_id>` | Provenance receipts. |
| `claude-memory recover` | Database recovery. |
| `claude-memory compact` | VACUUM + FTS rebuild. |
| `claude-memory export` | Dump facts to JSON. |
| `claude-memory ingest` / `sweep` / `publish` | Pipeline entrypoints. Hook commands stable as listed in §4. |
| `claude-memory hook <ingest\|sweep\|publish\|context\|nudge>` | Hook entrypoints; stdin JSON contract in §4. |
| `claude-memory serve-mcp` | MCP server. Argument schemas in §3. |
| `claude-memory stats [--scope SCOPE] [--tools] [--tokens] [--stale] [--since DAYS] [--stale-days N]` | Statistics. |
| `claude-memory show [--source SOURCE] [--pending]` | Print would-be-injected context (0.11.0+). |
| `claude-memory digest [--since DAYS] [--output FILE]` | Markdown rollup (0.10.0+). |
| `claude-memory census [--root DIR]` | Cross-project predicate audit (0.10.0+). |
| `claude-memory conflicts` / `changes` | Inspection. |
| `claude-memory db:init` | Initialize a single DB at a path. |
| `claude-memory completion <bash\|zsh\|fish>` | Shell completions. |
| `claude-memory version` / `help` | Inspection. |

### Experimental commands

May change in any minor; treat with care.

| Command | Notes |
|---|---|
| `claude-memory dedupe-conflicts [--dry-run] [--apply]` | One-shot historical cleanup. The output format (preview rows, count summary) may change. |
| `claude-memory reclassify-references [--dry-run] [--apply]` | Same shape; introduced 0.10.0. |
| `claude-memory recall --semantic` / `--mode=hybrid` | Semantic-recall flags depend on the embedding backend; `tfidf` is stable, `fastembed`/`api` may change configuration knobs. |
| `claude-memory embeddings` | Embedding-backend inspection; the JSON shape evolves with provider work. |
| `claude-memory import-auto-memory [--dry-run]` | Imports Claude Code auto-memory markdown files into the project DB as facts. Introduced 0.12.0 from the 2026-05-21 audit; argument shape and idempotency contract are stable but the heuristic for predicate mapping may evolve. |
| `claude-memory setup-vectors [--provider=NAME] [--model=NAME] [--no-reindex] [--dry-run] [--status]` | Documented opt-in path for enabling vector recall via fastembed. Introduced 0.12.1. Writes `CLAUDE_MEMORY_EMBEDDING_PROVIDER` (and optional `CLAUDE_MEMORY_EMBEDDING_MODEL`) to `.claude/settings.json` env block, then re-embeds via `IndexCommand`. fastembed remains a dev/test gem dep by design; install via `gem install fastembed` if not present. Argument shape stable; the underlying re-index implementation may evolve. |

### Internal / not for external automation

- `claude-memory index --vec` (rebuild operation) — semantics may shift with the embeddings overhaul.
- `claude-memory git-lfs` — installation helper; output shape not guaranteed.
- `claude-memory install-skill <name>` — skill plumbing.

### Exit codes (stable)

`Hook::ExitCodes`:

| Code | Meaning |
|---|---|
| `0` | Success or graceful degradation. |
| `1` | Non-blocking warning (shown to user; session continues). |
| `2` | Blocking error (fed to Claude for processing). |

Renaming or repurposing a code is a major-version change.

---

## 3. Public MCP tool surface

All 23 tools registered via `MCP::ToolDefinitions.all`. Argument schemas, return shapes (both `content` and `structuredContent`), and tool-annotation hints (`readOnlyHint`, `idempotentHint`, `destructiveHint`) are **stable** for the listed tools.

### Stable MCP tools

| Tool | Group | Stability notes |
|---|---|---|
| `memory.recall` | Query | Argument schema + return shape stable. New optional fields may be added. |
| `memory.recall_index` | Query | Stable. |
| `memory.recall_details` | Query | Stable. |
| `memory.recall_semantic` | Query | Stable since 0.9.0. |
| `memory.search_concepts` | Query | Stable. |
| `memory.explain` | Provenance | Stable. |
| `memory.fact_graph` | Provenance | Stable. |
| `memory.decisions` | Shortcut | Stable. |
| `memory.conventions` | Shortcut | Stable. |
| `memory.architecture` | Shortcut | Stable. |
| `memory.facts_by_tool` | Context | Stable. |
| `memory.facts_by_context` | Context | Stable. |
| `memory.promote` | Management | Stable. |
| `memory.reject_fact` | Management | Stable since 0.10.0. |
| `memory.store_extraction` | Management | Argument schema (`facts`, `entities`, `decisions`) stable. The `observations` field (Layer-2 observer) is **experimental** while the observational layer is built out. |
| `memory.undistilled` | Distillation | Stable since 0.10.0. |
| `memory.mark_distilled` | Distillation | Stable since 0.10.0. |
| `memory.status` | Monitoring | Stable. |
| `memory.stats` | Monitoring | Stable. |
| `memory.changes` | Monitoring | Stable. |
| `memory.conflicts` | Monitoring | Stable. |
| `memory.activity` | Monitoring | Stable since 0.10.0. |
| `memory.sweep_now` | Maintenance | Stable. |
| `memory.check_setup` | Discovery | Stable. |
| `memory.list_projects` | Discovery | Stable since 0.10.0. |

### Experimental MCP tools

These are registered in `MCP::ToolDefinitions.all` but **not yet covered by the stability guarantees above** — argument schema and return shape may change while the feature is built out.

| Tool | Group | Status |
|---|---|---|
| `memory.observations` | Observational layer | Experimental (unreleased). Read-only listing of episodic observations. |
| `memory.promote_observation` | Observational layer | Experimental (unreleased). Promotes a corroborated observation into a fact; refuses uncorroborated ones (anti-hallucination gate). Args/shape may change. |

### Stability of tool responses

Both response shapes are stable:

- **Text content**: a human-readable summary in `content[0].text`. Content text format may evolve, but always remains valid Markdown.
- **Structured content**: machine-parseable JSON in `structuredContent`. Top-level keys for each tool are stable; new keys may be added.
- **Compact mode** (`compact: true` argument where supported): the compact representation is stable but explicitly omits receipts. Decision is documented per-tool.

### What is NOT promised about MCP tools

- Tool descriptions (the prose strings in `tool_definitions.rb`) may be tuned for prompt quality.
- Tool annotations (`readOnlyHint` etc.) may flip if a tool's behavior changes — annotation flips count as a deprecation event.
- Server-internal pagination cursors are opaque to clients.

---

## 4. Public hook contract

ClaudeMemory ships hooks for **5 events** as listed in `Commands::Checks::HooksCheck::EXPECTED_HOOKS`: `Stop`, `StopFailure`, `SessionStart`, `PreCompact`, `SessionEnd`. The `init` command also writes hooks for `TaskCompleted`, `TeammateIdle`, and `Notification` in projects that opt in. **Adding or removing the events that `init` writes is a stable-surface change.**

### Hook subcommands (stable since 0.10.0)

`claude-memory hook <ingest|sweep|publish|context|nudge>` reads JSON from stdin. The `nudge` subcommand was added 0.11.0.

### Stable stdin payload fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `session_id` | string | yes for `ingest`, `context`, `nudge` | Claude Code session id. |
| `transcript_path` | string | yes for `ingest` | Path to the session transcript JSONL. |
| `project_path` | string | no | Defaults to `cwd`. |
| `cwd` | string | no | Working directory. |
| `source` | string | no | Hook fresh-session source (`startup`, `resume`, `clear`, etc.). Affects `context` injector behavior. |
| `mode` | string | no | For `publish` — `shared`, `local`, `home`. |

Unknown payload fields are **ignored** rather than rejected — this lets Claude Code add new fields without breaking older gem versions.

### Stable stdout response

For `claude-memory hook context` only:

```json
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "<markdown>"}}
```

The shape and key names are stable. `additionalContext` content format (Markdown sections) is stable as listed in §6.

### Stable `activity_events.detail_json` field set

Each hook records an `activity_events` row whose `detail_json` carries telemetry. The **stable** field set per `event_type` is enumerated in [`spec/smoke/expected_fields.yml`](../spec/smoke/expected_fields.yml) — that file is the manifest, and `bin/pre-release-smoke` enforces it as a release gate.

Adding a new field to `detail_json` is a stable-surface addition (non-breaking). Removing or renaming a listed field requires a deprecation cycle. The smoke gate refuses to ship a release if any listed field is unexpectedly null.

Current covered events (0.11.0):

- `hook_context`: `context_length`, `context_tokens` (since 0.11.0), `top_fact_ids`, `fact_count`. (`observation_count`, added with the observational layer, is additive and **experimental** — not yet on the smoke-gate manifest.)
- `roi_nudge`: `n`, `used`, `pct`, `prior_count` (all since 0.11.0).

`hook_ingest`, `hook_sweep`, `hook_publish` event detail fields are currently **internal** (not on the smoke-gate manifest). Promoting them to stable is a 0.12.x or later task.

---

## 5. Public Ruby API surface

External Ruby callers (benchmark adapters, scripts, and downstream gems) may rely on these classes and methods. Default for everything else: **internal**.

### Stable classes

| Class | Public surface |
|---|---|
| `ClaudeMemory::Recall` | `#initialize(manager)`, `#query(query, limit:, scope:, intent:)`, `#query_index(...)`, `#query_semantic(...)`, return-shape: array of `{fact:, receipts:, source:}`. |
| `ClaudeMemory::Configuration` | `#initialize(env = ENV)` and instance methods returning paths/flags. **Note:** instance methods only — no class-level helpers (e.g. `Configuration.global_db_path` does not exist; use `Configuration.new.global_db_path`). |
| `ClaudeMemory::Store::StoreManager` | `#initialize(global_db_path:, project_db_path:, project_path:, env:)`, `#ensure_both!`, `#close`, `#default_store`, `#store_if_exists(scope)`, accessors `global_store`, `project_store`. |
| `ClaudeMemory::Domain::Fact` | Read-only attribute accessors and predicate methods (`active?`, `superseded?`, `rejected?`). Frozen / immutable. |
| `ClaudeMemory::Domain::Entity` | Same shape — frozen value object. Predicates: `database?`, `framework?`, etc. |
| `ClaudeMemory::Domain::Provenance` | Frozen value object; `stated?`, `inferred?` predicates. |
| `ClaudeMemory::Domain::Conflict` | Frozen value object; `open?`, `resolved?` predicates. |
| `ClaudeMemory::Deprecations` | The deprecation-warning helper itself; `.warn(name:, replacement:, removed_in:, message:)`. |
| `ClaudeMemory::VERSION` | Semver string constant. |

### Experimental

| Class | Why |
|---|---|
| `ClaudeMemory::Hook::ContextInjector` | Used by `claude-memory show` and benchmark fixtures, but its emitted_* accessors evolve as the injector is tuned. Method signatures stable; private internals not. |
| `ClaudeMemory::Distill::Extraction` | Value object the LLM-distillation path produces. Field set may grow. |
| `ClaudeMemory::Core::TokenEstimator` | Estimation heuristic may sharpen; returned counts are approximations regardless. |

### Internal (do not rely on from external code)

Everything else under `lib/claude_memory/`. Specifically:

- All of `Resolve::*` (truth maintenance internals).
- All of `Sweep::*` (maintenance internals).
- All of `Index::*` (indexing internals — `LexicalFTS`, `VectorIndex`).
- All of `Hook::Handler` and `Hook::DistillationRunner` (use the CLI hook subcommands instead).
- All of `MCP::*` except via the public MCP-tool protocol (use `claude-memory serve-mcp` and the JSON-RPC interface).
- All of `Commands::*` except via the CLI (don't call command classes directly from external Ruby).
- All of `Dashboard::*` (treat the dashboard as a black box; don't import its panel classes).
- `Distill::NullDistiller`, `Distill::ReferenceMaterialDetector`, `Distill::BareConclusionDetector` — these are pluggable internals; treat as "may change in any patch."

If you need a feature from one of the internal classes, **open an issue** so we can promote it deliberately or expose it through a stable adapter.

---

## 6. Schema & predicate vocabulary

### Schema migrations

Schema is at v20 (unreleased; v18 shipped in 0.12.0) with 20 migrations under `db/migrations/`. Migrations remain forward-compatible per the round-trip-spec convention (`feedback_round_trip_migration_specs.md`): each release's specs verify that DBs from the prior 3 schema boundaries can be migrated into the current schema without data loss.

**What's stable:**

- Existing **table names**: `content_items`, `entities`, `entity_aliases`, `facts`, `provenance`, `fact_links`, `conflicts`, `mcp_tool_calls`, `activity_events`, `moment_feedback`, `delta_cursors`, plus `content_fts` (FTS5) and `facts_vec` (sqlite-vec).
- Existing **column names** on the above tables.
- The **predicate vocabulary** in `Resolve::PredicatePolicy::POLICIES`: `convention`, `decision`, `architecture`, `reference`, `uses_framework`, `uses_language`, `uses_database`, `deployment_platform`, `auth_method`. Adding new predicates is non-breaking; renaming or removing an existing predicate requires a deprecation cycle (see `SYNONYMS` for prior canonicalizations).
- **Cardinality** of each predicate (single vs multi). Reclassifying a predicate's cardinality is a breaking change — see the 0.9.0 `uses_framework` reclassification incident for context.

**What's experimental:**

- The `vec0` virtual-table internals — sqlite-vec evolution may shift representation.
- `mcp_tool_calls` retention behavior (currently 90 days, configurable); the column set is stable, the retention default is not.
- The `observations` table (v19–v20, incl. `corroboration_count`/`promoted_at`/`promoted_fact_id`) — episodic layer. Column set may still change while the layer is experimental.

**What's internal:**

- Auxiliary FTS shadow tables (e.g. `content_fts_data`, `content_fts_idx`) — managed by SQLite, treat as opaque.
- `schema_info` / `schema_migrations` housekeeping tables — managed by Sequel::Migrator.
- Specific SQL indexes and triggers — may be added/dropped without notice as long as the user-visible columns and behaviors stay the same.

### Removing a column or predicate

Always a major-version change. Process:

1. Mark the surface deprecated via `Deprecations.warn` in the next minor.
2. Keep reading the column / accepting the predicate for ≥ 1 minor cycle.
3. Migration to drop the column ships in the major bump.

---

## 7. Database signal-health audit (since 0.12.0)

The memory database itself has stability contracts that, when violated, indicate either a regression in the distillation/resolve pipeline or contamination of the source documentation. These contracts are enforced at two layers:

### `bin/memory-audit` (runtime audit script)

Reports per-DB statistics and exits non-zero on threshold breach. Stable surface:

- Output JSON shape (`--json` flag): `{project_path, global: {active_facts, predicate_counts}, project: {active_facts, predicate_counts, open_conflicts, pending_distillation}, single_cardinality_violations, warnings, failures, ok}`.
- Exit code: `0` on `failures.empty?`, `1` otherwise. `--no-exit` always returns 0 (informational mode).

Run before tagging a release; wire into CI on the project's own DB to catch in-conversation contamination.

### `spec/benchmarks/health/database_signal_spec.rb`

`:benchmark`-tagged RSpec suite that codifies the contracts:

1. Zero open conflicts in both stores.
2. At most one active fact per single-cardinality predicate (`uses_database`, `deployment_platform`, `auth_method`).
3. `memory.conventions` returns at least one project-scope fact when project conventions exist (regression guard against the pre-0.12 global-only filter).
4. `memory.decisions` returns only `decision`-predicate facts (no `uses_*` leakage).
5. `memory.architecture` returns only predicates in `Shortcuts::SHORTCUTS[:architecture][:predicates]`.
6. Distillation backlog < 100 (hard fail) / < 25 (warning).
7. Project active facts ≥ 5 (sanity floor — catches over-aggressive rejection).

Run via `bundle exec rspec spec/benchmarks/health/ --tag benchmark`. The
spec is **local-only** — `.claude/memory.sqlite3` is git-lfs tracked and CI
checkout doesn't pull LFS objects, so the spec auto-skips on CI when it
detects the unresolved pointer. Run it locally after `git lfs pull` to
validate signal contracts before tagging a release.

---

## 7. What is explicitly NOT public

Listed here for honesty — these surfaces look public but are not.

- **Dashboard JSON HTTP API.** The `claude-memory dashboard` server's endpoints are an internal interface for the bundled UI. Don't build scripts against `GET /api/trust` etc. — endpoints, response shapes, and even URL paths may change without notice.
- **`activity_events.detail_json` fields not in `spec/smoke/expected_fields.yml`.** Inspecting a missing field during debugging is fine; relying on it in scripts is not.
- **The exact text of `additionalContext`.** The Markdown sections (`## Decisions`, `## Conventions`, `## Architecture`, `## Pending Knowledge Extraction`, `## Auto-Memory Mirror`) and their order are stable; the per-fact rendering format inside each section is tuned for prompt quality and may change. The `## Observations` and `## Observation Reflection` sections (observational layer) and the published `.claude/rules/claude_memory.observations.md` snapshot are **experimental** while the layer is built out.
- **Internal env vars** (anything not listed in `Configuration` instance methods or in this doc). Examples that exist but are internal: `CLAUDE_MEMORY_LOG_LEVEL`, debug flags surfaced during development.
- **Test/spec/fixture infrastructure.** `spec/benchmarks/`, `spec/evals/`, `spec/support/` are not public APIs.
- **Plugin-format paths.** `.claude-plugin/`, `scripts/serve-mcp.sh`, etc. are part of the Claude Code plugin format integration; treat them as opaque.

---

## 8. Reporting a stability concern

If you depended on a surface that changed without a deprecation cycle, file an issue at [github.com/codenamev/claude_memory/issues](https://github.com/codenamev/claude_memory/issues) with:

1. The surface (class, method, flag, tool, field).
2. The version it worked in and the version that broke.
3. The use case (so we can decide whether to revert or add a stable replacement).

Surfaces listed here as **stable** that broke without warning are bugs and will be fixed in a patch release. Surfaces listed as **internal** or **experimental** may or may not be fixed — we'll triage based on reach.

---

*This doc is the contract; `lib/claude_memory/commands/registry.rb`, `lib/claude_memory/mcp/tool_definitions.rb`, `lib/claude_memory/resolve/predicate_policy.rb`, and `spec/smoke/expected_fields.yml` are the implementation. When they disagree, the manifest files in code are authoritative — but disagreement is itself a bug; keep them in sync.*
