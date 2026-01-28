# Code Quality Review - Ruby Best Practices

**Reviewed by perspectives of:** Sandi Metz, Jeremy Evans, Kent Beck, Avdi Grimm, Gary Bernhardt

**Review Date:** 2026-01-27 (Updated)

**Previous Review:** 2026-01-26

---

## Executive Summary

**EXCELLENT PROGRESS!** Since the January 26th review, critical architectural improvements continue:

### Major Wins Since Last Review ✅

1. ✅ **Migrations System Refactored** - Now using proper Sequel migration files in `db/migrations/` (001-007)
2. ✅ **DoctorCommand Refactored** - Reduced from 174 to 31 lines with extracted check classes
3. ✅ **FactRanker Extracted** - Pure logic class extracted to `Core::FactRanker` (Gary Bernhardt pattern!)
4. ✅ **Recall.rb Reduced** - From 914 to 754 lines (17% reduction)
5. ✅ **SQLiteStore Reduced** - From 542 to 383 lines (29% reduction)

### Critical Issues Remaining

Despite progress, **Recall.rb and MCP Tools remain god objects**:

1. **🔴 Recall.rb Still a God Object** - 754 lines, 58 methods (down from 914/57 but still too large)
2. **🔴 MCP Tools.rb Growing** - 1,039 lines (up from 901, +15%)
3. **🔴 JSON Functions Still Present** - operation_tracker.rb breaking Sequel abstractions
4. **🟡 String Timestamps Everywhere** - Should use DateTime columns
5. **🟡 Code Duplication** - Dual-database pattern still repeated

---

## 1. Sandi Metz Perspective (POODR)

### What's Been Fixed Since Last Review ✅

- ✅ **DoctorCommand refactored** - 174 → 31 lines, extracted 5 check classes
- ✅ **FactRanker extracted** - Pure logic separated from I/O
- ✅ **Migrations extracted** - Now 7 separate migration files
- ✅ **Recall reduced** - 914 → 754 lines (but still too large)

### Critical Issues Remaining

#### 🔴 Recall.rb Still God Object (recall.rb:1-754)

**Problem:** Despite 17% reduction, still handles too many responsibilities:
- Legacy single-database mode
- Dual-database mode (global + project)
- FTS search
- Semantic search (vector embeddings)
- Concept search
- Batch query optimization
- Change tracking
- Conflict queries
- Tool-based fact queries
- Context-based fact queries

**Current State:**
- **754 lines** (down from 914)
- **58 methods** (up from 57)
- Still violates SRP massively
- 10+ distinct responsibilities

**Evidence:**
```ruby
# recall.rb:42-48 - Routing logic repeated everywhere
def query(query_text, limit: 10, scope: SCOPE_ALL)
  if @legacy_mode
    query_legacy(query_text, limit: limit, scope: scope)
  else
    query_dual(query_text, limit: limit, scope: scope)
  end
end

# This pattern repeats for: query, query_index, explain, changes, conflicts,
# facts_by_branch, facts_by_directory, facts_by_tool, query_semantic, query_concepts
```

**Sandi Metz Says:** "A class should have one reason to change. This has ten."

**Recommended Fix:**
```ruby
# lib/claude_memory/recall.rb - Thin coordinator (< 100 lines)
module ClaudeMemory
  class Recall
    def initialize(store_or_manager, **options)
      @strategy = build_strategy(store_or_manager, options)
    end

    def query(query_text, limit: 10, scope: SCOPE_ALL)
      @strategy.query(query_text, limit: limit, scope: scope)
    end

    def query_semantic(query_text, limit: 10, scope: SCOPE_ALL, mode: "both")
      @strategy.query_semantic(query_text, limit: limit, scope: scope, mode: mode)
    end

    # ... delegate all methods to strategy

    private

    def build_strategy(store_or_manager, options)
      if store_or_manager.is_a?(Store::StoreManager)
        Recall::DualStoreStrategy.new(store_or_manager, options)
      else
        Recall::LegacyStoreStrategy.new(store_or_manager, options)
      end
    end
  end
end

# lib/claude_memory/recall/dual_store_strategy.rb (~300 lines)
module ClaudeMemory
  module Recall
    class DualStoreStrategy
      def initialize(manager, options)
        @manager = manager
        @fts = Recall::FtsSearch.new
        @semantic = Recall::SemanticSearch.new(options[:embedding_generator])
        @formatter = Recall::ResultFormatter.new
      end

      def query(query_text, limit:, scope:)
        @fts.search(@manager, query_text, limit: limit, scope: scope)
      end

      def query_semantic(query_text, limit:, scope:, mode:)
        @semantic.search(@manager, query_text, limit: limit, scope: scope, mode: mode)
      end

      # ... other methods
    end
  end
end

# lib/claude_memory/recall/fts_search.rb (~100 lines)
# lib/claude_memory/recall/semantic_search.rb (~150 lines)
# lib/claude_memory/recall/result_formatter.rb (~100 lines)
```

**Estimated Effort:** 2-3 days

#### 🔴 MCP Tools.rb Growing - Now at 1,039 Lines (mcp/tools.rb:1-1039)

**Problem:** File has **GROWN 15%** since last review (901 → 1,039 lines)

