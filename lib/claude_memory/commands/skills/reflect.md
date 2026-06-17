# Reflect

Consolidate the episodic observation log and promote corroborated observations into
durable facts. This is the manual, on-demand counterpart to the automatic Reflector
that runs during sweep — use it for a deeper pass.

## Usage

```
/reflect
/reflect --scope project
```

## Instructions

You are the Reflector for ClaudeMemory's episodic observation layer. Observations are
the "what happened" log; facts are the "what is true" store. Your job is to look across
the recent observations, find what has become a stable truth, and promote it — while
leaving one-off noise alone.

Work in three passes:

### 1. Survey

Call `memory.observations` (use `important_only: true` first for the 🔴 entries, then a
broader pass). Read the log as a narrative of what has happened in this project.

### 2. Promote corroborated observations → facts

The promotion bridge is gated: an observation must have been **corroborated** (sighted
repeatedly — `corroboration_count` ≥ the threshold) before it can become a fact. This is
deliberate: requiring repeated sightings before commitment is an anti-hallucination gate
against one-off doc/example text.

For each observation that represents a **stable, repeated truth**:

- Call `memory.promote_observation` with `observation_id`, a `predicate`
  (`decision` / `convention` / `architecture`), and an `object` that **embeds a reason**
  ("… because …", "… so that …", "to avoid …"). A bare conclusion is dead weight.
- The tool refuses observations that are not yet corroborated — do not try to force them.
  If something genuinely matters but has only been seen once, leave it; it will become
  eligible once it recurs.

Skip observations that are:

- transient (debugging steps, one-off events),
- already captured as facts (check `memory.recall` / `memory.decisions` first),
- example/illustrative text rather than a claim about *this* project.

### 3. Report

Summarize what you promoted (observation → fact) and what you intentionally left as
observations and why. Do not delete or rewrite observations — the deterministic Reflector
handles dedup/expiry during sweep; your job is the semantic judgment the regex pass can't make.

## Notes

- Promotion preserves provenance: the new fact links back to the observation's source.
- Promoted observations are marked so they are not re-suggested.
- No extra API cost — this runs inside the existing Claude Code session.
