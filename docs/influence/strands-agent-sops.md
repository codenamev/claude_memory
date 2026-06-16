# Strands Agent SOPs Analysis

*Analysis Date: 2026-05-01*
*Source: AWS Open Source Blog — "Introducing Strands Agent SOPs: Natural Language Workflows for AI Agents"*
*URL: https://aws.amazon.com/blogs/opensource/introducing-strands-agent-sops-natural-language-workflows-for-ai-agents/*
*Type: Article (not a repo). PyPI package `strands-agents-sops`, GitHub `strands-agents/agent-sop`.*

---

## Executive Summary

**Agent SOPs** are markdown-based "Standard Operating Procedures" that wrap an AI agent's instructions in a parameterized, RFC-2119-keyworded, chain-able format. Amazon teams use thousands of them internally; the open-source release ships four reference SOPs (`codebase-summary`, `pdd`, `code-task-generator`, `code-assist`) and tooling to author/load them via Strands Agents, MCP prompts, Claude Skills, or raw model calls.

**Verdict for ClaudeMemory**: ClaudeMemory already implements most of what SOPs propose, under different names. Skills (`/distill-transcripts`, `/release`, `/study-repo`) *are* SOPs. The hook context injection pipeline already chains stages (ingest → distill → resolve → publish). The current distillation prompt already uses RFC-2119-ish "MUST" language for the reason-clause requirement.

The genuinely novel ideas — and the only ones worth a closer look — are:
1. **Explicit parameter contracts** at SOP entry (Required/Optional with defaults), versus our skills that take freeform `$ARGUMENTS`.
2. **Progress checkpoints + resumability** for long-running workflows (`✅ Step 1 complete` style markers the agent emits).
3. **Self-describing format spec** (`strands-agents-sops rule` command) that lets Claude author new SOPs from a description.

The rest is old news for us. **Recommendation: do not adopt the Strands library or format. Borrow two narrow ideas (resumability + explicit parameters) into `/distill-transcripts` if and only if real distillation runs are large enough to fail mid-batch.**

## What an SOP Actually Is

Per the article, an SOP is markdown with these conventions:

- **RFC 2119 keywords** (MUST / SHOULD / MAY) for behavioral control.
- **Required/Optional parameters block** with defaults — gathered from the user via natural-language dialogue at invocation time.
- **Numbered steps** the agent executes sequentially.
- **Progress annotations** the agent prints as it goes (`✅ Validated codebase path exists`).
- **Output artifacts** in a conventional `.sop/<name>/` directory, used as handoff between chained SOPs.

Example parameter declaration (the only verbatim format snippet in the article):

```
Required Parameters:
• codebase_path: Path to the codebase to analyze
Optional Parameters:
• output_dir: Directory where documentation will be stored (default: ".sop/summary")
```

Invocation surfaces:

- **Strands Agents (Python)**: `Agent(system_prompt=code_assist, tools=[editor, shell])` — SOP becomes the system prompt.
- **MCP**: SOPs registered as MCP *prompts* (the `prompts/list` + `prompts/get` channel), invoked with `@codebase-summary` in Kiro CLI / `/prompts` listing.
- **Claude Skills**: A CLI converts SOPs to Anthropic Skill format.
- **Direct LLM**: paste into a model's message and run.

Composition is **sequential chaining via artifact handoff** — `codebase-summary` writes docs, `pdd` reads them. No nesting/include directive is shown.

## How This Maps to ClaudeMemory Today

| Strands concept | Our equivalent | Status |
|---|---|---|
| Markdown SOP | `lib/claude_memory/commands/skills/*.md` (Anthropic Skills) | ✅ Have it |
| MCP prompts surface | `MCP::QueryGuide` registers `memory_guide` via `prompts/list`+`prompts/get` | ✅ Have it |
| RFC-2119 "MUST" in instructions | `distill-transcripts.md:38-43` uses MUST for reason-clause embed | ✅ Have it |
| SessionStart prompt injection | `hook_command.rb:213` writes `hookSpecificOutput.additionalContext` | ✅ Have it |
| SOP chaining via artifacts | `Ingest → Distill → Resolve → Store → Publish` (CLAUDE.md L72-79) | ✅ Have it (DB rows are the artifacts) |
| AI-assisted SOP authoring | `/skill-creator` skill | ✅ Have it |
| Format spec exposable to Claude | `strands-agents-sops rule` CLI | ⚠️ Partial — our distillation prompt is in `distill-transcripts.md`, not exposed as a tool |
| Required/Optional parameter contract | We pass `$ARGUMENTS` as freeform text | ❌ Missing |
| Progress checkpoints + resumability | `/distill-transcripts` runs end-to-end; no mid-batch checkpoint | ❌ Missing |
| Reference SOPs (`codebase-summary` etc.) | N/A — wrong domain | ❌ Not applicable |

