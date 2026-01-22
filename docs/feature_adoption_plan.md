# ClaudeMemory Feature Adoption Plan
## Based on claude-mem Analysis

## Executive Summary

This plan incrementally adopts proven patterns from claude-mem (a production-grade memory system with 6+ months of real-world usage) while preserving ClaudeMemory's unique advantages (dual-database architecture, fact-based knowledge graph, truth maintenance system).

**Timeline:** 4-6 weeks across 3 phases
**Approach:** TDD, backward compatible, high-impact features first
**Risk Level:** Low

### Features Already Complete ✅
- **Slim Orchestrator Pattern** - CLI decomposed into 16 command classes (Phase 2 of previous refactoring)
- **Domain-Driven Design** - Rich domain models with business logic
- **Transaction Safety** - Multi-step operations wrapped in transactions
- **FileSystem Abstraction** - In-memory testing without disk I/O

---

## Phase 1: Privacy & Token Economics (Weeks 1-2)
### High-impact features with security and observability benefits

### 1.1 Privacy Tag System (Days 1-3)

**Priority:** HIGH - Security and user trust

**Goal:** Allow users to exclude sensitive content from storage using `<private>` tags

#### Implementation Steps

**1. Create Content Sanitizer (Day 1)**

**New file:** `lib/claude_memory/ingest/content_sanitizer.rb`

```ruby
# frozen_string_literal: true

module ClaudeMemory
  module Ingest
    class ContentSanitizer
      SYSTEM_TAGS = ["claude-memory-context"].freeze
      USER_TAGS = ["private", "no-memory", "secret"].freeze
      MAX_TAG_COUNT = 100 # ReDoS protection

      def self.strip_tags(text)
        validate_tag_count!(text)

        all_tags = SYSTEM_TAGS + USER_TAGS
        all_tags.each do |tag|
          # Match opening and closing tags, including multiline content
          text = text.gsub(/<#{Regexp.escape(tag)}>.*?<\/#{Regexp.escape(tag)}>/m, "")
        end

        text
      end

      def self.validate_tag_count!(text)
        all_tags = SYSTEM_TAGS + USER_TAGS
        pattern = /<(?:#{all_tags.join("|")})>/
        count = text.scan(pattern).size

        raise Error, "Too many privacy tags (#{count}), possible ReDoS attack" if count > MAX_TAG_COUNT
      end
    end
  end
end
```

**Tests:** `spec/claude_memory/ingest/content_sanitizer_spec.rb`
```ruby
RSpec.describe ClaudeMemory::Ingest::ContentSanitizer do
  describe ".strip_tags" do
    it "strips <private> tags and content" do
      text = "Public <private>Secret</private> Public"
      expect(described_class.strip_tags(text)).to eq("Public  Public")
    end

    it "strips multiple tag types" do
      text = "A <private>X</private> B <no-memory>Y</no-memory> C"
      expect(described_class.strip_tags(text)).to eq("A  B  C")
    end

    it "handles nested tags" do
      text = "Public <private>Outer <private>Inner</private></private> End"
      expect(described_class.strip_tags(text)).to eq("Public  End")
    end

    it "preserves multiline content structure" do
      text = "Line 1\n<private>Line 2\nLine 3</private>\nLine 4"
      result = described_class.strip_tags(text)
      expect(result).to eq("Line 1\n\nLine 4")
    end

    it "raises error on excessive tags (ReDoS protection)" do
      text = "<private>" * 101
      expect { described_class.strip_tags(text) }.to raise_error(ClaudeMemory::Error, /Too many privacy tags/)
    end

    it "strips claude-memory-context system tags" do
      text = "Before <claude-memory-context>Context</claude-memory-context> After"
      expect(described_class.strip_tags(text)).to eq("Before  After")
    end
  end

  describe ".validate_tag_count!" do
    it "accepts reasonable tag counts" do
      text = "<private>x</private>" * 50
      expect { described_class.validate_tag_count!(text) }.not_to raise_error
    end

    it "rejects excessive tag counts" do
      text = "<private>x</private>" * 101
      expect { described_class.validate_tag_count!(text) }.to raise_error(ClaudeMemory::Error)
    end
  end
end
```

**Commit:** "Add ContentSanitizer for privacy tag stripping with ReDoS protection"

**2. Integrate into Ingester (Day 2)**

**Modify:** `lib/claude_memory/ingest/ingester.rb` (after line 22)

