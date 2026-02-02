# Claude-Supermemory Analysis

*Analysis Date: 2026-02-02*
*Repository: https://github.com/supermemoryai/claude-supermemory*
*Version/Commit: latest main (shallow clone)*

---

## Executive Summary

**Project purpose**: Claude-Supermemory is a Claude Code plugin that provides persistent, cross-session memory by capturing conversation transcripts and injecting recalled context via hooks. It uses the Supermemory cloud service as its backend for storage and retrieval.

**Key innovation**: Cloud-delegated memory with automatic profile injection. Rather than maintaining a local knowledge base, it offloads all persistence, search, and profile computation to the Supermemory API. The plugin is purely a bridge between Claude Code's hook system and the cloud service.

**Technology Stack**:

| Component | Technology |
|-----------|-----------|
| Language | JavaScript (Node.js ≥18) |
| Storage | Supermemory Cloud API (no local DB) |
| Search | Hybrid vector + keyword (via Supermemory API) |
| Build | esbuild (bundle to single CJS files) |
| Linting | Biome v2.3.13 |
| Auth | Browser-based OAuth (local HTTP callback server) |
| Dependencies | 1 production (`supermemory@^4.0.0`), 2 dev |
| Total LOC | ~1,195 lines (source, excluding minified validate.js) |

**Production readiness**: Beta. Clean architecture, graceful error handling, and CI linting. No automated test suite. External API dependency means offline use is impossible. MIT license.

---

## Architecture Overview

### Data Model

Claude-Supermemory has **no local data model**. All persistence is in Supermemory's cloud:

- **Memories**: Free-text content with container tags, metadata, and custom IDs
- **Profiles**: Server-computed static (persistent) + dynamic (recent) facts per container
- **Search Results**: Vector + keyword hybrid search with similarity scores

The only local state is:
- Credentials: `~/.supermemory-claude/credentials.json`
- Settings: `~/.supermemory-claude/settings.json`
- Session trackers: `~/.supermemory-claude/trackers/{sessionId}.txt` (last captured UUID)

### Design Patterns

| Pattern | Location | Description |
|---------|----------|-------------|
| Adapter | `supermemory-client.js:11-109` | Wraps Supermemory SDK into normalized interface |
| Strategy | `hooks.json:1-50` | Different hooks for different lifecycle events |
| Facade | `context-hook.js:8-93` | Unified entry point delegating to helpers |
| Delta Ingestion | `transcript-formatter.js:51-70` | UUID-based cursor for incremental capture |
| Graceful Degradation | `context-hook.js:27-40` | Never blocks session, always returns `continue: true` |
| Tiered Config | `settings.js:23-41` | Defaults → file → ENV override chain |

### Module Organization

```
src/
├── Hooks (entry points)
│   ├── context-hook.js       → SessionStart: fetch profile, inject context
│   ├── prompt-hook.js        → UserPromptSubmit: stub (placeholder)
│   ├── observation-hook.js   → PostToolUse: stub (placeholder)
│   └── summary-hook.js       → Stop: capture transcript, save to cloud
├── CLI Scripts
│   ├── search-memory.js      → Manual memory search
│   └── add-memory.js         → Manual memory add
└── lib/ (core logic)
    ├── supermemory-client.js  → API wrapper (111 lines)
    ├── settings.js            → Configuration (89 lines)
    ├── auth.js                → Browser OAuth flow (117 lines)
    ├── format-context.js      → Memory → Claude injection (121 lines)
    ├── transcript-formatter.js → Transcript parsing (228 lines)
    ├── container-tag.js       → Project/user identification (51 lines)
    ├── compress.js            → Tool observation summarization (93 lines)
    ├── stdin.js               → Hook I/O abstraction
    └── validate.js            → Input validation (minified)
```

### Comparison Table vs ClaudeMemory

