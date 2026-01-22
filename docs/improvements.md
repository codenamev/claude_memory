# Improvements to Consider (Based on claude-mem Analysis)

*Generated: 2026-01-21*
*Source: Comparative analysis of [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem)*

This document identifies design patterns, features, and architectural decisions from claude-mem that could improve claude_memory. Each section includes rationale, implementation considerations, and priority.

---

## Executive Summary

Claude-mem (TypeScript/Node.js, v9.0.5) is a production-grade memory compression system with 6+ months of real-world usage. Key strengths:

- **Progressive Disclosure**: Token-efficient 3-layer retrieval workflow
- **ROI Metrics**: Tracks token costs and discovery efficiency
- **Slim Architecture**: Clean separation via service layer pattern
- **Dual Integration**: Plugin + MCP server for flexibility
- **Privacy-First**: User-controlled content exclusion via tags
- **Fail-Fast Philosophy**: Explicit error handling and exit codes

**Our Advantages**:
- Ruby ecosystem (simpler dependencies)
- Dual-database architecture (global + project scope)
- Fact-based knowledge graph (vs observation blobs)
- Truth maintenance system (conflict resolution)
- Predicate policies (single vs multi-value)

---

## 1. Progressive Disclosure Pattern

### What claude-mem Does

**3-Layer Workflow** enforced at the tool level:

```
Layer 1: search → Get compact index with IDs (~50-100 tokens/result)
Layer 2: timeline → Get chronological context around IDs
Layer 3: get_observations → Fetch full details (~500-1,000 tokens/result)
```

**Token savings**: ~10x reduction by filtering before fetching.

**MCP Tools**:
- `search` - Returns index format (titles, IDs, token counts)
- `timeline` - Returns context around specific observation
- `get_observations` - Returns full details only for filtered IDs
- `__IMPORTANT` - Workflow documentation (always visible)

**File**: `docs/public/progressive-disclosure.mdx` (673 lines of philosophy)

### What We Should Do

**Priority**: HIGH

**Implementation**:

1. **Add token count field to facts table**:
   ```ruby
   alter table :facts do
     add_column :token_count, Integer
   end
   ```

2. **Create index format in Recall**:
   ```ruby
   # lib/claude_memory/recall.rb
   def recall_index(query, scope: :project, limit: 20)
     facts = search_facts(query, scope:, limit:)
     facts.map do |fact|
       {
         id: fact[:id],
         subject: fact[:subject],
         predicate: fact[:predicate],
         object_preview: fact[:object_value][0..50],
         scope: fact[:scope],
         token_count: fact[:token_count] || estimate_tokens(fact)
       }
     end
   end
   ```

3. **Add MCP tool for fetching details**:
   ```ruby
   # lib/claude_memory/mcp/tools.rb
   TOOLS["memory.recall_index"] = {
     description: "Layer 1: Search for facts. Returns compact index with IDs.",
     input_schema: {
       type: "object",
       properties: {
         query: { type: "string" },
         scope: { type: "string", enum: ["global", "project", "both"] },
         limit: { type: "integer", default: 20 }
       }
     }
   }

   TOOLS["memory.recall_details"] = {
     description: "Layer 2: Fetch full fact details by IDs.",
     input_schema: {
       type: "object",
       properties: {
         fact_ids: { type: "array", items: { type: "integer" } }
       },
       required: ["fact_ids"]
     }
   }
   ```

4. **Update publish format** to show costs:
   ```markdown
   ## Recent Facts

   | ID | Subject | Predicate | Preview | Tokens |
   |----|---------|-----------|---------|--------|
   | #123 | project | uses_database | PostgreSQL | ~45 |
   | #124 | project | has_constraint | API rate lim... | ~120 |
   ```

**Benefits**:
- Reduces context waste in published snapshots
- Gives Claude control over retrieval depth
- Makes token costs visible for informed decisions

**Trade-offs**:
- More complex MCP interface
- Requires token estimation logic
- May confuse users who expect full details

---

## 2. ROI Metrics and Token Economics

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

## 3. Privacy Tag System

### What claude-mem Does

**Dual-Tag Architecture** for content exclusion:

1. **`<claude-mem-context>`** (system tag):
   - Prevents recursive storage when context is auto-injected
   - Strips at hook layer before worker sees it

2. **`<private>`** (user tag):
   - Manual privacy control
   - Users wrap sensitive content to exclude from storage
   - Example: `API key: <private>sk-abc123</private>`

**File**: `src/utils/tag-stripping.ts`