```ruby
def ingest(source:, session_id:, transcript_path:, project_path: nil)
  current_offset = @store.get_delta_cursor(session_id, transcript_path) || 0
  delta, new_offset = TranscriptReader.read_delta(transcript_path, current_offset)

  # NEW: Strip privacy tags before processing
  delta = ContentSanitizer.strip_tags(delta)

  return {status: :empty, message: "No content after cursor #{current_offset}"} if delta.empty?

  # ... rest of method unchanged
end
```

**Tests:** Add to `spec/claude_memory/ingest/ingester_spec.rb`
```ruby
it "strips privacy tags from ingested content" do
  File.write(transcript_path, "Public <private>Secret API key</private> Public")

  ingester.ingest(
    source: "test",
    session_id: "sess-123",
    transcript_path: transcript_path
  )

  # Verify stored content is sanitized
  item = store.content_items.first
  expect(item[:raw_text]).to eq("Public  Public")
  expect(item[:raw_text]).not_to include("Secret API key")
end

it "strips claude-memory-context tags" do
  File.write(transcript_path, "New <claude-memory-context>Old context</claude-memory-context> Content")

  ingester.ingest(
    source: "test",
    session_id: "sess-123",
    transcript_path: transcript_path
  )

  item = store.content_items.first
  expect(item[:raw_text]).to eq("New  Content")
end
```

**Commit:** "Integrate ContentSanitizer into Ingester"

**3. Update Documentation (Day 3)**

**Modify:** `README.md` - Add "Privacy Control" section after "Usage Examples"

```markdown
## Privacy Control

ClaudeMemory respects user privacy through content exclusion tags. Wrap sensitive information in `<private>` tags to prevent storage:

### Example

\`\`\`
API Configuration:
- Endpoint: https://api.example.com
- API Key: <private>sk-abc123def456789</private>
- Rate Limit: 1000/hour
\`\`\`

The API key will be stripped before storage, while other information is preserved.

### Supported Tags

- `<private>...</private>` - User-controlled privacy (recommended)
- `<no-memory>...</no-memory>` - Alternative privacy tag
- `<secret>...</secret>` - Alternative privacy tag

### System Tags

- `<claude-memory-context>...</claude-memory-context>` - Auto-stripped to prevent recursive storage of published memory

### Security Notes

- Tags are stripped at ingestion time (edge processing)
- Protected against ReDoS attacks (max 100 tags per ingestion)
- Content within tags is never stored or indexed
```

**Modify:** `CLAUDE.md` - Add to "Hook Integration" section

```markdown
### Privacy Tag Handling

ClaudeMemory automatically strips privacy tags during ingestion:

\`\`\`ruby
# User input:
"Database: postgresql, Password: <private>secret123</private>"

# Stored content:
"Database: postgresql, Password: "
\`\`\`

This happens at the hook layer before content reaches the database. Supported tags:
- `<private>` - User privacy control
- `<no-memory>` - Alternative syntax
- `<secret>` - Alternative syntax
- `<claude-memory-context>` - System tag (prevents recursive context injection)

ReDoS protection: Max 100 tags per ingestion.
```

**Commit:** "Document privacy tag system in README and CLAUDE.md"

---

### 1.2 Progressive Disclosure Pattern (Days 4-7)

**Priority:** HIGH - Token efficiency and cost reduction

**Goal:** Enable 2-tier retrieval (lightweight index → detailed fetch) to reduce context waste

#### Implementation Steps

**1. Add Token Estimation (Day 4)**

**New file:** `lib/claude_memory/core/token_estimator.rb`

```ruby
# frozen_string_literal: true

module ClaudeMemory
  module Core
    class TokenEstimator
      # Approximation: ~4 characters per token for English text
      # More accurate for Claude's tokenizer than simple word count
      CHARS_PER_TOKEN = 4.0

      def self.estimate(text)
        return 0 if text.nil? || text.empty?

        # Remove extra whitespace and count characters
        normalized = text.strip.gsub(/\s+/, " ")
        chars = normalized.length

        # Return ceiling to avoid underestimation
        (chars / CHARS_PER_TOKEN).ceil
      end

      def self.estimate_fact(fact)
        # Estimate tokens for a fact record
        text = [
          fact[:subject_name],
          fact[:predicate],
          fact[:object_literal]
        ].compact.join(" ")

        estimate(text)
      end
    end
  end
end
```

