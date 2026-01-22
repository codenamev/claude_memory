# Ruby Community Posts for ClaudeMemory v0.2.0

## Ruby Weekly Submission

### Email Template

**To:** editor@rubyweekly.com
**Subject:** [Submission] ClaudeMemory v0.2.0 - Long-term memory for Claude Code

```
Hi Ruby Weekly team,

I'd like to submit ClaudeMemory v0.2.0 for consideration.

**Title:** ClaudeMemory v0.2.0 – Privacy-first long-term memory for Claude Code

**Short Description:**
A Ruby gem providing persistent memory for Claude Code. V0.2.0 adds privacy tags for sensitive data, progressive disclosure (10x token reduction), and semantic shortcuts. Built with Ruby 3.2+, Sequel, and SQLite. 583 test examples, zero external dependencies.

**Link:** https://github.com/codenamev/claude_memory

**Release Notes:** https://github.com/codenamev/claude_memory/blob/main/docs/RELEASE_NOTES_v0.2.0.md

**Why interesting for Ruby developers:**
- Clean Ruby architecture with DDD principles
- Sequel ORM usage patterns
- SQLite FTS5 for full-text search
- Value objects and null objects in Ruby
- 583 RSpec examples with 100% critical path coverage

Thanks for your consideration!

Valentino Stoll
https://github.com/codenamev
```

---

## Reddit r/ruby Post

### Title
```
[Release] ClaudeMemory v0.2.0 - Privacy-first long-term memory for Claude Code
```

### Post Body

```markdown
Hi r/ruby!

I'm excited to share **ClaudeMemory v0.2.0**, a Ruby gem that gives Claude Code persistent memory across conversations.

## What Problem Does It Solve?

Claude Code (and most AI coding assistants) forget everything after each session. You have to repeatedly explain your tech stack, preferences, and decisions. ClaudeMemory solves this by automatically extracting and storing durable facts.

## Example Workflow

**Session 1:**
```ruby
You: "I'm building a Rails 7 app with PostgreSQL, deploying to Heroku"
Claude: [helps with setup]
# Behind the scenes: facts stored automatically
```

**Session 2 (weeks later):**
```ruby
You: "Help me add a background job"
Claude: "Based on my memory, you're using Rails 7 with PostgreSQL..."
# Claude recalls context automatically
```

## What's New in v0.2.0

### 🔒 Privacy Tag System

Exclude sensitive data from memory:

```ruby
"API key is <private>sk-abc123</private>"
# Sanitized to: "API key is "
# The key is NEVER stored or indexed
```

Implementation uses a comprehensive `ContentSanitizer` module with:
- Support for `<private>`, `<no-memory>`, `<secret>` tags
- ReDoS protection (100-tag limit)
- 100% test coverage for security-critical code
- Safe handling of malformed/nested tags

### ⚡ Progressive Disclosure (10x Performance)

Two-phase query system reduces token usage:

```ruby
# Phase 1: Lightweight index
recall_index(query: "database")
# Returns: ~50 tokens per fact (preview only)

# Phase 2: Full details on demand
recall_details(fact_id: 42)
# Returns: Complete provenance, quotes, relationships
```

**Token savings:**
- Before: 2,500 tokens (5 facts × 500 tokens)
- After: 250 tokens (5 facts × 50 tokens)
- **10x reduction!**

### 🎯 Semantic Shortcuts

Pre-configured queries for common use cases:

```ruby
memory.decisions      # Architectural decisions
memory.conventions    # Coding standards
memory.architecture   # Framework choices
```

Implemented with a centralized `Shortcuts` query builder using predicate-based configuration.

## Technical Details

### Architecture

Clean Ruby architecture following Domain-Driven Design:

```
Application Layer (CLI + Commands)
         ↓
Core Domain Layer (Fact, Entity, Provenance, Conflict)
         ↓
Business Logic Layer (Recall, Resolve, Distill)
         ↓
