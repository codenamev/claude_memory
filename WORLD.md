# WORLD.md — project charter

This file sets direction for claude_memory: what it exists to do, what it will
not become, and how proposed work gets judged. The maintainer (codenamev) owns
it. Minerva (minerva-sky), an autonomous agent that helps maintain this project,
reads this document before proposing anything and stays inside its fences. If a
proposal conflicts with this file, the proposal is wrong.

Status: PROPOSED. Drafted 2026-09-13, awaiting maintainer approval.

## Purpose

A Ruby gem that gives Claude Code long-term memory with no API keys and no
configuration: hooks ingest transcripts, facts are distilled with provenance,
contradictions get resolved, and a curated snapshot is published back into the
session. It exists so a developer's stack, conventions, and decisions survive
the end of a conversation without anyone maintaining a notes file by hand.

## Direction

- Truth maintenance is the product. Provenance, supersession, contested claims,
  and the corroboration gate between observations and facts are where depth
  wins. A memory that confidently repeats something false is worse than none.
- The two-layer model (semantic facts plus episodic observations, 0.13+) is the
  bet worth maturing. Observations should stay cheap and noisy-tolerant; facts
  should stay rare and earned.
- Local first, SQLite first. Everything works offline on a laptop with the
  bundled tfidf path. Vector embeddings are an upgrade, never a requirement.
- Head toward 1.0.0. `docs/api_stability.md` is the contract; the punchlist in
  `docs/1_0_punchlist.md` is the path. Work that shrinks the punchlist beats
  work that adds surface.
- Evidence over vibes. Recall quality claims come from the eval and soak
  harnesses (`docs/evals.md`, `docs/soak/`), not from a demo that happened to
  work once.

## Constraints

- Stable surfaces (CLI, MCP tools, hooks, Ruby API, schema, predicate
  vocabulary) change only through the deprecation cycle in
  `docs/api_stability.md`. Update that doc in the same commit as the change.
- Schema migrations are additive and reversible. A user's memory database is
  months of accumulated judgment; a migration that loses it is a release-blocker.
- Small, auditable dependency set: Ruby 3.2+, Sequel, Extralite, and little
  else. New runtime dependencies need a written justification in the PR.
- Hooks run inside every Claude Code session. Anything on that path must be
  fast, silent on success, and never able to block or crash the host session.
- Tests accompany every behavior change. CI (main.yml) gates merges. The
  published gem stays small; the manifest spec guards that.

## Anti-goals

- Not a hosted service. No accounts, no sync server, no telemetry. Memory
  lives on the user's disk.
- Not a general RAG framework. It remembers a developer's working context; it
  does not index arbitrary corpora.
- Not a chat log. Raw transcripts are input, never the stored product.
- No autonomous forgetting without a surface. Decay and expiry always leave a
  ratification path the user can see (0.13.x lifecycle work sets the pattern).
- No speculative abstraction. Two concrete uses before one abstraction, and no
  second storage backend until someone actually needs one.

## How work gets proposed

Improvements arrive as GitHub issues, labeled by origin and state:

- Origin: `loop:quality`, `loop:security`, `loop:deps`, `loop:research`,
  `loop:self` (agent-originated), or unlabeled (human-originated).
- State: `status:analyzed`, `status:deferred`, `status:wont-do`,
  `status:blocked`. A closed issue with `status:wont-do` records the reason in
  its final comment and is permanent institutional memory. Proposals must check
  closed and deferred issues, and `docs/improvements.md`, before re-raising an
  idea.

Design-level proposals (the shape of #13 and #15) stay at the issue stage until
the maintainer approves the direction. No implementation PR lands on an
unapproved design.

## Review policy

Changes are classed by risk (external visibility times reversibility), and each
class has an autonomy level that can rise as the agent's track record earns it:

- L0: propose in an issue only.
- L1: open a PR; the maintainer merges.
- L2: open a PR; it may merge after a 72-hour quiet period with green CI.
- L3: merge on green CI, reported in a digest.

Every class starts at L0 or L1. Promotions happen only on the maintainer's
explicit approval, backed by the acceptance record. Any revert demotes the
class immediately. Gem releases, version bumps, and schema changes are the
maintainer's alone. Review budget: at most two agent-originated PRs per week
from this repo.

## Amending this document

By pull request with maintainer approval, nothing else. The agent may propose
amendments; it may never merge them.