**Tests:** `spec/claude_memory/core/token_estimator_spec.rb`
```ruby
RSpec.describe ClaudeMemory::Core::TokenEstimator do
  describe ".estimate" do
    it "estimates tokens for short text" do
      expect(described_class.estimate("hello world")).to eq(3)
    end

    it "estimates tokens for longer text" do
      text = "The quick brown fox jumps over the lazy dog"
      expect(described_class.estimate(text)).to be_between(10, 12)
    end

    it "handles empty text" do
      expect(described_class.estimate("")).to eq(0)
      expect(described_class.estimate(nil)).to eq(0)
    end

    it "normalizes whitespace" do
      expect(described_class.estimate("a    b    c")).to eq(described_class.estimate("a b c"))
    end
  end

  describe ".estimate_fact" do
    it "estimates tokens for fact" do
      fact = {
        subject_name: "project",
        predicate: "uses_database",
        object_literal: "PostgreSQL"
      }

      tokens = described_class.estimate_fact(fact)
      expect(tokens).to be > 0
      expect(tokens).to be < 10
    end
  end
end
```

**Commit:** "Add TokenEstimator for progressive disclosure"

**2. Add Index Format to Recall (Day 5)**

**Modify:** `lib/claude_memory/recall.rb` - Add new method after line 28

```ruby
# Returns lightweight index format (no full content)
def query_index(query_text, limit: 20, scope: SCOPE_ALL)
  if @legacy_mode
    query_index_legacy(query_text, limit: limit, scope: scope)
  else
    query_index_dual(query_text, limit: limit, scope: scope)
  end
end

private

def query_index_dual(query_text, limit:, scope:)
  results = []

  if scope == SCOPE_ALL || scope == SCOPE_PROJECT
    @manager.ensure_project! if @manager.project_exists?
    if @manager.project_store
      project_results = query_index_single_store(@manager.project_store, query_text, limit: limit, source: :project)
      results.concat(project_results)
    end
  end

  if scope == SCOPE_ALL || scope == SCOPE_GLOBAL
    @manager.ensure_global! if @manager.global_exists?
    if @manager.global_store
      global_results = query_index_single_store(@manager.global_store, query_text, limit: limit, source: :global)
      results.concat(global_results)
    end
  end

  dedupe_and_sort(results, limit)
end

def query_index_single_store(store, query_text, limit:, source:)
  fts = Index::LexicalFTS.new(store)
  content_ids = fts.search(query_text, limit: limit * 3)
  return [] if content_ids.empty?

  # Collect fact IDs (same as query_single_store)
  seen_fact_ids = Set.new
  ordered_fact_ids = []

  content_ids.each do |content_id|
    provenance_records = store.provenance
      .select(:fact_id)
      .where(content_item_id: content_id)
      .all

    provenance_records.each do |prov|
      fact_id = prov[:fact_id]
      next if seen_fact_ids.include?(fact_id)

      seen_fact_ids.add(fact_id)
      ordered_fact_ids << fact_id
      break if ordered_fact_ids.size >= limit
    end
    break if ordered_fact_ids.size >= limit
  end

  return [] if ordered_fact_ids.empty?

  # Batch query facts but return INDEX format (lightweight)
  store.facts
    .left_join(:entities, id: :subject_entity_id)
    .select(
      Sequel[:facts][:id],
      Sequel[:facts][:predicate],
      Sequel[:facts][:object_literal],
      Sequel[:facts][:status],
      Sequel[:entities][:canonical_name].as(:subject_name),
      Sequel[:facts][:scope],
      Sequel[:facts][:confidence]
    )
    .where(Sequel[:facts][:id] => ordered_fact_ids)
    .all
    .map do |fact|
      {
        id: fact[:id],
        subject: fact[:subject_name],
        predicate: fact[:predicate],
        object_preview: fact[:object_literal]&.slice(0, 50), # Truncate for preview
        status: fact[:status],
        scope: fact[:scope],
        confidence: fact[:confidence],
        token_estimate: Core::TokenEstimator.estimate_fact(fact),
        source: source
      }
    end
end
```

**Tests:** Add to `spec/claude_memory/recall_spec.rb`
```ruby
describe "#query_index" do
  it "returns lightweight index format" do
    fact_id = create_fact("uses_database", "PostgreSQL with extensive configuration")

    results = recall.query_index("database", limit: 10, scope: :all)

    expect(results).not_to be_empty
    result = results.first

    # Has essential fields
    expect(result[:id]).to eq(fact_id)
    expect(result[:predicate]).to eq("uses_database")
    expect(result[:subject]).to be_present

    # Has preview (truncated)
    expect(result[:object_preview].length).to be <= 50

    # Has token estimate
    expect(result[:token_estimate]).to be > 0

    # Does NOT have full provenance
    expect(result).not_to have_key(:receipts)
    expect(result).not_to have_key(:valid_from)
  end

  it "includes token estimates" do
    create_fact("uses_framework", "React")

    results = recall.query_index("framework", limit: 10)

    expect(results.first[:token_estimate]).to be_between(1, 10)
  end
end
```

