# Code Quality Review - Ruby Best Practices

**Reviewed by perspectives of:** Sandi Metz, Jeremy Evans, Kent Beck, Avdi Grimm, Gary Bernhardt

**Review Date:** 2026-01-21

---

## Executive Summary

This codebase demonstrates good fundamentals with frozen string literals, consistent use of Sequel, and reasonable test coverage. However, there are significant opportunities for improvement in object-oriented design, separation of concerns, and adherence to Ruby idioms. The most critical issues center around:

1. **CLI God Object** - 867-line class with too many responsibilities
2. **Mixed Concerns** - I/O interleaved with business logic throughout
3. **Inconsistent Database Practices** - Mix of Sequel datasets and raw SQL
4. **Lack of Domain Objects** - Primitive obsession with hashes
5. **State Management** - Mutable instance variables where immutability preferred

---

## 1. Sandi Metz Perspective (POODR)

### Focus Areas
- Single Responsibility Principle
- Small, focused methods
- Clear dependencies
- DRY principle
- High test coverage

### Critical Issues

#### 🔴 CLI God Object (cli.rb:1-867)

**Problem:** The CLI class has 867 lines and handles parsing, validation, execution, database management, configuration, output formatting, and error handling.

**Violations:**
- Single Responsibility Principle violated
- Too many public methods (18+ commands)
- Too many private methods (20+)
- Methods > 10 lines (doctor_cmd, init_local, configure_global_hooks, etc.)

**Example:**
```ruby
# cli.rb:689-743 - doctor_cmd does too much
def doctor_cmd
  issues = []
  warnings = []

  # Database checking
  # File system checking
  # Config validation
  # Conflict detection
  # Output formatting
  # Error handling
end
```

**Recommended Fix:**
Extract command objects:
```ruby
# lib/claude_memory/commands/doctor.rb
module ClaudeMemory
  module Commands
    class Doctor
      def initialize(store_manager, reporter:)
        @store_manager = store_manager
        @reporter = reporter
      end

      def call
        checks = [
          DatabaseCheck.new(@store_manager),
          SnapshotCheck.new,
          HooksCheck.new
        ]

        results = checks.map(&:call)
        @reporter.report(results)
      end
    end
  end
end
```

#### 🔴 Long Methods Throughout

**Problem:** Many methods exceed 10-15 lines, making them hard to understand and test.

**Examples:**
- `cli.rb:689-743` - `doctor_cmd` (55 lines)
- `cli.rb:536-565` - `init_local` (30 lines)
- `cli.rb:586-601` - `configure_global_hooks` (16 lines)
- `recall.rb:58-78` - `query_dual` (21 lines)

**Recommended Fix:**
Break into smaller, well-named private methods:
```ruby
def doctor_cmd
  results = run_health_checks
  display_results(results)
  exit_code_from(results)
end

private

def run_health_checks
  [
    check_global_database,
    check_project_database,
    check_snapshot,
    check_hooks
  ]
end
```

#### 🟡 Duplicated Attribute Readers (store_manager.rb:47-49)

**Problem:**
```ruby
attr_reader :global_store, :project_store, :project_path  # line 8

# ... later ...

attr_reader :global_db_path  # line 47
attr_reader :project_db_path  # line 49
```

**Fix:** Consolidate at the top of the class.

#### 🟡 Multiple Responsibilities in Recall Class

**Problem:** Recall handles both legacy single-store mode and dual-database mode (recall.rb:9-20).

**Violations:**
- Two modes = two responsibilities
- Conditional logic based on mode throughout
- Hard to reason about which path executes

**Recommended Fix:**
Create separate classes:
```ruby
class LegacyRecall
  # Single store logic only
end

class DualRecall
  # Dual store logic only
end

# Factory
def self.build(store_or_manager)
  if store_or_manager.is_a?(Store::StoreManager)
    DualRecall.new(store_or_manager)
  else
    LegacyRecall.new(store_or_manager)
  end
end
```

#### 🟡 Inconsistent Visibility (sqlite_store.rb:204)

**Problem:**
```ruby
private  # line 59

# ... private methods ...

public   # line 204

def upsert_content_item(...)
```

**Recommended:** Keep all public methods together at the top, all private at the bottom.

---

## 2. Jeremy Evans Perspective (Sequel Expert)

### Focus Areas
- Proper Sequel usage patterns
- Database performance
- Schema design
- Connection management

### Critical Issues

