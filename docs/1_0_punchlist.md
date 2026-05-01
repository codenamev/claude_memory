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

### #5 `claude-memory show` — human-readable "what would be injected" ✅ landed 2026-04-29

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

**Status.** Landed 2026-04-29 (commit 2586bb3). New `Commands::ShowCommand`
runs `Hook::ContextInjector` and prints the would-be-injected Markdown.
Default suppresses the raw-transcript pending-knowledge dump for
readability (`--pending` opts in). Footer reports fact count, token
estimate, char count.

→ improvements.md entry: *#51 claude-memory show*. Effort: ½d.

### #7 First-week ROI nudge — *moved up from post-1.0* ✅ landed 2026-04-30

**Gap.** New users install, run a few sessions, don't know whether memory is
working. The dashboard exists but they have to know to look.

**Acceptance.** SessionEnd hook prints `memory contributed N facts this
session, %used = X` inline for the first ~10 sessions, then quiets. Opt-out
via `CLAUDE_MEMORY_NO_NUDGE=1`.

**Why this release.** Belongs with the trust theme — it's the user-visible
proof that memory is doing work for them. Originally listed as post-1.0;
elevating because cold-start trust deserves to land before 1.0.

**Status.** Landed in 2 atomic commits on 2026-04-30 (f450ed9, 3acce93)
plus production smoke-test against this project's DB (event #229
recorded with n=11, used=0, pct=0 for a real session_id). New
`Hook::Handler#nudge` + `claude-memory hook nudge`; SessionEnd config
appends nudge after ingest+sweep. Silent on opt-out, missing
session_id, n=0, or first-week-complete (so empty sessions don't burn
slots).

→ improvements.md entry: *#53 First-Week ROI Nudge*. Effort: ½d.

### Risk-de-risking — 3-scenario harm prototype ✅ landed 2026-04-30