**Commit:** "Add query_index method for progressive disclosure pattern"

**3. Add MCP Tools for Progressive Disclosure (Days 6-7)**

**Modify:** `lib/claude_memory/mcp/tools.rb`

Add to `#definitions` method (around line 150):
```ruby
{
  name: "memory.recall_index",
  description: "Layer 1: Search for facts and get lightweight index (IDs, previews, token counts). Use this first before fetching full details.",
  inputSchema: {
    type: "object",
    properties: {
      query: {
        type: "string",
        description: "Search query for fact discovery"
      },
      limit: {
        type: "integer",
        description: "Maximum results to return",
        default: 20
      },
      scope: {
        type: "string",
        enum: ["all", "global", "project"],
        default: "all",
        description: "Scope: 'all' (both), 'global' (user-wide), 'project' (current only)"
      }
    },
    required: ["query"]
  }
},
{
  name: "memory.recall_details",
  description: "Layer 2: Fetch full details for specific fact IDs from the index. Use after memory.recall_index to get complete information.",
  inputSchema: {
    type: "object",
    properties: {
      fact_ids: {
        type: "array",
        items: {type: "integer"},
        description: "Fact IDs from memory.recall_index"
      },
      scope: {
        type: "string",
        enum: ["project", "global"],
        default: "project",
        description: "Database to query"
      }
    },
    required: ["fact_ids"]
  }
}
```

Add to `#call` method (around line 175):
```ruby
when "memory.recall_index"
  recall_index(arguments)
when "memory.recall_details"
  recall_details(arguments)
```

Add private methods (around line 360):
```ruby
def recall_index(args)
  scope = args["scope"] || "all"
  results = @recall.query_index(args["query"], limit: args["limit"] || 20, scope: scope)

  total_tokens = results.sum { |r| r[:token_estimate] }

  {
    query: args["query"],
    scope: scope,
    result_count: results.size,
    total_estimated_tokens: total_tokens,
    facts: results.map do |r|
      {
        id: r[:id],
        subject: r[:subject],
        predicate: r[:predicate],
        object_preview: r[:object_preview],
        status: r[:status],
        scope: r[:scope],
        confidence: r[:confidence],
        tokens: r[:token_estimate],
        source: r[:source]
      }
    end
  }
end

def recall_details(args)
  fact_ids = args["fact_ids"]
  scope = args["scope"] || "project"

  # Batch fetch detailed explanations
  explanations = fact_ids.map do |fact_id|
    explanation = @recall.explain(fact_id, scope: scope)
    next nil if explanation.is_a?(Core::NullExplanation)

    {
      fact: {
        id: explanation[:fact][:id],
        subject: explanation[:fact][:subject_name],
        predicate: explanation[:fact][:predicate],
        object: explanation[:fact][:object_literal],
        status: explanation[:fact][:status],
        confidence: explanation[:fact][:confidence],
        scope: explanation[:fact][:scope],
        valid_from: explanation[:fact][:valid_from],
        valid_to: explanation[:fact][:valid_to]
      },
      receipts: explanation[:receipts].map { |r|
        {
          quote: r[:quote],
          strength: r[:strength],
          session_id: r[:session_id],
          occurred_at: r[:occurred_at]
        }
      },
      relationships: {
        supersedes: explanation[:supersedes],
        superseded_by: explanation[:superseded_by],
        conflicts: explanation[:conflicts].map { |c| {id: c[:id], status: c[:status]} }
      }
    }
  end.compact

  {
    fact_count: explanations.size,
    facts: explanations
  }
end
```

**Tests:** Add to `spec/claude_memory/mcp/tools_spec.rb`
```ruby
describe "memory.recall_index" do
  it "returns lightweight index" do
    create_fact("uses_database", "PostgreSQL")

    result = tools.call("memory.recall_index", {"query" => "database", "limit" => 10})

    expect(result[:result_count]).to be > 0
    expect(result[:total_estimated_tokens]).to be > 0

    fact = result[:facts].first
    expect(fact[:id]).to be_present
    expect(fact[:object_preview].length).to be <= 50
    expect(fact[:tokens]).to be > 0
  end
end

describe "memory.recall_details" do
  it "fetches full details for fact IDs" do
    fact_id = create_fact("uses_framework", "React with hooks")

    result = tools.call("memory.recall_details", {
      "fact_ids" => [fact_id],
      "scope" => "project"
    })

    expect(result[:fact_count]).to eq(1)

    fact = result[:facts].first
    expect(fact[:fact][:id]).to eq(fact_id)
    expect(fact[:fact][:object]).to eq("React with hooks") # Full content
    expect(fact[:receipts]).to be_an(Array)
    expect(fact[:relationships]).to be_present
  end

  it "handles multiple fact IDs" do
    id1 = create_fact("uses_database", "PostgreSQL")
    id2 = create_fact("uses_framework", "Rails")

    result = tools.call("memory.recall_details", {
      "fact_ids" => [id1, id2]
    })

    expect(result[:fact_count]).to eq(2)
  end
end
```

