# ClaudeMemory Plan (for Claude Code)
Turn-key Ruby gem providing Claude Code with instant, high-quality, long-term, self-managed memory using **Claude Code Hooks + MCP + Output Style**, with **minimal dependencies** (SQLite by default).

This file is designed to be handed to Claude Code so it can iteratively implement the project end-to-end. Follow the milestones in order, keep commits small, and keep the project runnable at every step.

---

## North Star
**ClaudeMemory** continuously ingests Claude Code transcripts, distills them into durable “Facts” with provenance and time validity, resolves contradictions into **supersession** or **conflicts**, and exposes memory via:
- **Automated ingestion + sweep** using Claude Code hooks
- **On-demand recall/explain** via an **MCP server**
- A **project Output Style** that encourages memory-aware behavior and consistent formatting

---

## Success criteria (MVP)
1) `claude-memory init` creates a working setup in a repo:
   - local SQLite DB
   - sample Claude Code hooks config snippet (Stop + SessionStart + PreCompact + SessionEnd + Notification idle_prompt)
   - Output Style file template
   - MCP server config instructions
2) When Claude Code runs in the repo, hooks trigger:
   - **ingest** on Stop + safety events
   - **sweep** on idle_prompt + safety events
3) ClaudeMemory can **publish a thin “Current Truth Snapshot”** into Claude Code memory files:
   - generates `.claude/rules/claude_memory.generated.md` (and optional path-scoped rule files)
   - top-level `.claude/CLAUDE.md` includes an `@.claude/rules/claude_memory.generated.md` import
   - snapshot stays concise (decisions/conventions/constraints/conflicts)
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

## Repository structure (target)
```
claude_memory/
  lib/
    claude_memory.rb
    claude_memory/
      version.rb
      config.rb
      store/
        sqlite_store.rb
        migrations.rb
      ingest/
        delta_cursor.rb
        transcript_reader.rb
      distill/
        distiller.rb
        null_distiller.rb
        json_schema.md
        prompts/
      resolve/
        predicate_policy.rb
        resolver.rb
      index/
        lexical_fts.rb
      mcp/
        server.rb
        tools.rb
      sweep/
        sweeper.rb
      cli.rb
      templates/
        hooks.example.json
        output-styles/
          memory-aware.md
  exe/
    claude-memory
  spec/
  plan.md
  README.md
  LICENSE
  Gemfile
  claude_memory.gemspec
```

---

## Implementation principles
- **Ship thin vertical slices**: ingest → store → recall in smallest increments.
- **Idempotency** is sacred: re-running ingest must not duplicate.
- **Determinism first**: resolver rules should be consistent without LLM judgment.
- **Time-bounded sweep**: sweep must accept a `--budget` and stop within it.
- **Explainability**: every recalled statement can point back to receipts.
- **Minimal deps**: prefer stdlib; required external gems should be few.

---

## Glossary
- **Content**: immutable evidence (transcript text + metadata)
- **Delta**: only new transcript content since last ingest
- **Entity**: identity-resolved “thing” (repo/module/person/service)
- **Fact**: atomic assertion with validity window + status + confidence
- **Provenance**: receipts: links from facts to content excerpts
- **Supersession**: new fact replaces old fact for the same slot
- **Conflict**: overlapping contradictory facts without supersession signal
- **Sweep**: maintenance/pruning/compaction process

---

## Milestones and tasks

### Milestone 0: Bootstrap the gem skeleton (1–2 commits)
**Goal:** A runnable Ruby gem with CLI entry point and tests.

Tasks
- Create gem scaffold (`bundle gem claude_memory`) if not already.
- Add `exe/claude-memory` that calls `ClaudeMemory::CLI`.
- Add RSpec (or Minitest) test harness.
- Add basic `README.md` describing purpose and MVP commands.

Acceptance checks
- `bundle exec rspec` passes (even if only a dummy test)
- `bundle exec exe/claude-memory --help` prints help

---

### Milestone 1: SQLite Store + schema (2–4 commits)
**Goal:** Persist content, cursors, entities, facts, provenance, conflicts.

Design decisions
- Store is a single SQLite file (default `.claude_memory.sqlite3` in repo root, configurable).
- Use a minimal migration mechanism (Ruby-based schema creator on first run).

Tables (MVP)
- `meta`: key/value (db_version, created_at)
- `content_items`: id, source, session_id, transcript_path, occurred_at, ingested_at, text_hash, byte_len, raw_text (or chunk storage), metadata_json
- `delta_cursors`: id, session_id, transcript_path, last_byte_offset, updated_at
- `entities`: id, type, canonical_name, slug, created_at
- `entity_aliases`: id, entity_id, source, alias, confidence
- `facts`: id, subject_entity_id, predicate, object_entity_id, object_literal, datatype, polarity, valid_from, valid_to, status, confidence, created_from, created_at
- `provenance`: id, fact_id, content_item_id, quote, attribution_entity_id, strength
- `fact_links`: id, from_fact_id, to_fact_id, link_type
- `conflicts`: id, fact_a_id, fact_b_id, status, detected_at, notes