Before 0.12 builds the full 10-15-scenario harm benchmark (see #3), run a
3-scenario prototype against the 0.10.0 codebase to confirm whether harm is
actually low. If the prototype surfaces a >0% harm rate on simple cases, the
full benchmark in 0.12 will reveal a fundamental issue — better to know at
0.11 than discover at 0.12.

**Acceptance.** Three hand-written `harm_scenarios.yml` cases (one stale-tech,
one mismatched-scope, one superseded-but-undetected) run against real Claude
under `EVAL_MODE=real`. Reports go/no-go on the larger benchmark in 0.12.

**Status.** Landed 2026-04-30 (commit 35b368e). Three cases written:
`harm_stale_tech` (MySQL fact vs SQLite reality), `harm_mismatched_scope`
(global TS/Tailwind preference applied to a Ruby gem),
`harm_superseded_undetected` (two contradicting auth_method facts both
active). Structure validation passes in stub mode. Real-mode is gated
behind `EVAL_MODE=real` (~$2-8 per run) so the operator decides when to
spend; this prototype reports harm rate but doesn't enforce a threshold
yet — that's the 0.12 release-gate work.

→ improvements.md entry: *#49 Negative-Fact Harm Benchmark* (prototype phase).
Effort: ½d.

**Ship target:** ~2 weeks from 0.10.0 (mid-May 2026 at current velocity).

---

## 0.12.0 — "Release Discipline" (~1.5 weeks of work)

Theme: *we can't ship a regression without noticing.* Internal infrastructure
that prevents future regressions and locks down what "regression" even means.
Not flashy but the actual prerequisite for 1.0's semver commitment.

*Restructured 2026-05-01 (post-0.11.0): #11 (API stability audit) promoted
from 1.0 because the scoreboard #6 needs an explicit stable-surface list to
gate against. New #12 (pre-release hook smoke gate) added to codify the
verification convention that surfaced during 0.11 work.*

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

### #6 Release-to-release benchmark scoreboard ✅ landed 2026-05-01

**Gap.** Benchmark output is textual today. Nothing diff-able across versions.
Regressions land silently — the only reason we caught the BM25 normalization
bug was a manual run.

**Acceptance.** Each `bin/run-evals` run writes
`spec/benchmarks/results/<version>.json`. New `bin/bench-diff` compares
against the last tagged version's JSON and reports deltas. `/release` skill
reads it and refuses to ship on regressions over threshold.

**Why this release.** The semver commitment in 1.0 *requires* this — we
can't promise non-regression without the infrastructure to detect it.

**Status.** Landed 2026-05-01. `bin/run-evals` writes
`spec/benchmarks/results/<version>.json` with diff-friendly pass-rate
metrics by category and per-scenario. `bin/bench-diff` compares against
the most recent prior tagged version's scoreboard via `Gem::Version`
ordering, flags pass-rate drops > threshold (default 5%), supports
`--threshold` / `--baseline` / `--json` / `--strict`. 11 unit specs
covering missing-baseline, threshold tuning, deep-nested metric paths,
JSON output. Wired into `/release` skill as new Phase 1 Step 7 (after
smoke gate, before lint). First release with the gate is 0.12.0 itself
— prior versions have no scoreboard, so bench-diff exits 0 with a "no
baseline" note; from 0.13 onward it actively gates.

→ improvements.md entry: *#52 Benchmark Scoreboard Diff*. Effort: 1d.

### #11 API stability audit — *promoted from 1.0 (2026-05-01)* ✅ landed 2026-05-01

**Gap.** "1.0 commits to semver" is meaningless without an explicit
public/internal split. Many of the surfaces touched in 0.9.0 / 0.10.0 / 0.11.0
(MCP tool schemas, hook payload shapes, CLI flags, dashboard endpoints,
`detail_json` field set) have evolved organically and aren't formally
documented as stable vs. internal.

**Acceptance.**

- New `docs/api_stability.md` enumerating:
  - **Public CLI**: every `claude-memory <subcommand>` and its flags, with stability tier
  - **Public MCP tools**: every tool's schema, return shape, and tool-annotation hints
  - **Public hook contract**: payload fields, return shapes, exit codes, `detail_json` field set per event_type
  - **Public Ruby API**: `Recall`, `Configuration`, `Store::StoreManager`, `Domain::*` vs. internal-only
  - **Schema**: stability of column names, table names, predicate vocabulary
- Deprecation policy paragraph: "we'll mark X deprecated in N.x.0 (with a runtime warning), keep it functional for ≥1 minor cycle, and remove no earlier than (N+1).0.0"
- `ClaudeMemory::Deprecations.warn(name:, replacement:, removed_in:)` module wired up and used at least once so the mechanism is exercised
- README + CLAUDE.md link to the new doc as the authoritative source

**Why this release.** #6's scoreboard needs to know what surfaces are stable
to gate against. Without #11, any "regression" finding is arguable. The
deprecation-warning module is also a prerequisite for any soft-rename work
during the 0.12 → 1.0 soak.

→ improvements.md entry: *#59 API Stability Audit*. Effort: 2d.

### #12 Pre-release hook smoke gate — *new this release (2026-05-01)* ✅ landed 2026-05-01

**Gap.** During 0.11 work, five commits landed for #47 token-budget telemetry
with 156 specs green. 24 hours of real SessionStart hook events recorded no
`context_tokens` field — because the *installed* gem was still 0.9.1 and the
`.claude/settings.json` hooks invoke the installed binary via PATH, not the
working tree. The bug wasn't in the code; the bug was in the release process.

This trap has been hit twice now (#47 in 0.11; an earlier ActivityLog
incident on 2026-04-16). It's documented in
`~/.claude/projects/.../memory/feedback_hooks_run_installed_gem.md` and as
two project conventions, but documentation hasn't stopped me (Claude) from
springing the trap again.

**Acceptance.**

- New `bin/pre-release-smoke` script: `rake install` → trigger each hook
  with a synthetic payload → inspect `activity_events.detail_json` via
  `sqlite3 json_extract` for expected fields per the current version → exit
  non-zero if anything is null.
- Per-version expectation manifest at `spec/smoke/expected_fields.yml`
  declares `{event_type, fields, since_version}` so new fields just need a
  YAML append; no script changes per release.
- `/release` skill Phase 1 runs the smoke gate after specs and before lint.
  Failure aborts before `git push`.
- Test: `spec/smoke/pre_release_smoke_spec.rb` validates the manifest schema
  and that the exit-code logic correctly flips on simulated null fields.

**Why this release.** Release Discipline that doesn't catch the trap I've
already hit twice isn't real discipline. Pairs with #6 — the scoreboard
catches regressions in measurement; the smoke gate catches the regression
where the measurement itself doesn't fire.

→ improvements.md entry: *#63 Pre-Release Hook Smoke Gate*. Effort: ½d.

**Ship target:** ~5-6 weeks from 0.10.0 (early-to-mid June 2026 at current
velocity, given the 0.12 scope grew from 3.5d to ~6d).

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

*(#11 API stability audit moved to 0.12 on 2026-05-01 — see above.)*

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

The biggest hidden risk in this plan was **the harm benchmark (#3) finds
something.** The 3-scenario prototype in 0.11 (above) was specifically
designed to surface this risk earlier — and **on 2026-04-30 the real-mode
prototype reported 0/3 harm**, green-lighting the full corpus expansion.
Risk is materially reduced; the 10-15-case corpus may still surface
something the 3-case sample missed, but a fundamental retrieval-discipline
issue is now unlikely.

Remaining risk for 0.12: **#11 API stability audit reveals the surface is
larger or messier than we thought**, pushing the doc work past the 2-day
estimate. Mitigation: scope `Public Ruby API` aggressively to "internal
unless proven otherwise" — easier to promote later than demote.

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

| Milestone | Estimated work | Calendar target | Status |
|---|---|---|---|
| 0.11.0 | ~1 week | ~2026-05-12 | ✅ shipped 2026-04-30 |
| 0.11.x patches | reactive | as-needed | open |
| 0.12.0 | ~1.5 weeks | ~2026-06-02 | in planning |
| Soak | 2-3 weeks | through ~2026-06-23 | future |
| 1.0.0 | 1-2 days release prep | ~2026-06-23 to 2026-06-30 | future |

*0.12 grew from ~1 week to ~1.5 weeks after 2026-05-01 restructure
(promoted #11 + added #12). 1.0 calendar shifted ~1 week later in
return; net no compression of the soak window.*

These are calendar estimates assuming roughly the same focus level as the
0.10.0 cycle. Real cadence will adjust based on what surfaces during soak.

---

*Last updated: 2026-05-01 (post-0.11.0 ship). 0.11.0 shipped 2026-04-30
with all 5 punchlist items + harm prototype reporting 0/3 harm. 0.12
restructured 2026-05-01: #11 (API stability audit) promoted from 1.0
because #6's scoreboard needs an explicit stable-surface list to gate
against; new #12 (pre-release hook smoke gate) added to codify the
verification convention surfaced during 0.11. 0.12 grew ~1 week → ~1.5
weeks; 1.0 ship target shifted ~1 week later in return.*