**Commit:** "Add progressive disclosure MCP tools (recall_index, recall_details)"

**4. Update Documentation (Day 7)**

**Modify:** `README.md` - Update "MCP Tools" section

```markdown
### MCP Tools

When configured, these tools are available in Claude Code:

#### Progressive Disclosure Tools (Recommended)

- `memory.recall_index` - **Layer 1**: Search for facts, returns lightweight index (IDs, previews, token estimates)
- `memory.recall_details` - **Layer 2**: Fetch full details for specific fact IDs

**Workflow:**
\`\`\`
1. memory.recall_index("database")
   → Returns 10 facts with previews (~50 tokens)

2. User/Claude selects relevant IDs (e.g., [123, 456])

3. memory.recall_details([123, 456])
   → Returns complete information (~500 tokens)
\`\`\`

**Benefits:** 10x token reduction for initial search, user control over detail retrieval

#### Full-Content Tools (Legacy)

- `memory.recall` - Search for relevant facts (returns full details immediately)
- `memory.explain` - Get detailed fact provenance
- `memory.promote` - Promote a project fact to global memory
- `memory.store_extraction` - Store extracted facts from a conversation
- `memory.changes` - Recent fact updates
- `memory.conflicts` - Open contradictions
- `memory.sweep_now` - Run maintenance
- `memory.status` - System health check
```

**Modify:** `CLAUDE.md` - Update "MCP Integration" section

```markdown
## MCP Integration

### Progressive Disclosure Workflow

ClaudeMemory uses a 2-layer retrieval pattern for token efficiency:

**Layer 1 - Discovery (`memory.recall_index`)**
Returns lightweight index with:
- Fact IDs and previews (50 char max)
- Token estimates per fact
- Scope and confidence
- Total estimated cost for full retrieval

**Layer 2 - Detail (`memory.recall_details`)**
Returns complete information for selected IDs:
- Full fact content
- Complete provenance with quotes
- Relationship graph (supersession, conflicts)
- Temporal validity

Example usage in Claude Code:

\`\`\`
Claude: Let me search your memory for database configuration
Tool: memory.recall_index(query="database", limit=10)
Result: Found 5 facts (~150 tokens if retrieved)

Claude: I'll fetch details for the 2 most relevant facts
Tool: memory.recall_details(fact_ids=[123, 124])
Result: Full details for PostgreSQL configuration
\`\`\`

This reduces initial context by ~10x compared to fetching all details immediately.
```

**Commit:** "Document progressive disclosure pattern in README and CLAUDE.md"

---

## Phase 2: Semantic Enhancements (Weeks 3-4)
### Improved query patterns and shortcuts

### 2.1 Semantic Shortcut Methods (Days 8-10)

**Priority:** MEDIUM - Developer convenience

**Goal:** Pre-configured queries for common use cases

#### Implementation Steps

**1. Add Shortcut Methods to Recall (Day 8)**

**Modify:** `lib/claude_memory/recall.rb` - Add class methods after line 55

```ruby
class << self
  def recent_decisions(manager, limit: 10)
    recall = new(manager)
    recall.query("decision constraint rule requirement", limit: limit, scope: SCOPE_ALL)
  end

  def architecture_choices(manager, limit: 10)
    recall = new(manager)
    recall.query("uses framework implements architecture pattern", limit: limit, scope: SCOPE_ALL)
  end

  def conventions(manager, limit: 20)
    recall = new(manager)
    recall.query("convention style format pattern prefer", limit: limit, scope: SCOPE_GLOBAL)
  end

  def project_config(manager, limit: 10)
    recall = new(manager)
    recall.query("uses requires depends_on configuration", limit: limit, scope: SCOPE_PROJECT)
  end

  def recent_changes(manager, days: 7, limit: 20)
    recall = new(manager)
    since = Time.now - (days * 24 * 60 * 60)
    recall.changes(since: since, limit: limit, scope: SCOPE_ALL)
  end
end
```

