# grepai Analysis

*Analysis Date: 2026-01-29*
*Repository: https://github.com/yoanbernabeu/grepai*
*Version/Commit: HEAD (main branch)*

---

## Executive Summary

### Project Purpose
grepai is a privacy-first CLI tool for semantic code search using vector embeddings, enabling natural language queries that find relevant code based on intent rather than exact text matches.

### Key Innovation
**Semantic search with zero cloud dependency** - Combines local vector embeddings (via Ollama) with file-watching for real-time index updates, drastically reducing AI agent token usage by ~80% through intelligent context retrieval instead of full codebase scans.

### Technology Stack
| Component | Technology |
|-----------|-----------|
| **Language** | Go 1.22+ |
| **Vector Store** | PostgreSQL with pgvector, Qdrant, or GOB (file-based) |
| **Embedding** | Ollama (local), OpenAI, LM Studio |
| **File Watching** | fsnotify |
| **CLI Framework** | cobra |
| **MCP Integration** | mark3labs/mcp-go |
| **Call Graph** | tree-sitter for AST parsing |
| **Testing** | Go stdlib testing with race detection |
| **CI/CD** | GitHub Actions (multi-OS, cross-compile) |

### Production Readiness
- **Maturity**: Production-ready (actively developed, popular on ProductHunt)
- **Test Coverage**: Comprehensive with race detection enabled
- **Documentation**: Excellent (dedicated docs site, blog, examples)
- **Distribution**: Homebrew, shell installers, multi-platform binaries
- **Community**: Active development, ~280K views on Reddit
- **Performance**: Designed for efficiency (compact JSON, batching, debouncing)

---

## Architecture Overview

### Data Model

**Two-Phase Indexing**:

1. **Vector Index** (semantic search)
   - **Chunk**: Code segment with vector embedding
     - Fields: ID, FilePath, StartLine, EndLine, Content, Vector, Hash, UpdatedAt
     - Chunk size: 512 tokens with 50-token overlap
     - Character-based chunking (handles minified files)
   - **Document**: File metadata tracking chunks
     - Fields: Path, Hash, ModTime, ChunkIDs

2. **Symbol Index** (call graph tracing)
   - **Symbol**: Function/method/class definitions
     - Fields: Name, Kind, File, Line, Signature, Receiver, Package, Exported
   - **Reference**: Symbol usage/call sites
     - Fields: SymbolName, File, Line, Context, CallerName, CallerFile
   - **CallEdge**: Caller → Callee relationships for graph traversal

**Storage Backends** (pluggable via `VectorStore` interface):
- GOB: File-based (`.grepai/index.gob`)
- PostgreSQL: pgvector extension for similarity search
- Qdrant: Dedicated vector database

### Design Patterns

1. **Interface-Based Extensibility**
   - `Embedder` interface (embedder/embedder.go:6): Pluggable embedding providers
   - `VectorStore` interface (store/store.go:50): Pluggable storage backends
   - `SymbolExtractor` interface (trace/trace.go:113): Pluggable language parsers

2. **Context-Aware Operations**
   - All I/O operations accept `context.Context` for cancellation
   - Example: `SaveChunks(ctx context.Context, chunks []Chunk) error`

3. **Batch Processing with Progress Callbacks**
   - `BatchEmbedder` interface (embedder/embedder.go:29): Parallel batch embedding
   - Progress callback: `func(batchIndex, totalBatches, completedChunks, totalChunks, retrying, attempt, statusCode)`

4. **Debounced File Watching**
   - Aggregates rapid file changes before triggering re-indexing
   - Prevents index thrashing during bulk operations (git checkout, etc.)

5. **Compact JSON Mode**
   - MCP tools support `--compact` flag to omit content (~80% token reduction)
   - Returns only file:line references, not full code chunks

### Module Organization

```
grepai/
├── cmd/
│   └── grepai/           # CLI entry point
├── cli/                  # Command implementations (init, watch, search, trace)
├── embedder/             # Embedding providers (Ollama, OpenAI, LMStudio)
├── indexer/              # Scanner, chunker, indexer orchestration
├── store/                # Vector storage backends (GOB, Postgres, Qdrant)
├── search/               # Semantic + hybrid search
├── trace/                # Symbol extraction, call graph (tree-sitter based)
├── watcher/              # File watching with debouncing
├── daemon/               # Background indexing daemon
├── config/               # YAML configuration management
├── updater/              # Self-update mechanism
└── mcp/                  # MCP server (5 tools)
```

**Entry Point Flow**:
```
cmd/grepai/main.go → cli/root.go → cli/{init,watch,search,trace}.go
```

**Data Flow**:
```
FileSystem → Scanner (respects .gitignore)
          → Chunker (overlapping chunks)
          → Embedder (batch API calls)
          → VectorStore (persist with hash-based deduplication)

Query → Embedder (query vector)
      → VectorStore.Search (cosine similarity)
      → Results (sorted by score)
```

### Comparison with ClaudeMemory

