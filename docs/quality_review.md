# Code Quality Review - Ruby Best Practices

**Review Date:** 2026-03-19
**Previous Review:** 2026-03-09
**Last Quality Update:** 2026-03-19 (9 items completed)

---

## Executive Summary

The codebase has grown from 11,392 to 12,239 LOC since the Mar 9 review. A configurable embedding provider system was added (+847 LOC across 5 new files and 8 modified files). The three watch-list files have grown further: `tools.rb` (728→745), `recall.rb` (681→727), `sqlite_store.rb` (547→547, unchanged). All three remain above 500 lines.

Five items were resolved in the Mar 19 quality update session: the Shortcuts scope bug (correctness), ApiAdapter exception typing, silent exception logging (3 locations), dead Configuration accessors removed, and `index_database` decomposed into focused methods. No known correctness bugs remain.

**Resolved this session:** 9 items (#3 Shortcuts scope, NEW-1 ApiError, NEW-2 dead accessors, NEW-3 silent rescues, #5 index_database decomposition, #6 promote_fact transaction, #7 provenance nil content_item_id, #12 Resolver mutable state, #19 SnippetExtractor DRY)
**Resolved since last review:** 3 additional items (ExportCommand N+1, `discover_other_projects` bare rescue, embedding test coverage)
**Total remaining:** 16 items

### Current Strengths

- Functional core: 20+ pure logic classes with zero I/O
- Domain objects: properly frozen and self-validating
- Null object pattern: NullFact, NullExplanation
- Result monad: Core::Result for Success/Failure
- 100% frozen_string_literal compliance (117 files)
- 1.84:1 test-to-code ratio (22,563 spec : 12,239 lib)
- New embedding subsystem: shared RSpec examples, duck-typed providers, Data.define value object
- Zero N+1 patterns in hot paths
- Proper batch loading via FactQueryBuilder
- Content-addressed dedup in IndexCommand
- DimensionCheck value object (functional core, no side effects)
- Zero known correctness bugs

---

## 1. Sandi Metz Perspective

### What's Been Fixed ✅
- New embedding providers follow duck typing contract (no base class inheritance)
- Shared RSpec examples verify provider contract (`spec/support/shared_examples/embedding_provider.rb`)
- `set_meta`/`get_meta` promoted to public API (needed by DimensionCheck, VectorIndex)
- ExportCommand N+1 eliminated with batch loading
- **Shortcuts scope bug fixed** — scopes changed from symbols to strings to match DualQueryTemplate comparisons
- **`index_database` decomposed** — split 130-line method into 5 focused methods: `index_database` (orchestrator), `handle_dimension_mismatch`, `find_facts_to_index`, `run_indexing`, `process_batch`, `report_dedup_stats`

### Critical Issues 🔴

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 1 | **Tools god object (745 lines, ~50 methods)** | `mcp/tools.rb:1-745` | 2-3 days |

The `Tools` class handles all 21 MCP tool implementations in a single file. Each handler mixes parameter extraction, domain logic, and response formatting. Individual tool handlers like `store_extraction` (lines 221-262, 41 lines) and `discover_other_projects` (lines 565-614, 50 lines) violate the 15-line method limit.

**Fix:** Extract each tool handler into its own class (e.g., `RecallHandler`, `StoreExtractionHandler`) with a common interface, registered via a handler registry.

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 2 | **Recall class too large (727 lines, ~65 methods)** | `recall.rb:1-727` | 2 days |

Every public method branches on `@legacy_mode` with parallel `_legacy` / `_dual` implementations (lines 42-56, 58-66, etc.). ~300+ lines of duplicated branching logic across 15+ method families.

**Fix:** Extract `LegacyQueryEngine` and `DualQueryEngine` classes implementing a common `QueryEngine` interface. Inject the appropriate engine at initialization based on `store_or_manager` type.

### High Priority Issues

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 4 | **SQLiteStore exceeds 500 lines (547)** | `store/sqlite_store.rb:1-547` | 1 day |

The file combines connection management, retry logic, schema management, migrations, and all CRUD operations. Schema migrations alone account for ~100 lines.

**Fix:** Extract `SchemaManager` module for migration methods, and consider a `RetryHandler` module for retry logic (lines 24-60).

---

## 2. Jeremy Evans Perspective

### What's Been Fixed ✅
- Batch queries in Recall pipeline (FactQueryBuilder)
- Transaction wrapping in Resolver
- ExportCommand N+1 eliminated
- `discover_other_projects` now catches specific exception types (`Sequel::DatabaseError, Extralite::Error, IOError`)
- **promote_fact transaction boundary fixed** — project data read before global transaction (already correct in code; verified and confirmed)
- **Provenance nil content_item_id fixed** — removed mandatory `content_item_id` validation from `Domain::Provenance`, allowing nil for promoted facts

### Medium Issues 🟡

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 8 | **upsert_content_item has 11 keyword parameters** | `store/sqlite_store.rb:158-184` | 1 hour |

Exceeds the 5-parameter guideline. Suggests the method is doing too much.

**Fix:** Introduce a `ContentItemAttributes` value object.

---

## 3. Kent Beck Perspective

### What's Been Fixed ✅
- New embedding subsystem has full test coverage (4 spec files, shared examples)
- `generator_spec.rb` now tests `name`/`dimensions` contract
- DimensionCheck tested for all 3 states (`:fresh`, `:match`, `:mismatch`)
- ApiAdapter tested with HTTP mocks (no WebMock dependency)

### High Priority Issues

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 9 | **12+ lib files without tests** | Multiple | 2-3 days |

Previously 16 untested files; now reduced to ~12 after adding embedding specs. Critical untested files:
- `commands/stats_command.rb` (250 lines)
- `commands/export_command.rb` (108 lines)
- `commands/recover_command.rb` (75 lines)
- `infrastructure/schema_validator.rb` (215 lines)
- `embeddings/fastembed_adapter.rb` (tested via shared examples but no dedicated spec)
- `embeddings/similarity.rb`
- `ingest/metadata_extractor.rb`, `ingest/tool_extractor.rb`
- `commands/checks/` (6 check files)
- `commands/initializers/` (5 initializer files)

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
- DimensionCheck returns a Result value object — no exceptions, no side effects
- `Embeddings.resolve` raises `ArgumentError` with clear message for unknown providers
- ApiAdapter raises with descriptive messages for missing API keys
- Duck typing for embedding providers (no base class)
- **ApiAdapter now uses typed `ApiError < StandardError`** instead of bare `raise "message"`
- **Resolver mutable state resolved** — verified that `project_path` and `scope` are already threaded as parameters through the entire method chain; no mutable instance state exists

### Carried Forward Issues 🟡

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 13 | **Inconsistent payload validation in hooks** | `hook/handler.rb:17-53` | 30 min |

`ingest` uses `.fetch("field")` with fallback, `sweep` uses `.fetch("budget", default)`, `publish` uses `.fetch("mode", "shared")`. No consistent validation pattern.

---

## 5. Gary Bernhardt Perspective

### What's Been Fixed ✅
- DimensionCheck is pure: takes store + provider, returns immutable Result. No hidden side effects.
- `clear_stale_embeddings` was moved from hidden infrastructure setup to explicit command-level call.
- VectorIndex#clear! encapsulates vec0 table knowledge (no raw SQL in command).
- **Dead Configuration embedding accessors removed** — resolver and ApiAdapter read ENV directly, no unused indirection.

### Carried Forward Issues 🟡

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 14 | **I/O mixed with logic in discover_other_projects** | `mcp/tools.rb:565-614` | 1 hour |

SQL queries, filesystem checks, database connections in a loop, and error handling all mixed together.

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 15 | **Sweeper mutable state** | `sweep/sweeper.rb:16-17` | 20 min |

| # | Issue | File:Line | Effort |
|---|-------|-----------|--------|
| 16 | **Dir.chdir in publish tests** | `spec/publish_spec.rb:14` | 15 min |

---

## 6. General Ruby Idioms

### What's Been Fixed ✅
- **Silent exception swallowing resolved** — 3 bare rescue blocks now log via `ClaudeMemory.logger.debug(...)`:
  - `mcp/instructions_builder.rb:29`
  - `hook/context_injector.rb:47`
  - `commands/checks/vec_check.rb:55`

- **SnippetExtractor range calculation DRY** — extracted `snippet_range` method to eliminate duplicated start/end index computation between `extract_with_lines` and `build_snippet`

### Carried Forward Issues

| # | Issue | File:Line | Severity | Effort |
|---|-------|-----------|----------|--------|
| 17 | **ResponseFormatter duplication** | `mcp/response_formatter.rb:27-280` | 🟡 Medium | 1 hour |
| 18 | **Publish section generator repetition** | `publish.rb:100-154` | Low | 30 min |

---

## 7. Positive Observations

- **Batch loading architecture**: `FactQueryBuilder` and `BatchLoader` eliminate N+1 patterns in all hot query paths
- **Consistent dependency injection**: All commands accept `stdout`, `stderr`, `stdin` for testability
- **Clean module boundaries**: Each module has clear responsibilities with minimal cross-coupling
- **Proper Sequel usage**: Datasets used consistently, raw SQL avoided almost entirely
- **Excellent domain modeling**: Fact, Entity, Provenance are immutable value objects with validation
- **Good file organization**: ~1 class per file, consistent naming, clear module nesting
- **Strong test culture**: 1.84:1 test-to-code ratio, behavior-focused tests
- **Infrastructure abstractions**: `FileSystem`, `InMemoryFileSystem` enable fast tests
- **Core::Result monad**: Consistent Success/Failure pattern throughout
- **New embedding subsystem**: Clean duck typing with shared RSpec examples verifying provider contract. DimensionCheck is a textbook value object — pure function, immutable result, no side effects. The resolver uses simple case/when (no over-engineered factory/registry).
- **VectorIndex#clear!**: Properly encapsulates destructive vec0 operation behind the abstraction boundary

---

## 8. Priority Refactoring Recommendations

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
| 8 | ContentItemAttributes value object | 1 hour | Readability |
| 10 | Replace sleep-based tests with mocks | 1 hour | Test speed |
| 11 | Shared test factory | 1 hour | DRY |
| 17 | ResponseFormatter base method | 1 hour | DRY |
| 14 | Separate I/O in discover_other_projects | 1 hour | Boundaries |

### Low Priority (Later)
| # | Item | Effort | Impact |
|---|------|--------|--------|
| 13 | Payload validator for hooks | 30 min | Consistency |
| 15 | Sweeper mutable state | 20 min | Immutability |
| 16 | Dir.chdir in tests | 15 min | Test isolation |
| 18 | Publish section builder | 30 min | DRY |

### Carried Forward (Low Priority from Earlier Reviews)
| # | Item | Original # |
|---|------|-----------|
| 20 | DateTime migration (string timestamps) | Feb 4 #17 |
| 21 | Command manager helper (`with_manager`) | Feb 4 #19 |
| 22 | release_connections polymorphism | Feb 4 #20 |
| 23 | Provenance batch insert (`multi_insert`) | Feb 4 #22 |
| 24 | Individual MCP tool classes | Feb 4 #23 (subsumed by #1) |
| 25 | Result objects for all queries | Feb 4 #24 |

---

## 9. Conclusion

The codebase maintains its strong architectural foundation. Nine quality items were resolved this session across two passes: the Shortcuts scope correctness bug, ApiAdapter exception typing, silent exception logging, dead code removal, method decomposition, promote_fact transaction verification, provenance nil validation fix, Resolver state verification, and SnippetExtractor DRY extraction.

No known correctness bugs remain. The most impactful remaining improvements are structural: (1) splitting `Tools` and `Recall` into focused classes, and (2) adding tests for ~12 untested files. The three >500-line files continue growing and represent the primary maintainability risk.

---

## Appendix A: Metrics Comparison

| Metric | Jan 29 | Feb 4 | Mar 9 | Mar 19 |
|--------|--------|-------|-------|--------|
| Ruby files (lib) | ~85 | 104 | 112 | **117** |
| LOC (lib) | ~8,000 | 9,982 | 11,392 | **12,239** |
| LOC (spec) | — | 17,693 | 21,632 | **22,563** |
| Pure logic classes | 17+ | 20+ | 20+ | **22+** |
| Test files | 74+ | 98 | 128 | **122** |
| Test-to-code ratio | ~1.5:1 | 1.77:1 | 1.90:1 | **1.84:1** |
| Files >500 lines | 0 | 2 | 3 | **3** 🔴 |
| Bare rescues (silent) | 0 | 0 | 1 | **0** ✅ |
| N+1 patterns (hot paths) | 0 | 0 | 0 | **0** ✅ |
| N+1 patterns (cold paths) | — | — | 1 | **0** ✅ |
| Untested lib files | — | — | 16 | **~12** 🟡 |
| Known correctness bugs | — | — | — | **0** ✅ |

## Appendix B: File Size Report

| File | Mar 9 | Mar 19 | Trend |
|------|-------|--------|-------|
| `mcp/tools.rb` | 728 | 745 | ⬆️ +17 |
| `recall.rb` | 681 | 727 | ⬆️ +46 |
| `store/sqlite_store.rb` | 547 | 547 | — |
| `mcp/response_formatter.rb` | 394 | 396 | ⬆️ +2 |
| `mcp/tool_definitions.rb` | 303 | 334 | ⬆️ +31 |
| `commands/index_command.rb` | 224 | 272 | ⬆️ +48 |
| `mcp/text_summary.rb` | 257 | 258 | ⬆️ +1 |
| `commands/stats_command.rb` | 239 | 250 | ⬆️ +11 |
| `commands/uninstall_command.rb` | 226 | 226 | — |
| `publish.rb` | 221 | 221 | — |
| `infrastructure/schema_validator.rb` | 215 | 215 | — |
| `commands/hook_command.rb` | 214 | 214 | — |
| `resolve/resolver.rb` | — | 195 | new to watch |
| `index/vector_index.rb` | — | 184 | new to watch |

---

**Next review:** After Tools extraction or Recall strategy pattern refactoring
