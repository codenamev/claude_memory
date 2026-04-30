# 1.0 Punchlist

*Created: 2026-04-28. Restructured 2026-04-28 (post-0.10.0 release) around
milestone versions per the path-to-1.0 plan.*

The remaining work for a stable 1.0 release. Distinct from `improvements.md` —
that file tracks the long tail of inbound study/idea entries; this file tracks
**what blocks 1.0 confidence and which release each item ships in**.

Guiding question: *a skeptical Ruby developer should be able to look at one
screen and say "yes, this is helping, here's the evidence" without trusting our
marketing.* Today the dashboard tells that story in pieces but not as a
headline. Each item below closes a specific gap that prevents that headline
from existing.

## What 1.0 commits to

Not "feature complete" — semver commitment. Once we ship 1.0:

- Public APIs (CLI surface, MCP tool schemas, hook payload shapes) lock to semver
- Schema migrations stay forward-compatible per the round-trip-spec convention
- The trust signals we ship have a baseline measurement other releases must beat

So 1.0 isn't gated by features. It's gated by **the measurement infrastructure
being trustworthy enough to defend a 1.0 claim.** That's why this punchlist is
mostly observability, not capability.

Items are cross-linked to the canonical entry in `improvements.md` where the
implementation detail and acceptance criteria live. This file is the
prioritization view; that file is the work view.

---

## 0.10.x — patch as needed (now)

Reactive only. Real usage will surface issues; cut a patch when one shows up.
No proactive minor work here.

---

## 0.11.0 — "Trust & Cost" (~1 week of work)

Theme: *users can see what memory costs and whether it's helping.* Each item
adds a number a skeptical user can read.

### #1 Token budget telemetry — *what does memory cost?* ✅ landed 2026-04-29

**Gap.** `Core::TokenEstimator` exists and is unused outside one helper. We
have no idea what % of the SessionStart token budget memory consumes per
session, how it scales with DB size, or whether it's growing.

**Acceptance.** Trust panel + `claude-memory digest` show p50/p95 injected
tokens per session over the last 30 days. Per-session count rides on every
`hook_context` activity event so the data is queryable post-hoc.

**Why this release.** Loudest critique of any context-injection memory
system; if we can't answer it numerically, we can't defend the trade.

**Status.** Landed in 4 atomic commits on 2026-04-29 (15cb5f5, 35ae8d2,
d9601ca, 5bfd7c8). `context_tokens` recorded on every successful
`hook_context` event, surfaced via `Dashboard::Trust#token_budget`,
`claude-memory digest` "Context cost" section, and
`claude-memory stats --tokens [--since DAYS]` with histogram.

→ improvements.md entry: *#47 Token Budget Telemetry*. Effort: 4-6h.

### #2 Hallucination rate as a first-class trust metric ✅ landed 2026-04-29

**Gap.** `ReferenceMaterialDetector` already classifies suspect facts and we
know from the #34 audit that ~25% of facts had embedded reasoning (i.e.
~75% were bare conclusions at audit time). Neither signal is exposed on the
dashboard. We display clean numbers; we should display stained ones.