#### 🔴 Raw SQL Instead of Sequel Datasets (cli.rb:752-764)

**Problem:**
```ruby
fact_count = store.db.execute("SELECT COUNT(*) FROM facts").first.first
content_count = store.db.execute("SELECT COUNT(*) FROM content_items").first.first
conflict_count = store.db.execute("SELECT COUNT(*) FROM conflicts WHERE status = 'open'").first.first
last_ingest = store.db.execute("SELECT MAX(ingested_at) FROM content_items").first.first
```

**Violations:**
- Bypasses Sequel's dataset API
- Inconsistent with rest of codebase
- No type casting or safety checks
- Raw SQL is harder to test

**Recommended Fix:**
```ruby
fact_count = store.facts.count
content_count = store.content_items.count
conflict_count = store.conflicts.where(status: 'open').count
last_ingest = store.content_items.max(:ingested_at)
```

#### 🔴 No Transaction Wrapping (store_manager.rb:79-122)

**Problem:** `promote_fact` performs multiple database writes without transaction:
```ruby
def promote_fact(fact_id)
  ensure_both!

  fact = @project_store.facts.where(id: fact_id).first
  # ... multiple inserts across two databases
  global_fact_id = @global_store.insert_fact(...)
  copy_provenance(fact_id, global_fact_id)

  global_fact_id
end
```

**Risk:** If `copy_provenance` fails, you have orphaned fact in global database.

**Recommended Fix:**
```ruby
def promote_fact(fact_id)
  ensure_both!

  @global_store.db.transaction do
    fact = @project_store.facts.where(id: fact_id).first
    return nil unless fact

    # ... inserts ...
  end
end
```

**Note:** Cross-database transactions are not atomic, but at least wrap single-DB operations.

#### 🔴 String Timestamps Instead of Time Objects

**Problem:** Throughout the codebase:
```ruby
String :created_at, null: false  # sqlite_store.rb:127
now = Time.now.utc.iso8601       # sqlite_store.rb:211
```

**Issues:**
- String comparison for dates is fragile
- No timezone enforcement at DB level
- Manual ISO8601 conversion everywhere
- Harder to query by date ranges

**Recommended Fix:**
```ruby
# Use DateTime columns
DateTime :created_at, null: false

# Use Sequel's timestamp plugin
Sequel.extension :date_arithmetic
plugin :timestamps, update_on_create: true
```

#### 🟡 No Connection Pooling Configuration

**Problem:** SQLite connections created without pooling options (sqlite_store.rb:15):
```ruby
@db = Sequel.sqlite(db_path)
```

**Recommendation:**
```ruby
@db = Sequel.connect(
  adapter: 'sqlite',
  database: db_path,
  max_connections: 4,
  pool_timeout: 5
)
```

#### 🟡 Manual Schema Migrations (sqlite_store.rb:68-91)

**Problem:** Hand-rolled migration system instead of Sequel's migration framework.

**Issues:**
- No rollback support
- No migration history
- Schema changes mixed with initialization

**Recommended:**
Use Sequel's migration extension:
```ruby
# db/migrations/001_initial_schema.rb
Sequel.migration do
  up do
    create_table(:entities) do
      primary_key :id
      String :type, null: false
      # ...
    end
  end

  down do
    drop_table(:entities)
  end
end

# In code:
Sequel::Migrator.run(@db, 'db/migrations')
```

#### 🟡 Sequel Plugins Not Used

**Problem:** No use of helpful Sequel plugins:
- `timestamps` - automatic created_at/updated_at
- `validation_helpers` - model validations
- `json_serializer` - better JSON handling
- `association_dependencies` - cascade deletes

**Example Benefit:**
```ruby
class Fact < Sequel::Model
  plugin :timestamps
  plugin :validation_helpers

  many_to_one :subject, class: :Entity
  one_to_many :provenance_records, class: :Provenance

  def validate
    super
    validates_presence [:subject_entity_id, :predicate]
  end
end
```

---

## 3. Kent Beck Perspective (TDD, XP, Simple Design)

### Focus Areas
- Test-first design
- Simple solutions
- Revealing intent
- Small steps
- Clear boundaries

### Critical Issues

#### 🔴 CLI Methods Untestable in Isolation

**Problem:** CLI methods create their own dependencies:
```ruby
def ingest
  opts = parse_ingest_options
  return 1 unless opts

  store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])  # Created here!
  ingester = ClaudeMemory::Ingest::Ingester.new(store)     # Created here!

  result = ingester.ingest(...)
  # ...
end
```

