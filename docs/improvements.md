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

---

## 6. Local Vector Embeddings for Semantic Search

### What Episodic-Memory Does

**Local Embedding Generation**:
- Uses Transformers.js to run models in Node.js (offline-capable)
- Model: `Xenova/all-MiniLM-L6-v2` (384-dimensional vectors)
- Truncates text to 2000 chars (512 token limit for model)
- Normalizes vectors for cosine similarity

**File**: `src/embeddings.ts`

```typescript
export async function generateEmbedding(text: string): Promise<number[]> {
  const truncated = text.substring(0, 2000);
  const output = await embeddingPipeline!(truncated, {
    pooling: 'mean',
    normalize: true
  });
  return Array.from(output.data);
}
```

**Vector Storage with sqlite-vec**:
```sql
CREATE VIRTUAL TABLE vec_exchanges USING vec0(
  id TEXT PRIMARY KEY,
  embedding FLOAT[384]
);
```

**Hybrid Search**:
- Vector similarity: `WHERE vec.embedding MATCH ? AND k = ? ORDER BY vec.distance`
- Text search: `WHERE user_message LIKE ? OR assistant_message LIKE ?`
- Both modes: Merge and deduplicate results

### What We Should Do

**Priority**: HIGH

**Implementation**:

1. **Add embeddings column and virtual table**:
   ```ruby
   # lib/claude_memory/store/sqlite_store.rb
   db.create_table :facts do
     # ... existing columns ...
     String :embedding_vector  # JSON array of floats
   end

   # Create virtual table for vector search
   db.execute <<-SQL
     CREATE VIRTUAL TABLE IF NOT EXISTS vec_facts USING vec0(
       fact_id INTEGER PRIMARY KEY,
       embedding FLOAT[384]
     );
   SQL
   ```

2. **Generate embeddings using ONNX Runtime**:
   ```ruby
   # lib/claude_memory/embeddings/generator.rb
   require 'onnxruntime'

   class EmbeddingGenerator
     MODEL_PATH = File.expand_path("~/.claude/models/all-MiniLM-L6-v2.onnx")

     def initialize
       @model = OnnxRuntime::Model.new(MODEL_PATH)
       @tokenizer = load_tokenizer
     end

     def generate(text)
       # Truncate to 512 tokens
       tokens = @tokenizer.encode(text).ids.take(512)

       # Run inference
       output = @model.predict({
         input_ids: [tokens],
         attention_mask: [Array.new(tokens.size, 1)]
       })

       # Mean pooling and normalize
       normalize(mean_pool(output['last_hidden_state']))
     end

     private

     def normalize(vector)
       magnitude = Math.sqrt(vector.sum { |v| v**2 })
       vector.map { |v| v / magnitude }
     end
   end
   ```

3. **Hybrid search in Recall**:
   ```ruby
   # lib/claude_memory/recall.rb
   def search(query, mode: :both, limit: 10)
     results = []

     if mode == :vector || mode == :both
       # Vector similarity search
       embedding = EmbeddingGenerator.new.generate(query)
       vector_results = db[:vec_facts]
         .select(:fact_id, :distance)
         .where(Sequel.lit("embedding MATCH ? AND k = ?",
                           embedding.pack('f*'), limit))
         .order(:distance)
         .all

       results.concat(vector_results)
     end

     if mode == :text || mode == :both
       # FTS5 search
       text_results = search_fts5(query, limit)
       results.concat(text_results)
     end

     # Deduplicate and rank
     results.uniq { |r| r[:fact_id] }
   end
   ```

4. **MCP tool for semantic search**:
   ```ruby
   # lib/claude_memory/mcp/server.rb
   TOOLS << {
     name: "memory.search_semantic",
     description: "Search facts using semantic similarity (finds conceptually related facts)",
     inputSchema: {
       type: "object",
       properties: {
         query: { type: "string" },
         mode: { type: "string", enum: ["vector", "text", "both"], default: "both" },
         limit: { type: "integer", default: 10 }
       },
       required: ["query"]
     }
   }
   ```

**Benefits**:
- Find conceptually similar facts even with different terminology
- Better recall for complex queries
- Works offline (no API calls for embeddings)
- Complements FTS5 for best overall search quality