**Still Contains:**
- 17+ tool definitions mixed with implementations
- Parameter validation logic
- Handler implementations
- Stats aggregation
- Error formatting
- Result formatting
- JSON serialization

**Violations:**
- Single file doing too much
- Hard to find specific tool logic
- Hard to test individual tools
- Mixed concerns (definition + implementation + formatting)

**Recommended Fix:**
```ruby
# lib/claude_memory/mcp/server.rb
module ClaudeMemory
  module MCP
    class Server
      TOOLS = {
        "memory.recall" => Tools::Recall,
        "memory.recall_index" => Tools::RecallIndex,
        "memory.recall_details" => Tools::RecallDetails,
        "memory.explain" => Tools::Explain,
        "memory.promote" => Tools::Promote,
        "memory.status" => Tools::Status,
        "memory.changes" => Tools::Changes,
        "memory.conflicts" => Tools::Conflicts,
        "memory.sweep_now" => Tools::SweepNow,
        "memory.decisions" => Tools::Decisions,
        "memory.conventions" => Tools::Conventions,
        "memory.architecture" => Tools::Architecture,
        "memory.facts_by_tool" => Tools::FactsByTool,
        "memory.facts_by_context" => Tools::FactsByContext,
        "memory.recall_semantic" => Tools::RecallSemantic,
        "memory.search_concepts" => Tools::SearchConcepts,
        "memory.stats" => Tools::Stats
      }

      def handle_tool_call(name, params)
        tool_class = TOOLS[name]
        return error_response("Unknown tool: #{name}") unless tool_class

        tool_class.new(@manager).call(params)
      end
    end
  end
end

# lib/claude_memory/mcp/tools/recall.rb (~60 lines)
module ClaudeMemory
  module MCP
    module Tools
      class Recall < BaseTool
        SCHEMA = {
          name: "memory.recall",
          description: "Recall facts matching a query.",
          inputSchema: {
            type: "object",
            properties: {
              query: {type: "string", description: "Search query"},
              limit: {type: "integer", default: 10},
              scope: {type: "string", enum: ["all", "global", "project"], default: "all"}
            },
            required: ["query"]
          }
        }

        def call(params)
          query = params["query"]
          limit = params.fetch("limit", 10)
          scope = params.fetch("scope", "all")

          recall = ClaudeMemory::Recall.new(@manager)
          results = recall.query(query, limit: limit, scope: scope)

          format_results(results)
        end

        private

        def format_results(results)
          {
            content: [{
              type: "text",
              text: Formatter.format_fact_list(results)
            }]
          }
        end
      end
    end
  end
end

# lib/claude_memory/mcp/tools/base_tool.rb (~30 lines)
# lib/claude_memory/mcp/tools/formatter.rb (~100 lines)
```

**Estimated Effort:** 2 days

#### 🟡 Massive Code Duplication Remains (recall.rb)

**Problem:** Every query method still has dual and legacy variants:
- `query`, `query_dual`, `query_legacy`
- `query_index`, `query_index_dual`, `query_index_legacy`
- `changes`, `changes_dual`, `changes_legacy`
- `conflicts`, `conflicts_dual`, `conflicts_legacy`
- `facts_by_branch`, `facts_by_context_dual`, `facts_by_context_legacy`

This represents **duplicate knowledge** expressed multiple times.

**Sandi Metz Says:** "Refactor duplication before extracting abstractions."

**Fix:** Extract strategy pattern (see Recall refactoring above).

**Estimated Effort:** Included in Recall refactoring (2-3 days)

---

## 2. Jeremy Evans Perspective (Sequel Expert)

### What's Been Fixed Since Last Review ✅

- ✅ **Migrations refactored** - Now using Sequel::Migrator with proper migration files
- ✅ **Migration directory created** - 7 migration files (001-007) in `db/migrations/`
- ✅ **Manual migration code removed** - No more hand-rolled `migrate_to_vN!` methods
- ✅ **SQLiteStore reduced** - 542 → 383 lines (29% reduction)

**Evidence:**
```ruby
# sqlite_store.rb:4 - Now imports Sequel migrations
require "sequel/extensions/migration"

# Migration files exist:
# db/migrations/001_create_initial_schema.rb
# db/migrations/002_add_project_scoping.rb
# db/migrations/003_add_session_metadata.rb
# db/migrations/004_add_fact_embeddings.rb
# db/migrations/005_add_incremental_sync.rb
# db/migrations/006_add_operation_tracking.rb
# db/migrations/007_add_ingestion_metrics.rb
```

### Critical Issues Remaining

#### 🔴 JSON Functions Break Sequel Abstraction (infrastructure/operation_tracker.rb:114-117, 136-139)

**Problem:** Using raw SQLite JSON functions instead of Sequel abstractions:

```ruby
# operation_tracker.rb:111-118
stuck.update(
  status: "failed",
  completed_at: now,
  checkpoint_data: Sequel.function(:json_set,
    Sequel.function(:coalesce, :checkpoint_data, "{}"),
    "$.error",
    "Reset by recover command - operation exceeded 24h timeout")
)

# operation_tracker.rb:133-140
@store.db[:operation_progress]
  .where(operation_type: operation_type, scope: scope, status: "running")
  .where { started_at < threshold_time }
  .update(
    status: "failed",
    completed_at: now,
    checkpoint_data: Sequel.function(:json_set,
      Sequel.function(:coalesce, :checkpoint_data, "{}"),
      "$.error",
      "Automatically marked as failed - operation exceeded 24h timeout")
  )
```