**Testing Issues:**
- Can't inject test double for store
- Must use real database for tests
- Slow integration tests required
- Hard to test error paths

**Recommended Fix:**
```ruby
def ingest(store: default_store)
  opts = parse_ingest_options
  return 1 unless opts

  ingester = ClaudeMemory::Ingest::Ingester.new(store)
  result = ingester.ingest(...)
  # ...
end

private

def default_store
  @default_store ||= ClaudeMemory::Store::SQLiteStore.new(opts[:db])
end
```

#### 🔴 Methods Don't Reveal Intent

**Problem:** `run` method is a giant case statement (cli.rb:14-58):
```ruby
def run
  command = @args.first || "help"

  case command
  when "help", "-h", "--help"
    print_help
    0
  when "version", "-v", "--version"
    print_version
    0
  # ... 15 more cases
  end
end
```

**Issues:**
- Doesn't reveal what the CLI does
- Adding commands requires modifying this method
- No clear command structure

**Recommended Fix:**
```ruby
def run
  command_name = extract_command_name
  command = find_command(command_name)
  command.call(arguments)
end

private

def find_command(name)
  COMMANDS.fetch(name) { UnknownCommand.new(name) }
end

COMMANDS = {
  'help' => Commands::Help.new(@stdout),
  'ingest' => Commands::Ingest.new(@stdout, @stderr),
  # ...
}
```

#### 🔴 Complex Boolean Logic (cli.rb:124-125)

**Problem:**
```ruby
opts[:global] = true if !opts[:global] && !opts[:project]
opts[:project] = true if !opts[:global] && !opts[:project]
```

**Issues:**
- Double negative logic
- Duplicate condition
- Intent unclear (setting both to true?)
- Bug: both will be true after these lines!

**Fix:**
```ruby
if !opts[:global] && !opts[:project]
  opts[:global] = true
  opts[:project] = true
end
```

Better:
```ruby
opts[:global] = opts[:project] = true if opts.values_at(:global, :project).none?
```

#### 🟡 Side Effects Hidden in Constructor (index/lexical_fts.rb:6-10)

**Problem:**
```ruby
def initialize(store)
  @store = store
  @db = store.db
  ensure_fts_table!  # Side effect!
end
```

**Issues:**
- Constructor has side effect (creates table)
- Violates Command-Query Separation
- Can't instantiate without modifying database
- Hard to test

**Recommended Fix:**
```ruby
def initialize(store)
  @store = store
  @db = store.db
end

def index_content_item(content_item_id, text)
  ensure_fts_table!  # Lazy initialization
  # ...
end
```

Or better: separate schema setup from usage.

#### 🟡 No Clear Separation of Concerns

**Problem:** Parser, validator, executor, formatter all in one method:
```ruby
def recall_cmd
  # Parse
  query = @args[1]

  # Validate
  unless query
    @stderr.puts "Usage: ..."
    return 1
  end

  # Parse options
  opts = {limit: 10, scope: "all"}
  OptionParser.new do |o|
    # ...
  end

  # Execute
  manager = ClaudeMemory::Store::StoreManager.new
  recall = ClaudeMemory::Recall.new(manager)
  results = recall.query(query, limit: opts[:limit], scope: opts[:scope])

  # Format
  if results.empty?
    @stdout.puts "No facts found."
  else
    results.each do |result|
      print_fact(result[:fact])
      # ...
    end
  end

  # Cleanup
  manager.close
  0
end
```

**Recommended:** Extract to separate objects (Parser, Validator, Executor, Formatter).

---

## 4. Avdi Grimm Perspective (Confident Ruby)

### Focus Areas
- Confident code
- Tell, don't ask
- Null object pattern
- Duck typing
- Meaningful return values

### Critical Issues

#### 🔴 Nil Checks Throughout (recall.rb)

**Problem:**
```ruby
def explain(fact_id, scope: nil)
  # ...
  explain_from_store(store, fact_id)
end

def explain_from_store(store, fact_id)
  fact = find_fact_from_store(store, fact_id)
  return nil unless fact  # Returning nil!

  {
    fact: fact,
    receipts: find_receipts_from_store(store, fact_id),
    # ...
  }
end
```

**Issues:**
- Caller must check for nil
- Forces defensive programming everywhere
- No clear "not found" semantics

