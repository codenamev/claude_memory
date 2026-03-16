# Lossless Claw Analysis

*Analysis Date: 2026-03-16*
*Repository: https://github.com/martian-engineering/lossless-claw*
*Version: 0.3.0 (commit 49949fb)*

---

## Executive Summary

**Lossless Claw** is a TypeScript plugin for OpenClaw that implements **Lossless Context Management (LCM)** — a DAG-based summarization system that replaces sliding-window context compaction. Instead of discarding old messages, it compresses them into a hierarchy of summaries while preserving every original message in SQLite.

**Key Innovation**: Depth-aware summarization DAG with three-level escalation (normal → aggressive → deterministic fallback), ensuring compaction always succeeds. Agents can drill into any summary to recover original detail via `lcm_expand_query`.

| Aspect | Detail |
|--------|--------|
| Language | TypeScript (~34K LOC) + Go TUI |
| Storage | SQLite (WAL mode, optional FTS5) |
| Framework | OpenClaw plugin (ContextEngine interface) |
| Testing | Vitest, 20 test files, ~153K lines |
| Author | Josh Lehman / Martian Engineering |
| License | MIT |
| Maturity | Pre-1.0 but production-quality |
| Docs | 5 detailed guides + 6 design specs |

**Production Readiness**: High. Comprehensive test suite, extensive documentation, structured release process (Changesets + GitHub Actions), depth-aware prompts, crash recovery via session reconciliation.

---

## Architecture Overview

### Data Model

**Conversations → Messages → Summaries (DAG)**

```
messages (raw, with message_parts)
    ↓ leaf compaction
summaries (depth 0, kind="leaf")
    ↓ condensation
summaries (depth 1+, kind="condensed")
    ↓ condensation
summaries (depth 2+, ...)
```

- **conversations**: session_id, title, bootstrapped_at
- **messages**: role, content, token_count, seq (monotonic)
- **message_parts**: 10 columns for polymorphic content (text, tool calls, reasoning, patches, files)
- **summaries**: summaryId (SHA-256), kind, depth, token_count, earliest_at/latest_at, descendant_count, file_ids
- **summary_parents**: DAG edges (parent-child relationships)
- **context_items**: Ordered list of what model sees (references messages or summaries)
- **large_files**: Intercepted files >25K tokens with exploration summaries

### Design Patterns

| Pattern | Location | Purpose |
|---------|----------|---------|
| Dependency Injection | `src/types.ts:92-149` | LcmDependencies interface decouples from OpenClaw |
| Factory Methods | `src/tools/*.ts` (createLcmXxxTool) | Dynamic tool construction |
| Strategy | `src/expansion-policy.ts` | Route-vs-delegate decision matrix |
| Decorator | `src/expansion-auth.ts` | AuthorizedOrchestrator wraps base for budgets |
| Reference Counting | `src/db/connection.ts:29-52` | SQLite connection pool |
| DAG Traversal | `src/expansion.ts:116-165` | Token-budgeted graph walk |
| Three-Level Escalation | `src/summarize.ts` | Normal → aggressive → fallback truncation |

### Module Organization

```
index.ts                    # Plugin registration + multi-tier auth (1325 lines)
src/
├── engine.ts              # ContextEngine lifecycle (1825 lines)
├── assembler.ts           # Context reconstruction
├── compaction.ts          # CompactionEngine with leaf + condensation passes
├── summarize.ts           # Depth-aware prompts + LLM summarization
├── expansion.ts           # DAG expansion orchestrator
├── expansion-auth.ts      # Delegation grants with token caps + TTL
├── expansion-policy.ts    # Route-vs-delegate decision matrix
├── retrieval.ts           # grep/describe/expand query interface
├── large-files.ts         # File interception (>25K tokens)
├── integrity.ts           # DAG repair
├── transcript-repair.ts   # Tool-use/result pairing sanitization
├── types.ts               # DI contracts
├── db/
│   ├── connection.ts      # Ref-counted SQLite pooling
│   ├── config.ts          # 13 env vars with 3-tier precedence
│   ├── migration.ts       # Schema migrations with cycle protection
│   └── features.ts        # Runtime FTS5 detection + caching
├── store/
│   ├── conversation-store.ts  # Message CRUD + search
│   ├── summary-store.ts       # DAG persistence + lineage queries
│   ├── fts5-sanitize.ts       # FTS5 query sanitization
│   └── full-text-fallback.ts  # LIKE-based fallback
└── tools/
    ├── lcm-grep-tool.ts       # Regex + full-text search
    ├── lcm-describe-tool.ts   # Summary/file metadata inspection
    ├── lcm-expand-tool.ts     # Low-level DAG expansion (sub-agent)
    └── lcm-expand-query-tool.ts # Main agent expansion wrapper
```

