# Code Quality Review - Ruby Best Practices

**Review Date:** 2026-04-28
**Previous Review:** 2026-04-22 (6 days ago)
**Last Quality Update:** 2026-04-22 (4 items completed — LLMCache + MetricsAggregator extractions, Publish DRY, Dashboard specs)
**Codebase Growth:** 17,014 → 19,025 LOC (+2,011, +12% in 6 days)

> **Post-review update (2026-04-28, same session):** Items #34, #32, #35, #36 (quick wins + missing command specs) and the first two of the six proposed `Dashboard::API` extractions (#31: `Dashboard::Timeline` + `Dashboard::Health`) landed before the v0.10.0 release commit. `dashboard/api.rb` dropped 807 → 607 LOC (-200, -25%), reversing the regression and bringing it back under the 2026-04-22 baseline (627). The remaining four extractions (`RecallQuery`, `RecallTriggerFinder`, `UserPromptExtractor`, `FactsQuery`) are deferred to 0.10.1. Findings below describe the *pre-update* state captured at review time.

---

## Observational Layer — Pre-Merge Review (2026-06-18)

**Review Date:** 2026-06-18
**Previous Review:** 2026-04-28 (51 days ago)
**Scope:** the observational-layer branch (`claude/observational-layer-design-7662r9`, 22 commits ahead of `origin/main`, ~57 files). Two parallel expert-lens reviews — core/data layer (migrations 019/020, `Domain::Observation`, `SQLiteStore` observation methods, `Resolver`) and pipeline layer (`NullDistiller` extraction, renderer, `Reflector`, `ContextInjector`, MCP handlers, dashboard panel).

**Verdict:** No hard merge-blockers. The append-only/tombstone discipline is consistent, `Domain::Observation` is a clean immutable value object, border validation (`coerce_observation`) is textbook, and test coverage on this surface is above the repo average. The items below are latent correctness edge-cases + cleanups; none break the system as shipped (the layer is experimental and observations are project-scoped only today).

### High — address or consciously accept before merge

- **H1 · `consolidate_observations` read-modify-write race** — `lib/claude_memory/store/sqlite_store.rb:805-826` (Evans/Bernhardt). The source `SELECT` and `combined = sources.sum{…}` run *outside* the `@db.transaction` block, and the tombstone `UPDATE` (822) doesn't re-assert `status: "active"`. Two reflectors firing close together (PreCompact + SessionEnd) could double-count corroboration or re-tombstone an already-consolidated source. SQLite's single-writer lock narrows the window but doesn't close the gap. **Fix:** move the read inside the transaction and re-filter `status: "active"` on the update. Mechanical, ~1h incl. spec.
- **P1 · `noise_body?` over-broad — drops legit prose** — `lib/claude_memory/distill/null_distiller.rb:53,169` (Grimm/Bernhardt). `NOISE_BODY_SIGNATURE` matches `::`, `{}`, `=>` anywhere, so `"decided to adopt ClaudeMemory::Observation as the model"` is silently dropped — common in Ruby prose. Confirmed at runtime. **This is a precision-tuning *design* change to extraction behavior, not a mechanical fix** — per the project's data-driven-design convention it should be surveyed against real corpus data before retuning, not changed blind. Candidate: narrow to strong structural markers (`def `/`class `/`module `, JSON `","`/`":\s*"`, `$(`, `&&`, `||`), drop bare `::`/`{}`/`=>`, add a false-negative spec corpus.
- **P2 · cross-scope promote nudge — latent wrong-DB landmine** — `lib/claude_memory/hook/context_injector.rb:159-194` + `lib/claude_memory/mcp/handlers/management_handlers.rb:88` (Evans/Beck). `fetch_promotion_candidates` flat-maps project+global stores; the reflection block emits `[obs #<id>]` (a *per-DB* autoincrement id) with no scope; `promote_observation`/`consolidate_observations` default `scope: "project"`. A global-store candidate would route the promote call to the wrong DB. **Dead today** (nothing writes observations to the global DB), but a genuine landmine if global observations ever appear. **Fix:** restrict reflection candidates to the project store + document, or scope-tag the nudge line (mirror `emitted_facts_by_scope`). ~1-2h.
- **M1 · `consolidate_observations` has zero test coverage** — the most complex method in `sqlite_store.rb` is the only observation method with no specs (the `< 2 → nil` guard, summed-corroboration-tips-threshold, multi-row tombstone are all load-bearing and untested). Add specs alongside the H1 fix. ~1h.

### Medium

- **M2/P7 · token-estimate `/4.0` heuristic duplicated 3×** — `sqlite_store.rb:714,819` + `dashboard/observations.rb:98` (Metz DRY). The compression-ratio correctness depends on both halves using the same divisor. Extract `Core::TokenEstimate.from_chars`/`.from_bytes`. ~1h.
- **M3/P10 · `recent_observations` `min_priority` name inverted** — `sqlite_store.rb:731` (Beck revealing-names). Filters `priority <= min_priority`, but priority is inverted (1=important), so a higher "minimum" returns *more* rows. Rename `max_priority_value`/`importance_floor`. ~30m + callers.
- **M4 · `Resolver#apply` `@return` rdoc stale** — `resolver.rb:29` omits the `:observations_created` and `:fact_ids` keys this PR adds. ~10m.
- **M5 · `fact_ids` array silently contains `nil`s** — `resolver.rb:45,61` (Grimm meaningful-returns). Comment promises positional alignment with `extraction.facts`, but `:discard` contributes `nil`; the sole consumer already `.compact.first`s. Pick one contract and document it (or compact at source). ~20m.
- **P3 · `clean_observation_body` is 6 chained gsubs, brittle** — `null_distiller.rb:178` (Bernhardt). Pure text logic buried as a private method; extract to a tested `Observe::BodyCleaner` with an input→output spec table. ~2h.
- **P4 · `extract_decisions`/`extract_observations` double-scan `DECISION_PATTERNS`** — `null_distiller.rb:105,138` (Metz DRY). Two full regex passes per chunk on the P95<5ms hot path; titles and bodies also diverge, complicating later corroboration. ~2-3h.
- **P5 · `consolidate_observations` reuses `coerce_observation(args)` on the whole tool-args hash** — `management_handlers.rb:151` (Grimm border). Couples the consolidation tool's param names to the observation schema and pulls in `kind`/`priority` defaults the caller may not intend. Pass a narrowed hash. ~1h.
- **P6 · dashboard N+1 across stores** — `dashboard/observations.rb:48-99` (Evans, bounded). 8-12 small aggregate queries per load; acceptable at store-count 2 but the `.where(status: "active")` predicate repeats ~6×. One `group_and_count(:status)` per store. ~2h.

