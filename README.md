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

### 3. Analyze Your Project

Run the analyze command to bootstrap memory with your project's tech stack:

```
/claude-memory:analyze
```

This reads your project files (Gemfile, package.json, etc.) and stores facts about languages, frameworks, tools, and conventions.

### 4. Verify Setup
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
- **Privacy First**: `<private>` tags exclude sensitive data
- **Progressive Disclosure**: Lightweight queries before full details
- **Semantic Shortcuts**: Quick access to decisions, conventions, architecture
- **Truth Maintenance**: Automatic conflict resolution
- **Claude-Powered**: Uses Claude's intelligence to extract facts (no API key needed)
- **Token Efficient**: 10x reduction in memory queries with progressive disclosure

## Privacy Control

Exclude sensitive data from memory using privacy tags:

```
You: "My API key is <private>sk-abc123</private>"
Claude: [uses it during session]

# Stored: "API endpoint configured with key"
# NOT stored: "sk-abc123"
```

Supported tags: `<private>`, `<no-memory>`, `<secret>`

## Documentation

- 📖 [Getting Started](docs/GETTING_STARTED.md) - Step-by-step onboarding *(coming soon)*
- 💡 [Examples](docs/EXAMPLES.md) - Use cases and workflows
- 🔧 [Plugin Setup](docs/PLUGIN.md) - Claude Code integration
- 🏗️ [Architecture](docs/architecture.md) - Technical deep dive
- 📝 [Changelog](CHANGELOG.md) - Release notes

## For Developers

- **Language:** Ruby 3.2+
- **Storage:** SQLite3 (no external services)
- **Testing:** 583 examples, 100% core coverage
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
