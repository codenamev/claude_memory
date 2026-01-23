# Updated ClaudeMemory Plan (for Claude Code)

## Architecture Overview

ClaudeMemory uses a **dual-database architecture**:

```
~/.claude/memory.sqlite3          # Global DB - user-wide knowledge
.claude/memory.sqlite3            # Project DB - project-specific facts
```

**Key components:**
- `Store::StoreManager` — manages both database connections
- `Recall` — queries both databases, merges results (project facts prioritized)
- `promote` command — graduates project facts to global memory
- MCP server — exposes tools that query both databases

---

## What changed from the original plan (specifically changed, not brand new)
These items are **modifications to the original plan’s approach**, driven by Claude Code’s official docs for Settings, Memory, Plugins, and Hooks.

1) **Hooks configuration now targets Claude Code Settings files**
   - Replaced “drop-in hooks template JSON” with an `init` flow that **creates/merges** hook config into:
     - `.claude/settings.json` (team/shared, committed)
     - `.claude/settings.local.json` (personal, uncommitted)

2) **Hook execution is now routed through a dedicated CLI “hook entrypoint”**
   - Instead of relying on shell parsing or external tooling (e.g. `jq`), hooks call:
     - `claude-memory hook ingest`
     - `claude-memory hook sweep`
     - `claude-memory hook publish`
   - These commands **read the hook payload JSON from stdin** and act deterministically.

3) **Hook time-bounding is explicit**
   - Hook configurations include per-hook `timeout` values, aligned with “sweep/publish should never stall coding”.

4) **Enterprise/managed environments are acknowledged**
   - The plan now includes a documented fallback when hooks are blocked (e.g., managed “hooks only” policies):
     - manual CLI workflows remain fully usable
     - `doctor` reports likely restriction states and suggests safe alternatives

5) **Publishing to Claude Code memory now supports more targets**
   - “Publish snapshot” now supports:
     - repo-shared rules import (`.claude/rules/*.md`)
     - project-local private (`CLAUDE.local.md`)
     - home-dir shared (`~/.claude/...`) with import wiring
   - Also adds an optional “nested subtree” publishing strategy for monorepos.

---

## New aspects added to the plan (and how to execute them)
The sections below describe the **newly added capabilities** and where they fit into implementation milestones.

### F) Dual-database architecture ✅ IMPLEMENTED
**Goal:** Separate global and project-specific memory into distinct databases.

**Problem**
- Single database approach conflates cross-project knowledge with project-specific facts
- Project A's decisions can pollute Project B's recall
- Need both persistent user-wide knowledge AND project-specific knowledge

**Solution: Two separate SQLite databases**

1. **Database locations**
   - **Global DB**: `~/.claude/memory.sqlite3` — user-wide knowledge that persists across all projects
   - **Project DB**: `.claude/memory.sqlite3` — project-specific facts, lives in project directory

2. **StoreManager class**
   - Manages both database connections via `Store::StoreManager`
   - Lazy initialization: databases created on first use
   - `ensure_global!`, `ensure_project!`, `ensure_both!` methods
   - `promote_fact(fact_id)` copies a project fact to global DB

3. **Recall searches both databases**
   - Queries both databases when `scope: all` (default)
   - Deduplicates by fact signature (subject:predicate:object)
   - Project facts take precedence over global facts
   - `--scope project` queries only project DB
   - `--scope global` queries only global DB

4. **Promote command for fact graduation**
   - `claude-memory promote <fact_id>` copies a project fact to global
   - Copies entity, fact, and provenance records
   - Use when user says a preference should apply everywhere

5. **MCP tools updated**
   - `memory.status` returns stats for both databases
   - `memory.promote` promotes facts via MCP
   - `memory.explain` accepts `scope` parameter

**Alignment with Organizational Memory Playbook**
- Axiom 2: Truth is temporal → extends to spatial (project context)
- Axiom 4: Provenance includes WHERE (which project/database)
- Scale 2: "Which belief is in force?" → database + scope determines applicability

---

### A) Settings-driven hook installation (instead of standalone templates)
**Goal:** Make setup “Claude-native” by writing hooks into the real settings locations Claude Code reads.

