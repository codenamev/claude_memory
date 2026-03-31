# KBS (Knowledge-Based System) Analysis

*Analysis Date: 2026-03-02*
*Re-studied: 2026-03-30 — no changes since v0.2.1*
*Repository: https://github.com/MadBomber/kbs*
*Version: v0.2.1 (commit c04561d)*

---

## Executive Summary

KBS is a Ruby gem implementing a Knowledge-Based System with RETE algorithm inference, Blackboard architecture, and AI integration. It provides forward-chaining rule evaluation, declarative DSL, persistent fact storage (SQLite/Redis/Hybrid), audit trails, and message-based multi-agent coordination.

**Key Innovation**: RETE algorithm implementation in Ruby with unlinking optimization, combined with a Blackboard architecture for multi-agent fact coordination.

| Attribute | Value |
|-----------|-------|
| Language | Ruby (>= 3.2.0) |
| LOC | ~2,796 (lib/) |
| Runtime deps | sqlite3 (>= 1.6) |
| Stars | 2 |
| Contributors | 1 (Dewayne VanHoozer) |
| License | MIT |
| Created | 2025-10-07 |
| Last updated | 2026-02-27 |
| Tests | 199 runs, 447 assertions (Minitest) |
| Releases | 3 (v0.0.1, v0.1.0, v0.2.1) |

**Production Readiness**: Early-stage. Low adoption (2 stars, sole maintainer), 3 releases over ~5 months. Well-documented and tested but not battle-tested in production at scale.

---

## Architecture Overview

### Data Model

KBS uses two distinct fact models depending on context:

1. **In-memory facts** (`KBS::Fact`, `fact.rb:4-42`): Mutable objects with `type` + `attributes` hash. ID is Ruby `object_id`. Pattern matching via `matches?(pattern)` supports equality, Proc predicates, and variable bindings.

2. **Persistent facts** (`KBS::Blackboard::Fact`, `blackboard/fact.rb:1-65`): UUID-identified, backed by SQLite/Redis. Attribute mutations trigger persistence callbacks. Supports soft deletion via `retract()`.

### Core Architecture

```
Rules (DSL) → RETE Network → Alpha/Beta/Join/Production Nodes
                                        ↓
WorkingMemory ← Facts ← Blackboard Memory → Persistence (SQLite/Redis)
                              ↓                    ↓
                        Message Queue          Audit Log
```

### Design Patterns

| Pattern | Implementation | File Reference |
|---------|---------------|----------------|
| RETE Algorithm | Alpha/Beta networks with unlinking | `engine.rb:1-149` |
| Observer | Fact changes trigger RETE propagation | `working_memory.rb:17-20` |
| Builder | Fluent rule configuration | `dsl/rule_builder.rb:1-115` |
| Strategy | Store abstraction (SQLite/Redis/Hybrid) | `blackboard/persistence/store.rb:7-52` |
| Interpreter | DSL via instance_eval + PatternEvaluator | `dsl/knowledge_base.rb:15-23` |
| Composite | Blackboard aggregates Engine + Memory + Queue + Audit | `blackboard/memory.rb:13-189` |

### Module Organization (32 files)

```
lib/kbs/
├── engine.rb              # RETE inference engine (149 LOC)
├── fact.rb                # In-memory fact model (43 LOC)
├── rule.rb                # Rule with conditions + action (46 LOC)
├── condition.rb           # Pattern condition (26 LOC)
├── token.rb               # RETE token (partial match) (37 LOC)
├── working_memory.rb      # Transient fact store (32 LOC)
├── alpha_memory.rb        # Pattern matching node (37 LOC)
├── beta_memory.rb         # Join result store (57 LOC)
├── join_node.rb           # RETE join node (117 LOC)
├── negation_node.rb       # NOT condition handling (88 LOC)
├── production_node.rb     # Rule firing terminal (28 LOC)
├── decompiler.rb          # YARV bytecode decompiler (204 LOC)
├── dsl/
│   ├── knowledge_base.rb  # DSL entry point (185 LOC)
│   ├── rule_builder.rb    # Fluent rule building (115 LOC)
│   ├── condition_helpers.rb # Predicate factories (57 LOC)
│   ├── pattern_evaluator.rb # method_missing DSL (69 LOC)
│   └── variable.rb        # Binding variables (35 LOC)
└── blackboard/
    ├── engine.rb           # Blackboard-backed RETE (83 LOC)
    ├── memory.rb           # Central workspace (191 LOC)
    ├── fact.rb             # Persistent fact model (65 LOC)
    ├── message_queue.rb    # SQLite message queue (96 LOC)
    ├── audit_log.rb        # Fact change history (115 LOC)
    ├── redis_message_queue.rb  # Redis messages (111 LOC)
    ├── redis_audit_log.rb  # Redis audit (107 LOC)
    └── persistence/
        ├── store.rb        # Abstract interface (55 LOC)
        ├── sqlite_store.rb # SQLite backend (242 LOC)
        ├── redis_store.rb  # Redis backend (218 LOC)
        └── hybrid_store.rb # Redis+SQLite (118 LOC)
```

