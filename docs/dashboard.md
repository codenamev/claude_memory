# ClaudeMemory Dashboard

Local web UI for inspecting what memory knows, what it's been doing, and where
it's going wrong. Headline feature of v0.10.0.

## Quick start

```bash
claude-memory dashboard
```

Opens `http://localhost:3377` in your default browser. Reads from both the
global (`~/.claude/memory.sqlite3`) and project (`.claude/memory.sqlite3`)
databases. No write side effects from page loads — the UI is a viewer with
explicit action buttons (reject / promote / feedback) where applicable.

```bash
# Custom port
claude-memory dashboard --port 4000

# Don't auto-open the browser (e.g. running in tmux/headless)
claude-memory dashboard --no-open
```

Press `Ctrl+C` in the terminal to stop the server.

## What each panel shows

The dashboard is **feed-first**: the main view is a chronological stream of
*moments* (memory activity events), with sidebar panels giving aggregate signals.

### Sidebar — Trust

At-a-glance signals so you can answer "is memory helping?" — and "what does
it cost?" — in one look:

- **This week's moments** — count of value-producing events (recall hits,
  context injections, extractions). Includes a week-over-week delta.
- **What memory knows about you** — up to 5 global facts rendered as plain
  English. The "fingerprint" of your cross-project preferences.
- **Needs review** — open conflicts (deduped to distinct contradictions) +
  stale facts (active but not recalled in the configured window) + empty
  recalls (queries that returned nothing).
- **Token budget (30d)** *(0.11.0+)* — p50/p95/avg `context_tokens` injected
  per SessionStart over the last 30 days, with sample size. Answers "what
  does memory cost per session?" — pairs with the digest's "Context cost"
  section and `claude-memory stats --tokens`.
- **Quality score (live, 30d)** *(0.11.0+)* — 0–100 hallucination-rate
  proxy. `score = 100 - (suspect_pct + bare_pct)` where suspect = facts
  retagged as `predicate=reference` and bare = decision/convention facts
  whose object skipped the prompt-mandated reason clause. Headline is the
  live 30-day window; the underlying snapshot also exposes a `historical`
  block over all active facts for context. Returns 100 on empty stores.
- **Utilization (30d)** — of facts extracted in the last 30 days, what % has
  Claude actually surfaced via recall or context injection. Color-coded
  (green ≥40%, yellow ≥15%, red below). Hidden on fresh installs.
- **Feedback (30d)** — thumbs-up/down ratio from moments you've rated.

### Feed — Moments

Real-time stream of memory activity, classified by kind:

- `recall_hit` / `recall_empty` — `memory.recall*` calls, with top fact IDs
  resolved to their sentences. Click for full payload.
- `context_injection` — SessionStart context emitted into Claude's prompt,
  with a preview and the facts it carried. `context_skipped` when injection
  was empty.
- `extraction` — facts/entities created via `memory.store_extraction`,
  inlined with content preview.
- `hook_ingest` / `hook_sweep` — pipeline activity.

Each moment has a 👍/👎 button. Use them deliberately — the ratio feeds the
Trust panel and is a calibration signal we read against retrieval quality
benchmarks.

Filter via query params: `kinds=recall_hit`, `before=<ISO timestamp>`.

### Knowledge

Active facts grouped by predicate. Sections include:

- Decisions, Conventions, Architecture (multi-value)
- Tech stack (uses_database, uses_framework, uses_language, deployment_platform, auth_method)
- **References** (added 0.10.0) — facts auto-tagged as reference material
  by `Distill::ReferenceMaterialDetector` (LOC counts, "X is a plugin…"
  templates, author attributions). Separated from conventions to keep the
  signal-to-noise ratio of the conventions section high.

### Conflicts

Open contradictions, deduped at the display layer: identical
`(subject, predicate, object_pair)` detections collapse into one row with a
`×N` badge. The "Needs review" sidebar count uses the deduped count, not
raw rows.

Each row links to:
- Both sides of the conflict with provenance
- A bulk-reject action ("reject all rows that match this exact contradiction")
- The originating activity event

### Reuse

Most-used facts in the time window. Useful for answering "which facts are
actually doing the work?" when you suspect memory is accumulating dead weight.

### Activity (timeline)

Daily rollup of facts created, content ingested, hook events fired, and
recalls performed over the last 30 days. Click any day to drill into the
underlying events.

### Health

Four checks: global database, project database, hooks installation,
sqlite-vec coverage. Each surfaces an actionable fix string (e.g.,
"Run `claude-memory init` to install the standard hook set"). Status
escalates to the worst individual check (error > warning > healthy).

### Observations (episodic layer, 0.13.0+)

The episodic counterpart to the fact-based panels. Facts answer "what is
true"; **observations** are an append-only log of "what happened" in your
sessions. Surfaced both as a first-class sidebar panel (headline numbers)
and an Advanced → Observations tab (full detail):