**Issues:**
- Breaks Sequel's database abstraction
- SQLite-specific (not portable)
- Hard to test
- Complex nested function calls
- Can't easily mock for testing

**Jeremy Evans Would Say:** "Handle JSON in Ruby. Use the database for storage, not logic."

**Recommended Fix:**
```ruby
# Option 1: Handle JSON in Ruby (preferred)
def reset_stuck_operations(operation_type: nil, scope: nil)
  # ... setup dataset ...

  # Fetch, modify, save
  stuck.all.each do |op|
    checkpoint = op[:checkpoint_data] ? JSON.parse(op[:checkpoint_data]) : {}
    checkpoint["error"] = "Reset by recover command - operation exceeded 24h timeout"

    @store.db[:operation_progress]
      .where(id: op[:id])
      .update(
        status: "failed",
        completed_at: now,
        checkpoint_data: JSON.generate(checkpoint)
      )
  end

  stuck.count
end

# Option 2: Use Sequel's JSON plugin (if available for SQLite)
Sequel.extension :sqlite_json_ops

# Then use Sequel's JSON operations
checkpoint_data: Sequel.pg_jsonb(:checkpoint_data).set(["error"], message)
```

**Estimated Effort:** 0.5 days

#### 🔴 String Timestamps Everywhere (Throughout codebase)

**Problem:** Using ISO8601 strings instead of DateTime columns:

```ruby
# sqlite_store.rb:95
now = Time.now.utc.iso8601

# sqlite_store.rb:165-166
now = Time.now.utc.iso8601
entities.insert(type: type, canonical_name: name, slug: slug, created_at: now)

# operation_tracker.rb:17
now = Time.now.utc.iso8601

# Schema uses String columns for timestamps everywhere
```

**Issues:**
- String comparison fragile (requires ISO8601 format)
- No timezone enforcement at DB level
- Manual conversion everywhere (Time.now.utc.iso8601 appears 20+ times)
- Can't use Sequel's date operations
- More storage than integer timestamps
- Harder to do date arithmetic

**Jeremy Evans Would Say:** "Use DateTime columns and let Sequel handle conversions."

**Recommended Fix:**
```ruby
# Migration to convert string timestamps to DateTime
Sequel.migration do
  up do
    # For each table with timestamp strings:
    # 1. Add new DateTime column
    # 2. Copy and parse data
    # 3. Drop old column
    # 4. Rename new column

    alter_table(:content_items) do
      add_column :occurred_at_dt, DateTime
      add_column :ingested_at_dt, DateTime
    end

    # Batch convert strings to DateTime
    self[:content_items].all.each do |row|
      self[:content_items].where(id: row[:id]).update(
        occurred_at_dt: Time.parse(row[:occurred_at]),
        ingested_at_dt: Time.parse(row[:ingested_at])
      )
    end

    alter_table(:content_items) do
      drop_column :occurred_at
      drop_column :ingested_at
      rename_column :occurred_at_dt, :occurred_at
      rename_column :ingested_at_dt, :ingested_at
    end
  end

  down do
    # Reverse conversion
  end
end

# Then use Sequel's automatic timestamp handling
plugin :timestamps, update_on_create: true

# And use Sequel's date operations
.where { occurred_at > Time.now - 86400 }
```

**Estimated Effort:** 1-2 days (migration + testing)

#### 🟡 WAL Mode Enabled (Good!) but Missing Checkpoint Management

**Positive Observation:**
```ruby
# sqlite_store.rb:22-28
@db.run("PRAGMA journal_mode = WAL")
@db.run("PRAGMA synchronous = NORMAL")
@db.run("PRAGMA busy_timeout = 5000")
```

**Recommendation:** Add periodic WAL checkpoint to prevent unlimited WAL growth:
```ruby
# Add method to SQLiteStore
def checkpoint_wal
  @db.run("PRAGMA wal_checkpoint(TRUNCATE)")
end

# Call periodically in sweep or maintenance
```

**Estimated Effort:** 0.25 days

---

## 3. Kent Beck Perspective (TDD, XP, Simple Design)

### What's Been Fixed Since Last Review ✅

- ✅ **DoctorCommand simplified** - 174 → 31 lines, clear delegation
- ✅ **Check classes extracted** - Each with single responsibility
- ✅ **FactRanker extracted** - Pure testable logic

**Evidence:**
```ruby
# commands/doctor_command.rb:8-27 (Beautiful simplicity!)
def call(_args)
  manager = ClaudeMemory::Store::StoreManager.new

  checks = [
    Checks::DatabaseCheck.new(manager.global_db_path, "global"),
    Checks::DatabaseCheck.new(manager.project_db_path, "project"),
    Checks::SnapshotCheck.new,
    Checks::ClaudeMdCheck.new,
    Checks::HooksCheck.new
  ]

  results = checks.map(&:call)

  manager.close

  reporter = Checks::Reporter.new(stdout, stderr)
  success = reporter.report(results)

  success ? 0 : 1
end
```

**Kent Beck Would Say:** "This is what simple design looks like."

### Issues Remaining

