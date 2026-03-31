# Claude-Supermemory Analysis (Updated)

*Analysis Date: 2026-03-02*
*Previous Analysis: 2026-02-02*
*Re-studied: 2026-03-30 — No meaningful code changes since v2.0.1. marketplace.json bumped to 0.0.3, added claude-code-review GitHub Action (anthropics/claude-code-action@v1). All findings remain current.*
*Repository: https://github.com/supermemoryai/claude-supermemory*
*Version: 2.0.0 (commit de39413)*

---

## Executive Summary

### Project Purpose

Claude-Supermemory is a Claude Code plugin providing persistent, cross-session memory using the Supermemory cloud service. It captures conversation transcripts at session end and injects recalled context at session start via hooks.

### Key Innovation (What's New Since Last Study)

1. **Team Memory** (v2.0.0): Project knowledge shared across team members via repo-level container tags, separate from personal memories. Dual `personalTag` + `repoTag` queries in parallel (`src/context-hook.js:52-55`).

2. **Signal Extraction**: Configurable keyword-based capture — only capture conversation turns containing signal keywords (e.g., "remember", "architecture", "decision"). Reduces noise in memory storage (`settings.json:signalKeywords`).

3. **Project Config**: Per-repo overrides via `.claude/.supermemory-claude/config.json` — custom API keys, container tags, signal settings per project.

4. **Browser Auth Flow**: OAuth-based authentication with local HTTP callback server (`src/lib/auth.js:117 lines`). Falls back to manual API key.

### Technology Stack

| Component | Technology |
|-----------|-----------|
| **Language** | JavaScript (CommonJS, Node.js ≥18) |
| **Storage** | Supermemory Cloud API (no local DB) |
| **Search** | Hybrid vector + keyword (via Supermemory API) |
| **Build** | esbuild (bundle to single CJS files) |
| **Linting** | Biome v2.3.13 |
| **Auth** | Browser-based OAuth + ENV fallback |
| **Dependencies** | 1 production (`supermemory@^4.0.0`), 2 dev |
| **Plugin** | Claude Code marketplace format |

### Production Readiness

- **Maturity**: Stable (v2.0.0), Supermemory Pro required
- **Test Coverage**: No automated tests (unchanged from last analysis)
- **Documentation**: Clear README with config examples
- **Limitation**: Cloud dependency — no offline use
- **License**: MIT

---

## Architecture Overview

### Data Model

No local data model. All persistence is in Supermemory's cloud:

- **Personal Memories**: User-specific, identified by `personalTag` (derived from cwd)
- **Team/Repo Memories**: Project-wide, identified by `repoTag` (git remote URL hash)
- **Profiles**: Server-computed static + dynamic facts per container

Local state:
- `~/.supermemory-claude/credentials.json` — auth tokens
- `~/.supermemory-claude/settings.json` — global config
- `.claude/.supermemory-claude/config.json` — per-project config

### Key Design Patterns

1. **Dual Container Tags** (`src/context-hook.js:47-55`): Personal and repo tags queried in parallel for session context:
   ```javascript
   const [personalResult, repoResult] = await Promise.all([
     client.getProfile(personalTag, projectName).catch(() => null),
     client.getProfile(repoTag, projectName).catch(() => null),
   ]);
   ```

2. **Signal Extraction** (`settings.json`): Only capture conversation turns containing signal keywords, with configurable context window:
   ```json
   {
     "signalExtraction": true,
     "signalKeywords": ["remember", "architecture", "decision", "bug", "fix"],
     "signalTurnsBefore": 3,
     "includeTools": ["Edit", "Write"]
   }
   ```

3. **Graceful Degradation** (`src/context-hook.js:27-40`): Never blocks session start. Auth failures, API errors, and empty results all produce informative `additionalContext` messages.

4. **Tiered Config** (`src/lib/settings.js`): Defaults → file → ENV override chain.

### Comparison with ClaudeMemory

| Aspect | Supermemory (2.0.0) | ClaudeMemory | Notes |
|--------|---------------------|--------------|-------|
| **Storage** | Supermemory Cloud | Local SQLite (dual DB) | We're self-contained |
| **Search** | Cloud hybrid search | Local FTS5 + fastembed | We work offline |
| **Team Memory** | Repo container tags | Not supported | They support shared team knowledge |
| **Signal Extraction** | Keyword-triggered | Ingest all transcripts | They're more selective |
| **Config** | Per-project overrides | Global + project scope | Similar concept |
| **Context Injection** | SessionStart hook | SessionStart hook | Same pattern (we adopted this) |
| **Dependencies** | Cloud API required | All local | We're more reliable |
| **Testing** | None | Comprehensive RSpec | We're more robust |
| **LOC** | ~1,195 | ~5,000 | We're more feature-rich |