### Comparison vs ClaudeMemory

| Aspect | Lossless Claw | ClaudeMemory |
|--------|---------------|--------------|
| **Domain** | Context management (conversation compression) | Knowledge management (fact extraction) |
| **Storage Model** | Messages + summary DAG | SPO triples with provenance |
| **Compaction** | Depth-aware DAG summarization | Sweep (prune expired/superseded facts) |
| **Search** | FTS5 + regex on messages/summaries | FTS5 + sqlite-vec on facts |
| **Recall** | grep → describe → expand_query escalation | recall → explain → fact_graph |
| **Scope** | Per-conversation | Global + project dual-database |
| **Language** | TypeScript | Ruby |
| **LLM Integration** | Heavy (summarization on every compaction) | Light (NullDistiller, future extraction) |
| **Plugin Format** | OpenClaw ContextEngine | Claude Code plugin + MCP |
| **Truth Maintenance** | Summaries supersede messages | Resolver with predicate policies |
| **Sub-agents** | Delegation grants for expansion | None (MCP tools only) |

---

## Key Components Deep-Dive

### 1. Compaction Engine (`src/compaction.ts`)

The heart of LCM. Implements incremental and full-sweep compaction:

**Leaf Pass** (lines 222-400):
- Protects "fresh tail" (default 32 recent messages)
- Chunks messages up to `leafChunkTokens` (20K default)
- Summarizes with leaf-specific prompt
- Three-level escalation ensures progress

**Condensation Pass** (lines 400-600):
- Merges same-depth summaries into higher-level nodes
- Minimum fanout: 8 for leaves, 4 for condensed
- Hard minimum: 2 (for forced compaction under pressure)
- Depth-appropriate prompts (d1, d2, d3+)

**Token Budget Management** (lines 170-222):
- Threshold-based triggering (default 75% of context window)
- `compactUntilUnder()`: Repeated sweeps until budget met

### 2. Depth-Aware Prompts (`tui/prompts/`)

Different summarization strategies per DAG level:

- **leaf.tmpl** (d0): Narrative preservation with timestamps, file tracking
- **condensed-d1.tmpl** (d1): Chronological narrative, delta-oriented
- **condensed-d2.tmpl** (d2): Arc-focused (goal → outcome → what carries forward)
- **condensed-d3.tmpl** (d3+): Maximum abstraction, durable context only

This is the most novel pattern — summaries at different depths serve different purposes.

### 3. Expansion Policy (`src/expansion-policy.ts:39-303`)

Intelligent routing for recall queries:

**Decision Matrix** (lines 215-303):
- `answer_directly`: No candidates or low-complexity probe
- `expand_shallow`: Direct expansion (depth ≤ 2, 1 candidate, low token risk)
- `delegate_traversal`: Sub-agent for deep/broad queries

**Token Risk Classification** (lines 189-205):
- Low: ratio < 0.35
- Moderate: 0.35–0.70
- High: ≥ 0.70

**Indicators** (lines 95-146):
- Broad time range detection via regex + year span
- Multi-hop detection via query language + depth/breadth heuristics

### 4. Context Assembly (`src/assembler.ts:206+`)

Reconstructs model context from DAG:

1. Fetch all context_items ordered by ordinal
2. Resolve each (summaries → XML user messages; messages → reconstructed from parts)
3. Split into evictable prefix + protected fresh tail
4. Fill remaining budget from evictable set (newest first)
5. Normalize assistant content to array blocks
6. Sanitize tool-use/result pairing

**XML Summary Format**:
```xml
<summary id="sum_abc123" kind="leaf" depth="0" descendant_count="5"
         earliest_at="2026-02-17T07:37:00" latest_at="2026-02-17T08:23:00">
  <content>...summary text...</content>
</summary>
```