| Aspect | Claude-Supermemory | ClaudeMemory |
|--------|-------------------|--------------|
| **Storage** | Cloud API (Supermemory) | Local SQLite (dual-DB) |
| **Data Model** | Free-text memories | Subject-predicate-object facts |
| **Search** | Hybrid via API | FTS5 + FastEmbed local vectors |
| **Truth Maintenance** | Server-side (opaque) | Explicit resolver with supersession |
| **Scope System** | Container tags (project/user hash) | Dual database (global + project) |
| **Offline Support** | None | Full offline |
| **Test Suite** | None | Full RSpec suite + benchmarks |
| **Extraction** | Raw transcript capture | Distiller interface for fact extraction |
| **Conflict Resolution** | Deduplication only | Conflict detection + resolution |
| **Context Injection** | Hook-based XML injection | Published markdown snapshots |
| **Language** | JavaScript (Node.js) | Ruby |
| **LOC** | ~1,195 | ~8,000+ |
| **Dependencies** | 1 prod, 2 dev | ~5 prod |

---

## Key Components Deep-Dive

### 1. Context Injection via SessionStart Hook

**Purpose**: Inject recalled memories at session start so Claude has prior context.

**File**: `src/context-hook.js:8-93`

The hook reads stdin JSON from Claude Code, fetches the user's profile from Supermemory, formats it, and returns it as `additionalContext` in the hook response:

```javascript
// context-hook.js:72-74
writeOutput({
  hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext },
});
```

The `additionalContext` string is injected into Claude's system prompt as XML:

```xml
<supermemory-context>
The following is recalled context about the user...

## User Profile (Persistent)
- Prefers TypeScript over JavaScript

## Recent Context
- Working on authentication flow

## Relevant Memories (with relevance %)
- [2hrs ago] Implemented JWT auth for API [89%]

Use these memories naturally when relevant...
</supermemory-context>
```

**Key design**: `format-context.js:25-52` deduplicates across static, dynamic, and search results using a `Set`. This is lexical matching only (no semantic dedup).

**ClaudeMemory comparison**: We publish to `.claude/rules/claude_memory.generated.md` which Claude reads on startup. Their approach is more dynamic (fetches at runtime) but requires API availability. Our approach works offline but is stale until re-published.

### 2. Transcript Capture via Stop Hook

**Purpose**: Capture conversation turns when session ends.

**File**: `src/summary-hook.js:7-67`, `src/lib/transcript-formatter.js:1-228`

The Stop hook parses Claude Code's NDJSON transcript, extracts new entries since last capture, and formats them into a compact tagged format:

```
[turn:start timestamp="2026-02-02T10:30:00Z"]

[role:user]
How do I implement auth?
[user:end]

[tool:Edit]
file_path: src/auth.js
old_string: function login() {
new_string: async function login() {
[tool:end]

[role:assistant]
I've updated the login function to be async...
[assistant:end]

[turn:end]
```

**Key features**:
- UUID-based cursor tracking (`transcript-formatter.js:17-29`) — more reliable than timestamps
- Thinking blocks skipped (`transcript-formatter.js:136`)
- System reminders and self-references cleaned (`transcript-formatter.js:168-175`)
- Tool results truncated to 500 chars (`transcript-formatter.js:5`)
- Read tool results completely skipped (`transcript-formatter.js:6`)
- Minimum 100 chars to save (`transcript-formatter.js:212`)

**ClaudeMemory comparison**: We also do delta-based ingestion with cursor tracking. Their approach stores raw formatted transcript as a single memory blob. We extract structured facts (subject-predicate-object). Their approach is simpler but less queryable.

### 3. Tool Observation Compression

**Purpose**: Summarize tool usage into compact strings for memory storage.

**File**: `src/lib/compress.js:1-93`

Each tool type gets a custom summarization:

