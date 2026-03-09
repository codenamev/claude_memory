# Code Quality Review - Ruby Best Practices

**Review Date:** 2026-03-09
**Previous Review:** 2026-02-04
**Last Quality Update:** 2026-02-04 (21/24 items completed)

---

## Executive Summary

The codebase has grown from 9,982 to 11,392 LOC since the Feb 4 review. Core architecture remains solid — functional core, proper layering, zero bare rescues, zero N+1 queries in hot paths. The 3 files on the previous watch list have all grown: `tools.rb` (610→728), `recall.rb` (608→681), `sqlite_store.rb` (481→547). All three now exceed 500 lines.

**New issues found:** 18 items (2 critical, 4 high, 7 medium, 5 low)
**Carried forward:** 9 items from previous review (1 medium, 8 low)
**Total remaining:** 27 items

### Current Strengths

- Functional core: 20+ pure logic classes with zero I/O
- Domain objects: properly frozen and self-validating
- Null object pattern: NullFact, NullExplanation
- Result monad: Core::Result for Success/Failure
- 100% frozen_string_literal compliance (112 files)
- 1.90:1 test-to-code ratio (21,632 spec : 11,392 lib)
- Zero bare rescues in hot paths, zero N+1 in query paths
- Well-structured batch loading via FactQueryBuilder

---

## 1. Sandi Metz Perspective

### What's Been Fixed ✅
- N+1 queries eliminated in prior review
- Long methods decomposed (resolve_fact, detailed_stats, check_setup)
- Classes extracted (SchemaValidator, OperationTracker)

### Critical Issues 🔴

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 1 | **Tools god object (728 lines, 48 methods)** | `mcp/tools.rb:1-728` | 2-3 days |

The `Tools` class handles all 21 MCP tool implementations in a single file. The `call` dispatcher (lines 29-76) is a 21-branch case statement. Each handler mixes parameter extraction, domain logic, and response formatting. Individual tool handlers like `store_extraction` (lines 221-262, 41 lines) and `discover_other_projects` (lines 565-614, 50 lines) violate the 15-line method limit.

**Fix:** Extract each tool handler into its own class (e.g., `RecallHandler`, `StoreExtractionHandler`) with a common interface, registered via a handler registry.

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 2 | **Recall class too large (681 lines, 74 methods)** | `recall.rb:1-681` | 2 days |

Every public method branches on `@legacy_mode` with parallel `_legacy` / `_dual` implementations (lines 42-56, 58-66, etc.). ~150+ lines of duplicated branching logic. The class has 74 methods — far beyond single responsibility.

**Fix:** Extract `LegacyQueryEngine` and `DualQueryEngine` classes implementing a common `QueryEngine` interface. Inject the appropriate engine at initialization based on `store_or_manager` type.

### High Priority Issues

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 3 | **ExportCommand N+1 queries** | `commands/export_command.rb:83-85` | 30 min |

Inside the `collect_from_store` loop, each fact triggers 2 individual queries — one for the subject entity (line 84) and one for provenance records (line 85). With 100+ facts this becomes 200+ queries.

```ruby
# Current (N+1):
facts_ds.each do |fact|
  subject = store.entities.where(id: fact[:subject_entity_id]).first
  receipts = store.provenance.where(fact_id: fact[:id]).all
end

# Fix (batch):
all_facts = facts_ds.all
entity_ids = all_facts.map { |f| f[:subject_entity_id] }.compact.uniq
entities_by_id = store.entities.where(id: entity_ids).all
  .each_with_object({}) { |e, h| h[e[:id]] = e }
fact_ids = all_facts.map { |f| f[:id] }
provenance_by_fact = store.provenance.where(fact_id: fact_ids).all
  .group_by { |p| p[:fact_id] }
```

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 4 | **SQLiteStore exceeds 500 lines (547)** | `store/sqlite_store.rb:1-547` | 1 day |

The file combines database connection, retry logic, schema management, migrations, and all CRUD operations. Schema migrations alone account for ~100 lines.

**Fix:** Extract `SchemaManager` module for migration methods, and consider a `RetryHandler` module for retry logic (lines 24-60).

---

## 2. Jeremy Evans Perspective

