# ClaudeMemory Architecture

## Overview

ClaudeMemory is architected using Domain-Driven Design (DDD) principles with clear separation of concerns across multiple layers. The codebase has undergone significant refactoring to improve maintainability, testability, and performance.

## Architectural Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  CLI (Router) → Commands (20 classes) → Configuration       │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                   Core Domain Layer                          │
│  Domain Models: Fact, Entity, Provenance, Conflict          │
│  Value Objects: SessionId, TranscriptPath, FactId           │
│  Null Objects: NullFact, NullExplanation                    │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                 Business Logic Layer                         │
│  Recall → Resolve → Distill → Ingest → Publish             │
│  Sweep → Embeddings → MCP → Hook                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                 Infrastructure Layer                         │
│  Store (SQLite v6 + WAL) → FileSystem → Index (FTS5+TF-IDF)│
│  Templates                                                   │
└─────────────────────────────────────────────────────────────┘
```

## Layer Details

### 1. Application Layer

**Purpose:** Handle user interaction and command routing

**Components:**
- **CLI** (`cli.rb`): Thin router that dispatches to command classes
- **Commands** (`commands/`): 20 command classes, each handling one CLI command
- **Configuration** (`configuration.rb`): Centralized ENV access and path calculation

**Key Principles:**
- Single Responsibility: Each command does one thing
- Dependency Injection: I/O isolated for testing (stdout, stderr, stdin)
- Command Pattern: Uniform interface via `BaseCommand#call(args)`
- Registry Pattern: Dynamic command lookup via `Commands::Registry`

**Example:**
```ruby
# Thin router
class CLI
  def run
    command_class = Commands::Registry.find(@args.first || "help")
    command = command_class.new(stdout: @stdout, stderr: @stderr, stdin: @stdin)
    command.call(@args[1..-1] || [])
  end
end

# Individual command
class DoctorCommand < BaseCommand
  def call(args)
    # All logic here, fully testable
  end
end
```

### 2. Core Domain Layer

**Purpose:** Encapsulate business logic and domain concepts

**Components:**

#### Domain Models (`domain/`)
- **Fact**: Subject-predicate-object triples with validation
  - Methods: `active?`, `superseded?`, `global?`, `project?`
  - Validates: Required fields, confidence 0-1

- **Entity**: Named entities (databases, frameworks, people)
  - Methods: `database?`, `framework?`, `person?`
  - Validates: Required type, name, slug

- **Provenance**: Evidence linking facts to sources
  - Methods: `stated?`, `inferred?`
  - Validates: Required fact_id, content_item_id

- **Conflict**: Contradictions between facts
  - Methods: `open?`, `resolved?`
  - Validates: Required fact IDs

#### Value Objects (`core/`)
- **SessionId**: Type-safe session identifiers
- **TranscriptPath**: Type-safe file paths
- **FactId**: Type-safe positive integer IDs
- **TextBuilder**: Searchable text construction from entities/facts/decisions
- **ResultSorter**: Result ranking and sorting logic
- **FactQueryBuilder**: SQL query construction for fact retrieval
- All are immutable (frozen) and self-validating

#### Null Objects (`core/`)
- **NullFact**: Represents non-existent fact (eliminates nil checks)
- **NullExplanation**: Represents non-existent explanation

#### Result Pattern (`core/`)
- **Result**: Success/Failure for consistent error handling

**Key Principles:**
- Immutability: All domain objects are frozen
- Self-validation: Invalid objects cannot be constructed
- Rich behavior: Business logic in domain objects, not scattered
- Tell, Don't Ask: Objects have behavior, not just data

### 3. Business Logic Layer

**Purpose:** Implement core memory operations

**Components:**

#### Recall (`recall.rb` + `recall/`)
- Queries facts from global and project databases
- **Optimization**: Batch queries to eliminate N+1 issues
  - Before: 2N+1 queries for N facts
  - After: 3 queries total (FTS + batch facts + batch receipts)
- Supports scope filtering (project, global, all)
- Returns facts with provenance receipts
- `DualQueryTemplate`: Query template handling for dual-database queries