```javascript
// compress.js:17-74
case 'Edit': return `Edited ${file}: "${oldSnippet}" → "${newSnippet}"`;
case 'Write': return `Created ${file} (${contentLen} chars)`;
case 'Bash': return `Ran: ${cmd}${desc}${success ? '' : ' [FAILED]'}`;
case 'Task': return `Spawned ${agent}: ${desc}`;
```

Handles 10 tool types: Edit, Write, Bash, Task, Read, Glob, Grep, WebFetch, WebSearch, NotebookEdit.

**ClaudeMemory comparison**: We don't have tool-specific compression. Our transcript formatter stores tool usage in provenance, but without per-tool summarization logic. This is a useful pattern for reducing memory storage size.

### 4. Container Tag System (Project Isolation)

**Purpose**: Identify projects and users for memory isolation.

**File**: `src/lib/container-tag.js:1-51`

Uses SHA256 hashing of git root path for project identification:

```javascript
// container-tag.js:21-25
function getContainerTag(cwd) {
  const gitRoot = getGitRoot(cwd);
  const basePath = gitRoot || cwd;
  return `claudecode_project_${sha256(basePath)}`;  // 16-char hash
}
```

Also generates user-level tags based on git email or username (`container-tag.js:33-43`).

**ClaudeMemory comparison**: We use `project_path` on facts and dual databases. Their hashing approach provides privacy (path not exposed in API calls) and cross-machine consistency for same-email users. Our approach is more explicit but less privacy-preserving.

### 5. Graceful Auth Flow

**Purpose**: Authenticate with Supermemory via browser-based OAuth.

**File**: `src/lib/auth.js` (referenced from context-hook.js:22-40)

Starts a local HTTP server on port 19876, opens the system browser to Supermemory's auth page, and captures the API key via callback. Falls back gracefully:

```javascript
// context-hook.js:27-40
catch (authErr) {
  const isTimeout = authErr.message === 'AUTH_TIMEOUT';
  writeOutput({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: `<supermemory-status>
${isTimeout ? 'Authentication timed out...' : 'Authentication failed...'}
Session will continue without memory context.
</supermemory-status>`,
    },
  });
  return;  // Never blocks the session
}
```

**ClaudeMemory comparison**: We don't need authentication (local SQLite). This is relevant only if we ever add a cloud sync feature.

### 6. Skill-Based Search

**Purpose**: User-triggered memory search via `/super-search` command.

**File**: `plugin/skills/super-search/SKILL.md:1-35`