```typescript
export function stripPrivateTags(text: string): string {
  const MAX_TAG_COUNT = 100;  // ReDoS protection

  return text
    .replace(/<claude-mem-context>[\s\S]*?<\/claude-mem-context>/g, '')
    .replace(/<private>[\s\S]*?<\/private>/g, '');
}
```

**Edge Processing Philosophy**: Stripping happens at hook layer (before data reaches database).

### What We Should Do

**Priority**: HIGH

**Implementation**:

1. **Add tag stripping to ingester**:
   ```ruby
   # lib/claude_memory/ingest/transcript_reader.rb
   class TranscriptReader
     SYSTEM_TAGS = ['claude-memory-context'].freeze
     USER_TAGS = ['private', 'no-memory'].freeze
     MAX_TAG_COUNT = 100

     def strip_tags(text)
       validate_tag_count(text)

       ALL_TAGS = SYSTEM_TAGS + USER_TAGS
       ALL_TAGS.each do |tag|
         text = text.gsub(/<#{tag}>.*?<\/#{tag}>/m, '')
       end

       text
     end

     def validate_tag_count(text)
       count = text.scan(/<(?:#{ALL_TAGS.join('|')})>/).size
       raise "Too many tags (#{count}), possible ReDoS" if count > MAX_TAG_COUNT
     end
   end
   ```

2. **Document in README**:
   ```markdown
   ## Privacy Control

   Wrap sensitive content in `<private>` tags to exclude from storage:

   ```
   API endpoint: https://api.example.com
   API key: <private>sk-abc123def456</private>
   ```

   System tags (auto-stripped):
   - `<claude-memory-context>` - Prevents recursive storage of published memory
   ```

3. **Add to hook handler**:
   ```ruby
   # lib/claude_memory/hook/handler.rb
   def ingest_hook
     input = read_stdin
     transcript = input[:transcript_delta]

     # Strip tags before processing
     transcript = strip_privacy_tags(transcript)

     ingester.ingest(transcript)
   end
   ```

4. **Test edge cases**:
   ```ruby
   # spec/claude_memory/ingest/transcript_reader_spec.rb
   it "strips nested private tags" do
     text = "Public <private>Secret <private>Nested</private></private> Public"
     expect(strip_tags(text)).to eq("Public  Public")
   end

   it "prevents ReDoS with many tags" do
     text = "<private>" * 101
     expect { strip_tags(text) }.to raise_error(/Too many tags/)
   end
   ```

**Benefits**:
- User control over sensitive data
- Prevents credential leakage
- Protects recursive context injection
- Security-conscious design

**Trade-offs**:
- Users must remember to tag sensitive content
- May create false sense of security
- Regex-based (could miss edge cases)

---

## 4. Slim Orchestrator Pattern

### What claude-mem Does

**Worker Service Evolution**: Refactored from 2,000 lines → 300 lines orchestrator.

**File Structure**:
```
src/services/worker-service.ts (300 lines - orchestrator)
  ↓ delegates to
src/server/Server.ts (Express setup)
src/services/sqlite/Database.ts (data layer)
src/services/worker/ (business logic)
  ├── SDKAgent.ts (agent management)
  ├── SessionManager.ts (session lifecycle)
  └── search/SearchOrchestrator.ts (search strategies)
src/infrastructure/ (process management)
```

**Benefit**: Testability, readability, separation of concerns.

### What We Should Do

**Priority**: MEDIUM

**Current State**:
- `lib/claude_memory/cli.rb`: 800+ lines (all commands)
- Logic mixed with CLI parsing
- Hard to test individual commands

**Implementation**:

1. **Extract command classes**:
   ```ruby
   # lib/claude_memory/commands/
   ├── base_command.rb
   ├── ingest_command.rb
   ├── recall_command.rb
   ├── publish_command.rb
   ├── promote_command.rb
   └── sweep_command.rb
   ```

2. **Slim CLI to routing**:
   ```ruby
   # lib/claude_memory/cli.rb (150 lines)
   module ClaudeMemory
     class CLI
       def run(args)
         command_name = args[0]
         command = command_for(command_name)
         command.run(args[1..])
       end

       private

       def command_for(name)
         case name
         when "ingest" then Commands::IngestCommand.new
         when "recall" then Commands::RecallCommand.new
         # ...
         end
       end
     end
   end
   ```

3. **Command base class**:
   ```ruby
   # lib/claude_memory/commands/base_command.rb
   module ClaudeMemory
     module Commands
       class BaseCommand
         def initialize
           @store_manager = Store::StoreManager.new
         end

         def run(args)
           options = parse_options(args)
           validate_options(options)
           execute(options)
         end

         private

         def parse_options(args)
           raise NotImplementedError
         end

         def execute(options)
           raise NotImplementedError
         end
       end
     end
   end
   ```

