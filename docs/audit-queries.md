# Audit Queries

Pre-written SQL for validating that the ClaudeMemory plugin is being invoked when it should. Run via [cq](https://github.com/technicalpickles/cq) — install with `cargo install --git https://github.com/technicalpickles/cq`.

These query Claude Code's raw transcripts (in `~/.claude/projects/`), not ClaudeMemory's own SQLite databases. That's deliberate: cq sees *all* tool calls including ones that bypassed the MCP server entirely, which is exactly the angle needed to spot activation gaps.

For server-side telemetry (counts, latencies of MCP calls that *did* land), use `claude-memory stats --tools` against ClaudeMemory's `mcp_tool_calls` table instead.

## Query 1 — Memory plugin activation rate

How often is any `mcp__memory__*` tool being called, normalized by total sessions?

```bash
cq sql "
WITH session_window AS (
  SELECT DISTINCT session_id FROM messages
),
memory_sessions AS (
  SELECT DISTINCT session_id FROM tool_calls
  WHERE name LIKE 'mcp__memory__%'
)
SELECT
  (SELECT count(*) FROM session_window) AS total_sessions,
  (SELECT count(*) FROM memory_sessions) AS sessions_with_memory_call,
  ROUND(100.0 * (SELECT count(*) FROM memory_sessions)
        / NULLIF((SELECT count(*) FROM session_window), 0), 1) AS pct
" --since 30d --table
```

**Why it matters**: a low percentage doesn't mean the plugin is broken — many sessions don't need memory. It's a denominator for the next two queries.

## Query 2 — Sessions that asked memory-shaped questions but never called memory

The most useful query. Surfaces user prompts where memory *should* have been the obvious tool, but Claude went elsewhere (Read, Grep, Bash) instead.

```bash
cq sql "
WITH memory_sessions AS (
  SELECT DISTINCT session_id FROM tool_calls
  WHERE name LIKE 'mcp__memory__%'
)
SELECT
  m.session_id,
  m.timestamp,
  left(m.text, 200) AS user_prompt
FROM messages m
LEFT JOIN memory_sessions ms ON m.session_id = ms.session_id
WHERE m.type = 'user'
  AND ms.session_id IS NULL
  AND (
    m.text ILIKE '%why did we%'
    OR m.text ILIKE '%what convention%'
    OR m.text ILIKE '%how do we usually%'
    OR m.text ILIKE '%what did we decide%'
    OR m.text ILIKE '%architecture%'
    OR m.text ILIKE '%what''s the pattern%'
  )
ORDER BY m.timestamp DESC
" --since 30d --table --limit 30
```

**What to do with results**: each row is a candidate for either (a) a tightening of MCP server instructions / skill descriptions, or (b) confirmation that the question genuinely didn't need memory and the keyword filter is too loose.

## Query 3 — Which memory tools actually get called?

```bash
cq sql "
SELECT
  name AS tool,
  count(*) AS invocations,
  count(DISTINCT session_id) AS sessions
FROM tool_calls
WHERE name LIKE 'mcp__memory__%'
GROUP BY name
ORDER BY invocations DESC
" --since 30d --table
```

**Expected shape**: `mcp__memory__recall`, `mcp__memory__conventions`, `mcp__memory__decisions` should dominate. Tools that never fire (`memory_fact_graph`, `memory_explain`, `memory_search_concepts`, `memory_facts_by_*`) might have description/triggering issues — same pattern as cq's "skill audit" use case.

## Query 4 — Error rate per memory tool

```bash
cq sql "
SELECT
  tc.name AS tool,
  count(*) AS calls,
  sum(CASE WHEN tr.is_error THEN 1 ELSE 0 END) AS errors,
  ROUND(100.0 * sum(CASE WHEN tr.is_error THEN 1 ELSE 0 END)
        / count(*), 1) AS pct_errors
FROM tool_calls tc
JOIN tool_results tr ON tc.tool_use_id = tr.tool_use_id
WHERE tc.name LIKE 'mcp__memory__%'
GROUP BY tc.name
ORDER BY errors DESC
" --since 30d --table
```

**Why it matters**: a memory tool returning errors is much worse than not firing — Claude sees the failure and learns to avoid that tool. Triage anything above ~5%.

## Query 5 — Result-size distribution (context budget hygiene)

```bash
cq sql "
SELECT
  tc.name AS tool,
  count(*) AS calls,
  MIN(length(tr.content)) AS min_chars,
  ROUND(AVG(length(tr.content))) AS avg_chars,
  MAX(length(tr.content)) AS max_chars
FROM tool_calls tc
JOIN tool_results tr ON tc.tool_use_id = tr.tool_use_id
WHERE tc.name LIKE 'mcp__memory__%'
GROUP BY tc.name
ORDER BY avg_chars DESC
" --since 30d --table
```

**Why it matters**: ClaudeMemory exposes a `compact: true` option that drops receipts for ~60% smaller responses. If averages are large, either the compact flag isn't being passed by callers or the tools that don't accept it are dumping too much.

## When to re-run

- Before each release — does the new version improve activation rate or reduce errors?
- After meaningful changes to MCP server instructions / skill descriptions
- If a user reports "the memory plugin doesn't seem to do anything" — Query 2 will usually surface the gap concretely

## Related

- Source for the methodology: `docs/influence/cq.md`
- Server-side telemetry alternative: `claude-memory stats --tools --since 30`
- cq schema reference: `cq schema --examples`