#### 🔴 Complex Conditional Logic Still Present (recall.rb:42-106)

**Problem:** Every public method starts with mode-based routing:

```ruby
# recall.rb:42-48
def query(query_text, limit: 10, scope: SCOPE_ALL)
  if @legacy_mode
    query_legacy(query_text, limit: limit, scope: scope)
  else
    query_dual(query_text, limit: limit, scope: scope)
  end
end

# This repeats for 10+ methods
```

**Kent Beck Would Say:** "Conditionals are not polymorphism. Use polymorphism to eliminate conditionals."

**Recommended Fix:** Strategy pattern (see Sandi Metz section)

**Estimated Effort:** 2-3 days

#### 🟡 Side Effects in Constructor Still Present (index/lexical_fts.rb:6-10)

**Problem:** Constructor has database side effect:

```ruby
# index/lexical_fts.rb:6-10
def initialize(store)
  @store = store
  @db = store.db
  ensure_fts_table!  # Side effect!
end
```

**Kent Beck Would Say:** "Constructors should just construct. Move side effects to explicit methods."

**Recommended Fix:**
```ruby
def initialize(store)
  @store = store
  @db = store.db
end

# Lazy initialization
def index_content_item(content_item_id, text)
  ensure_fts_table!  # Create on first use
  # ... indexing logic
end

# Or better: Separate schema setup
def self.setup_schema(db)
  db.create_table?(:fts_index) do
    # ...
  end
end

# Then in migrations or setup:
LexicalFTS.setup_schema(db)
```

**Estimated Effort:** 0.5 days

#### 🟡 Reveal Intent Through Naming (Throughout codebase)

**Good Examples Found:**
```ruby
# Good: Clear intent
def batch_find_facts(store, fact_ids)
def dedupe_by_fact_id(results, limit)
def facts_by_branch(branch_name, limit: 20, scope: SCOPE_ALL)
```

**Needs Improvement:**
```ruby
# Unclear: What does "apply" do?
def apply(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")

# Better:
def resolve_and_store_extraction(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")

# Unclear: What is "call"?
def call(args)

# Better: Name after what it does
def perform_health_check(args)
def recall_matching_facts(params)
```

**Estimated Effort:** 0.5 days

---

## 4. Avdi Grimm Perspective (Confident Ruby)

### What's Been Fixed Since Last Review ✅

- ✅ **Null objects exist** - NullFact, NullExplanation
- ✅ **Result objects used** - Core::Result for success/failure
- ✅ **FactRanker extracted** - Pure value transformations

### Issues Remaining

#### 🔴 Inconsistent Return Values (Throughout codebase)

**Problem:** Methods return different types on success vs failure:

```ruby
# Returns array or nil
def explain(fact_id, scope: nil)
  # ...
  return nil unless fact  # Nil on not found
  {
    fact: fact,
    receipts: receipts
  }
end

# Returns integer ID or raises
def insert_fact(...)
  facts.insert(...)  # Returns ID on success, raises on error
end

# Returns boolean
def update_fact(fact_id, ...)
  # ...
  return false if updates.empty?
  facts.where(id: fact_id).update(updates)
  true
end
```

**Avdi Grimm Would Say:** "Return objects that understand their role. Use Result objects consistently."

**Recommended Fix:**
```ruby
# Use Result consistently
module ClaudeMemory
  module Domain
    class StoreResult
      def self.success(value)
        Success.new(value)
      end

      def self.not_found(message = "Not found")
        NotFound.new(message)
      end

      def self.error(message)
        Error.new(message)
      end
    end

    class Success < StoreResult
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def success? = true
      def error? = false
      def not_found? = false
    end

    class Error < StoreResult
      attr_reader :message

      def initialize(message)
        @message = message
      end

      def success? = false
      def error? = true
      def not_found? = false
    end

    class NotFound < StoreResult
      attr_reader :message

      def initialize(message)
        @message = message
      end

      def success? = false
      def error? = false
      def not_found? = true
    end
  end
end

# Usage
def insert_fact(...)
  id = facts.insert(...)
  StoreResult.success(id)
rescue Sequel::UniqueConstraintViolation => e
  StoreResult.error("Duplicate fact: #{e.message}")
end

def explain(fact_id, scope: nil)
  fact = find_fact(fact_id, scope)
  return StoreResult.not_found("Fact #{fact_id} not found") unless fact

  receipts = provenance_for_fact(fact_id)
  StoreResult.success({fact: fact, receipts: receipts})
end

# Client code
result = store.insert_fact(...)

case result
when StoreResult::Success
  puts "Inserted fact ##{result.value}"
when StoreResult::Error
  stderr.puts "Error: #{result.message}"
end
```

**Estimated Effort:** 1-2 days

#### 🟡 Primitive Obsession - Hashes Still Used (recall.rb)

**Problem:** Domain concepts returned as hashes:

```ruby
# recall.rb returns raw hashes
{
  fact: {
    id: 123,
    subject_entity_id: 456,
    predicate: "uses_database",
    object_literal: "PostgreSQL",
    confidence: 0.95
  },
  receipts: [
    {fact_id: 123, quote: "We use PostgreSQL", strength: "stated"}
  ],
  source: :project,
  score: 0.85
}
```

**Avdi Grimm Would Say:** "Give your data behavior. Turn hashes into objects."