**Recommended Fix:**
```ruby
class NullExplanation
  def fact
    NullFact.new
  end

  def receipts
    []
  end

  def present?
    false
  end
end

def explain_from_store(store, fact_id)
  fact = find_fact_from_store(store, fact_id)
  return NullExplanation.new unless fact

  Explanation.new(
    fact: fact,
    receipts: find_receipts_from_store(store, fact_id),
    # ...
  )
end
```

#### 🔴 Inconsistent Return Values

**Problem:** Different methods return different types:
```ruby
# Returns integer exit code
def ingest
  # ...
  0
end

# Returns hash
def promote_fact(fact_id)
  # ...
  global_fact_id
end

# Returns nil or hash
def explain_from_store(store, fact_id)
  return nil unless fact
  { fact: fact, ... }
end
```

**Issues:**
- No consistent interface
- Callers can't rely on duck typing
- Some return success/failure, others return values

**Recommended Fix:**
Use result objects:
```ruby
class Result
  def self.success(value)
    Success.new(value)
  end

  def self.failure(error)
    Failure.new(error)
  end
end

def promote_fact(fact_id)
  ensure_both!

  fact = @project_store.facts.where(id: fact_id).first
  return Result.failure("Fact not found") unless fact

  global_fact_id = # ... promotion logic
  Result.success(global_fact_id)
end
```

#### 🔴 Ask-Then-Do Pattern (publish.rb:165-171)

**Problem:**
```ruby
def should_write?(path, content)
  return true unless File.exist?(path)

  existing_hash = Digest::SHA256.file(path).hexdigest
  new_hash = Digest::SHA256.hexdigest(content)
  existing_hash != new_hash
end

# Usage:
if should_write?(path, content)
  File.write(path, content)
end
```

**Issues:**
- Asking for permission, then doing action
- Should just "tell" the object to write

**Recommended Fix:**
```ruby
class SmartWriter
  def write_if_changed(path, content)
    return :unchanged if unchanged?(path, content)

    File.write(path, content)
    :written
  end

  private

  def unchanged?(path, content)
    File.exist?(path) &&
      Digest::SHA256.file(path).hexdigest == Digest::SHA256.hexdigest(content)
  end
end
```

#### 🟡 Early Returns Scattered (resolver.rb:60-73)

**Problem:**
```ruby
def resolve_fact(fact_data, entity_ids, content_item_id, occurred_at)
  # ...
  if PredicatePolicy.single?(predicate) && existing_facts.any?
    matching = existing_facts.find { |f| values_match?(f, object_val, object_entity_id) }
    if matching
      add_provenance(matching[:id], content_item_id, fact_data)
      outcome[:provenance] = 1
      return outcome  # Early return 1
    elsif supersession_signal?(fact_data)
      supersede_facts(existing_facts, occurred_at)
      outcome[:superseded] = existing_facts.size
    else
      create_conflict(existing_facts.first[:id], fact_data, subject_id, content_item_id, occurred_at)
      outcome[:conflicts] = 1
      return outcome  # Early return 2
    end
  end

  # ... continues
end
```

**Issues:**
- Multiple exit points make flow hard to follow
- Hard to ensure cleanup
- Nested conditionals

**Recommended Fix:**
Extract to guard clauses at top:
```ruby
def resolve_fact(fact_data, entity_ids, content_item_id, occurred_at)
  outcome = build_outcome

  return handle_matching_fact(...) if matching_fact_exists?(...)
  return handle_conflict(...) if conflicts_with_existing?(...)

  create_new_fact(...)
end
```

#### 🟡 Primitive Obsession

**Problem:** Domain concepts represented as hashes:
```ruby
fact = {
  subject_name: "repo",
  predicate: "uses_database",
  object_literal: "PostgreSQL",
  status: "active",
  confidence: 1.0
}
```

**Issues:**
- No domain behavior
- No validation
- No encapsulation
- Hard to refactor

**Recommended Fix:**
```ruby
class Fact
  attr_reader :subject_name, :predicate, :object_literal, :status, :confidence

  def initialize(subject_name:, predicate:, object_literal:, status: "active", confidence: 1.0)
    @subject_name = subject_name
    @predicate = predicate
    @object_literal = object_literal
    @status = status
    @confidence = confidence

    validate!
  end

  def active?
    status == "active"
  end

  def superseded?
    status == "superseded"
  end

  private

  def validate!
    raise ArgumentError, "predicate required" if predicate.nil?
    raise ArgumentError, "confidence must be 0-1" unless (0..1).cover?(confidence)
  end
end
```