**Trade-offs**:
- Increased storage: ~1.5KB per fact (384 floats)
- Embedding generation time during ingestion
- Need to download/bundle ONNX model (~100MB)
- Ruby ONNX runtime less mature than Python/Node.js

**Alternative**: Shell out to Python script for embeddings:
```ruby
def generate_embedding(text)
  result = `python3 #{__dir__}/embed.py #{Shellwords.escape(text)}`
  JSON.parse(result)
end
```

---

## 7. Multi-Concept AND Search

### What Episodic-Memory Does

**Array-Based Query**:
```typescript
// Search for conversations matching ALL concepts
const results = await searchMultipleConcepts(
  ["React Router", "authentication", "JWT"],
  { limit: 10 }
);
```

**Implementation**:
1. Search each concept independently with 5x limit
2. Build map of conversation → array of results (one per concept)
3. Filter to conversations matching ALL concepts
4. Rank by average similarity across concepts

**File**: `src/search.ts` (lines 227-287)

**MCP Tool**:
```typescript
{
  query: ["React Router", "authentication", "JWT"],  // Array = multi-concept
  limit: 10
}
```

### What We Should Do

**Priority**: MEDIUM

**Implementation**:

1. **Add multi-concept search to Recall**:
   ```ruby
   # lib/claude_memory/recall.rb
   def search_concepts(concepts, limit: 10, scope: :all)
     # Search each concept independently
     concept_results = concepts.map do |concept|
       search(concept, limit: limit * 5, scope: scope)
     end

     # Build map: fact_id → [results]
     fact_map = Hash.new { |h, k| h[k] = [] }
     concept_results.each_with_index do |results, concept_idx|
       results.each do |result|
         fact_map[result.id] << { result: result, concept_idx: concept_idx }
       end
     end

     # Filter to facts matching ALL concepts
     multi_concept_results = fact_map.select do |fact_id, results|
       results.map { |r| r[:concept_idx] }.uniq.size == concepts.size
     end

     # Rank by average similarity
     multi_concept_results.map do |fact_id, results|
       similarities = results.map { |r| r[:result].similarity }
       avg_similarity = similarities.sum / similarities.size

       {
         fact: results.first[:result].fact,
         concept_similarities: similarities,
         average_similarity: avg_similarity
       }
     end.sort_by { |r| -r[:average_similarity] }.take(limit)
   end
   ```

2. **MCP tool**:
   ```ruby
   TOOLS << {
     name: "memory.search_concepts",
     description: "Search for facts matching ALL of the provided concepts (AND query)",
     inputSchema: {
       type: "object",
       properties: {
         concepts: {
           type: "array",
           items: { type: "string" },
           minItems: 2,
           maxItems: 5
         },
         limit: { type: "integer", default: 10 }
       },
       required: ["concepts"]
     }
   }
   ```

3. **Format output**:
   ```ruby
   def format_multi_concept_results(results, concepts)
     return "No facts found matching all concepts" if results.empty?

     output = "Found #{results.size} facts matching all concepts [#{concepts.join(' + ')}]:\n\n"

     results.each_with_index do |result, idx|
       output << "#{idx + 1}. #{result[:fact].subject} #{result[:fact].predicate} #{result[:fact].object}\n"

       scores = result[:concept_similarities].zip(concepts)
         .map { |sim, concept| "#{concept}: #{(sim * 100).round}%" }
         .join(", ")
       output << "   Concepts: #{scores}\n"
       output << "   Average match: #{(result[:average_similarity] * 100).round}%\n\n"
     end

     output
   end
   ```

**Benefits**:
- Precise queries requiring multiple concepts to match
- Better than single query with all concepts combined
- Reduces false positives from partial matches

**Trade-offs**:
- Multiple search passes (N searches for N concepts)
- More complex ranking logic
- May miss facts if one concept has weak match

---

## 8. Tool Usage Tracking

### What Episodic-Memory Does

**Dedicated tool_calls table**:
```sql
CREATE TABLE tool_calls (
  id TEXT PRIMARY KEY,
  exchange_id TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  tool_input TEXT,
  tool_result TEXT,
  is_error BOOLEAN DEFAULT 0,
  timestamp TEXT NOT NULL,
  FOREIGN KEY (exchange_id) REFERENCES exchanges(id)
);