**Tests:** Add to `spec/claude_memory/recall_spec.rb`
```ruby
describe ".recent_decisions" do
  it "returns decision-related facts" do
    create_fact("decision", "Use PostgreSQL for primary database")
    create_fact("constraint", "API rate limit 1000/min")

    results = described_class.recent_decisions(manager, limit: 10)

    expect(results.size).to be >= 2
    expect(results.map { |r| r[:fact][:predicate] }).to include("decision", "constraint")
  end
end

describe ".conventions" do
  it "returns only global scope conventions" do
    create_global_fact("convention", "Use 4-space indentation")
    create_project_fact("convention", "Project uses tabs")

    results = described_class.conventions(manager, limit: 10)

    # Should only return global convention
    expect(results.size).to eq(1)
    expect(results.first[:fact][:object_literal]).to eq("Use 4-space indentation")
  end
end
```

**Commit:** "Add semantic shortcut methods to Recall"

**2. Add MCP Tools for Shortcuts (Day 9)**

**Modify:** `lib/claude_memory/mcp/tools.rb`

Add definitions (around line 150):
```ruby
{
  name: "memory.decisions",
  description: "Quick access to architectural decisions, constraints, and rules",
  inputSchema: {
    type: "object",
    properties: {
      limit: {type: "integer", default: 10}
    }
  }
},
{
  name: "memory.conventions",
  description: "Quick access to coding conventions and style preferences (global scope)",
  inputSchema: {
    type: "object",
    properties: {
      limit: {type: "integer", default: 20}
    }
  }
},
{
  name: "memory.architecture",
  description: "Quick access to framework choices and architectural patterns",
  inputSchema: {
    type: "object",
    properties: {
      limit: {type: "integer", default: 10}
    }
  }
}
```

Add handlers (around line 175):
```ruby
when "memory.decisions"
  decisions(arguments)
when "memory.conventions"
  conventions(arguments)
when "memory.architecture"
  architecture(arguments)

# ... private methods (around line 400):

def decisions(args)
  results = Recall.recent_decisions(@manager, limit: args["limit"] || 10)
  format_shortcut_results(results, "decisions")
end

def conventions(args)
  results = Recall.conventions(@manager, limit: args["limit"] || 20)
  format_shortcut_results(results, "conventions")
end

def architecture(args)
  results = Recall.architecture_choices(@manager, limit: args["limit"] || 10)
  format_shortcut_results(results, "architecture")
end

def format_shortcut_results(results, category)
  {
    category: category,
    count: results.size,
    facts: results.map do |r|
      {
        id: r[:fact][:id],
        subject: r[:fact][:subject_name],
        predicate: r[:fact][:predicate],
        object: r[:fact][:object_literal],
        scope: r[:fact][:scope],
        source: r[:source]
      }
    end
  }
end
```

**Commit:** "Add semantic shortcut MCP tools (decisions, conventions, architecture)"

**3. Update Documentation (Day 10)**

**Modify:** `README.md` - Add "Semantic Shortcuts" section

```markdown
### Semantic Shortcuts

Quick access to common queries via MCP tools:

- `memory.decisions` - Architectural decisions, constraints, and rules
- `memory.conventions` - Coding conventions and style preferences (global scope)
- `memory.architecture` - Framework choices and architectural patterns

These shortcuts use optimized queries for specific use cases, reducing the need for manual query construction.

#### CLI Usage

\`\`\`bash
# Get all architectural decisions
claude-memory recall "decision constraint rule"

# Get global conventions only
claude-memory recall "convention style format" --scope global

# Get project architecture
claude-memory recall "uses framework architecture" --scope project
\`\`\`
```

**Commit:** "Document semantic shortcuts in README"

---

### 2.2 Exit Code Strategy for Hooks (Day 11)

**Priority:** MEDIUM - Better error handling for Claude Code integration

**Goal:** Define clear exit code contract for hook commands

#### Implementation Steps

**1. Create Exit Code Constants**

**New file:** `lib/claude_memory/hook/exit_codes.rb`

```ruby
# frozen_string_literal: true

module ClaudeMemory
  module Hook
    module ExitCodes
      # Success or graceful shutdown
      SUCCESS = 0

      # Non-blocking error (shown to user, session continues)
      # Example: Missing transcript file, database not initialized
      WARNING = 1

      # Blocking error (fed to Claude for processing)
      # Example: Database corruption, schema mismatch
      ERROR = 2
    end
  end
end
```