### What's Been Fixed ✅
- Batch queries in Recall pipeline (FactQueryBuilder)
- Transaction wrapping in Resolver
- Proper Sequel DSL usage throughout

### Critical Issues 🔴

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 5 | **Bare rescue in discover_other_projects** | `mcp/tools.rb:607` | 10 min |

```ruby
rescue => _e
  entry[:error] = "Could not read database"
end
```

This catches *all* exceptions including `NoMemoryError`, `SystemExit`, `Interrupt`. Should use specific exception types.

**Fix:** `rescue Sequel::DatabaseError, Extralite::Error, IOError => _e`

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 6 | **Transaction boundary mismatch in promote_fact** | `store/store_manager.rb:89-124` | 30 min |

The transaction wraps `@global_store.db.transaction` but `copy_provenance` (line 121) reads from `@project_store` inside the global transaction. If `@project_store` fails mid-read after global writes, the global transaction still commits (autocommit on the project side). Not a data loss risk but a consistency concern.

**Fix:** Read all provenance records from project store *before* the global transaction:

```ruby
provenance_records = @project_store.provenance.where(fact_id: fact_id).all
@global_store.db.transaction do
  # ... create entities and fact ...
  provenance_records.each { |prov| @global_store.insert_provenance(...) }
end
```

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 7 | **Provenance insert with nil content_item_id** | `store/store_manager.rb:133` | 20 min |

`copy_provenance` passes `content_item_id: nil` when promoting facts. If `insert_provenance` in SQLiteStore validates this field, it will fail silently or raise. The Domain `Provenance` class validates non-nil `content_item_id`.

**Fix:** Use a sentinel value like `"promoted"` or make `content_item_id` nullable in the provenance domain model for promoted facts.

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 8 | **upsert_content_item has 11 keyword parameters** | `store/sqlite_store.rb:158-184` | 1 hour |

Exceeds the 5-parameter guideline significantly. Suggests the method is doing too much.

**Fix:** Introduce a `ContentItemAttributes` value object:

```ruby
attrs = ContentItemAttributes.new(source:, session_id:, text_hash:, byte_len:, ...)
store.upsert_content_item(attrs)
```

---

## 3. Kent Beck Perspective

### What's Been Fixed ✅
- Test-to-code ratio improved to 1.90:1
- Clear boundaries between layers

### High Priority Issues

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 9 | **16 lib files without tests** | Multiple | 2-3 days |

Critical untested files:
- `embeddings/generator.rb` (161 lines of math/algorithm code)
- `embeddings/similarity.rb`
- `embeddings/fastembed_adapter.rb`
- `commands/stats_command.rb` (239 lines)
- `commands/export_command.rb` (108 lines)
- `commands/recover_command.rb` (75 lines)
- `infrastructure/schema_validator.rb` (215 lines)
- `ingest/metadata_extractor.rb`, `ingest/tool_extractor.rb`

Database migrations 8-11 also lack migration-specific tests.

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 10 | **Sleep-based tests add 4+ seconds** | `spec/ingest/ingester_spec.rb:43,65,81` | 1 hour |

Three `sleep 1.01` calls wait for filesystem mtime changes. `publish_spec.rb:189` has `sleep 1.1`.

**Fix:** Mock `File.mtime` or inject a time provider instead of real sleeps.

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 11 | **No shared test factory** | `spec/spec_helper.rb` | 1 hour |

`spec_helper.rb` is only 21 lines. ~20 test files independently define `create_fact` and `create_content_with_fact` helpers. The canonical pattern from `tools_spec.rb:275` should be extracted.

**Fix:** Create `spec/support/database_factory.rb` with shared helpers, require from spec_helper.

---

## 4. Avdi Grimm Perspective

### What's Been Fixed ✅
- Null objects used properly (NullFact, NullExplanation)
- Result monad for Success/Failure
- Domain objects frozen and self-validating

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 12 | **Resolver mutable state after init** | `resolve/resolver.rb:12-13` | 30 min |

`@current_project_path` and `@current_scope` are set in `apply()` (line 12-13) rather than threaded as parameters through the method chain. This makes the Resolver stateful between calls.

**Fix:** Pass `project_path` and `scope` as explicit parameters to `resolve_fact`, `create_conflict`, etc.

