# Mastra Observational Memory — Influence Study

*Analysis Date: 2026-06-16*
*Source: Mastra "Observational Memory" (announcement + docs + research, Feb 2026)*
*Type: Architecture study (feature/paradigm, not a full repo clone)*
*Status: Design exploration — no code yet. Branch `claude/observational-layer-design-7662r9`.*

*Sources:*
- *[Announcing Observational Memory (Mastra blog)](https://mastra.ai/blog/observational-memory)*
- *[Observational Memory docs](https://mastra.ai/docs/memory/observational-memory)*
- *[Observational Memory research / LongMemEval](https://mastra.ai/research/observational-memory)*
- *[VentureBeat: "Observational memory cuts AI agent costs 10x..."](https://venturebeat.com/data/observational-memory-cuts-ai-agent-costs-10x-and-outscores-rag-on-long)*
- *[The Decoder: traffic-light priority system](https://the-decoder.com/mastras-open-source-ai-memory-uses-traffic-light-emojis-for-more-efficient-compression/)*

---

## Executive Summary

### What this is

Mastra Observational Memory (OM) is a **text-based, dual-agent episodic memory** for long-running agents. It compresses raw message history into a structured, append-only log of dated **observations** that lives entirely in the LLM context window — no vector or graph DB. It reports state-of-the-art LongMemEval scores (84.23% with gpt-4o; 94.87% with gpt-5-mini) at 3–6× token compression.

### Why ClaudeMemory cares

In Mastra's taxonomy, ClaudeMemory is the thing OM positions *against*: a structured **semantic** store (subject-predicate-object facts with scope, validity windows, supersession, provenance) injected **dynamically per query** via `memory.recall` and SessionStart fact injection.

The key realization from this study: **ClaudeMemory has no episodic layer at all.** Facts answer "what is true." Observations answer "what happened." OM is purely episodic; ClaudeMemory is purely semantic. An observational layer is not redundant with distillation — it is the missing half.

We already own two of OM's four moving parts in spirit:
- The **distillation pipeline** (NullDistiller + Layer-2 Claude-as-distiller) is an Observer that emits *facts* instead of a *narrative log*.
- **Resolve + Sweep** is a Reflector that operates on *facts* instead of *observations*.

The work is therefore: add a narrative episodic store, point the existing Observer/Reflector machinery at it, add a cache-stable injection mode, and — uniquely to us — bridge observations into facts via corroboration.

---

## How Mastra OM Works

### Two-block context window

1. **Observation block** — a compressed, append-only log of dated observations (decisions, key events, distilled facts from older messages). Reads like a log of decisions and actions, not documentation.
2. **Raw tail** — recent messages not yet compressed.

### The Observer

Fires when raw message tokens cross ~30k (configurable). A separate background agent compresses messages into new dated observations appended to the observation block. Each observation captures one discrete event: a user statement, an agent action, a tool-call result, or a preference expressed in passing. 3–6× compression.

### The Reflector

Fires when observations cross ~40k tokens (configurable). A separate background agent garbage-collects: combines related items, reflects on overarching patterns, and drops context that no longer matters.

### Traffic-light priority

Observations carry 🔴 (important) / 🟡 (maybe important) / 🟢 (info only). The priority is **internal** to the Observer/Reflector pipeline. When observations are presented to the main "Actor" agent, 🟡 and 🟢 are stripped — only 🔴 survives — because the priority emojis serve the memory pipeline and are visual noise to the actor.

### Prompt-cache stability (the headline win)

Because the observation block is **append-only between reflections**, the prompt prefix stays stable and every turn gets a full cache hit. Cache invalidates only on a reflection, which is infrequent. This is explicitly contrasted with RAG-style memory that re-retrieves and rewrites the prompt every turn, busting the cache and producing a variable cost curve.

### Storage

Plain text in a standard backend (Postgres / LibSQL / MongoDB), loaded directly into the context window — not pulled through embedding search.

---

## Comparative Analysis vs ClaudeMemory

| Dimension | Mastra OM | ClaudeMemory today |
|-----------|-----------|--------------------|
| Memory type | Episodic (narrative log) | Semantic (SPO facts) |
| Storage | Plain text in context window | Normalized SQLite + FTS5 + vec0 |
| Retrieval | None — log loaded wholesale | Dynamic per-query (FTS + vector RRF) |
| Compression | Observer (LLM), 3–6× | NullDistiller + Claude-as-distiller → facts |
| Consolidation | Reflector (LLM), lossy drop | Resolve (supersession) + Sweep (TTL/GC) |
| Provenance | Weak — compression is lossy | Strong — provenance receipts, lineage |
| Cache behavior | Stable append-only prefix | Per-query injection (cache-busting) |
| Cost | Two background LLM agents (extra API $) | Claude-as-distiller, zero extra API $ |

**The two systems are complementary, not competing.** OM's weakness is exactly ClaudeMemory's strength (provenance, truth maintenance) and vice versa (episodic recall, cache-stable injection).

---

## Adoption Opportunities (prioritized)

### High Priority

**A. Episodic observation store + Layer-1 Observer.** New `observations` table (schema v18); NullDistiller emits observation rows alongside facts; `memory.observations` read tool. Append-only with `consolidated_into` lineage (mirrors `fact_links`) rather than Mastra's lossy drop — preserves our provenance guarantee. Zero behavior change to facts.

**B. Cache-stable injection.** Publish `.claude/rules/claude_memory.observations.md` (append-only, dated, 🔴+plain only — 🟡/🟢 stripped as Mastra does for the actor). SessionStart injects a two-block context: Block 1 = consolidated observations (stable, cache-friendly), Block 2 = recent undistilled tail. Front-loading a stable block reduces the per-turn `memory.recall` churn that busts caching. *Honest limit:* we influence Claude Code's cache via a stable `additionalContext` prefix within a session; we don't control it. Cross-session caching remains Claude Code's domain.

**C. The observation→fact promotion bridge (unique to us).** The Reflector promotes *corroborated* observations into structured facts. An observation is low-commitment; a fact is committed truth. Requiring repeated, corroborated sightings before promotion is a natural confidence gate — and directly mitigates the documented hallucination problem where the distiller commits `uses_database`/`uses_framework` facts from one-off example text in docs (today producing reject churn). Observation-first, fact-on-corroboration makes premature hallucinated facts never commit.

### Medium Priority

**D. Automatic Reflector (free) — confirmed feasible.** A consultation with the claude-code-guide agent (2026-06-16) confirms automatic reflection is achievable with zero extra API cost, in two tiers:
- **Deterministic tier (fully autonomous, no model):** dedupe near-identical observations, drop stale 🟢 past a TTL, merge by entity/time window — pure Ruby, run shell-side inside the `PreCompact` and `SessionEnd` hooks (and the existing Sweep). This needs no model and fires automatically.
- **Semantic tier (autonomous-on-next-turn, rides the session):** at `PreCompact`, the hook injects a reflection instruction via `additionalContext` ("consolidate the observation log: combine related items, surface patterns, drop the irrelevant"). Claude Code itself performs the consolidation on its next turn, inside the existing session — no separate paid call.

See the dedicated section below for why `PreCompact` is the right trigger and what the constraints are. This **supersedes** the earlier "manual `/reflect` only" recommendation: `/reflect` remains as a manual on-demand deep pass, but reflection is now primarily automatic.

**E. Compression / cache telemetry.** Reuse the `context_tokens` telemetry on `hook_context` events (0.11.0) and the Trust/Health panels to report compression ratio and token reduction. Add a LongMemEval-style episodic/long-session suite to DevMemBench alongside the existing retrieval and truth-maintenance suites.

### Features to Avoid (from this study)

- **Two always-on background LLM agents.** Violates the standing convention against features requiring separate Anthropic API calls. Our Observer = context-hook injection (Claude-as-distiller); our Reflector = deterministic shell-side GC + `PreCompact`-injected semantic consolidation that rides the existing session (see automatic-reflection section).
- **Claude Code Routines / subagents for reflection.** Routines run as a separate scheduled cloud session (separate token budget); subagents run in their own context window (~7× token burn). Both incur extra spend — rejected for recurring reflection. Reserve them, if ever, for a one-off heavy backfill the user explicitly opts into.
- **Lossy drop on reflection.** Mastra truly discards observations ("never forgives"). We tombstone via `consolidated_into` and retain raw `content_items` — provenance is non-negotiable.
- **Replacing dynamic recall.** Augment, don't replace. Observations become a front-loaded episodic block; `memory.recall` stays for targeted lookups.

---

## Proposed Data Model (sketch)

```
observations  (schema v18)
  id, ts (event time), session_id
  body            -- dense narrative text, the observation itself
  kind            -- user_statement | agent_action | tool_result | preference | decision | event
  priority        -- 1=🔴 important, 2=🟡 maybe, 3=🟢 info  (internal pipeline signal)
  scope, project_path
  source_content_item_id   -- provenance back to the raw transcript chunk
  consolidated_into        -- Reflector lineage (mirrors fact_links supersession)
  token_count              -- for budget / compression math
  status, created_at, reflected_at
```

## Proposed Pipeline Integration

```
Transcripts → Ingest → Index (FTS5)
                   ↓
   ┌─────────────── Distill ───────────────┐
   │                                         │
 Facts (SPO, semantic)            Observations (narrative, episodic)  ← NEW
   │                                         │
 Resolve (truth maint.)          Reflect (consolidate / GC / pattern) ← NEW
   │                                         │
 Store (facts)                   Store (observations)                 ← NEW
   │                                         │
   └──────────── Promotion bridge ──────────┘
           (Reflector promotes corroborated observations → facts)
                   ↓
   Publish: stable observation block (cache-friendly) + fact snapshot
```

## Automatic Reflection in Claude Code (consultation findings, 2026-06-16)

Source: claude-code-guide agent consultation. Citations: [Hooks reference](https://code.claude.com/docs/en/hooks.md), [Subagents](https://code.claude.com/docs/en/subagents.md), [Routines / scheduled tasks](https://code.claude.com/docs/en/web-scheduled-tasks).

**What does not exist:** There is no timer-, cron-, or idle-based hook event. Hook events are lifecycle-driven only — `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`/`StopFailure`, `PreCompact`/`PostCompact`, `PreToolUse`/`PostToolUse(Failure)`, plus async signals (`FileChanged`, etc.). No hook can force a model turn or enqueue a prompt; a hook can only inject `additionalContext` that the model acts on at its *next* invocation.

**What this unlocks anyway:** `PreCompact` is the right reflection trigger because it fires precisely when the context window is filling — i.e. on *context pressure*. That is conceptually the same signal Mastra uses (Reflector fires at a ~40k-token observation threshold). So "reflect when memory gets big" maps cleanly onto "reflect when Claude Code is about to compact."

**The free automatic pattern (recommended):**
- `PreCompact` + `SessionEnd` hooks run the **deterministic** Reflector shell-side in Ruby (dedupe / TTL-drop 🟢 / merge) — fully autonomous, no model, no cost.
- `PreCompact` injects an `additionalContext` instruction that makes Claude perform the **semantic** consolidation (pattern-finding, observation→fact promotion) on its next turn, inside the existing session — no separate paid call.
- `SessionStart` injects the consolidated two-block observation log (already in recommendation B).

**Where extra cost is unavoidable (and therefore rejected):** truly autonomous *between-session* reflection on a wall clock. That requires Claude Code Routines (separate paid cloud session) or a headless `claude -p` call or a subagent (~7× tokens) — all separate spend. We accept the tradeoff: our reflection is automatic on *lifecycle events* (compaction, session boundaries), not on a wall-clock timer. For our single-developer, local-first scale this is sufficient.

## Suggested Phasing

1. Schema + Layer-1 Observer (table, NullDistiller rows, `memory.observations`).
2. Stable two-block injection; measure token/compression deltas.
3. **Automatic Reflector**: deterministic GC shell-side in `PreCompact` + `SessionEnd`/Sweep.
4. **Automatic semantic reflection**: `PreCompact` `additionalContext` consolidation instruction + observation→fact promotion bridge. Keep a manual `/reflect` skill for on-demand deep passes.

Phase 4 is where this stops being "Mastra-on-Ruby" and becomes a hybrid episodic+semantic system stronger than either alone.

## Decisions for ClaudeMemory (memory-convention format)

Per the `/study-repo` memory discipline, the following are decisions about **claude_memory itself** derived from this study — to be stored via `memory.store_extraction` (`subject=claude_memory`, `decision`/`architecture` predicate, reason clause embedded) once the memory MCP server is connected. External facts about Mastra stay in this influence doc, not in memory.

- **Decision:** claude_memory will add an episodic observation layer that *augments* (does not replace) the dynamic-recall semantic fact store — because facts answer "what is true" and observations answer "what happened," and we currently have no episodic half; recall stays for targeted lookups while observations provide a stable front-loaded narrative. (User-confirmed "augment" on 2026-06-16.)
- **Decision:** observation reflection will be automatic via the `PreCompact` and `SessionEnd` hooks rather than a manual-only skill — because Claude Code exposes no timer/cron hook, but `PreCompact` fires on context pressure (the analog of Mastra's token-threshold trigger) and rides the existing session at no extra API cost.
- **Decision:** the Reflector's deterministic GC runs shell-side in Ruby and its semantic consolidation runs via `PreCompact` `additionalContext` (Claude-as-reflector inline) — to keep automatic reflection within the no-extra-API-cost convention, explicitly rejecting Claude Code Routines and subagents because each incurs a separate token budget.
- **Decision:** reflection will tombstone superseded observations via a `consolidated_into` link rather than hard-deleting them (unlike Mastra's lossy drop) — to preserve claude_memory's provenance guarantee while still bounding context size.
- **Decision:** an observation is promoted to a structured fact only after corroboration across multiple observations — because requiring repeated sightings before commitment doubles as an anti-hallucination gate against the documented reject-churn from one-off doc/example text.

> **Pending memory ingestion (deferred 2026-06-16).** These were NOT written to the project DB in the remote design session: `.claude/memory.sqlite3` is git-LFS-backed and the container had only the pointer (no `git-lfs`, real DB not materialized), so writing would have clobbered it. Store them in a local session via `memory.store_extraction` with this payload:
>
> ```json
> {
>   "scope": "project",
>   "facts": [
>     {"subject": "claude_memory", "predicate": "decision", "object": "Add an episodic observation layer that augments (does not replace) the dynamic-recall semantic fact store, because facts answer 'what is true' and observations answer 'what happened' and we currently lack the episodic half; recall stays for targeted lookups."},
>     {"subject": "claude_memory", "predicate": "decision", "object": "Make observation reflection automatic via the PreCompact and SessionEnd hooks rather than a manual-only skill, because Claude Code exposes no timer/cron hook but PreCompact fires on context pressure (the analog of Mastra's token threshold) and rides the existing session at no extra API cost."},
>     {"subject": "claude_memory", "predicate": "decision", "object": "Run the Reflector's deterministic GC shell-side in Ruby and its semantic consolidation via PreCompact additionalContext (Claude-as-reflector inline), to keep automatic reflection within the no-extra-API-cost convention, explicitly rejecting Claude Code Routines and subagents because each incurs a separate token budget."},
>     {"subject": "claude_memory", "predicate": "decision", "object": "Tombstone superseded observations via a consolidated_into link rather than hard-deleting them (unlike Mastra's lossy drop), to preserve claude_memory's provenance guarantee while still bounding context size."},
>     {"subject": "claude_memory", "predicate": "decision", "object": "Promote an observation to a structured fact only after corroboration across multiple observations, because requiring repeated sightings before commitment doubles as an anti-hallucination gate against reject-churn from one-off doc/example text."}
>   ]
> }
> ```

## Open Questions

- **Augment vs replace recall?** Resolved: **augment** (user-confirmed 2026-06-16). Observations become a front-loaded episodic block; `memory.recall` stays for targeted lookups.
- **Automatic vs manual reflection?** Resolved: **automatic** via `PreCompact`/`SessionEnd` (deterministic GC shell-side + semantic consolidation injected for the next turn), with `/reflect` retained for manual deep passes. The only thing we forgo is wall-clock between-session reflection, which would cost extra (Routines/subagents) — deliberately rejected.