### Comparison Table vs ClaudeMemory

| Aspect | KBS | ClaudeMemory |
|--------|-----|--------------|
| **Primary purpose** | Rule-based inference | Knowledge storage & recall |
| **Fact model** | type + attributes (JSON blob) | Subject-predicate-object triples |
| **Fact identity** | object_id / UUID | Integer ID + docid |
| **Mutability** | Mutable attributes | Immutable facts |
| **Persistence** | sqlite3 gem (raw SQL) | Sequel + Extralite |
| **Schema** | Single `facts` table + JSON | Normalized (facts, entities, provenance, fact_links, conflicts) |
| **Scoping** | Session-based | Global/Project dual-database |
| **Truth maintenance** | None | Supersession + conflict resolution |
| **Temporal** | created_at/updated_at | valid_from/valid_to windows |
| **Search** | Pattern matching, raw SQL | FTS5, semantic embeddings, hybrid |
| **Provenance** | Audit log (separate table) | Linked provenance with source excerpts |
| **Conflict resolution** | Not implemented | PredicatePolicy + Resolver |
| **Message passing** | Priority queue (SQLite/Redis) | Not a core feature |
| **AI integration** | RubyLLM for LLM calls | MCP server for Claude Code |
| **Reasoning** | Forward-chaining (RETE) | Query/recall based |
| **Soft delete** | retracted flag | valid_to timestamp |

---

## Key Components Deep-Dive

### 1. RETE Inference Engine

The RETE implementation is the core differentiator. It compiles rules into a discrimination network:

**Network building** (`engine.rb:99-143`):
```ruby
def build_network_for_rule(rule)
  current_beta = @root_beta_memory
  rule.conditions.each_with_index do |condition, index|
    pattern = condition.pattern.merge(type: condition.type)
    alpha_memory = get_or_create_alpha_memory(pattern)
    if condition.negated
      negation_node = NegationNode.new(alpha_memory, current_beta, tests)
      # ...
    else
      join_node = JoinNode.new(alpha_memory, current_beta, tests)
      # ...
    end
  end
  production_node = ProductionNode.new(rule)
  current_beta.successors << production_node
end
```

**Relevance to ClaudeMemory**: Low. ClaudeMemory's truth maintenance uses a different paradigm (explicit supersession/conflict resolution via `Resolver`), not forward-chaining inference. RETE would be over-engineering for our conflict detection needs.

### 2. Store Abstraction (`persistence/store.rb:7-52`)

Clean abstract interface with 9 required methods:

```ruby
class Store
  def add_fact(uuid, type, attributes)    # CRUD
  def remove_fact(uuid)
  def update_fact(uuid, attributes)
  def get_fact(uuid)
  def get_facts(type = nil, pattern = {})
  def query_facts(conditions, params)     # Advanced queries
  def clear_session(session_id)           # Session management
  def stats                               # Monitoring
  def close                               # Lifecycle
  def vacuum                              # Optional maintenance
  def transaction(&block)                 # Default: just yield
end
```

**Relevance to ClaudeMemory**: Medium. ClaudeMemory's `SQLiteStore` combines schema management, CRUD, and query logic in one class (~800+ LOC). KBS's clean separation of the store interface from implementation is a good pattern, though our Sequel-based approach provides more abstraction already.

### 3. Audit Log (`blackboard/audit_log.rb:8-115`)

Dedicated table for fact change history with timestamps and session isolation:

```ruby
def log_fact_change(fact_uuid, fact_type, attributes, action)
  # INSERT INTO fact_history (fact_uuid, fact_type, attributes, action, session_id)
end
```

Schema: `fact_history` (uuid, type, attributes JSON, action [ADD/REMOVE/UPDATE], timestamp, session_id) + `rules_fired` (rule_name, fact_uuids JSON, bindings JSON, fired_at, session_id).