- **Counts by status / kind / priority** — active vs. consolidated vs.
  expired; decision / preference / event; 🔴 important / 🟡 maybe / 🟢 info.
- **Corroboration + promotion readiness** — how many observations have been
  seen enough times (≥2, the corroboration gate) to be promotable to facts,
  and the highest corroboration count seen. Promotion is the
  anti-hallucination gate: a one-off mention never becomes a fact.
- **Compression ratio** — source content tokens ÷ observation tokens, the
  Mastra-style measure of how much the episodic log condenses raw sessions.
- **Recent timeline** — the latest observations, newest first, with their
  priority markers.

Promote a corroborated observation to a fact with `memory.promote_observation`
(or `claude-memory observations promote`), merge related ones with
`memory.consolidate_observations`, or run the `/reflect` skill for a guided
survey → consolidate → promote pass.

### Activity drill-down

Clicking any moment opens a modal with the parsed payload, prettified JSON,
and — for recall events — a "what triggered this?" correlation showing the
preceding ingest and the user prompt that motivated the recall.

### Query tester

Run `memory.recall*` queries inline and see scored results, with optional
score traces (`vec_rank`, `fts_rank`, `rrf_final`) for hybrid retrieval
debugging. Surfaces an actionable hint if FTS5 corruption is detected
(suggests `claude-memory compact`).

## When to use it

- **After any session that surprised you** — was the recall actually firing?
  Did the fact you taught get extracted? The Moments feed answers both.
- **Before promoting a fact to global** — see what's already there in the
  Knowledge panel, including dedupe siblings.
- **When `claude-memory doctor` warns about conflicts** — the Conflicts
  panel groups duplicates so you don't have to handle them one row at a time.
- **When deciding what to keep** — the Reuse panel shows which facts have
  earned their spot; everything else is staleness candidate per the
  `claude-memory stats --stale` listing.

## What it's not

- Not an editor for fact text (use `claude-memory promote` / `reject`).
- Not a replacement for the CLI — for headless / scripted use, prefer
  `claude-memory stats`, `claude-memory digest`, `claude-memory census`.
- Not a multi-user surface — bound to localhost, single-process WEBrick.
- Not a long-running service — runs in the foreground; close when done.

## Architecture

The dashboard is a thin web layer over the same `Recall`, `Conflicts`,
`Trust`, `Moments`, etc. classes the MCP server uses. Each panel is backed by
a dedicated module under `lib/claude_memory/dashboard/`:

| Panel / endpoint | Module | Responsibility |
|---|---|---|
| Trust sidebar | `Dashboard::Trust` | Weekly moments, fingerprint, utilization, feedback |
| Feed | `Dashboard::Moments` | Activity-event classification + presenter |
| Knowledge | `Dashboard::Knowledge` | Predicate-grouped fact summary |
| Conflicts | `Dashboard::Conflicts` | Dedup grouping, bulk-reject helper |
| Reuse | `Dashboard::Reuse` | Most-used-fact ranking |
| Health | `Dashboard::Health` | Four system checks with fix strings |
| Timeline | `Dashboard::Timeline` | 30-day daily rollup |
| Routing | `Dashboard::API` | HTTP-shape glue + per-endpoint formatting |

Connections are released after each request so the dashboard never holds a
WAL writer lock open across page loads.

## Related CLI

- `claude-memory digest [--since DAYS] [--output FILE]` — markdown report of
  the same Trust + Knowledge + Conflicts + Feedback signals plus
  **Context cost** (token-budget p50/p95) and **Quality** (score + rejection
  rate) sections. Suitable for email or commit-into-repo.
- `claude-memory show [--pending] [--source SOURCE]` *(0.11.0+)* — print
  what memory would inject at the next SessionStart in plain Markdown.
  Same `Hook::ContextInjector` path real sessions use, so the output
  matches what Claude actually receives. Footer reports fact count, ~token
  estimate, and char count.
- `claude-memory stats --tokens [--since DAYS]` *(0.11.0+)* — token budget
  histogram (p50/p95/avg/min/max + bucketed distribution) for SessionStart
  context injections. Same data the Trust panel's Token budget block aggregates.
- `claude-memory census [--root DIR]` — privacy-safe cross-project
  predicate vocabulary scan; pairs with the Knowledge panel for "what
  predicates does my whole tree use?".
- `claude-memory stats --stale [--stale-days N]` — list facts the dashboard
  flags as stale.
- `claude-memory dedupe-conflicts` / `reclassify-references` — one-shot
  cleanups for what the Conflicts and Knowledge → References panels surface.
- `claude-memory observations [list|promote|consolidate]` *(0.13.0+)* — the
  CLI mirror of the Observations panel: list/inspect the episodic log
  (`--kind`, `--status`, `--scope`, `--json`), promote a corroborated
  observation to a fact, or consolidate related ones. `claude-memory stats
  --observations` prints the counts summary.