**Recommended Fix:**
```ruby
module ClaudeMemory
  module Domain
    class RecallResult
      attr_reader :fact, :receipts, :source, :score

      def initialize(fact:, receipts:, source:, score: nil)
        @fact = Fact.from_hash(fact)
        @receipts = receipts.map { |r| Provenance.from_hash(r) }
        @source = source
        @score = score
      end

      def relevant?
        score && score > 0.7
      end

      def high_confidence?
        fact.high_confidence?
      end

      def from_project?
        source == :project
      end

      def from_global?
        source == :global
      end

      def to_hash
        {
          fact: fact.to_hash,
          receipts: receipts.map(&:to_hash),
          source: source,
          score: score
        }
      end
    end
  end
end

# Usage
results = recall.query("PostgreSQL").map { |r| Domain::RecallResult.new(**r) }

results.select(&:relevant?).each do |result|
  if result.high_confidence?
    puts "✓ #{result.fact.summary}"
  end
end
```

**Estimated Effort:** 1 day

#### 🟡 Tell, Don't Ask Violations (Various files)

**Examples Found:**
```ruby
# Asking about state then acting
if fact[:status] == "active"
  process_fact(fact)
end

# Better: Tell the object what to do
if fact.active?
  fact.process
end

# Asking then modifying
if result[:source] == :project
  priority = 0
else
  priority = 1
end

# Better: Ask the object
priority = result.source_priority
```

**Recommended:** Move logic into domain objects where possible.

**Estimated Effort:** 0.5 days

---

## 5. Gary Bernhardt Perspective (Boundaries, Fast Tests)

### What's Been Fixed Since Last Review ✅

- ✅ **FactRanker extracted** - Pure logic with no I/O (Perfect functional core!)
- ✅ **Check classes** - Good separation of concerns
- ✅ **FileSystem abstraction** - InMemoryFileSystem for testing

**Evidence:**
```ruby
# core/fact_ranker.rb:1-90
# Pure business logic - no database, no I/O
class FactRanker
  def self.dedupe_and_sort_index(results, limit)
    seen_signatures = Set.new
    unique_results = []

    results.each do |result|
      sig = "#{result[:subject]}:#{result[:predicate]}:#{result[:object_preview]}"
      next if seen_signatures.include?(sig)

      seen_signatures.add(sig)
      unique_results << result
    end

    unique_results.sort_by { |item|
      source_priority = (item[:source] == :project) ? 0 : 1
      [source_priority]
    }.first(limit)
  end
end
```

**Gary Bernhardt Would Say:** "This is perfect. Pure logic, no I/O, fast tests."

### Issues Remaining

#### 🔴 Recall Mixes I/O with Logic (recall.rb:701-748)

**Problem:** Semantic search mixes database queries with ranking logic:

```ruby
# recall.rb:701-748
def query_concepts_single(store, concepts, limit:, source:)
  # I/O: Search each concept independently
  concept_results = concepts.map do |concept|
    search_by_vector(store, concept, limit * 5, source)  # Database I/O
  end

  # Logic: Build fact map
  fact_map = Hash.new { |h, k| h[k] = [] }

  concept_results.each_with_index do |results, concept_idx|
    results.each do |result|
      fact_id = result[:fact][:id]
      fact_map[fact_id] << {
        result: result,
        concept_idx: concept_idx,
        similarity: result[:similarity] || 0.0
      }
    end
  end

  # Logic: Filter to facts matching ALL concepts
  multi_concept_facts = fact_map.select do |_fact_id, matches|
    represented_concepts = matches.map { |m| m[:concept_idx] }.uniq
    represented_concepts.size == concepts.size
  end

  return [] if multi_concept_facts.empty?

  # Logic: Rank by average similarity
  ranked = multi_concept_facts.map do |fact_id, matches|
    similarities = matches.map { |m| m[:similarity] }
    avg_similarity = similarities.sum / similarities.size.to_f
    # ... more logic
  end

  ranked.sort_by { |r| -r[:similarity] }.take(limit)
end
```

**Gary Bernhardt Would Say:** "Push I/O to the edges. Keep the core pure."