4. **Example command**:
   ```ruby
   # lib/claude_memory/commands/recall_command.rb
   module ClaudeMemory
     module Commands
       class RecallCommand < BaseCommand
         def parse_options(args)
           OptionParser.new do |opts|
             opts.on("--query QUERY") { |q| options[:query] = q }
             opts.on("--scope SCOPE") { |s| options[:scope] = s }
           end.parse!(args)
         end

         def execute(options)
           results = Recall.search(
             options[:query],
             scope: options[:scope]
           )
           puts format_results(results)
         end
       end
     end
   end
   ```

**Benefits**:
- Each command is independently testable
- CLI.rb becomes simple router
- Easier to add new commands
- Clear separation of parsing vs execution

**Trade-offs**:
- More files to navigate
- Slightly more boilerplate
- May be overkill for small CLI

---

## 5. Health Monitoring and Process Management

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

## 6. Semantic Shortcuts and Search Strategies

### What claude-mem Does

**Semantic Shortcuts** (pre-configured queries):

```typescript
// File: src/services/worker/http/routes/SearchRoutes.ts
app.get('/api/decisions', (req, res) => {
  const results = await search({ type: 'decision' });
  res.json(results);
});

app.get('/api/changes', (req, res) => {
  const results = await search({ type: ['feature', 'change'] });
  res.json(results);
});

app.get('/api/how-it-works', (req, res) => {
  const results = await search({ type: 'how-it-works' });
  res.json(results);
});
```

**Search Strategy Pattern**:

```typescript
// File: src/services/worker/search/SearchOrchestrator.ts
class SearchOrchestrator {
  strategies: [
    ChromaSearchStrategy,    // Vector search (if available)
    SQLiteSearchStrategy,    // FTS5 fallback
    HybridSearchStrategy     // Combine both
  ]

  async search(query, options) {
    const strategy = selectStrategy(options);
    return strategy.execute(query);
  }
}
```

**Fallback Logic**:
1. Try Chroma vector search (semantic)
2. Fall back to SQLite FTS5 (keyword)
3. Merge and re-rank results if both available

### What We Should Do

**Priority**: MEDIUM

**Implementation**:

1. **Add shortcut methods to Recall**:
   ```ruby
   # lib/claude_memory/recall.rb
   module ClaudeMemory
     class Recall
       class << self
         def recent_decisions(limit: 10)
           search("decision constraint rule", limit:)
         end

         def architecture_choices(limit: 10)
           search("uses framework implements architecture", limit:)
         end

         def conventions(limit: 20)
           search("convention style format pattern", scope: :global, limit:)
         end

         def project_config(limit: 10)
           search("uses requires depends_on", scope: :project, limit:)
         end
       end
     end
   end
   ```

2. **Add MCP tools for shortcuts**:
   ```ruby
   # lib/claude_memory/mcp/tools.rb
   TOOLS["memory.decisions"] = {
     description: "Quick access to architectural decisions and constraints",
     input_schema: { type: "object", properties: { limit: { type: "integer" } } }
   }

   TOOLS["memory.conventions"] = {
     description: "Quick access to coding conventions and preferences",
     input_schema: { type: "object", properties: { limit: { type: "integer" } } }
   }
   ```

3. **Search strategy pattern** (future: if we add vector search):
   ```ruby
   # lib/claude_memory/index/search_strategy.rb
   module ClaudeMemory
     module Index
       class SearchStrategy
         def self.select(options)
           if options[:semantic] && vector_db_available?
             VectorSearchStrategy.new
           else
             LexicalSearchStrategy.new
           end
         end
       end

       class LexicalSearchStrategy < SearchStrategy
         def search(query)
           LexicalFTS.search(query)
         end
       end

       class VectorSearchStrategy < SearchStrategy
         def search(query)
           # Future: vector embeddings
         end
       end
     end
   end
   ```

**Benefits**:
- Common queries are one command
- Reduces cognitive load
- Pre-optimized for specific use cases
- Strategy pattern enables future enhancements

**Trade-offs**:
- Need to pick right shortcuts (user research)
- May not cover all use cases
- Shortcuts can become stale

---

## 7. Web-Based Viewer UI

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

## 8. Dual-Integration Strategy

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

## 9. Exit Code Strategy for Hooks

### What claude-mem Does

**Hook Exit Code Contract**:

