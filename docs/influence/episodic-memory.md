# Episodic Memory Analysis

*Analysis Date: 2026-03-02*
*Repository: https://github.com/obra/episodic-memory*
*Version: 1.0.15 (commit 6feaa5b)*
*Re-studied: 2026-03-30 — No changes since v1.0.15. Repo dormant. One adoptable pattern identified: CLAUDE_CONFIG_DIR env var support (`src/paths.ts:20-22`) for configurable Claude config directory. Orphaned MCP process prevention (SIGHUP handler in wrapper) not applicable — ClaudeMemory runs as single Ruby process, no wrapper/child architecture.*

*Re-studied: 2026-06-30 — v1.4.2 (commit 1075769). **Active again** — 8 releases since baseline (1.1.0 → 1.4.2). Highlights below.*

---

## Re-study 2026-06-30 (v1.0.15 → v1.4.2)

The repo went from dormant to actively maintained, shipping 8 releases between 2026-05-02 and 2026-05-21. The work clustered into four themes: an embedding-model upgrade with background migration, Codex cross-harness support, hardening of the auto-sync/summarizer pipeline against process explosion and queue poisoning, and version-drift tooling.

### NEW adoptable — High priority

#### A. Background, resumable embedding-model migration (v1.2.0)
- **What**: When they upgraded the encoder from all-MiniLM-L6-v2 to bge-small-en-v1.5, existing indexes kept working against a *mixed* set of old/new embeddings while a background job re-embedded stale rows in bounded batches (default 500/sync, `EPISODIC_MEMORY_MIGRATION_BATCH`). An `EMBEDDING_VERSION` integer is stamped per row; `pickStaleBatch` selects `WHERE embedding_version < EMBEDDING_VERSION`; `recordReembedded` atomically swaps the vector + bumps the version; crash mid-batch just leaves rows tagged for the next run. Lock-protected so concurrent syncs don't double-embed.
- **Evidence**: `src/embedding-migration.ts:19-89` (EMBEDDING_VERSION, pickStaleBatch, recordReembedded, countStale), `src/sync-cli.ts:152-172` (per-sync batch driver), CHANGELOG 1.2.0.
- **Why it matters to us**: ClaudeMemory has pluggable embedding providers (tfidf/fastembed/api) and `Embeddings::DimensionCheck`, but DimensionCheck only *detects* a mismatch — there's no graceful, online re-embed path. Today a provider/model switch means stale or unusable vectors until a full rebuild. Their pattern (per-row `embedding_version` column + bounded re-embed batch wired into the existing Sweep/hook maintenance, no extra API cost) maps cleanly onto our PreCompact/SessionEnd sweep and our "no separate API call" convention (fastembed is local).
- **Effort**: 2-3 days (add `embedding_version` to the vec store, a `Sweep` step that re-embeds N stale rows per run, bump-on-pipeline-change constant).

#### B. Version-drift test + one-command bump script (v1.1.1)
- **What**: `package.json` is the single source of truth; `src/version.ts` is generated from it; a `test/version-consistency.test.ts` asserts plugin.json + marketplace.json all equal it (CI fails on drift); `scripts/bump-version.sh X.Y.Z` rewrites every declared file (driven by `.version-bump.json`) and `--audit` greps the repo for stray version strings.
- **Evidence**: `test/version-consistency.test.ts:1-40`, `scripts/bump-version.sh`, `.version-bump.json`, CHANGELOG 1.1.1.
- **Why it matters to us**: We have this *exact* problem documented as a manual chore/gotcha — "Version must be updated in three places: version.rb, plugin.json, marketplace.json." We bump them by hand and rely on the release skill. A drift spec (assert plugin.json/marketplace.json == `ClaudeMemory::VERSION`) is a ~20-line RSpec test that turns a known footgun into a CI failure. The bump-script is optional gravy; the spec is the high-value, low-effort win.
- **Effort**: 0.5 day for the drift spec; +0.5 day for a rake bump task.

### NEW adoptable — Medium priority

#### C. Single-instance file lock for hook-spawned maintenance (v1.4.2, #97)
- **What**: Concurrent SessionStart hooks (multi-worktree) spawned competing sync workers that collided on SQLite with `SQLITE_BUSY`. Fix: a `proper-lockfile` single-instance lock with PID-liveness fallback; losers print "already running (pid X); skipping" and exit clean. Same lock is reused for the embedding migration.
- **Evidence**: `src/file-lock.ts`, CHANGELOG 1.4.2.
- **Why it matters to us**: We've hit hook DB-contention (memory: "looping `claude-memory reject` silently no-ops under hook contention"; we lean on WAL + busy_timeout). A lightweight machine-level lock around hook-spawned sweep/ingest would make concurrent-session behavior deterministic rather than relying purely on busy_timeout retries. Lower urgency since WAL handles most of it.
- **Effort**: 1 day.

#### D. Exact-match metadata search filters (v1.1.0, #63)
- **What**: `--project`, `--session-id`, `--git-branch` scope filters on CLI + MCP search, bound as SQL parameters.
- **Evidence**: CHANGELOG 1.1.0.
- **Why it matters to us**: We scope by project/global already. A `git_branch` recall filter could be a useful cross-cut (facts learned on a feature branch). Speculative — gather usage data first per our data-driven-design convention.
- **Effort**: 1 day.

### Validations (no action, confirms our choices)

- **bge-small-en-v1.5 is the right model**: They migrated *to* the exact model we already default to in fastembed, citing measured retrieval gains on 17k real exchanges — rank-1 47%→53%, top-10 68%→75% (CHANGELOG 1.2.0). Our prior influence-doc note ("ours is better") is now "they agree."
- **High-water-mark delta ingestion**: Their indexer's `COUNT(*) > 0` skip silently dropped appended exchanges; fixed with a `MAX(line_end)` high-water mark (#84). This is exactly our cursor-per-session delta model — worth a one-time check that our ingest cursor advances on *appended* transcript tails, not just first-seen files.
- **Cosine-vs-L2 score display bug (#55)**: `1 - distance` is wrong for L2; unit-normalized cosine is `1 - d²/2`. Ranking was unaffected (monotonic) but displayed similarity was. If/when we expose sqlite-vec L2 distances as "similarity %", verify the conversion math.

### Features to AVOID (unchanged stance, reinforced)

- **Claude Agent SDK summarization** (their core mechanism) — violates our no-extra-API-cost convention. v1.1.2's "recursive process explosion" (#87: SDK subprocess fires SessionStart → re-runs sync → spawns subprocess → fan-out of hundreds of detached processes, burning API quota) is a cautionary tale that *validates* our decision to never spawn Claude subprocesses for memory work. Their reentrancy-guard env var fix is N/A to us because the cascade can't exist in our architecture.
- **Codex cross-harness support** (v1.3.0) — out of scope; we target Claude Code.
- **Summarizer error-sentinel/queue-retry machinery** (v1.4.1/1.4.2) — only needed because they have an async LLM summarization queue; we don't.

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