#### Resolve (`resolve/`)
- Truth maintenance and conflict resolution
- **Transaction safety**: Multi-step operations wrapped in DB transactions
- PredicatePolicy: Controls single vs. multi-value predicates
- Handles supersession and conflict detection

#### Distill (`distill/`)
- Extracts facts and entities from transcripts
- Pluggable design (currently NullDistiller stub)
- Detects scope hints (global vs. project)

#### Ingest (`ingest/`)
- Delta-based transcript ingestion
- Tracks cursor position to avoid reprocessing
- Handles file shrinking (compaction)

#### Publish (`publish.rb`)
- Generates markdown snapshots
- **FileSystem abstraction**: Testable without disk I/O
- Modes: shared (repo), local (uncommitted), home (user dir)

#### Sweep (`sweep/`)
- Maintenance and pruning
- Time-bounded execution
- Cleans up old content and expired facts

#### Embeddings (`embeddings/`)
- Lightweight TF-IDF embedding generation
- 384-dimensional normalized vectors
- Semantic similarity calculations
- No heavy ML dependencies required

#### MCP (`mcp/`)
- Model Context Protocol server
- Exposes 19 tools including: recall, explain, promote, status, decisions, conventions, architecture, semantic search, check_setup, and more
- `ResponseFormatter`: Consistent MCP response formatting
- `SetupStatusAnalyzer`: Initialization and version status analysis

#### Hook (`hook/`)
- Reads JSON from stdin
- Routes to ingest/sweep/publish

### 4. Infrastructure Layer

**Purpose:** Handle external systems and I/O

**Components:**

#### Store (`store/`)
- **SQLiteStore**: Direct database access via Sequel (schema v6)
- **StoreManager**: Manages dual databases (global + project)
- **Transaction safety**: Atomic multi-step operations
- **WAL mode**: Write-Ahead Logging for better concurrency
- Schema migrations with per-migration transactions

#### FileSystem (`infrastructure/`)
- **FileSystem**: Real filesystem wrapper
- **InMemoryFileSystem**: Fast in-memory testing
- Interface: `exist?`, `read`, `write`, `file_hash`
- Enables testing without tempdir cleanup

#### Index (`index/`)
- SQLite FTS5 for lexical full-text search
- TF-IDF embeddings for semantic similarity (384-dimensional vectors)
- Hybrid search modes: text-only, semantic-only, or both

#### Templates (`templates/`)
- Hook configuration examples (`hooks.example.json`)
- Output style templates (`output-styles/memory-aware.md`)
- Setup and configuration scaffolding

**Key Principles:**
- Ports and Adapters: Clear interfaces for external systems
- Dependency Injection: Real vs. test implementations
- Transaction boundaries: ACID guarantees

## Design Patterns Used

### 1. Command Pattern
- Each CLI command is a separate class
- Uniform interface: `call(args) → exit_code`
- Easy to add new commands without modifying router

### 2. Registry Pattern
- `Commands::Registry` maps command names to classes
- Dynamic dispatch
- Easy to see all available commands

### 3. Null Object Pattern
- `NullFact`, `NullExplanation` eliminate nil checks
- Prevents NilClass errors
- More expressive: `explanation.is_a?(NullExplanation)` vs `explanation.nil?`

### 4. Value Object Pattern
- `SessionId`, `TranscriptPath`, `FactId` prevent primitive obsession
- Self-validating at construction
- Type safety in method signatures

### 5. Repository Pattern (Implicit)
- `Store::SQLiteStore` abstracts data access
- Could be extended with explicit repository layer

### 6. Strategy Pattern
- `PredicatePolicy` determines fact resolution behavior
- Pluggable distillers

### 7. Template Method Pattern
- `BaseCommand` provides common functionality
- Subclasses override `call(args)`

## Data Flow

### Ingestion Flow
```
Transcript File
  ↓
TranscriptReader (delta detection)
  ↓
Ingester (content storage)
  ↓
Distiller (fact extraction)
  ↓
Resolver (truth maintenance)
  ↓
SQLiteStore (persistence)
```