**Implementation notes (process-level)**
- `claude-memory init` should:
  1) Detect whether `.claude/settings.json` exists
  2) Merge in a `hooks` section (do not overwrite unrelated settings)
  3) Optionally add entries to `.claude/settings.local.json` when the user selects local-only behavior
  4) Use environment variables like `$CLAUDE_PROJECT_DIR` in commands where helpful
  5) Print a “what changed” summary so the user can review diffs

**Design preference**
- Keep “team-wide” automation minimal and safe:
  - ingest on Stop + safety events
  - sweep on idle_prompt + safety events
  - publish only on SessionEnd/PreCompact (optional, avoids churn)

---

### B) Hook entrypoint subcommands (stdin JSON)
**Goal:** Make hooks robust, cross-platform, and dependency-light.

**Commands**
- `claude-memory hook ingest`
- `claude-memory hook sweep`
- `claude-memory hook publish`

**Process flow**
- Claude Code runs the hook command and provides event payload JSON to stdin.
- The hook command:
  - parses stdin JSON
  - extracts `session_id`, `transcript_path`, the hook event name, and any useful metadata
  - calls the internal action (ingest/sweep/publish)
  - exits quickly with clear exit codes (0 success, non-zero on error)

**Benefits**
- Avoids `jq`
- Avoids shell quoting bugs
- Makes local testing easy (replay fixtures)

---

### C) Managed hooks restriction fallback
**Goal:** Ensure ClaudeMemory is still usable even when hooks are restricted by enterprise policy.

**Behavior**
- If hooks appear blocked/ignored:
  - user runs `claude-memory ingest` manually (or via slash command if plugin is enabled)
  - sweep/publish can be run on demand

**Doctor improvements**
- `claude-memory doctor` should:
  - verify settings file presence and hook configuration
  - warn if the environment is likely to ignore user/project hooks
  - offer the manual-mode commands as next steps

---

### D) Plugin packaging milestone (Phase 2 / Team-ready)
**Goal:** Make ClaudeMemory easy to distribute and enable across many repos.

**What the plugin adds**
- Slash commands:
  - `/claude-memory:recall`
  - `/claude-memory:publish`
  - `/claude-memory:sweep`
  - `/claude-memory:status`
- Optional: plugin-shipped MCP server config and “Memory Steward” agent/skill bundle

**Why this matters**
- Versioned distribution
- One “enable” switch in settings
- Fewer manual config steps for teams

---

### E) Expanded publishing strategies for Claude Code memory
**Goal:** Use Claude’s built-in memory system as the “thin, always-on RAM” layer.

**Publish modes**
1) `--mode shared` (repo)
   - writes `.claude/rules/claude_memory.generated.md`
   - ensures `.claude/CLAUDE.md` imports it

2) `--mode local` (repo private)
   - writes `CLAUDE.local.md` or a local-only generated file
   - safe for secrets/personal prefs

3) `--mode home` (user home)
   - writes `~/.claude/claude_memory/<project>.md`
   - project imports the home file via `@~/...` import (where appropriate)

**Granularity**
- `--granularity repo` (single snapshot)
- `--granularity paths` (optional path-scoped rules)
- `--granularity nested` (optional subtree `CLAUDE.md` snapshots for monorepos)

**No-churn**
- Publish only rewrites generated files if content changed (hash compare).

---

## Full updated end-to-end plan
This is the consolidated plan that Claude Code should execute.

---

## North Star
**ClaudeMemory** continuously ingests Claude Code transcripts, distills them into durable “Facts” with provenance and time validity, resolves contradictions into **supersession** or **conflicts**, and exposes memory via:
- **Automated ingestion + sweep** using Claude Code hooks (installed via settings)
- **On-demand recall/explain** via an **MCP server**
- **Published concise snapshots** into Claude Code’s memory files (`CLAUDE.md` / `.claude/rules/`)
- A **project Output Style** that encourages memory-aware behavior and consistent formatting

---

## Success criteria (MVP)
1) `claude-memory init` creates a working setup in a repo:
   - **Dual databases**: global (`~/.claude/memory.sqlite3`) + project (`.claude/memory.sqlite3`)
   - **merges hook config into `.claude/settings.json`** (and optionally `.claude/settings.local.json`)
   - Output Style file template
   - MCP server config in `.mcp.json`