### Low (fast-follow cleanups)

- **L1** `persist_observations` reaches into raw hashes (`obs[:body]`…) — coerce through `Domain::Observation` at the border; defaults are triplicated. `resolver.rb:81`. ~1-2h.
- **L2** `respond_to?(:observations)` guard is dead defensiveness — `Extraction` always defines it. `resolver.rb:82`. ~5m.
- **L3/P8** status strings (`"active"`/`"consolidated"`/`"expired"`) and `2`/`3` literals scattered — add `STATUSES`/reuse `PROMOTION_THRESHOLD`/`INFO` from `Domain::Observation`. ~30m.
- **L4** `increment_corroboration` returns void while sibling mutators return `updated > 0` — make symmetric. `sqlite_store.rb:772`. ~10m.
- **L5** migration index DDL uses raw `CREATE INDEX` rather than Sequel's `index` DSL — idiomatic-only. ~30m, optional.
- **L6** `consolidate_observations` doesn't thread `session_id` (synthesized rows get NULL) — document the intent or thread it. ~5m.

### What's done well

Append-only/tombstone discipline honored end-to-end with "row preserved, not deleted" specs; `Domain::Observation` immutable/frozen/self-validating with intention-revealing predicates; `corroborated?(threshold)` kept a total function (threshold injected, not hard-coded); resolver change genuinely additive (observations persist *inside* the extraction transaction, "no observations → fact behavior unchanged" tested); pure Sequel datasets throughout (no raw SQL except index DDL); promotion-gate tests pin the anti-hallucination invariant; `coerce_observation` border validation with `filter_map` drops invalids without aborting the batch; the Go-language case-sensitivity fix is clean and well-specced.

### Recommended pre-merge action

