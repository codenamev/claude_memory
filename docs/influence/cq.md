# cq Analysis

*Analysis Date: 2026-04-28*
*Repository: https://github.com/technicalpickles/cq*
*Focus: Tool usefulness (not internals)*

---

## Executive Summary

**cq** is a Rust CLI that indexes Claude Code's JSONL session transcripts into a local DuckDB cache (`~/.cache/cq/index.duckdb`) and exposes four SQL views (`sessions`, `messages`, `tool_calls`, `tool_results`) for querying with raw SQL or canned subcommands.

It is positioned squarely as **observability for your own Claude Code usage** — not a memory system, not a curation tool, not an in-session helper. You run it from a separate terminal to ask meta-questions like "which skills are firing?" or "where did context go in that bad session?"

**Verdict for ClaudeMemory**: complementary, not competing. cq is a *read* tool over raw transcripts; ClaudeMemory is a *write/curate* tool that distills transcripts into facts. Same data source, different jobs. **Recommendation: install cq as a developer-side audit tool**, especially for validating that the ClaudeMemory plugin itself is being used correctly. Do not adopt internals — the architectures don't overlap meaningfully.

**Tech stack**: Rust, DuckDB (with JSON extension), clap, comfy-table, fs2 file locking. ~14 source modules, MIT licensed.

## What cq Actually Gives You

The four views are the product. Everything else (subcommands, `--grep`, `-A/-B/-C` context flags, `--since 7d`) is convenience over those views.

| View | What it is | Why it matters |
|------|------------|----------------|
| `sessions` | One row per session, with timestamps, message counts, tool counts | Fastest way to find "the session where X happened" |
| `messages` | One row per user/assistant turn | Full-text grep across your entire history |
| `tool_calls` | One row per tool_use block with input as queryable JSON | The killer view — `json_extract_string(input, '$.command')` etc. |
| `tool_results` | One row per tool_result with `is_error` flag | Pairs with `tool_calls` to find silent failures |

The `tool_calls` view is where the value is. SQL + JSON path extraction over every Bash command, every Read path, every Skill invocation, every MCP tool call, across all your sessions, scoped automatically to the current project.

## Concrete Use Cases (lifted from their docs/use-cases.md)

These three patterns are the strongest argument for installing cq today:

### 1. Skill activation gaps

> *"Out of 166 sessions that ran `git commit` in a 7-day window, only 16 activated any commit skill. The rest went straight through Bash."*

A self-join on `tool_calls` between `Bash WHERE command LIKE '%git commit%'` and `Skill WHERE skill LIKE '%commit%'`, grouped by session_id, tells you which sessions ran `git commit` *without* invoking a commit skill. This is the cleanest "is my skill triggering?" signal that exists.

**Direct relevance to you**: ClaudeMemory ships several skills (`/distill-transcripts`, `/release`, `/review-for-quality`, `/review-commit`, etc.) and an MCP plugin. You currently have no way to answer "is the memory plugin actually firing on questions where it should?" Same query shape works:

```sql
-- Sessions that asked architecture/convention questions but never called memory.*
WITH memory_sessions AS (
  SELECT DISTINCT session_id FROM tool_calls
  WHERE name LIKE 'mcp__memory__%'
)
SELECT m.session_id, m.text
FROM messages m
LEFT JOIN memory_sessions ms ON m.session_id = ms.session_id
WHERE m.type = 'user'
  AND (m.text ILIKE '%convention%' OR m.text ILIKE '%architecture%' OR m.text ILIKE '%why did we%')
  AND ms.session_id IS NULL
```

### 2. Silent failures (the wrong-path pattern)

> *"The skill instructions referenced the wrong path... Claude recovered every time by Glob-searching for the file, so from the outside everything looked fine. Across 23 sessions over 30 days, the same silent failure repeated."*

Detects the `Read fails → Glob → Read succeeds at different path` sequence. For ClaudeMemory's skills (which reference dozens of file paths in `.claude/skills/`), this is a maintenance multiplier — broken paths self-heal at the cost of a few wasted tool calls per invocation, and you'd never notice without this query.

### 3. Context-budget forensics

> *"Three calls ate the context budget. Thirty more burned it retrying queries that would never work."*