### 5. Sub-Agent Delegation (`src/expansion-auth.ts`, `src/tools/lcm-expand-tool.delegation.ts`)

Secure sub-agent spawning for deep recall:

- **Delegation grants**: Token budget + conversation scope + TTL per sub-agent
- **Session key parsing**: `agent:<agentId>:<subagent|suffix...>`
- **Recursion guard**: Prevents recursive sub-agent spawning
- **Multi-pass execution**: Round-based with pass tracking and budget enforcement
- **Observability**: Status (ok/timeout/error) with runId collection

### 6. Large File Handling (`src/large-files.ts`)

Files >25K tokens intercepted at ingestion:
- Stored separately with lightweight exploration summaries (~200 tokens)
- Replaced with compact reference in context
- Accessible via `lcm_describe` tool
- MIME type inference from extension

### 7. Go TUI (`tui/`)

Interactive terminal built with Bubbletea for database inspection:
- Browse agents → sessions → conversations → DAG/context/files
- **Rewrite**: Re-summarize with current prompts
- **Dissolve**: Undo condensation, restore parent summaries
- **Repair**: Fix corrupted summaries (fallback markers)
- **Transplant**: Copy DAG across conversations
- **Backfill**: Import pre-LCM sessions

---

## Comparative Analysis

### What They Do Well

1. **Depth-aware summarization** — Different prompts per DAG level is brilliant. Leaf summaries preserve detail; high-depth condensations abstract to durable themes. We have no analogous graduated abstraction.

2. **Three-level escalation** — Ensures compaction always succeeds. Normal → aggressive → deterministic fallback prevents infinite loops or stalled compaction. Robust production pattern.

3. **Sub-agent delegation for deep recall** — Token-budgeted sub-agents for deep DAG traversal. Keeps main agent context lean while enabling arbitrary depth exploration.

4. **Context assembly pipeline** — Sophisticated reconstruction with fresh tail protection, budget-aware eviction, tool-use pairing sanitization. We don't manage context assembly at all.

5. **Session reconciliation** — Handles crashes by comparing JSONL ground truth with database state. Resilient to interrupted operations.

6. **TUI for debugging** — Interactive inspection of the entire summary DAG, with ability to rewrite, dissolve, and repair summaries. We have CLI commands but no interactive debugging.

### What We Do Well

1. **Structured knowledge extraction** — SPO triples with provenance vs raw message compression. Our facts are queryable, scopable, and support truth maintenance. Their summaries are opaque text.

2. **Dual-database scope system** — Global vs project separation. They operate per-conversation only.

3. **Truth maintenance** — Resolver with predicate policies, supersession, and conflict detection. They have no equivalent — new summaries just replace old ones.

4. **Semantic search** — sqlite-vec with fastembed-rb for embedding-based retrieval. They rely on FTS5/LIKE only.

5. **Lightweight architecture** — No LLM calls in the hot path (retrieval). Their every compaction requires LLM summarization ($$$).

6. **Entity extraction** — Named entity tracking with aliases. They store raw conversation content with no entity model.

### Trade-offs

| Trade-off | Lossless Claw | ClaudeMemory |
|-----------|---------------|--------------|
| LLM cost | High (summarization per compaction) | Low (no LLM in recall) |
| Information loss | Very low (DAG preserves originals) | Some (fact distillation is lossy) |
| Query flexibility | Strong (grep + expand into originals) | Strong (FTS + vector + hybrid) |
| Context quality | Excellent (assembled with summaries) | Good (published snapshot) |
| Scope model | Per-conversation | Global + project |
| Maintenance | Complex (DAG integrity, repair) | Simple (sweep expired/superseded) |
| Startup cost | High (bootstrap + reconciliation) | Low (read-only at startup) |

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Depth-Aware Prompt Templates for Distiller ⭐

- **Value**: When we build a real distiller (replacing NullDistiller), use graduated extraction prompts based on context depth. Fresh conversations get detailed extraction; well-established facts get consolidation prompts. Parallels their leaf/d1/d2/d3+ prompt hierarchy.
- **Evidence**: `tui/prompts/leaf.tmpl`, `tui/prompts/condensed-d1.tmpl`, `tui/prompts/condensed-d2.tmpl`, `tui/prompts/condensed-d3.tmpl` — four distinct prompt templates with increasing abstraction
- **Implementation**: Create prompt templates for distiller stages: initial extraction (detailed), re-extraction (consolidation), contradiction resolution (focused). Use depth/freshness to select template.
- **Effort**: 1-2 days (when building real distiller)
- **Trade-off**: Complexity in managing multiple prompt variants
- **Recommendation**: ADOPT — core insight for distiller design