**Recommended Fix:**
```ruby
# Core - Pure logic (lib/claude_memory/core/concept_ranker.rb)
module ClaudeMemory
  module Core
    class ConceptRanker
      # Pure function: no I/O, just transformations
      def self.rank_by_concepts(concept_results, concepts, limit)
        fact_map = build_fact_map(concept_results)
        multi_concept_facts = filter_by_all_concepts(fact_map, concepts.size)
        return [] if multi_concept_facts.empty?

        rank_by_average_similarity(multi_concept_facts, limit)
      end

      private

      def self.build_fact_map(concept_results)
        fact_map = Hash.new { |h, k| h[k] = [] }

        concept_results.each_with_index do |results, concept_idx|
          results.each do |result|
            fact_id = result[:fact][:id]
            fact_map[fact_id] << {
              result: result,
              concept_idx: concept_idx,
              similarity: result[:similarity] || 0.0
            }
          end
        end

        fact_map
      end

      def self.filter_by_all_concepts(fact_map, expected_concept_count)
        fact_map.select do |_fact_id, matches|
          represented_concepts = matches.map { |m| m[:concept_idx] }.uniq
          represented_concepts.size == expected_concept_count
        end
      end

      def self.rank_by_average_similarity(multi_concept_facts, limit)
        ranked = multi_concept_facts.map do |fact_id, matches|
          similarities = matches.map { |m| m[:similarity] }
          avg_similarity = similarities.sum / similarities.size.to_f

          first_match = matches.first[:result]

          {
            fact: first_match[:fact],
            receipts: first_match[:receipts],
            similarity: avg_similarity,
            concept_similarities: similarities
          }
        end

        ranked.sort_by { |r| -r[:similarity] }.take(limit)
      end
    end
  end
end

# Shell - Handles I/O (lib/claude_memory/recall/concept_search.rb)
module ClaudeMemory
  module Recall
    class ConceptSearch
      def initialize(store)
        @store = store
      end

      def call(concepts, limit:, source:)
        # I/O: Fetch all concept results
        concept_results = concepts.map do |concept|
          search_by_vector(@store, concept, limit * 5, source)
        end

        # Pure: Rank results
        Core::ConceptRanker.rank_by_concepts(concept_results, concepts, limit)
      end

      private

      def search_by_vector(store, concept, limit, source)
        # Database query
      end
    end
  end
end
```

**Benefits:**
- `ConceptRanker` tests run in < 1ms (no database)
- Easy to test edge cases (empty results, identical similarities, etc.)
- Logic can be reused in different contexts
- Clear separation of concerns

**Estimated Effort:** 1 day

#### 🟡 Mutable Instance Variables (resolver.rb, recall.rb)

**Problem:** State stored in instance variables:

```ruby
# resolver.rb (resolved in previous review, but pattern remains elsewhere)
def apply(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")
  @current_project_path = project_path  # Mutable state
  @current_scope = scope                # Mutable state
  # ...
end
```

**Gary Bernhardt Would Say:** "Prefer immutable data. Pass context explicitly."

**Recommended Fix:**
```ruby
class ResolutionContext
  attr_reader :project_path, :scope, :occurred_at, :content_item_id

  def initialize(project_path:, scope:, occurred_at:, content_item_id:)
    @project_path = project_path
    @scope = scope
    @occurred_at = occurred_at
    @content_item_id = content_item_id
    freeze  # Immutable
  end
end

def apply(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")
  context = ResolutionContext.new(
    project_path: project_path,
    scope: scope,
    occurred_at: occurred_at || Time.now.utc.iso8601,
    content_item_id: content_item_id
  )

  resolve_with_context(extraction, context)
end

private

def resolve_with_context(extraction, context)
  # Pass context instead of reading instance variables
end
```

**Estimated Effort:** 0.5 days

---

## 6. General Ruby Idioms and Style

### ✅ What's Working Well

1. **Frozen string literals** - Consistent across all files
2. **Module namespacing** - Clean organization
3. **Sequel usage** - Generally good dataset methods
4. **Standard Ruby** - Consistent code style
5. **Documentation** - Good inline comments where needed

### 🟡 Minor Issues

#### Method Visibility (sqlite_store.rb)

**Good News:** No more mid-class `public` keyword! Visibility is clean.

```ruby
# All public methods at top
def initialize(db_path)
def close
def upsert_content_item(...)
# ... more public methods ...

# All private at bottom
private

def ensure_schema!
def migrate_from_legacy_pragma!
# ... more private methods ...
```

**Status:** ✅ Fixed

#### ENV Access Centralized (Throughout)

**Observation:** Configuration class exists and is being used:

```ruby
# recall.rb:28
config = Configuration.new(env)
@project_path = project_path || config.project_dir
```

**Status:** ✅ Improving - Good use of Configuration class

---

## 7. Positive Observations

### ✅ Major Architectural Wins

1. **Command Pattern** - CLI remains at 41 lines, command classes work well
2. **Domain Objects** - Fact, Entity, Provenance, Conflict properly implemented
3. **Value Objects** - SessionId, TranscriptPath, FactId, Result classes
4. **Null Objects** - NullFact, NullExplanation eliminate nil checks
5. **Infrastructure Abstraction** - FileSystem/InMemoryFileSystem
6. **FactRanker** - Perfect example of functional core (Gary Bernhardt)
7. **DoctorCommand** - Now exemplar of simplicity (31 lines)
8. **Migrations** - Proper Sequel migration system with rollback support
9. **Check Classes** - Good separation in DoctorCommand refactoring
10. **WAL Mode** - Good concurrency setup

### ✅ Code Quality Improvements

- Transaction safety in critical operations
- Good test coverage (64+ spec files)
- Excellent README and documentation
- Consistent code style with Standard Ruby
- Good use of Sequel's dataset methods
- FTS integration working well
- Dual-database design is sound

---

## 8. Priority Refactoring Recommendations

### High Priority (This Week)

#### 1. Split Recall.rb God Object 🔴 CRITICAL

**Target:** Reduce from 754 lines to < 150 lines for main coordinator

**Actions:**
- Extract `Recall::DualStoreStrategy` (~300 lines)
- Extract `Recall::LegacyStoreStrategy` (~300 lines)
- Extract `Recall::FtsSearch` (~100 lines)
- Extract `Recall::SemanticSearch` (~150 lines)
- Extract `Recall::ConceptSearch` (~100 lines)
- Extract `Recall::ResultFormatter` (~100 lines)

