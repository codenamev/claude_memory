# Claude-Mem Analysis

*Analysis Date: 2026-03-02*
*Repository: https://github.com/thedotmack/claude-mem*
*Version: 10.5.2 (commit ecb09df)*

---

## Executive Summary

### Project Purpose

Claude-Mem is a persistent memory compression system for Claude Code. It captures tool usage observations during sessions, generates semantic summaries, and injects relevant context into future sessions. The largest and most actively developed memory plugin in the ecosystem.

### Key Innovation

1. **Progressive Disclosure Pattern**: 3-layer token-efficient workflow — search (compact index, ~50-100 tokens/result) → timeline (chronological context) → get_observations (full details, ~500-1000 tokens/result). Claims ~10x token savings by filtering before fetching.

2. **Worker Service Architecture**: Background HTTP server (port 37777) with web viewer UI, managed by Bun. Decouples hook processing from worker logic.

3. **Smart Explore** (v10.5.0): Tree-sitter AST-powered code navigation with 3 MCP tools (`smart_search`, `smart_outline`, `smart_unfold`). Claims 6-12x token savings vs full file reads.

4. **Multi-Platform Support**: Claude Code + Cursor + OpenClaw gateway adapters.

### Technology Stack

| Component | Technology |
|-----------|-----------|
| **Language** | TypeScript (ESM) |
| **Runtime** | Bun (worker), Node.js (hooks) |
| **Database** | SQLite (sessions, observations, summaries) |
| **Vector Search** | Chroma vector database (hybrid semantic + keyword) |
| **Summarization** | Claude Agent SDK + Gemini + OpenRouter agents |
| **MCP** | @modelcontextprotocol/sdk v1.25.1 |
| **Web UI** | React 18 + Express (port 37777) |
| **AST Parsing** | tree-sitter (10 languages) |
| **Build** | esbuild |
| **Testing** | Bun test runner |
| **Plugin** | Claude Code marketplace format |
| **License** | AGPL-3.0 |

### Production Readiness

- **Maturity**: Production (v10.5.2, very active development)
- **Test Coverage**: Extensive test suite (70+ test files across sqlite, worker, agents, search, context, infrastructure)
- **Documentation**: Professional docs site (docs.claude-mem.ai)
- **Community**: Large user base, active issue tracker
- **Complexity**: High — worker service, Chroma, multiple AI providers, web UI

---

## Architecture Overview

### Data Model

```
Lifecycle Hooks (SessionStart, UserPromptSubmit, PostToolUse, Stop, SessionEnd)
    ↓
Hook Scripts → JSON stdin → Platform Adapter → Event Handler
    ↓
Worker Service (HTTP API on port 37777)
    ↓
┌─────────────────┐    ┌──────────────────┐
│  SQLite DB      │    │  Chroma Vector DB│
│  - sessions     │    │  - embeddings    │
│  - observations │    │  - hybrid search │
│  - summaries    │    │  - keyword index │
│  - prompts      │    │                  │
└─────────────────┘    └──────────────────┘
    ↓
MCP Tools (search, timeline, get_observations, smart_*)
    ↓
Web Viewer UI (React, port 37777)
```

### Key Design Patterns

1. **Platform Adapter Pattern** (`src/cli/adapters/`): Claude Code and Cursor have different hook formats. Adapters normalize input for shared event handlers.

2. **Progressive Disclosure** (`README:199-232`): 3-layer workflow for token-efficient memory retrieval:
   - Layer 1: `search` — compact index with IDs (~50-100 tokens/result)
   - Layer 2: `timeline` — chronological context around results
   - Layer 3: `get_observations` — full details for filtered IDs

3. **Worker Service** (`src/services/worker/`): Background HTTP server manages state, search, SSE broadcasting, and AI agent calls. Hooks are thin clients that POST to the worker.

4. **Graceful Degradation** (`src/cli/hook-command.ts:26-66`): Sophisticated error classification — transport failures (worker down) return exit 0 (graceful), client bugs (4xx) return exit 2 (blocking).

5. **Smart Explore** (v10.5.0): Tree-sitter AST parsing for structural code navigation. `smart_search` → `smart_outline` → `smart_unfold` progressive disclosure.

### Comparison with ClaudeMemory

| Aspect | Claude-Mem | ClaudeMemory | Notes |
|--------|-----------|--------------|-------|
| **Data Model** | Observations + summaries | Subject-predicate-object facts | They store raw observations; we extract knowledge |
| **Storage** | SQLite + Chroma | Dual SQLite (project + global) | They need separate Chroma process |
| **Vector Search** | Chroma (external) | fastembed-rb (embedded) | We're simpler, they're more capable |
| **Architecture** | Worker service + hooks | MCP server + hooks | They have background process overhead |
| **MCP Tools** | search, timeline, get_observations, smart_* | 18 recall/management tools | Different focus |
| **Plugin Format** | marketplace.json | Ruby gem | They're easier to install |
| **Web UI** | React viewer at :37777 | None | Feature we don't need |
| **AI Providers** | Claude SDK + Gemini + OpenRouter | anthropic-rb | They're more flexible |
| **License** | AGPL-3.0 | MIT | Our license is more permissive |
| **Complexity** | Very high (~10K+ LOC) | Moderate (~5K LOC) | We're simpler by design |

---

## Key Components Deep-Dive

### Component 1: Progressive Disclosure Search

**Purpose**: Minimize token usage during memory retrieval.