#### 2. Three-Level Escalation for Sweep/Maintenance ⭐

- **Value**: Our sweep operations can stall on edge cases (large datasets, locked databases). A normal → aggressive → fallback escalation pattern ensures maintenance always completes. Prevents stuck states.
- **Evidence**: `src/summarize.ts` — three escalation levels with deterministic fallback; `src/compaction.ts:170-222` — budget-targeted sweeps
- **Implementation**: Apply to Sweep module: normal sweep (time-bounded) → aggressive sweep (wider scope, less selective) → fallback (force-expire oldest, skip integrity checks). Return status indicating which level was needed.
- **Effort**: 1-2 days
- **Trade-off**: Aggressive/fallback modes may be too aggressive
- **Recommendation**: ADOPT — robustness pattern

#### 3. Tool Escalation Workflow in MCP Instructions ⭐

- **Value**: Their `lcm_grep → lcm_describe → lcm_expand_query` escalation pattern is explicitly documented in assembler system prompts, teaching agents when to use cheap vs expensive tools. Our MCP guide prompt could adopt this pattern.
- **Evidence**: `src/assembler.ts:51-112` — system prompt additions with tool escalation hierarchy and precision checklist
- **Implementation**: Update QueryGuide module to include explicit tool escalation: `memory.recall` (fast, broad) → `memory.recall_details` (targeted) → `memory.explain` (deep provenance) → `memory.fact_graph` (relationship exploration). Add cost/speed annotations per tool.
- **Effort**: 0.5 days
- **Trade-off**: None — pure documentation improvement
- **Recommendation**: ADOPT — immediate win

### Medium Priority

#### 4. Connection Health Probing

- **Value**: Their connection pooling includes health checks before reuse (`src/db/connection.ts:12-19`). Our StoreManager creates connections but doesn't verify they're healthy before returning them.
- **Evidence**: `src/db/connection.ts:5-52` — reference-counted pooling with probe query
- **Implementation**: Add `db.execute("SELECT 1")` health check to StoreManager before returning connections. Cache healthy connections, recreate on failure.
- **Effort**: 0.5 days
- **Trade-off**: Slight overhead per connection acquisition
- **Recommendation**: CONSIDER — defensive measure

#### 5. Token Budget Tracking for Recall

- **Value**: Their expansion system tracks token budgets meticulously — remaining tokens, cost per operation, budget enforcement. Could apply to our recall to prevent oversized responses.
- **Evidence**: `src/expansion-auth.ts` — grant-based budgeting; `src/expansion-policy.ts:189-205` — token risk classification
- **Implementation**: Add optional `max_tokens` param to recall tools. Track response size, truncate gracefully with "more results available" indicator.
- **Effort**: 1-2 days
- **Trade-off**: Additional parameter complexity
- **Recommendation**: CONSIDER — useful for large databases

#### 6. Conversation-Scoped Context Injection

- **Value**: Their assembler adds depth-aware guidance to system prompts when conversations are heavily compacted. We could inject similar context about fact density/recency in our SessionStart hook.
- **Evidence**: `src/assembler.ts:62-112` — conditional system prompt additions based on compaction depth
- **Implementation**: In hook context injection, include metadata: fact count, recent changes count, conflict count. When conflicts > 0, add advisory note.
- **Effort**: 1 day
- **Trade-off**: Slightly larger context injection
- **Recommendation**: CONSIDER — enhances existing hook context

### Low Priority

#### 7. Interactive DAG/Fact Browser TUI

- **Value**: Their Go TUI with Bubbletea is impressive for debugging. A similar interactive fact browser could help users understand their knowledge graph.
- **Evidence**: `tui/main.go` + `tui/data.go` — full Bubbletea application
- **Implementation**: Would require a Go or Ruby TUI library (e.g., tty-prompt, pastel)
- **Effort**: 3-5 days
- **Trade-off**: Significant new dependency, maintenance burden
- **Recommendation**: DEFER — CLI commands are sufficient for now

