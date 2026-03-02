# grepai Analysis (Updated)

*Analysis Date: 2026-03-02*
*Previous Analysis: 2026-01-29*
*Repository: https://github.com/yoanbernabeu/grepai*
*Version: 0.34.0 (commit 1c7aba9)*

---

## Executive Summary

### Project Purpose

grepai is a privacy-first CLI for semantic code search using vector embeddings. It enables natural language queries that find relevant code by meaning, not just text — reducing AI agent input tokens by providing targeted context.

### Key Innovation (What's New Since Last Study)

1. **RPG Semantic Graph Layer** (v0.31.0, `rpg/`): A full knowledge graph for code that maps functional areas, categories, symbols, and their relationships. Uses Jaccard similarity for feature matching, co-caller affinity edges, and hierarchical organization (Area → Category → Subcategory → File → Symbol → Chunk).

2. **Workspace Mode** (v0.31.0): Multi-project support with cross-project call graph analysis, workspace-aware file watching, and per-project symbol stores.

3. **Bubble Tea TUI** (v0.34.0): Interactive terminal UI for watch, status, trace, init, and workspace commands.

4. **MCP Discovery Commands** (v0.34.0): `grepai_list_workspaces` and `grepai_list_projects` tools for AI agents to discover available search scopes.

5. **New Embedding Providers** (v0.32.0): Synthetic API and OpenRouter added alongside Ollama, LM Studio, and OpenAI. Factory pattern (`NewFromConfig`/`NewFromWorkspaceConfig`) centralizes provider initialization.

6. **Multi-Worktree Support** (v0.29.0-0.30.0): Git worktree detection, auto-init, and parallel watching via errgroup.

### Technology Stack