CREATE INDEX idx_tool_name ON tool_calls(tool_name);
```

**Extraction from JSONL**:
- Parses tool_use blocks from assistant messages
- Extracts tool name and input
- Associates with exchange ID
- Includes tools in embedding for better search

**File**: `src/parser.ts` (lines 124-137)

**Search Results Show Tools**:
```
1. [project, 2025-10-15]
   "How do I fix the authentication bug?"
   Tools: Read(5), Edit(2), Bash(1)
   Lines 10-42 in conversation.jsonl
```

### What We Should Do

**Priority**: HIGH

**Implementation**:

1. **Add tool_calls table**:
   ```ruby
   # lib/claude_memory/store/sqlite_store.rb
   db.create_table :tool_calls do
     primary_key :id
     foreign_key :content_item_id, :content_items
     String :tool_name, null: false
     String :tool_input, text: true
     String :tool_result, text: true
     TrueClass :is_error, default: false
     DateTime :timestamp, null: false
   end

   db.add_index :tool_calls, :tool_name
   db.add_index :tool_calls, :content_item_id
   ```

2. **Extract from transcript during ingestion**:
   ```ruby
   # lib/claude_memory/ingest/ingester.rb
   def extract_tool_calls(transcript_chunk)
     tool_calls = []

     # Parse JSONL
     transcript_chunk.each_line do |line|
       message = JSON.parse(line)
       next unless message['type'] == 'assistant'

       content = message['message']['content']
       next unless content.is_a?(Array)

       content.each do |block|
         if block['type'] == 'tool_use'
           tool_calls << {
             tool_name: block['name'],
             tool_input: block['input'].to_json,
             timestamp: message['timestamp']
           }
         end
       end
     end

     tool_calls
   end
   ```

3. **Link to provenance**:
   ```ruby
   # Associate tools with content items
   content_item = store.insert_content_item(transcript_chunk)
   tool_calls = extract_tool_calls(transcript_chunk)

   tool_calls.each do |tc|
     store.insert_tool_call(
       content_item_id: content_item.id,
       **tc
     )
   end
   ```

4. **Query by tool usage**:
   ```ruby
   # Find facts discovered using specific tools
   def facts_by_tool(tool_name)
     db[:facts]
       .join(:provenance, fact_id: :id)
       .join(:tool_calls, content_item_id: :content_item_id)
       .where(Sequel[:tool_calls][:tool_name] => tool_name)
       .select_all(:facts)
       .distinct
       .all
   end
   ```

5. **MCP tool**:
   ```ruby
   TOOLS << {
     name: "memory.facts_by_tool",
     description: "Find facts discovered using a specific tool (Read, Edit, Bash, etc.)",
     inputSchema: {
       type: "object",
       properties: {
         tool_name: { type: "string" },
         limit: { type: "integer", default: 20 }
       },
       required: ["tool_name"]
     }
   }
   ```

**Benefits**:
- Know which tools were used during fact discovery
- Filter facts by discovery method
- Debug ingestion issues
- Understand patterns (e.g., most facts from Read tool)

**Trade-offs**:
- Additional table and foreign keys
- Parsing complexity for tool extraction
- Storage overhead

---

## 9. Enhanced Session Metadata

### What Episodic-Memory Does

**Rich Metadata Capture**:
```typescript
interface ConversationExchange {
  // ... basic fields ...

  // Session context
  sessionId?: string;
  cwd?: string;
  gitBranch?: string;
  claudeVersion?: string;

  // Thinking metadata
  thinkingLevel?: string;
  thinkingDisabled?: boolean;
  thinkingTriggers?: string; // JSON array
}
```

**Schema**:
```sql
ALTER TABLE exchanges ADD COLUMN session_id TEXT;
ALTER TABLE exchanges ADD COLUMN cwd TEXT;
ALTER TABLE exchanges ADD COLUMN git_branch TEXT;
ALTER TABLE exchanges ADD COLUMN claude_version TEXT;
ALTER TABLE exchanges ADD COLUMN thinking_level TEXT;
ALTER TABLE exchanges ADD COLUMN thinking_disabled BOOLEAN;
ALTER TABLE exchanges ADD COLUMN thinking_triggers TEXT;