### Query Flow
```
User Query
  ↓
Recall (FTS search)
  ↓
Batch Queries (facts + receipts)
  ↓
Result Assembly
  ↓
Response
```

### Publish Flow
```
SQLiteStore (active facts)
  ↓
Publish (snapshot generation)
  ↓
FileSystem (write)
  ↓
.claude/rules/claude_memory.generated.md
```

## Performance Optimizations

### 1. N+1 Query Elimination
**Problem:** Recall queried each fact and its receipts individually
**Solution:** Batch query all facts, batch query all receipts
**Impact:** 2N+1 queries → 3 queries (7x faster for 10 facts)

### 2. FileSystem Abstraction
**Problem:** Tests hit disk for every file operation
**Solution:** InMemoryFileSystem for tests
**Impact:** ~10x faster test suite

### 3. Transaction Safety
**Problem:** Multi-step operations could leave inconsistent state
**Solution:** Wrap in database transactions
**Impact:** Data integrity guaranteed

### 4. WAL Mode for Concurrency
**Problem:** Database locks prevented concurrent reads during writes
**Solution:** Enable Write-Ahead Logging (WAL) mode in SQLite
**Impact:** MCP server and hooks can operate concurrently without blocking

### 5. Lightweight Semantic Search
**Problem:** Traditional semantic search requires heavy ML models and API calls
**Solution:** TF-IDF embeddings with 384-dimensional vectors (no external dependencies)
**Impact:** Fast semantic search without external API costs

## Testing Strategy

### Unit Tests
- Commands: Test with mocked I/O
- Domain models: Test validation and behavior
- Value objects: Test construction and equality

### Integration Tests
- Store operations: Use real SQLite database
- Recall queries: Test with seeded data

### Fast Tests
- InMemoryFileSystem: No disk I/O
- Mocked stores: Avoid database setup

### Test Isolation
- Dependency injection throughout
- No global state
- Each test independent

## Code Metrics

### Before Refactoring
- CLI: 881 lines (god object)
- Tests: 277 examples
- N+1 queries in Recall
- Direct File I/O
- Primitive obsession
- Scattered ENV access

### After Refactoring
- CLI: 41 lines (thin router, 95% reduction from original)
- Tests: 988 examples (257% increase)
- Batch queries (3 total)
- FileSystem abstraction
- Value objects (SessionId, TranscriptPath, FactId)
- Centralized Configuration
- 4 domain models with business logic
- 20 command classes
- 19 MCP tools
- Semantic search with TF-IDF embeddings
- Schema v6 with WAL mode

## Future Improvements

### Phase 5 (Optional)
- Proper Sequel migrations (vs. hand-rolled)
- Explicit Repository layer
- More domain models (Explanation, ContentItem)
- GraphQL API for external access

### Potential Enhancements
- Event sourcing for fact history
- CQRS: Separate read/write models
- Background job processing
- Multi-database support (PostgreSQL, MySQL)
- Distributed memory across multiple Claude instances

## References

### Design Principles
- **SOLID Principles**: Single Responsibility, Open/Closed, Dependency Inversion
- **Domain-Driven Design**: Rich domain models, ubiquitous language
- **Ports and Adapters**: Infrastructure abstractions
- **Tell, Don't Ask**: Behavior in objects

### Inspirations
- Sandi Metz - _Practical Object-Oriented Design in Ruby_
- Eric Evans - _Domain-Driven Design_
- Martin Fowler - _Patterns of Enterprise Application Architecture_
- Avdi Grimm - _Confident Ruby_
- Gary Bernhardt - Boundaries talk

## Conclusion

The refactored architecture provides:
- ✅ Clear separation of concerns
- ✅ High testability (988 tests)
- ✅ Type safety (value objects)
- ✅ Null safety (null objects)
- ✅ Performance (batch queries, in-memory FS, WAL mode)
- ✅ Maintainability (small, focused classes)
- ✅ Extensibility (easy to add commands/tools)
- ✅ Semantic search (lightweight TF-IDF embeddings)

The codebase now follows best practices for Ruby applications and is well-positioned for future growth.