---

## 5. Gary Bernhardt Perspective (Boundaries, Fast Tests)

### Focus Areas
- Functional core, imperative shell
- Fast unit tests
- Clear boundaries
- Separation of I/O and logic
- Value objects

### Critical Issues

#### 🔴 I/O Mixed with Logic Throughout CLI

**Problem:** Every CLI method mixes computation with I/O:
```ruby
def recall_cmd
  query = @args[1]
  unless query
    @stderr.puts "Usage: ..."  # I/O
    return 1
  end

  opts = {limit: 10, scope: "all"}  # Logic
  OptionParser.new do |o|            # I/O (arg parsing)
    o.on("--limit N", Integer) { |v| opts[:limit] = v }
  end

  manager = ClaudeMemory::Store::StoreManager.new  # I/O (database)
  recall = ClaudeMemory::Recall.new(manager)
  results = recall.query(query, limit: opts[:limit], scope: opts[:scope])  # Logic

  if results.empty?
    @stdout.puts "No facts found."  # I/O
  else
    @stdout.puts "Found #{results.size} fact(s):\n\n"  # I/O
    results.each do |result|
      print_fact(result[:fact])  # I/O
    end
  end

  manager.close  # I/O
  0
end
```

**Issues:**
- Can't test logic without I/O
- Slow tests (database required)
- Hard to test error cases
- Can't reuse logic in different contexts

**Recommended Fix:**
Functional core:
```ruby
module ClaudeMemory
  module Core
    class RecallQuery
      def self.call(query:, limit:, scope:, facts_repository:)
        facts = facts_repository.search(query, limit: limit, scope: scope)

        {
          found: facts.any?,
          count: facts.size,
          facts: facts.map { |f| FactPresenter.new(f) }
        }
      end
    end
  end
end
```

Imperative shell:
```ruby
def recall_cmd
  params = RecallParams.parse(@args)
  return usage_error unless params.valid?

  manager = StoreManager.new
  result = Core::RecallQuery.call(
    query: params.query,
    limit: params.limit,
    scope: params.scope,
    facts_repository: FactsRepository.new(manager)
  )

  output_result(result)
  manager.close
  0
end
```

**Benefits:**
- Core logic is pure (no I/O)
- Fast unit tests for core
- Shell handles all I/O
- Easy to test edge cases

#### 🔴 No Value Objects

**Problem:** Primitive types used everywhere:
```ruby
def ingest(source:, session_id:, transcript_path:, project_path: nil)
  # All strings - no domain meaning
end
```

**Issues:**
- No type safety
- Easy to swap arguments
- No validation
- No domain behavior

**Recommended Fix:**
```ruby
class SessionId
  attr_reader :value

  def initialize(value)
    @value = value
    validate!
  end

  def to_s
    value
  end

  private

  def validate!
    raise ArgumentError, "Session ID cannot be empty" if value.nil? || value.empty?
  end
end

class TranscriptPath
  attr_reader :value

  def initialize(value)
    @value = Pathname.new(value)
    validate!
  end

  def exist?
    value.exist?
  end

  private

  def validate!
    raise ArgumentError, "Path cannot be nil" if value.nil?
  end
end

# Usage:
def ingest(source:, session_id:, transcript_path:, project_path: nil)
  session_id = SessionId.new(session_id) unless session_id.is_a?(SessionId)
  transcript_path = TranscriptPath.new(transcript_path) unless transcript_path.is_a?(TranscriptPath)

  # Now have type safety and validation
end
```

#### 🔴 Direct File I/O in Business Logic

**Problem:** Publish class directly reads/writes files:
```ruby
def should_write?(path, content)
  return true unless File.exist?(path)  # Direct file I/O

  existing_hash = Digest::SHA256.file(path).hexdigest  # Direct file I/O
  # ...
end

def ensure_import_exists(mode, path)
  if File.exist?(claude_md)  # Direct file I/O
    content = File.read(claude_md)  # Direct file I/O
    # ...
  end
end
```

**Issues:**
- Can't test without filesystem
- Slow tests
- Hard to test error conditions