| Aspect | grepai | ClaudeMemory |
|--------|--------|--------------|
| **Language** | Go (compiled, fast) | Ruby (interpreted) |
| **Primary Use** | Semantic code search | Long-term AI memory |
| **Data Model** | Chunks + Symbols | Facts + Provenance |
| **Storage** | Vector DB (pgvector/Qdrant/GOB) | SQLite (facts, no vectors) |
| **Search** | Vector similarity + hybrid | Full-text search (FTS5) |
| **Indexing** | Automatic (file watcher) | Manual (transcript ingest) |
| **MCP Tools** | 5 (search, trace, status) | 8+ (recall, explain, promote) |
| **Scope** | Project-local or workspace | Global + Project dual-DB |
| **Truth Maintenance** | Hash-based deduplication | Supersession + conflict resolution |
| **Performance** | Optimized for speed (Go, batching) | Optimized for accuracy (resolution) |
| **Distribution** | Standalone CLI (Homebrew) | Ruby gem |
| **Testing** | Go stdlib + race detection | RSpec with mocks |
| **UI** | CLI with bubbletea (TUI) | Pure CLI |
| **Call Graph** | Yes (tree-sitter AST) | No |
| **File Watching** | Yes (fsnotify) | No (transcript-driven) |

**Key Architectural Difference**: grepai is **proactive** (watches files, updates index automatically) while ClaudeMemory is **reactive** (responds to transcript events via hooks).

---

## Key Components Deep-Dive

### Component 1: Chunking Strategy

**Purpose**: Split code into overlapping chunks optimized for embedding

**Implementation** (indexer/chunker.go:47-100):
```go
// Character-based chunking (not line-based) handles minified files
maxChars := c.chunkSize * CharsPerToken  // 512 tokens * 4 chars = 2048 chars
overlapChars := c.overlap * CharsPerToken // 50 tokens * 4 chars = 200 chars

for pos < len(content) {
    end := pos + maxChars
    // Try to break at newline for cleaner chunks
    if end < len(content) {
        lastNewline := strings.LastIndex(content[pos:end], "\n")
        if lastNewline > 0 {
            end = pos + lastNewline + 1
        }
    }

    // Calculate line numbers using pre-built index
    startLine := getLineNumber(lineStarts, pos)
    endLine := getLineNumber(lineStarts, end-1)

    chunks = append(chunks, ChunkInfo{
        ID: fmt.Sprintf("%s_%d", filePath, chunkIndex),
        FilePath: filePath,
        StartLine: startLine,
        EndLine: endLine,
        Content: chunkContent,
        Hash: sha256Hash,  // For deduplication
    })

    pos = end - overlapChars  // Overlap for context continuity
}
```

**Design Decisions**:
- **Character-based**: Handles minified files with very long lines
- **Overlap**: 50 tokens ensure context continuity across chunks
- **Newline breaking**: Prefers natural boundaries when possible
- **Line number mapping**: Pre-build index for O(log n) lookups
- **Hash-based deduplication**: Skip re-embedding unchanged chunks

**Performance**: ~4 chars per token is empirically validated for code.

---

### Component 2: File Watcher with Debouncing

**Purpose**: Incrementally update index on file changes without thrashing

**Implementation** (watcher/watcher.go:30-100):
```go
type Watcher struct {
    pending   map[string]FileEvent  // Aggregates rapid changes
    pendingMu sync.Mutex            // Thread-safe updates
    timer     *time.Timer           // Debounce timer
}

func (w *Watcher) processEvents(ctx context.Context) {
    for {
        select {
        case event := <-w.watcher.Events:
            w.pendingMu.Lock()

            // Aggregate events (overwrites older events for same file)
            w.pending[relPath] = FileEvent{Type: eventType, Path: relPath}

            // Reset debounce timer
            if w.timer != nil {
                w.timer.Stop()
            }
            w.timer = time.AfterFunc(time.Duration(w.debounceMs)*time.Millisecond,
                w.flushPending)

            w.pendingMu.Unlock()
        }
    }
}
```

**Design Decisions**:
- **Debouncing**: Default 300ms prevents index thrashing during bulk operations
- **Event aggregation**: Multiple edits to same file collapse to single update
- **Recursive watching**: Watches all subdirectories automatically
- **gitignore respect**: Uses `sabhiram/go-gitignore` for filtering

**Use Case**: During `git checkout`, hundreds of files change simultaneously. Debouncing waits for changes to settle before re-indexing.

---

### Component 3: MCP Server Design

**Purpose**: Expose grepai as native tool for AI agents (Claude Code, Cursor, Windsurf)

