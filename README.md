# ClaudeMemory

**Long-term memory for Claude Code** - automatic, intelligent, zero-configuration

[![Gem Version](https://badge.fury.io/rb/claude_memory.svg)](https://badge.fury.io/rb/claude_memory)

## What It Does

ClaudeMemory gives Claude Code a persistent memory across all your conversations.
It automatically:
- ✅ Extracts durable facts from conversations (tech stack, preferences, decisions)
- ✅ Remembers project-specific and global knowledge
- ✅ Provides instant recall without manual prompting
- ✅ Maintains truth (handles conflicts, supersession)

**No API keys. No configuration. Just works.**

## Quick Start

### 1. Install the Gem
```bash
gem install claude_memory
```

### 2. Install the Plugin

From within Claude Code, add the marketplace and install the plugin:

```bash
# Add the marketplace (one-time setup)
/plugin marketplace add codenamev/claude_memory

# Install the plugin
/plugin install claude-memory
```

### 3. Initialize Memory

Initialize both global and project-specific memory:

```bash
claude-memory init
```

This creates:
- **Global database** (`~/.claude/memory.sqlite3`) - User-wide preferences
- **Project database** (`.claude/memory.sqlite3`) - Project-specific knowledge

### 4. Analyze Your Project (Optional)

Bootstrap memory with your project's tech stack:

```
/claude-memory:analyze
```

This reads your project files (Gemfile, package.json, etc.) and stores facts about languages, frameworks, tools, and conventions.

### 5. Verify Setup
```bash
claude-memory doctor
```

### Use with Claude Code
Just talk naturally! Memory happens automatically.

```
You: "I'm building a Rails app with PostgreSQL, deploying to Heroku"
Claude: [helps with setup]

# Behind the scenes:
# - Session transcript ingested
# - Facts extracted automatically
# - No user action needed
```

**Later:**
```
You: "Help me add a background job"
Claude: "Based on my memory, you're using Rails with PostgreSQL..."
```

👉 **[See Getting Started Guide →](docs/GETTING_STARTED.md)**
👉 **[View Example Conversations →](docs/EXAMPLES.md)**

## How It Works

1. **You chat with Claude** - Tell it about your project
2. **Facts are extracted** - Claude identifies durable knowledge
3. **Memory persists** - Stored locally in SQLite
4. **Automatic recall** - Claude remembers in future conversations

👉 **[Architecture Deep Dive →](docs/architecture.md)**

## Key Features

- **Dual Scope**: Project-specific + global user preferences
- **Hybrid Search**: FTS5 full-text + semantic vector search with Reciprocal Rank Fusion
- **Native Vector Storage**: [sqlite-vec](https://github.com/asg017/sqlite-vec) for fast KNN search with local embeddings ([fastembed-rb](https://github.com/khasinski/fastembed-rb), no API key)
- **Session Context**: Automatic context injection at session start with recent facts
- **Privacy First**: `<private>` tags exclude sensitive data
- **Progressive Disclosure**: Lightweight queries before full details
- **Semantic Shortcuts**: Quick access to decisions, conventions, architecture
- **Truth Maintenance**: Automatic conflict resolution
- **Claude-Powered**: Uses Claude's intelligence to extract facts (no API key needed)
- **Token Efficient**: 10x reduction in memory queries with progressive disclosure
- **Database Maintenance**: Compact, export, and backup commands

## Privacy Control

Exclude sensitive data from memory using privacy tags:

```
You: "My API key is <private>sk-abc123</private>"
Claude: [uses it during session]

# Stored: "API endpoint configured with key"
# NOT stored: "sk-abc123"
```

Supported tags: `<private>`, `<no-memory>`, `<secret>`

## Upgrading

Existing users can upgrade seamlessly:

```bash
gem update claude_memory
```

All database migrations happen automatically. Run `claude-memory doctor` to verify.

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

## Troubleshooting

### Check Setup Status

If memory tools aren't working, check initialization status:

```
memory.check_setup
```

This returns:
- Initialization status (healthy, needs_upgrade, not_initialized)
- Version information
- Missing components
- Actionable recommendations

### Installation Help

Need help getting started? Run:

```
/setup-memory
```

This skill provides:
- Step-by-step installation instructions
- Common error solutions
- Post-installation verification
- Upgrade guidance

### Health Check

Verify your ClaudeMemory installation:

```bash
claude-memory doctor
```

This checks:
- Database existence and integrity
- Schema version compatibility
- sqlite-vec availability and index coverage
- Hooks configuration
- Snapshot status
- Stuck operations

### Uninstalling

To remove ClaudeMemory configuration:

```bash
# Remove hooks and MCP configuration (keeps databases)
claude-memory uninstall

# Remove everything including databases
claude-memory uninstall --full

# For global uninstall
claude-memory uninstall --global
claude-memory uninstall --global --full
```

The uninstall command removes:
- Hooks from `.claude/settings.json`
- MCP server from `.claude.json`
- ClaudeMemory section from `CLAUDE.md`
- Databases and generated files (with `--full`)

**Note:** The `doctor` command will warn you if orphaned hooks are detected (hooks configured but MCP plugin removed). Run `claude-memory uninstall` to clean them up.

## Documentation

- 📖 [Getting Started](docs/GETTING_STARTED.md) - Step-by-step onboarding
- 💡 [Examples](docs/EXAMPLES.md) - Use cases and workflows
- 🔧 [Plugin Setup](docs/PLUGIN.md) - Claude Code integration
- 🏗️ [Architecture](docs/architecture.md) - Technical deep dive
- 📝 [Changelog](CHANGELOG.md) - Release notes

## Benchmarks

ClaudeMemory includes **DevMemBench**, a developer-domain benchmark suite that measures retrieval quality and truth maintenance accuracy. All offline benchmarks run locally at zero cost.

### Latest Results

| Benchmark | Metric | Score |
|-----------|--------|-------|
| **Truth Maintenance** | Accuracy (100 cases) | **100%** |
| **FTS5 Retrieval** | Recall@5 (40 easy queries) | **97.5%** |
| **Semantic Retrieval** | Recall@5 (85 queries aggregate) | **78.6%** |
| **Semantic Retrieval** | Recall@5 (40 medium queries) | **69.6%** |
| **Hybrid Retrieval** | Recall@5 (100 queries aggregate) | **72.7%** |
| **Hybrid Retrieval** | Recall@10 (20 hard queries) | **62.8%** |
| **Scope Ranking** | Queries returning expected facts | **5/5** |

Semantic and hybrid retrieval use [fastembed-rb](https://github.com/khasinski/fastembed-rb) with the BAAI/bge-small-en-v1.5 model (384-dim, runs locally, no API key needed).

### What the benchmarks measure

**Retrieval accuracy** -- Given a database of ~105 developer-domain facts across 5 simulated projects, how well does search find the right facts? Measured with standard IR metrics (Recall@k, MRR, nDCG@10) across 155 queries at varying difficulty levels (exact keyword match, semantic paraphrase, cross-category synthesis, abstention, temporal).

**Truth maintenance** -- Given pairs of existing and incoming facts, does the resolver correctly determine the outcome? 100 FEVER-inspired cases test four outcomes: supersession (new stated fact replaces old), conflict (inferred fact contradicts stated), accumulation (multi-value predicates coexist), and corroboration (same fact adds provenance).

**End-to-end with Claude** -- 31 scenarios across 5 LongMemEval ability categories (information extraction, multi-session reasoning, temporal reasoning, knowledge updates, abstention). Requires `EVAL_MODE=real` and costs ~$2-8 per run.

### Running benchmarks

```bash
# Offline benchmarks ($0, ~8 seconds)
bundle exec rspec spec/benchmarks/ --tag benchmark --format documentation

# Full evals + benchmarks
./bin/run-evals --all

# End-to-end with real Claude (~$2-8)
EVAL_MODE=real bundle exec rspec spec/benchmarks/e2e/ --tag eval_real
```

The benchmark dataset draws from real CLAUDE.md patterns and is designed specifically for ClaudeMemory's 6 predicates and 8 entity types. Open IR datasets (BEIR, FEVER, LongMemEval) informed the methodology but don't cover developer-domain knowledge.

👉 **[Benchmark Details →](spec/benchmarks/README.md)**

## For Developers

- **Language:** Ruby 3.2+
- **Storage:** SQLite3 (no external services)
- **Testing:** 1477 examples (1375 unit/integration + 102 benchmarks/evals), 100% core coverage
- **Code Style:** Standard Ruby

```bash
git clone https://github.com/codenamev/claude_memory
cd claude_memory
bin/setup
bundle exec rspec
```

👉 **[Development Guide →](CLAUDE.md)**

## Support

- 🐛 [Report a bug](https://github.com/codenamev/claude_memory/issues)
- 💬 [Discussions](https://github.com/codenamev/claude_memory/discussions)

## License

MIT - see [LICENSE.txt](LICENSE.txt)

---

**Made with ❤️ by [Valentino Stoll](https://github.com/codenamev)**
