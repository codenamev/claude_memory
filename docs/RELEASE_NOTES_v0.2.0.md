# ClaudeMemory v0.2.0: Privacy, Performance, Polish

**Release Date:** January 22, 2026

We're excited to announce ClaudeMemory v0.2.0, a major feature release that brings privacy-first design, 10x performance improvements, and comprehensive polish to your Claude Code memory system.

## 🔒 Privacy & Security

**Privacy Tag System**

Exclude sensitive data from memory with simple tags:

```
You: "My API key is <private>sk-abc123</private>"
```

The key is **never stored** or indexed. Supported tags:
- `<private>` - Generic sensitive data
- `<no-memory>` - Explicit memory exclusion
- `<secret>` - Secrets and credentials

**Security Hardening**
- ReDoS protection with 100-tag limit per ingestion
- ContentSanitizer module with 100% test coverage
- Safe handling of malformed or nested tags

## ⚡ Token Economics & Performance

**Progressive Disclosure Pattern**

New two-phase query system reduces token usage by **10x**:

1. **`memory.recall_index`** - Lightweight preview (~50 tokens per fact)
   - Quick scan of relevant facts
   - Decide what needs details

2. **`memory.recall_details`** - Full provenance on demand
   - Complete fact details
   - Source quotes and relationships
   - Only when needed

**Example:**
```
Before: 2,500 tokens (5 facts × 500 tokens)
After:    250 tokens (5 facts × 50 tokens)
10x reduction!
```

**Query Optimization**
- N+1 query elimination (2N+1 → 3 queries)
- Batch loading for facts, provenance, and entities
- IndexQuery object for cleaner search logic
- TokenEstimator with 100% test coverage

## 🎯 Semantic Shortcuts

Pre-configured queries for common use cases:

- **`memory.decisions`** - Architectural decisions and accepted proposals
- **`memory.conventions`** - Global coding conventions and style preferences
- **`memory.architecture`** - Framework choices and architectural patterns

**Before:**
```ruby
memory.recall("decisions OR conventions OR choices OR patterns...")
```

**After:**
```ruby
memory.decisions  # Just works!
```

## 🛠️ Developer Experience

**Exit Code Strategy**

Standardized hook exit codes for robust integration:
```ruby
SUCCESS = 0  # Operation completed
WARNING = 1  # Completed with warnings (e.g., skipped ingestion)
ERROR   = 2  # Operation failed
```

**Testing & Quality**
- **157 new test examples** (426 → 583 total)
- 100% coverage for security-critical modules (ContentSanitizer)
- 100% coverage for accuracy-critical modules (TokenEstimator)
- Comprehensive hook exit code tests (13 test cases)

**Code Quality**
- PrivacyTag value object for type-safe tag handling
- QueryOptions parameter object for consistent APIs
- Empty query handling for FTS5 edge cases

## 📊 What's Included

### New MCP Tools
- `memory.recall_index` - Lightweight fact previews
- `memory.recall_details` - Full fact details on demand
- `memory.decisions` - Quick decision lookup
- `memory.conventions` - Convention lookup
- `memory.architecture` - Architecture lookup

### Enhanced Features
- Privacy tag support in all ingestion paths
- Token estimation for all query results
- Batch-optimized recall queries
- Comprehensive error handling

## 📦 Installation

### New Users
```bash
gem install claude_memory
claude-memory init --global
claude-memory doctor
```

### Existing Users
```bash
gem update claude_memory
```

**No migration needed** - all existing databases are compatible!

## 🔄 Upgrade Guide

### Breaking Changes
**None!** This release is fully backward compatible.

### Recommended Actions
1. Update the gem: `gem update claude_memory`
2. Review the [new examples](https://github.com/codenamev/claude_memory/blob/main/docs/EXAMPLES.md)
3. Start using privacy tags for sensitive data
4. Try semantic shortcuts (`memory.decisions`, `memory.conventions`)

## 📖 Documentation

- 📋 [Comprehensive Examples](https://github.com/codenamev/claude_memory/blob/main/docs/EXAMPLES.md) - 9 real-world scenarios
- 🔐 [Privacy Guide](https://github.com/codenamev/claude_memory/blob/main/docs/EXAMPLES.md#example-4-privacy-control)
- ⚡ [Performance Guide](https://github.com/codenamev/claude_memory/blob/main/docs/EXAMPLES.md#example-6-progressive-disclosure)
- 🏗️ [Architecture](https://github.com/codenamev/claude_memory/blob/main/docs/architecture.md)

## 🙏 Credits

Built with ❤️ by [Valentino Stoll](https://github.com/codenamev)

Special thanks to:
- Early adopters and testers
- Claude Code team for hooks and MCP support
- Ruby community for feedback and ideas

## 🚀 What's Next

### Planned for v0.3.0
- Vector embeddings for semantic search (optional)
- Multi-project memory sharing
- Memory export/import utilities
- Web dashboard for memory visualization

### Long-term Roadmap
- Team collaboration features
- Memory analytics and insights
- Plugin marketplace integration

## 🐛 Known Issues

None at this time! Please [report bugs](https://github.com/codenamev/claude_memory/issues) if you find any.

## 💬 Feedback & Support

- 🐛 [Report a bug](https://github.com/codenamev/claude_memory/issues)
- 💡 [Request a feature](https://github.com/codenamev/claude_memory/issues)
- 💬 [Join discussions](https://github.com/codenamev/claude_memory/discussions)
- 📧 Email: valentino@hanamirb.org

---

**Full Changelog:** [CHANGELOG.md](https://github.com/codenamev/claude_memory/blob/main/CHANGELOG.md)