**Acceptance.** Trust panel surfaces a `quality_score` derived from
suspect-fact ratio + bare-conclusion ratio over active facts in both stores.
Digest includes a 30-day rejection rate ("how much of what we extracted got
rejected within a week?") so calibration drift is visible.

**Why this release.** Pollution rate matters as much as recall rate. Pairs
with #1 — together they answer the "is this still worth it?" question.

**Status.** Landed in 3 atomic commits on 2026-04-29 (27fa6af, 4d1c5bf,
0b72fa4). New `Distill::BareConclusionDetector` + `Dashboard::Trust#quality_score`
+ `claude-memory digest` Quality section with rejection rate.

→ improvements.md entry: *#48 Hallucination Rate Metric*. Effort: 1d.

### #5 `claude-memory show` — human-readable "what would be injected"

**Gap.** Inspecting memory state today requires the dashboard or several CLI
commands (`recall`, `stats`, `census`). The CLAUDE.md alternative is
`cat CLAUDE.md` — instant, plain-English, no tool. We need the same one-line
inspect surface.

**Acceptance.** `claude-memory show` runs the same `Hook::ContextInjector`
path real sessions use, prints what would be injected next session in plain
English (not JSON), sized to fit a terminal, with predicate-grouped sections
matching the snapshot format.

**Why this release.** Trust requires inspectability. A user who can't see what
memory will inject can't develop confidence in it.

→ improvements.md entry: *#51 claude-memory show*. Effort: ½d.

### #7 First-week ROI nudge — *moved up from post-1.0*

**Gap.** New users install, run a few sessions, don't know whether memory is
working. The dashboard exists but they have to know to look.

**Acceptance.** SessionEnd hook prints `memory contributed N facts this
session, %used = X` inline for the first ~10 sessions, then quiets. Opt-out
via `CLAUDE_MEMORY_NO_NUDGE=1`.

**Why this release.** Belongs with the trust theme — it's the user-visible
proof that memory is doing work for them. Originally listed as post-1.0;
elevating because cold-start trust deserves to land before 1.0.

→ improvements.md entry: *#53 First-Week ROI Nudge*. Effort: ½d.

### Risk-de-risking — 3-scenario harm prototype (new this release)

Before 0.12 builds the full 10-15-scenario harm benchmark (see #3), run a
3-scenario prototype against the 0.10.0 codebase to confirm whether harm is
actually low. If the prototype surfaces a >0% harm rate on simple cases, the
full benchmark in 0.12 will reveal a fundamental issue — better to know at
0.11 than discover at 0.12.

**Acceptance.** Three hand-written `harm_scenarios.yml` cases (one stale-tech,
one mismatched-scope, one superseded-but-undetected) run against real Claude
under `EVAL_MODE=real`. Reports go/no-go on the larger benchmark in 0.12.

→ improvements.md entry: *#49 Negative-Fact Harm Benchmark* (prototype phase).
Effort: ½d.

**Ship target:** ~2 weeks from 0.10.0 (mid-May 2026 at current velocity).

---

## 0.12.0 — "Release Discipline" (~1 week of work)

Theme: *we can't ship a regression without noticing.* Internal infrastructure
that prevents future regressions. Not flashy but the actual prerequisite for
1.0's semver commitment.

### #3 Negative-fact harm benchmark (full 10-15 scenarios)

**Gap.** Every benchmark today measures whether memory **helps**. Nothing
measures whether memory **harms** — i.e. injects a wrong fact and Claude
follows it. Without this, "memory helps" is unfalsifiable.

**Acceptance.** `spec/benchmarks/dataset/harm_scenarios.yml` with 10-15 cases
spanning four harm classes (stale-tech, mismatched-scope, superseded-but-
undetected, reference-material-as-fact). Each scores `harm` if Claude follows
the wrong fact, `safe` otherwise. Wired into `bin/run-evals`. **>1% harm
rate blocks release** (configurable via `HARM_RATE_THRESHOLD`).

**Why this release.** A retrieval system that occasionally makes Claude
*wrong* is strictly worse than no memory; the release gate proves we're not
in that regime.

→ improvements.md entry: *#49 Negative-Fact Harm Benchmark* (full corpus).
Effort: 2d.

### #4 Publish the CLAUDE.md baseline in headline E2E results

**Gap.** `claude_md_adapter` exists in `spec/benchmarks/comparative/adapters/`
and is wired into `comparative_helper.rb`. The README's headline comparative
table doesn't include it. The single most important question for adoption —
*"is this better than a hand-written CLAUDE.md?"* — is unanswered in our
published numbers.

**Acceptance.** Comparative E2E report includes `CLAUDE.md baseline` row in
`spec/benchmarks/README.md` and in `bin/run-evals --comparative` summary.
README explicitly states the win/loss versus the static baseline.

**Why this release.** Cheapest item on the list — adapter built, just
surface the number. Pairs with #6 because it materializes once the
scoreboard infrastructure is there.

→ improvements.md entry: *#50 CLAUDE.md Baseline in Headline Results*.
Effort: 30min code + one $2-8 real-mode run.

### #6 Release-to-release benchmark scoreboard

**Gap.** Benchmark output is textual today. Nothing diff-able across versions.
Regressions land silently — the only reason we caught the BM25 normalization
bug was a manual run.

**Acceptance.** Each `bin/run-evals` run writes
`spec/benchmarks/results/<version>.json`. New `bin/bench-diff` compares
against the last tagged version's JSON and reports deltas. `/release` skill
reads it and refuses to ship on regressions over threshold.

**Why this release.** The semver commitment in 1.0 *requires* this — we
can't promise non-regression without the infrastructure to detect it.

→ improvements.md entry: *#52 Benchmark Scoreboard Diff*. Effort: 1d.

**Ship target:** ~4 weeks from 0.10.0 (end of May 2026).

---

## 0.12.x → 1.0 — soak period (2-3 weeks)

Critical phase. Run 0.12 against real usage. Watch:

- **Harm rate stays at 0%** — release gate from #3
- **Hallucination rate trend** — from #2
- **Token budget growth** — from #1, #9
- **Utilization ratio** — across multiple projects

If any signal shifts unfavorably during soak, fix in 0.12.x. **Don't ship 1.0
from a release that hasn't observed itself for ≥2 weeks.**

This soak period is also where the relevance ratio metric (#31 from 0.10.0)
materializes its first real-mode measurement, and where the 0.11 trust
signals get a chance to be real numbers vs. theory.

---

## 1.0.0 — "Stable Memory"

Theme: *ready for daily use, ready to recommend.*

### Post-1.0-punchlist polish (if landed during soak)

These were originally post-1.0 in the punchlist; if soak time permits, they
land in 1.0. Otherwise they ship in 1.1.

### #8 Real-session repeat-correction detection

The repeat-correction benchmark (#32 from 0.10.0) is synthetic; production
has no equivalent signal. Analyze `activity_events` for "this fact was
injected last session, the user re-stated it this session" — that's where
memory is silently failing.

→ improvements.md entry: *#54 Real-Session Repeat-Correction Detection*.
Effort: 2d.

### #9 Token-cost growth tracking

Builds on #1. Weekly digest reports "context cost grew X% over 30d" as an
anomaly signal that the DB is bloating or context injection is going wide.

→ improvements.md entry: *#55 Token-Cost Growth Tracking*. Effort: 3h after
#1 lands.

### #10 Drift dashboard

Snapshot `census` weekly, surface predicate distribution shifts on the
dashboard. Answers "is my fact base going off?" without a manual audit.

→ improvements.md entry: *#56 Drift Dashboard*. Effort: 1.5d.

### #11 API stability audit (NEW — added 2026-04-28)

**Gap.** "1.0 commits to semver" is meaningless without an explicit
public/internal split. Many of the surfaces touched in 0.9.0 / 0.10.0
(MCP tool schemas, hook payload shapes, CLI flags, dashboard endpoints)
have evolved organically and aren't formally documented as stable vs.
internal.

**Acceptance.**

- New `docs/api_stability.md` enumerating:
  - **Public CLI**: every `claude-memory <subcommand>` and its flags, with stability tier
  - **Public MCP tools**: every tool's schema, return shape, and tool-annotation hints
  - **Public hook contract**: payload fields, return shapes, exit codes
  - **Public Ruby API**: which classes/modules under `lib/claude_memory/` are external-facing (`Recall`, `Configuration`, `Store::StoreManager`?) vs. internal-only
  - **Schema**: stability of column names, table names, predicate vocabulary
- A deprecation policy: "we'll mark X deprecated in N.x.0 and remove no earlier than (N+1).0.0"
- README + CLAUDE.md link to the new doc as the authoritative source

**Why this release.** Without this, the 1.0 semver promise is vibes, not a
contract. Future regressions in non-listed areas can be argued away; future
regressions in listed areas are bugs. Forces us to be honest about what
we're committing to.

→ improvements.md entry: *#59 API Stability Audit* (added 2026-04-28; renumbered
from #57 after rebase brought in Mercury-article entries #57/#58). Effort:
2d including the doc + deprecation-warning instrumentation for any
soon-to-be-removed surface.

### Release framing

README + CHANGELOG framing for 1.0 explicitly states:

- "We measured X harm rate, Y utilization, Z hallucination rate across N
  projects over W weeks before tagging this."
- The public API surface is documented at `docs/api_stability.md`
- Deprecation policy explicit

**Ship target:** 6-8 weeks from 0.10.0 (mid-June 2026 at current velocity).

---

## Defer / skip for 1.0

- **#44 Universal search box** — cosmetic given the gaps above. Knowledge tab
  drawers cover the primary need.
- **#45 Live SSE/WebSocket feed** — polling is adequate; dashboard polish, not
  a confidence gap.
- **#23 REST API endpoint** — MCP covers primary use case; defer to 1.x.
- **#25 HTTP MCP transport** — no startup-latency complaint to motivate it yet.

---

## Risk to flag now

The biggest hidden risk in this plan is **the harm benchmark (#3) finds
something.** If 10-15 scenarios with intentionally wrong facts produce >1%
harm rate, that's a fundamental retrieval-discipline issue that could push
1.0 by months. The 3-scenario prototype in 0.11 (above) is specifically
designed to surface this risk earlier.

---

## Velocity assumptions

Based on actual release cadence Mar-Apr 2026:

| Pair | Days |
|---|---|
| 0.7.0 → 0.7.1 | minor patch, days |
| 0.7.1 → 0.8.0 | 17 |
| 0.8.0 → 0.9.0 | 17 |
| 0.9.0 → 0.9.1 | same day (patch) |
| 0.9.1 → 0.10.0 | 12 |

Average ~2 weeks per minor with substantial work landing each cycle.

| Milestone | Estimated work | Calendar target |
|---|---|---|
| 0.10.x patches | reactive | as-needed |
| 0.11.0 | ~1 week | ~2026-05-12 |
| 0.12.0 | ~1 week | ~2026-05-26 |
| Soak | 2-3 weeks | through ~2026-06-16 |
| 1.0.0 | 1-2 days release prep + #11 | ~2026-06-16 to 2026-06-23 |

These are calendar estimates assuming roughly the same focus level as the
0.10.0 cycle. Real cadence will adjust based on what surfaces during soak.

---

*Last updated: 2026-04-28 (post-0.10.0). Restructured around milestone
versions per the path-to-1.0 plan. #7 moved up from post-1.0 to 0.11; #11
API stability audit added as a new 1.0 must-have; 3-scenario harm prototype
added to 0.11 as risk-de-risking work for the full 0.12 benchmark.*