CREATE INDEX idx_session_id ON exchanges(session_id);
CREATE INDEX idx_git_branch ON exchanges(git_branch);
```

**Use Cases**:
- Filter conversations by git branch
- Track facts learned in specific working directories
- Understand thinking mode usage patterns

### What We Should Do

**Priority**: MEDIUM

**Implementation**:

1. **Extend content_items table**:
   ```ruby
   # Migration
   db.alter_table :content_items do
     add_column :cwd, String
     add_column :git_branch, String
     add_column :claude_version, String
     add_column :thinking_level, String
     add_column :thinking_disabled, TrueClass
   end

   db.add_index :content_items, :git_branch
   ```

2. **Extract from transcript**:
   ```ruby
   # lib/claude_memory/ingest/ingester.rb
   def extract_metadata(transcript_chunk)
     # Parse first message for metadata
     first_line = transcript_chunk.lines.first
     message = JSON.parse(first_line)

     {
       session_id: message['sessionId'],
       cwd: message['cwd'],
       git_branch: message['gitBranch'],
       claude_version: message['version'],
       thinking_level: message.dig('thinkingMetadata', 'level'),
       thinking_disabled: message.dig('thinkingMetadata', 'disabled')
     }
   end
   ```

3. **Query by metadata**:
   ```ruby
   # Find facts learned on specific branch
   def facts_by_branch(branch_name)
     db[:facts]
       .join(:provenance, fact_id: :id)
       .join(:content_items, id: :content_item_id)
       .where(Sequel[:content_items][:git_branch] => branch_name)
       .select_all(:facts)
       .distinct
       .all
   end
   ```

4. **MCP tool**:
   ```ruby
   TOOLS << {
     name: "memory.facts_by_context",
     description: "Find facts learned in specific context (branch, directory, etc.)",
     inputSchema: {
       type: "object",
       properties: {
         git_branch: { type: "string" },
         cwd: { type: "string" },
         limit: { type: "integer", default: 20 }
       }
     }
   }
   ```

**Benefits**:
- Context-aware fact retrieval
- Understand where knowledge was acquired
- Filter by development branch or working directory

**Trade-offs**:
- Additional columns and indexes
- Metadata may not always be available in transcripts

---

## 10. Incremental Sync with Background Processing

### What Episodic-Memory Does

**Incremental Sync**:
```typescript
function copyIfNewer(src: string, dest: string): boolean {
  if (fs.existsSync(dest)) {
    const srcStat = fs.statSync(src);
    const destStat = fs.statSync(dest);
    if (destStat.mtimeMs >= srcStat.mtimeMs) {
      return false; // Dest is current, skip
    }
  }

  // Atomic copy: temp file + rename
  const tempDest = dest + '.tmp.' + process.pid;
  fs.copyFileSync(src, tempDest);
  fs.renameSync(tempDest, dest);
  return true;
}
```

**Background Sync**:
```bash
# SessionStart hook
episodic-memory sync --background
```

Runs in background, user continues working immediately.

**File**: `src/sync.ts`

### What We Should Do

**Priority**: HIGH

**Implementation**:

1. **Track modification times**:
   ```ruby
   # Migration
   db.alter_table :content_items do
     add_column :source_mtime, DateTime
   end
   ```

2. **Skip unchanged files**:
   ```ruby
   # lib/claude_memory/ingest/ingester.rb
   def should_ingest?(file_path)
     mtime = File.mtime(file_path)

     existing = store.content_item_by_path(file_path)
     return true unless existing

     existing.source_mtime.nil? || mtime > existing.source_mtime
   end

   def ingest(file_path)
     return unless should_ingest?(file_path)

     content = File.read(file_path)
     store.insert_content_item(
       path: file_path,
       content: content,
       source_mtime: File.mtime(file_path)
     )

     # Process content...
   end
   ```

3. **Background processing**:
   ```ruby
   # lib/claude_memory/commands/hook/ingest_command.rb
   def call(args)
     opts = parse_options(args, { async: false })

     if opts[:async]
       # Fork and detach
       pid = fork do
         Process.setsid  # Detach from terminal
         ingest_stdin
       end
       Process.detach(pid)

       stdout.puts "Ingestion started in background (PID: #{pid})"
       return 0
     end

     ingest_stdin
     0
   end
   ```

4. **Hook configuration**:
   ```json
   {
     "hooks": {
       "SessionStart": [{
         "matcher": "startup|resume",
         "hooks": [{
           "type": "command",
           "command": "claude-memory hook ingest --async",
           "async": true
         }]
       }]
     }
   }
   ```

**Benefits**:
- Fast subsequent ingestions (seconds vs minutes)
- Non-blocking hooks (user continues working immediately)
- Atomic operations (safe concurrent execution)

**Trade-offs**:
- Background process management complexity
- Need to track modification times
- Potential race conditions if multiple sessions start simultaneously

---

## 11. Enhanced Statistics and Reporting

### What Episodic-Memory Does

**Comprehensive Stats**:
```typescript
interface IndexStats {
  totalConversations: number;
  conversationsWithSummaries: number;
  conversationsWithoutSummaries: number;
  totalExchanges: number;
  dateRange?: { earliest: string; latest: string };
  projectCount: number;
  topProjects?: Array<{ project: string; count: number }>;
  databaseSize?: string;
}
```

**Output Format**:
```
Episodic Memory Index Statistics
==================================================

