# Code Quality Review - Ruby Best Practices

**Review Date:** 2026-04-22
**Previous Review:** 2026-03-19
**Codebase Growth:** 12,239 → 17,014 LOC (+4,775, +39%)

---

## Executive Summary

The codebase has grown ~39% in five weeks, driven primarily by three additions:

1. **Dashboard subsystem** (new, ~1,247 LOC across 5 files) — JSON API, WEBrick server, conflict helpers, fact presenter, efficacy scoring
2. **SQLiteStore regrowth** (386 → 683 LOC) — table accessors re-added, LLM cache methods, ingestion metric aggregation
3. **MCP/command expansion** — new handlers, new command variants, expanded tool definitions

Two files now exceed the 500-line threshold (up from 0 in March). The test-to-code ratio dropped from 1.84:1 to 1.65:1 as tests didn't keep pace with library growth. Three dashboard modules (`conflicts.rb`, `fact_presenter.rb`, `server.rb`) shipped without direct specs, though `api_spec.rb` exercises them transitively through API responses.

No new correctness bugs. No hot-path N+1 patterns. All bare rescues are defensive/optional (return `false` or `nil` in boolean or skip contexts). No new raw SQL outside of FTS5/vec0 DDL and schema introspection.

**Resolved since last review:** None of the 12 carried-forward items were addressed. All are still non-critical (thin CLI wrappers, DRY tweaks, test ergonomics).

**New this review:** 5 medium-priority items tied to the dashboard and SQLiteStore regrowth. 3 low-priority items for test coverage gaps.

### Current Strengths

- Functional core: 25+ pure logic classes with zero I/O
- Dashboard architecture is sound — `API` delegates to `Conflicts`, `FactPresenter`, `Efficacy` rather than becoming a god object
- Domain objects remain frozen and self-validating (Fact, Entity, Provenance, Conflict)
- 100% `frozen_string_literal: true` compliance (148 lib files)
- Zero N+1 query patterns in hot paths; dashboard uses batch `as_hash(:id)` loading
- Proper transaction wrapping in `Resolver` and `Maintenance`
- Clean duck-typed embedding provider contract with shared RSpec examples
- Handler module decomposition from March still holding (no handler >215 LOC)
- Consistent dependency injection across commands and dashboard modules

---

## 1. Sandi Metz Perspective

### What's Been Fixed ✅

Items resolved before this review (from Mar 19 session) remain in good shape:
- `Tools` god object still ~249 LOC thin dispatcher; handlers stayed focused
- `Recall` still a 94-line facade delegating to engine strategies
- `SnippetExtractor` DRY extraction still in place
- Embedding provider contract (duck typing, shared examples) unchanged

### Critical Issues 🔴

None remaining.

### High Priority Issues

#### A. SQLiteStore regrew from 386 → 683 LOC (+77%)

`lib/claude_memory/store/sqlite_store.rb` was the headline refactor of Mar 19 (from 547 down to 386). It has since regrown past its original pre-refactor size.

**Contributing additions:**
- Table accessor methods re-added (`content_items`, `entities`, `facts`, `provenance`, etc., L99-106) — probably worth keeping for clarity
- LLM cache support (`llm_cache_store`, `llm_cache_lookup`, L606-626) — new feature
- Ingestion metrics aggregation (`aggregate_ingestion_metrics`, L532-562, 30 lines) — new feature
- Backfill distillation metrics (`backfill_distillation_metrics!`, L567, 20 lines) — new feature
- `reject_fact` (L366, 24 lines) — was CLI, moved into store

**Method sizes >15 lines:**

