# Claude Memory Demo

This document walks through a complete end-to-end demo of ClaudeMemory.

## Setup

```bash
# Install the gem
gem install claude_memory

# Initialize in your project
cd your-project
claude-memory init
```

## Ingest Some Content

Create a sample transcript:

```bash
echo '{"type":"message","content":"We decided to use PostgreSQL for the database."}
{"type":"message","content":"Convention: Always use snake_case for variable names."}
{"type":"message","content":"We are deploying to AWS using Terraform."}' > /tmp/demo_transcript.jsonl
```

Ingest it:

```bash
claude-memory ingest \
  --source claude_code \
  --session-id demo-session \
  --transcript-path /tmp/demo_transcript.jsonl
```

## Distill and Resolve Facts

The distiller extracts structured facts from raw content:

```bash
# Search the indexed content
claude-memory search "PostgreSQL"

# Check for conflicts
claude-memory conflicts
```

## Recall Facts

Query the memory:

```bash
# Recall facts about databases
claude-memory recall "database"

# Explain a specific fact
claude-memory explain 1
```

## Publish Snapshot

Generate a snapshot for Claude Code:

```bash
claude-memory publish

# Check the generated file
cat .claude/rules/claude_memory.generated.md
```

## Maintenance

Run periodic maintenance:

```bash
# Run sweep with 5-second budget
claude-memory sweep --budget 5

# Check system status via MCP
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"memory.status","arguments":{}}}' | \
  claude-memory serve-mcp
```

## Verify Setup

```bash
claude-memory doctor
```

## Full Loop with Claude Code

1. Configure hooks (from `claude-memory init` output)
2. Configure MCP server
3. Start using Claude Code normally
4. Hooks automatically ingest transcripts
5. Use MCP tools like `memory.recall` in your prompts
6. Run `claude-memory publish` periodically to update snapshot

## Example: Detecting Conflicts

```bash
# First statement
echo '{"type":"message","content":"We use MySQL for the database."}' > /tmp/t1.jsonl
claude-memory ingest --source claude_code --session-id s1 --transcript-path /tmp/t1.jsonl

# Contradicting statement without supersession
echo '{"type":"message","content":"We use PostgreSQL for the database."}' > /tmp/t2.jsonl
claude-memory ingest --source claude_code --session-id s2 --transcript-path /tmp/t2.jsonl

# This would create a conflict (requires distill+resolve which needs LLM in full version)
claude-memory conflicts
```

## Example: Supersession

```bash
# Original decision
echo '{"type":"message","content":"We decided to use MySQL."}' > /tmp/t1.jsonl
claude-memory ingest --source claude_code --session-id s1 --transcript-path /tmp/t1.jsonl

# Superseding decision with explicit signal
echo '{"type":"message","content":"We no longer use MySQL, switching to PostgreSQL."}' > /tmp/t2.jsonl
claude-memory ingest --source claude_code --session-id s2 --transcript-path /tmp/t2.jsonl

# Check recent changes
claude-memory changes --since 2024-01-01
```