Total Conversations: 145
Total Exchanges: 1,247

With Summaries: 120
Without Summaries: 25
  (17.2% missing summaries)

Date Range:
  Earliest: 10/1/2025
  Latest: 1/23/2026

Unique Projects: 8

Top Projects by Conversation Count:
    42 - claude_memory
    38 - my-app
    22 - docs-site
    ...
```

**File**: `src/stats.ts`

### What We Should Do

**Priority**: MEDIUM

**Implementation**:

1. **Enhanced stats command**:
   ```ruby
   # lib/claude_memory/commands/stats_command.rb
   class StatsCommand < BaseCommand
     def call(args)
       stats = gather_stats

       stdout.puts format_stats(stats)
       0
     end

     private

     def gather_stats
       {
         global: database_stats(Configuration.global_db_path),
         project: database_stats(Configuration.project_db_path),
         combined: combined_stats
       }
     end

     def database_stats(db_path)
       return nil unless File.exist?(db_path)

       db = Sequel.sqlite(db_path)

       {
         facts: {
           total: db[:facts].count,
           active: db[:facts].where(superseded_by_id: nil).count,
           superseded: db[:facts].exclude(superseded_by_id: nil).count,
           by_predicate: db[:facts]
             .group(:predicate)
             .select{ [predicate, count.function.*] }
             .order(Sequel.desc(2))
             .limit(10)
             .all
         },
         entities: {
           total: db[:entities].count,
           by_type: db[:entities]
             .group(:entity_type)
             .select{ [entity_type, count.function.*] }
             .all
         },
         content_items: {
           total: db[:content_items].count,
           date_range: db[:content_items]
             .select{ [min(created_at).as(earliest), max(created_at).as(latest)] }
             .first
         },
         conflicts: {
           open: db[:conflicts].where(status: 'open').count,
           resolved: db[:conflicts].where(status: 'resolved').count
         },
         provenance: {
           facts_with_provenance: db[:provenance].select(:fact_id).distinct.count,
           total_receipts: db[:provenance].count
         }
       }
     end

     def format_stats(stats)
       output = "ClaudeMemory Statistics\n"
       output << "=" * 50 << "\n\n"

       if stats[:global]
         output << "GLOBAL DATABASE\n"
         output << format_db_stats(stats[:global])
         output << "\n"
       end

       if stats[:project]
         output << "PROJECT DATABASE\n"
         output << format_db_stats(stats[:project])
         output << "\n"
       end

       output
     end
   end
   ```

2. **MCP tool for stats**:
   ```ruby
   TOOLS << {
     name: "memory.stats",
     description: "Get detailed statistics about the memory system",
     inputSchema: {
       type: "object",
       properties: {
         scope: { type: "string", enum: ["global", "project", "all"], default: "all" }
       }
     }
   }
   ```

**Benefits**:
- Visibility into memory system health
- Identify coverage gaps (missing provenance, etc.)
- Understand predicate usage patterns
- Debug issues with concrete numbers

**Trade-offs**:
- Complex aggregation queries
- Formatting complexity

---

## 12. WAL Mode for Better Concurrency

### What Episodic-Memory Does

**Enable WAL Mode**:
```typescript
// Enable WAL mode for better concurrency
db.pragma('journal_mode = WAL');
```

**File**: `src/db.ts` (line 54)

**Benefits**:
- Readers don't block writers
- Writers don't block readers
- Better performance for concurrent access
- Safer for background sync operations

### What We Should Do

**Priority**: LOW (easy win)

**Implementation**:

```ruby
# lib/claude_memory/store/sqlite_store.rb
def initialize(db_path)
  @db = Sequel.sqlite(db_path)

  # Enable WAL mode for better concurrency
  @db.pragma('journal_mode = WAL')

  # Other pragmas
  @db.pragma('synchronous = NORMAL')
  @db.pragma('foreign_keys = ON')

  create_schema unless schema_exists?