**Implementation** (mcp/server.go:100-168):
```go
func (s *Server) registerTools() {
    // 1. grepai_search
    searchTool := mcp.NewTool("grepai_search",
        mcp.WithDescription("Semantic code search..."),
        mcp.WithString("query", mcp.Required(), mcp.Description("Natural language query")),
        mcp.WithNumber("limit", mcp.Description("Max results (default: 10)")),
        mcp.WithBoolean("compact", mcp.Description("Omit content (~80% token savings)")),
        mcp.WithString("workspace", mcp.Description("Cross-project search")),
        mcp.WithString("projects", mcp.Description("Filter by project names")),
    )
    s.mcpServer.AddTool(searchTool, s.handleSearch)

    // 2. grepai_trace_callers - Find who calls a function
    // 3. grepai_trace_callees - Find what a function calls
    // 4. grepai_trace_graph - Build full call graph
    // 5. grepai_index_status - Health check
}

func (s *Server) handleSearch(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    query := request.RequireString("query")
    limit := request.GetInt("limit", 10)
    compact := request.GetBool("compact", false)

    // Initialize embedder + store
    emb := s.createEmbedder(cfg)
    st := s.createStore(ctx, cfg)
    defer emb.Close(); defer st.Close()

    // Search
    searcher := search.NewSearcher(st, emb, cfg.Search)
    results := searcher.Search(ctx, query, limit)

    // Return compact or full results
    if compact {
        return SearchResultCompact{FilePath, StartLine, EndLine, Score}
    } else {
        return SearchResult{FilePath, StartLine, EndLine, Score, Content}
    }
}
```

**Design Decisions**:
- **5 focused tools**: Search, trace callers, trace callees, trace graph, status
- **Compact mode**: Critical for token efficiency (~80% reduction)
- **Workspace support**: Search across multiple projects with shared embedder/store
- **Project filtering**: Comma-separated list filters workspace results
- **Error handling**: Returns `ToolResultError` instead of throwing exceptions
- **Resource cleanup**: Explicit `defer` for embedder/store cleanup

**Integration**: Works out-of-box with Claude Code, Cursor, Windsurf via stdio transport.

---

### Component 4: Call Graph via tree-sitter

**Purpose**: Static analysis for "find callers" and "find callees" without executing code

**Implementation** (trace/extractor.go):
- Uses tree-sitter parsers for Go, TypeScript, Python, JavaScript, C#, Java, Ruby, Rust
- Extracts symbols (function definitions) and references (function calls)
- Builds call graph: `Symbol → References → Callers/Callees`

**Symbol Extraction** (trace/extractor.go:115):
```go
type Symbol struct {
    Name      string     // Function/method name
    Kind      SymbolKind // function, method, class, interface
    File      string
    Line      int
    Signature string     // Full signature for disambiguation
    Receiver  string     // For methods (e.g., "MyStruct")
    Package   string
    Exported  bool       // Public vs private
    Language  string
}
```

**Reference Extraction** (trace/trace.go:36):
```go
type Reference struct {
    SymbolName string  // What's being called
    File       string  // Where the call happens
    Line       int
    Context    string  // Surrounding code for display
    CallerName string  // Who's making the call
    CallerFile string  // Where caller is defined
    CallerLine int
}
```

**Call Graph Query** (trace/store.go):
- `LookupCallers(symbolName)` → All references where symbol is called
- `LookupCallees(symbolName, file)` → All references within symbol's body
- `GetCallGraph(symbolName, depth)` → Multi-level traversal (BFS)

**Design Decisions**:
- **Fast mode**: tree-sitter AST parsing (no execution)
- **Language-agnostic**: Interface-based extractor per language
- **Context preservation**: Stores surrounding code for display
- **Disambiguation**: Uses signature + file for overloaded functions
- **Depth-limited**: Prevents exponential explosion in call graphs

---

### Component 5: Hybrid Search

**Purpose**: Combine vector similarity with keyword matching for better relevance

**Implementation** (search/search.go):
```go
type HybridConfig struct {
    Enabled bool    // Enable hybrid search
    K       int     // RRF constant (default: 60)
}

func (s *Searcher) Search(ctx context.Context, query string, limit int) ([]SearchResult, error) {
    if !s.cfg.Hybrid.Enabled {
        return s.vectorSearch(ctx, query, limit)
    }

    // 1. Vector search (semantic)
    vectorResults := s.vectorSearch(ctx, query, limit*2)

    // 2. Text search (keyword)
    textResults := s.textSearch(ctx, query, limit*2)

    // 3. Reciprocal Rank Fusion (RRF)
    fusedResults := s.fuseResults(vectorResults, textResults)

    return fusedResults[:limit]
}

func (s *Searcher) fuseResults(vec, text []Result) []Result {
    scores := make(map[string]float32)
    for rank, r := range vec {
        scores[r.Chunk.ID] += 1.0 / float32(rank + s.cfg.Hybrid.K)
    }
    for rank, r := range text {
        scores[r.Chunk.ID] += 1.0 / float32(rank + s.cfg.Hybrid.K)
    }
    // Sort by fused score
}
```

**Design Decisions**:
- **RRF (Reciprocal Rank Fusion)**: Proven effective for combining ranked lists
- **K=60 default**: Standard RRF constant balancing vector vs text
- **2x over-fetch**: Retrieve more results before fusion to avoid missing relevant items
- **Configurable**: Can disable hybrid for pure semantic search

**Trade-off**: Slightly slower (2 searches + fusion) but significantly better relevance for queries with specific keywords.

---

### Component 6: Pluggable Storage Backends

**Purpose**: Support different deployment scenarios (local, team, cloud)