**Modify:** `lib/claude_memory/hook/handler.rb` - Add error classes

```ruby
class Handler
  class NonBlockingError < StandardError; end
  class BlockingError < StandardError; end

  # ... existing code ...

  def handle_error(error)
    case error
    when NonBlockingError
      warn "Warning: #{error.message}"
      ExitCodes::WARNING
    when BlockingError
      $stderr.puts "ERROR: #{error.message}"
      ExitCodes::ERROR
    else
      # Unknown errors are blocking by default (safer)
      $stderr.puts "ERROR: #{error.class}: #{error.message}"
      ExitCodes::ERROR
    end
  end
end
```

**Modify:** `lib/claude_memory/commands/hook_command.rb` - Return proper exit codes

```ruby
def call(args)
  # ... existing code ...

  case subcommand
  when "ingest"
    result = handler.ingest(payload)
    result[:status] == :skipped ? Hook::ExitCodes::WARNING : Hook::ExitCodes::SUCCESS
  when "sweep"
    handler.sweep(payload)
    Hook::ExitCodes::SUCCESS
  when "publish"
    handler.publish(payload)
    Hook::ExitCodes::SUCCESS
  else
    stderr.puts "Unknown hook subcommand: #{subcommand}"
    Hook::ExitCodes::ERROR
  end
rescue Handler::NonBlockingError => e
  handler.handle_error(e)
rescue => e
  handler.handle_error(e)
end
```

**Tests:** Add to `spec/claude_memory/commands/hook_command_spec.rb`
```ruby
it "returns SUCCESS exit code for successful ingest" do
  payload = {
    "subcommand" => "ingest",
    "session_id" => "sess-123",
    "transcript_path" => transcript_path
  }

  exit_code = command.call(["ingest"], stdin: StringIO.new(JSON.generate(payload)))
  expect(exit_code).to eq(Hook::ExitCodes::SUCCESS)
end

it "returns WARNING exit code for skipped ingest" do
  payload = {
    "subcommand" => "ingest",
    "session_id" => "sess-123",
    "transcript_path" => "/nonexistent/file"
  }

  exit_code = command.call(["ingest"], stdin: StringIO.new(JSON.generate(payload)))
  expect(exit_code).to eq(Hook::ExitCodes::WARNING)
end
```

**Update:** `CLAUDE.md`

```markdown
## Hook Exit Codes

ClaudeMemory hooks follow a standardized exit code contract:

- **0 (SUCCESS)**: Hook completed successfully or gracefully shut down
- **1 (WARNING)**: Non-blocking error (shown to user, session continues)
  - Examples: Missing transcript file, database not initialized, empty delta
- **2 (ERROR)**: Blocking error (fed to Claude for processing)
  - Examples: Database corruption, schema version mismatch, critical failures

This ensures predictable behavior when integrated with Claude Code hooks system.
```

**Commit:** "Add exit code strategy for hook commands"

---

## Phase 3: Future Enhancements (Optional)
### Lower priority features for later consideration

### 3.1 Token Economics Tracking (Days 12-15, Optional)

**Priority:** LOW-MEDIUM - Observability

**Goal:** Track token usage metrics to demonstrate memory system efficiency

**Note:** This requires distiller integration (currently a stub). Skip if distiller not implemented.

#### High-Level Steps

1. Add `ingestion_metrics` table to schema
2. Track tokens during distillation
3. Add `stats` CLI command
4. Add metrics footer to publish output

**Deferred:** Wait for distiller implementation

---

## Critical Files Reference

### Phase 1: Privacy & Token Economics

#### New Files
- `lib/claude_memory/ingest/content_sanitizer.rb` - Privacy tag stripping
- `lib/claude_memory/core/token_estimator.rb` - Token estimation
- `spec/claude_memory/ingest/content_sanitizer_spec.rb` - Tests
- `spec/claude_memory/core/token_estimator_spec.rb` - Tests

#### Modified Files
- `lib/claude_memory/ingest/ingester.rb` - Integrate ContentSanitizer
- `lib/claude_memory/recall.rb` - Add query_index method
- `lib/claude_memory/mcp/tools.rb` - Add progressive disclosure tools
- `README.md` - Document privacy tags and progressive disclosure
- `CLAUDE.md` - Document privacy tags and MCP tools

### Phase 2: Semantic Enhancements

#### New Files
- `lib/claude_memory/hook/exit_codes.rb` - Exit code constants