end
```

**Benefits**:
- Better concurrency (multiple readers, non-blocking writes)
- Improved performance
- Safer for concurrent hook execution
- One-line change

**Trade-offs**:
- Creates -wal and -shm files alongside database
- Slightly more disk space usage
- Not compatible with network filesystems (NFS)

---

## Implementation Priorities

### High Priority (Next Sprint)

1. **WAL Mode** (1 hour) - One-line change, immediate concurrency benefit
2. **Tool Usage Tracking** (1-2 days) - High value for debugging and filtering
3. **Incremental Sync** (2-3 days) - Major performance improvement for hooks
4. **Session Metadata** (1 day) - Useful context for facts

### Medium Priority (Next Quarter)

5. **Local Vector Embeddings** (1-2 weeks) - Enables semantic search (requires ONNX setup)
6. **Multi-Concept AND Search** (2-3 days) - Better query precision
7. **Enhanced Statistics** (2-3 days) - Better system visibility
8. **Background Processing** (3-5 days) - Non-blocking hooks
9. **ROI Metrics** (from claude-mem) - Track token economics for distillation

### Low Priority (Future)

10. **Health Monitoring** - Only if we add background worker
11. **Web Viewer UI** - Only if users request visualization
12. **Dual Integration** - Only if we add Claude Code hooks integration
13. **Config-Driven Context** - Only if users request snapshot customization

---

## Migration Path

### Next Sprint (Remaining Tasks)

- [ ] Add metrics table for token tracking during distillation
- [ ] Track token costs in ingestion pipeline
- [ ] Display ROI metrics in `claude-memory status` command

### Future (If Requested)

- [ ] Add vector embeddings (if users request semantic search)
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

### Our Unique Advantages

1. **Dual-database architecture** - Global + project scopes
2. **Fact-based knowledge graph** - Structured vs blob observations or conversation exchanges
3. **Truth maintenance** - Conflict resolution and supersession
4. **Predicate policies** - Single vs multi-value semantics
5. **Ruby ecosystem** - Simpler dependencies, easier install

### High-Value Opportunities from Episodic-Memory

1. **WAL Mode** - One-line change for better concurrency
2. **Tool Usage Tracking** - Know which tools were used during fact discovery
3. **Incremental Sync** - Fast subsequent ingestions (seconds vs minutes)
4. **Session Metadata** - Context about where/when facts were learned
5. **Local Vector Embeddings** - Semantic search alongside FTS5
6. **Multi-Concept AND Search** - Precise queries requiring multiple concepts
7. **Enhanced Statistics** - Better system visibility and health monitoring
8. **Background Processing** - Non-blocking hooks for better UX

### Remaining Opportunities from claude-mem

- **ROI Metrics** - Track token economics for distillation cost/benefit visibility
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

**Best of both worlds**:
- Add vector embeddings to ClaudeMemory for semantic search
- Keep fact-based knowledge graph for structured queries
- Adopt incremental sync and tool tracking from episodic-memory
- Maintain truth maintenance and conflict resolution
- Add session metadata for richer context

---

## References

- [episodic-memory GitHub](https://github.com/obra/episodic-memory) - Semantic conversation search
- [claude-mem GitHub](https://github.com/thedotmack/claude-mem) - Memory compression system
- [ClaudeMemory Updated Plan](updated_plan.md) - Original improvement plan

---

*This document has been updated to reflect completed implementations and new insights from episodic-memory. Five major improvements from claude-mem have been successfully integrated. The document now includes high-value patterns from episodic-memory that can enhance ClaudeMemory while maintaining its unique advantages.*