**Location**: `README:199-232`, MCP tools

**Implementation**:
```
Step 1: search(query="auth bug", type="bugfix", limit=10)
        → Returns compact index with IDs (~50-100 tokens/result)
Step 2: Review index, identify relevant IDs (e.g., #123, #456)
Step 3: get_observations(ids=[123, 456])
        → Returns full details (~500-1000 tokens/result)
```

**Design Decisions**:
- ~10x token savings by filtering before fetching details
- Timeline layer provides chronological context
- Batch ID fetching for efficiency

### Component 2: Hook Error Classification

**Purpose**: Distinguish worker unavailability from actual bugs.

**Location**: `src/cli/hook-command.ts:26-66`

```typescript
// Transport failures → exit 0 (graceful degradation)
const transportPatterns = [
  'econnrefused', 'econnreset', 'epipe', 'etimedout',
  'fetch failed', 'socket hang up',
];
// HTTP 4xx → exit 2 (blocking error, developer needs to see)
// HTTP 5xx → exit 0 (server issues, degrade gracefully)
```

**Design Decisions**:
- Conservative: unknown errors are blocking (surface bugs)
- Transport failures never block Claude Code sessions
- Hook stderr suppressed (Claude Code shows stderr as error UI)

### Component 3: Smart Explore (Tree-Sitter AST)

**Purpose**: Token-optimized structural code search.

**Location**: v10.5.0 changelog, plugin skills

**Design Decisions**:
- 10 languages via tree-sitter grammars
- 3-tool progressive disclosure: search → outline → unfold
- Claims 6-12x token savings vs full file reads
- Complements rather than replaces Read tool

---

## Comparative Analysis

### What They Do Well

1. **Progressive Disclosure**: Elegant token-saving pattern for search results
2. **Graceful Degradation**: Sophisticated error classification prevents blocking Claude sessions
3. **Platform Adapters**: Clean abstraction for Claude Code vs Cursor
4. **Smart Explore**: AST-powered code navigation is genuinely useful
5. **Web Viewer**: Real-time memory stream with SSE

### What We Do Well

1. **Knowledge Distillation**: Structured facts > raw observations
2. **Truth Maintenance**: Supersession and conflict resolution
3. **Simplicity**: No background process, no external database
4. **Dual-Database System**: Clean project/global separation
5. **License**: MIT vs AGPL-3.0
6. **Test Architecture**: Focused, fast, no I/O in tests

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Progressive Disclosure Pattern for Recall
- **Value**: ~10x token savings on large result sets
- **Evidence**: `README:199-232` — 3-layer search → timeline → details workflow
- **Implementation**: Our `memory.recall_index` + `memory.recall_details` already implements this! Validate it matches their token savings pattern.
- **Effort**: 0.5 days (validation and documentation)
- **Trade-off**: None — we already have the infrastructure
- **Recommendation**: **ADOPT** (document our existing progressive disclosure)

#### 2. Hook Error Classification
- **Value**: Prevent memory system errors from blocking Claude Code sessions
- **Evidence**: `src/cli/hook-command.ts:26-66` — transport vs client error classification
- **Implementation**: Add similar classification to our hook commands. Exit 0 for transport failures, exit 1 for bugs.
- **Effort**: 1 day
- **Trade-off**: Minimal
- **Recommendation**: **ADOPT**

### Medium Priority

#### 3. Platform Adapter Pattern
- **Value**: Clean abstraction for supporting multiple AI code editors
- **Evidence**: `src/cli/adapters/` — Claude Code, Cursor adapters
- **Implementation**: Extract hook input normalization into adapter interface
- **Effort**: 2-3 days
- **Trade-off**: Premature if we only support Claude Code
- **Recommendation**: **DEFER** — Only if Cursor/Windsurf support is requested

#### 4. Compact Result Mode Documentation
- **Value**: Our `compact: true` mode already provides token savings — document it better
- **Evidence**: Their progressive disclosure docs show clear token economics
- **Implementation**: Add token estimates to our MCP tool descriptions
- **Effort**: 0.5 days
- **Recommendation**: **ADOPT**

### Features to Avoid

- **Worker Service Architecture**: Background process adds complexity and failure modes. Our stdio MCP server is simpler and sufficient.
- **Chroma Vector Database**: External dependency. sqlite-vec (from QMD/episodic-memory) is better fit.
- **Web Viewer UI**: CLI output is sufficient. CLAUDE.md already says to avoid this.
- **AGPL License**: Restrictive for a developer tool.
- **Multiple AI Providers**: Over-engineering. We use anthropic-rb directly.
- **Smart Explore**: Interesting but out of scope — code search is not our domain.
- **Tree-Sitter AST Parsing**: Not relevant to memory/fact retrieval.

---

## Key Takeaways

### Main Learnings
1. Progressive disclosure is the right pattern for token-efficient retrieval — we already have it
2. Hook error classification is important for not blocking user sessions
3. Worker service architecture adds significant complexity
4. Chroma is being used but sqlite-vec (from QMD/episodic-memory) is simpler
5. AGPL licensing is unusual for developer tools

### Recommended Adoption Order
1. **Document progressive disclosure**: We already have recall_index + recall_details
2. **Add hook error classification**: Prevent hook failures from blocking sessions
3. **Add token estimates to tool descriptions**: Help Claude use tools efficiently

---

*Analysis completed: 2026-03-02*
*Analyst: Claude Code*
*Review Status: Draft*