The pattern is clear: we independently arrived at the same architecture. The two bullets in the "Missing" rows are the only candidates worth thinking about for adoption.

## Where SOPs Could Improve Distillation

### 1. Resumability for `/distill-transcripts`

**Current state.** `/distill-transcripts --limit 10` calls `memory.undistilled`, processes items one-by-one, calls `memory.mark_distilled` after each. If the run aborts mid-batch (rate limit, context exhaustion, user Ctrl-C), the items processed before the abort are marked, the rest are not. There is no explicit checkpoint file, but the DB itself is the checkpoint.

**SOPs angle.** SOPs add visible progress markers (`✅ Item 4/10 complete`) and a resume contract (`if .sop/distill/state.json exists, skip processed items`).

**Honest verdict.** Our DB-as-checkpoint already handles resumability. The visible-progress angle is a UX win for big runs but not a correctness improvement. **Do this only if we add a `--limit 100`+ workflow that users actually run.** Today nobody runs that.

### 2. Required/Optional Parameter Block in Skills

**Current state.** `/distill-transcripts` accepts `--limit N` parsed implicitly inside the skill body. Other skills accept `$ARGUMENTS` as a freeform blob. Users discover parameters by reading the skill markdown.

**SOPs angle.** Declared parameter blocks let the agent prompt the user before running ("what's the codebase_path?"), and let tooling (an SOP registry, MCP prompt list) introspect the contract.

**Honest verdict.** Anthropic Skills allow YAML frontmatter that already does this (`argument-hint`, parameter docs). We are under-using that frontmatter. **Cheap, safe improvement.** Adding a `Parameters:` block to the top of `distill-transcripts.md`, `release.md`, `study-repo.md` (and friends) costs ~10 minutes per skill and makes them self-documenting to both humans and any agent reading them.

### 3. Format-Spec-As-Tool for Authoring

**Current state.** `/skill-creator` exists. It has the format knowledge in its prompt body.

**SOPs angle.** `strands-agents-sops rule` is a CLI command that prints the SOP format spec to stdout, so any agent can `Bash` it and learn how to author one. This is a small but real ergonomic win — the spec lives in one place, not duplicated into every "make a new skill" prompt.

**Honest verdict.** Marginal. We don't have a sprawl of skill-authoring locations to consolidate. **Defer indefinitely** unless we start writing many more skills.

## What NOT to Adopt

- **The Python package itself.** Strands is a Python agent framework; we're a Ruby gem. No reuse path.
- **The `.sop/<name>/` artifact directory convention.** We persist via DB rows + `claude_memory.generated.md`. Adding a parallel filesystem artifact tree would just add cleanup burden and an out-of-DB state to reconcile.
- **The four reference SOPs (`codebase-summary` etc.).** Wrong domain — they're for code-workflow agents, not memory pipelines. Nothing to lift.
- **Renaming "skills" to "SOPs" in our docs.** Anthropic's term is *Skills*; that's the term Claude Code users know. Adopting Amazon's term creates confusion for zero gain.
- **Sequential-only chaining as an enforced pattern.** Our pipeline already chains, but we should keep room for parallel work (e.g., NullDistiller layer 1 runs synchronously in the ingest hook regardless of layer 2/3). SOP chaining is sequential by construction.

## Adoption Opportunities

### Medium Priority

#### 1. Parameter blocks in skill frontmatter

