# Claude-Mem Analysis

*Analysis Date: 2026-03-02*
*Repository: https://github.com/thedotmack/claude-mem*
*Version: 10.5.2 (commit ecb09df)*
*Re-studied: 2026-03-30 — v10.6.3 (commit d068821). 4 releases since last study (v10.5.6, v10.6.0, v10.6.1, v10.6.2, v10.6.3). Key changes: OpenClaw system prompt context injection replacing MEMORY.md writes (v10.6.0), compressed context output ~53% smaller (v10.6.1), timeline report skill (v10.6.1), process supervisor hardening with PID 0 fix and signal race condition fix (v10.5.6), activity spinner orphan session fix (v10.6.2), Gemini CLI integration (v10.6.3), 7 critical cross-platform bug fixes (v10.6.3). Context injection pattern (appendSystemContext with 60s cache) aligns with our SessionStart hook approach. Compressed context format worth studying. No new adoptable patterns beyond what we already implement.*

---

## Re-studied: 2026-06-30 — v13.9.1 (commit 3a2ba29)

**CHANGED? Yes — major.** ~60 releases and three major versions since the v10.6.3 baseline (v11.0.0 → v12.0.0 → v13.0.0 → v13.9.1). The project's center of gravity shifted from a single Bun worker + SQLite + Chroma into a far heavier multi-runtime system. Two dominant themes since baseline: (1) a large opt-in **Server Beta** stack (Postgres + Redis + BullMQ + REST `/v1` API), and (2) a ground-up **PostHog cloud telemetry** buildout. Both reinforce our existing rejections rather than offering new adoptable surface. The genuinely adoptable signal is concentrated in observer-output quality and per-prompt context injection.

### What changed (by major version)

- **v11.0.0 (2026-04-05)** — *Semantic Context Injection*: every `UserPromptSubmit` now queries the vector store for the top-N most relevant past observations and injects them, replacing recency-based "last N" with relevance-based retrieval (survives `/clear`, skips <20-char prompts, degrades gracefully when the vector store is down). *Strict Observer Response Contract* (breaking): the observer can no longer return prose skips like "Skipping — no substantive tool executions"; `buildObservationPrompt` now requires `<observation>` XML blocks or an empty response, and a `ResponseProcessor` warns on non-XML. Also: tier routing (Haiku for simple tool-only queues, ~52% cost cut), multi-machine observation sync over SSH, orphaned-message drain.
- **v12.0.0 (2026-04-07)** — *File-Read Decision Gate*: a `PreToolUse` hook detects when a file already has prior observations, injects the observation timeline, and **blocks the redundant `Read`/`Edit`** via `permissionDecision: deny` with a rich payload (file-size threshold + observation dedup). Smart-explore expanded to 24 tree-sitter languages. Platform-source isolation (`platform_source` column) namespaces Claude vs Codex sessions. 40+ cross-platform bug fixes.
- **v13.0.0 (2026-05-08)** — *Server Beta* opt-in runtime: Postgres-backed storage, BullMQ+Redis queue, `/v1` REST API, API-key auth, outbox pattern, Docker/E2E harness. **Relicensed AGPL-3.0 → Apache-2.0** (our prior doc flagged AGPL as a concern — that concern is now resolved on their side, though we remain MIT).
- **v13.5.x–13.8.0** — almost entirely PostHog telemetry (per-session rollups, redacted error tracking, historical backfill, geolocation, cost-per-observation KPIs) plus worker-lifecycle hardening (self-replacing worker, single spawn-gate lockfile, CLI capability probing).
- **v13.9.0 (2026-06-29)** — `claude-mem/sdk` (cmem-sdk): an **in-process** capture→compress→search pipeline with **no HTTP worker and no Redis**. Notable because it walks back toward the in-process model we already use — quiet validation of our no-background-process stance. `server-beta` runtime renamed to `server`.
- **v13.9.1 (2026-06-29)** — observer drops invalid prose and pauses on quota; platform-source-scoped recovery.

### NEW adoptable items

#### High Priority

1. **Per-prompt semantic context injection (UserPromptSubmit hook)** — *value:* directly addresses our known `project_headless_retrieval_gap` (in headless `claude -p`, Claude never calls MCP recall tools, so memory's contribution rests entirely on the one-shot SessionStart injection). A `UserPromptSubmit` hook that injects the top-N semantically relevant facts on *each* prompt would extend memory's reach to mid-session and headless turns without an MCP round-trip. *Evidence:* v11.0.0 changelog "Semantic Context Injection (#1568)"; handler in `src/cli/handlers/session-init.ts`. *Effort:* ~1–2 days — we already have `recall_semantic` (fastembed) and a context-injection path; this is a new hook event reusing existing retrieval, gated on prompt length and deduped against the SessionStart block. *Trade-off:* token cost per prompt — must cap N small and skip trivial prompts as they do.

2. **Observer output-fidelity classifier (`idle` / `prose` / `xml` taxonomy + visible preview)** — *value:* hardens our new observational layer's extraction border. Today our `store_extraction` validates/coerces, but a malformed Claude-as-observer turn can silently yield zero observations with no signal. claude-mem's `classifyObserverOutput` splits non-XML output into `idle` (benign empty — drop quietly) vs `prose` (conversational — drop but log a single-line preview), so a stuck-at-zero pipeline is *visible* rather than silent. *Evidence:* `src/sdk/output-classifier.ts:40-50` (`classifyObserverOutput`), `previewOutput` at `:20-28`. *Effort:* ~0.5 day — a pure function mirroring our existing `BareConclusionDetector`/`ReferenceMaterialDetector` style, plus a debug-level preview log when an extraction turn produced no rows. *Trade-off:* none; it's a diagnostics-only gate.

#### Medium Priority

3. **Quota-pause detection that preserves claimed work** — `isQuotaLimitedObserverOutput` (`src/sdk/output-classifier.ts:57-75`) distinguishes "Claude usage limit reached" prose from ordinary observer prose, so a quota pause does *not* get confused with a no-op skip. Less critical for us (we use the in-session Claude Code budget, no separate API), but the principle — *don't treat an interruption as "nothing to record"* — applies to our SessionStart distillation when the session is truncated. *Effort:* ~0.5 day if we choose to flag truncated-extraction turns distinctly.

### Features to avoid (reinforced)

- **Server Beta (Postgres + Redis + BullMQ + REST `/v1`)** — exactly the external-infrastructure complexity our CLAUDE.md and prior studies reject. Their own v13.9.0 cmem-sdk (no worker, no Redis) signals the in-process model is the saner default.
- **PostHog cloud telemetry** — the bulk of 13.5–13.8 is cloud analytics with consent gates, scrubbers, and a "~$7,700/mo → ~$10/mo" billing concern. Out of scope for a local-first, privacy-by-default gem; we keep telemetry in-DB (`mcp_tool_calls`, `activity_events`).
- **File-Read Decision Gate / Smart-Explore (24 languages, tree-sitter)** — still code-navigation domain, not fact memory. The `PreToolUse`-deny-with-injection *mechanism* is clever but we have no equivalent use case.
- **Multi-machine SSH sync, tier routing, multiple AI providers** — out of scope; we have no background agent making provider calls.

### Bottom line

claude-mem grew massively (3 majors, Postgres/Redis/REST, cloud telemetry) but most of that growth is infrastructure we deliberately avoid — and their own v13.9.0 in-process SDK quietly validates our no-worker design. The two patterns worth lifting are small and retrieval/quality-focused: **per-prompt semantic injection** (closes our headless-retrieval gap) and an **observer output classifier** (makes silent zero-extraction visible in our observation layer).

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