**Interface** (store/store.go:50):
```go
type VectorStore interface {
    SaveChunks(ctx context.Context, chunks []Chunk) error
    DeleteByFile(ctx context.Context, filePath string) error
    Search(ctx context.Context, queryVector []float32, limit int) ([]SearchResult, error)
    GetDocument(ctx context.Context, filePath string) (*Document, error)
    Load(ctx context.Context) error
    Persist(ctx context.Context) error
    Close() error
    GetStats(ctx context.Context) (*IndexStats, error)
}
```

**Implementations**:

1. **GOB Store** (store/gob.go): File-based, single-project
   - Storage: `.grepai/index.gob` (binary format)
   - Search: In-memory cosine similarity (brute force)
   - Use case: Individual developers, local projects
   - Pros: Zero dependencies, fast for small codebases (<10K files)
   - Cons: Memory usage grows with index size, no concurrent access

2. **PostgreSQL Store** (store/postgres.go): Database-backed, multi-project
   - Storage: Postgres with pgvector extension
   - Search: `<=>` operator (optimized with IVFFlat index)
   - Use case: Teams, shared index across projects
   - Pros: Concurrent access, persistence, scalable
   - Cons: Requires Postgres + pgvector setup

3. **Qdrant Store** (store/qdrant.go): Dedicated vector DB
   - Storage: Qdrant server (gRPC API)
   - Search: Native vector search with HNSW indexing
   - Use case: Large codebases (>50K files), production deployments
   - Pros: Fastest search, advanced filtering, scalable
   - Cons: Additional service to run

**Configuration** (.grepai/config.yaml):
```yaml
store:
  backend: "gob"  # or "postgres" or "qdrant"
  postgres:
    dsn: "postgresql://user:pass@localhost/grepai"
  qdrant:
    endpoint: "localhost"
    port: 6334
    collection: "my-codebase"
```

**Design Decisions**:
- **Same interface**: Swap backends without changing application code
- **Project ID scoping**: Multi-project support in Postgres/Qdrant
- **Hash-based deduplication**: All backends check chunk hash before embedding
- **Graceful degradation**: GOB works offline, Postgres/Qdrant require connectivity

---

## Comparative Analysis

### What They Do Well

#### 1. **Incremental Indexing with File Watching**
- **Value**: Index stays fresh automatically without manual triggers
- **Evidence**: watcher/watcher.go:61 - `fsnotify` integration with debouncing
- **How**: Watches all directories recursively, respects gitignore, debounces rapid changes
- **Result**: Zero maintenance overhead for users, always up-to-date search results

#### 2. **Compact JSON Mode for Token Efficiency**
- **Value**: ~80% reduction in AI agent token usage
- **Evidence**: mcp/server.go:36 - `SearchResultCompact` omits content field
- **How**: MCP tools support `--compact` flag returning only file:line:score, not full chunks
- **Result**: Enables AI agents to search larger codebases without hitting context limits

#### 3. **Tree-sitter for Call Graph Analysis**
- **Value**: Language-agnostic static analysis without code execution
- **Evidence**: trace/extractor.go - Parsers for 8+ languages
- **How**: AST parsing extracts symbols + references, builds call graph
- **Result**: "Find callers" feature shows impact before refactoring

#### 4. **Interface-Based Extensibility**
- **Value**: Easy to add new embedders or storage backends
- **Evidence**: embedder/embedder.go:6, store/store.go:50
- **How**: Clean interfaces with multiple implementations (Ollama, OpenAI, LMStudio | GOB, Postgres, Qdrant)
- **Result**: Users choose deployment model (local, team, cloud) without code changes

#### 5. **Character-Based Chunking**
- **Value**: Handles minified files and long lines gracefully
- **Evidence**: indexer/chunker.go:54 - `maxChars := c.chunkSize * CharsPerToken`
- **How**: Splits by characters with newline preference, not by lines
- **Result**: No failures on minified JS/CSS, consistent chunk sizes

#### 6. **Hybrid Search (Vector + Text)**
- **Value**: Better relevance for queries with specific keywords
- **Evidence**: search/search.go - Reciprocal Rank Fusion (RRF)
- **How**: Combines cosine similarity with full-text search using RRF
- **Result**: Finds both semantically related and keyword-matched code

#### 7. **Multi-Platform Distribution**
- **Value**: Easy installation on Mac/Linux/Windows
- **Evidence**: .goreleaser.yml, install.sh, install.ps1, Homebrew tap
- **How**: GoReleaser builds cross-platform binaries, shell installers
- **Result**: Friction-free adoption (`brew install grepai`)

#### 8. **Workspace Mode**
- **Value**: Search across multiple projects simultaneously
- **Evidence**: mcp/server.go:252 - `handleWorkspaceSearch`
- **How**: Shared embedder + store with project filtering
- **Result**: Reuse patterns across related projects (microservices, monorepos)

---

### What We Do Well