`SELECT name, length(content) AS result_chars FROM tool_calls JOIN tool_results ... ORDER BY result_chars DESC` for a single session. Surfaces the few large tool results that dominate context. Useful when a session "felt slow" but no individual step looked wrong.

## How cq Compares to ClaudeMemory's Existing Data

ClaudeMemory already captures some of this in its own SQLite databases:

| Capability | ClaudeMemory | cq |
|------------|--------------|-----|
| Per-project tool calls | ✅ `tool_calls` table (v3, content_item_id-scoped) | ✅ `tool_calls` view |
| Cross-project SQL | ❌ Project DB is project-scoped by design | ✅ Default cross-project, opt out with `--project` |
| MCP tool telemetry | ✅ `mcp_tool_calls` table (v13) | ❌ Doesn't see MCP tools as a distinct category |
| Tool inputs as queryable JSON | ⚠️ Stored as `tool_input` text, not indexed for JSON path | ✅ DuckDB `json_extract_string` over JSON |
| Tool results with `is_error` | ✅ `is_error` column | ✅ `is_error` column |
| Raw SQL access for ad-hoc analysis | ⚠️ `sqlite3 .claude/memory.sqlite3` works but no view layer | ✅ `cq sql "..."` first-class |
| Session-level rollups | Partial | ✅ `sessions` view |
| Distills facts, resolves conflicts | ✅ Core purpose | ❌ Not a goal |
| Cross-session message grep | ❌ FTS5 is fact-scoped | ✅ `cq messages --grep` |

**Conclusion**: ClaudeMemory has the *write* path (ingest → distill → resolve → publish). cq has the *read* path (incremental sync → views → SQL). They share input data (Claude Code JSONLs) and stop there.

## Adoption Opportunities

### High Priority ⭐

#### 1. Install cq as a developer audit tool for the ClaudeMemory project itself

- **Value**: Answer two questions you currently can't answer cheaply:
  1. "Is the memory plugin being invoked when it should?" (skill activation)
  2. "Are there silent failures in `mcp__memory__*` calls?" (error rate, retry loops)
- **Evidence**: cq's three documented use cases (use-cases.md:1–200) translate directly to ClaudeMemory's situation; you ship a plugin with similar trigger ambiguity
- **Implementation**: `cargo install --git https://github.com/technicalpickles/cq` — no integration needed, runs out-of-band
- **Effort**: 5 minutes
- **Trade-off**: Adds a Rust toolchain dependency on the dev machine; DuckDB cache grows over time (rebuild via `--reindex`)
- **Recommendation**: **ADOPT** as a personal tool, not a project dependency

#### 2. Borrow cq's three reference queries for a `docs/audit-queries.md`

- **Value**: Pre-written SQL the user (or a future maintainer) can run against ClaudeMemory's own databases or via cq to validate the plugin is doing its job. Useful for releases ("did v0.10 actually move the memory.recall hit rate?") and for reproducing skill-activation regressions.
- **Evidence**: use-cases.md provides exact query templates; only the predicate names change
- **Implementation**: New doc file, three queries, ~30 minutes
- **Effort**: Low
- **Trade-off**: Maintenance — queries rot when schemas change. Mitigate by pinning to ClaudeMemory's own `tool_calls` schema where possible (stable since v3) rather than cq's view schema (younger).
- **Recommendation**: **CONSIDER** — only worth it if you're going to actually run the audits

### Medium Priority

#### 3. Expose ClaudeMemory's `tool_calls` data via a similar SQL view layer

- **Value**: ClaudeMemory's `tool_calls` table already has the data, but `sqlite3 .claude/memory.sqlite3 "SELECT ..."` requires knowing column names. A `claude-memory sql` subcommand mirroring `cq sql` would lower the barrier.
- **Evidence**: cq's `sql.rs` (intentionally unparameterized passthrough) shows the minimal viable shape
- **Implementation**: New `SqlCommand` in `lib/claude_memory/commands/`, ~50 lines using existing Sequel connection
- **Effort**: Half a day including tests
- **Trade-off**: Power-user feature. Risks footgun (drop tables) — would need read-only enforcement. Adds surface area to maintain.
- **Recommendation**: **DEFER** — only if users start asking. Right now `memory.recall_semantic` and the shortcut tools cover the curated path, and `sqlite3` covers the power-user path. The middle ground is thinly populated.