**Recommended Fix:**
Inject file system adapter:
```ruby
class FileSystem
  def exist?(path)
    File.exist?(path)
  end

  def read(path)
    File.read(path)
  end

  def write(path, content)
    File.write(path, content)
  end

  def file_hash(path)
    Digest::SHA256.file(path).hexdigest
  end
end

class InMemoryFileSystem
  def initialize
    @files = {}
  end

  def exist?(path)
    @files.key?(path)
  end

  def read(path)
    @files.fetch(path) { raise Errno::ENOENT }
  end

  def write(path, content)
    @files[path] = content
  end

  def file_hash(path)
    content = read(path)
    Digest::SHA256.hexdigest(content)
  end
end

class Publish
  def initialize(store, file_system: FileSystem.new)
    @store = store
    @file_system = file_system
  end

  def should_write?(path, content)
    return true unless @file_system.exist?(path)

    existing_hash = @file_system.file_hash(path)
    new_hash = Digest::SHA256.hexdigest(content)
    existing_hash != new_hash
  end
end
```

**Test:**
```ruby
RSpec.describe Publish do
  it "writes when file doesn't exist" do
    fs = InMemoryFileSystem.new
    store = double(:store)
    publish = Publish.new(store, file_system: fs)

    # Fast, no real filesystem
  end
end
```

#### 🔴 State Stored in Instance Variables (resolver.rb:10-13)

**Problem:**
```ruby
def apply(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")
  occurred_at ||= Time.now.utc.iso8601
  @current_project_path = project_path  # Mutable state!
  @current_scope = scope                # Mutable state!

  # Used in private methods
end

def resolve_fact(fact_data, entity_ids, content_item_id, occurred_at)
  # ... uses @current_project_path and @current_scope
  fact_scope = fact_data[:scope_hint] || @current_scope
  fact_project = (fact_scope == "global") ? nil : @current_project_path
end
```

**Issues:**
- Hidden coupling between methods
- Stateful object (not thread-safe)
- Hard to reason about
- Side effects on instance

**Recommended Fix:**
Pass as parameters:
```ruby
def apply(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")
  occurred_at ||= Time.now.utc.iso8601

  context = ResolutionContext.new(
    project_path: project_path,
    scope: scope,
    occurred_at: occurred_at
  )

  result = build_result

  extraction.facts.each do |fact_data|
    outcome = resolve_fact(fact_data, entity_ids, content_item_id, context)
    merge_outcome!(result, outcome)
  end

  result
end

def resolve_fact(fact_data, entity_ids, content_item_id, context)
  # Uses context parameter instead of instance variables
  fact_scope = fact_data[:scope_hint] || context.scope
  fact_project = (fact_scope == "global") ? nil : context.project_path
end
```

#### 🟡 No Clear Layer Boundaries

**Problem:** Classes don't follow clear architectural layers:
```
CLI → creates Store directly
CLI → creates Ingester directly
Ingester → creates FTS index
Publish → reads files
Hook::Handler → creates dependencies
```

**Recommended Architecture:**
```
Presentation Layer (CLI, HTTP)
  ↓
Application Layer (Use Cases / Commands)
  ↓
Domain Layer (Core business logic - pure)
  ↓
Infrastructure Layer (Database, Files, External APIs)
```

**Example:**
```ruby
# Domain Layer - Pure logic
module ClaudeMemory
  module Domain
    class Fact
      # Pure domain object
    end

    class FactRepository
      # Interface (abstract)
      def find(id)
        raise NotImplementedError
      end

      def save(fact)
        raise NotImplementedError
      end
    end
  end
end

# Infrastructure Layer
module ClaudeMemory
  module Infrastructure
    class SequelFactRepository < Domain::FactRepository
      def initialize(db)
        @db = db
      end

      def find(id)
        # Sequel-specific implementation
      end

      def save(fact)
        # Sequel-specific implementation
      end
    end
  end
end

# Application Layer
module ClaudeMemory
  module Application
    class PromoteFact
      def initialize(fact_repository:, event_publisher:)
        @fact_repository = fact_repository
        @event_publisher = event_publisher
      end

      def call(fact_id)
        fact = @fact_repository.find(fact_id)
        return Result.failure("Not found") unless fact

        promoted = fact.promote_to_global
        @fact_repository.save(promoted)
        @event_publisher.publish(FactPromoted.new(fact_id))

        Result.success(promoted.id)
      end
    end
  end
end

# Presentation Layer
class CLI
  def promote_cmd
    fact_id = @args[1]&.to_i
    return usage_error unless valid_fact_id?(fact_id)

    result = @promote_fact_use_case.call(fact_id)

    if result.success?
      @stdout.puts "Promoted fact ##{fact_id}"
      0
    else
      @stderr.puts result.error
      1
    end
  end
end
```

---

