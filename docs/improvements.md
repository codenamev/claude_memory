# Improvements to Consider

*Updated: 2026-01-23*
*Sources:*
- *[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) - Memory compression system*
- *[obra/episodic-memory](https://github.com/obra/episodic-memory) - Semantic conversation search*

This document identifies design patterns and features from claude-mem and episodic-memory that could improve claude_memory. Implemented improvements have been removed from this document.

---

## Implemented Improvements ✓

The following improvements from the original analysis have been successfully implemented:

1. **Progressive Disclosure Pattern** - `memory.recall_index` and `memory.recall_details` MCP tools with token estimation
2. **Privacy Tag System** - ContentSanitizer with `<private>`, `<no-memory>`, and `<secret>` tag stripping
3. **Slim Orchestrator Pattern** - CLI refactored to thin router with extracted command classes
4. **Semantic Shortcuts** - `memory.decisions`, `memory.conventions`, and `memory.architecture` MCP tools
5. **Exit Code Strategy** - Hook::ExitCodes module with SUCCESS/WARNING/ERROR constants
6. **WAL Mode for Concurrency** - SQLite Write-Ahead Logging enabled for better concurrent access
7. **Enhanced Statistics** - Comprehensive stats command showing facts, entities, provenance, conflicts
8. **Session Metadata Tracking** - Captures git_branch, cwd, claude_version, thinking_level from transcripts
9. **Tool Usage Tracking** - Dedicated tool_calls table tracking tool names, inputs, timestamps
10. **Semantic Search with TF-IDF** - Local embeddings (384-dimensional), hybrid vector + text search
11. **Multi-Concept AND Search** - Query facts matching all of 2-5 concepts simultaneously
12. **Incremental Sync** - mtime-based change detection to skip unchanged transcript files
13. **Context-Aware Queries** - Filter facts by git branch, directory, or tools used

---

## Design Decisions

### No Tag Count Limit (2026-01-23)

**Decision**: Removed MAX_TAG_COUNT limit from ContentSanitizer.

**Rationale**:
- The regex pattern `/<tag>.*?<\/tag>/m` is provably safe from ReDoS attacks
  - Non-greedy matching (`.*?`) with clear delimiters
  - No nested quantifiers or alternation that could cause catastrophic backtracking
  - Performance is O(n) and predictable
- Performance benchmarks show excellent speed even at scale:
  - 100 tags: 0.07ms
  - 200 tags: 0.13ms
  - 1,000 tags: 0.64ms
- Real-world usage legitimately produces 100-200+ tags in long sessions
  - System tags like `<claude-memory-context>` accumulate
  - Users mark multiple sections with `<private>` tags
- The limit created false alarms and blocked legitimate ingestion
- No other similar tool (claude-mem, episodic-memory) enforces tag count limits

**Do not reintroduce**: Tag count validation is unnecessary and harmful. If extreme input causes issues, investigate the actual root cause rather than adding arbitrary limits.

---

## Executive Summary

This document analyzes two complementary memory systems:

**Claude-mem** (TypeScript/Node.js, v9.0.5) - Memory compression system with 6+ months of production usage:
- ROI Metrics tracking token costs
- Health monitoring and process management
- Configuration-driven context injection

**Episodic-memory** (TypeScript/Node.js, v1.0.15) - Semantic conversation search for Claude Code:
- Local vector embeddings (Transformers.js)
- Multi-concept AND search
- Automatic conversation summarization
- Tool usage tracking
- Session metadata capture
- Background sync with incremental updates

**Our Current Advantages**:
- Ruby ecosystem (simpler dependencies)
- Dual-database architecture (global + project scope)
- Fact-based knowledge graph (vs observation blobs or conversation exchanges)
- Truth maintenance system (conflict resolution)
- Predicate policies (single vs multi-value)
- Progressive disclosure already implemented
- Privacy tag stripping already implemented

**High-Value Opportunities from Episodic-Memory**:
- Vector embeddings for semantic search alongside FTS5
- Tool usage tracking during fact discovery
- Session metadata capture (git branch, working directory)
- Multi-concept AND search
- Background sync with incremental updates
- Enhanced statistics and reporting

---

## Episodic-Memory Comparison

### Architecture Overview

**Episodic-memory** focuses on **conversation-level semantic search** rather than fact extraction. Key differences:

| Feature | Episodic-Memory | ClaudeMemory |
|---------|----------------|--------------|
| **Data Model** | Conversation exchanges (user-assistant pairs) | Facts (subject-predicate-object triples) |
| **Search Method** | Vector embeddings + text search | FTS5 full-text search |
| **Embeddings** | Local Transformers.js (Xenova/all-MiniLM-L6-v2) | None (FTS5 only) |
| **Vector Storage** | sqlite-vec virtual table | N/A |
| **Scope** | Single database with project field | Dual database (global + project) |
| **Truth Maintenance** | None (keeps all conversations) | Supersession + conflict resolution |
| **Summarization** | Claude API generates summaries | N/A |
| **Tool Tracking** | Explicit tool_calls table | Mentioned in provenance text |
| **Session Metadata** | sessionId, cwd, gitBranch, claudeVersion, thinking metadata | Limited (session_id in content_items) |
| **Multi-Concept Search** | Array-based AND queries (2-5 concepts) | Single query only |
| **Incremental Sync** | Timestamp-based mtime checks | Re-processes all content |
| **Background Processing** | Async hook with --background flag | Synchronous hook execution |
| **Statistics** | Rich stats with project breakdown | Basic status command |
| **Exclusion** | Content-based markers (`<INSTRUCTIONS-TO-EPISODIC-MEMORY>DO NOT INDEX`) | Tag stripping (`<private>`, `<no-memory>`) |
| **Line References** | Stores line_start and line_end for each exchange | No line tracking |
| **WAL Mode** | Enabled for concurrency | Not enabled |

### What Episodic-Memory Does Well

1. **Semantic Search with Local Embeddings**
   - Uses Transformers.js to run embedding model locally (offline-capable)
   - 384-dimensional vectors from `Xenova/all-MiniLM-L6-v2`
   - Hybrid vector + text search for best recall
   - sqlite-vec virtual table for fast similarity queries

2. **Multi-Concept AND Search**
   - Array of 2-5 concepts that must all be present in results
   - Searches each concept independently then intersects results
   - Ranks by average similarity across all concepts
   - Example: `["React Router", "authentication", "JWT"]`

3. **Tool Usage Tracking**
   - Dedicated `tool_calls` table with foreign key to exchanges
   - Captures tool_name, tool_input, tool_result, is_error
   - Tool names included in embeddings for tool-based searches
   - Search results show tool usage summary

4. **Rich Session Metadata**
   - Captures: sessionId, cwd, gitBranch, claudeVersion
   - Thinking metadata: level, disabled, triggers
   - Conversation structure: parentUuid, isSidechain
   - Enables filtering by branch, project context

5. **Incremental Sync**
   - Atomic file operations (temp file + rename)
   - mtime-based change detection (only copies modified files)
   - Fast subsequent syncs (seconds vs minutes)
   - Safe concurrent execution

6. **Automatic Conversation Summarization**
   - Uses Claude API to generate concise summaries
   - Summaries stored as `.txt` files alongside conversations
   - Concurrency-limited batch processing
   - Summary limit (default 10 per sync) to control API costs

7. **Background Sync**
   - `--background` flag for async processing
   - SessionStart hook runs sync without blocking
   - User continues working while indexing happens
   - Output logged to file for debugging

8. **Line-Range References**
   - Stores line_start and line_end for each exchange
   - Enables precise source linking in search results
   - Supports pagination: read specific line ranges from large conversations
   - Example: "Lines 10-25 in conversation.jsonl (295KB, 1247 lines)"

9. **Statistics and Reporting**
   - Total conversations, exchanges, date range
   - Summary coverage tracking
   - Project breakdown with top 10 projects
   - Database size reporting

10. **Exclusion Markers**
    - Content-based opt-out: `<INSTRUCTIONS-TO-EPISODIC-MEMORY>DO NOT INDEX THIS CHAT</INSTRUCTIONS-TO-EPISODIC-MEMORY>`
    - Files archived but excluded from search index
    - Prevents meta-conversations from polluting index
    - Use case: sensitive work, test sessions, agent conversations

11. **WAL Mode for Concurrency**
    - SQLite Write-Ahead Logging enabled
    - Better concurrency for multiple readers
    - Safe for concurrent sync operations

### Design Patterns Worth Adopting

1. **Local Vector Embeddings**
   - **Value**: Semantic search finds conceptually similar content even with different terminology
   - **Implementation**: Add `embeddings` column to facts table, use sqlite-vec extension
   - **Ruby gems**: `onnxruntime` or shell out to Python/Node.js for embeddings
   - **Trade-off**: Increased storage (384 floats per fact), embedding generation time

2. **Multi-Concept AND Search**
   - **Value**: Precise queries like "find conversations about React AND authentication AND JWT"
   - **Implementation**: Run multiple searches and intersect results, rank by average similarity
   - **Application to facts**: Find facts matching multiple predicates or entities
   - **MCP tool**: `memory.search_concepts(concepts: ["auth", "API", "security"])`

3. **Tool Usage Tracking**
   - **Value**: Know which tools were used during fact discovery (Read, Edit, Bash, etc.)
   - **Implementation**: Add `tool_calls` table or JSON column in content_items
   - **Schema**: `{ tool_name, tool_input, tool_result, timestamp }`
   - **Use case**: "Which facts were discovered using the Bash tool?"

4. **Session Metadata Capture**
   - **Value**: Context about where/when facts were learned
   - **Implementation**: Extend content_items with git_branch, cwd, claude_version columns
   - **Use case**: "Show facts learned while on feature/auth branch"

5. **Incremental Sync**
   - **Value**: Faster subsequent ingestions (seconds vs minutes)
   - **Implementation**: Store mtime for each content_item, skip unchanged files
   - **Hook optimization**: Only process delta since last ingest

6. **Background Processing**
   - **Value**: Don't block user while processing large transcripts
   - **Implementation**: Fork process or use Ruby's async/await
   - **Hook flag**: `claude-memory hook ingest --async`

7. **Line-Range References in Provenance**
   - **Value**: Precise source linking for fact verification
   - **Implementation**: Store line_start and line_end in provenance table
   - **Display**: "Fact from lines 42-56 in transcript.jsonl"

8. **Statistics Command**
   - **Value**: Visibility into memory system health
   - **Implementation**: Enhance `claude-memory status` with more metrics
   - **Metrics**: Facts by predicate, entities by type, provenance coverage, scope breakdown

9. **WAL Mode**
   - **Value**: Better concurrency, safer concurrent operations
   - **Implementation**: `db.pragma('journal_mode = WAL')` in store initialization
   - **Benefit**: Multiple readers don't block each other

---

## 1. ROI Metrics and Token Economics

### What claude-mem Does

**Discovery Token Tracking**:
- `discovery_tokens` field on observations table
- Tracks tokens spent discovering each piece of knowledge
- Cumulative metrics in session summaries
- Footer displays ROI: "Access 10k tokens for 2,500t"

**File**: `src/services/sqlite/Database.ts`

```typescript
observations: {
  id: INTEGER PRIMARY KEY,
  title: TEXT,
  narrative: TEXT,
  discovery_tokens: INTEGER,  // ← Cost tracking
  created_at_epoch: INTEGER
}

session_summaries: {
  cumulative_discovery_tokens: INTEGER,  // ← Running total
  observation_count: INTEGER
}
```

**Context Footer Example**:
```markdown
💡 **Token Economics:**
- Context shown: 2,500 tokens
- Research captured: 10,000 tokens
- ROI: 4x compression
```

### What We Should Do

**Priority**: MEDIUM

**Implementation**:

1. **Add metrics table**:
   ```ruby
   create_table :ingestion_metrics do
     primary_key :id
     foreign_key :content_item_id, :content_items
     Integer :input_tokens
     Integer :output_tokens
     Integer :facts_extracted
     DateTime :created_at
   end
   ```

2. **Track during distillation**:
   ```ruby
   # lib/claude_memory/distill/distiller.rb
   def distill(content)
     response = api_call(content)
     facts = extract_facts(response)

     store_metrics(
       input_tokens: response.usage.input_tokens,
       output_tokens: response.usage.output_tokens,
       facts_extracted: facts.size
     )

     facts
   end
   ```

3. **Display in CLI**:
   ```ruby
   # claude-memory stats
   def stats_cmd
     metrics = store.aggregate_metrics
     puts "Token Economics:"
     puts "  Input: #{metrics[:input_tokens]} tokens"
     puts "  Output: #{metrics[:output_tokens]} tokens"
     puts "  Facts: #{metrics[:facts_extracted]}"
     puts "  Efficiency: #{metrics[:facts_extracted] / metrics[:input_tokens].to_f} facts/token"
   end
   ```

4. **Add to published snapshot**:
   ```markdown
   <!-- At bottom of .claude/rules/claude_memory.generated.md -->

   ---

   *Memory stats: 145 facts from 12,500 ingested tokens (86 facts/1k tokens)*
   ```

**Benefits**:
- Visibility into memory system efficiency
- Justifies API costs (shows compression ratio)
- Helps tune distillation prompts for better extraction

**Trade-offs**:
- Requires API usage tracking
- Adds database complexity
- May not be meaningful for all distiller implementations

---

## 2. Health Monitoring and Process Management

### What claude-mem Does

**Worker Service Management**:

```typescript
// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    port: WORKER_PORT,
    memory: process.memoryUsage(),
    version: packageJson.version
  });
});

// Smart startup
async function ensureWorkerHealthy(timeout = 10000) {
  const healthy = await checkHealth();
  if (!healthy) {
    await startWorker();
    await waitForHealth(timeout);
  }
}
```

**Process Management**:
- PID file tracking (`~/.claude-mem/worker.pid`)
- Port conflict detection
- Version mismatch warnings
- Graceful shutdown handlers
- Platform-aware timeouts (Windows vs Unix)

**File**: `src/infrastructure/ProcessManager.ts`

### What We Should Do

**Priority**: LOW (we use MCP server, not background worker)

**Implementation** (if we add background worker):

1. **Health endpoint in MCP server**:
   ```ruby
   # lib/claude_memory/mcp/server.rb
   def handle_ping
     {
       status: "ok",
       version: ClaudeMemory::VERSION,
       databases: {
         global: File.exist?(global_db_path),
         project: File.exist?(project_db_path)
       },
       uptime: Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
     }
   end
   ```

2. **PID file management**:
   ```ruby
   # lib/claude_memory/daemon.rb
   class Daemon
     PID_FILE = File.expand_path("~/.claude/memory_server.pid")

     def start
       check_existing_process
       fork_and_daemonize
       write_pid_file
       setup_signal_handlers
       run_server
     end

     def stop
       pid = read_pid_file
       Process.kill("TERM", pid)
       wait_for_shutdown
       remove_pid_file
     end
   end
   ```

**Benefits**:
- Reliable server lifecycle
- Easy debugging (health checks)
- Prevents duplicate processes

**Trade-offs**:
- Complexity we may not need
- Ruby daemons are tricky on Windows
- MCP stdio transport doesn't need health checks

**Verdict**: Skip unless we switch to HTTP-based MCP transport.

---

## 3. Web-Based Viewer UI

### What claude-mem Does

**Real-Time Memory Viewer** at `http://localhost:37777`:

- React-based web UI
- Server-Sent Events (SSE) for real-time updates
- Infinite scroll pagination
- Project filtering
- Settings persistence (sidebar state, theme)
- Auto-reconnection with exponential backoff
- Single-file HTML bundle (esbuild)

**File**: `src/ui/viewer/` (React components)

**Features**:
- See observations as they're captured
- Search historical observations
- Filter by project
- Export/share observations
- Theme toggle (light/dark)

**Build**:
```typescript
esbuild.build({
  entryPoints: ['src/ui/viewer/index.tsx'],
  bundle: true,
  outfile: 'plugin/ui/viewer.html',
  loader: { '.tsx': 'tsx', '.woff2': 'dataurl' },
});
```

### What We Should Do

**Priority**: LOW (nice-to-have)

**Implementation** (if we want it):

1. **Add Sinatra web server**:
   ```ruby
   # lib/claude_memory/web/server.rb
   require 'sinatra/base'
   require 'json'

   module ClaudeMemory
     module Web
       class Server < Sinatra::Base
         get '/' do
           erb :index
         end

         get '/api/facts' do
           facts = Recall.search(params[:query], limit: 100)
           json facts
         end

         get '/api/stream' do
           stream :keep_open do |out|
             # SSE for real-time updates
             EventMachine.add_periodic_timer(1) do
               out << "data: #{recent_facts.to_json}\n\n"
             end
           end
         end
       end
     end
   end
   ```

2. **Add to MCP server** (optional HTTP endpoint):
   ```ruby
   # claude-memory serve --web
   def serve_with_web
     Thread.new { Web::Server.run!(port: 37778) }
     serve_mcp  # Main MCP server
   end
   ```

3. **Simple HTML viewer**:
   ```html
   <!-- lib/claude_memory/web/views/index.erb -->
   <!DOCTYPE html>
   <html>
   <head>
     <title>ClaudeMemory Viewer</title>
     <style>/* Minimal CSS */</style>
   </head>
   <body>
     <div id="facts-list"></div>
     <script>
       // Fetch and display facts
       fetch('/api/facts')
         .then(r => r.json())
         .then(facts => render(facts));
     </script>
   </body>
   </html>
   ```

**Benefits**:
- Visibility into memory system
- Debugging tool
- User trust (transparency)

**Trade-offs**:
- Significant development effort
- Need to bundle web assets
- Another dependency (web server)
- Maintenance burden

**Verdict**: Skip for MVP. Consider if users request it.

---

## 4. Dual-Integration Strategy

### What claude-mem Does

**Plugin + MCP Server Hybrid**:

1. **Claude Code Plugin** (primary):
   - Hooks for lifecycle events
   - Worker service for AI processing
   - Installed via marketplace

2. **MCP Server** (secondary):
   - Thin wrapper delegating to worker HTTP API
   - Enables Claude Desktop integration
   - Same backend, different frontend

**File**: `src/servers/mcp-server.ts` (thin wrapper)

```typescript
// MCP server delegates to worker HTTP API
const mcpServer = new McpServer({
  name: "claude-mem",
  version: packageJson.version
});

mcpServer.setRequestHandler(ListToolsRequestSchema, async () => {
  // Fetch tools from worker
  const tools = await fetch('http://localhost:37777/api/mcp/tools');
  return tools.json();
});

mcpServer.setRequestHandler(CallToolRequestSchema, async (request) => {
  // Forward to worker
  const result = await fetch('http://localhost:37777/api/mcp/call', {
    method: 'POST',
    body: JSON.stringify(request.params)
  });
  return result.json();
});
```

**Benefit**: One backend, multiple frontends.

### What We Should Do

**Priority**: LOW

**Current State**: We only have MCP server (no plugin hooks yet).

**Implementation** (if we add Claude Code hooks):

1. **Keep MCP server as primary**:
   ```ruby
   # lib/claude_memory/mcp/server.rb
   # Current implementation - keep as-is
   ```

2. **Add hook handlers**:
   ```ruby
   # lib/claude_memory/hook/handler.rb
   # Delegate to same store manager
   def ingest_hook
     store_manager = Store::StoreManager.new
     ingester = Ingest::Ingester.new(store_manager)
     ingester.ingest(read_stdin[:transcript_delta])
   end
   ```

3. **Shared backend**:
   ```
   MCP Server (stdio) ──┐
                         ├──> Store::StoreManager ──> SQLite
   Hook Handler (stdin) ─┘
   ```

**Benefits**:
- Works with both Claude Code and Claude Desktop
- No duplicate logic
- Clean separation of transport vs business logic

**Trade-offs**:
- More integration points to maintain
- Hook contract is Claude Code-specific

**Verdict**: Consider if we add Claude Code hooks (not urgent).

---

## 5. Configuration-Driven Context Injection

### What claude-mem Does

**Context Config File**: `~/.claude-mem/settings.json`

```json
{
  "context": {
    "mode": "reader",  // reader | chat | inference
    "observations": {
      "enabled": true,
      "limit": 10,
      "types": ["decision", "gotcha", "trade-off"]
    },
    "summaries": {
      "enabled": true,
      "fields": ["request", "learned", "completed"]
    },
    "timeline": {
      "depth": 5
    }
  }
}
```

**File**: `src/services/context/ContextConfigLoader.ts`

**Benefit**: Users can fine-tune what gets injected.

### What We Should Do

**Priority**: LOW

**Implementation**:

1. **Add config file**:
   ```ruby
   # ~/.claude/memory_config.yml
   publish:
     mode: shared  # shared | local | home
     facts:
       limit: 50
       scopes: [global, project]
       predicates: [uses_*, depends_on, has_constraint]
     entities:
       limit: 20
     conflicts:
       show: true
   ```

2. **Load in publisher**:
   ```ruby
   # lib/claude_memory/publish.rb
   class Publisher
     def initialize
       @config = load_config
     end

     def load_config
       path = File.expand_path("~/.claude/memory_config.yml")
       YAML.load_file(path) if File.exist?(path)
     rescue
       default_config
     end
   end
   ```

3. **Apply during publish**:
   ```ruby
   def build_snapshot
     config = @config[:publish]

     facts = store.facts(
       limit: config[:facts][:limit],
       scopes: config[:facts][:scopes]
     )

     format_snapshot(facts, config)
   end
   ```

**Benefits**:
- User control over published content
- Environment-specific configs
- Reduces noise in generated files

**Trade-offs**:
- Another config file to document
- May confuse users
- Publish should be opinionated by default

**Verdict**: Skip for MVP. Default config is sufficient.

---

## Features We're Already Doing Better

### 1. Dual-Database Architecture (Global + Project)

**Our Advantage**: `Store::StoreManager` with global + project scopes.

Claude-mem has a single database with project filtering. Our approach is cleaner:

```ruby
# We separate global vs project knowledge
@global_store = Store::SqliteStore.new(global_db_path)
@project_store = Store::SqliteStore.new(project_db_path)

# Claude-mem filters post-query
SELECT * FROM observations WHERE project = ?
```

**Keep this.** It's a better design.

### 2. Fact-Based Knowledge Graph

**Our Advantage**: Subject-predicate-object triples with provenance.

Claude-mem stores blob observations. We store structured facts:

```ruby
# Ours (structured)
{ subject: "project", predicate: "uses_database", object: "PostgreSQL" }

# Theirs (blob)
{ title: "Uses PostgreSQL", narrative: "The project uses..." }
```

**Keep this.** Enables richer queries and inference.

### 3. Truth Maintenance System

**Our Advantage**: `Resolve::Resolver` with supersession and conflicts.

Claude-mem doesn't resolve contradictions. We do:

```ruby
# We detect when facts supersede each other
old: { subject: "api", predicate: "uses_auth", object: "JWT" }
new: { subject: "api", predicate: "uses_auth", object: "OAuth2" }
# → Creates supersession link

# We detect conflicts
fact1: { subject: "api", predicate: "rate_limit", object: "100/min" }
fact2: { subject: "api", predicate: "rate_limit", object: "1000/min" }
# → Creates conflict record
```

**Keep this.** It's a core differentiator.

### 4. Predicate Policies

**Our Advantage**: `Resolve::PredicatePolicy` for single vs multi-value.

Claude-mem doesn't distinguish. We do:

```ruby
# Single-value (supersedes)
"uses_database" → only one database at a time

# Multi-value (accumulates)
"depends_on" → many dependencies
```

**Keep this.** Prevents false conflicts.

### 5. Ruby Ecosystem (Simpler)

**Our Advantage**: Fewer dependencies, easier install.

```ruby
# Ours
gem install claude_memory  # Done

# Theirs
npm install                 # Needs Node.js
npm install chromadb        # Needs Python + pip
npm install better-sqlite3  # Needs node-gyp + build tools
```

**Keep this.** Ruby's stdlib is excellent.

---

## Features to Avoid

### 1. Chroma Vector Database

**Their Approach**: Hybrid SQLite FTS5 + Chroma vector search.

**Our Take**: **Skip it.** Adds significant complexity:

- Python dependency
- ChromaDB server
- Embedding generation
- Sync overhead

**Alternative**: Stick with SQLite FTS5. Add embeddings only if users request semantic search.

### 2. Claude Agent SDK for Distillation

**Their Approach**: Use `@anthropic-ai/claude-agent-sdk` for observation compression.

**Our Take**: **Skip it.** We already have `Distill::Distiller` interface. SDK adds:

- Node.js dependency
- Subprocess management
- Complex event loop

**Alternative**: Direct API calls via `anthropic-rb` gem (if we implement distiller).

### 3. Worker Service Background Process

**Their Approach**: Long-running worker with HTTP API + MCP wrapper.

**Our Take**: **Skip it.** We use MCP server directly:

- No background process to manage
- No port conflicts
- No PID files
- Simpler deployment

**Alternative**: Keep stdio-based MCP server. Add HTTP transport only if needed.

### 4. Web Viewer UI

**Their Approach**: React-based web UI at `http://localhost:37777`.

**Our Take**: **Skip for MVP.** Significant effort for uncertain value:

- React + esbuild
- SSE implementation
- State management
- CSS/theming

**Alternative**: CLI output is sufficient. Add web UI if users request it.
**Alternative**: CLI output is sufficient. Add web UI if users request it.

---

## Remaining Improvements

The following sections (6-12 from the original analysis) have been implemented and moved to the "Implemented Improvements" section above:

- ✅ Section 6: Local Vector Embeddings for Semantic Search
- ✅ Section 7: Multi-Concept AND Search  
- ✅ Section 8: Tool Usage Tracking
- ✅ Section 9: Enhanced Session Metadata
- ✅ Section 10: Incremental Sync (mtime-based)
- ✅ Section 11: Enhanced Statistics and Reporting
- ✅ Section 12: WAL Mode for Better Concurrency

**For remaining unimplemented improvements, see:** [remaining_improvements.md](./remaining_improvements.md)

Key remaining items:
- Background processing for hooks (--async flag)
- ROI metrics and token economics tracking
- Structured logging
- Embed command for backfilling embeddings

---

## QMD-Inspired Improvements (2026-01-26)

Analysis of **QMD (Quick Markdown Search)** reveals several high-value optimizations for search quality and performance. QMD is an on-device markdown search engine with hybrid BM25 + vector + LLM reranking, achieving 50%+ Hit@3 improvement over BM25-only search.

**See detailed analysis**: [docs/influence/qmd.md](./influence/qmd.md)

### High Priority ⭐

#### 1. **Native Vector Storage (sqlite-vec)** ⭐ CRITICAL

- **Value**: 10-100x faster KNN queries, enables larger fact databases
- **QMD Proof**: Handles 10,000+ documents with sub-second vector queries
- **Current Issue**: JSON embedding storage requires loading all facts, O(n) Ruby similarity calculation
- **Solution**: sqlite-vec extension with native C KNN queries
- **Implementation**:
  - Schema migration v7: Create `facts_vec` virtual table using `vec0`
  - Two-step query pattern (avoid JOINs - they hang with vec tables!)
  - Update `Embeddings::Similarity` class
  - Backfill existing embeddings
- **Trade-off**: Adds native dependency (acceptable, well-maintained, cross-platform)
- **Recommendation**: **ADOPT IMMEDIATELY** - This is foundational

#### 2. **Reciprocal Rank Fusion (RRF) Algorithm** ⭐ HIGH VALUE

- **Value**: 50% improvement in Hit@3 for medium-difficulty queries (QMD evaluation)
- **QMD Proof**: Evaluation suite shows consistent improvements across all query types
- **Current Issue**: Naive deduplication doesn't properly fuse ranking signals
- **Solution**: Mathematical fusion of FTS + vector ranked lists with position-aware scoring
- **Formula**: `score = Σ(weight / (k + rank + 1))` with top-rank bonus
- **Implementation**:
  - Create `Recall::RRFusion` class
  - Update `Recall#query_semantic_dual` to use RRF
  - Apply weights: original query ×2, expanded queries ×1
  - Add top-rank bonus: +0.05 for #1, +0.02 for #2-3
- **Trade-off**: Slightly more complex than naive merging (acceptable, well-tested)
- **Recommendation**: **ADOPT IMMEDIATELY** - Pure algorithmic improvement

#### 3. **Docid Short Hash System** ⭐ MEDIUM VALUE

- **Value**: Better UX, cross-database fact references
- **QMD Proof**: Used in all output, enables `qmd get #abc123`
- **Current Issue**: Integer IDs are database-specific, not user-friendly
- **Solution**: 8-character hash IDs for facts (e.g., `#abc123de`)
- **Implementation**:
  - Schema migration v8: Add `docid` column (indexed, unique)
  - Backfill existing facts with SHA256-based docids
  - Update CLI commands (`explain`, `recall`) to accept docids
  - Update MCP tools to accept docids
  - Update output formatting to show docids
- **Trade-off**: Hash collisions possible (8 chars = 1 in 4.3 billion, very rare)
- **Recommendation**: **ADOPT IN PHASE 2** - Clear UX improvement

#### 4. **Smart Expansion Detection** ⭐ MEDIUM VALUE

- **Value**: Skip unnecessary vector search when FTS finds exact match
- **QMD Proof**: Saves 2-3 seconds on 60% of queries (exact keyword matches)
- **Current Issue**: Always runs both FTS and vector search, even for exact matches
- **Solution**: Heuristic detection of strong FTS signal
- **Thresholds**: `top_score >= 0.85` AND `gap >= 0.15`
- **Implementation**:
  - Create `Recall::ExpansionDetector` class
  - Update `Recall#query_semantic_dual` to check before vector search
  - Add optional metrics tracking (skip rate, latency saved)
- **Trade-off**: May miss semantic results for exact matches (acceptable)
- **Recommendation**: **ADOPT IN PHASE 3** - Clear performance win

### Medium Priority

#### 5. **Document Chunking for Long Transcripts**

- **Value**: Better embeddings for long content (>3000 chars)
- **QMD Approach**: 800 tokens, 15% overlap, semantic boundary detection
- **Break Priority**: paragraph > sentence > line > word
- **Implementation**: Modify ingestion to chunk long content_items before embedding
- **Consideration**: Only if users report issues with long transcripts
- **Recommendation**: **DEFER** - Not urgent, TF-IDF handles shorter content well

#### 6. **LLM Response Caching**

- **Value**: Reduce API costs for repeated distillation
- **QMD Proof**: Hash-based caching with 80% hit rate
- **Implementation**:
  - Add `llm_cache` table (hash, result, created_at)
  - Cache key: `SHA256(operation + model + input)`
  - Probabilistic cleanup: 1% chance per operation, keep latest 1000
- **Consideration**: Most valuable when distiller is fully implemented
- **Recommendation**: **ADOPT WHEN DISTILLER ACTIVE** - Cost savings

#### 7. **Enhanced Snippet Extraction**

- **Value**: Better search result previews with query term highlighting
- **QMD Approach**: Find line with most query term matches, extract 1 line before + 2 after
- **Implementation**: Add to `Recall` output formatting
- **Consideration**: Improves UX but not critical
- **Recommendation**: **CONSIDER** - Nice-to-have

### Low Priority / Not Recommended

#### 8. **Neural Embeddings (EmbeddingGemma)** (DEFER)

- **QMD Model**: 300M params, 300MB download, 384 dimensions
- **Value**: Better semantic search quality (+40% Hit@3 over TF-IDF)
- **Cost**: 300MB download, 300MB VRAM, 2s cold start, complex dependency
- **Decision**: **DEFER** - TF-IDF sufficient for now, revisit if users report poor quality

#### 9. **Cross-Encoder Reranking** (REJECT)

- **QMD Model**: Qwen3-Reranker-0.6B (640MB)
- **Value**: Better ranking precision via LLM scoring
- **Cost**: 640MB model, 400ms latency per query, complex dependency
- **Decision**: **REJECT** - Over-engineering for fact retrieval

#### 10. **Query Expansion (LLM)** (REJECT)

- **QMD Model**: Qwen3-1.7B (2.2GB)
- **Value**: Generate alternative query phrasings for better recall
- **Cost**: 2.2GB model, 800ms latency per query
- **Decision**: **REJECT** - No LLM in recall path, too heavy

#### 11. **YAML Collection System** (REJECT)

- **QMD Use**: Multi-directory indexing with per-path contexts
- **Our Use**: Dual-database (global + project) already provides clean separation
- **Decision**: **REJECT** - Our approach is cleaner for our use case

#### 12. **Content-Addressable Storage** (REJECT)

- **QMD Use**: Deduplicates documents by SHA256 hash
- **Our Use**: Facts deduplicated by signature, not content hash
- **Decision**: **REJECT** - Different data model

#### 13. **Virtual Path System** (REJECT)

- **QMD Use**: `qmd://collection/path` unified namespace
- **Our Use**: Dual-database provides clear namespace
- **Decision**: **REJECT** - Unnecessary complexity

---

## Implementation Priorities

### High Priority (QMD-Inspired)

1. **Native Vector Storage (sqlite-vec)** ⭐ - 10-100x faster KNN, foundational improvement
2. **Reciprocal Rank Fusion (RRF)** ⭐ - 50% better search quality, pure algorithm
3. **Docid Short Hashes** - Better UX for fact references
4. **Smart Expansion Detection** - Skip unnecessary vector search when FTS is confident

### Medium Priority

5. **Background Processing** - Non-blocking hooks for better UX (from episodic-memory)
6. **ROI Metrics** - Track token economics for distillation (from claude-mem)
7. **LLM Response Caching** - Reduce API costs (from QMD)
8. **Document Chunking** - Better embeddings for long transcripts (from QMD, if needed)

### Low Priority

9. **Structured Logging** - Better debugging with JSON logs
10. **Embed Command** - Backfill embeddings for existing facts
11. **Enhanced Snippet Extraction** - Query-aware snippet preview (from QMD)
12. **Health Monitoring** - Only if we add background worker
13. **Web Viewer UI** - Only if users request visualization
14. **Configuration-Driven Context** - Only if users request snapshot customization

---

## Migration Path

### Completed ✓

- [x] WAL mode for better concurrency
- [x] Enhanced statistics command
- [x] Session metadata tracking
- [x] Tool usage tracking
- [x] Semantic search with TF-IDF embeddings
- [x] Multi-concept AND search
- [x] Incremental sync with mtime tracking
- [x] Context-aware queries

### Phase 1: Vector Storage Upgrade (from QMD) - IMMEDIATE

- [ ] Add sqlite-vec extension support (gem or FFI)
- [ ] Create schema migration v7: `facts_vec` virtual table using `vec0`
- [ ] Backfill existing embeddings from JSON to native vectors
- [ ] Update `Embeddings::Similarity` class for native KNN (two-step query pattern)
- [ ] Test migration on existing databases
- [ ] Document extension installation in README
- [ ] Benchmark: Measure KNN query improvement (expect 10-100x)

### Phase 2: RRF Fusion (from QMD) - IMMEDIATE

- [ ] Implement `Recall::RRFusion` class with k=60 parameter
- [ ] Update `Recall#query_semantic_dual` to use RRF fusion
- [ ] Apply weights: original query ×2, expanded queries ×1
- [ ] Add top-rank bonus: +0.05 for #1, +0.02 for #2-3
- [ ] Test with synthetic ranked lists (unit tests)
- [ ] Validate improvements with real queries

### Phase 3: UX Improvements (from QMD) - NEAR-TERM

- [ ] Schema migration v8: Add `docid` column (8-char hash, indexed, unique)
- [ ] Backfill existing facts with SHA256-based docids
- [ ] Update CLI commands to accept/display docids (`ExplainCommand`, `RecallCommand`)
- [ ] Update MCP tools for docid support (`memory.explain`, `memory.recall`)
- [ ] Test cross-database docid lookups

### Phase 4: Performance Optimizations (from QMD) - NEAR-TERM

- [ ] Implement `Recall::ExpansionDetector` class
- [ ] Update `Recall#query_semantic_dual` to check before vector search
- [ ] Add metrics tracking (skip rate, avg latency saved)
- [ ] Tune thresholds based on usage patterns

### Remaining Tasks

- [ ] Background processing (--async flag for hooks)
- [ ] ROI metrics table for token tracking during distillation
- [ ] LLM response caching (from QMD, when distiller is active)
- [ ] Structured logging implementation
- [ ] Embed command for backfilling embeddings

### Future (If Requested)

- [ ] Document chunking for long transcripts (from QMD, if users report issues)
- [ ] Enhanced snippet extraction (from QMD, for better search result previews)
- [ ] Build web viewer (if users request visualization)
- [ ] Add HTTP-based health checks (if background worker is added)
- [ ] Configuration-driven snapshot generation (if users request customization)

---

## Key Takeaways

### Successfully Adopted from claude-mem ✓

1. Progressive disclosure (token-efficient retrieval)
2. Privacy controls (tag-based content exclusion)
3. Clean architecture (command pattern, slim CLI)
4. Semantic shortcuts (decisions, conventions, architecture)
5. Exit code strategy (hook error handling)

### Successfully Adopted from Episodic-Memory ✓

1. **WAL Mode** - Better concurrency with Write-Ahead Logging
2. **Tool Usage Tracking** - Dedicated table tracking which tools discovered facts
3. **Incremental Sync** - mtime-based change detection for fast re-ingestion
4. **Session Metadata** - Context capture (git branch, cwd, Claude version)
5. **Local Vector Embeddings** - TF-IDF semantic search alongside FTS5
6. **Multi-Concept AND Search** - Precise queries matching 2-5 concepts simultaneously
7. **Enhanced Statistics** - Comprehensive reporting on facts, entities, provenance
8. **Context-Aware Queries** - Filter by branch, directory, or tools used

### Our Unique Advantages

1. **Dual-database architecture** - Global + project scopes
2. **Fact-based knowledge graph** - Structured vs blob observations or conversation exchanges
3. **Truth maintenance** - Conflict resolution and supersession
4. **Predicate policies** - Single vs multi-value semantics
5. **Ruby ecosystem** - Simpler dependencies, easier install
6. **Lightweight embeddings** - No external dependencies (TF-IDF vs Transformers.js)

### Remaining Opportunities

- **Background Processing** - Non-blocking hooks for better UX (from episodic-memory)
- **ROI Metrics** - Track token economics for distillation (from claude-mem)
- **Structured Logging** - JSON-formatted logs for debugging
- **Embed Command** - Backfill embeddings for existing facts
- **Health Monitoring** - Only if we add background worker
- **Web Viewer UI** - Only if users request visualization
- **Configuration-Driven Context** - Only if users request snapshot customization

---

## Comparison Summary

**Episodic-memory** and **claude_memory** serve complementary but different needs:

**Episodic-memory** excels at:
- Semantic conversation search with local embeddings
- Preserving complete conversation context
- Multi-concept AND queries
- Fast incremental sync
- Tool usage tracking
- Rich session metadata

**ClaudeMemory** excels at:
- Structured fact extraction and storage
- Truth maintenance and conflict resolution
- Dual-scope architecture (global vs project)
- Knowledge graph with provenance
- Semantic shortcuts for common queries

**Best of both worlds (achieved)**:
- ✅ Added vector embeddings for semantic search (TF-IDF based)
- ✅ Kept fact-based knowledge graph for structured queries
- ✅ Adopted incremental sync and tool tracking from episodic-memory
- ✅ Maintained truth maintenance and conflict resolution
- ✅ Added session metadata for richer context
- ✅ Implemented multi-concept AND search
- ✅ Enhanced statistics and reporting

---

## References

- [episodic-memory GitHub](https://github.com/obra/episodic-memory) - Semantic conversation search
- [claude-mem GitHub](https://github.com/thedotmack/claude-mem) - Memory compression system
- [ClaudeMemory Updated Plan](updated_plan.md) - Original improvement plan

---

*This document has been updated to reflect completed implementations. Thirteen major improvements have been successfully integrated: 5 from claude-mem and 8 from episodic-memory. ClaudeMemory now combines the best of both systems while maintaining its unique advantages in fact-based knowledge representation and truth maintenance.*

*Last updated: 2026-01-23 - Major implementation milestone achieved*