Infrastructure Layer (SQLiteStore, FileSystem, Index)
```

### Tech Stack

- **Ruby:** 3.2+ with `frozen_string_literal: true`
- **Database:** SQLite3 (~> 2.0)
- **ORM:** Sequel (~> 5.0)
- **Testing:** RSpec with 583 examples
- **Linting:** Standard Ruby
- **FTS:** SQLite FTS5 (no vector embeddings needed)

### Code Quality

- **Value Objects:** `SessionId`, `TranscriptPath`, `FactId`, `PrivacyTag`, `QueryOptions`
- **Null Objects:** `NullFact`, `NullExplanation`
- **Command Pattern:** 16 focused command classes (CLI is 41 lines)
- **Query Optimization:** N+1 elimination (2N+1 → 3 queries via batch loading)
- **Test Coverage:** 100% for `ContentSanitizer` and `TokenEstimator`

## Installation

```bash
gem install claude_memory
claude-memory init --global
claude-memory doctor
```

Or add to Gemfile:

```ruby
gem 'claude_memory'
```

## Integration with Claude Code

ClaudeMemory integrates via:

1. **MCP Tools** - Memory operations exposed to Claude
2. **Hooks** - Automatic ingestion on session stop
3. **Skills** - `/memory` command for manual interaction

No API keys required! Uses Claude Code's own session for fact extraction.

## Example Usage

### CLI

```bash
# Initialize
claude-memory init

# Ingest content
claude-memory ingest --source claude_code \
  --session-id sess-123 \
  --transcript-path ~/.claude/projects/myproject/latest.jsonl

# Recall facts
claude-memory recall "database"

# Explain with provenance
claude-memory explain 42