#### Modified Files
- `lib/claude_memory/recall.rb` - Add shortcut class methods
- `lib/claude_memory/mcp/tools.rb` - Add shortcut MCP tools
- `lib/claude_memory/hook/handler.rb` - Use exit codes
- `lib/claude_memory/commands/hook_command.rb` - Return exit codes
- `README.md` - Document semantic shortcuts
- `CLAUDE.md` - Document exit codes

---

## Testing Strategy

### Test-First Workflow
1. Write failing test for new behavior
2. Implement minimal code to pass
3. Refactor while keeping tests green
4. Commit with tests + implementation

### Coverage Goals
- Maintain >80% coverage throughout
- 100% coverage for ContentSanitizer (security-critical)
- 100% coverage for TokenEstimator (accuracy-critical)

### Integration Testing
- Test progressive disclosure end-to-end (recall_index → recall_details)
- Test privacy tag stripping with various edge cases
- Test exit codes in hook commands

---

## Success Metrics

### Phase 1 Metrics
- ✅ Privacy tags stripped at ingestion (zero sensitive data stored)
- ✅ Progressive disclosure reduces initial context by ~10x
- ✅ New MCP tools: recall_index, recall_details
- ✅ Token estimation accurate within 20%

### Phase 2 Metrics
- ✅ Semantic shortcuts reduce query complexity
- ✅ Exit codes standardized for hooks
- ✅ 3 new shortcut MCP tools (decisions, conventions, architecture)

---

## Verification Plan

### After Phase 1

```bash
# Test privacy tag stripping
echo "Public <private>secret</private> text" > /tmp/test.txt
./exe/claude-memory ingest --source test --session test-1 --transcript /tmp/test.txt --db /tmp/test.sqlite3
# Verify "secret" not stored

# Test progressive disclosure
./exe/claude-memory recall "database" --limit 5
# Should see full results (no index format in CLI yet)

# Test MCP tools
./exe/claude-memory serve-mcp
# Send test requests for recall_index and recall_details
```

### After Phase 2

```bash
# Test semantic shortcuts via MCP
./exe/claude-memory serve-mcp
# Test memory.decisions, memory.conventions, memory.architecture

# Test exit codes
echo '{"subcommand":"ingest","session_id":"test"}' | ./exe/claude-memory hook ingest
echo $?  # Should be 1 (WARNING) for missing transcript
```

---

## Migration Path

### Week 1-2: Foundation (Phase 1)
- Days 1-3: Privacy tag system (HIGH priority)
- Days 4-7: Progressive disclosure (HIGH priority)

### Week 3-4: Enhancements (Phase 2)
- Days 8-10: Semantic shortcuts (MEDIUM priority)
- Day 11: Exit code strategy (MEDIUM priority)

### Week 5-6: Optional (Phase 3)
- Days 12-15: Token economics tracking (LOW, requires distiller)

---

## What We're NOT Doing (And Why)

### ❌ Chroma Vector Database
**Reason:** Adds Python dependency, embedding generation, sync overhead. SQLite FTS5 is sufficient.

### ❌ Background Worker Process
**Reason:** MCP stdio transport works well. No need for HTTP server, PID files, port management.

### ❌ Web Viewer UI
**Reason:** Significant effort (React, SSE, state management) for uncertain value. CLI is sufficient.

### ❌ Slim Orchestrator Pattern
**Reason:** ALREADY COMPLETE! Previous refactoring extracted all 16 commands.

---

## Architecture Advantages We're Preserving

### ✅ Dual-Database Architecture (Global + Project)
Better than claude-mem's single database with filtering.

### ✅ Fact-Based Knowledge Graph
Structured triples enable richer queries vs. observation blobs.

### ✅ Truth Maintenance System
Conflict resolution and supersession not present in claude-mem.

### ✅ Predicate Policies
Single-value vs multi-value predicates prevent false conflicts.

### ✅ Ruby Ecosystem
Simpler dependencies, easier install vs. Node.js + Python stack.

---

## Next Steps

1. **Review and approve this plan**
2. **Create feature branch:** `feature/claude-mem-adoption`
3. **Start Phase 1, Step 1.1:** Add ContentSanitizer for privacy tags
4. **Commit early, commit often:** Small, focused changes
5. **Review progress:** Weekly checkpoint after each phase

---

## Notes

- All features maintain backward compatibility
- Tests are updated/added with each change
- Code style follows Standard Ruby
- Frozen string literals maintained throughout
- Ruby 3.2+ idioms used where appropriate
- Privacy tag stripping is non-reversible by design (security-first)
- Progressive disclosure is optional (legacy recall tool still works)