```typescript
// Success or graceful shutdown
process.exit(0);  // Windows Terminal closes tab

// Non-blocking error (show to user, continue)
console.error("Warning: ...");
process.exit(1);

// Blocking error (feed to Claude for processing)
console.error("ERROR: ...");
process.exit(2);
```

**Philosophy**: Worker/hook errors exit with 0 to prevent Windows Terminal tab accumulation.

**File**: `docs/context/claude-code/exit-codes.md`

### What We Should Do

**Priority**: MEDIUM (if we add hooks)

**Implementation**:

1. **Define exit code constants**:
   ```ruby
   # lib/claude_memory/hook/exit_codes.rb
   module ClaudeMemory
     module Hook
       module ExitCodes
         SUCCESS = 0
         WARNING = 1  # Non-blocking error
         ERROR = 2    # Blocking error
       end
     end
   end
   ```

2. **Use in hook handler**:
   ```ruby
   # lib/claude_memory/hook/handler.rb
   def run
     handle_hook(ARGV[0])
     exit ExitCodes::SUCCESS
   rescue NonBlockingError => e
     warn e.message
     exit ExitCodes::WARNING
   rescue => e
     $stderr.puts "ERROR: #{e.message}"
     exit ExitCodes::ERROR
   end
   ```

3. **Document in CLAUDE.md**:
   ```markdown
   ## Hook Exit Codes

   - **0**: Success or graceful shutdown
   - **1**: Non-blocking error (shown to user, session continues)
   - **2**: Blocking error (fed to Claude for processing)
   ```

**Benefits**:
- Clear contract with Claude Code
- Predictable behavior
- Better error handling

**Trade-offs**:
- Hook-specific pattern
- Not applicable to MCP server

---

## 10. Configuration-Driven Context Injection

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

## Implementation Priorities

### High Priority (Next Sprint)

1. **Progressive Disclosure Pattern** - Add index format to Recall, update MCP tools
2. **Privacy Tag System** - Implement `<private>` tag stripping
3. **Exit Code Strategy** - Define exit codes for future hooks

### Medium Priority (Next Quarter)

4. **ROI Metrics** - Track token economics
5. **Slim Orchestrator Pattern** - Extract commands from CLI
6. **Semantic Shortcuts** - Add convenience methods to Recall
7. **Search Strategies** - Prepare for future vector search

### Low Priority (Future)

8. **Health Monitoring** - Only if we add background worker
9. **Dual Integration** - Only if we add Claude Code hooks
10. **Config-Driven Context** - Only if users request customization
11. **Web Viewer UI** - Only if users request visualization

---

## Migration Path

### Phase 1: Quick Wins (1-2 weeks)

- [ ] Implement `<private>` tag stripping in ingester
- [ ] Add token count estimation to facts
- [ ] Create index format in Recall
- [ ] Add `memory.recall_index` MCP tool
- [ ] Document progressive disclosure pattern

### Phase 2: Structural (1 month)

- [ ] Extract command classes from CLI
- [ ] Add metrics table for token tracking
- [ ] Implement semantic shortcuts
- [ ] Add search strategy pattern (prep for vector search)

### Phase 3: Advanced (3+ months)

- [ ] Add vector embeddings (if requested)
- [ ] Build web viewer (if requested)
- [ ] Add Claude Code hooks (if requested)
- [ ] Implement background worker (if needed)

---

## Key Takeaways

**What claude-mem does exceptionally well**:
1. Progressive disclosure (token efficiency)
2. ROI metrics (visibility)
3. Privacy controls (user trust)
4. Clean architecture (maintainability)
5. Production polish (error handling, logging, health checks)

**What we do better**:
1. Dual-database architecture (global + project)
2. Fact-based knowledge graph (structured)
3. Truth maintenance (conflict resolution)
4. Predicate policies (semantic understanding)
5. Simpler dependencies (Ruby ecosystem)

**Our path forward**:
- Adopt their token efficiency patterns
- Keep our knowledge graph architecture
- Add privacy controls
- Improve observability (metrics)
- Maintain simplicity (avoid over-engineering)

---

## References

- [claude-mem GitHub](https://github.com/thedotmack/claude-mem)
- [Architecture Evolution](../claude-mem/docs/public/architecture-evolution.mdx)
- [Progressive Disclosure Philosophy](../claude-mem/docs/public/progressive-disclosure.mdx)
- [ClaudeMemory Updated Plan](updated_plan.md)

---

*This analysis represents a critical review of production-grade patterns that have proven effective in real-world usage. Our goal is to learn from claude-mem's strengths while preserving the unique advantages of our fact-based approach.*