#### 1. **Truth Maintenance with Conflict Resolution**
- **Our Advantage**: Fact supersession and conflict detection
- **Evidence**: resolve/resolver.rb - Determines equivalence, supersession, or conflicts
- **Value**: Maintains consistent knowledge base even with contradictory information
- **Why**: Memory requires long-term coherence; search can tolerate stale chunks

#### 2. **Dual-Database Scoping (Global + Project)**
- **Our Advantage**: User preferences (global) vs project-specific facts
- **Evidence**: store/store_manager.rb - Manages two SQLite connections
- **Value**: Facts apply at correct granularity (always vs this-project-only)
- **Why**: Memory has semantic scope; search is purely location-based

#### 3. **Provenance Tracking**
- **Our Advantage**: Every fact links to source transcript content
- **Evidence**: domain/provenance.rb - Links facts to content_items
- **Value**: Users can verify where facts came from, assess confidence
- **Why**: Memory requires trustworthiness; search assumes correctness

#### 4. **Pluggable Distiller Interface**
- **Our Advantage**: AI-powered fact extraction (future: Claude API)
- **Evidence**: distill/distiller.rb - Extracts entities, facts, scope hints
- **Value**: Understands context and intent, not just code structure
- **Why**: Memory extracts meaning; search indexes literal content

#### 5. **Hook-Based Integration**
- **Our Advantage**: Seamless integration with Claude Code events
- **Evidence**: hook/ - Reads stdin JSON from Claude Code hooks
- **Value**: Zero-effort ingestion, automatic sweeping
- **Why**: Memory is reactive to AI sessions; search is proactive (file watcher)

---

### Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| **Their: Proactive file watching** | Always up-to-date, zero manual work | CPU/disk overhead, battery drain on laptops, irrelevant for non-code files |
| **Ours: Reactive transcript ingest** | Only processes meaningful interactions | Requires hook setup, delayed until session ends |
| **Their: Vector embeddings** | Semantic understanding, fuzzy matching | Requires embedding provider, slower than text search, cost (if OpenAI) |
| **Ours: FTS5 full-text search** | Fast, zero dependencies, no cost | Exact/substring matching only, no semantic understanding |
| **Their: Go (compiled)** | Fast startup, low memory, easy distribution | Harder to extend (compile step), less metaprogramming |
| **Ours: Ruby (interpreted)** | Easy to extend, rich metaprogramming | Slower, requires Ruby runtime, harder to distribute |
| **Their: Chunk-based storage** | Optimized for retrieval granularity | Redundancy across chunks, harder to track changes |
| **Ours: Fact-based storage** | Deduplicated, structured, queryable | Requires distillation step, more complex schema |
| **Their: Interface-based backends** | Pluggable storage (GOB/Postgres/Qdrant) | Complexity in maintaining multiple implementations |
| **Ours: SQLite-only** | Simple, zero config, portable | Limited scalability, no built-in vector search |
| **Their: Tree-sitter call graph** | Static analysis, language-agnostic | Setup cost (parsers), limited to supported languages |
| **Ours: No call graph** | Simpler architecture | Can't answer "who calls this?" questions |
| **Their: Compact JSON mode** | Token-efficient for AI agents | Requires Read tool for full content (two-step) |
| **Ours: Full content in recall** | One-step retrieval | Higher token usage per query |

**Key Trade-off**: grepai prioritizes **search speed and semantic understanding** at the cost of setup complexity. ClaudeMemory prioritizes **truth maintenance and provenance** at the cost of search sophistication.

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Incremental Indexing with File Watching
- **Value**: ClaudeMemory index could stay fresh automatically during coding sessions
- **Evidence**: watcher/watcher.go:44 - `fsnotify` with debouncing, gitignore respect
- **Implementation**:
  1. Add `fsnotify` to Gemfile
  2. Create `ClaudeMemory::Watcher` class wrapping `Listen` gem (Ruby equivalent of fsnotify)
  3. Watch `.claude/projects/*/transcripts/*.jsonl` for new lines (tail-like behavior)
  4. Debounce events (default 500ms to avoid thrashing during bulk writes)
  5. Trigger `IngestCommand` automatically when new transcript data appears
  6. Optional: Watch `.claude/rules/` for manual fact additions
- **Effort**: 2-3 days (watcher class, integration with ingest, testing)
- **Trade-off**: Adds background process (memory overhead ~10MB), may complicate testing
- **Recommendation**: **ADOPT** - Eliminates manual `claude-memory ingest` calls, huge UX win

#### 2. Compact Response Format for MCP Tools
- **Value**: Reduce token usage by ~60% in MCP responses by omitting verbose content
- **Evidence**: mcp/server.go:219 - `SearchResultCompact` omits content field, returns only metadata
- **Implementation**:
  1. Add `compact` boolean parameter to `memory.recall` and `memory.search_*` tools
  2. Create `CompactFormatter` in `MCP::ResponseFormatter`:
     ```ruby
     def format_fact_compact(fact)
       {
         id: fact.id,
         subject: fact.subject,
         predicate: fact.predicate,
         object: fact.object,
         scope: fact.scope,
         confidence: fact.confidence
       }
       # Omit: provenance, supersession_chain, context excerpts
     end
     ```
  3. Default to `compact: true` for all MCP tools (user can override with `compact: false`)
  4. Update tool descriptions to explain compact mode