#### 8. Large Content Interception

- **Value**: Their large file processor intercepts >25K token files and replaces them with compact summaries. Could apply to our ingester for very large transcript segments.
- **Evidence**: `src/large-files.ts` — file interception with exploration summaries
- **Implementation**: During ingest, if a content item exceeds threshold, store a summary reference instead of full content.
- **Effort**: 2 days
- **Trade-off**: Requires LLM call for summarization
- **Recommendation**: DEFER — our transcripts are already chunked

### Features to Avoid

- **DAG-Based Compaction** — Fundamentally different paradigm from fact extraction. Their approach compresses conversations; ours distills knowledge. These are complementary, not competing.
- **Per-Conversation Scoping** — Our dual-database (global/project) is more useful for knowledge that spans conversations.
- **LLM-Heavy Pipeline** — Every compaction requires LLM calls. Our lightweight retrieval path (no LLM) is a significant advantage.
- **Go TUI** — Adding a second language (Go) for a debugging tool is over-engineering for our use case.
- **Message Parts Polymorphism** — Their 10-column message_parts table handles tool calls, reasoning, patches, etc. We don't store raw messages, so this is irrelevant.
- **OpenClaw ContextEngine Interface** — Tight coupling to their framework. Our MCP + hooks approach is more portable.
- **Sub-Agent Delegation for Recall** — Spawning sub-agents adds latency and complexity. Our MCP tools return results directly, which is simpler and faster. (Note: we already have #8 Search Agent Delegation in improvements.md for a lighter-weight version.)
- **Session Reconciliation** — Crash recovery by comparing JSONL with DB. We use atomic transactions and don't need recovery logic.
- **OAuth Refresh for API Keys** — Multi-provider auth chain is OpenClaw-specific complexity we don't need.

---

## Implementation Recommendations

### Phase 1: Quick Wins (1-2 days)

1. **Tool Escalation Workflow** (#3) — Update QueryGuide with explicit tool hierarchy and cost annotations
2. **Connection Health Probing** (#4) — Add health check to StoreManager

### Phase 2: Robustness (2-3 days)

3. **Three-Level Escalation for Sweep** (#2) — Add escalation pattern to maintenance operations
4. **Token Budget Tracking** (#5) — Optional max_tokens for recall

### Phase 3: Future Distiller Design (when building distiller)

5. **Depth-Aware Prompt Templates** (#1) — Graduated extraction prompts based on context
6. **Conversation-Scoped Context** (#6) — Dynamic metadata in hook injection

---

## Architecture Decisions

### What to Preserve (Our Advantages)
- SPO triple model with provenance — more structured than opaque summaries
- Dual-database scope system — more flexible than per-conversation
- No-LLM retrieval path — cheaper and faster
- Truth maintenance with predicate policies — they have no equivalent
- sqlite-vec semantic search — they only have FTS5/LIKE

### What to Adopt
- Three-level escalation pattern for operations that must succeed
- Tool escalation documentation in MCP instructions
- Depth-aware prompts when building real distiller
- Connection health probing as defensive measure

### What to Reject
- DAG-based conversation compaction (different paradigm)
- LLM-heavy pipeline (cost and latency)
- Go TUI (wrong trade-off for our project)
- OpenClaw-specific patterns (framework coupling)
- Sub-agent delegation (complexity vs benefit for our use case)

---

## Key Takeaways

1. **Different problem, different solution**: LCM compresses conversations; we extract knowledge. Both are valid approaches to "memory" but serve fundamentally different purposes. There's no architectural adoption to make — the patterns worth adopting are tactical, not structural.

2. **Depth-aware prompts are the key insight**: Their graduated prompt strategy (detail at leaves, abstraction at depth) is the most transferable concept. When we build a real distiller, this should inform prompt design.

3. **Escalation patterns ensure robustness**: Their three-level escalation (normal → aggressive → fallback) is a production-quality pattern we should adopt for any operation that must succeed.

4. **Tool escalation workflow is immediately actionable**: Documenting cheap-to-expensive tool progression in our MCP instructions is a zero-cost improvement.

5. **Our approach has clear advantages**: Structured facts, semantic search, no-LLM retrieval, and truth maintenance are strengths we should preserve. Their LLM-heavy pipeline is a significant cost/complexity trade-off.