**Relevance to ClaudeMemory**: Low-Medium. ClaudeMemory already has provenance tracking via the `provenance` table (links facts to source content_items with excerpts). KBS's audit is simpler (action log) while ours is richer (evidence chain). However, KBS's explicit action tracking (ADD/REMOVE/UPDATE) could complement our provenance for debugging.

### 4. Blackboard Memory (`blackboard/memory.rb:13-189`)

Central coordinator composing Store + MessageQueue + AuditLog:

```ruby
def add_fact(type, attributes = {})
  uuid = SecureRandom.uuid
  @store.transaction do
    @store.add_fact(uuid, type, attributes)
    @audit_log.log_fact_change(uuid, type, attributes, 'ADD')
  end
  fact = Fact.new(uuid, type, attributes, self)
  notify_observers(:add, fact)
  fact
end
```

**Relevance to ClaudeMemory**: Medium. The composition pattern (Memory = Store + Queue + Audit) is clean. ClaudeMemory's `StoreManager` manages dual databases but doesn't compose additional concerns. The message queue pattern could be interesting for coordinating between hooks.

### 5. Declarative DSL (`dsl/rule_builder.rb:1-115`)

Fluent rule definition with instance_eval:

```ruby
rule "momentum_breakout" do
  desc "Detect stock momentum breakouts"
  priority 10
  on :stock, volume: greater_than(1_000_000)
  on :stock, price_change_pct: greater_than(3)
  without :position, status: "open"
  perform do |facts, bindings|
    # ...
  end
end
```

**Relevance to ClaudeMemory**: Low. ClaudeMemory doesn't need a rule DSL — its distillation and resolution logic operates differently. However, the condition helper pattern (`greater_than`, `one_of`, `matches`) is elegant and could inspire a query DSL for complex recall operations.

### 6. SQLite Store Implementation (`persistence/sqlite_store.rb:10-242`)

Uses raw `sqlite3` gem with JSON-serialized attributes:

```ruby
def add_fact(uuid, type, attributes)
  attributes_json = JSON.generate(attributes)
  @db.execute(
    "INSERT INTO facts (uuid, fact_type, attributes, session_id) VALUES (?, ?, ?, ?)",
    [uuid, type.to_s, attributes_json, @session_id]
  )
end
```

**Notable patterns**:
- Nested transaction support via depth counter (`sqlite_store.rb:199-214`)
- Soft delete via `retracted` flag (`sqlite_store.rb:87-104`)
- Auto-update trigger for `updated_at` (`sqlite_store.rb:68-76`)
- JSON pattern matching in Ruby, not SQL (`sqlite_store.rb:230-238`)

**Relevance to ClaudeMemory**: Low. ClaudeMemory uses Sequel + Extralite (significantly better performance than sqlite3 gem) and a normalized schema vs JSON blobs. KBS's approach is simpler but less queryable.

---

## Comparative Analysis

### What KBS Does Well

1. **Clean store abstraction** (`persistence/store.rb`): 9 methods, clear interface, easy to implement new backends
2. **Multi-backend flexibility**: SQLite + Redis + Hybrid with auto-detection (`memory.rb:32-51`)
3. **Audit trail as first-class concern**: Separate table with explicit action tracking
4. **Expressive DSL**: `on`, `without`, `perform` with condition helpers reads naturally
5. **Transaction safety**: Both fact mutation and audit logging wrapped in transactions (`memory.rb:60-63`)
6. **Session isolation**: UUID-based sessions with cleanup (`memory.rb:160-163`)
7. **Documentation quality**: 31 docs files, architecture guides, progressive learning path
8. **Example coverage**: 32 executable examples across domains

### What ClaudeMemory Does Better

1. **Rich fact model**: Subject-predicate-object triples vs flat JSON blobs enable structured queries
2. **Truth maintenance**: Supersession, conflict detection, PredicatePolicy — KBS has none
3. **Dual-scope architecture**: Global/project separation is core; KBS only has session isolation
4. **Search capabilities**: FTS5 + semantic embeddings + hybrid search vs simple pattern matching
5. **Provenance chains**: Source-linked evidence vs simple action logs
6. **Temporal validity**: valid_from/valid_to windows vs binary active/retracted
7. **Performance**: Sequel + Extralite significantly outperforms sqlite3 gem
8. **Domain fit**: Purpose-built for AI memory; KBS is general-purpose inference

### Trade-offs