| Component | Technology |
|-----------|-----------|
| **Language** | Go 1.22+ |
| **Vector Store** | GOB (file-based), PostgreSQL/pgvector, Qdrant |
| **Embedding** | Ollama (default), LM Studio, OpenAI, Synthetic, OpenRouter |
| **File Watching** | fsnotify with debouncing |
| **CLI Framework** | cobra |
| **MCP** | mark3labs/mcp-go |
| **Call Graph** | tree-sitter (Go, TypeScript, C#, F#, more) |
| **Knowledge Graph** | RPG (custom, GOB-serialized) |
| **Testing** | Go stdlib + race detection |
| **TUI** | Bubble Tea |

### Production Readiness

- **Maturity**: Production-ready (v0.34.0, active community)
- **Test Coverage**: Comprehensive (race detection, cross-platform)
- **Documentation**: Dedicated docs site, blog, benchmarks
- **Distribution**: Homebrew, multi-platform binaries
- **Community**: 280K+ views on Reddit, ProductHunt featured, active contributors

---

## Architecture Overview

### Data Model (Updated)

**Three-Layer Index**:

1. **Vector Index** (semantic search): Chunks with embeddings, pluggable backends
2. **Symbol Index** (call graph): tree-sitter AST → Symbol/Reference/CallEdge
3. **RPG Semantic Graph** (v0.31.0, NEW):

```
Area (functional area, top-level)          [V_H]
  └── Category                             [V_H]
      └── Subcategory                      [V_H]
          └── File (source file)           [V_L]
              └── Symbol (function/class)  [V_L]
                  └── Chunk (vector ref)   [V_L]
```

**Edge Types** (`rpg/model.go:27-38`):
- `feature_parent`: Hierarchy edges
- `contains`: File → Symbol containment
- `invokes`: Call graph edges
- `imports`: Import relationships
- `maps_to_chunk`: Symbol → vector chunk
- `semantic_sim`: Feature similarity edges

### Key Design Patterns (Updated)

1. **RPG Encoder** (`rpg/indexer.go:29-75`): Orchestrates graph building from symbol store + vector store. Uses drift thresholds, feature extractors, and hierarchy builders.

2. **Triple Query Engine** (`rpg/query.go:72-80`): Three operations — `SearchNode` (Jaccard similarity), `FetchNode` (detailed context with parents/children/edges), `Explore` (graph traversal with depth/direction/edge-type filters).

3. **File Watcher with Debouncing** (`watcher/watcher.go:30-59`): fsnotify with configurable debounce, gitignore-aware, event deduplication via pending map.

4. **Embedder Factory** (`embedder/factory.go`): `NewFromConfig`/`NewFromWorkspaceConfig` centralizes provider initialization across CLI and MCP server. Supports Ollama, LM Studio, OpenAI, Synthetic, OpenRouter.

5. **GOB File Locking** (v0.29.0): Cross-process safety for shared index files. Prevents data corruption in multi-process scenarios.

### Comparison with ClaudeMemory

| Aspect | grepai (0.34.0) | ClaudeMemory | Notes |
|--------|-----------------|--------------|-------|
| **Data Model** | Code chunks + RPG graph | Subject-predicate-object facts | Different domains |
| **Storage** | GOB/PostgreSQL/Qdrant | Dual SQLite | We're simpler |
| **Embeddings** | Ollama/OpenAI/etc (remote) | fastembed-rb (local ONNX) | We're self-contained |
| **File Watching** | fsnotify + debounce | None (hook-triggered) | They auto-index |
| **Knowledge Graph** | RPG semantic graph | Fact links (supersession/conflict) | Different purpose |
| **MCP** | mcp-go (Go) | Custom Ruby MCP server | Different languages |
| **CLI** | cobra (Go) | Custom Ruby CLI | Different stacks |

---

## Key Components Deep-Dive

### Component 1: RPG Semantic Graph (NEW)

**Purpose**: Map code structure into searchable knowledge graph with functional areas, categories, and semantic relationships.

**Location**: `rpg/` (model.go, indexer.go, query.go, hierarchy.go, evolver.go)

**Implementation** (`rpg/model.go:42-80`):
```go
type Node struct {
    ID            string    `json:"id"`
    Kind          NodeKind  `json:"kind"`           // area, category, file, symbol, chunk
    Feature       string    `json:"feature"`         // primary semantic label
    Features      []string  `json:"features"`        // atomic semantic features
    Path          string    `json:"path,omitempty"`
    SymbolName    string    `json:"symbol_name,omitempty"`
    Summary       string    `json:"summary,omitempty"` // LLM-generated
}
```

**Design Decisions**:
- Hierarchical: Area → Category → Subcategory → File → Symbol → Chunk
- Feature-based similarity using Jaccard coefficient
- Co-caller affinity edges with occurrence threshold
- Drift threshold for incremental updates (`RPGEncoderConfig.DriftThreshold`)
- GOB serialization for persistence

### Component 2: File Watcher

**Purpose**: Keep index fresh automatically as files change.

**Location**: `watcher/watcher.go:30-80`

```go
type Watcher struct {
    root       string
    watcher    *fsnotify.Watcher
    ignore     *indexer.IgnoreMatcher
    debounceMs int
    events     chan FileEvent
    pending    map[string]FileEvent  // debounce deduplication
}
```

**Design Decisions**:
- Configurable debounce (default 300ms)
- Recursive directory watching
- Gitignore-aware filtering
- Event deduplication via pending map
- Multi-worktree support (v0.30.0)

### Component 3: MCP Discovery Tools (NEW)

**Purpose**: Let AI agents discover available search scopes.

**Location**: `mcp/server.go`

**Design Decisions**:
- `grepai_list_workspaces`: Returns workspace-level entries for scope selection
- `grepai_list_projects`: Returns relative paths within workspace
- Compact vs full output modes for token efficiency

---

## Comparative Analysis

### What They Do Well

1. **RPG Knowledge Graph**: Rich semantic structure for code understanding
2. **File Watching**: Automatic index updates without manual commands
3. **Embedder Factory**: Clean abstraction for multiple embedding providers
4. **Cross-Process Safety**: GOB file locking prevents data corruption
5. **MCP Discovery**: Agent-friendly scope exploration tools
6. **Multi-Worktree**: Git worktree detection and parallel watching

### What We Do Well

1. **Self-Contained Embeddings**: fastembed-rb needs no external service
2. **Dual-Database Scope**: Project/global separation is cleaner
3. **Truth Maintenance**: Temporal validity and conflict resolution
4. **Rich MCP Tools**: 18 specialized tools vs their general search
5. **Simpler Architecture**: No background processes or external databases

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Incremental Indexing with File Watching
- **Value**: Eliminates manual `claude-memory ingest` calls
- **Evidence**: `watcher/watcher.go:30-59` — fsnotify with debouncing, gitignore respect
- **Implementation**: Add `listen` gem (Ruby fsnotify equivalent), watch `.claude/projects/*/transcripts/*.jsonl`, debounce 500ms, trigger IngestCommand
- **Effort**: 2-3 days
- **Trade-off**: Background process ~10MB memory overhead
- **Recommendation**: **CONSIDER** — Already in improvements.md (#3), reinforced by this study

### Medium Priority

#### 2. MCP Discovery Tools
- **Value**: Let Claude discover available search scopes before querying
- **Evidence**: `mcp/server.go` — `grepai_list_workspaces`, `grepai_list_projects`
- **Implementation**: Add `memory.list_projects` tool showing databases with fact counts
- **Effort**: 1 day
- **Trade-off**: Minimal — useful metadata
- **Recommendation**: **CONSIDER**

#### 3. Embedder Factory Pattern
- **Value**: Clean abstraction for swapping embedding providers
- **Evidence**: `embedder/factory.go` — `NewFromConfig` centralizes initialization
- **Implementation**: Our fastembed-rb is already self-contained, but a factory would help if we add sqlite-vec and need to support different models
- **Effort**: 1-2 days
- **Trade-off**: Premature unless we add multiple embedding providers
- **Recommendation**: **DEFER**

### Features to Avoid

- **RPG Knowledge Graph**: Wrong domain — code graph vs fact graph
- **Ollama/External Embeddings**: We use local ONNX embeddings (fastembed-rb)
- **PostgreSQL/Qdrant**: Over-engineering for our SQLite-based architecture
- **tree-sitter AST**: Not relevant to fact/memory retrieval
- **Bubble Tea TUI**: CLI output is sufficient
- **GOB Serialization**: We use SQLite which has built-in ACID

---

## Key Takeaways

### Changes Since Last Analysis (2026-01-29)
- RPG Semantic Graph Layer added (v0.31.0) — major new feature
- Workspace mode for multi-project support
- Bubble Tea TUI for interactive commands
- MCP discovery commands (list_workspaces, list_projects)
- Synthetic API + OpenRouter embedding providers
- Multi-worktree detection and parallel watching
- .grepaiignore support
- F# language support for trace

### Main Learnings
1. RPG graph is interesting but wrong domain for us
2. File watching with debouncing remains the best auto-indexing approach
3. MCP discovery tools are a nice UX pattern for multi-scope systems
4. Factory patterns for embedding providers are smart if you support multiple backends

---

*Analysis completed: 2026-03-02*
*Analyst: Claude Code*
*Review Status: Draft*