Tasks
- Implement `ClaudeMemory::Store::SQLiteStore`:
  - open DB, ensure schema, basic CRUD helpers
  - JSON encode/decode helpers
- Implement migrations:
  - `ensure_schema!` checks meta/db_version and creates tables if missing
- Implement store methods needed later:
  - `upsert_content_item(...)`
  - `get_delta_cursor(session_id, transcript_path)`
  - `update_delta_cursor(...)`
  - `facts_for_slot(subject_id, predicate)`
  - `insert_fact(...)`, `update_fact(...)`
  - `insert_provenance(...)`
  - `insert_conflict(...)`

Acceptance checks
- `claude-memory db:init` creates DB file and schema
- Running twice is idempotent

---

### Milestone 2: Transcript delta ingestion (2–4 commits)
**Goal:** Ingest transcript deltas using transcript_path + session_id.

Process flow
- CLI receives `--transcript_path` and `--session_id`.
- Read file size, compare to stored cursor offset.
- If file shrank (compaction/rotate), reset offset to 0.
- Read only new bytes from last offset.
- Store a `content_item` with delta payload and metadata.
- Update cursor offset.

Tasks
- Implement `Ingest::TranscriptReader.read_delta(path, from_offset)`
- Implement CLI command: `claude-memory ingest --source claude_code --session_id ... --transcript_path ...`
- Store `content_item` record with occurred_at/ingested_at now.

Acceptance checks
- No-change ingest does nothing
- Appending text creates a new content_item and cursor update
- Reset behavior when file shrinks works

---

### Milestone 3: Lexical index for recall (MVP) (2–5 commits)
**Goal:** Provide fast search without embeddings.

Preferred: SQLite FTS5 (fallback to pure Ruby index if needed)

Tasks
- Implement `Index::LexicalFTS`:
  - `index_content_item(id, text)`
  - `search(query, limit) => ids`
- Implement `claude-memory search "query"` for debugging.

Acceptance checks
- Search returns recently ingested deltas containing query terms

---

### Milestone 4: Distiller interface + NullDistiller (2–4 commits)
**Goal:** Define extraction contract; ship with stub distiller.

Extraction schema (v1)
- entities: [{type, name, aliases?, confidence?}]
- facts: [{subject, predicate, object, polarity, confidence, quote, strength, time_hint, decision_ref?}]
- decisions: [{title, summary, status_hint, emits_fact_indexes}]
- signals: [{kind, value}]

Tasks
- Implement `Distill::Distiller` interface
- Implement `Distill::NullDistiller` with minimal heuristics
- Document schema in `json_schema.md`

Acceptance checks
- Distill returns an Extraction object even without LLM

---

### Milestone 5: Resolver (truth maintenance) (3–6 commits)
**Goal:** Deterministic equivalent/additive/supersession/conflict rules.

Tasks
- Implement `PredicatePolicy` registry
- Implement `Resolve::Resolver.apply(extraction, occurred_at:)`
- Persist facts, provenance, fact_links, conflicts

Acceptance checks
- Contradiction without explicit replace creates conflict
- Explicit replace/switch/no longer triggers supersession and closes old validity

---

### Milestone 6: Recall + Explain (CLI) (2–4 commits)
**Goal:** Human-usable recall and receipts.

Tasks
- `claude-memory recall "query"` returns facts + receipts + conflicts
- `claude-memory explain FACT_ID` returns provenance receipts
- `claude-memory changes --since ...` basic support

Acceptance checks
- Recall returns canonical facts + receipts after a few turns
- Explain prints receipts

---

### Milestone 7: Sweep mechanics (2–5 commits)
**Goal:** Maintenance runs quickly and safely via hooks.

Tasks
- Implement `Sweep::Sweeper.run!(budget_seconds:)`
- CLI: `claude-memory sweep --budget 5s`

Acceptance checks
- Sweep honors budget, safe to run repeatedly

---

### Milestone 8: MCP server (3–6 commits)
**Goal:** Provide memory tools to Claude Code.

Tools (MVP)
- memory.recall, memory.explain, memory.changes, memory.conflicts, memory.sweep_now, memory.status

Tasks
- Implement MCP server + tools
- CLI: `claude-memory serve-mcp`

Acceptance checks
- Server starts, tools return compact JSON

---