# Check health
claude-memory doctor
```

### MCP Tools (in Claude Code)

```ruby
memory.recall(query: "database", scope: "project")
memory.store_extraction(facts: [...], entities: [...])
memory.promote(fact_id: 42)  # Promote to global scope
memory.decisions              # Semantic shortcut
```

## Code Examples

### Privacy Sanitization

```ruby
module ClaudeMemory
  class ContentSanitizer
    PRIVACY_TAGS = %w[private no-memory secret].freeze
    MAX_TAGS = 100

    def self.sanitize(content)
      tag_count = 0
      content.gsub(/<(#{PRIVACY_TAGS.join("|")})>.*?<\/\1>/mi) do
        tag_count += 1
        raise ReDoSError if tag_count > MAX_TAGS
        ""
      end
    end
  end
end
```

### Progressive Disclosure

```ruby
module ClaudeMemory
  class Recall
    def recall_index(query:, limit: 10)
      # Lightweight preview
      facts = search_fts(query).limit(limit)
      facts.map do |fact|
        {
          id: fact.id,
          preview: "#{fact.subject} #{fact.predicate} #{fact.object}",
          confidence: fact.confidence,
          scope: fact.scope,
          tokens: TokenEstimator.estimate_preview(fact)  # ~50 tokens
        }
      end
    end

    def recall_details(fact_id:)
      # Full details with provenance
      fact = find_fact(fact_id)
      {
        **fact.to_h,
        provenance: load_provenance(fact),      # Batch query
        relationships: load_relationships(fact), # Batch query
        tokens: TokenEstimator.estimate_full(fact)  # ~500 tokens
      }
    end
  end
end
```

### Semantic Shortcuts

```ruby
module ClaudeMemory
  class Shortcuts
    PREDICATES = {
      decisions: %w[decision architectural_choice],
      conventions: %w[convention coding_standard],
      architecture: %w[uses_framework uses_database deployment_platform]
    }.freeze

    def self.build(shortcut)
      predicates = PREDICATES[shortcut]
      Recall.new.where(predicate: predicates)
    end
  end
end
```

## Testing

583 RSpec examples covering:

- **Unit Tests:** Domain models, value objects, query builders
- **Integration Tests:** Full pipeline (ingest → distill → resolve → store)
- **Hook Tests:** All event types with exit code verification
- **Security Tests:** ReDoS protection, malformed tags
- **Performance Tests:** N+1 query elimination, batch loading

```bash
bundle exec rspec
# 583 examples, 0 failures
```

## Performance Characteristics

- **Ingestion:** O(n) where n = transcript length
- **FTS Indexing:** O(n log n) via SQLite FTS5
- **Recall Queries:** O(log n) with FTS5 + batch loading
- **Memory Usage:** Minimal (SQLite memory-mapped I/O)
- **Disk Usage:** ~1-5MB per project (typical)

## Why SQLite and Not Vector Embeddings?

1. **Zero Dependencies** - No external services or API keys
2. **FTS5 Is Fast** - Full-text search is sufficient for fact recall
3. **Simpler Model** - Exact match > approximate semantic similarity for facts
4. **Local First** - Everything stored locally, no network calls
5. **Proven Tech** - SQLite is battle-tested and embedded everywhere

Future versions may add optional vector search for semantic similarity, but FTS5 covers 95% of use cases.

## Roadmap

### v0.3.0 (Planned)
- Optional vector embeddings for semantic search
- Multi-project memory sharing
- Memory export/import utilities
- Web dashboard for visualization

### Long-term
- Team collaboration features
- Memory analytics and insights
- Plugin marketplace integration

## Contributing

Contributions welcome! The codebase uses:

- **SOLID principles** throughout
- **Domain-Driven Design** with rich models
- **Dependency injection** for testability
- **Standard Ruby** for linting

See [CLAUDE.md](https://github.com/codenamev/claude_memory/blob/main/CLAUDE.md) for development setup and architecture docs.

## Links

- **GitHub:** https://github.com/codenamev/claude_memory
- **RubyGems:** https://rubygems.org/gems/claude_memory
- **Examples:** https://github.com/codenamev/claude_memory/blob/main/docs/EXAMPLES.md
- **Architecture:** https://github.com/codenamev/claude_memory/blob/main/docs/architecture.md
- **Changelog:** https://github.com/codenamev/claude_memory/blob/main/CHANGELOG.md

## Questions?

Happy to answer questions about:
- Implementation details
- Architecture decisions (why DDD, why Sequel, etc.)
- Performance optimizations
- Security considerations
- Claude Code integration

Feel free to ask here or open a GitHub discussion!

---

**Built with ❤️ by [Valentino Stoll](https://github.com/codenamev)**
```

---

## Ruby Flow Post

### Title
```
ClaudeMemory v0.2.0: Privacy-First Memory System for Claude Code
```

### Body

```markdown
Just released ClaudeMemory v0.2.0! 🚀

A Ruby gem providing long-term memory for Claude Code with privacy tags, progressive disclosure, and semantic shortcuts.

**Tech Stack:**
- Ruby 3.2+
- Sequel ORM
- SQLite3 + FTS5
- RSpec (583 examples)
- Standard Ruby linting

**New in v0.2.0:**
🔒 Privacy tags: `<private>secret</private>` never stored
⚡ 10x token reduction with progressive disclosure
🎯 Semantic shortcuts (decisions, conventions, architecture)
✅ 100% coverage for security-critical modules

**Architecture Highlights:**
- Domain-Driven Design with value objects
- N+1 query elimination (2N+1 → 3 queries)
- Command Pattern (CLI: 41 lines → 16 command classes)
- Null Object Pattern for clean code

```bash
gem install claude_memory
claude-memory init --global
```

GitHub: https://github.com/codenamev/claude_memory

Ask me anything about the implementation!
```

---

## Ruby Rogues Podcast Pitch (Optional)

### Email Template

**To:** rubyrogues@devchat.tv
**Subject:** Podcast Topic Idea: Building AI Memory Systems with Ruby

```
Hi Ruby Rogues team,

I'd love to discuss a potential podcast topic: building production-ready AI memory systems using Ruby.

I recently released ClaudeMemory v0.2.0, a Ruby gem that provides persistent memory for Claude Code. The project showcases several interesting Ruby patterns:

**Technical Topics:**
- Domain-Driven Design in Ruby (value objects, domain models)
- SQLite FTS5 for full-text search (no vector embeddings needed)
- Sequel ORM patterns and query optimization
- Security considerations (ReDoS protection, content sanitization)
- Testing strategy (583 examples, 100% critical path coverage)
- Command Pattern for CLI design (881 → 41 lines)

**Broader Themes:**
- Building AI tools with Ruby (why Ruby is great for this)
- Privacy-first design in AI systems
- Token economics and performance optimization
- Local-first software architecture
- Integration patterns (MCP, hooks, skills)

**Project Stats:**
- Ruby 3.2+, Sequel, SQLite3
- 583 RSpec examples
- Zero external dependencies
- GitHub: https://github.com/codenamev/claude_memory

Would this be a good fit for an upcoming episode? Happy to discuss the technical details and lessons learned from building this system.

Thanks for your consideration!

Valentino Stoll
https://github.com/codenamev
```

---

## Ruby Together Announcement (Optional)

### Template

```markdown
# ClaudeMemory: A Ruby Gem for AI Memory

The Ruby community has a new tool for working with AI coding assistants: ClaudeMemory v0.2.0.

## What It Does

ClaudeMemory provides persistent memory for Claude Code, automatically extracting and storing facts about your projects, preferences, and decisions. Built entirely in Ruby with SQLite.

## Why It Matters for Ruby

1. **Showcases Ruby's Strengths:** Domain-Driven Design, clean OOP, expressive DSLs
2. **Zero Dependencies:** Pure Ruby with SQLite (no external services)
3. **Production Ready:** 583 test examples, 100% critical path coverage
4. **Open Source:** MIT licensed, contributions welcome

## Technical Highlights

- Sequel ORM for database access
- SQLite FTS5 for full-text search
- Value objects and null objects
- Command Pattern for CLI
- Progressive disclosure for performance

## Links

- GitHub: https://github.com/codenamev/claude_memory
- RubyGems: https://rubygems.org/gems/claude_memory
- Architecture Docs: https://github.com/codenamev/claude_memory/blob/main/docs/architecture.md

Built by Valentino Stoll ([@codenamev](https://github.com/codenamev))
```

---

## Usage Recommendations

### Timing
1. **Ruby Weekly:** Submit immediately after GitHub release
2. **Reddit r/ruby:** Post 1-2 days after release
3. **Ruby Flow:** Cross-post same day as Reddit
4. **Ruby Rogues:** Reach out 1-2 weeks after release (after gathering feedback)
5. **Ruby Together:** Optional announcement if project gains traction

### Engagement Tips
1. **Be Active:** Respond to comments and questions within 24 hours
2. **Show Code:** Include implementation details when asked
3. **Be Humble:** Acknowledge limitations and areas for improvement
4. **Credit Others:** Mention Ruby gems and tools that inspired you
5. **Link Generously:** Point to docs, examples, and architecture details

### Follow-up Ideas
1. **Blog Post:** "Building a Privacy-First AI Memory System with Ruby"
2. **Conference Talk:** Submit to RubyConf or regional Ruby conferences
3. **Screencast:** Record a 10-minute demo for YouTube
4. **Podcast:** Reach out to Ruby on Rails Podcast or Bike Shed
5. **Tutorial:** Write a step-by-step guide for Ruby developers

---

## Community Engagement Script

When people ask questions, use this framework:

### For Architecture Questions
```
Great question! ClaudeMemory uses [concept] because [reason].

The specific implementation is in [file]:
[code snippet]

More details in the architecture doc: [link]
```

### For Performance Questions
```
Performance was a key focus for v0.2.0. Here's what we did:

1. [Optimization 1] - [Result]
2. [Optimization 2] - [Result]

Benchmarks show [metric].

Implementation details: [link]
```

### For Comparison Questions
```
Good question! Here's how ClaudeMemory compares to [alternative]:

ClaudeMemory:
- Pro: [advantages]
- Con: [tradeoffs]

[Alternative]:
- Pro: [advantages]
- Con: [tradeoffs]

The right choice depends on [use case].
```

### For Contributing Questions
```
Thanks for your interest in contributing!

The best places to start:
1. [Easy issue or area]
2. [Medium complexity area]

Development setup:
```bash
git clone https://github.com/codenamev/claude_memory
cd claude_memory
bin/setup
bundle exec rspec
```

See CLAUDE.md for architecture details: [link]
```