Fix the mechanical items — **H1** (read-inside-transaction), **P2** (defuse cross-scope), **M1** (the missing consolidation spec), **M4/M5** (document this PR's own new `apply` surface). Flag **P1** (regex retune) for a data-driven decision — do not change blind. Everything else is tracked here as fast-follow.

---

## Post-0.11 Investigation: Hallucination Rate Metric Calibration (2026-04-30)

When #48 (hallucination-rate metric) was first run against this project's real DB, it surfaced numbers that *looked* alarming:

- Quality score: 39/100
- Bare conclusions: 34 / 59 active facts (57.6%)
- 7-day rejection rate: 27 of 32 facts (84.4%)

The first read was that the LLM extractor was producing noise faster than usable knowledge. Per `improvements.md` #60, four causes were proposed; diagnostics ran 2026-04-30:

| Cause | Verdict | Evidence |
|---|---|---|
| Prompt drift in `distill-transcripts.md` | **Confirmed dominant** | 34/35 (97%) bare-conclusion facts pre-date the reason-clause prompt commit `f22d12f` (2026-04-20). Only 1 was created post-commit (and that one is a meta-convention added during this session). |
| Auto-memory mirror regurgitation | Rejected | 0/35 substring matches in `~/.claude/projects/.../memory/*.md`. Auto-memory mirror only landed in 0.10.0 (2026-04-28), after the bare-fact creation window — temporally impossible to be the source. |
| `ReferenceMaterialDetector` predicate scope too narrow | Not material | Only 3/35 bare facts are `decision`-predicate; 0 of those match the strong reference-material patterns. Expanding `GUARDED_PREDICATES` would not move the needle on the bare-conclusion count. |
| Junky corpus / rejection cluster | **Confirmed in single class** | All 27 rejected facts in the 7-day window are `uses_database` (18) or `deployment_platform` (9), all with `session_id=nil` (MCP-originated, almost certainly `/study-repo` runs misattributing external-project tech to this project), all from 2026-04-23 to 04-24. Systemic single-class failure, correctly cleaned up after detection — not ongoing extraction noise. |

**What this means for #48 as currently shipped:**

The metric is *technically correct* but *pragmatically misleading*. It bakes historical noise (pre-prompt-commit bare conclusions) into a signal that users will read as "ongoing extraction quality." A 57.6% bare-conclusion rate looks like the LLM is broken; in reality the live extraction rate (post-2026-04-20) is ~3% (1 bare fact out of ~30+ created since the prompt commit landed).

The 84% rejection rate has a similar structural issue: it counts cleanup of a bursty `/study-repo` regression against the active-facts denominator, not against the actual extraction quality of the live window.

**Quick fix shipping now (this session):** restrict `quality_score` and the digest's "Quality" section to facts created within the same 30-day window already used by `token_budget`. Surface a separate "historical" line so users can see both numbers, but the headline is the live one. This makes the metric actionable: a high live bare-conclusion rate = live LLM calibration drift; a high historical rate = legacy data, not a current alarm.

**Deferred to 0.12 / 1.x:**

1. The systemic `/study-repo` misattribution failure mode (cause 4) deserves its own guard. External-project READMEs being studied should land in `reference` predicates, not as `uses_database`/`deployment_platform`. Track this as a follow-up entry.
2. A backfill/cleanup pass on the 34 historical bare-conclusion facts: either retroactive rejection, or a one-shot reclassification that moves them to a `legacy_observation` predicate that the prompt's reason-clause requirement doesn't apply to.
3. The metric's calibration assumes "bare conclusion = bad", but spot-checking shows several flagged facts are perfectly informative ("MCP tools return dual content + structuredContent via TextSummary module") — they describe mechanics implicitly. The vocabulary may itself be too strict; revisit during 1.0 soak with real usage data.

**Process win:** the metric did its job — it surfaced a real signal that would otherwise have stayed invisible, and the investigation distinguished historical noise from live calibration. Without #48 we'd have no way to know.

---

## Executive Summary

Six days, +2,011 LOC. The headline finding: **the watch-list item from 2026-04-22 (#28 — extract per-endpoint helpers from `Dashboard::API`) was not just deferred, it actively regressed.** `dashboard/api.rb` grew from 627 → 807 LOC (+180, +29%), is now the only file in `lib/` over 750 lines, and gained four new methods all exceeding 15 lines. Method-size pressure increased: the previous worst case (`recall` at 39 lines) is now `timeline` at 52 lines, and the file has 11 methods over 15 lines (vs 11 last review) but with a higher mean.

The codebase is otherwise healthy. Five **new dashboard subsystems** (`moments.rb`, `reuse.rb`, `trust.rb`, `scoped_fact_resolver.rb`, plus `efficacy.rb` carried over) shipped with **direct spec files**. Three new schema migrations (v15/v16/v17) all wrap DDL with idempotent `create_table?` / `add_column` and have **per-migration specs plus round-trip specs from v12, v13, and v14 forward to v17** (a deliberate process improvement noted in `feedback_round_trip_migration_specs.md`). Four new sweep operations (`dedupe_open_conflicts`, `reclassify_references`) gained spec coverage in `sweep/maintenance_spec.rb`.

**What regressed:**
- `dashboard/api.rb` 627 → 807 LOC (+180). Watch-list item not addressed.
- `sweep/maintenance.rb` 334 → 456 LOC (+122). Two of the four new methods are 50+ lines (`dedupe_open_conflicts` 58, `restore_multi_value_supersessions` 57).
- Sleep-based test latency grew. `dashboard/moments_spec.rb` and `dashboard/api_spec.rb` add 4 more `sleep 1.1` calls (+4.4s wall). Total sleep-based test cost in suite is now ~8.4s, up from ~4s.
- One new code smell: `digest_command.rb:128` calls `Dashboard::Trust.new(manager).send(:utilization)` — reaches into a private method instead of exposing `utilization` on the public Trust API.

**What was resolved or improved since 2026-04-22:**
- Round-trip migration specs from v12/v13/v14 → v17 added (release-blocker per `feedback_round_trip_migration_specs.md`).
- Per-migration specs for v13–v17 added under `spec/claude_memory/store/migrations/`.
- New dashboard subsystems shipped *with* specs (good pattern — Reuse, Moments, Trust, Knowledge, ScopedFactResolver all have direct specs).
- `lib/claude_memory/store/sqlite_store.rb` only grew 40 LOC (544 → 584); regrowth controlled.

**New this review:** 4 items. 1 high-priority (Dashboard::API extraction, now urgent), 1 medium (`sweep/maintenance.rb` size), 1 low (`Time.parse` duplication across dashboard files), 1 quick win (`.send(:utilization)` smell in digest).

### Current Strengths

- Migrations now ship with per-migration specs **and** cross-version round-trip specs — a deliberate release-readiness improvement that landed during this window
- New dashboard subsystems all have direct specs; spec count grew 156 → 188 files (+32)
- Domain objects, frozen string literals, transaction wrapping, no raw SQL, no N+1 in hot paths — all preserved
- Five files >300 LOC last review; eight now, but mostly because of new modules carrying single responsibilities (Moments 244, Trust 284, Conflicts 285), not god-object regrowth

---

## 1. Sandi Metz Perspective

### What's Been Fixed ✅

- `SQLiteStore` regrowth held steady at 584 LOC after the 2026-04-22 LLMCache + MetricsAggregator extractions; only +40 LOC over 6 days, and that's adding two new tables (`moment_feedback`, `activity_events`) with their CRUD wrappers
- New dashboard subsystems each landed under 300 LOC with focused responsibilities
  - `Moments` (244 LOC) — feed-shape construction, no DB writes
  - `Trust` (284 LOC) — sidebar aggregations, all reads
  - `Reuse` (97 LOC) — top-N "most-used" panel
  - `Knowledge` (136 LOC) — fact summary panel
  - `ScopedFactResolver` (95 LOC) — pure helper
- Round-trip migration specs (`round_trip_v12_to_v17_spec.rb` etc.) — Sandi-style "test the contract, not the implementation"

### Critical Issues 🔴

#### A. `Dashboard::API` regressed: 627 → 807 LOC (+29%) — **carried-forward item became urgent**

`lib/claude_memory/dashboard/api.rb` was the watch-list item at the close of the 2026-04-22 review (#28). Six days later, instead of shrinking via per-endpoint extraction, it absorbed:

- `find_recall_trigger` (lib/claude_memory/dashboard/api.rb:193) — 32 lines, 5 SQL constructions, calls 3 helpers, JSON-parses event details
- `extract_user_prompt` (lib/claude_memory/dashboard/api.rb:237) — 29 lines, JSONL parsing, content type narrowing, plumbing-noise filtering
- `facts` (lib/claude_memory/dashboard/api.rb:373) — 39 lines (was 26), now also handles `stale_only` filtering with cross-store exclusion
- `facts_seen_in_recent_recalls` (lib/claude_memory/dashboard/api.rb:418) — 20 lines, scoped-pair aggregation
- `efficacy` (lib/claude_memory/dashboard/api.rb:439) — 31 lines (was 23), now branches on session_id with time-window correlation
- New micro-endpoints: `moments`, `trust`, `knowledge`, `reuse`, `moment_feedback`, `clear_moment_feedback`, `fact_detail`, `promote_fact`, `reject_fact`

The class now has **42 methods** (up from ~31) and **8 methods over 20 lines**. The methods that delegate cleanly (`conflicts`, `moments`, `trust`, `knowledge`, `reuse` — all 1-liners) are the right pattern; the rest of the file should follow that pattern.

**Method size table (current state):**

| Method | Line | Size | Concern |
|---|---|---|---|
| `timeline` | 471 | 52 | 3 separate Sequel aggregations + Ruby-side merge — should be `Dashboard::Timeline` |
| `vec_health` | 759 | 46 | Branchy status derivation over coverage stats |
| `recall` | 315 | 41 | Result flattening + bare rescue + actionable-hint branching |
| `facts` | 373 | 39 | Pagination + filter + cross-store stale exclusion |
| `activity_detail` | 149 | 37 | Joined fetch + linked facts + recall-trigger correlation |
| `hooks_health` | 704 | 32 | Multi-state status with fix messages |
| `find_recall_trigger` | 193 | 32 | Time-window query with session_id fallback |
| `efficacy` | 439 | 31 | Session-scope vs window-scope branching |
| `extract_user_prompt` | 237 | 29 | JSONL reverse-walk + plumbing filter |
| `session_summary` | 119 | 29 | Multi-event-type aggregation |
| `db_stats` | 647 | 28 | Predicate counts + entity counts + size stats |

**Proposed extractions** (each candidate is testable in isolation):

```ruby
# lib/claude_memory/dashboard/timeline.rb — pure aggregation
class Timeline
  def initialize(manager) = @manager = manager
  def days = { days: build_days }
  private
  def build_days
    return [] unless store
    fact_rows, content_rows, event_rows = load_aggregations
    merge_into_days(fact_rows, content_rows, event_rows)
  end
end

# lib/claude_memory/dashboard/health.rb — already 4 health checks (db, hooks, vec, vectors)
class Health
  def report = { status: overall(checks), checks: checks, version: VERSION }
  private
  def checks = [db_health("global"), db_health("project"), hooks_health, vec_health]
end

# lib/claude_memory/dashboard/recall_query.rb — wraps live recall + actionable error mapping
class RecallQuery
  def call(params) = format_response(run(params))
end

# lib/claude_memory/dashboard/recall_trigger_finder.rb — pure time-window correlation
# lib/claude_memory/dashboard/user_prompt_extractor.rb — pure JSONL parsing
# lib/claude_memory/dashboard/facts_query.rb — pagination + stale exclusion
```

After these extractions `api.rb` should drop to **~250 LOC** of routing-and-delegation. The pattern was already proven by `Conflicts` / `Moments` / `Trust` / `Knowledge` / `Reuse`.

**File:** `lib/claude_memory/dashboard/api.rb`
**Effort:** 4–6 hours (5 extractions, each with a focused spec)
**Priority:** 🔴 — was medium last review, escalates to high because the trend line points at 1,000+ LOC by next sprint if uncorrected
**Expert principle:** Sandi Metz SRP; Bernhardt boundaries; Beck simple design

### Medium Issues 🟡

#### B. `sweep/maintenance.rb` grew 334 → 456 LOC (+122, +37%)

Last review noted maintenance.rb at 334 (after dropping from 456 earlier — see the review's appendix B). It's now back at 456. Two large methods landed:

- `dedupe_open_conflicts` (lib/claude_memory/sweep/maintenance.rb:273) — 58 lines, multi-step transaction (group → resolve duplicates → reattach provenance → reject losers → mark conflicts resolved)
- `reclassify_references` (lib/claude_memory/sweep/maintenance.rb:340) — 26 lines, transactional cleanup that requires `Distill::ReferenceMaterialDetector`

Plus the pre-existing `restore_multi_value_supersessions` (line 185, 57 lines).

These are all *one-shot historical cleanups* (per their docstrings). They don't belong in the regular sweep cycle — they're admin operations. Two options:

1. **Extract to `Sweep::HistoricalCleanup`** — a separate module for one-shot data fixes
2. **Keep in Maintenance but extract long methods** — e.g. `dedupe_open_conflicts` calls `pair_key`, but the inner per-group logic (lib/claude_memory/sweep/maintenance.rb:294-326) is 32 lines that could be `resolve_duplicate_group(keeper, duplicates)`

**File:** `lib/claude_memory/sweep/maintenance.rb`
**Effort:** 2 hours
**Priority:** 🟡 Medium
**Expert principle:** Sandi Metz SRP; Beck single level of abstraction

#### C. `digest_command.rb:128` calls private API via `.send`

```ruby
# lib/claude_memory/commands/digest_command.rb:128
util = Dashboard::Trust.new(manager).send(:utilization)
```

This is the only `.send` to a private method in `lib/`. Two paths forward:

```ruby
# Option 1: Promote utilization to public on Trust (it already returns a documented Hash shape)
# lib/claude_memory/dashboard/trust.rb — remove `private` annotation above utilization

# Option 2: Extract Dashboard::Utilization as its own object
class Utilization
  def initialize(manager) = @manager = manager
  def report = { extracted:, used:, used_from_extracted:, ratio_pct:, window_days: }
end
```

Option 2 is cleaner — Trust currently *also* exposes `utilization` indirectly through `snapshot`, so users have two paths to the same data. Extracting the calculator gives Digest, Trust, and any future caller one canonical interface.

**File:** `lib/claude_memory/commands/digest_command.rb:128`
**Effort:** 30 minutes
**Priority:** 🟡 Medium (works correctly, but tells future readers "private is negotiable")
**Expert principle:** Avdi Grimm tell-don't-ask; Sandi Metz dependency clarity

### Low Issues

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 8 | `upsert_content_item` 11 keyword params (carried) | `store/sqlite_store.rb:193` | 1 hour |
| 32 | `parse_timestamp` duplicated in `dashboard/api.rb:565` and `dashboard/conflicts.rb:278` | both | 15 min |
| 33 | `stores_for(scope)` / `facts_stores_for(scope)` near-identical pattern | `dashboard/conflicts.rb:160`, `dashboard/api.rb:589` | 30 min |

---

## 2. Jeremy Evans Perspective

### What's Been Fixed ✅

- Migrations v15, v16, v17 all wrap DDL in idempotent `create_table?` / `add_column` and provide `down` blocks (v14's down is intentionally a no-op with comment)
- `Trust#extracted_fact_pairs` (lib/claude_memory/dashboard/trust.rb:231) and `used_fact_pairs` (line 248) batch via `select(:id)` + iteration — no per-row queries
- `Conflicts#load_facts_for_rows` (lib/claude_memory/dashboard/conflicts.rb:235) batches with `where(id: ids).as_hash(:id)` — explicit N+1 prevention

### Raw SQL Audit

No new raw SQL. The handful of `Sequel.lit` calls in `dashboard/api.rb` are all `DATE(...)` group-by helpers (lines 479, 487, 494) — required because Sequel doesn't have a portable `DATE(timestamp_string)` extractor for SQLite.

### Transaction Safety

New transactional methods all wrap correctly:
- `Sweep::Maintenance#dedupe_open_conflicts` — wraps in `@store.db.transaction` (line 289)
- `Sweep::Maintenance#reclassify_references` — wraps in `@store.db.transaction` (line 349)
- `SQLiteStore#upsert_moment_feedback` — wraps in `@db.transaction` (line 128)

### N+1 Audit (new dashboard panels)

- `Moments#build_moment` (lib/claude_memory/dashboard/moments.rb:125) calls `resolve_content` and `extracted_facts` per row. **Potential N+1 if a feed page surfaces 50 ingest moments.** `extracted_facts` runs `store.db[:facts].join(:provenance).where(content_item_id:)` per moment.
- `Trust#count_open_conflicts` (lib/claude_memory/dashboard/trust.rb:145) → `Conflicts#distinct_open_counts` walks both stores. Acceptable (fixed cardinality of 2).
- `Trust#used_fact_pairs` (lib/claude_memory/dashboard/trust.rb:248) loads up to N=500 events without limit. Could grow unbounded. Recommend explicit `.limit(...)` for safety.

**Recommendation:**
- Batch `extracted_facts` in `Moments`: collect all `content_item_id`s up front, run one `where(content_item_id: ids)` join, group results in Ruby.
- Add explicit `.limit` to `used_fact_pairs` (10,000 is a safe ceiling for a 30-day window).

**File:** `lib/claude_memory/dashboard/moments.rb:125,231`
**Effort:** 45 minutes
**Priority:** 🟡 Medium (will only bite at scale; fix proactively)
**Expert principle:** Jeremy Evans dataset hygiene

---

## 3. Kent Beck Perspective

### What's Been Fixed ✅

- **Migration spec coverage hit gold standard.** Per-migration specs for v13/v14/v15/v16/v17 + cross-version round-trips from v12, v13, and v14 all forward to v17. That's the canonical "test the seam" pattern. The lessons from `feedback_round_trip_migration_specs.md` are now codified in green tests.
- New commands `digest_command.rb` and `census_command.rb` shipped with direct specs
- New dashboard modules all have direct specs (`moments_spec.rb`, `reuse_spec.rb`, `trust_spec.rb`, `knowledge_spec.rb`, `scoped_fact_resolver_spec.rb`)

### High Priority Issues

#### D. Two new commands shipped without specs

| Command | LOC | Spec? |
|---|---|---|
| `commands/dedupe_conflicts_command.rb` | 55 | ❌ none |
| `commands/reclassify_references_command.rb` | 56 | ❌ none |

Both are thin wrappers over `Sweep::Maintenance` (which *is* tested), but the CLI-layer concerns — option parsing, scope routing, output format, dry-run flag flow-through — are uncovered.

The output format in particular has logic worth pinning:
- `dedupe_conflicts_command.rb:38-52` decides `DRY RUN` vs `DEDUPE`, separator length, decisions header
- `reclassify_references_command.rb:38-53` truncates objects to 100 chars + ellipsis

**Proposed:** Mirror `digest_command_spec.rb` (or `census_command_spec.rb`) — test option parsing, dry-run paths, and stdout shape via injected `StringIO`.

**Effort:** 30 min each (60 min total)
**Priority:** High — these are admin commands that mutate data; CLI ergonomics belong under test

#### E. `dashboard/server.rb` still untested

Carried over from 2026-04-22. The file has grown 189 → 211 LOC (+22) due to new endpoints (moments feedback POST/DELETE, conflict reject_similar). All branching is inside the request router (`handle_moments`, `handle_conflicts`).

WEBrick HTTP testing is awkward but not impossible — `Rack::MockRequest` works against the API class directly. Alternatively, exercise the routing by injecting a stub WEBrick request object.

**Effort:** 1.5 hours
**Priority:** Medium-Low

### Sleep-Based Test Latency Increased

Total sleep-based test cost in `bundle exec rspec`:

| Spec | sleep total | Notes |
|---|---|---|
| `spec/claude_memory/ingest/ingester_spec.rb` | 3.03s | mtime resolution, carried |
| `spec/claude_memory/publish_spec.rb` | 1.1s | carried |
| `spec/claude_memory/recall_spec.rb` | 0.01s | carried |
| `spec/claude_memory/dashboard/moments_spec.rb` | 2.2s | **NEW** ordering of activity events |
| `spec/claude_memory/dashboard/api_spec.rb` | 2.2s | **NEW** activity ordering tests |
| **Total** | **~8.5s** | up from ~4s last review |

The dashboard sleeps are because activity_events ordering depends on `occurred_at` ISO timestamps, and successive inserts in <1s produce the same timestamp. Two fixes:

```ruby
# Option 1: Inject explicit timestamps (already supported via insert column)
store.activity_events.insert(occurred_at: Time.now.utc.iso8601, ...)
store.activity_events.insert(occurred_at: (Time.now + 1).utc.iso8601, ...)

# Option 2: Stub Time.now via Timecop or RSpec's allow(Time).to receive(:now)
```

Option 1 requires no extra dep. Either eliminates 4.4s of wall time.

**File:** `spec/claude_memory/dashboard/moments_spec.rb:130,132`, `api_spec.rb:332,359`
**Effort:** 30 minutes
**Priority:** 🟡 Medium (test speed degrades CI loop)
**Expert principle:** Kent Beck fast feedback

### Carried-Forward Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 11 | No shared test factory | `spec/spec_helper.rb` | 1 hour |

---

## 4. Avdi Grimm Perspective

### What's Been Fixed ✅

- New code uses scoped rescues (`rescue Sequel::DatabaseError, JSON::ParserError`) over bare rescues by default. Of 18 new rescue clauses in dashboard files, **13 are scoped to specific exception types**, 5 are bare and all return safe defaults
- `Result` pattern preserved in embeddings paths
- `Core::RelativeTime.format` used consistently across new dashboard modules

### Bare Rescue Audit (full lib/, current count: 19 bare rescues)

The count grew from 5 → 19 because new dashboard code added 5 in `api.rb`. All are defensive (return safe shape):

| Location | Context | Returns | Verdict |
|---|---|---|---|
| `mcp/handlers/stats_handlers.rb:102` | `fts_legacy?` | `false` | Acceptable — boolean check |
| `mcp/instructions_builder.rb:147` | `vec_available?` | `false` | Acceptable |
| `sweep/maintenance.rb:140` | FTS prune | skips row | Acceptable |
| `commands/hook_command.rb:102` | forked handler | `nil` | Required |
| `commands/stats_command.rb:276` | `check_fts_format` | no-op | Acceptable |
| **`dashboard/api.rb:340` (new)** | recall live query | error hash | Acceptable — wide net for unfamiliar errors from Recall pipeline |
| **`dashboard/api.rb:672` (new)** | `db_stats` aggregation | `{exists:, error:}` | Acceptable |
| **`dashboard/api.rb:693` (new)** | `db_health` introspection | error hash | Acceptable |
| **`dashboard/api.rb:728` (new)** | `hooks_health` JSON read | error hash | Acceptable |
| **`dashboard/api.rb:797` (new)** | `vec_health` | error hash | Acceptable |

Verdict: per `Style/RescueStandardError` in Standard Ruby (rejected explicit-rescue change in last review), these are correct. **No action.**

### Carried-Forward Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 13 | Inconsistent payload validation | `hook/handler.rb:53-82` | 30 min |

Verified still present.

### New Concern

#### F. `digest_command.rb:128` reaches into `Trust`'s private API

Documented above (#C). Repeating here under the Avdi lens: the explicit `.send` is a public-API smell. Either the method shouldn't be private, or there should be a public wrapper. Choose.

---

## 5. Gary Bernhardt Perspective

### What's Been Fixed ✅

- New dashboard modules continue to honor the imperative-shell / functional-core split:
  - `Trust` does only reads + transformation (no writes)
  - `Moments` does reads + transformation
  - `Reuse` does reads + transformation
  - `Efficacy::Reporter` is **pure** (no DB) — takes events, returns a hash — Bernhardt's dream
- `Knowledge#summary` returns shaped data; UI logic stays out of the model
- New value-object-y data: `KIND_TO_EVENT_TYPES`, `FEED_EVENT_TYPES` are frozen module constants

### Boundaries

```
HTTP layer:    Dashboard::Server (211 LOC, untested)         ← imperative shell
JSON layer:    Dashboard::API (807 LOC ⚠ growing)            ← needs to shrink to routing
Subsystems:    Conflicts, Moments, Trust, Knowledge, Reuse   ← functional core (good)
Pure helpers:  Efficacy::Reporter, ScopedFactResolver        ← pure (excellent)
Query layer:   Recall, store datasets                        ← impure but isolated
```

`API` is the wrong layer to be doing JSONL parsing (`extract_user_prompt`), time-window correlation (`find_recall_trigger`), or 3-source aggregation (`timeline`). Each of those wants to be its own pure object.

### Test Speed Regression

Sleep-based tests are dollar-bills the suite is burning every CI run. Eliminating them is functional-core hygiene — the test should pin behavior, not wait for clock state.

### Carried-Forward Issues 🟡

| # | Issue | File:Line | Effort |
|---|---|---|---|
| 15 | Sweeper mutable state | `sweep/sweeper.rb:16-17` | 20 min |
| 16 | `Dir.chdir` in publish tests | `spec/publish_spec.rb:14` | 15 min |

---

## 6. General Ruby Idioms

### New Items

| # | Issue | File:Line | Severity | Effort |
|---|---|---|---|---|
| 31 | `Dashboard::API` 807 LOC, 11 methods >15 lines (regression of #28) | `dashboard/api.rb` | 🔴 High | 4–6 hours |
| 32 | `parse_timestamp(value)` duplicated verbatim in api.rb:565 and conflicts.rb:278 | both | 🟢 Low | 15 min |
| 33 | `stores_for` / `facts_stores_for` near-identical between Conflicts and API | `conflicts.rb:160`, `api.rb:589` | 🟢 Low | 30 min |
| 34 | `digest_command.rb:128` uses `.send(:utilization)` to call private | `digest_command.rb:128` | 🟡 Medium | 30 min |
| 35 | Sleep-based dashboard tests add 4.4s to suite | `dashboard/{moments,api}_spec.rb` | 🟡 Medium | 30 min |
| 36 | DedupeConflictsCommand and ReclassifyReferencesCommand untested | `commands/` | High | 60 min |
| 37 | `sweep/maintenance.rb` regrew to 456 LOC; 3 methods >50 lines | `sweep/maintenance.rb` | 🟡 Medium | 2 hours |
| 38 | `Moments#extracted_facts` per-moment join (potential N+1 at 50-row pages) | `moments.rb:231` | 🟡 Medium | 30 min |

### Carried-Forward Items

| # | Issue | File:Line | Severity | Effort |
|---|---|---|---|---|
| 17 | ResponseFormatter duplication | `mcp/response_formatter.rb` | 🟡 Medium | 1 hour |
| 28 | ~~Dashboard::API method extraction~~ — **escalated to #31** | — | — | — |
| 8 | `upsert_content_item` 11 keyword params | `store/sqlite_store.rb:193` | 🟢 Low | 1 hour |
| 10 | Sleep-based ingester tests | `spec/ingest/ingester_spec.rb` | 🟢 Low | 1 hour |
| 11 | No shared test factory | `spec/spec_helper.rb` | 🟢 Low | 1 hour |

---

## 7. Positive Observations

- **Migration discipline** — round-trip specs, per-migration specs, idempotent DDL. The "treat round-trip migration specs as a release blocker" lesson from `feedback_round_trip_migration_specs.md` got operationalized in 5 days
- **New commands ship with specs** — DigestCommand and CensusCommand both got direct specs; the two that didn't (Dedupe + Reclassify) are 55-line wrappers over already-tested Maintenance methods, so the gap is small
- **Dashboard subsystem decomposition** — when 5 new panels (Moments, Reuse, Trust, Knowledge, ScopedFactResolver) all land as their own classes with their own specs, the module-extraction muscle is strong
- **`Efficacy::Reporter` purity** — 128 LOC, zero I/O, takes events and returns shape. Spec is fast and readable. This is the model the rest of dashboard/ should converge on
- **No raw SQL added; no N+1 in hot paths; transaction safety maintained** — across +2,011 LOC in 6 days

---

## 8. Priority Refactoring Recommendations

### High Priority (This Week — pre-0.10.0 release)

| # | Item | File:Line | Effort | Impact |
|---|---|---|---|---|
| 31 | Extract `Dashboard::Timeline` / `Health` / `RecallQuery` / `RecallTriggerFinder` / `UserPromptExtractor` / `FactsQuery` from API | `dashboard/api.rb` | 4–6 hours | API drops 807→~250 LOC; reverses regression |
| 36 | Add `dedupe_conflicts_command_spec.rb` + `reclassify_references_command_spec.rb` | `spec/claude_memory/commands/` | 1 hour | CLI surface tested |

### Medium Priority (Next Sprint)

| # | Item | File:Line | Effort |
|---|---|---|---|
| 34 | Promote `Trust#utilization` to public OR extract `Dashboard::Utilization` | `dashboard/trust.rb`, `digest_command.rb:128` | 30 min |
| 35 | Replace sleep-based dashboard tests with explicit timestamps | `dashboard/{moments,api}_spec.rb` | 30 min |
| 37 | Extract long methods from `sweep/maintenance.rb` (`dedupe_open_conflicts`, `restore_multi_value_supersessions`) OR move one-shot cleanups to `Sweep::HistoricalCleanup` | `sweep/maintenance.rb` | 2 hours |
| 38 | Batch `Moments#extracted_facts` to avoid 50-row N+1 | `moments.rb:231` | 30 min |
| 17 | ResponseFormatter consolidation (carried) | `mcp/response_formatter.rb` | 1 hour |
| 13 | Payload validator for hook events (carried) | `hook/handler.rb` | 30 min |
| E | `dashboard/server_spec.rb` (carried) | `spec/claude_memory/dashboard/` | 1.5 hours |

### Low Priority (Later)

| # | Item | Effort |
|---|---|---|
| 32 | DRY `parse_timestamp` (`api.rb:565` ↔ `conflicts.rb:278`) | 15 min |
| 33 | DRY `stores_for` / `facts_stores_for` | 30 min |
| 8 | `ContentItemAttributes` value object | 1 hour |
| 10 | Replace sleep-based ingester tests | 1 hour |
| 11 | Shared test factory | 1 hour |
| 15 | Sweeper mutable state | 20 min |
| 16 | `Dir.chdir` in publish tests | 15 min |

### Quick Wins (Today)

| # | Item | Effort |
|---|---|---|
| 32 | Extract `parse_timestamp` to `Core::RelativeTime` (it already lives there as a value module) | 15 min |
| 34 | Promote `Trust#utilization` to public | 5 min |
| 35 | Inject timestamps into dashboard spec inserts | 30 min |

---

## 9. Conclusion

In 6 days the codebase grew 12% (+2,011 LOC). Most of that growth was healthy — five new dashboard subsystems with specs, three migrations with both per-version and round-trip specs, two new admin commands wrapping already-tested maintenance methods. Migration discipline in particular leveled up: the lesson from `feedback_round_trip_migration_specs.md` shipped as actual release-blocking spec coverage.

**The headline regression is `Dashboard::API`.** Last review marked it medium-priority for per-endpoint extraction. Six days later it's gained 180 LOC, four new methods over 15 lines, and one method (`timeline`) that's now 52 lines. This is the file that most rewards extraction — it's already surrounded by collaborators (`Conflicts`, `Moments`, `Trust`, `Knowledge`, `Reuse`) that prove the per-endpoint pattern works. Doing the extraction now reverses the trend; deferring lets it accumulate another 200 LOC by next review.

**Recommended next-action set, in order:**

1. **`/quality-update`** to apply #31 (Dashboard::API extraction) and #36 (missing command specs). Target: api.rb ≤ 300 LOC, all commands tested.
2. Quick wins #32 + #34 + #35 in the same session (~75 min total).
3. Schedule #37 and #38 for the next sprint — neither is urgent but both compound if left alone.
4. After #31 lands, `/review-for-quality` again pre-0.10.0 release to confirm the regression closed.

The 0.10.0 release should not ship with `dashboard/api.rb` at 807 LOC — the per-endpoint extraction is well-defined, well-precedented, and small-batch (5 extractions × ~1hr each). Doing it before tag is the difference between landing 0.10.0 with a healthy dashboard subsystem vs. burying tech debt in the headline feature of the release.

---

## Appendix A: Metrics Comparison

| Metric | Mar 9 | Mar 19 | Apr 22 (review) | Apr 22 (after update) | **Apr 28 (this review)** |
|---|---|---|---|---|---|
| Ruby files (lib) | 112 | 117 | 148 | 150 | **161** (+11 new modules) |
| LOC (lib) | 11,392 | 12,239 | 17,014 | 17,031 | **19,025** (+2,011) |
| LOC (spec) | 21,632 | 22,563 | 28,074 | 28,490 | **31,079** (+2,605) |
| Spec files | 128 | 122 | 154 | 156 | **188** (+32) |
| Test-to-code ratio | 1.90:1 | 1.84:1 | 1.65:1 | 1.67:1 | **1.63:1** ⬇️ |
| Files >500 lines | 3 | 0 | 2 | 1 | **2** ⬆️ (api.rb 807, sqlite_store.rb 584) |
| Files >300 lines | 9 | 9 | 10 | 8 | **8** (same count, different mix) |
| Bare rescues (justified) | 1 | 0 | 5 | 5 | **19** (14 new, all defensive) |
| Bare rescues (unsafe) | 0 | 0 | 0 | 0 | **0** ✅ |
| N+1 patterns (hot paths) | 0 | 0 | 0 | 0 | **0** ✅ |
| Pure logic classes | 20+ | 22+ | 25+ | 27+ | **32+** (+5 new dashboard modules) |
| Migration round-trip specs | 0 | 0 | 0 | 0 | **3** (v12→v17, v13→v17, v14→v17) ✅ |
| Per-migration specs | 0 | 0 | 0 | 0 | **13** (001–017 minus a few) ✅ |
| Sleep-based test cost | — | — | ~4s | ~4s | **~8.5s** ⬆️ |
| Untested new commands | — | — | 0 | 0 | **2** (dedupe-conflicts, reclassify-references) |
| Known correctness bugs | — | 0 | 0 | 0 | **0** ✅ |

## Appendix B: File Size Report

| File | Mar 19 | Apr 22 (review) | Apr 22 (after update) | **Apr 28 (this review)** | Trend |
|---|---|---|---|---|---|
| `dashboard/api.rb` | — | 627 🆕 | 627 | **807** | ⬆️ +180 (+29%) — **regression** |
| `store/sqlite_store.rb` | 386 | 683 | 544 | **584** | ⬆️ +40 (new tables) |
| `mcp/tool_definitions.rb` | 334 | 459 | 459 | **459** | — |
| `sweep/maintenance.rb` | — | 334 | 334 | **456** | ⬆️ +122 — new |
| `mcp/response_formatter.rb` | 396 | 397 | 397 | **397** | — |
| `commands/stats_command.rb` | 250 | 346 | 346 | **383** | ⬆️ +37 |
| `recall/query_core.rb` | 357 | 371 | 371 | **371** | — |
| `mcp/text_summary.rb` | 258 | 313 | 313 | **313** | — |
| `dashboard/conflicts.rb` | — | 195 | 195 | **285** | ⬆️ +90 (dedup grouping logic) |
| `dashboard/trust.rb` | — | — | — | **284** | 🆕 new feed-first sidebar |
| `resolve/resolver.rb` | 195 | 254 | 254 | **268** | ⬆️ +14 (dedupe + scope_hint fix) |
| `mcp/tools.rb` | 104 | 249 | 249 | **264** | ⬆️ +15 |
| `commands/index_command.rb` | 272 | 259 | 259 | **259** | — |
| `commands/hook_command.rb` | 214 | 215 | 215 | **249** | ⬆️ +34 |
| `publish.rb` | 221 | 256 | 248 | **248** | — |
| `dashboard/moments.rb` | — | — | — | **244** | 🆕 feed primitive |
| `commands/uninstall_command.rb` | 226 | 226 | 226 | **226** | — |
| `hook/context_injector.rb` | — | 214 | 214 | **225** | ⬆️ +11 |
| `store/store_manager.rb` | — | 215 | 215 | **215** | — |
| `infrastructure/schema_validator.rb` | 215 | 215 | 215 | **215** | — |
| `commands/census_command.rb` | — | — | — | **210** | 🆕 predicate census |
| `mcp/handlers/setup_handlers.rb` | 211 | 211 | 211 | **211** | — |
| `dashboard/server.rb` | — | 189 | 189 | **211** | ⬆️ +22 (new endpoints) |
| `embeddings/model_registry.rb` | — | — | — | **210** | 🆕 |
| `mcp/server.rb` | — | 206 | 206 | **206** | — |
| `mcp/handlers/stats_handlers.rb` | — | 205 | 205 | **205** | — |
| `commands/initializers/hooks_configurator.rb` | — | — | — | **200** | — |
| `commands/embeddings_command.rb` | — | — | — | **198** | — |
| `ingest/ingester.rb` | — | — | — | **190** | — |
| `index/vector_index.rb` | 184 | 184 | 184 | **184** | — |
| `commands/digest_command.rb` | — | — | — | **181** | 🆕 weekly digest |
| `mcp/handlers/management_handlers.rb` | — | — | — | **177** | — |
| `ingest/observation_compressor.rb` | — | — | — | **177** | 🆕 tool-specific compression |
| `recall.rb` | 94 | 175 | 175 | **175** | — |
| `core/fact_query_builder.rb` | — | — | — | **174** | — |
| `mcp/error_classifier.rb` | — | — | — | **171** | — |
| `embeddings/generator.rb` | — | — | — | **165** | — |
| `index/lexical_fts.rb` | — | — | — | **153** | — |
| `dashboard/knowledge.rb` | — | — | — | **136** | 🆕 |
| `dashboard/efficacy.rb` | — | 127 | 127 | **127** | — |
| `dashboard/fact_presenter.rb` | — | 109 | 109 | **109** | — |
| `dashboard/reuse.rb` | — | — | — | **97** | 🆕 |
| `dashboard/scoped_fact_resolver.rb` | — | — | — | **95** | 🆕 |
| `commands/reclassify_references_command.rb` | — | — | — | **56** | 🆕 (untested) |
| `commands/dedupe_conflicts_command.rb` | — | — | — | **55** | 🆕 (untested) |

## Appendix C: Methods >15 Lines in Watch-List Files

### `dashboard/api.rb` (807 LOC, **42 methods**)

| Method | Line | Size | Action |
|---|---|---|---|
| `timeline` | 471 | 52 | Extract `Dashboard::Timeline` |
| `vec_health` | 759 | 46 | Extract into `Dashboard::Health` |
| `recall` | 315 | 41 | Extract `Dashboard::RecallQuery` |
| `facts` | 373 | 39 | Extract `Dashboard::FactsQuery` |
| `activity_detail` | 149 | 37 | Extract event-detail builder |
| `hooks_health` | 704 | 32 | Extract into `Dashboard::Health` |
| `find_recall_trigger` | 193 | 32 | Extract `Dashboard::RecallTriggerFinder` |
| `efficacy` | 439 | 31 | Move session-window logic into `Efficacy::Loader` |
| `extract_user_prompt` | 237 | 29 | Extract `Dashboard::UserPromptExtractor` |
| `session_summary` | 119 | 29 | Extract aggregator |
| `db_stats` | 647 | 28 | Extract into `Dashboard::Health` |
| `db_health` | 676 | 25 | Extract into `Dashboard::Health` |
| `load_content_item` | 603 | 21 | Could move into `FactPresenter` or its own loader |
| `activity` | 48 | 20 | Acceptable — thin wrapper |
| `facts_seen_in_recent_recalls` | 418 | 20 | Move into `Dashboard::FactsQuery` |
| `collect_configured_hook_types` | 739 | 19 | Move into `Dashboard::Health` |
| `serialize_recall_fact` | 545 | 19 | Move into `Dashboard::RecallQuery` |
| `health` | 14 | 18 | Becomes 3-liner after `Dashboard::Health` extraction |
| `reject_fact` | 294 | 16 | Acceptable — public surface |

### `sweep/maintenance.rb` (456 LOC)

| Method | Line | Size | Action |
|---|---|---|---|
| `dedupe_open_conflicts` | 273 | 58 | Extract per-group `resolve_duplicate_group` helper |
| `restore_multi_value_supersessions` | 185 | 57 | Already documented; could extract `compute_restore_decisions` |
| `dedupe_multi_value_facts` | 58 | 34 | Acceptable — well-bounded transactional op |
| `reclassify_references` | 340 | 26 | Acceptable |
| `prune_old_content` | 130 | 16 | Acceptable |

### `store/sqlite_store.rb` (584 LOC)

| Method | Line | Size | Notes |
|---|---|---|---|
| `upsert_content_item` | 193 | 27 | 11 kwargs (carried #8) |
| `reject_fact` | 410 | 25 | Conflict resolution in transaction |
| `insert_fact` | 332 | 22 | Many optional fields |
| `upsert_moment_feedback` | 123 | 21 | New — transaction with retry |
| `update_fact` | 373 | 19 | Generic update via allowed-keys |

---

## Historical Reviews

Earlier reviews (Jan 29, Feb 4, Mar 9, Mar 19) tracked the codebase from ~8,000 → 12,239 LOC. Their highlights, preserved here:

- **Jan 29 (initial)** — Identified Tools and Recall god-object risks; introduced first metrics baseline.
- **Feb 4** — Carried-forward items #17–#25 (DateTime migration, command manager helper, release_connections polymorphism, provenance batch insert, result objects). All still low-priority and open.
- **Mar 9** — Three files >500 LOC; bare rescue counted; vector index work landed.
- **Mar 19** — Successful refactor wave: `RetryHandler` + `SchemaManager` extracted from `SQLiteStore` (547 → 386); `Tools` reduced to 104-line dispatcher with 6 handler modules; `Recall` to 94-line facade. **Established the module-inclusion pattern** that has been reused successfully for LLMCache, MetricsAggregator, and the dashboard subsystems.

The 2026-04-22 review absorbed the 39% codebase growth (+4,775 LOC) without correctness regressions and resolved its top two watch-items (`SQLiteStore` regrowth, dashboard test coverage). It left `Dashboard::API` extraction as a medium-priority watch item — which the present review (2026-04-28) escalates to high-priority based on the 180-LOC regression in 6 days.

---

**Next review:** After #31 (Dashboard::API extraction) lands, or pre-0.10.0 release tag.