- **Value**: Self-documenting skills; Claude can prompt the user for missing parameters instead of guessing from `$ARGUMENTS`. Better intro-spectability for any future skill registry UI.
- **Evidence**: Article's `Required Parameters / Optional Parameters` block — only structural snippet quoted verbatim; Anthropic Skills format already supports `argument-hint` and similar fields we under-use.
- **Implementation**: Add `## Parameters` section near the top of `lib/claude_memory/commands/skills/distill-transcripts.md`, `release.md`, `study-repo.md`, `quality-update.md`, `improve.md`. Format: bullet list with `name: description (default: …)`.
- **Effort**: ~30 minutes total across all skills.
- **Trade-off**: Tiny doc maintenance burden; no runtime cost.
- **Recommendation**: ADOPT (low-cost, high-clarity).

### Low Priority

#### 2. Progress markers + explicit checkpoint file in `/distill-transcripts`

- **Value**: Better UX on long runs (users see progress); cleaner resume after mid-batch failure.
- **Evidence**: Article shows `✅ Validated codebase path exists` style output; SOPs document progress to support resumability.
- **Implementation**: Have `/distill-transcripts` print `[N/M] item <docid> → K facts` after each `memory.mark_distilled`. Optionally, write `.claude/distill_state.json` with `last_processed_content_id` so a re-run can resume.
- **Effort**: ~1 hour for stdout markers; ~3 hours including a state file with safe-resume semantics.
- **Trade-off**: State file adds another moving piece; DB already handles correctness, so this is purely UX. Not worth doing until somebody actually runs `/distill-transcripts --limit 100+` regularly.
- **Recommendation**: DEFER. Revisit if dashboard/usage data shows multi-hundred-item distillation runs.

#### 3. SOP-style format spec exposed as MCP prompt

- **Value**: Lets a future "make me a new skill" agent fetch our skill format spec via MCP `prompts/get` instead of duplicating it.
- **Evidence**: Article's `strands-agents-sops rule` command — same idea.
- **Implementation**: Add a `skill_authoring_guide` prompt to `MCP::QueryGuide` alongside `memory_guide`.
- **Effort**: ~1 hour.
- **Trade-off**: Solves a problem we don't yet have. We have one skill-authoring location (`/skill-creator`).
- **Recommendation**: DEFER until skill sprawl is a real problem.

### Features to Avoid

- **Generic "SOP runtime" abstraction** layered over our skills: pure ceremony. Anthropic Skills already give us the runtime.
- **`.sop/<name>/` artifact filesystem** parallel to our DB: doubles state, doubles cleanup, halves the value of having a curated SQLite store.
- **Adopting the term "SOP" anywhere user-facing**: term collision with Skills.

## Implementation Recommendations

**Phase 1 (do this in any 0.12.x release).** Add `## Parameters` blocks to the existing skill markdowns. ~30 minutes. Closes the only meaningful gap from this study.

**Phase 2 (defer).** Progress markers + `.claude/distill_state.json` checkpoint, only after we see real users running large distillation batches.

**Phase 3 (avoid unless triggered).** MCP-prompt-exposed skill format spec, only after we have ≥3 skill-authoring locations to consolidate.

## Architecture Decisions

**Preserve.** Our DB-as-checkpoint substrate, our use of Anthropic Skills as the SOP equivalent, our `additionalContext` injection on SessionStart, our distillation prompt's explicit reason-clause requirement.

**Adopt.** Explicit parameter declarations in skill frontmatter (Phase 1).

**Reject.** Strands Python package, `.sop/` artifact tree, generic SOP runtime abstraction, terminology adoption ("SOP" → user-facing).

## Key Takeaways

1. **We are already doing this.** Strands describes a class of patterns — markdown instructions, MCP prompts, parameterized invocation, sequential chaining, RFC-2119 vocabulary — that ClaudeMemory has independently. The existence of Strands is *validation*, not a roadmap.
2. **Anthropic Skills ≈ Strands SOPs.** Same idea, different label, different ecosystem. Don't refactor toward Strands; we'd just be renaming Skills.
3. **One narrow win.** Explicit parameter declarations in skill frontmatter cost ~30 minutes and make our skills self-documenting. Worth doing.
4. **One narrow defer.** Progress markers + checkpoint files in `/distill-transcripts` are real UX improvements *if* anyone runs distillation at scale; today nobody does. Revisit when the data says to.
5. **No deep architectural shifts.** Nothing in the article justifies a redesign of our distillation, storage, or prompting pipelines.