---

## Key Components Deep-Dive

### Component 1: Team Memory (NEW)

**Purpose**: Share project knowledge across team members.

**Location**: `src/context-hook.js:47-72`, `src/lib/container-tag.js`

**Design Decisions**:
- Personal tag: derived from filesystem path
- Repo tag: derived from git remote URL
- Both queried in parallel
- Results formatted separately ("Personal Memories" vs "Project Knowledge")
- Empty results handled gracefully

### Component 2: Signal Extraction

**Purpose**: Reduce noise by only capturing significant conversation turns.

**Location**: `README:52-69`, settings.json

**Design Decisions**:
- Keyword-based detection (configurable list)
- Context window: capture N turns before signal turn
- Tool-based detection: capture turns using specific tools (Edit, Write)
- Disabled by default (captures everything)

### Component 3: Context Hook

**Purpose**: Inject past memories into new sessions.

**Location**: `src/context-hook.js:12-121`

**Design Decisions**:
- Reads stdin JSON from Claude Code hook
- Parallel API calls for personal + team context
- `combineContexts` merges with labeled sections
- Output via `hookSpecificOutput.additionalContext`
- Multiple fallback messages for auth/API/empty states

---

## Comparative Analysis

### What They Do Well

1. **Team Memory**: Repo-level container tags enable shared team knowledge
2. **Signal Extraction**: Smart filtering reduces memory noise
3. **Simplicity**: ~1,195 LOC, single dependency, clear architecture
4. **Graceful Degradation**: Never blocks sessions on failure

### What We Do Well

1. **Local-First**: No cloud dependency, works offline
2. **Knowledge Distillation**: Structured facts > raw transcript dumps
3. **Truth Maintenance**: Supersession and conflict resolution
4. **Comprehensive Testing**: Full RSpec suite
5. **Rich MCP Tools**: 18 tools for diverse queries
6. **Dual-Database**: Cleaner than container tags for scope separation

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Signal-Based Ingestion Filtering
- **Value**: Reduce noise in fact database, focus on significant content
- **Evidence**: `README:52-69` — keyword-triggered capture with context window
- **Implementation**: During ingest, prioritize transcript sections containing signal keywords (e.g., "decided", "convention", "always", "never", "prefer"). Already partially implemented via distiller scope hints.
- **Effort**: 1-2 days
- **Trade-off**: May miss important but subtly-expressed facts
- **Recommendation**: **CONSIDER** — Our distiller already extracts structured facts, which inherently filters noise

### Medium Priority

#### 2. Team/Shared Memory
- **Value**: Share project knowledge across team members
- **Evidence**: `src/context-hook.js:47-55` — dual personal/repo queries
- **Implementation**: Our global database already serves this role for cross-project knowledge. For team sharing, would need a shared database location or sync mechanism.
- **Effort**: 5+ days
- **Trade-off**: Significant complexity for team sync
- **Recommendation**: **DEFER** — Wait for user demand

#### 3. Per-Project Configuration
- **Value**: Different settings per project
- **Evidence**: `.claude/.supermemory-claude/config.json` per-repo config
- **Implementation**: Our Configuration class could support project-level overrides
- **Effort**: 1-2 days
- **Trade-off**: Minimal
- **Recommendation**: **CONSIDER** — Useful if users have different projects with different needs

### Features to Avoid

- **Cloud Storage Dependency**: Our local-first approach is superior
- **No-Test Approach**: Their lack of testing is a weakness, not a feature
- **Container Tag System**: Our dual-database approach is cleaner
- **Browser OAuth Flow**: Over-engineering for a developer tool
- **Supermemory API**: External service dependency

---

## Key Takeaways

### Changes Since Last Analysis (2026-02-02)
- v2.0.0 with team memory support
- Signal extraction for smarter capture
- Per-project configuration
- Browser-based auth flow
- Skills (super-search, super-save)
- GitHub Actions CI

### Main Learnings
1. Team memory via shared container tags is interesting but our dual-database handles scope well
2. Signal extraction is a clever noise reduction strategy worth considering
3. Their simplicity (~1,195 LOC) is admirable but comes at the cost of features and testing
4. Cloud dependency remains their biggest weakness vs our local-first approach

---

*Analysis completed: 2026-03-02*
*Analyst: Claude Code*
*Review Status: Draft*
