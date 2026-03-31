# Episodic Memory Analysis

*Analysis Date: 2026-03-02*
*Repository: https://github.com/obra/episodic-memory*
*Version: 1.0.15 (commit 6feaa5b)*
*Re-studied: 2026-03-30 — No changes since v1.0.15. Repo dormant. One adoptable pattern identified: CLAUDE_CONFIG_DIR env var support (`src/paths.ts:20-22`) for configurable Claude config directory. Orphaned MCP process prevention (SIGHUP handler in wrapper) not applicable — ClaudeMemory runs as single Ruby process, no wrapper/child architecture.*

---

## Executive Summary

### Project Purpose

Episodic Memory provides semantic search for Claude Code conversations. It indexes past sessions and makes them searchable via natural language, enabling Claude to remember decisions, patterns, and context across sessions.

### Key Innovation

**Conversation-level semantic search with local embeddings.** Rather than extracting structured facts, episodic-memory preserves raw conversation exchanges (user/assistant pairs) and makes them searchable via Transformers.js embeddings — all local, no API calls for search. Uses Claude Agent SDK for optional summarization.

### Technology Stack

| Component | Technology |
|-----------|-----------|
| **Language** | TypeScript (ESM) |
| **Database** | better-sqlite3 + sqlite-vec v0.1.7-alpha.2 |
| **Embeddings** | @xenova/transformers (all-MiniLM-L6-v2, local ONNX) |
| **Summarization** | @anthropic-ai/claude-agent-sdk (Haiku default) |
| **MCP** | @modelcontextprotocol/sdk v1.20.0 |
| **Validation** | Zod v3 |
| **Build** | tsc + esbuild |
| **Testing** | vitest |
| **Plugin** | Claude Code marketplace format |

### Production Readiness

- **Maturity**: Stable (v1.0.15), actively maintained
- **Test Coverage**: vitest suite (api-config, parser, db, sync, search, etc.)
- **Plugin Distribution**: Claude Code marketplace
- **Author**: Jesse Vincent (obra) — well-known Ruby/Perl community figure
- **Offline**: Full local operation (embeddings + search), summarization optional

---

## Architecture Overview

### Data Model

```
~/.claude/projects/ (raw conversation JSONL files)
    ↓ sync/copy
~/.episodic-memory/archive/ (archived copies)
    ↓ parse
exchanges table (id, project, timestamp, user_message, assistant_message, archive_path, line_start, line_end)
    ↓ embed
vec_exchanges (sqlite-vec virtual table, vector similarity)
    ↓ summarize (optional)
summaries (Claude-generated conversation summaries)
```

Key schema features (`src/db.ts:57-79`):
- Session metadata: `session_id`, `cwd`, `git_branch`, `claude_version`
- Thinking metadata: `thinking_level`, `thinking_disabled`, `thinking_triggers`
- Parent tracking: `parent_uuid`, `is_sidechain` for conversation branching

### Design Patterns

1. **Exchange-Level Granularity** (`src/indexer.ts:40-100`): Each user/assistant pair is a searchable unit. Embeddings combine both messages for context.

2. **Local-First Embeddings** (`src/embeddings.ts:1-46`): Xenova/transformers.js with all-MiniLM-L6-v2 — no API calls, no API keys, works offline. 384-dim vectors, 512-token max.

3. **Delta Sync** (`src/indexer.ts:64-89`): Only copies new/modified files from `~/.claude/projects` to archive. Idempotent and safe for concurrent execution.

4. **Multi-Concept AND Search** (`src/search.ts:27-100`): Supports both single-query and multi-concept array queries. Vector and text modes combinable.

5. **Exclusion Markers**: `<INSTRUCTIONS-TO-EPISODIC-MEMORY>DO NOT INDEX THIS CHAT</INSTRUCTIONS-TO-EPISODIC-MEMORY>` for sensitive conversations.

### Comparison with ClaudeMemory

| Aspect | Episodic Memory | ClaudeMemory | Notes |
|--------|----------------|--------------|-------|
| **Data Model** | Raw conversation exchanges | Distilled facts with provenance | Different philosophy |
| **Storage** | better-sqlite3 + sqlite-vec | Sequel + Extralite | Both use SQLite |
| **Embeddings** | @xenova/transformers (local) | fastembed-rb (local) | Both local ONNX |
| **Vector Search** | sqlite-vec (native) | JSON embeddings (O(n)) | They're faster |
| **Summarization** | Claude Agent SDK (optional) | Distiller pipeline | We extract structured facts |
| **Scope** | Per-conversation exchanges | Per-fact with project/global scope | We're more granular |
| **MCP Tools** | search, show | 18 tools | We're more comprehensive |
| **Plugin** | marketplace.json | Ruby gem | They're easier to install |

---

## Key Components Deep-Dive

### Component 1: Local Embedding Pipeline