| Method | L | Size | Notes |
|---|---|---|---|
| `aggregate_ingestion_metrics` | 532 | 30 | Multiple sub-queries + merge |
| `upsert_content_item` | 149 | 26 | 11 keyword params (carried-forward #8) |
| `reject_fact` | 366 | 24 | Conflict resolution in transaction |
| `insert_fact` | 288 | 21 | Many optional fields |
| `llm_cache_store` | 606 | 20 | Insert + read-back |
| `backfill_distillation_metrics!` | 567 | 20 | Aggregation orchestration |
| `update_fact` | 329 | 18 | Generic update via allowed-keys |

**Proposed fix:** Extract a `MetricsAggregator` or `LLMCache` module to be included, mirroring the successful `RetryHandler` + `SchemaManager` pattern. This is the project's own convention for breaking up this class without breaking its API.

**File:** `lib/claude_memory/store/sqlite_store.rb` (683 lines)
**Effort:** 1–1.5 hours

#### B. Dashboard::API at 627 lines with multiple 20+ line methods

`lib/claude_memory/dashboard/api.rb` is new (not in March review). Architecturally clean (delegates to `Conflicts`, `FactPresenter`, `Efficacy`), but the API itself has accumulated orchestration code.

**Method sizes >15 lines (verified):**

| Method | L | Size | Concern |
|---|---|---|---|
| `recall` | 186 | 39 | Query construction + dual-shape result flattening |
| `timeline` | 302 | 29 | Activity event formatting |
| `session_summary` | 85 | 28 | Multi-query aggregation |
| `db_stats` | 467 | 27 | Predicate counts + entity counts + size stats |
| `facts` | 242 | 26 | Pagination + filtering + presenter dispatch |
| `efficacy` | 270 | 23 | Score computation delegated but wrapping is thick |
| `activity_detail` | 115 | 22 | Event detail shape construction |
| `load_content_item` | 423 | 20 | Joined fetch + shape |

**Proposed fix:** Extract query-construction helpers into a `Dashboard::QueryBuilder` or per-endpoint command objects. Example: a `Dashboard::RecallQuery.new(manager, params).call` would reduce `recall` to ~5 lines and be unit-testable without HTTP plumbing.

**File:** `lib/claude_memory/dashboard/api.rb` (627 lines)
**Effort:** 2–3 hours (5 methods to extract)

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 8 | `upsert_content_item` has 11 keyword params (carried) | `store/sqlite_store.rb:149-174` | 1 hour |
| 26 | `publish.rb` section generators still repeat structure | `publish.rb:114-165` | 30 min |

Convention: `generate_decisions_section`, `generate_conventions_section`, `generate_constraints_section`, `generate_additional_section` all share: `select predicate`, `return "" if empty`, `build header`, `append lines`, `join`. Could be:

```ruby
def generate_section(facts, section:, title:, formatter:)
  rows = facts.select { |f| PredicatePolicy.section_for(f[:predicate]) == section }
  return "" if rows.empty?
  (["## #{title}\n"] + rows.map(&formatter)).join("\n") + "\n"
end
```

---

## 2. Jeremy Evans Perspective

### What's Been Fixed ✅

- Batch loading in `FactPresenter#list_summary` (L59-63): single `where(id: ids).as_hash(:id)` call
- Transaction wrapping preserved in `Maintenance#restore_multi_value_supersessions` (L205)
- Dashboard reuses tested `Recall` engine rather than issuing its own queries (`api.rb:199`)

### Raw SQL Audit

All production raw SQL remains justified:

| Location | Pattern | Verdict |
|---|---|---|
| `index/lexical_fts.rb:144-147` | `CREATE VIRTUAL TABLE ... USING fts5` | Required — Sequel has no FTS5 DDL |
| `index/vector_index.rb:176-179` | `CREATE VIRTUAL TABLE ... USING vec0` | Required — sqlite-vec DDL |
| `index/vector_index.rb:159-160` | `execute_with_params` via Extralite | Required — Sequel bind params don't work with vec0 |
| `mcp/handlers/stats_handlers.rb:99` | `SELECT sql FROM sqlite_master` | Required — schema introspection |
| `commands/stats_command.rb:236` | `SELECT sql FROM sqlite_master` | Required — schema introspection |

**Verdict:** Zero inappropriate raw SQL.

### Transaction Safety

Spot-checked:
- `resolve/resolver.rb`: wraps supersession + conflict insert in `@store.db.transaction` ✅
- `sweep/maintenance.rb:205`: wraps multi-value restoration ✅
- `dashboard/conflicts.rb:84`: uses `store.reject_fact` which opens its own transaction ✅

### N+1 Audit

New dashboard code checked:
- `FactPresenter#list_summary` — batch loads all entities in one query ✅
- `dashboard/api.rb#load_linked_facts` — single join query ✅
- `dashboard/api.rb#load_facts_by_ids` — single `where(id: ids)` ✅
- `dashboard/api.rb#recall` — delegates to production `Recall` pipeline (already batched) ✅

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 8 | `upsert_content_item` 11-param signature (carried) | `store/sqlite_store.rb:149` | 1 hour |

**Fix:** `ContentItemAttributes = Data.define(:source, :text_hash, ...)` value object. Would also enable `ContentItemAttributes.from_transcript_chunk(...)` factory methods.

---

## 3. Kent Beck Perspective

### What's Been Fixed ✅

- `similarity.rb`, `metadata_extractor.rb`, `tool_extractor.rb`, `recover_command.rb`, `schema_validator.rb` specs added in March session — still green
- `dashboard/api_spec.rb` (new) tests the API surface and exercises the delegate helpers transitively

### High Priority Issues

#### C. Dashboard test coverage gaps (new subsystem)

Three of five dashboard modules ship without direct spec files:

| File | LOC | Direct Spec? | Transitive Coverage |
|---|---|---|---|
| `dashboard/api.rb` | 627 | ✅ `api_spec.rb` | N/A |
| `dashboard/efficacy.rb` | 127 | ✅ `efficacy_spec.rb` | N/A |
| `dashboard/conflicts.rb` | 195 | ❌ | Partial via `api_spec.rb` |
| `dashboard/fact_presenter.rb` | 109 | ❌ | Partial via `api_spec.rb` |
| `dashboard/server.rb` | 189 | ❌ | None (HTTP glue) |

`Conflicts` and `FactPresenter` have non-trivial shape logic (provenance loading, entity batching, merge conflict handling) that deserves direct unit tests. `Server` is harder to test (WEBrick mounting), but at minimum routing configuration could be tested.

**Effort:**
- `fact_presenter_spec.rb` — 45 min
- `conflicts_spec.rb` — 1 hour
- `server_spec.rb` — 1–1.5 hours

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 10 | Sleep-based tests (~4s total) | `spec/ingest/ingester_spec.rb:43,65,81`, `spec/publish_spec.rb:222` | 1 hour |
| 11 | No shared test factory | `spec/spec_helper.rb` | 1 hour |

Both carried forward unchanged.

---

## 4. Avdi Grimm Perspective

### What's Been Fixed ✅

- `Core::Result` still used consistently in embedding paths
- `ApiError < StandardError` intact
- Resolver still parameter-threaded; no rediscovered mutable state

### Bare Rescue Audit (5 total, all defensive)

Every bare `rescue` in production code returns a safe default:

| Location | Context | Returns | Verdict |
|---|---|---|---|
| `mcp/handlers/stats_handlers.rb:102` | `fts_legacy?` introspection | `false` | Acceptable — boolean check |
| `mcp/instructions_builder.rb:147` | `vec_available?` probe | `false` | Acceptable — capability check |
| `sweep/maintenance.rb:140` | FTS entry remove in prune loop | skips row | Acceptable — prune-best-effort |
| `commands/hook_command.rb:102` | Forked background handler | `nil` | Required — must not escape fork |
| `commands/stats_command.rb:239` | `check_fts_format` helper | no-op | Acceptable — informational only |

**Recommendation:** Add `rescue StandardError` explicitly to silence the only remaining lint concern (bare rescues catch `StandardError` in Ruby anyway, so this is purely stylistic). Or add a brief `# bare rescue: informational only` comment documenting intent.

**Effort:** 10 minutes total; zero functional change.

### Carried-Forward Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 13 | Inconsistent payload validation | `hook/handler.rb:53-82` | 30 min |

Verified still present: `ingest` uses `payload.fetch("session_id")` (raises on missing), `sweep` uses `payload.fetch("budget", DEFAULT_SWEEP_BUDGET)`, `publish` uses `payload.fetch("mode", "shared")`, `context` uses `payload["source"]` (nil-allows). No consistent pattern.

---

## 5. Gary Bernhardt Perspective

### What's Been Fixed ✅

- Dashboard keeps WEBrick I/O isolated to `Dashboard::Server` (functional core/imperative shell separation)
- Dashboard `API` methods are pure transformations over store queries — return hashes, don't mutate
- Dashboard helpers (`Conflicts`, `FactPresenter`, `Efficacy`) receive dependencies via constructor
- `VectorIndex#clear!` still encapsulates vec0 destruction

### Current Boundaries

Dashboard layering is textbook functional-core/imperative-shell:

```
HTTP layer:    Dashboard::Server (WEBrick mount_proc)      ← imperative shell
JSON layer:    Dashboard::API (query → hash transformation) ← functional
Query layer:   Recall engine + store datasets              ← impure but isolated
Presentation:  FactPresenter, Conflicts, Efficacy          ← pure transformations
```

### Carried-Forward Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 15 | Sweeper mutable state | `sweep/sweeper.rb:16-17` | 20 min |
| 16 | `Dir.chdir` in publish tests | `spec/publish_spec.rb:14` | 15 min |

Both unchanged from March.

---

## 6. General Ruby Idioms

### Carried-Forward Items

| # | Issue | File:Line | Severity | Effort |
|---|---|---|---|---|
| 17 | ResponseFormatter duplication | `mcp/response_formatter.rb:27-280` | 🟡 Medium | 1 hour |
| 18 | Publish section generator repetition | `publish.rb:114-165` | 🟢 Low | 30 min |

Reviewed: `ResponseFormatter` has been split into ~12 focused static methods; further DRY extraction is possible but has diminishing return. Publish section generators are still textually repetitive (4 near-identical methods). Low priority.

### New Items

| # | Issue | File:Line | Severity | Effort |
|---|---|---|---|---|
| 27 | SQLiteStore regrowth past 500 LOC | `store/sqlite_store.rb` | 🟡 Medium | 1–1.5 hour |
| 28 | Dashboard::API recall/timeline/db_stats methods >20 lines | `dashboard/api.rb:186,302,467` | 🟡 Medium | 2–3 hours |
| 29 | Dashboard untested modules (conflicts, fact_presenter, server) | `spec/claude_memory/dashboard/` | 🟡 Medium | 3 hours |
| 30 | Bare rescue style (prefer explicit StandardError) | 5 locations | 🟢 Low | 10 min |

---

## 7. Positive Observations

- **Dashboard architecture is exemplary** — when a 1,247-LOC feature lands without creating any god objects or introducing any N+1 patterns, that's a healthy codebase
- **`FactPresenter` batch loading** (`list_summary` L59-63) is a reusable pattern: `flat_map` + `uniq` + single `where(id:)` + `as_hash(:id)` lookup — better than N+1 in a presenter loop
- **Delegation pattern in `API#conflicts`, `API#reject_fact`** — API doesn't know how conflicts are stored, it just asks `Conflicts` helper. Proper tell-don't-ask
- **Transaction safety preserved** through the regrowth — new `reject_fact`, `llm_cache_store`, and aggregation methods all use proper transactions
- **Handler module decomposition from March held** — no handler has regrown past 215 LOC despite the codebase growing 39%
- **Zero new correctness bugs** across a 39% LOC expansion

---

## 8. Priority Refactoring Recommendations

### High Priority (Next Week)

| # | Item | File:Line | Effort | Impact |
|---|---|---|---|---|
| 27 | Extract `LLMCache` / `MetricsAggregator` module from SQLiteStore | `store/sqlite_store.rb` | 1–1.5 hours | Regrowth control |
| 29 | Add `fact_presenter_spec.rb` and `conflicts_spec.rb` | `spec/claude_memory/dashboard/` | 2 hours | Coverage |

### Medium Priority (Next Sprint)

| # | Item | Effort | Impact |
|---|---|---|---|
| 28 | Extract `Dashboard::RecallQuery` / `SessionSummary` / `DbStats` helpers | 2–3 hours | Readability |
| 8 | `ContentItemAttributes` value object (carried) | 1 hour | Param reduction |
| 10 | Replace sleep-based tests with mocks (carried) | 1 hour | Test speed |
| 11 | Shared test factory `spec/support/database_factory.rb` (carried) | 1 hour | DRY |
| 17 | ResponseFormatter consolidation (carried) | 1 hour | DRY |
| 29 | Add `server_spec.rb` | 1.5 hours | Coverage |

### Low Priority (Later)

| # | Item | Effort |
|---|---|---|
| 13 | Payload validator for hooks (carried) | 30 min |
| 15 | Sweeper mutable state (carried) | 20 min |
| 16 | `Dir.chdir` in tests (carried) | 15 min |
| 26/18 | Publish section builder helper (carried) | 30 min |
| 30 | Explicit `rescue StandardError` in 5 defensive rescues | 10 min |

### Carried Forward (Low Priority from Earlier Reviews)

| # | Item | Original # |
|---|---|---|
| 20 | DateTime migration (string timestamps) | Feb 4 #17 |
| 21 | Command manager helper (`with_manager`) | Feb 4 #19 |
| 22 | `release_connections` polymorphism | Feb 4 #20 |
| 23 | Provenance batch insert (`multi_insert`) | Feb 4 #22 |
| 25 | Result objects for all queries | Feb 4 #24 |

---

## 9. Conclusion

The codebase absorbed 39% LOC growth (+4,775 LOC) over five weeks without introducing any correctness bugs, N+1 patterns, or god-object regressions in new code. The dashboard subsystem is particularly well-structured — it would have been easy to put all 1,247 LOC in `api.rb`, but the author correctly split it into five collaborators.

**Two watch items emerged:**

1. `SQLiteStore` regrew past its pre-March-refactor size (386 → 683). The successful pattern from March (`RetryHandler`, `SchemaManager` module inclusion) should be reapplied to extract the new aggregation/cache concerns.
2. `Dashboard::API` is under 700 lines but has 8 methods over 15 lines. Extracting per-endpoint query objects would drop it to ~300 LOC.

**Test ratio regression** (1.84 → 1.65) is concerning mostly because of three untested dashboard modules. Not urgent — `api_spec.rb` covers them transitively — but direct coverage is warranted given the dashboard's growing surface area.

All 12 carried-forward items from March remain low-priority and non-blocking.

---

## Appendix A: Metrics Comparison

| Metric | Jan 29 | Feb 4 | Mar 9 | Mar 19 | **Apr 22** |
|---|---|---|---|---|---|
| Ruby files (lib) | ~85 | 104 | 112 | 117 | **148** |
| LOC (lib) | ~8,000 | 9,982 | 11,392 | 12,239 | **17,014** |
| LOC (spec) | — | 17,693 | 21,632 | 22,563 | **28,074** |
| Pure logic classes | 17+ | 20+ | 20+ | 22+ | **25+** |
| Test files | 74+ | 98 | 128 | 122 | **154** |
| Test-to-code ratio | ~1.5:1 | 1.77:1 | 1.90:1 | 1.84:1 | **1.65:1** ⬇️ |
| Files >500 lines | 0 | 2 | 3 | **0** | **2** ⬆️ |
| Files >300 lines | — | — | 9 | 9 | **10** |
| Bare rescues (unsafe) | 0 | 0 | 1 | 0 | **0** ✅ |
| Bare rescues (defensive, justified) | — | — | — | — | **5** |
| N+1 patterns (hot paths) | 0 | 0 | 0 | 0 | **0** ✅ |
| Untested dashboard modules | — | — | — | — | **3 of 5** ⚠️ |
| Known correctness bugs | — | — | — | 0 | **0** ✅ |

## Appendix B: File Size Report

| File | Mar 19 | **Apr 22** | Trend |
|---|---|---|---|
| `store/sqlite_store.rb` | 386 | **683** | ⬆️ +297 (regrowth — needs extraction) |
| `dashboard/api.rb` | — | **627** | 🆕 new subsystem |
| `mcp/tool_definitions.rb` | 334 | **459** | ⬆️ +125 (new tool schemas) |
| `mcp/response_formatter.rb` | 396 | **397** | — |
| `recall/query_core.rb` | 357 | **371** | ⬆️ +14 |
| `commands/stats_command.rb` | 250 | **346** | ⬆️ +96 |
| `sweep/maintenance.rb` | — | **334** | 🆕 to watch list |
| `mcp/text_summary.rb` | 258 | **313** | ⬆️ +55 |
| `commands/index_command.rb` | 272 | **259** | ⬇️ -13 |
| `publish.rb` | 221 | **256** | ⬆️ +35 |
| `resolve/resolver.rb` | 195 | **254** | ⬆️ +59 |
| `mcp/tools.rb` | 104 | **249** | ⬆️ +145 (handler dispatch growth) |
| `commands/uninstall_command.rb` | 226 | **226** | — |
| `store/store_manager.rb` | — | **215** | 🆕 to watch list |
| `infrastructure/schema_validator.rb` | 215 | **215** | — |
| `commands/hook_command.rb` | 214 | **215** | ⬆️ +1 |
| `hook/context_injector.rb` | — | **214** | 🆕 to watch list |
| `mcp/handlers/setup_handlers.rb` | 211 | **211** | — |
| `mcp/server.rb` | — | **206** | 🆕 |
| `mcp/handlers/stats_handlers.rb` | — | **205** | 🆕 |
| `dashboard/conflicts.rb` | — | **195** | 🆕 (untested) |
| `dashboard/server.rb` | — | **189** | 🆕 (untested) |
| `index/vector_index.rb` | 184 | **184** | — |
| `recall.rb` | 94 | **175** | ⬆️ +81 |
| `dashboard/efficacy.rb` | — | **127** | 🆕 |
| `dashboard/fact_presenter.rb` | — | **109** | 🆕 (untested) |

## Appendix C: Methods > 15 Lines in Watch-List Files

### `dashboard/api.rb`

| Method | Line | Size |
|---|---|---|
| `recall` | 186 | 39 |
| `timeline` | 302 | 29 |
| `session_summary` | 85 | 28 |
| `db_stats` | 467 | 27 |
| `facts` | 242 | 26 |
| `efficacy` | 270 | 23 |
| `activity_detail` | 115 | 22 |
| `load_content_item` | 423 | 20 |
| `activity` | 48 | 19 |
| `serialize_recall_fact` | 365 | 18 |
| `collect_configured_hook_types` | 559 | 18 |

### `store/sqlite_store.rb`

| Method | Line | Size |
|---|---|---|
| `aggregate_ingestion_metrics` | 532 | 30 |
| `upsert_content_item` | 149 | 26 |
| `reject_fact` | 366 | 24 |
| `insert_fact` | 288 | 21 |
| `llm_cache_store` | 606 | 20 |
| `backfill_distillation_metrics!` | 567 | 20 |
| `update_fact` | 329 | 18 |

---

**Next review:** After `SQLiteStore` module extraction or `Dashboard::API` query-object refactor.