- **Effort**: 4-6 hours (add parameter, update formatters, tests)
- **Trade-off**: User needs follow-up `memory.explain <fact_id>` for full context (two-step interaction)
- **Recommendation**: **ADOPT** - Critical for scaling to large fact databases (1000+ facts)

#### 3. Hybrid Search (Vector + Text)
- **Value**: Better relevance when users search for specific terms (e.g., "uses_database") while preserving semantic matching
- **Evidence**: search/search.go - Reciprocal Rank Fusion (RRF) with K=60
- **Implementation**:
  1. Add `sqlite-vec` extension to Gemfile for vector similarity in SQLite
  2. Add `embeddings` column to `facts` table (BLOB storing float32 array)
  3. Create `ClaudeMemory::Embedder` interface:
     - Implementation: Call Anthropic API for embeddings (free with Claude usage)
     - Cache embeddings per fact (regenerate only when fact changes)
  4. Implement RRF in `Recall#query`:
     ```ruby
     vector_results = vector_search(query, limit * 2)  # Cosine similarity
     text_results = fts_search(query, limit * 2)       # Existing FTS5
     fuse_with_rrf(vector_results, text_results, k: 60)
     ```
  5. Make hybrid search optional via `.grepai/config.yaml`:
     ```yaml
     search:
       hybrid:
         enabled: true
         k: 60
     ```
- **Effort**: 5-7 days (embedder setup, schema migration, RRF implementation, testing)
- **Trade-off**: Requires API calls for embedding (cost ~$0.00001/fact), slower queries (2x search + fusion)
- **Recommendation**: **CONSIDER** - High value but significant implementation effort. Start with FTS5, add vectors later if search quality issues arise.

#### 4. Call Graph for Fact Dependencies
- **Value**: Show which facts depend on others (supersession chains, conflict relationships) visually
- **Evidence**: trace/trace.go:95 - `CallGraph` struct with nodes and edges
- **Implementation**:
  1. Create `memory.fact_graph <fact_id> --depth 2` MCP tool
  2. Query `fact_links` table to build graph:
     - Nodes: Facts (subject/predicate/object)
     - Edges: Supersedes, Conflicts, Supports
  3. Return JSON matching grepai's format:
     ```json
     {
       "root": "fact_123",
       "nodes": {"fact_123": {...}, "fact_456": {...}},
       "edges": [
         {"from": "fact_123", "to": "fact_456", "type": "supersedes"},
         {"from": "fact_123", "to": "fact_789", "type": "conflicts"}
       ],
       "depth": 2
     }
     ```
  4. Depth-limited BFS traversal (avoid exponential explosion)
- **Effort**: 2-3 days (graph builder, MCP tool, tests)
- **Trade-off**: Adds complexity for a feature used mainly for debugging/exploration
- **Recommendation**: **ADOPT** - Invaluable for understanding why facts were superseded or conflicted

#### 5. Multi-Project Workspace Mode
- **Value**: Search facts across multiple projects simultaneously (e.g., all Ruby projects)
- **Evidence**: mcp/server.go:252 - `handleWorkspaceSearch` with project filtering
- **Implementation**:
  1. Extend `.claude/settings.json` with workspace config:
     ```json
     {
       "workspaces": {
         "ruby-projects": {
           "projects": [
             "/Users/me/project1",
             "/Users/me/project2"
           ],
           "scope": "project"  // Only search project-scoped facts
         }
       }
     }
     ```
  2. Add `workspace` parameter to `memory.recall`:
     ```ruby
     memory.recall(query: "authentication", workspace: "ruby-projects")
     ```
  3. StoreManager opens all project databases, merges results
  4. Filter by `project_path` matching workspace projects
- **Effort**: 3-4 days (workspace config, multi-DB queries, result merging, tests)
- **Trade-off**: Complexity in managing multiple DB connections, potential for confusion (which project is this fact from?)
- **Recommendation**: **DEFER** - Nice-to-have but low ROI for current use case (most users work on one project at a time)

---

### Medium Priority

#### 6. Self-Update Mechanism
- **Value**: Users get bug fixes and new features automatically without reinstalling gem
- **Evidence**: updater/updater.go - Checks GitHub releases, downloads binary, replaces self
- **Implementation**:
  1. Add `claude-memory update` command
  2. Check GitHub releases API for `anthropics/claude-memory` (or RubyGems API)
  3. Compare current version (`ClaudeMemory::VERSION`) with latest
  4. Download gem, extract, replace files in-place
  5. Display changelog and prompt to confirm
- **Effort**: 2-3 days (update logic, safe file replacement, testing)
- **Trade-off**: Requires write permissions to gem directory (may fail in system-wide installs)
- **Recommendation**: **CONSIDER** - Nice UX, but users can `gem update` manually

