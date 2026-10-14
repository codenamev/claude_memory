# WORLD.md: claude_memory, answered six ways

This file sets direction for claude_memory: what it exists to do, what it will
not become, and how proposed work gets judged. The maintainer (codenamev) owns
it. Minerva (minerva-sky), an autonomous agent that helps maintain this project,
reads this document before proposing anything and stays inside its fences. If a
proposal conflicts with this file, the proposal is wrong.

Status: PROPOSED. Drafted 2026-09-13 as a seven-section charter. Restructured
2026-09-20 under the six headings every repo in the fleet now shares, so a loop
session or a portfolio pass finds the same answer in the same place in every
repo. Awaiting maintainer approval.

## VISION (where we hope this goes)

<!-- VAL: edit. New. The old charter said what the gem does and which bets to mature; it never said what a developer's life looks like once it works. -->

A developer opens Claude Code on a project they last touched in March and the
session already knows the stack, the conventions, the decision they argued
about for a week, and the one they reversed. Nothing was written down by hand.
Nothing false survived. The memory got there by watching, and it earned every
fact it repeats. The measure of success is a session that stops asking
questions the developer already answered, not a bigger database.

## MISSION (what we're here to do)

A Ruby gem that gives Claude Code long-term memory with no API keys and no
configuration: hooks ingest transcripts, facts are distilled with provenance,
contradictions get resolved, and a curated snapshot is published back into the
session. It exists so a developer's stack, conventions, and decisions survive
the end of a conversation without anyone maintaining a notes file by hand.

## CONSTITUTION (what rules we must obey)

The fleet's shared rules live in one place and this file links to them rather
than pasting: the [operator's constitution](https://github.com/minerva-sky/workspace/blob/master/WORLD.md#constitution-what-rules-we-must-obey).
That covers the autonomy ladder (L0 propose in an issue, L1 open a PR the
maintainer merges, L2 merge after a quiet period on green CI, L3 merge on green
CI and report in a digest), how a class gets promoted (maintainer approval on
the acceptance record) and demoted (any revert, immediately).

Local additions for claude_memory:

- Gem releases, version bumps, and schema changes are the maintainer's alone,
  whatever the class's level elsewhere.
- Stable surfaces (CLI, MCP tools, hooks, Ruby API, schema, predicate
  vocabulary) change only through the deprecation cycle in
  `docs/api_stability.md`. Update that doc in the same commit as the change.
- Schema migrations are additive and reversible. A user's memory database is
  months of accumulated judgment; a migration that loses it is a release-blocker.
- Small, auditable dependency set: Ruby 3.2+, Sequel, Extralite, and little
  else. New runtime dependencies need a written justification in the PR.
- Hooks run inside every Claude Code session. Anything on that path must be
  fast, silent on success, and never able to block or crash the host session.
- Tests accompany every behavior change. CI (`main.yml`) gates merges. The
  published gem stays small; the manifest spec guards that.
- Design-level proposals (the shape of #13 and #15) stay at the issue stage
  until the maintainer approves the direction. No implementation PR lands on
  an unapproved design.
- Review budget: the maintainer reviews at most two agent-originated pull
  requests a week from this repo. Proposals beyond that wait as issues.

Anti-goals, which are constraints wearing a different hat:

- Not a hosted service. No accounts, no sync server, no telemetry. Memory
  lives on the user's disk.
- Not a general RAG framework. It remembers a developer's working context; it
  does not index arbitrary corpora.
- Not a chat log. Raw transcripts are input, never the stored product.
- No autonomous forgetting without a surface. Decay and expiry always leave a
  ratification path the user can see (the #14 lifecycle work sets the pattern).
- No speculative abstraction. Two concrete uses before one abstraction, and no
  second storage backend until someone actually needs one.

## ROADMAP (what next)

`docs/1_0_punchlist.md` is the roadmap, and this section is its index. When the
two disagree, this file wins on scope and that file wins on sequence.

The direction, in order:

1. Truth maintenance is the product. Provenance, supersession, contested
   claims, and the corroboration gate between observations and facts are where
   depth wins. A memory that confidently repeats something false is worse than
   none.
2. The two-layer model (semantic facts plus episodic observations, 0.13+) is
   the bet worth maturing. Observations should stay cheap and noise-tolerant;
   facts should stay rare and earned.
3. Head toward 1.0.0. `docs/api_stability.md` is the contract; the punchlist is
   the path. Work that shrinks the punchlist beats work that adds surface.
4. Local first, SQLite first. Everything works offline on a laptop with the
   bundled tfidf path. Vector embeddings are an upgrade, never a requirement.
5. Evidence over vibes. Recall quality claims come from the eval and soak
   harnesses (`docs/evals.md`, `docs/soak/`), not from a demo that happened to
   work once.

Where things stand at 0.13.2: the fact lifecycle from #14 (expiring state,
ratification via CLI, MCP, and dashboard) merged as PR #16 and is unreleased.
The two design issues, #13 (provenance and authority, contested claims kept and
surfaced) and #15 (relation edges beyond supersedes), wait on the maintainer's
direction. The maintainer's own in-flight fixes (#18: the sweep's prune, the
extralite 2.15 hole, the spurious SessionStart error; #19: worktrees sharing
one database) come before any agent work that touches the same paths.

<!-- VAL: edit. What the next release is called and what it carries is the maintainer's call. -->

## AGENTS (how agents work here)

`CLAUDE.md` says how to work in this codebase: check memory before exploring,
keep `docs/api_stability.md` in step with any surface change, run the audit.
That split stays: this file says what to build, that one says how.

Improvements arrive as GitHub issues. This repo does not yet run a project
loop, and the origin and state labels below do not exist here yet; issues today
are human-originated and carry the default GitHub labels. When a loop is
configured, its issues carry the fleet's labels (`loop:quality`,
`loop:security`, `loop:deps`, `loop:research`, `loop:self`; `status:analyzed`,
`status:deferred`, `status:wont-do`, `status:blocked`), a closed
`status:wont-do` issue records the reason in its final comment, and proposals
check closed and deferred issues, and `docs/improvements.md`, before re-raising
an idea. The improvements file is the older institutional memory and still
counts.

Each change class has an autonomy level per the constitution above. Every class
starts at L0 or L1, and the current level per class is recorded on the
operator's side, not here.

## CHARTER (why this exists, what territory, what freedoms)

**Why:** because every Claude Code session starts from zero, and the cost of
that is paid in re-explained stacks, re-argued decisions, and file paths
guessed wrong. The context is all in the transcripts already. Someone has to
distill it and keep it honest.

**Territory:** <!-- VAL: edit. The old charter drew this border only by negation (the anti-goals); this states it positively. -->
claude_memory owns the memory databases (global and per-project), the hooks
that feed them, the distiller and resolver that turn transcripts into facts and
observations, the MCP tools and CLI that read and curate them, the dashboard,
and the eval and soak harnesses that measure recall. It does not own the
sessions that produce transcripts, the model that reads the snapshot, or any
corpus that is not a developer's own working context.

**Freedoms:** the agent may open issues on anything in this territory, open
PRs at the class's autonomy level, run the evals and audit against its own
dogfooding database, and propose amendments to this file.

**Constraints:** the agent never merges amendments to this file, never
releases the gem or bumps its version, and never lands a schema change or an
implementation of an unapproved design above L0.

## Amending this document

By pull request with maintainer approval, nothing else. The agent may propose
amendments; it may never merge them.
