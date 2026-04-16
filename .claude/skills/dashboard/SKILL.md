---
name: dashboard
description: Launch a local web dashboard for ClaudeMemory debugging and observability
---

# Dashboard

Launch the ClaudeMemory debugging dashboard to visualize memory system health, activity, and efficacy.

## Task

Start the dashboard web server so the user can inspect what's happening behind the scenes.

## Steps

1. Run the dashboard command:

```bash
claude-memory dashboard
```

This starts a local web server (default port 3377) and opens it in the browser.

## What the Dashboard Shows

- **Health Status**: Database health, hook configuration, vector index status
- **Overview**: Fact/entity/content counts, top predicates, entity type distribution, 30-day activity timeline
- **Activity**: Live event log of hook executions (ingest, context, sweep), memory recalls, and store extractions with timing and details
- **Facts**: Searchable fact explorer with status filtering, predicate/object search
- **Efficacy**: Recall hit rate, total results served, average results per query, top queries by result count

## Options

- `--port PORT` - Use a different port (default: 3377)
- `--no-open` - Don't auto-open the browser

## Notes

- Dashboard auto-refreshes every 30 seconds
- Activity events are recorded by hooks and MCP tools into the `activity_events` table
- The dashboard reads from both global and project databases
- Press Ctrl+C to stop the server