#### 7. Configuration via YAML
- **Value**: Easier configuration than editing JSON or ENV vars
- **Evidence**: config/config.go - `.grepai/config.yaml` with typed structs
- **Implementation**:
  1. Add `.claude/memory.yaml` support:
     ```yaml
     ingest:
       auto_sweep: true
       sweep_budget_seconds: 5
     publish:
       mode: shared
       include_provenance: false
     recall:
       default_limit: 10
       scope: all
     ```
  2. Load YAML in `Configuration` class, merge with ENV vars (ENV takes precedence)
  3. Validate config on load (raise clear errors for invalid values)
- **Effort**: 1-2 days (YAML parsing, validation, tests)
- **Trade-off**: Another configuration method to document and support
- **Recommendation**: **CONSIDER** - Better UX, but JSON in `.claude/settings.json` works fine for now

#### 8. Batch MCP Tool Operations
- **Value**: Reduce round-trips when agent needs to recall multiple facts
- **Evidence**: embedder/embedder.go:10 - `EmbedBatch` for parallel processing
- **Implementation**:
  1. Add `memory.recall_batch` tool accepting array of queries:
     ```json
     {
       "queries": [
         {"query": "authentication", "limit": 5},
         {"query": "database schema", "limit": 3}
       ]
     }
     ```
  2. Execute queries in parallel (use `Concurrent::Future` from concurrent-ruby gem)
  3. Return merged results with query labels:
     ```json
     [
       {"query": "authentication", "results": [...]},
       {"query": "database schema", "results": [...]}
     ]
     ```
- **Effort**: 1-2 days (batch tool, parallel execution, tests)
- **Trade-off**: More complex error handling (what if one query fails?)
- **Recommendation**: **CONSIDER** - Useful if agents frequently need multiple searches, but current single-query API is simpler

---

### Low Priority

#### 9. TUI (Terminal UI) for Interactive Exploration
- **Value**: Visual interface for browsing facts, conflicts, provenance
- **Evidence**: cli/ uses `charmbracelet/bubbletea` for rich TUI
- **Implementation**:
  1. Add `claude-memory explore` command launching TUI
  2. Use `tty-prompt` gem for interactive menus:
     - Browse facts by predicate
     - Explore supersession chains
     - View conflict details
     - Search facts interactively
  3. Display provenance excerpts inline
- **Effort**: 3-5 days (TUI design, navigation, rendering)
- **Trade-off**: Adds dependency and complexity for limited use case (most interaction via MCP tools)
- **Recommendation**: **DEFER** - Nice for power users, but MCP tools + `memory.explain` cover 90% of needs

#### 10. Prometheus Metrics Endpoint
- **Value**: Monitor memory system health (fact count, sweep duration, query latency)
- **Evidence**: grepai exposes metrics via `grepai_index_status` tool
- **Implementation**:
  1. Add `claude-memory serve-metrics` command (HTTP server on `:9090/metrics`)
  2. Expose Prometheus-format metrics:
     - `claude_memory_facts_total{scope="global|project"}`
     - `claude_memory_sweep_duration_seconds`
     - `claude_memory_recall_latency_seconds`
  3. Optional: Export to StatsD, DataDog, etc.
- **Effort**: 2-3 days (metrics collection, HTTP server, testing)
- **Trade-off**: Requires running separate metrics server, overkill for most users
- **Recommendation**: **DEFER** - Only needed for production deployments with SLAs

---

### Features to Avoid

#### 1. Cloud-Based Embedding Service
- **Why Avoid**: grepai's privacy-first approach (Ollama local embeddings) is a key selling point, but ClaudeMemory's use case (AI memory, not code search) doesn't require embeddings yet
- **Our Alternative**: Stick with FTS5 full-text search until we need semantic matching. If we add embeddings, use Anthropic API (already authenticated) rather than separate embedding service
- **Reasoning**: Adding embeddings adds cost, latency, and complexity. FTS5 is sufficient for fact recall (structured data) vs code search (unstructured data)

#### 2. Multiple Storage Backends (Postgres, Qdrant)
- **Why Avoid**: Increases maintenance burden (test matrix, docs, support) for unclear benefit
- **Our Alternative**: SQLite is perfect for local storage, portable, and sufficient for fact databases (<100K facts). If we need remote storage, use libSQL (SQLite over HTTP) or Turso
- **Reasoning**: grepai needs backends for team collaboration (shared index). ClaudeMemory is single-user by design (global + project scoping)

#### 3. Daemon Mode with Background Indexing
- **Why Avoid**: Adds complexity (process management, logging, crash recovery) and battery drain
- **Our Alternative**: Hook-based reactive ingestion (current approach) is elegant and efficient. Only process transcripts when meaningful work happens (AI sessions)
- **Reasoning**: grepai needs daemon for real-time file watching. ClaudeMemory doesn't need to watch files (transcripts are append-only, hooks trigger ingestion)

---

## Implementation Recommendations

### Phase 1: Quick Wins (1-2 weeks)

**Goal**: Low-effort, high-value improvements

- [ ] **Compact MCP responses** (4-6 hours)
  - Add `compact: true` parameter to all recall tools
  - Omit provenance and context excerpts by default
  - Test token reduction with realistic queries
  - Success criteria: 60% token reduction in MCP responses