**Estimated Effort:** 2-3 days

**Priority:** 🔴 Critical - This is the largest god object

#### 2. Refactor MCP Tools.rb 🔴 CRITICAL

**Target:** Reduce from 1,039 lines to < 100 lines for registry

**Actions:**
- Split into individual tool files (17 files × ~60 lines each)
- Extract `MCP::Tools::BaseTool` for shared behavior
- Extract `MCP::Tools::Formatter` for result formatting
- Create tool registry in `MCP::Server`

**Estimated Effort:** 2 days

**Priority:** 🔴 Critical - File is growing, needs immediate attention

#### 3. Fix JSON Functions in OperationTracker 🔴

**Target:** Remove raw SQL JSON functions

**Actions:**
- Replace `Sequel.function(:json_set, ...)` with Ruby JSON handling
- Fetch checkpoint data, modify in Ruby, save back
- Add tests for checkpoint error handling

**Estimated Effort:** 0.5 days

**Priority:** 🔴 Critical - Breaks Sequel abstraction

### Medium Priority (Next Week)

#### 4. Extract ConceptRanker to Core 🟡

**Target:** Separate I/O from logic in concept search

**Actions:**
- Create `Core::ConceptRanker` with pure logic
- Create `Recall::ConceptSearch` for I/O shell
- Add fast tests for ConceptRanker (no database)

**Estimated Effort:** 1 day

**Priority:** 🟡 Medium - Improves testability

#### 5. Implement Result Objects Consistently 🟡

**Target:** Replace nil returns with Result objects

**Actions:**
- Create `Domain::StoreResult` hierarchy
- Update all store methods to return Result
- Update all recall methods to return Result
- Update tests

**Estimated Effort:** 1-2 days

**Priority:** 🟡 Medium - Improves error handling

#### 6. Convert String Timestamps to DateTime 🟡

**Target:** Use proper DateTime columns throughout

**Actions:**
- Write migration to convert all timestamp columns
- Update code to use Sequel's automatic timestamp handling
- Remove manual `Time.now.utc.iso8601` calls
- Enable `timestamps` plugin

**Estimated Effort:** 1-2 days

**Priority:** 🟡 Medium - Database best practice

### Low Priority (Later)

#### 7. Create RecallResult Domain Object 🔵

**Target:** Replace result hashes with domain objects

**Actions:**
- Create `Domain::RecallResult` class
- Add behavior methods (relevant?, high_confidence?)
- Update formatters to use domain object

**Estimated Effort:** 1 day

**Priority:** 🔵 Low - Nice to have

#### 8. Add WAL Checkpoint Management 🔵

**Target:** Prevent unlimited WAL growth

**Actions:**
- Add `checkpoint_wal` method to SQLiteStore
- Call during sweep/maintenance
- Add tests

**Estimated Effort:** 0.25 days

**Priority:** 🔵 Low - Operational improvement

#### 9. Fix Constructor Side Effects 🔵

**Target:** Remove side effects from LexicalFTS constructor

**Actions:**
- Move `ensure_fts_table!` to lazy initialization
- Or create class method for schema setup
- Update tests

**Estimated Effort:** 0.5 days

**Priority:** 🔵 Low - Small improvement

---

## 9. Conclusion

**Outstanding progress continues!** The team has successfully addressed major architectural debt:

### Key Achievements Since Jan 26

1. ✅ **Migrations refactored** - Now using proper Sequel migration files
2. ✅ **DoctorCommand refactored** - 174 → 31 lines with check classes
3. ✅ **FactRanker extracted** - Perfect functional core example
4. ✅ **Recall reduced** - 914 → 754 lines (17% improvement)
5. ✅ **SQLiteStore reduced** - 542 → 383 lines (29% improvement)

### Critical Next Steps

**Recall.rb remains the primary god object** at 754 lines with 58 methods. Despite improvement, it still handles 10+ responsibilities. The same refactoring strategy that worked for CLI and DoctorCommand should be applied here.

**MCP Tools.rb is growing** and needs immediate attention before it becomes harder to refactor.

### Summary by Expert

| Expert | Status | Key Issues |
|--------|--------|------------|
| **Sandi Metz** | 🟡 Good | Recall still god object, MCP Tools growing |
| **Jeremy Evans** | ✅ Excellent | Migrations fixed! Minor JSON function issue remains |
| **Kent Beck** | ✅ Good | DoctorCommand exemplar, Recall needs polymorphism |
| **Avdi Grimm** | 🟡 Good | Need Result objects, eliminate primitive obsession |
| **Gary Bernhardt** | ✅ Excellent | FactRanker perfect! Extract more pure logic |

### Risk Assessment

**Low risk.** The refactoring pattern is proven (CLI → DoctorCommand → Recall). The test suite provides safety. The team has demonstrated capability.

### Estimated Total Effort

- **High priority:** 5-6 days (1 developer)
- **Medium priority:** 4-5 days (1 developer)
- **Low priority:** 2 days (1 developer)
- **Total:** 11-13 days for comprehensive refactoring

### Recommendation

**Start with Recall.rb refactoring immediately.** Use the same strategy that worked for DoctorCommand:

