# Code Quality Review - Ruby Best Practices

**Review Date:** 2026-02-04
**Previous Review:** 2026-01-29
**Last Quality Update:** 2026-02-04 (21/24 items completed)

---

## Executive Summary

The codebase is in strong shape after a comprehensive quality pass on Feb 4. All critical and high-priority issues from the review have been resolved: N+1 queries eliminated, bare rescues replaced with specific exception types, mutation patterns fixed in functional core, and long methods decomposed into focused helpers.

**Remaining work:** 9 items (1 medium, 8 low priority). No critical or high-priority issues remain.

### Current Strengths

- Functional core: 20+ pure logic classes with zero I/O
- Domain objects: properly frozen and self-validating
- Null object pattern: NullFact, NullExplanation
- Result monad: Core::Result for Success/Failure
- 100% frozen_string_literal compliance (104 files)
- 1.77:1 test-to-code ratio (17,693 spec : 9,982 lib)
- Zero bare rescues, zero N+1 queries

---

## Remaining Items

### Medium Priority

| # | Issue | File:Line | Expert |
|---|-------|-----------|--------|
| 16 | Resolver mutable state after init | `resolve/resolver.rb:10-13` | Gary Bernhardt |

`@current_project_path` and `@current_scope` are set in `apply()` rather than threaded as parameters. Should pass through method chain instead of mutable instance state.

### Low Priority

| # | Issue | File:Line | Expert |
|---|-------|-----------|--------|
| 17 | DateTime migration (string timestamps) | Multiple files | Jeremy Evans |
| 18 | Strategy pattern in Recall (608 lines) | `recall.rb` | Sandi Metz |
| 19 | Command manager helper (`with_manager`) | `commands/*.rb` | Kent Beck |
| 20 | release_connections polymorphism | `mcp/server.rb:148-156` | Gary Bernhardt |
| 21 | Sweeper mutable state | `sweep/sweeper.rb:16-17` | Gary Bernhardt |
| 22 | Provenance batch insert (`multi_insert`) | `store/store_manager.rb:129-139` | Jeremy Evans |
| 23 | Individual MCP tool classes | `mcp/tools.rb` | Sandi Metz |
| 24 | Result objects for all queries | Multiple files | Avdi Grimm |

---

## Risk Assessment

| Area | Risk Level | Notes |
|------|-----------|-------|
| **Performance** | ✅ Low | N+1 queries fixed |
| **Maintainability** | ✅ Low | Long methods decomposed |
| **Correctness** | ✅ Low | databases_exist? fixed, ResultSorter non-mutating |
| **Error Handling** | ✅ Low | All bare rescues replaced with specific types |
| **Architecture** | ✅ Low | Strong functional core, proper layering |
| **Testing** | ✅ Low | 1.77:1 ratio, 98 spec files |

---

## Metrics

| Metric | Jan 29 | Feb 4 |
|--------|--------|-------|
| Ruby files (lib) | ~85 | 104 |
| LOC (lib) | ~8,000 | 9,982 |
| Pure logic classes | 17+ | 20+ |
| Test files | 74+ | 98 |
| Test-to-code ratio | ~1.5:1 | 1.77:1 |
| Files >500 lines | 0 | 2 (tools, recall) 🟡 |
| Bare rescues | 0 | 0 ✅ |
| N+1 patterns | 0 | 0 ✅ |

## File Size Watch List

| File | Lines | Concern |
|------|-------|---------|
| `mcp/tools.rb` | ~610 | Consider individual tool classes (#23) |
| `recall.rb` | ~608 | Consider strategy pattern extraction (#18) |
| `store/sqlite_store.rb` | 481 | Trending up — watch for 500 |

---

## Completed (Feb 4, 2026)

<details>
<summary>21 items completed in 7 atomic commits</summary>

**Quick Wins (6):** bare rescue in server.rb, tool_extractor.rb, stats_command.rb; ResultSorter mutation; RRFusion mutation; databases_exist? logic

**High Priority (8):** N+1 provenance query; N+1 legacy query; check_setup extraction; detailed_stats extraction; resolve_fact decomposition; ingester transaction body extraction

**Medium Priority (7):** RRFusion mutation; OperationTracker DRY; ToolExtractor bare rescue; databases_exist?; stats_command bare rescue; SchemaValidator.validate extraction; FactGraph.build decomposition
</details>

---

**Next review:** After recall.rb strategy pattern or sqlite_store.rb extraction