| Consideration | KBS Advantage | ClaudeMemory Advantage |
|--------------|---------------|----------------------|
| Flexibility | Multi-backend (SQLite/Redis) | Purpose-built for AI memory use case |
| Fact model | Simple, flexible JSON | Structured, queryable triples |
| Reasoning | Forward-chaining RETE | Recall-oriented search + truth maintenance |
| Complexity | 2,796 LOC, simpler architecture | Richer features, more code |
| Dependencies | Minimal (sqlite3 only) | More dependencies but better perf (Sequel + Extralite) |
| Maturity | 2 stars, 3 releases, solo maintainer | More developed, more users |

---

## Suitability as Upstream Dependency

### Arguments FOR

1. **Upstream maintenance**: Bug fixes and improvements come free
2. **Store abstraction**: Could wrap our persistence behind KBS's interface
3. **Audit trail**: Built-in fact change tracking
4. **Rule engine potential**: Could formalize truth maintenance as rules

### Arguments AGAINST (Stronger)

1. **Architectural mismatch**: KBS solves inference (forward-chaining rules); ClaudeMemory solves knowledge management (storage, recall, truth maintenance). These are fundamentally different problems.

2. **Schema incompatibility**: KBS stores facts as `{type, attributes_json}` in a single table. ClaudeMemory needs normalized `{subject, predicate, object}` triples with scope, temporal validity, provenance links, and entity relationships. Adapting KBS's schema would require replacing its entire persistence layer.

3. **Performance regression**: KBS uses the `sqlite3` gem with raw SQL. ClaudeMemory uses Sequel + Extralite, which is significantly faster for our query patterns (batch loading, FTS5, embeddings).

4. **Missing core features**: KBS has no truth maintenance (supersession/conflicts), no FTS5 indexing, no embedding/vector search, no scope system (global/project), no temporal validity windows. These are ClaudeMemory's core differentiators and would need to be built on top anyway.

5. **Low adoption risk**: 2 stars, single maintainer. Using this as a dependency introduces supply chain risk with minimal benefit. The gem could go unmaintained.

6. **Abstraction tax**: Wrapping KBS's store interface around our Sequel-based persistence would add indirection without benefit — we'd be using a thin wrapper around SQLite to talk to our own SQLite.

7. **Feature surface mismatch**: KBS includes RETE engine, DSL, Blackboard, Redis support, message queuing — most of which ClaudeMemory doesn't need. This is significant dead weight as a dependency.

### Verdict: **Do NOT use as dependency**

The architectures solve fundamentally different problems. The integration cost exceeds the benefit of upstream updates. KBS's store abstraction is the only directly useful component, but ClaudeMemory's Sequel-based approach is already more capable.

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Explicit Fact Action Tracking
- **Value**: Debug visibility into fact lifecycle (ADD/UPDATE/SUPERSEDE/RETRACT)
- **Evidence**: `blackboard/audit_log.rb:43-49` — `log_fact_change(uuid, type, attributes, action)`
- **Implementation**: Add `action` column to existing content change tracking. Log explicit actions (INSERT, SUPERSEDE, CONFLICT, RETRACT) alongside provenance.
- **Effort**: 0.5 day
- **Trade-off**: Minor schema change, migration needed
- **Recommendation**: CONSIDER — enhances debugging without major refactoring

### Medium Priority

#### 2. Transaction-Wrapped Audit Logging Pattern
- **Value**: Guarantee audit completeness — fact mutation and audit log always succeed or fail together
- **Evidence**: `blackboard/memory.rb:60-63` — `@store.transaction { store.add_fact(...); audit_log.log(...) }`
- **Implementation**: Ensure our Resolver's supersession and conflict operations also log within the same transaction.
- **Effort**: 0.5 day
- **Trade-off**: Minimal — our Sequel transactions already support this
- **Recommendation**: CONSIDER — defensive improvement

#### 3. Condition Helpers for Query DSL
- **Value**: More expressive recall queries with predicate helpers
- **Evidence**: `dsl/condition_helpers.rb:1-57` — `greater_than(v)`, `one_of(*values)`, `matches(regex)`, `satisfies(&block)`
- **Implementation**: Add predicate helpers to Recall queries for filtering facts by attribute values.
- **Effort**: 1-2 days
- **Trade-off**: Adds API surface; may not be needed if FTS/embedding search is sufficient
- **Recommendation**: DEFER — current query interface sufficient for LLM use case

#### 4. Message Queue for Hook Coordination
- **Value**: Decouple hook invocations; allow async communication between ingest/sweep/publish
- **Evidence**: `blackboard/message_queue.rb:1-96` — SQLite-backed priority queue with post/consume/peek
- **Implementation**: Add simple message table for inter-hook communication (e.g., "sweep needed" flag, "publish pending" state)
- **Effort**: 1-2 days
- **Trade-off**: Adds complexity for a problem we mostly solve with hook ordering
- **Recommendation**: DEFER — hooks work sequentially; message queue adds unnecessary complexity