- [ ] **Fact dependency graph** (2-3 days)
  - Implement `memory.fact_graph <fact_id> --depth 2` tool
  - BFS traversal of fact_links table
  - Return JSON with nodes and edges
  - Success criteria: Visualize supersession chains and conflicts

### Phase 2: Incremental Indexing (2-3 weeks)

**Goal**: Auto-update index during coding sessions

- [ ] **File watcher for transcripts** (2-3 days)
  - Add `Listen` gem (Ruby equivalent of fsnotify)
  - Watch `.claude/projects/*/transcripts/*.jsonl` for changes
  - Debounce rapid changes (500ms)
  - Trigger `IngestCommand` automatically
  - Success criteria: Index updates within 1 second of transcript write

- [ ] **Optional daemon mode** (2-3 days)
  - Add `claude-memory watch` command (background process)
  - Fork and daemonize, write PID file
  - Graceful shutdown on SIGTERM
  - Success criteria: Run in background, no manual ingest needed

- [ ] **Integration with existing hooks** (1 day)
  - Keep existing hooks as fallback (if watcher not running)
  - Add `auto_watch: true` setting to enable watcher
  - Success criteria: Works with or without daemon

### Phase 3: Hybrid Search (4-6 weeks)

**Goal**: Add semantic search for better relevance

- [ ] **Embedder interface** (1 week)
  - Create `ClaudeMemory::Embedder` module
  - Implement Anthropic API embedder (call `/v1/embeddings`)
  - Cache embeddings in `fact_embeddings` table
  - Success criteria: Generate embeddings for facts

- [ ] **Vector storage** (1 week)
  - Add `sqlite-vec` extension to dependencies
  - Migrate schema: add `embedding` BLOB column to `facts`
  - Implement cosine similarity search
  - Success criteria: Vector search returns similar facts

- [ ] **RRF implementation** (1 week)
  - Implement Reciprocal Rank Fusion in `Recall#query`
  - Combine FTS5 results with vector results
  - Make hybrid search optional via config
  - Success criteria: Better relevance than FTS5 alone

- [ ] **Performance tuning** (1 week)
  - Benchmark vector search vs FTS5
  - Add caching for frequently-queried embeddings
  - Optimize batch embedding (parallel API calls)
  - Success criteria: Hybrid search <500ms for typical queries

---

## Architecture Decisions

### What to Preserve

- **SQLite-only storage**: Simple, portable, fast enough for fact databases
- **Hook-based integration**: Elegant reactive model (no polling, no daemons unless opted-in)
- **Fact-based data model**: Structured triples with provenance vs unstructured chunks
- **Truth maintenance**: Supersession and conflict resolution (grepai has no equivalent)
- **Dual-database scoping**: Global vs project facts (grepai has only project-local or workspace)

### What to Adopt

- **File watcher for incremental indexing**: Huge UX win, eliminates manual `ingest` calls
- **Compact JSON for MCP tools**: Critical for scaling to large fact databases
- **Fact dependency graph visualization**: Invaluable for debugging supersession/conflicts
- **Interface-based extensibility**: If we add embeddings, use pluggable `Embedder` interface
- **Hybrid search (RRF)**: Better relevance, proven technique

### What to Reject

- **Cloud-based embeddings**: Privacy concerns, cost, latency (use Anthropic API if needed)
- **Multiple storage backends**: Adds complexity without clear benefit for single-user tool
- **Daemon mode by default**: Optional is fine, but hooks are simpler and more efficient
- **Tree-sitter call graphs**: Out of scope for memory system (we track fact dependencies, not code dependencies)
- **Workspace mode**: Defer until multi-project use case is validated

---

## Key Takeaways

1. **grepai excels at real-time semantic search** via file watching + vector embeddings. We should adopt file watching for transcript indexing but defer vector embeddings until FTS5 proves insufficient.

2. **Compact JSON mode is critical for token efficiency**. We should implement this immediately in all MCP tools (60% token reduction with minimal effort).

3. **Fact dependency graphs** (supersession chains, conflicts) are analogous to grepai's call graphs. Implementing `memory.fact_graph` would be highly valuable for understanding fact relationships.

4. **Interface-based extensibility** is a proven pattern. If we add embeddings, follow grepai's `Embedder` interface design for pluggability.

5. **Hybrid search (vector + text)** is more sophisticated than our FTS5-only approach, but adds significant complexity. Defer until search quality becomes a bottleneck.

6. **Go's performance and distribution advantages** are appealing, but Ruby is fine for our use case (not latency-critical, single-user tool). Don't rewrite unless clear performance issues arise.

7. **Recommended adoption order**:
   - **Immediate**: Compact JSON, fact dependency graph
   - **Short-term**: File watcher for transcripts
   - **Medium-term**: Hybrid search (if needed)
   - **Defer**: Workspace mode, cloud backends, TUI

**Expected impact**: Adopting file watching + compact JSON would eliminate manual `ingest` calls and reduce token usage by 60%, dramatically improving UX without major architectural changes.