*(Carried forward from previous review as #16)*

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 13 | **Inconsistent payload validation in hooks** | `hook/handler.rb:17-53` | 30 min |

`ingest` uses `.fetch("field")` with fallback, `sweep` uses `.fetch("budget", default)`, `publish` uses `.fetch("mode", "shared")`. No consistent schema validation pattern.

**Fix:** Create a `PayloadValidator` or use a simple schema hash to validate required/optional fields uniformly.

---

## 5. Gary Bernhardt Perspective

### What's Been Fixed ✅
- Strong functional core / imperative shell separation
- Value objects (FactId, SessionId, TranscriptPath) are immutable
- Pure logic in FactRanker, ConceptRanker, SnippetExtractor

### High Priority Issues

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 14 | **I/O mixed with logic in discover_other_projects** | `mcp/tools.rb:565-614` | 1 hour |

This method performs: SQL queries (lines 572-590), filesystem checks (line 598: `File.exist?`), database connections in a loop (lines 602-606), and error handling. Pure imperative shell with no separation.

**Fix:** Extract database discovery to a pure function that returns paths, and filesystem/DB checks to an imperative wrapper.

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 15 | **Sweeper mutable state** | `sweep/sweeper.rb:16-17` | 20 min |

*(Carried forward from previous review as #21)*

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 16 | **Dir.chdir in publish tests** | `spec/publish_spec.rb:14` | 15 min |

Tests use `Dir.chdir(test_dir)` which modifies global state. Fragile if tests ever run in parallel.

**Fix:** Use `Dir.chdir(test_dir) { ... }` block form or inject working directory.

---

## 6. General Ruby Idioms

| # | Issue | File:Line | Severity | Effort |
|---|-------|-----------|----------|--------|
| 17 | **ResponseFormatter duplication** | `mcp/response_formatter.rb:27-280` | 🟡 Medium | 1 hour |
| 18 | **Publish section generator repetition** | `publish.rb:100-154` | Low | 30 min |
| 19 | **SnippetExtractor validation duplication** | `core/snippet_extractor.rb:18-31` | Low | 10 min |

`ResponseFormatter` has 4 nearly identical `format_*_fact` methods (`format_recall_fact`, `format_semantic_fact`, `format_concept_fact`, etc.) sharing ~80% of code. Extract a base `format_fact` method with field selection.

`Publish` has 4 similar section generators (decisions, conventions, constraints, conflicts) each filtering facts by predicate and building markdown. Extract a `SectionBuilder`.

---

## 7. Positive Observations

- **Batch loading architecture**: `FactQueryBuilder` and `BatchLoader` eliminate N+1 patterns in all hot query paths
- **Consistent dependency injection**: All commands accept `stdout`, `stderr`, `stdin` for testability
- **Clean module boundaries**: Each module has clear responsibilities with minimal cross-coupling
- **Proper Sequel usage**: Datasets used consistently, raw SQL avoided almost entirely
- **Excellent domain modeling**: Fact, Entity, Provenance are immutable value objects with validation
- **Good file organization**: ~1 class per file, consistent naming, clear module nesting
- **Strong test culture**: 1.90:1 test-to-code ratio, behavior-focused tests
- **Infrastructure abstractions**: `FileSystem`, `InMemoryFileSystem` enable fast tests
- **Core::Result monad**: Consistent Success/Failure pattern throughout

---

## 8. Priority Refactoring Recommendations

### Critical (This Week)
| # | Item | Effort | Impact |
|---|------|--------|--------|
| 5 | Fix bare rescue in `discover_other_projects` | 10 min | Correctness |
| 3 | Fix ExportCommand N+1 queries | 30 min | Performance |

### High Priority (Next Week)
| # | Item | Effort | Impact |
|---|------|--------|--------|
| 1 | Extract Tools into handler classes | 2-3 days | Maintainability |
| 2 | Extract Recall legacy/dual into strategy | 2 days | Maintainability |
| 9 | Add tests for untested critical files | 2-3 days | Coverage |
| 4 | Extract SQLiteStore schema/retry modules | 1 day | Maintainability |

### Medium Priority (Next Sprint)
| # | Item | Effort | Impact |
|---|------|--------|--------|
| 6 | Fix promote_fact transaction boundary | 30 min | Consistency |
| 7 | Fix provenance nil content_item_id | 20 min | Correctness |
| 8 | ContentItemAttributes value object | 1 hour | Readability |
| 10 | Replace sleep-based tests with mocks | 1 hour | Test speed |
| 11 | Shared test factory | 1 hour | DRY |
| 12 | Thread Resolver state as params | 30 min | Immutability |
| 17 | ResponseFormatter base method | 1 hour | DRY |
| 14 | Separate I/O in discover_other_projects | 1 hour | Boundaries |

### Low Priority (Later)
| # | Item | Effort | Impact |
|---|------|--------|--------|
| 13 | Payload validator for hooks | 30 min | Consistency |
| 15 | Sweeper mutable state | 20 min | Immutability |
| 16 | Dir.chdir in tests | 15 min | Test isolation |
| 18 | Publish section builder | 30 min | DRY |
| 19 | SnippetExtractor validation DRY | 10 min | DRY |

### Carried Forward (Low Priority from Feb 4)
| # | Item | Original # |
|---|------|-----------|
| 20 | DateTime migration (string timestamps) | #17 |
| 21 | Command manager helper (`with_manager`) | #19 |
| 22 | release_connections polymorphism | #20 |
| 23 | Provenance batch insert (`multi_insert`) | #22 |
| 24 | Individual MCP tool classes | #23 (subsumed by #1) |
| 25 | Result objects for all queries | #24 |

---

## 9. Conclusion

The codebase maintains its strong architectural foundation but the three largest files have continued growing and now all exceed 500 lines. The most impactful improvements are: (1) fixing the bare rescue and N+1 in export (quick wins), (2) splitting `Tools` and `Recall` into focused classes (structural), and (3) adding tests for the 16 untested files (coverage).

No correctness regressions found. The batch loading patterns, domain modeling, and test culture remain excellent. The main risk is the growing complexity of `tools.rb` and `recall.rb` making future changes harder.

---

## Appendix A: Metrics Comparison

| Metric | Jan 29 | Feb 4 | Mar 9 |
|--------|--------|-------|-------|
| Ruby files (lib) | ~85 | 104 | 112 |
| LOC (lib) | ~8,000 | 9,982 | 11,392 |
| LOC (spec) | — | 17,693 | 21,632 |
| Pure logic classes | 17+ | 20+ | 20+ |
| Test files | 74+ | 98 | 128 |
| Test-to-code ratio | ~1.5:1 | 1.77:1 | 1.90:1 |
| Files >500 lines | 0 | 2 | **3** 🔴 |
| Bare rescues | 0 | 0 | **1** 🔴 |
| N+1 patterns (hot paths) | 0 | 0 | 0 ✅ |
| N+1 patterns (cold paths) | — | — | **1** 🟡 |
| Untested lib files | — | — | **16** 🟡 |

## Appendix B: Quick Wins

These can be done immediately (< 30 min total):

1. **Fix bare rescue** (`mcp/tools.rb:607`): Change `rescue => _e` to `rescue Sequel::DatabaseError, Extralite::Error, IOError => _e`
2. **SnippetExtractor DRY** (`core/snippet_extractor.rb:18-31`): Extract shared validation to private method
3. **Dir.chdir block form** (`spec/publish_spec.rb:14`): Use `Dir.chdir(dir) { ... }` instead of global chdir

## Appendix C: File Size Report

| File | Feb 4 | Mar 9 | Trend |
|------|-------|-------|-------|
| `mcp/tools.rb` | ~610 | 728 | ⬆️ +118 |
| `recall.rb` | ~608 | 681 | ⬆️ +73 |
| `store/sqlite_store.rb` | 481 | 547 | ⬆️ +66 |
| `mcp/response_formatter.rb` | — | 394 | new to watch |
| `mcp/tool_definitions.rb` | — | 303 | new to watch |
| `mcp/text_summary.rb` | — | 257 | new to watch |
| `commands/stats_command.rb` | — | 239 | — |
| `commands/uninstall_command.rb` | — | 226 | — |
| `commands/index_command.rb` | — | 224 | — |
| `publish.rb` | — | 221 | — |
| `infrastructure/schema_validator.rb` | — | 215 | — |
| `commands/hook_command.rb` | — | 214 | — |

---

**Next review:** After Tools extraction or Recall strategy pattern refactoring
