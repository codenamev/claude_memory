# cq Analysis

*Analysis Date: 2026-04-28*
*Repository: https://github.com/technicalpickles/cq*
*Focus: Tool usefulness (not internals)*

> **Re-studied: 2026-07-09 — v0.2.1 (commit 650ca67) — CHANGED (one real net-new item).** Motion since v0.2.0 is small (5 substantive commits): a `run-cq` build/smoke skill, CI toolchain pinning + cache-artifact gitignore, CLAUDE.md/CONTEXT.md doc sync, and one fix that matters to us — **cq's SQL views now recognize `advisor()` calls (commit 81cee42).** advisor uses `server_tool_use` (call) + `advisor_tool_result` (result) content blocks instead of the standard `tool_use`/`tool_result` pair, and the result block lives in an *assistant*-type record with `content` nested as `{type, text}`, not the following user record. cq extended its type filter from `= 'tool_use'` to `IN ('tool_use', 'server_tool_use')`. **ClaudeMemory's `Ingest::ToolExtractor` (lib/claude_memory/ingest/tool_extractor.rb:51) has the *exact* pre-fix shape** — it filters `block["type"] == "tool_use"` in assistant messages only, so `server_tool_use`/advisor calls are silently absent from our `tool_calls` table (and thus `memory.facts_by_tool` attribution). That is the single net-new adoptable finding; see the dated section at the very bottom. Rejections: the run-cq smoke skill and all CI/toolchain/gitignore mechanics are Rust/DuckDB-specific and not adoptable. Prior v0.2.0 re-study preserved below.
>
> **Re-studied: 2026-06-30 — cq v0.2.0 (commit 343c092, released 2026-06-30).** The 2026-04-28 baseline below predates a versioned release (cq's first tagged release is v0.2.0). Since then cq added: subagent transcript indexing (`is_sidechain`/`agent_id`/`agent_type`/`workflow_id`, recurses into `<uuid>/subagents/*.jsonl`), a Claude Code plugin (`claude-plugin/` + marketplace) that teaches Claude to write `cq sql` audit queries, `--count-by` aggregation, `--fields` JSON-column extraction, `--offset` pagination, a `projects` subcommand, multi-source discovery (`--source`/cenv), and a batch of CLI-UX hardening (parameterized SQL, stdout/stderr split, empty-result suggestions, truncation hints). **The single highest-value finding for ClaudeMemory is the subagent-transcript gap — see the dated section at the bottom.** Original analysis preserved unchanged below.

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

---

## Re-study: 2026-06-30 — cq v0.2.0 (commit 343c092)

**Baseline:** 2026-04-28 (pre-release working tree). **Current:** v0.2.0, released 2026-06-30. **Changed:** yes — substantial. The architecture verdict from April still holds (observability vs curation; complementary, not competing; don't adopt DuckDB/cross-project-default/raw-SQL-as-curation). What follows is only what is *new* and adoptable.

### High Priority ⭐

#### R1. Verify ClaudeMemory ingests subagent transcripts — likely a real coverage gap

This is the headline finding. cq now recurses into `<project>/<session-uuid>/subagents/*.jsonl` and tags every row with `is_sidechain`, `agent_id`, `agent_type`, `workflow_id` (claude_provider.rs:245, README "Views" section). Their skill-activation use case explicitly attributes many misses to subagents: *"subagents (which may not have the skill list in their context) accounted for many of the misses."*

- **Why it matters for us:** `Ingest::Ingester#ingest` (lib/claude_memory/ingest/ingester.rb:35) consumes exactly one `transcript_path` handed in by the hook payload. It never enumerates a `subagents/` directory. So any knowledge produced *inside* a subagent run only reaches memory if Claude Code fires a Stop/SessionEnd/TaskCompleted hook carrying that subagent's transcript path. If it doesn't (cq's evidence suggests subagent activity is a non-trivial slice), **ClaudeMemory is blind to a whole class of sessions** — which is the same "is the plugin firing when it should?" question the lead is chasing, one layer down.
- **Evidence:** cq commits `capture subagent agentType from meta.json` (d865669), `recurse into subagents/ when scanning, exclude journal.jsonl` (4407e66), `recursive max_dir_mtime so Auto-sync detects deep subagent files` (9bd2f94); cq's own use-cases.md attribution.
- **Action (not a code change yet — a measurement):** run `cq sql` to count how many of *our own* `claude_memory` project sessions had subagent activity, and cross-check against which transcript paths the `content_items` table actually ingested. If there's a delta, decide whether the ingest hook payload already carries subagent paths or whether we need a `subagents/`-aware glob in the ingest path.
- **Effort:** measurement ~1h; fix (if needed) ~half-day (subagent-aware discovery + a `is_sidechain`/`agent_type` column on `content_items` for provenance).
- **Recommendation:** **INVESTIGATE FIRST.** Don't build blind — this is exactly the "survey real multi-project data before a schema change" discipline this project follows.

#### R2. `--count-by` + `--fields`: the audit ergonomics our `docs/audit-queries.md` plan wanted

cq added `--count-by <field>` (group-and-count over any column, incl. JSON input fields) and `--fields a,b` (project JSON input keys into columns) across tools/messages/sessions (commits 2e62b06, 2aa4f3f). This is the cheap version of the skill-activation audit — `cq tools Skill --count-by skill` reproduces "The Audit" use case without writing SQL.

- **Why it matters:** our April doc floated a speculative `claude-memory sql` subcommand (deferred). cq shows the lighter-weight win is *aggregation flags on existing list commands*, not a raw-SQL passthrough. If we ever surface tool/recall telemetry on the CLI, copy `--count-by` (group `mcp_tool_calls` by `tool_name`) rather than exposing SQL.
- **Effort:** low if/when we add it; for now it's a design note.
- **Recommendation:** **CONSIDER** — fold into any future `claude-memory stats --tools` enhancement; reject the raw-`sql` subcommand idea in favor of this.

### Medium Priority

#### R3. cq now ships a Claude Code plugin whose skill *teaches Claude to write the audit queries*

`claude-plugin/skills/cq/SKILL.md` + marketplace packaging (commit 3893ff8). The skill hands Claude the full schema + query cookbook so Claude reaches for cq automatically on "is my git-commit skill firing?"-shaped questions. Their README has a candid "When it doesn't fire" section (competing skills, description tuning) — the same triggering problem ClaudeMemory's `memory_guide` prompt and skill descriptions face.

- **Relevance:** we already have the analog (`memory_guide` MCP prompt, the memory-first-workflow skill). The adoptable nuance is cq's *honesty about non-activation* baked into the plugin README, and their `--examples` schema dump "designed to be consumed by AI agents building their own queries." Our `docs/audit-queries.md` (if/when written) should be phrased as agent-consumable query templates, not just human docs.
- **Recommendation:** **CONSIDER** — low effort, aligns with our `feedback_honest_evidence_public_materials` norm.

#### R4. CLI-UX hardening worth mirroring

Two concrete, low-cost patterns: (a) **parameterized queries** replacing string interpolation (commit 0e3eebe) — a security fix that retroactively validates our April "read-only enforcement / footgun" worry about any SQL surface; (b) **stdout/stderr separation** (progress/errors to stderr, data to stdout — commit 500d755) so output is pipeable. ClaudeMemory's CLI commands should keep telemetry/progress noise off stdout for the same reason. Also: empty-result contextual suggestions and `--limit` truncation hints (d46ebf6, bcc1303) — small UX wins if we touch the recall/stats commands.

- **Recommendation:** **DEFER** — pick up opportunistically; the stdout/stderr discipline is the one worth auditing now since hooks parse our stdout as JSON.

### Features to avoid (unchanged + new)

- All April "avoid" items still stand (DuckDB primary store, cross-project default, re-index-on-every-command).
- **New:** cq's multi-source/cenv discovery (`--source`, `$CENV_BASE`) solves cq's "query across remote container envs" problem. ClaudeMemory's `CLAUDE_CONFIG_DIR` override already covers our isolation need; don't generalize it into a multi-source union — our project/global scope split is the deliberate boundary.

### Bottom line

cq matured from a pre-release tool into a v0.2.0 plugin-shipping product; the one thing that should change *our* roadmap is the subagent-transcript coverage question (R1) — measure whether ClaudeMemory's hook-driven ingest is silently skipping subagent sessions before doing anything else.

---

## Re-study: 2026-07-09 — cq v0.2.1 (commit 650ca67)

**Baseline:** v0.2.0 (2026-06-30). **Current:** v0.2.1 (2026-07-07). **Changed:** yes, but narrowly — 5 substantive commits, one of which is directly adoptable. All v0.2.0 architecture verdicts stand unchanged (complementary/observability-vs-curation; reject DuckDB, cross-project default, raw-SQL-as-curation).

### High Priority ⭐

#### R5. Recognize `server_tool_use` (advisor) blocks in `ToolExtractor` — a real, currently-silent coverage gap

cq's fix `recognize advisor() calls in tool_calls/tool_results views` (commit 81cee42) documents a Claude Code transcript tool-call shape our ingest is blind to:

- **The shape:** `advisor()` invocations are emitted as a `server_tool_use` content block (the call — same `id`/`name`/`input` shape as `tool_use`) and an `advisor_tool_result` block (the result). Unlike normal tools, **both blocks live in `assistant`-type records** — the result is *not* in the following `user` record — and the result's `content` is a nested object `{type, text}`, not a plain string. Fixture: `tests/fixtures/advisor_session.jsonl` in their repo; view logic: `src/views.rs:143-210`.
- **Our gap:** `Ingest::ToolExtractor#extract_tools_from_message` (lib/claude_memory/ingest/tool_extractor.rb:43,51) returns early unless `message["type"] == "assistant"` (OK — advisor calls *are* in assistant records) and then only keeps blocks where `block["type"] == "tool_use"`. `server_tool_use` blocks fall through, so **every advisor call is absent from the `tool_calls` table**, and therefore from `memory.facts_by_tool` context attribution. `ToolFilter` would happily capture an `advisor` tool (not in `DEFAULT_SKIP_TOOLS`), so the only thing blocking it is the extractor's type check.
- **The fix (mirror cq exactly):** change the guard at tool_extractor.rb:51 from `next unless block["type"] == "tool_use"` to accept both, e.g. `next unless %w[tool_use server_tool_use].include?(block["type"])`. Optionally normalize the recorded `tool_name` to `"advisor"` for the server-tool case. This is the Ruby analog of cq's `IN ('tool_use', 'server_tool_use')`.
- **Result side:** we *don't* pair tool_results in the extractor at all today (`is_error: false` is hardcoded at tool_extractor.rb:57; the store's `insert_tool_calls` accepts a `tool_result`/`is_error` field that ingest never populates). So the `advisor_tool_result` nested-`{type,text}` unwrap cq had to do is **not** currently our problem — only the call-side block matters until/unless we start ingesting tool results.
- **Effort:** S (one-line guard change + a fixture-backed spec asserting an advisor `server_tool_use` block lands in `tool_calls`). Verify per the project's installed-gem discipline: `rake install`, fire a real hook, confirm the row exists — specs assert against the working tree, hooks run the installed gem.
- **Trade-off:** advisor() is a niche server-side tool, so absolute volume is low; the win is correctness/consistency of the `tool_calls` telemetry, not a large data recovery. Low risk — additive, no schema change.
- **Recommendation:** **ADOPT.** Cheap, correct, and it closes the same "is the telemetry seeing everything it should?" gap cq just closed. File as an improvement.

### Rejections (Rust/DuckDB/CI-specific, not adoptable)

- **`run-cq` build/smoke skill** (commit 89f5491, `.claude/skills/run-cq/SKILL.md` + `smoke.sh`). A self-contained skill that builds the release binary if missing and drives every subcommand against an isolated `CQ_CACHE_DIR`, asserting exit codes incl. one deliberate error path. The *pattern* (hermetic smoke driver that shells the real binary and checks exit codes) is sound, but ClaudeMemory already covers this ground with rspec, evals, the `debug-memory`/`setup-memory` skills, and the documented "fire a real hook, check `activity_events`" smoke test. Not net-new for us. Note only: if we ever want a one-shot end-to-end CLI smoke skill, cq's frontmatter-lists-the-verbs + isolated-cache + assert-the-error-path structure is a decent template.
- **CI toolchain pinning** (Rust 1.96.0), **gitignore of `index.duckdb`/`index.lock`** stray cache artifacts, **release-please automation** — all DuckDB/Rust/GitHub-Actions mechanics with no Ruby/SQLite analog worth importing.

### Audit-query surface

No new use-cases or audit queries beyond one advisor lookup added to their plugin SKILL.md (`SELECT ... FROM tool_calls WHERE name = 'advisor'`). Nothing to add to our `docs/audit-queries.md` beyond noting that once R5 lands, an advisor-activation audit becomes possible against our own `tool_calls` table.

### Bottom line

One adoptable item this cycle: teach `ToolExtractor` to recognize `server_tool_use`/advisor blocks (R5), the direct Ruby mirror of cq's 81cee42. Everything else is Rust/DuckDB/CI plumbing. The subagent-coverage investigation (R1, still open from v0.2.0) remains the larger outstanding question.