## 6. General Ruby Idioms and Style Issues

### 🟡 Inconsistent Method Call Parentheses

**Problem:**
```ruby
@stdout.puts "Message"           # No parens
print_help                        # No parens
manager.close                     # No parens
opts = {limit: 10, scope: "all"} # No parens

OptionParser.new do |o|           # Parens with block
  o.on("--limit N", Integer) { |v| opts[:limit] = v }  # Parens
end

manager = ClaudeMemory::Store::StoreManager.new  # Parens
```

**Recommendation:** Be consistent. Common Ruby style:
- Use parens for methods with arguments
- Omit for methods without arguments
- Omit for keywords (`puts`, `print`, `raise`)

### 🟡 Long Parameter Lists

**Problem:**
```ruby
def upsert_content_item(source:, text_hash:, byte_len:, session_id: nil, transcript_path: nil,
  project_path: nil, occurred_at: nil, raw_text: nil, metadata: nil)
  # 9 parameters!
end

def insert_fact(subject_entity_id:, predicate:, object_entity_id: nil, object_literal: nil,
  datatype: nil, polarity: "positive", valid_from: nil, status: "active",
  confidence: 1.0, created_from: nil, scope: "project", project_path: nil)
  # 12 parameters!
end
```

**Recommendation:** Use parameter objects:
```ruby
class ContentItemParams
  attr_reader :source, :text_hash, :byte_len, :session_id, :transcript_path,
              :project_path, :occurred_at, :raw_text, :metadata

  def initialize(source:, text_hash:, byte_len:, **optional)
    @source = source
    @text_hash = text_hash
    @byte_len = byte_len
    @session_id = optional[:session_id]
    # ... etc
  end
end

def upsert_content_item(params)
  # Much cleaner
end
```

### 🟡 Mixed Hash Access (Symbols vs Strings)

**Problem:**
```ruby
# MCP Server
request["id"]        # String key
request["method"]    # String key

# Domain
fact[:subject_name]  # Symbol key
fact[:predicate]     # Symbol key
```

**Recommendation:** Be consistent. Use symbols for internal hashes, strings for external JSON.

### 🟡 Rescue Without Specific Exception

**Problem:**
```ruby
begin
  store = ClaudeMemory::Store::SQLiteStore.new(db_path)
  # ...
rescue => e  # Catches everything!
  issues << "#{label} database error: #{e.message}"
end
```

**Recommendation:** Catch specific exceptions:
```ruby
rescue Sequel::DatabaseError, SQLite3::Exception => e
  issues << "#{label} database error: #{e.message}"
end
```

### 🟡 ENV Access Scattered Throughout

**Problem:**
```ruby
# claude_memory.rb:28
home = env["HOME"] || File.expand_path("~")

# store_manager.rb:11
@project_path = project_path || env["CLAUDE_PROJECT_DIR"] || Dir.pwd

# hook/handler.rb:16
session_id = payload["session_id"] || @env["CLAUDE_SESSION_ID"]
```

**Recommendation:** Centralize environment access:
```ruby
module ClaudeMemory
  class Configuration
    def initialize(env = ENV)
      @env = env
    end

    def home_dir
      @env["HOME"] || File.expand_path("~")
    end

    def project_dir
      @env["CLAUDE_PROJECT_DIR"] || Dir.pwd
    end

    def session_id
      @env["CLAUDE_SESSION_ID"]
    end
  end
end
```

### 🟡 Boolean Traps

**Problem:**
```ruby
opts = {global: false, project: false}

# What does this mean?
manager.ensure_global!
manager.ensure_project!

# What does true/false mean here?
if opts[:global]
  # ...
end
```

**Recommendation:** Use explicit values:
```ruby
scope = opts[:scope]  # :global, :project, or :both

case scope
when :global
  manager.ensure_global!
when :project
  manager.ensure_project!
when :both
  manager.ensure_both!
end
```

### 🟡 No Use of Ruby 3 Features

**Observations:**
- No pattern matching (available since Ruby 2.7)
- No rightward assignment
- No endless method definitions
- No type annotations (RBS/Sorbet)

**Opportunities:**
```ruby
# Current
case command
when "help", "-h", "--help"
  print_help
when "version", "-v", "--version"
  print_version
end

# With pattern matching
case command
in "help" | "-h" | "--help"
  print_help
in "version" | "-v" | "--version"
  print_version
in unknown
  handle_unknown(unknown)
end

# Current
def valid?(fact)
  fact[:predicate] && fact[:subject_entity_id]
end

# Endless method
def valid?(fact) = fact[:predicate] && fact[:subject_entity_id]
```