1. Extract strategy classes
2. Run tests after each extraction
3. Celebrate small wins
4. Measure progress (lines of code, method count)

The codebase is in excellent shape with a clear path forward.

---

## Appendix A: Metrics Comparison

| Metric | Jan 26, 2026 | Jan 27, 2026 | Change |
|--------|--------------|--------------|--------|
| CLI lines | 41 | 41 | ✅ Stable |
| Command classes | 16 | 16 | ✅ Stable |
| Recall lines | 914 | 754 | ✅ -17% |
| Recall methods | 57 | 58 | 🟡 +1 |
| MCP Tools lines | 901 | 1,039 | 🔴 +15% |
| SQLiteStore lines | 542 | 383 | ✅ -29% |
| DoctorCommand lines | 174 | 31 | ✅ -82% |
| Check classes | 0 | 5 | ✅ +5 |
| Migration files | 0 | 7 | ✅ +7 |
| Domain objects | 4 | 4 | ✅ Stable |
| Value objects | 4 | 4 | ✅ Stable |
| Null objects | 2 | 2 | ✅ Stable |
| God objects | 2 | 2 | 🟡 Same (Recall, MCP Tools) |
| Pure logic classes | 0 | 1 (FactRanker) | ✅ +1 |

**Key Insights:**
- ✅ **Excellent:** SQLiteStore (-29%), DoctorCommand (-82%), Migrations system
- ✅ **Good:** Recall reduced 17%, FactRanker extracted
- 🔴 **Concern:** MCP Tools growing +15%
- 🟡 **Watch:** Recall still too large despite improvement

---

## Appendix B: Quick Wins (Can Do Today)

1. **Fix JSON functions in OperationTracker** (2 hours)
   - Replace `Sequel.function(:json_set)` with Ruby JSON handling
   - Two locations: lines 114-117 and 136-139

2. **Add WAL checkpoint management** (1 hour)
   - Add `checkpoint_wal` method to SQLiteStore
   - Call during sweep operations

3. **Extract ResultFormatter from Recall** (2 hours)
   - Create `Recall::ResultFormatter` class
   - Move all formatting logic

4. **Create BaseTool for MCP** (2 hours)
   - Extract shared behavior from tool implementations
   - Reduce duplication in tool classes

5. **Add ConceptRanker to Core** (3 hours)
   - Extract pure logic from `query_concepts_single`
   - Add fast tests

**Total quick wins:** ~10 hours, significant impact

---

## Appendix C: File Size Report

**Largest Files (> 500 lines):**
- `lib/claude_memory/mcp/tools.rb` - **1,039 lines** 🔴 (up 15%)
- `lib/claude_memory/recall.rb` - **754 lines** 🔴 (down 17%)

**Medium Files (200-500 lines):**
- `lib/claude_memory/store/sqlite_store.rb` - 383 lines ✅ (down 29%)

**Well-Sized Files (< 200 lines):**
- `lib/claude_memory/cli.rb` - 41 lines ✅
- `lib/claude_memory/commands/doctor_command.rb` - 31 lines ✅
- `lib/claude_memory/core/fact_ranker.rb` - 90 lines ✅
- Most command files - 30-115 lines ✅
- Check classes - 30-115 lines each ✅
- Domain objects - 30-80 lines ✅
- Value objects - 20-40 lines ✅

**Migration Files:**
- `db/migrations/*.rb` - 7 files (596-3,617 bytes each) ✅

---

## Appendix D: Test Coverage Analysis

**Test Files:** 64+ spec files

**Well-Tested Areas:**
- ✅ Commands (all 16 commands have tests)
- ✅ Domain objects (Fact, Entity, Provenance, Conflict)
- ✅ Value objects (SessionId, TranscriptPath, FactId)
- ✅ Store operations (SQLiteStore)
- ✅ FactRanker (pure logic, fast tests)

**Needs More Tests:**
- 🟡 Failure modes (database failures, constraint violations)
- 🟡 Concurrent access scenarios
- 🟡 Migration rollback testing
- 🟡 Edge cases in semantic search
- 🟡 MCP tool error handling

**Test Performance:**
- ✅ Most tests run fast (< 100ms)
- ✅ Good use of InMemoryFileSystem for speed
- ✅ FactRanker tests are pure (< 1ms each)
- 🟡 Some integration tests could be faster

---

## Appendix E: Debt Tracking

**Technical Debt Paid Off:**
- ✅ CLI god object (867 → 41 lines)
- ✅ Manual migrations (replaced with Sequel::Migrator)
- ✅ DoctorCommand (174 → 31 lines)
- ✅ No FactRanker extraction (now extracted)

**Technical Debt Incurred:**
- 🔴 MCP Tools.rb growing (901 → 1,039 lines)

**Technical Debt Remaining:**
- 🔴 Recall.rb god object (754 lines, 58 methods)
- 🔴 JSON functions in OperationTracker
- 🟡 String timestamps throughout
- 🟡 Inconsistent return values
- 🟡 Primitive obsession (hashes vs objects)

**Debt Trend:** ✅ **Positive** - More debt paid off than incurred

---

**Review completed:** 2026-01-27
**Reviewed by:** Claude Code (via critical analysis through expert perspectives)
**Next review:** Recommend after Recall.rb and MCP Tools refactoring (estimated 1-2 weeks)