Defines a Claude Code skill that triggers a search script:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/search-memory.cjs" "USER_QUERY_HERE"
```

The skill markdown defines when it should be triggered: "Use when user asks about past work, previous sessions, how something was implemented."

**ClaudeMemory comparison**: We expose `memory.recall` and related tools via MCP. Their skill-based approach requires Claude to interpret intent and construct a search query. Our MCP approach lets Claude call tools directly with structured parameters. MCP is more powerful; skills are simpler to implement.

---

## Comparative Analysis

### What They Do Well

1. **Minimal footprint**: ~1,195 lines of code with 1 production dependency. Extremely lightweight.
2. **Hook response format**: Clean use of `hookSpecificOutput.additionalContext` for context injection at session start. This is a documented Claude Code API pattern we could adopt.
3. **Relative time formatting** (`format-context.js:1-23`): "2hrs ago", "3d ago" instead of ISO timestamps — more useful for context.
4. **Tool-specific compression** (`compress.js:13-75`): Per-tool summarization produces compact, readable summaries.
5. **Privacy-preserving identifiers** (`container-tag.js:4-6`): SHA256 hashing of paths means project names never leave the local machine.
6. **Deferred profile computation**: The Supermemory API computes static vs dynamic fact separation server-side, avoiding client-side complexity.
7. **Structured content tags**: `[turn:start]`, `[role:user]`, `[tool:Edit]` markup enables later parsing.
8. **Credential security**: API key never persisted in settings file (`settings.js:46`).

### What We Do Well

1. **Local-first architecture**: Full offline support, no API dependency, no subscription cost.
2. **Structured fact model**: SPO triples enable rich querying that blob storage cannot.
3. **Truth maintenance**: Supersession and conflict resolution with predicate policies.
4. **Comprehensive test suite**: Full RSpec coverage + DevMemBench benchmarks.
5. **Dual-database scope**: Clean separation of global vs project knowledge.
6. **Local semantic search**: FastEmbed ONNX model runs locally, no API calls for search.
7. **MCP integration**: 18 tools expose full memory API to Claude, more powerful than skills.
8. **Provenance tracking**: Every fact links back to source content with evidence.

### Trade-offs

| Trade-off | Cloud (Supermemory) | Local (ClaudeMemory) |
|-----------|-------------------|---------------------|
| **Setup** | Needs account + API key | `gem install` + done |
| **Latency** | Network round-trip | Instant (local SQLite) |
| **Offline** | Doesn't work | Full functionality |
| **Cost** | Requires Pro subscription | Free |
| **Cross-device** | Automatic sync | Manual (no built-in sync) |
| **Complexity** | Simple bridge (~1.2K LOC) | Full system (~8K+ LOC) |
| **Profile AI** | Server computes profiles | Must implement distiller |
| **Scalability** | Server handles growth | Must manage local DB |

---

## Adoption Opportunities

### High Priority ⭐

#### 1. SessionStart Context Injection via Hook ⭐

- **Value**: Inject recalled facts directly into Claude's context at session start, ensuring Claude always has relevant memory without requiring MCP tool calls
- **Evidence**: `context-hook.js:72-74` — uses `hookSpecificOutput.additionalContext` to inject XML context
- **Implementation**: Add a `SessionStart` hook handler to ClaudeMemory that:
  1. Queries both global and project databases for recent/relevant facts
  2. Formats them into a concise context block
  3. Returns via `hookSpecificOutput.additionalContext`
  - This supplements (not replaces) our existing `.claude/rules/` publish mechanism
- **Effort**: 1-2 days (hook handler, context formatter, settings integration)
- **Trade-off**: Adds startup latency (local DB query is fast, <100ms). Could duplicate info already in published rules file.
- **Recommendation**: **ADOPT** — Direct context injection ensures Claude sees memory immediately, before it could even call MCP tools. Our published rules file may not always be read or prioritized.

#### 2. Tool-Specific Observation Compression ⭐

- **Value**: Compact, readable summaries of tool usage for fact provenance and memory storage. Reduces token waste by ~70% vs storing raw tool I/O.
- **Evidence**: `compress.js:13-75` — 10 tool handlers producing human-readable summaries like `Edited auth.js: "login()" → "async login()"`
- **Implementation**: Create `ClaudeMemory::Compress::ToolSummarizer` class with per-tool handlers:
  ```ruby
  case tool_name
  when "Edit" then "Edited #{relative_path(file)}: #{truncate(old)} → #{truncate(new)}"
  when "Bash" then "Ran: #{truncate(cmd)}#{failed ? ' [FAILED]' : ''}"
  end
  ```
  Use during ingestion to produce compact provenance descriptions.
- **Effort**: 4-6 hours (class + tests, integrate with ingest pipeline)
- **Trade-off**: Lossy compression — original tool I/O detail is discarded
- **Recommendation**: **ADOPT** — Directly improves provenance quality and reduces storage size

#### 3. Relative Time Formatting in Recall Output ⭐

- **Value**: "2hrs ago", "3d ago" is more useful than "2026-02-02T10:30:00Z" when browsing facts
- **Evidence**: `format-context.js:1-23` — clean relative time function with progressive granularity
- **Implementation**: Add `ClaudeMemory::Formatting::RelativeTime` module, use in MCP recall results and CLI output
- **Effort**: 2-3 hours (module + tests + integration)
- **Trade-off**: None significant — ISO timestamps can be kept for technical/sort purposes
- **Recommendation**: **ADOPT** — Simple UX improvement

#### 4. Structured Transcript Tagging Format ⭐

- **Value**: Tagged format (`[role:user]`, `[tool:Edit]`, `[turn:start]`) enables structured parsing of ingested content. More reliable than regex-based extraction.
- **Evidence**: `transcript-formatter.js:72-84, 95-96, 141-148` — consistent markup for all content types
- **Implementation**: During ingestion, emit structured markers around content chunks. Enables the distiller to identify tool usage, user intent, and assistant reasoning separately.
- **Effort**: 1 day (update ingest formatter, update distiller interface)
- **Trade-off**: Slightly larger storage per content item
- **Recommendation**: **CONSIDER** — Useful when we implement a real distiller. Can defer until then.

### Medium Priority

#### 5. Plugin Distribution Format

- **Value**: Standard Claude Code plugin installation (`/install plugin`) instead of manual gem + MCP + hook setup
- **Evidence**: `plugin/hooks/hooks.json`, `plugin/skills/`, `plugin/commands/` — structured plugin format with automatic hook registration
- **Implementation**: Package ClaudeMemory as a Claude Code plugin with `hooks.json`, skills, and commands. Keep the gem for library usage.
- **Effort**: 2-3 days (plugin packaging, testing across platforms)
- **Trade-off**: Must maintain two distribution formats (gem + plugin). Plugin format may have constraints.
- **Recommendation**: **CONSIDER** — Would significantly reduce setup friction. Wait for Claude Code plugin ecosystem to mature.

#### 6. Tool Capture Filtering (Skip/Capture Lists)

- **Value**: Configurable tool filtering prevents noisy tools (Read, Glob) from bloating memory
- **Evidence**: `settings.js:9-15` — `skipTools` and `captureTools` arrays with whitelist/blacklist modes
- **Implementation**: Add tool filtering to ingestion config. Default skip: Read, Glob, Grep. Default capture: Edit, Write, Bash, Task.
- **Effort**: 3-4 hours (config + filter logic + tests)
- **Trade-off**: May miss useful context from skipped tools
- **Recommendation**: **CONSIDER** — Our tool_calls table already captures all tools; this would filter what gets elevated to facts

#### 7. Content Cleaning Pipeline

- **Value**: Strip system reminders, self-referential context, and noise before storage
- **Evidence**: `transcript-formatter.js:168-175` — regex-based removal of `<system-reminder>` and `<supermemory-context>` tags
- **Implementation**: Extend our `ContentSanitizer` to also strip `<claude-memory-context>` and `<system-reminder>` tags from ingested content
- **Effort**: 1-2 hours (regex additions + tests)
- **Trade-off**: Could accidentally strip user content that happens to use these tags
- **Recommendation**: **CONSIDER** — Our `ContentSanitizer` already handles `<private>` and `<no-memory>` tags. Adding system tag stripping is a small extension.

### Low Priority

#### 8. Browser-Based Auth Flow

- **Value**: Smoother onboarding for cloud features
- **Evidence**: `auth.js:62-109` — local HTTP server + browser redirect
- **Implementation**: Only relevant if we add cloud sync or API features
- **Effort**: 1-2 days
- **Trade-off**: Complexity for a feature we may never need
- **Recommendation**: **DEFER** — We're local-first. No cloud auth needed.

#### 9. Minimum Content Length Filter

- **Value**: Prevents saving trivially small memories
- **Evidence**: `transcript-formatter.js:212` — `if (result.length < 100) return null`
- **Implementation**: Add minimum content threshold in ingestion pipeline
- **Effort**: 30 minutes
- **Trade-off**: Could miss short but significant exchanges
- **Recommendation**: **DEFER** — Our distiller should handle quality filtering

### Features to Avoid

#### 1. Cloud-Only Storage

**Reasoning**: Their entire storage layer depends on Supermemory's API. This means no offline support, requires a paid subscription, and exposes all memory content to a third party. Our local SQLite approach is a fundamental advantage. Do not adopt cloud storage as primary.

#### 2. No Local Search

**Reasoning**: All search queries go to Supermemory's API. Our local FastEmbed + FTS5 hybrid search is faster, private, and works offline. Do not replace local search with API calls.

#### 3. No Test Suite

**Reasoning**: The repository has zero automated tests. Our comprehensive RSpec suite + DevMemBench benchmarks is a significant quality advantage. Do not reduce test coverage.

#### 4. Stub Hooks (Placeholder Architecture)

**Reasoning**: `prompt-hook.js` and `observation-hook.js` are stubs that only log and return success. This suggests the architecture was designed for future features that haven't materialized. Don't create placeholder code.

#### 5. Server-Side Profile Computation

**Reasoning**: They delegate "static vs dynamic" fact classification to the Supermemory API. This is opaque and uncontrollable. Our explicit predicate policies and truth maintenance system provide transparent, auditable knowledge management.

---

## Implementation Recommendations

### Phase 1: Context Injection (Immediate)

1. Add `SessionStart` hook handler that queries local DB for relevant facts
2. Format facts as compact context block with sections (conventions, decisions, architecture)
3. Return via `hookSpecificOutput.additionalContext`
4. Include relative timestamps for temporal context
5. Add tests for hook handler and formatter

### Phase 2: Ingestion Quality (Near-term)

1. Implement tool-specific observation compression for provenance
2. Add `<system-reminder>` and self-reference tag stripping to ContentSanitizer
3. Add configurable tool filtering for ingestion noise reduction
4. Consider structured transcript tagging for distiller input

### Phase 3: Distribution (Future)

1. Investigate Claude Code plugin format for easier installation
2. Package hooks, skills, and MCP server as plugin bundle
3. Maintain gem distribution for library consumers

---

## Architecture Decisions

### Preserve (Our Advantages)

- **Local SQLite storage** — privacy, offline support, no subscription
- **Fact-based knowledge graph** — structured querying, truth maintenance
- **Dual-database architecture** — clean global vs project separation
- **MCP tool interface** — 18 tools, more powerful than skills
- **Comprehensive test suite** — RSpec + DevMemBench benchmarks
- **FastEmbed local embeddings** — no API for semantic search

### Adopt

- **SessionStart context injection** — supplement published rules with dynamic injection
- **Tool observation compression** — compact provenance descriptions
- **Relative time formatting** — better UX for temporal context
- **System tag stripping** — cleaner ingested content

### Reject

- **Cloud storage dependency** — local-first is our core advantage
- **API-only search** — local search is faster and private
- **No test policy** — maintain our testing standards
- **Placeholder architecture** — only build what's needed now
- **Plugin-only distribution** — keep gem as primary, plugin as secondary option

---

## Key Takeaways

1. **Cloud vs local is the fundamental architectural difference.** Claude-Supermemory trades privacy and offline support for simplicity and cross-device sync. We should stay local-first.

2. **SessionStart context injection is the highest-value pattern to adopt.** It ensures Claude has memory context before any MCP tool calls. This is complementary to our existing publish mechanism.

3. **Their codebase is remarkably lean (~1.2K LOC).** This is achieved by delegating all intelligence to the Supermemory API. Our system is necessarily more complex because we handle search, truth maintenance, and fact extraction locally.

4. **Tool compression and relative timestamps are easy wins.** Both improve UX with minimal implementation effort.

5. **The plugin distribution format is worth watching.** As Claude Code's plugin ecosystem matures, packaging as a plugin could dramatically reduce setup friction.

6. **No test suite is a significant weakness.** Their approach of "delegate to cloud API" reduces local testing needs, but also means they can't verify behavior changes. Our testing infrastructure is a major advantage.

---

*Analysis performed by studying source code at `/tmp/study-repos/claude-supermemory`. All file:line references are relative to that checkout.*