---

## 7. Positive Observations

Despite the issues above, this codebase has several strengths:

### ✅ Good Practices

1. **Frozen String Literals** - Every file has `# frozen_string_literal: true`
2. **Consistent Sequel Usage** - Most of the time uses Sequel datasets properly
3. **Explicit Dependencies** - Constructor injection used (though inconsistently)
4. **Module Namespacing** - Good use of nested modules
5. **Test Coverage** - Spec files exist for most modules
6. **Documentation** - Good README and CLAUDE.md files
7. **Schema Versioning** - Database has schema version tracking
8. **Error Classes** - Custom error classes defined
9. **Keyword Arguments** - Modern Ruby style with keyword arguments
10. **FTS Integration** - Good use of SQLite's FTS5 capabilities

---

## 8. Priority Refactoring Recommendations

### High Priority (Week 1-2)

1. **Extract CLI Command Objects**
   - Target: Reduce cli.rb from 867 lines to < 200
   - Extract each command to separate class
   - Use command pattern

2. **Add Transaction Safety**
   - Wrap `promote_fact` in transaction
   - Wrap resolver operations in transactions
   - Add rollback tests

3. **Fix Raw SQL in doctor_cmd**
   - Replace with Sequel dataset methods
   - Ensures consistency

4. **Separate I/O from Logic in Core Classes**
   - Start with Recall, Publish
   - Extract functional core
   - Make imperativeshell thin

### Medium Priority (Week 3-4)

5. **Introduce Value Objects**
   - SessionId, TranscriptPath, FactId
   - Adds type safety
   - Documents domain

6. **Replace Nil Returns with Null Objects**
   - NullExplanation, NullFact
   - Enables confident code
   - Reduces nil checks

7. **Extract Repository Pattern**
   - FactRepository, EntityRepository
   - Abstracts data access
   - Enables testing without database

8. **Split Recall into Legacy/Dual**
   - Remove conditional mode logic
   - Clearer single responsibility
   - Easier to maintain

### Low Priority (Week 5+)

9. **Add Domain Models**
   - Fact, Entity, Provenance classes
   - Rich domain behavior
   - Replace primitive hashes

10. **Introduce Proper Migrations**
    - Use Sequel migration framework
    - Versioned, reversible
    - Development/production parity

11. **Add Type Annotations**
    - Consider RBS or Sorbet
    - Better IDE support
    - Catches type errors early

12. **Centralize Configuration**
    - Configuration class
    - Environment variable access
    - Testable, mockable

---

## 9. Conclusion

This codebase shows solid Ruby fundamentals but suffers from common growing pains: God Objects, mixed concerns, and lack of architectural boundaries. The issues are fixable and follow predictable patterns.

**Key Takeaways:**
1. **CLI needs major refactoring** - Extract command objects
2. **Separate I/O from logic** - Enable fast tests
3. **Use transactions** - Data integrity
4. **Introduce domain objects** - Replace primitive hashes
5. **Adopt null object pattern** - Reduce nil checks

**Estimated Refactoring Effort:**
- High priority: 2 weeks (1 developer)
- Medium priority: 2 weeks (1 developer)
- Low priority: 1-2 weeks (1 developer)
- Total: 5-6 weeks for comprehensive refactoring

**Risk Assessment:** Low-to-medium risk. Changes are incremental and testable. Existing test suite provides safety net.

---

## Appendix A: Recommended Reading

1. **Sandi Metz** - _Practical Object-Oriented Design in Ruby_ (POODR)
2. **Jeremy Evans** - _Sequel Documentation_ and _Roda Book_
3. **Kent Beck** - _Test-Driven Development: By Example_
4. **Avdi Grimm** - _Confident Ruby_
5. **Gary Bernhardt** - _Boundaries_ talk, _Destroy All Software_ screencasts
6. **Martin Fowler** - _Refactoring: Ruby Edition_

## Appendix B: Quick Wins (Can Do Today)

1. Fix raw SQL in `doctor_cmd` (20 minutes)
2. Consolidate `attr_reader` in StoreManager (5 minutes)
3. Fix boolean logic in `parse_db_init_options` (10 minutes)
4. Move `public` declaration in SQLiteStore (2 minutes)
5. Extract long methods in CLI (1 hour per method)

---

**Review completed:** 2026-01-21