2) When Claude Code runs in the repo, hooks trigger via the hook entrypoints:
   - **ingest** on Stop + safety events
   - **sweep** on idle_prompt + safety events
   - optional publish on SessionEnd/PreCompact
3) ClaudeMemory can **publish a thin “Current Truth Snapshot”** into Claude Code memory files:
   - generates `.claude/rules/claude_memory.generated.md` (and optional path-scoped or nested subtree snapshots)
   - `.claude/CLAUDE.md` imports the generated snapshot
4) `claude-memory recall "..."` returns relevant **canonical facts** plus at least one **receipt** per fact after a few Claude turns.
5) Contradictory beliefs do **not** overwrite silently:
   - if explicit replacement or strong provenance: create **supersedes** link and close old validity window
   - otherwise: create **conflict** record
6) Everything runs **locally by default** with minimal dependencies:
   - SQLite file DB (required)
   - No embeddings required for MVP
   - LLM distillation is pluggable (MVP can ship with a stub distiller)

---

## Non-goals (MVP)
- No full RDF/SPARQL store
- No multi-source ingestion (Slack/GitHub/etc.) beyond transcript ingestion
- No complex UI (CLI + MCP is enough)
- No mandatory background daemon (hooks drive automation)

---

## Milestones and tasks

### Milestone 0: Bootstrap the gem skeleton (1–2 commits)
Goal: runnable gem + CLI + tests.

---

### Milestone 1: SQLite Store + schema (2–4 commits)
Goal: persist content, cursors, entities, facts, provenance, conflicts.

---

### Milestone 2: Transcript delta ingestion (2–4 commits)
Goal: ingest transcript deltas using transcript_path + session_id.

---

### Milestone 3: Lexical index for recall (MVP) (2–5 commits)
Goal: fast search without embeddings (SQLite FTS preferred).

---

### Milestone 4: Distiller interface + NullDistiller (2–4 commits)
Goal: define extraction contract; ship with stub distiller.

---

### Milestone 5: Resolver (truth maintenance) (3–6 commits)
Goal: deterministic equivalent/additive/supersession/conflict.

---

### Milestone 6: Recall + Explain (CLI) (2–4 commits)
Goal: human-usable recall and receipts.

---

### Milestone 7: Sweep mechanics (2–5 commits)
Goal: time-bounded maintenance via `claude-memory sweep`.

---

### Milestone 8: MCP server (3–6 commits)
Goal: provide memory tools to Claude Code.

---

### Milestone 9 (UPDATED): Settings-driven hook installation + hook entrypoints (3–6 commits)
**Goal:** Make automation turnkey and robust.

Tasks
- Add CLI subcommands:
  - `claude-memory hook ingest`
  - `claude-memory hook sweep`
  - `claude-memory hook publish`
- Implement stdin JSON parsing for hook payloads
- Update `claude-memory init` to:
  - create/merge `.claude/settings.json` with hook definitions
  - optionally create/merge `.claude/settings.local.json`
  - install safe per-hook `timeout` values
- Ensure hook commands use project-relative paths and `$CLAUDE_PROJECT_DIR` where useful
- Extend `doctor` to validate:
  - hooks present and syntactically correct in settings
  - print manual fallback steps for managed environments

Acceptance checks
- Running `init` results in settings files Claude Code uses
- Hook entrypoints can be tested by piping in fixture JSON

---

### Milestone 10: Output Style template (1–2 commits)
Goal: encourage memory-aware behavior without breaking coding guidance.

---

### Milestone 10.5 (UPDATED): Publish snapshot to Claude Code memory (2–5 commits)
**Goal:** Treat Claude Code memory files as a curated publishing layer.

Tasks
- Add CLI: `claude-memory publish`
  - `--mode shared|local|home`
  - `--granularity repo|paths|nested`
  - optional `--since <iso>`
- Implement no-churn rewriting via hash comparison
- Ensure `.claude/CLAUDE.md` imports the generated snapshot
- Optional: path-scoped `.claude/rules/*.md` via YAML frontmatter
- Optional: nested subtree snapshot strategy for monorepos

Acceptance checks
- Claude Code automatically loads published snapshot content
- Publish does not rewrite files when unchanged