**Purpose**: Generate vector embeddings without external APIs.

**Location**: `src/embeddings.ts:1-46`

```typescript
// From src/embeddings.ts:8-13
embeddingPipeline = await pipeline(
  'feature-extraction',
  'Xenova/all-MiniLM-L6-v2'
);
```

**Design Decisions**:
- all-MiniLM-L6-v2: 384 dimensions, fast, good quality for conversation search
- Combined user+assistant+tools for richer embeddings (`embeddings.ts:32-45`)
- 2000 character truncation (512 token model limit)

### Component 2: Conversation Sync

**Purpose**: Copy and archive conversations from Claude Code's project directory.

**Location**: `src/indexer.ts:40-100`

**Design Decisions**:
- Copies to `~/.episodic-memory/archive/` for persistence
- Batch processing with configurable concurrency
- Exclude projects via config
- Optional no-summaries mode for faster indexing

### Component 3: Multi-Concept Search

**Purpose**: Find conversations matching ALL of multiple concepts.

**Location**: `src/search.ts:27-100`, `src/mcp-server.ts:31-68`

**Design Decisions**:
- Array query triggers multi-concept AND search
- Single string triggers standard search
- Modes: vector, text, both
- Date range filtering (after/before)
- Line-range addressing for conversation excerpts

---

## Comparative Analysis

### What They Do Well

1. **Local Embeddings**: Xenova/transformers.js works offline with zero configuration
2. **sqlite-vec Integration**: Native vector search in SQLite
3. **Plugin Distribution**: Single `/plugin install` command
4. **Conversation Preservation**: Keeps raw context, not just extracted facts
5. **Multi-Concept AND Search**: Powerful for finding intersections

### What We Do Well

1. **Knowledge Distillation**: Facts with provenance > raw transcripts
2. **Truth Maintenance**: Supersession and conflict resolution
3. **Dual-Database System**: Project/global scope separation
4. **Comprehensive MCP Tools**: 18 tools vs 2
5. **Rich Metadata**: Temporal validity, predicate policies, fact links

---

## Adoption Opportunities

### High Priority ⭐

#### 1. sqlite-vec for Vector Search (Reinforces QMD Finding)
- **Value**: Native vector search, eliminates O(n) Ruby similarity
- **Evidence**: `src/db.ts:5,51` — single `sqliteVec.load(db)` call with better-sqlite3
- **Implementation**: Same as QMD recommendation — add sqlite-vec extension
- **Effort**: 3-5 days
- **Trade-off**: Native dependency
- **Recommendation**: **ADOPT** — Both QMD and episodic-memory validate sqlite-vec

#### 2. Multi-Concept AND Search
- **Value**: Find facts matching ALL of multiple concepts (intersection queries)
- **Evidence**: `src/mcp-server.ts:31-40` — array query for multi-concept search
- **Implementation**: Already partially implemented as `memory.search_concepts`
- **Effort**: 1 day (verify existing implementation covers this)
- **Trade-off**: None
- **Recommendation**: **ADOPT** — Validate our existing implementation matches their pattern

#### 3. Conversation Exclusion Markers
- **Value**: Let users exclude sensitive sessions from indexing
- **Evidence**: README:236-251 — `<INSTRUCTIONS-TO-EPISODIC-MEMORY>DO NOT INDEX</INSTRUCTIONS-TO-EPISODIC-MEMORY>`
- **Implementation**: Honor `<no-memory>` or similar tags during ingest
- **Effort**: 0.5 days
- **Trade-off**: None
- **Recommendation**: **ADOPT** — We already strip `<no-memory>` tags, but should skip entire sessions containing them

### Medium Priority

#### 4. Exchange-Level Embedding
- **Value**: Combined user+assistant+tool embeddings capture richer context
- **Evidence**: `src/embeddings.ts:32-45` — combines user, assistant, and tool names
- **Implementation**: Include tool context in fact embeddings during distillation
- **Effort**: 1 day
- **Trade-off**: Slightly larger embeddings
- **Recommendation**: **CONSIDER**

### Features to Avoid

- **Raw Conversation Storage**: We distill into structured facts — keeping raw exchanges would bloat storage
- **Claude Agent SDK for Summarization**: We use direct API calls via anthropic-rb gem
- **all-MiniLM-L6-v2 Model**: Our bge-small-en-v1.5 is better for fact-style content (384-dim vs 384-dim, but better benchmarks)

---

## Key Takeaways

### Main Learnings
1. sqlite-vec is becoming standard — used by QMD, episodic-memory, and others
2. Multi-concept AND search is valuable for intersecting knowledge domains
3. Local-first embeddings (no API) is the right approach — we already do this
4. Conversation exclusion markers provide important privacy control

---

*Analysis completed: 2026-03-02*
*Analyst: Claude Code*
*Review Status: Draft*