### Low Priority

#### 5. Redis Store Backend
- **Value**: 100x faster fact access for high-frequency query scenarios
- **Evidence**: `blackboard/persistence/redis_store.rb:1-218` — Full Redis implementation with indexes
- **Implementation**: Add Redis as optional hot cache in front of SQLite
- **Effort**: 3-5 days
- **Trade-off**: Adds Redis dependency, operational complexity
- **Recommendation**: DEFER — SQLite + Extralite is fast enough; no user demand

#### 6. Soft Delete Pattern
- **Value**: Recoverable fact deletion, simpler than temporal validity
- **Evidence**: `persistence/sqlite_store.rb:87-103` — `retracted` flag with `retracted_at` timestamp
- **Implementation**: N/A — ClaudeMemory already uses `valid_to` timestamps which is more powerful (temporal queries, not just active/inactive)
- **Effort**: N/A
- **Trade-off**: N/A
- **Recommendation**: REJECT — our temporal validity subsumes soft delete

### Features to Avoid

1. **RETE Algorithm** — Forward-chaining inference is architecturally wrong for ClaudeMemory. Our truth maintenance is about detecting contradictions in stored knowledge, not evaluating rule patterns against a fact base. Adding RETE would massively over-engineer a problem we solve with ~100 lines of Resolver code.

2. **Raw sqlite3 gem** — We use Sequel + Extralite for good reasons: dataset API, connection pooling, migration support, and significantly better performance. Downgrading to raw SQL would be a regression.

3. **JSON blob storage** — KBS stores fact attributes as `JSON.generate(attributes)` in a TEXT column. This prevents SQL-level queries on individual attributes. Our normalized schema (subject, predicate, object columns) enables precise queries without deserializing.

4. **KBS as a dependency** — See "Suitability as Upstream Dependency" section above. The architectural mismatch, performance regression, and feature gaps make this a poor fit.

---

## Implementation Recommendations

### Phase 1: Learn, Don't Depend (Now)

- Study KBS's audit trail pattern for potential provenance enhancements
- Note the clean store abstraction pattern for future reference
- No code changes needed — the patterns are documented here for future consideration

### Phase 2: Selective Pattern Adoption (If Needed)

- Explicit action tracking on fact changes (inspired by `audit_log.rb`)
- Transaction-wrapped audit guarantees (inspired by `memory.rb`)
- Only implement if debugging needs arise

---

## Architecture Decisions

### Preserve

- **Sequel + Extralite**: Superior to KBS's raw sqlite3 approach
- **Normalized schema**: Subject-predicate-object triples vs JSON blobs
- **Truth maintenance**: Resolver with supersession/conflicts — KBS has nothing comparable
- **Dual-database scoping**: Global/project separation
- **FTS5 + embeddings**: KBS has no search capabilities beyond pattern matching

### Reject

- **KBS as dependency**: Architectural mismatch, low adoption, feature gaps
- **RETE engine**: Wrong paradigm for knowledge recall
- **Raw SQL persistence**: Regression from Sequel
- **JSON blob storage**: Regression from normalized schema
- **Redis backend**: Unnecessary complexity for our use case
- **Message queue**: Hooks work sequentially

### Consider (Low Priority)

- **Explicit action tracking**: Enhances debugging visibility
- **Transaction-wrapped auditing**: Defensive improvement

---

## Key Takeaways

1. **KBS and ClaudeMemory solve fundamentally different problems.** KBS is an inference engine (rules → conclusions from facts). ClaudeMemory is a knowledge management system (store → recall → maintain facts). The overlap is only at the "facts stored in SQLite" level.

2. **Do not use as a dependency.** The integration cost far exceeds the benefit. KBS's store abstraction is clean but our Sequel-based approach is already more capable. The RETE engine, DSL, and message queue are irrelevant to our use case.

3. **Learn from the patterns.** KBS's audit trail (explicit actions), transaction-wrapped mutations, and store abstraction are well-implemented patterns. We can incorporate these ideas without taking a dependency.

4. **ClaudeMemory is ahead on every axis that matters for AI memory**: truth maintenance, semantic search, provenance, scoping, temporal validity, and performance. KBS fills a different niche (expert systems, rule-based inference) well.

5. **If rule-based reasoning becomes needed**, KBS could be valuable as a separate integration layer (e.g., rules that trigger based on memory state changes), but this would be an optional plugin, not a core dependency.