### Milestone 9: Claude Code hooks templates (2–3 commits)
**Goal:** Turn-key automation configuration.

Templates
- Stop -> ingest
- SessionStart -> ingest catch-up
- PreCompact -> ingest flush + sweep
- SessionEnd -> ingest flush + sweep
- Notification idle_prompt -> sweep budget small

Tasks
- `claude-memory init` prints/copies templates

Acceptance checks
- Easy to apply; referenced commands exist

---

### Milestone 10: Output Style template (1–2 commits)
**Goal:** Encourage memory-aware behavior without breaking coding guidance.

Tasks
- Provide `memory-aware.md` with `keep-coding-instructions: true`
- Installed/referenced by `init`

---

### Milestone 10.5: Publish snapshot to Claude Code memory (2–4 commits)
**Goal:** Use Claude Code’s built-in memory system as a **curated publishing layer** (thin “RAM”), while SQLite remains the truth-maintained store.

Key Claude Code memory behaviors to lean into
- Project memory files: `./CLAUDE.md` or `./.claude/CLAUDE.md`
- Modular project rules: `./.claude/rules/*.md` (auto-loaded)
- Path-scoped rules via YAML frontmatter `paths:` globs
- Imports via `@relative/path` (depth capped), enabling a small hand-written top-level file that imports a generated snapshot
- Nested subtree memory loads lazily when Claude reads files in that subtree (useful for monorepos)

Outputs (MVP)
- `.claude/rules/claude_memory.generated.md` (generated, concise)
- Optional: `.claude/rules/claude_memory.<area>.md` files with `paths:` frontmatter for major modules (auth, deploy, etc.)
- Ensure `.claude/CLAUDE.md` (or `CLAUDE.md`) imports the generated file:
  - Add a single line: `@.claude/rules/claude_memory.generated.md`

Snapshot format guidance
- Keep it short, structured, and reviewable:
  - **Current Decisions**
  - **Conventions**
  - **Known Constraints**
  - **Open Conflicts**
- Prefer bullets over paragraphs; avoid dumping raw logs or long histories.

Tasks
- Add CLI: `claude-memory publish`
  - Modes:
    - `--mode shared` writes generated files under `.claude/rules/`
    - `--mode local` writes into `CLAUDE.local.md` or a local-only generated file
  - Granularity:
    - `--granularity repo` writes a single snapshot
    - `--granularity paths` writes repo + a few path-scoped rule files (optional, MVP can start with repo-only)
  - Selection:
    - default to “current canonical facts + open conflicts + recent supersessions”
    - optionally allow `--since <iso>` for “recent changes only”
- Add `init` behavior:
  - Create `.claude/rules/` if missing
  - Install a minimal `.claude/CLAUDE.md` (if user opts in) that imports the generated snapshot
  - Or print clear instructions for the import line
- Add a “no-churn” strategy:
  - Only rewrite generated files if content actually changed (hash compare) to reduce noisy diffs

Optional hook wiring (recommended)
- Publish only on “safe events”:
  - `SessionEnd` and/or `PreCompact`
  - Keep it budgeted and/or incremental (avoid running on every Stop)

Acceptance checks
- Running `publish` produces a concise snapshot that Claude Code loads automatically
- Editing files under a path-scoped rule causes that scoped memory to apply (paths mode)
- Re-running publish with no changes does not rewrite files unnecessarily


### Milestone 11: End-to-end demo + doctor (1–2 commits)
**Goal:** Verify full loop.

Tasks
- `docs/demo.md`
- `claude-memory doctor` validates DB, last ingest, and optional MCP

---

### Milestone 12: Packaging + Release hygiene (2–4 commits)
**Goal:** Make it usable by others.

Tasks
- README install + usage
- CI
- `gem build` succeeds

---

## Command surface (target)
- claude-memory init
- claude-memory publish [--mode shared|local] [--granularity repo|paths] [--since <iso>]
- claude-memory ingest --source claude_code --session_id ... --transcript_path ...
- claude-memory recall "..."
- claude-memory explain FACT_ID
- claude-memory conflicts
- claude-memory changes --since ...
- claude-memory sweep --budget 5s
- claude-memory serve-mcp
- claude-memory doctor

---

## Appendices

### Appendix A: Suggested initial predicate policies (MVP)
- convention: multi, non-exclusive
- decision: multi (by scope)
- auth_method: single, exclusive
- uses_database: single, exclusive
- deployment_platform: single, exclusive

### Appendix B: Suggested sweep defaults (MVP)
- proposed_fact_ttl_days: 14
- disputed_fact_ttl_days: 30
- content_retention_days: 30 (purge only if not referenced by provenance)
- default sweep budget: 5s (idle_prompt), 15s (session end)