---

### Milestone 11: Dual-database architecture ✅ COMPLETE
**Goal:** Separate global and project memory into distinct databases.

Tasks ✅
- Created `Store::StoreManager` class to manage both databases
- Global DB at `~/.claude/memory.sqlite3`
- Project DB at `.claude/memory.sqlite3`
- Updated `Recall` to query both databases and merge results
- Added `promote` command and MCP tool to graduate facts to global
- Updated all CLI commands to use `StoreManager`
- Removed `--db` option from most commands (paths derived automatically)
- Added `--scope` flag to `recall`, `conflicts`, `changes`, `sweep`, `publish`

Acceptance checks ✅
- `claude-memory init` creates both databases
- `claude-memory recall` queries both, project facts prioritized
- `claude-memory promote <id>` copies fact to global DB
- `claude-memory doctor` reports status of both databases

---

### Milestone 12: End-to-end demo + doctor (1–2 commits)
Goal: verify full loop; doctor detects managed-hook limitations.

---

### Milestone 13: Packaging + Release hygiene (2–4 commits)
Goal: make it usable by others.

---

### Milestone 14 (Phase 2): Plugin packaging (optional but recommended for teams) (4–10 commits)
**Goal:** Distribute ClaudeMemory via a Claude plugin.

Tasks
- Create plugin wrapper with:
  - slash commands (`/claude-memory:*`)
  - optional bundled MCP config and agent/skill (later)
- Document enabling the plugin in settings
- Provide private marketplace instructions if needed

Acceptance checks
- Enabling plugin exposes slash commands that call your gem

---

## Command surface (updated)

### Database management
- `claude-memory db:init [--global] [--project]` — initialize databases
- `claude-memory init [--global]` — full project setup (creates both DBs, hooks, MCP config)

### Ingestion
- `claude-memory ingest --session-id ... --transcript-path ... [--db PATH]`
- `claude-memory hook ingest|sweep|publish [--db PATH]` — reads stdin JSON

### Recall & query
- `claude-memory recall "..." [--limit N] [--scope project|global|all]`
- `claude-memory search "..." [--limit N] [--scope project|global]`
- `claude-memory explain <fact_id> [--scope project|global]`
- `claude-memory conflicts [--scope project|global|all]`
- `claude-memory changes [--since ISO] [--limit N] [--scope project|global|all]`

### Maintenance
- `claude-memory sweep [--budget N] [--scope project|global]`
- `claude-memory publish [--mode shared|local|home] [--granularity repo|paths|nested] [--scope project|global]`
- `claude-memory promote <fact_id>` — copy project fact to global DB

### Services
- `claude-memory serve-mcp` — start MCP server (queries both DBs)
- `claude-memory doctor` — health check for both databases

**Database locations:**
- Global: `~/.claude/memory.sqlite3`
- Project: `.claude/memory.sqlite3`

**Scope options:**
- `project`: current project's database only
- `global`: global database only
- `all` (default for recall): both databases, project facts take precedence

---

## MCP Tools (updated)

The MCP server exposes these tools to Claude Code:

| Tool | Description |
|------|-------------|
| `memory.recall` | Search both databases for matching facts |
| `memory.explain` | Get detailed fact with provenance (requires `scope` param) |
| `memory.changes` | List recent fact changes from both databases |
| `memory.conflicts` | List open conflicts from both databases |
| `memory.sweep_now` | Run maintenance sweep on specified database |
| `memory.status` | Get stats for both global and project databases |
| `memory.promote` | Promote a project fact to global memory |

---

## Hook wiring (updated target behavior)
- Ingest backbone: Stop (plus SessionStart/PreCompact/SessionEnd safety)
- Sweep backbone: Notification idle_prompt (plus PreCompact/SessionEnd hygiene)
- Publish: optional on SessionEnd and/or PreCompact (budgeted; avoid churn)
- Hooks should call the **hook entrypoint subcommands** (stdin JSON).

---

## Appendix: Managed environment fallback
If hooks are blocked by policy:
- Run `claude-memory ingest` manually at key points
- Run `claude-memory sweep` and `claude-memory publish` on demand
- Use MCP tools for recall/explain regardless
