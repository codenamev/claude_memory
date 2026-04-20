# Distill Transcripts

Extract structured knowledge (facts, entities, decisions) from undistilled transcript content and persist it to long-term memory.

## Usage

```
/distill-transcripts
/distill-transcripts --limit 10
```

## Instructions

You are a knowledge extraction specialist. Your job is to read raw transcript content and extract structured facts, entities, and decisions, then persist them via the memory.store_extraction MCP tool.

### Step 1: Get Undistilled Content

Call `memory.undistilled` with `limit: 10` to get transcript content that hasn't been processed yet.

If no items are returned, report "No undistilled content found" and stop.

### Step 2: Extract Knowledge (per item)

For each content item, carefully read the raw_text and extract:

**Entities** — Named things mentioned:
- type: database, framework, language, platform, repo, module, person, service
- name: Canonical name (e.g., "PostgreSQL" not "postgres")
- confidence: 0.0-1.0

**Facts** — Knowledge learned:
- subject: Entity name or "repo" for project-level facts
- predicate: prefer a predicate from the canonical vocabulary defined in
  `lib/claude_memory/resolve/predicate_policy.rb` (convention, decision,
  architecture, uses_framework, uses_language, uses_database,
  deployment_platform, auth_method). Other snake_case predicates are
  accepted but fall through to the default multi-value policy.
- object: The value. For **decision** and **convention** predicates, the object
  MUST embed the reason — append a compact "— because ..." / "so that ..." /
  "to avoid ..." clause, or include the trigger ("caused by X", "breaks when Y").
  Bare conclusions without rationale are dead weight once they become stale:
  a fact with a reason is recoverable, a fact without one is not. Architecture
  facts should note the design *trade-off* if non-obvious.
- confidence: 0.0-1.0
- quote: Source excerpt (max 200 chars)
- strength: "stated" (explicitly said) or "inferred" (implied)
- scope_hint: "project" (this project only) or "global" (all projects)

Examples of the reasoning requirement:
- ❌ Bare: "Configuration class has instance methods only"
- ✅ With why: "Configuration class has instance methods only — stub with instance_double + allow(Configuration).to receive(:new) because class-level stubbing breaks isolation"
- ❌ Bare: "MCP tools return dual content + structuredContent"
- ✅ With why: "MCP tools return dual content + structuredContent so human-readable summaries and machine-parseable JSON ship in the same response; compact mode omits receipts for ~60% smaller payloads"

**Decisions** — Choices made:
- title: Short summary (max 100 chars)
- summary: Full description
- status_hint: "accepted", "proposed", or "rejected"

### What to Extract

- Technology choices ("we use PostgreSQL", "switched to React")
- Conventions ("always use frozen_string_literal", "test files go in spec/")
- Architectural decisions ("API uses REST", "auth via JWT")
- Preferences ("prefer 4-space indent", "use Standard Ruby")
- Project structure ("migrations in db/migrations/", "commands in commands/")

### What to Skip

- Debugging steps and transient errors
- Code output and tool observations
- File contents that were just being read
- Ephemeral task details ("fix this test", "run the linter")
- Information already obvious from the codebase itself

### Scope Detection

Set scope_hint to "global" when the text contains signals like:
- "I always...", "in all my projects...", "my preference is..."
- "everywhere", "across all repos"

Default to "project" for everything else.

### Step 3: Persist Each Extraction

For each content item with extracted knowledge:

1. Call `memory.store_extraction` with the entities, facts, and decisions arrays
2. Call `memory.mark_distilled` with the content_item_id and facts_extracted count
3. If nothing was extracted, still call `memory.mark_distilled` with facts_extracted: 0

### Step 4: Report

Return a summary:

```
## Distillation Complete

- Items processed: N
- Facts extracted: N
- Entities found: N
- Decisions captured: N
- Items skipped (nothing to extract): N
```

### Guidelines

- Process items one at a time to keep extractions focused
- Use `compact: true` on `memory.undistilled` for smaller responses
- Be conservative — only extract facts you're confident about (>0.7)
- Prefer "stated" strength over "inferred" unless clearly implied
- Do NOT fabricate facts — only extract what's actually in the text
- If text is mostly code/tool output with no conversational knowledge, mark as distilled with 0 facts
- Prefer one fact-with-reason over two facts-without. Length cost is worth it — stale facts with reasoning are recoverable, stale facts without are dead weight
