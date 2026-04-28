# 1.0 Punchlist

*Created: 2026-04-28*

The remaining work for a stable 1.0 release. Distinct from `improvements.md` —
that file tracks the long tail of inbound study/idea entries; this file tracks
**what blocks 1.0 confidence**.

Guiding question: *a skeptical Ruby developer should be able to look at one
screen and say "yes, this is helping, here's the evidence" without trusting our
marketing.* Today the dashboard tells that story in pieces but not as a
headline. Each item below closes a specific gap that prevents that headline
from existing.

Items are cross-linked to the canonical entry in `improvements.md` where the
implementation detail and acceptance criteria live. This file is the
prioritization view; that file is the work view.

---

## Must-have for 1.0

### 1. Token budget telemetry — *what does memory cost?*

**Gap.** `Core::TokenEstimator` exists and is unused outside one helper. We
have no idea what % of the SessionStart token budget memory consumes per
session, how it scales with DB size, or whether it's growing.

**Acceptance.** Trust panel + `claude-memory digest` show p50/p95 injected
tokens per session over the last 30 days. Per-session count rides on every
`hook_context` activity event so the data is queryable post-hoc.

**Why must-have.** "Costs you tokens forever" is the strongest critique of any
context-injection memory system; if we can't answer it numerically, we can't
defend the trade.

→ improvements.md entry: *Token Budget Telemetry*

### 2. Hallucination rate as a first-class trust metric

**Gap.** `ReferenceMaterialDetector` already classifies suspect facts and we
know from the #34 audit that ~25% of facts had embedded reasoning (i.e.
~75% were bare conclusions at audit time). Neither signal is exposed on the
dashboard. We display clean numbers; we should display stained ones.

**Acceptance.** Trust panel surfaces a `quality_score` derived from
suspect-fact ratio + bare-conclusion ratio over active facts in both stores.
Digest includes a 30-day rejection rate ("how much of what we extracted got
rejected within a week?") so calibration drift is visible.

**Why must-have.** We can't claim "memory is helping" if we can't show "memory
isn't poisoning the well."

→ improvements.md entry: *Hallucination Rate Metric*

### 3. Negative-fact harm benchmark

**Gap.** Every benchmark we run today measures whether memory **helps**.
Nothing measures whether memory **harms** — i.e. injects a wrong fact and
Claude follows it. Without this, "memory helps" is unfalsifiable.

**Acceptance.** New `spec/benchmarks/dataset/harm_scenarios.yml` with 10–15
cases where memory holds a stale or wrong fact. Each case scores `harm` if
Claude's response follows the wrong fact, `safe` otherwise. Wired into
`bin/run-evals`. >1% harm rate blocks release.

**Why must-have.** A retrieval system that occasionally makes Claude *wrong*
is strictly worse than no memory; we need a release gate that proves we're
not in that regime.

→ improvements.md entry: *Negative-Fact Harm Benchmark*

### 4. Publish the CLAUDE.md baseline in headline E2E results

**Gap.** `claude_md_adapter` exists in `spec/benchmarks/comparative/adapters/`
and supports E2E. The adapter is wired into `comparative_helper.rb` but the
README's headline comparative table doesn't include it. The single most
important question for adoption — *"is this better than a hand-written
CLAUDE.md?"* — is currently unanswered in our published numbers.

**Acceptance.** Comparative E2E report includes `CLAUDE.md baseline` row in
`spec/benchmarks/README.md` and in `bin/run-evals --comparative` summary
output. README explicitly states the win/loss versus the static baseline.

**Why must-have.** Cheapest item on the list — adapter already built, just
surface the number. If we can't beat a static CLAUDE.md on developer
scenarios, that's the loudest possible signal that the rest of the system
needs work; if we can, that's the headline 1.0 brag.

→ improvements.md entry: *CLAUDE.md Baseline in Headline Results*

### 5. `claude-memory show` — human-readable "what would be injected"

**Gap.** Inspecting memory state today requires the dashboard or several CLI
commands (`recall`, `stats`, `census`). The CLAUDE.md alternative is
`cat CLAUDE.md` — instant, plain-English, no tool. We need the same one-line
inspect surface.

**Acceptance.** `claude-memory show` runs the same `Hook::ContextInjector`
path real sessions use, prints what would be injected next session in plain
English (not JSON), sized to fit a terminal, with predicate-grouped sections
matching the snapshot format.

**Why must-have.** Trust requires inspectability. A user who can't see what
memory will inject can't develop confidence in it.

→ improvements.md entry: *claude-memory show*

### 6. Release-to-release benchmark scoreboard

**Gap.** Benchmark output is textual today. Nothing diff-able across versions.
Regressions land silently — the only reason we caught the FTS5/RRF
normalization bug was a manual run.

**Acceptance.** Each `bin/run-evals` run writes
`spec/benchmarks/results/<version>.json`. New `bin/bench-diff` (or rake task)
compares against the last tagged version's JSON and reports deltas. Release
script (`/release` skill) reads it and refuses to ship on regressions over a
configurable threshold.

**Why must-have.** Without longitudinal tracking, every benchmark we run is a
snapshot. 1.0 is the moment we commit to *not regressing* what we ship.

→ improvements.md entry: *Benchmark Scoreboard Diff*

---

## Strong post-1.0

These shouldn't block 1.0 but should land in the next release window.

### 7. First-week ROI nudge

SessionEnd hook prints `memory contributed N facts this session, %used = X`
inline for the first ~10 sessions. Closes the cold-start gap where new users
don't see value because they don't think to look.

→ improvements.md entry: *First-Week ROI Nudge*

### 8. Real-session repeat-correction detector

The repeat-correction benchmark (#32) is synthetic; production has no
equivalent signal. Analyze `activity_events` to detect "this fact was injected
last session, the user re-stated it this session" — that's where memory is
silently failing.

→ improvements.md entry: *Real-Session Repeat-Correction Detection*

### 9. Token-cost growth tracking

Builds on #1. Weekly digest reports "context cost grew X% over 30d" as an
anomaly signal that the DB is bloating or context injection is going wide.

→ improvements.md entry: *Token-Cost Growth Tracking*

### 10. Drift dashboard

Snapshot `census` weekly, surface predicate distribution shifts on the
dashboard. Answers "is my fact base going off?" without a manual audit.

→ improvements.md entry: *Drift Dashboard*

---

## Defer / skip for 1.0

- **#44 Universal search box** — cosmetic given the gaps above. Knowledge tab
  drawers cover the primary need.
- **#45 Live SSE/WebSocket feed** — polling is adequate; dashboard polish, not
  a confidence gap.

---

## Sequencing recommendation

Smallest set that materially shifts 1.0 confidence (~2 days):

1. **Token budget telemetry** (#1) — closes the loudest critique.
2. **CLAUDE.md baseline publish** (#4) — adapter already built, one report change.
3. **Hallucination rate** (#2) — reuses ReferenceMaterialDetector.

Then in roughly priority order: `claude-memory show` (#5), harm benchmark
(#3), scoreboard (#6). Post-1.0 items follow naturally once the must-haves
land.

---

*Last updated: 2026-04-28 — initial punchlist drawn from session-end critique
of observability/outcome gaps. Each entry will be elaborated with concrete
file:line refs in improvements.md as it's worked.*