### Low Priority

#### 4. Adopt cq's `--since 7d` duration parser pattern

- **Value**: Unified relative-time parsing across `claude-memory` subcommands; ClaudeMemory has `Core::RelativeTime` for *output*, less consistency on *input*
- **Evidence**: cq's `scope.rs` parses `7d|24h|30m` uniformly across all commands
- **Implementation**: A `Core::DurationParser` value object
- **Effort**: A couple hours
- **Trade-off**: Real but minor UX win
- **Recommendation**: **DEFER** — pick up if/when adding more time-filtered commands

### Features to Avoid

- **DuckDB as a primary store**. ClaudeMemory's SQLite + extralite + Sequel choice is right for the curation/write workload (FTS5, vec0, transactional resolve). DuckDB is right for cq's analytical scan-everything workload. Don't conflate them.
- **Cross-project default scoping**. cq defaults to "all projects" with auto-narrowing to current project. ClaudeMemory's project/global split is a feature for memory recall (you don't want one project's conventions leaking into another). Keep what you have.
- **Re-indexing transcripts on every command**. cq's incremental sync exists because it has no other ingest path. ClaudeMemory's hook-driven ingest is already incremental in a different way and shouldn't be replaced.

## Trade-offs of Using cq Long-Term

- **Cache freshness**: cq syncs on every run via mtime/size fast-path. Cost: a few hundred ms on a large transcript history.
- **Lock contention**: `fs2` file lock means concurrent runs may show stale data (the design choice is "stale-but-available beats error" — fine for a query tool).
- **No curation**: cq surfaces patterns; you still have to interpret them. The "152 sessions skipped the skill" finding only matters if you act on it.
- **Schema is Claude Code's JSONL format**: if Anthropic changes the transcript shape, cq breaks until updated. Same risk ClaudeMemory has, just exposed differently.

## Implementation Recommendations

**Phase 1 — Just install it (today, 5 minutes)**:
- `cargo install --git https://github.com/technicalpickles/cq`
- Run `cq tools` and `cq sessions` to see your own usage
- Run the skill-activation query against your `mcp__memory__*` tool calls

**Phase 2 — If Phase 1 surfaces something useful (~half-day)**:
- Five concrete queries already pre-written in `docs/audit-queries.md` (activation rate, missed-memory-shaped prompts, tool ranking, error rate, result-size distribution)
- Decide if any belong as a recurring `/schedule` agent ("audit memory plugin activation weekly")

**Phase 3 — Speculative (defer indefinitely)**:
- A `claude-memory sql` subcommand if users ask for one
- A `Core::DurationParser` value object if you add another time-filtered command

## Architecture Decisions

**Preserve**:
- ClaudeMemory's two-DB scope split (project vs global)
- SQLite + extralite + Sequel as the storage stack
- Hook-driven ingest, not on-demand re-parse
- Distill → Resolve → Publish curation pipeline

**Adopt** (out-of-band, not into the codebase):
- cq itself, as a developer-side audit tool

**Reject**:
- DuckDB / cross-project default / replacing curation with raw SQL views

## Key Takeaways

1. **cq solves a different problem than ClaudeMemory**: observability vs curation. The right answer is "use both," not "absorb one into the other."
2. **The most valuable thing in the cq repo is `docs/use-cases.md`**, not the code. The three query patterns (skill activation, silent failures, context budget) are immediately runnable against your own usage.
3. **ClaudeMemory has data parity for the per-project case** (the `tool_calls` table covers the same ground), but lacks cq's cross-project SQL ergonomics. That gap is small — a `sqlite3` shell closes it for power users.
4. **Highest-leverage next step**: install cq, run the skill-activation query against `mcp__memory__*`, see whether the memory plugin is firing as expected. That's a 10-minute experiment with a real chance of surfacing a fixable issue.

## Next Steps

- [ ] Install cq locally
- [ ] Run `cq sql` audit on `mcp__memory__*` activation rate over the last 30d
- [ ] If the audit surfaces a real gap, file it and decide whether the fix lives in skill descriptions, MCP server instructions, or elsewhere
