# Improvements to Consider

*Updated: 2026-06-16 - Added #69 (self-heal the FTS rank index after concurrent ingest — live incident: hook-vs-MCP write contention leaves `ORDER BY rank` malformed while data stays intact, silently degrading recall until a manual `compact`). Earlier 2026-06-16 - Added Mastra Observational Memory study — one High Priority item (#68, episodic observation layer: Observer + Reflector + observation→fact promotion bridge) and one Medium item (compression/cache telemetry + LongMemEval episodic suite). Key insight: ClaudeMemory has no episodic layer; observations ("what happened") complement facts ("what is true"). See `docs/influence/mastra-observational-memory.md`. Previously: 2026-05-23 - Added AI Memory Systems Landscape Analysis (Nakajima/Opus 4.6 Research article, 2026-03-26) — meta-study of 7 benchmarks + ~12 systems. Four High Priority items: graph traversal as third RRF source (#64), temporal-aware retrieval (#65), bi-temporal schema cleanup (#66), LongMemEval integration (#67). One promotion: improvement #57 (provenance-strength ranking) Medium → High, validated as the "soft epistemic separation" pattern. See `docs/influence/ai-memory-systems-2026.md`. Previously: 2026-05-01 - Added Strands Agent SOPs study (article, not repo) — one M-priority item (parameter blocks in skill frontmatter); rest already implemented or deferred. See `docs/influence/strands-agent-sops.md`. Previously: 2026-04-28 (post-0.10.0) - Restructured 1.0 punchlist around milestone versions. **0.11.0 "Trust & Cost"** ships #47 (token budget), #48 (hallucination rate), #51 (claude-memory show), #53 (first-week ROI nudge — moved up from post-1.0), and a 3-scenario prototype of #49 (harm benchmark). **0.12.0 "Release Discipline"** ships #49 full corpus, #50 (CLAUDE.md baseline), #52 (benchmark scoreboard). **1.0.0** lands soak-validated #54/#55/#56 if time + new #59 API stability audit. See `docs/1_0_punchlist.md` for the full plan with calendar targets. Also added 2026-04-28: two ranking-signal gaps surfaced by the Mercury / "Why Karpathy's Second Brain Breaks" article (Zaid, 2026-04-28) — provenance-strength-aware ranking (#57) and reinforcement/decay scoring (#58). Earlier 2026-04-28 updates: opened the 1.0 punchlist track + added cq study. Previously: 2026-03-30 - Re-studied all 7 influencer repos. New recommendations: CLAUDE_CONFIG_DIR support (#26, from episodic-memory), Usage Stats / ROI Tracking (#27, from grepai v0.35.0). New Features to Avoid: AST-Aware Code Chunking (QMD), Custom Instructions via Env Var (lossless-claw v0.5.2), OpenClaw Context Injection (claude-mem v10.6.0). Repos with no changes: kbs (v0.2.1), claude-supermemory (v2.0.1), episodic-memory (v1.0.15). Previously: 14 features implemented through 2026-03-24.*
*Sources:*
- *[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.6.3, re-studied 2026-03-30)*
- *[obra/episodic-memory](https://github.com/obra/episodic-memory) - Semantic conversation search (v1.0.15, re-studied 2026-03-30 — no changes)*
- *[yoanbernabeu/grepai](https://github.com/yoanbernabeu/grepai) - Semantic code search (v0.35.0, re-studied 2026-03-30)*
- *[supermemoryai/claude-supermemory](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed persistent memory (v2.0.1, re-studied 2026-03-30 — no changes)*
- *[tobi/qmd](https://github.com/tobi/qmd) - On-device hybrid search engine (v2.0.1+unreleased, re-studied 2026-03-30)*
- *[MadBomber/kbs](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1, studied 2026-03-30 — no changes)*
- *[martian-engineering/lossless-claw](https://github.com/martian-engineering/lossless-claw) - DAG-based lossless context management (v0.5.2, re-studied 2026-03-30)*
- *[Mastra Observational Memory](https://mastra.ai/blog/observational-memory) - Text-based dual-agent episodic memory (studied 2026-06-16)*

This document contains only unimplemented improvements. Completed items are removed.

---

## High Priority

### ~~1. Native Vector Storage (sqlite-vec)~~ ✅ Implemented 2026-03-04

Schema migration v12 with `facts_vec` virtual table (vec0, cosine distance). Two-step query pattern (KNN → batch hydration). VectorIndex class with native C KNN search, fallback to O(n) Ruby. Backfill via `claude-memory index --vec` and sweeper. Doctor check with coverage stats. Cross-platform: arm64-darwin, x86_64-darwin, x86_64-linux.

### ~~2. Claude Code Plugin Distribution Format~~ ✅ Implemented 2026-03-04

Plugin packaging with `plugin.json` referencing MCP server, hooks, skills, commands, and output styles. Wrapper scripts (`scripts/serve-mcp.sh`, `scripts/hook-runner.sh`) handle gem detection gracefully. Initializers detect plugin mode via `CLAUDE_PLUGIN_ROOT` and skip hooks/MCP/output-style config. Version sync Rake task keeps plugin metadata in sync with gem version.

### ~~3. Intent Parameter for Recall~~ ✅ Implemented 2026-03-23

Optional `intent` parameter added to `Recall#query`, `#query_index`, and `#query_semantic`. Threaded through DualEngine/LegacyEngine via `QueryCore#intent_augmented_query`. Intent appended to search query (0.5x weight for chunk selection, 0.3x for semantic). Disables BM25 shortcut when intent provided so vector search always runs. Exposed via `memory.recall`, `memory.recall_index`, and `memory.recall_semantic` MCP tools.

### ~~4. MCP Tool Annotations~~ ✅ Implemented 2026-03-09

Added `readOnlyHint`, `idempotentHint`, `destructiveHint` annotations to all 23 MCP tools via shared constants (READ_ONLY, WRITE, WRITE_IDEMPOTENT). 19 query tools marked read-only, store_extraction/sweep_now/mark_distilled as write, promote as write-idempotent.

### ~~5. Retrieval Score Traces~~ ✅ Implemented 2026-03-20

Added `explain: true` parameter to `memory.recall_semantic` MCP tool. When enabled, each result includes `score_trace` with `vec_rank`, `vec_score`, `vec_rrf`, `fts_rank`, `fts_score`, `fts_rrf`, and `rrf_final`. Threaded through Recall → DualEngine/LegacyEngine → QueryCore → RRFusion. Components show nil for sources that didn't contribute.

### ~~6. MCP Stdout Protection Audit~~ ✅ Implemented 2026-03-09

ServeMcpCommand captures real stdout for MCP transport, redirects `$stdout` to `$stderr` during serve. Accidental puts/print from gems goes to stderr. Restore via ensure block.

### ~~7. Worktree-Aware Git Root Detection~~ ✅ Implemented 2026-03-09

Configuration#project_dir uses `git rev-parse --git-common-dir` to resolve main repo root across worktrees. `CLAUDE_MEMORY_ISOLATE_WORKTREES` env var opts into per-worktree isolation. Uses Open3.capture2 with graceful fallback to Dir.pwd.

### ~~8. Search Agent Delegation Pattern~~ ✅ Implemented 2026-03-20

Created `memory-recall.md` agent definition that chains recall → explain → fact_graph with 4-step workflow (fast lookup → semantic search → enrich → synthesize). Available as `/memory-recall` slash command after installation. Bundled in plugin commands directory and installable via `claude-memory install-skill memory-recall`.

### ~~9. Self-Excluding Agent Conversations~~ ✅ Implemented 2026-03-09

Added `SELF_CONTEXT_MARKER` constant (`claude-memory-self`) to ClaudeMemory module. Added to ingester EXCLUSION_TAGS. Transcripts containing `<claude-memory-self>` are skipped entirely, preventing meta-conversation pollution.

### ~~10. Dedicated Maintenance Class~~ ✅ Implemented 2026-03-16

Extracted `Sweep::Maintenance` class from Sweeper with 8 individual operations, each returning affected counts: `expire_proposed_facts`, `expire_disputed_facts`, `prune_orphaned_provenance`, `prune_old_content`, `backfill_vec_index`, `cleanup_vec_expired`, `checkpoint_wal`, `vacuum`. Sweeper now delegates to Maintenance internally.

### ~~11. Dynamic MCP Instructions Enhancement~~ ✅ Implemented 2026-03-16

Enhanced InstructionsBuilder with knowledge summary (decision/convention/entity counts by predicate pattern), vec availability detection, and dynamic usage tips that adapt based on available capabilities. Semantic search guidance included when sqlite-vec is loaded.

### ~~12. Embedded Skill Distribution~~ ✅ Implemented 2026-03-20

Added `claude-memory install-skill` command. Skills shipped as markdown files in `lib/claude_memory/commands/skills/`. Supports `--list`, `--force`, and auto-creates `~/.claude/commands/` directory. Registry-based design supports future skill additions. Paired with Search Agent Delegation (#8).

### ~~13. Depth-Aware Prompt Templates for Distiller~~ ⭐ Partially Implemented 2026-03-24

Source: lossless-claw v0.3.0 study (2026-03-16)

Three-layer automatic distillation pipeline: (1) NullDistiller wired into ingest hooks for instant regex extraction on Stop/SessionStart/PreCompact/SessionEnd/TaskCompleted/TeammateIdle, (2) Context hook injection at SessionStart includes undistilled content with extraction instructions — Claude Code acts as the LLM distiller at zero extra cost, (3) `/distill-transcripts` skill for manual deep extraction. New MCP tools: `memory.undistilled`, `memory.mark_distilled`. Depth-aware prompt selection (initial vs consolidation vs contradiction) deferred to skill enhancement — no Ruby code needed, just skill file edits.

### ~~14. Three-Level Escalation for Sweep/Maintenance~~ ✅ Implemented 2026-03-16

Added `run_with_escalation!` to Sweeper: normal (standard TTLs) → aggressive (halved TTLs) → fallback (force-expire oldest 10 proposed/disputed). Stats include `:escalation_level`. MCP `memory.sweep_now` gains `escalate: true` parameter. TextSummary shows escalation level in output.

### ~~15. Tool Escalation Workflow in MCP Instructions~~ ✅ Implemented 2026-03-16

Restructured QueryGuide with 4-tier escalation hierarchy (Fast Lookup → Broad Search → Targeted Deep Dive → Relationship Exploration). Each tool annotated with cost estimates (tokens per call). Added "Recommended Workflow" section. InstructionsBuilder usage hint updated with escalation guidance.

### ~~16. Structured Error Classification~~ ✅ Implemented 2026-03-16

Added `MCP::ErrorClassifier` with three-tier classification: benign (empty results, first use — no alarm), retryable (DB locked, I/O errors — retry flag), fatal (disk full, corruption — recommendations). MCP tools use classified errors with severity, retry hints, and actionable recommendations.

### ~~17. Entity Context Extraction Prompts~~ ✅ Implemented 2026-03-24

Source: claude-supermemory v2.0.1 study (2026-03-09)

Extraction instructions embedded in `/distill-transcripts` skill and context hook injection prompt. Defines what to extract (technology decisions, conventions, preferences, architecture, entities by type) vs what to skip (debugging steps, code output, transient errors). Scope detection for global vs project facts. Claude Code itself performs extraction — no separate API call needed.

### 47. Token Budget Telemetry — *what does memory cost?*

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #1)

**Gap.** `Core::TokenEstimator` (`lib/claude_memory/core/token_estimator.rb`) exists and is only consumed by `Index::IndexQuery`. We record `context_length` (chars) on every `hook_context` activity event but never tokens, so users can't answer "what's memory costing me per session?" — the loudest critique of any context-injection memory system.

**Implementation.**

- **Capture at injection time.** `Commands::HookCommand#record_context_activity` (hook_command.rb:208-232) already builds the details hash with `context_length`. Add `context_tokens: Core::TokenEstimator.estimate(context_text)` and the same field in `Hook::Handler#context` (handler.rb:106-108). Backfill behavior: legacy events without `context_tokens` fall back to `context_length / 4` (matches TokenEstimator's CHARS_PER_TOKEN constant).
- **Surface in Trust.** `Dashboard::Trust#snapshot` (trust.rb:28-36) gains a `token_budget` block: `{p50:, p95:, total_30d:, sessions:}` derived from `activity_events` where `event_type='hook_context' AND status='success'` over `UTILIZATION_DAYS`.
- **Surface in digest.** `Commands::DigestCommand` (digest_command.rb) adds a "Context cost" line — average tokens injected per session in the window, rendered alongside activity counts.
- **Surface in stats.** `claude-memory stats --tokens` prints the same p50/p95 + per-day distribution for terminal-only users.

**Acceptance.**

- Trust panel shows `Context cost` widget with current-week p95 + week-over-week delta (matches the existing weekly_moments shape).
- Digest's Activity section includes "Context tokens injected (avg/session): N".
- `claude-memory stats --tokens --since 30` works and matches the dashboard.

**Edge cases.**

- Sessions where `generate_context` returns nil (`status='skipped'`): record `context_tokens: 0` so the denominator stays honest.
- Fresh installs with no `hook_context` events: Trust shows the widget hidden (mirroring the `utilization` panel's empty-state handling).
- Old events (pre-rollout) without the field: fall back via `(detail_json->>'context_length').to_i / 4`. Doc this in the migration note in `db/migrations/` if a schema change is added later — currently no schema change required.

**Effort.** ~4-6 hours. No schema changes; `detail_json` is opaque blob.

**Why high priority.** Without this number, the trade-off "memory eats N tokens forever" is unfalsifiable. The data is already flowing through `record_context_activity` — we're only failing to compute one extra integer.

---

### 48. Hallucination Rate as a First-Class Trust Metric

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #2). Builds on #34 (Why-Preservation Audit) and #41 (ReferenceMaterialDetector).

**Gap.** We already have `Distill::ReferenceMaterialDetector` classifying "X is a CLI/library/MCP server" / "by Firstname Lastname" / LOC-count facts as suspect. The #34 audit found ~25% of project facts had embedded reasoning, ~75% were bare conclusions. Neither signal is exposed on the dashboard. The Trust panel today shows clean numbers; it should show stained ones so users can see the calibration loop.

**Implementation.**

- **Two component metrics.**
  1. *Suspect-fact ratio*: `ReferenceMaterialDetector.suspect_count(active_facts) / active_facts.count`. Already a one-liner — the detector exists and is invoked in `ManagementHandlers#store_extraction` to retag at write time. Add a read-only count method.
  2. *Bare-conclusion ratio*: new lightweight detector that flags `decision`/`convention` facts whose `object_literal` lacks a why clause. Cheapest heuristic: `object !~ /\b(because|so that|caused by|breaks when|to avoid|to ensure|reason)\b/i`. Lives in `lib/claude_memory/distill/why_clause_detector.rb` so the rule is cited in one spot.
- **Composite quality_score.** `Dashboard::Trust#snapshot` exposes `quality: {suspect_pct:, bare_conclusion_pct:, score:}` where `score = 100 - suspect_pct - bare_conclusion_pct/2` (bare conclusions are weaker negatives than reference-material mislabels). Tunable; the formula matters less than the trend.
- **Rejection-rate companion.** Digest gains a "Calibration" section: of facts created in the last 30d, what % are now `status='rejected'`? This is the ex-post calibration signal that complements the ex-ante quality_score.
- **CLI surface.** `claude-memory stats --quality` prints the score plus the top 10 suspect facts so users can act.

**Acceptance.**

- Trust panel shows `Quality score: 87 (suspect 4%, bare 18%)` with red/yellow/green coding (>80 green, >60 yellow, else red).
- Digest's Calibration section shows `12/87 facts rejected within 7 days (14% rejection rate)`.
- Stats command lists actionable suspects with docids so users can `claude-memory reject <docid>`.

**Edge cases.**

- Reference-material is a multi-value predicate now (#41), so detector hits don't always mean rejection — they can also indicate correctly-tagged reference rows. The metric only counts mislabeled-as-convention/decision suspects, not facts with `predicate='reference'`.
- Bare-conclusion detection is regex-based and lossy. Keep it advisory: this score is a trend signal, not a precision tool. Accept ~10% false-positive rate as long as the directional signal holds across releases.
- Empty-DB case: `quality_score` is nil (not 100). Frontend hides the widget.

**Effort.** ~1 day. Detector reuse + one new helper + Trust + digest wiring.

**Why high priority.** A retrieval system that injects polluted facts is strictly worse than no memory. Users need to see the pollution rate, not just the recall rate.

---

### 49. Negative-Fact Harm Benchmark — *prototype in 0.11.0, full corpus in 0.12.0*

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #3). Parallels #32 (Repeat-Correction Benchmark) but inverts the goal.

**Two-phase delivery (added 2026-04-28):**
- **0.11.0 — 3-scenario prototype (~½d).** Three hand-written cases (one stale-tech, one mismatched-scope, one superseded-but-undetected) run against real Claude under `EVAL_MODE=real`. Smoke test: if even three cases produce >0% harm rate, the full benchmark in 0.12 will reveal a fundamental issue and we want to know early. No release gate yet — the prototype is diagnostic.
- **0.12.0 — full 10-15 scenario corpus (~2d).** Adds the missing harm classes (reference-material-as-fact + remaining stale/mismatched/superseded cases) and wires the >1% harm-rate release gate.

**Gap.** Every benchmark we run measures whether memory **helps** (Recall@k, MRR, e2e pass rate, repeat-correction prevention rate). Nothing measures whether memory **harms** — i.e. holds a wrong/stale fact and causes Claude to follow it. Without this, "memory helps" is unfalsifiable.

**Implementation.**

- **Dataset.** `spec/benchmarks/dataset/harm_scenarios.yml` modeled on `repeat_correction_scenarios.yml` (`spec/benchmarks/e2e/repeat_correction_spec.rb` is the template). Each scenario carries:
  - `memory_facts`: 1-3 facts pre-loaded into memory, intentionally outdated/wrong (e.g. `uses_database = MySQL` when the prompt context implies PostgreSQL is current).
  - `prompt`: a question whose right answer requires *not* trusting the wrong fact.
  - `harm_patterns`: regex list — any match in Claude's response = Claude followed the bad fact. Matches the absence-pattern shape from #32.
  - `safe_indicators`: optional positive patterns showing Claude correctly questioned/ignored the fact.
- **10-15 scenarios spanning four harm classes:**
  1. *Stale-tech*: outdated framework/database choice that conflicts with prompt cues.
  2. *Mismatched-scope*: project fact applied to a different-project prompt (tests scope leakage).
  3. *Superseded-but-undetected*: fact that should have been superseded but wasn't.
  4. *Reference-material-as-fact*: a "by Firstname Lastname" attribution mislabeled as `convention`, prompt asks for actual conventions.
- **Spec.** `spec/benchmarks/e2e/harm_spec.rb` runs each scenario through the e2e harness (`ClaudeCliRunner`) with memory enabled; scores `harm` if any `harm_patterns` matches, `safe` otherwise. Stub mode validates schema + regex compile (matches #32 pattern). Real mode reports harm rate with $-cost printed.
- **Release gate.** `bin/run-evals --all` aggregates harm rate; `> 1%` blocks release. Threshold tunable via `HARM_RATE_THRESHOLD` env var. The `/release` skill reads the latest result JSON (#52 below) before publishing.

**Acceptance.**

- Stub run validates 10-15 scenarios pass schema/regex checks.
- Real run prints `Harm rate: X/N (Y%)` with per-scenario passes/fails and `safe_indicators` stats.
- Release script refuses to publish when harm rate exceeds threshold.
- Dashboard shows latest harm rate alongside other benchmark scores once #52 lands.

**Edge cases.**

- `harm_patterns` regexes need to be specific enough that "I'm not sure" doesn't match. Lean on the same diagnostic discipline as #32 (positive `safe_indicators` for ambiguous cases).
- Scenario IDs need stable docids so we can track which scenarios regress release-to-release once #52 lands.
- No `acceptance_keywords` — the metric is *absence* of harm, not positive proof of correctness.

**Effort.** ~2 days. Dataset is the bulk of the time (real-world wrong-fact patterns drawn from the existing audit notes — Sequel.sqlite, hallucination CLAUDE.md example, Rails-vs-React conflicts).

**Why high priority.** Closes the "is this strictly better than no memory" question. Pairs with #50 (CLAUDE.md baseline) so we can publish "vs no memory: harmless; vs CLAUDE.md: superior".

---

### 50. Publish CLAUDE.md Baseline in Headline E2E Results

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #4)

**Gap.** `spec/benchmarks/comparative/adapters/claude_md_adapter.rb` exists, supports E2E (`supports_e2e?` returns true, `setup_for_claude` writes a real CLAUDE.md), and is registered in `comparative_helper.rb`. But the README's headline comparative table doesn't include it. The single most important question for adoption — *"is this better than a hand-written CLAUDE.md?"* — is unanswered in our published numbers.

**Implementation.**

- **Surface in comparative E2E spec.** `spec/benchmarks/comparative/e2e/comparative_e2e_spec.rb` already iterates adapters via `ComparativeHelpers.adapters`; ensure CLAUDE.md baseline is included in the iteration (verify by reading the spec — likely needs an `if adapter.supports_e2e?` guard tweak).
- **Reporter changes.** `spec/benchmarks/comparative/reporting/comparative_reporter.rb` already supports multi-adapter rows. Confirm CLAUDE.md row appears in markdown + terminal output.
- **README publishing.** `spec/benchmarks/README.md` "Comparative Results" section gets a new E2E table showing pass rate per ability category for ClaudeMemory vs CLAUDE.md baseline vs No memory. Run `EVAL_MODE=real ./bin/run-evals --comparative` once and paste the result.
- **Release gate.** Add a soft gate in `/release` skill: warn (don't block) if ClaudeMemory's E2E pass rate isn't materially above CLAUDE.md baseline. Threshold: 5% absolute pass-rate margin. Tunable.

**Acceptance.**

- README has a "ClaudeMemory vs CLAUDE.md baseline" E2E pass-rate table with a brief commentary on when each wins.
- Comparative reporter prints CLAUDE.md row inline with QMD/grepai/no-memory.
- README "Key takeaways" updated to include the ClaudeMemory-vs-CLAUDE.md comparison as a top-line finding.

**Edge cases.**

- CLAUDE.md baseline returns `[]` for `search()` — that's fine, retrieval comparison already handles this (it's a No-Retrieval row in retrieval results). The E2E story is the one we care about.
- The static CLAUDE.md grows unbounded with our test fact set (105 facts). That's the baseline's *actual* ergonomics — don't artificially shrink it. If CLAUDE.md beats us in E2E because Claude can read everything, that's a genuine signal.

**Effort.** ~30 min code + one $2-8 real-mode run.

**Why high priority.** Cheapest item on the list. If we can't beat a static CLAUDE.md on developer scenarios, that's the loudest possible "we're not done" signal; if we can, that's the headline 1.0 brag.

---

### 51. `claude-memory show` — Human-Readable "What Would Be Injected"

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #5)

**Gap.** Inspecting memory state today requires the dashboard or several CLI commands (`recall`, `stats`, `census`). The CLAUDE.md alternative is `cat CLAUDE.md` — instant, plain-English, no tool. Users develop trust through inspectability, and we're missing the simplest possible inspect surface.

**Implementation.**

- **New command.** `lib/claude_memory/commands/show_command.rb` registered in `Commands::Registry`. Construct a `Hook::ContextInjector` against the current manager (`source: nil` → behaves as a startup session for the fresh-session sections), call `generate_context`, and print the result. That's the same path real sessions use, so the output is *exactly* what would be injected.
- **Plain-English rendering.** ContextInjector already returns markdown; the command pipes it through `less` if `STDOUT.tty?` and `--paginate` (default true). `--raw` flag dumps the unprocessed string for diffing across runs.
- **Section flags.** `--decisions`, `--conventions`, `--architecture`, `--undistilled`, `--mirror` filter to specific sections. Default is all sections.
- **Sized for terminal.** Existing `MAX_TEXT_PER_ITEM` (1500 chars) and per-section limits already cap output.
- **Token reporting.** When #47 lands, `claude-memory show` prints a footer line: `(Estimated cost: ~N tokens; X% of 200k context window.)` so the user sees the trade in the same view.

**Acceptance.**

- `claude-memory show` runs in <1s on a populated DB and prints what next session would see.
- `claude-memory show --raw` is suitable for diff'ing (deterministic ordering already enforced by `Recall#query`).
- `claude-memory show --section decisions` works for narrow inspection.

**Edge cases.**

- Empty DB: print "No facts in memory yet. Try `claude-memory hook context` after a few sessions." rather than empty output.
- Fresh-session-only sections (undistilled, mirror) only show with `--source startup` or by default. `--no-fresh` suppresses them for the steady-state view.
- ContextInjector currently auto-commits the auto-memory mirror state on emission (context_injector.rb:67); the show command must pass an injector that *doesn't* commit, or the act of inspecting alters state. Two options: (a) add a `read_only:` flag to ContextInjector, (b) construct a no-op AutoMemoryMirror double in the show command. (a) is cleaner.

**Effort.** Half a day.

**Why high priority.** Trust requires inspectability. A user who can't see what memory will inject can't develop confidence in it. This is the answer to "show me, don't tell me."

---

### 52. Release-to-Release Benchmark Scoreboard

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #6)

**Gap.** Benchmark output is textual today (`spec/benchmarks/comparative/reporting/comparative_reporter.rb` + per-spec `puts`). Nothing diff-able across versions. The only reason we caught the BM25 normalization regression was a manual run. 1.0 is the moment we commit to *not regressing* what we ship; we need machine-readable longitudinal results.

**Implementation.**

- **JSON output sink.** New `BenchmarkHelpers::ResultsWriter` module in `spec/benchmarks/benchmark_helper.rb`. Each benchmark spec calls `ResultsWriter.record(suite:, metrics:)` after computing its metrics. Writer accumulates into a single `spec/benchmarks/results/<version>-<timestamp>.json` per run, plus a `spec/benchmarks/results/latest.json` symlink.
- **Schema.** Top-level `{version:, run_at:, suites: {retrieval: {...}, resolution: {...}, distillation: {...}, e2e: {...}, harm: {...}, comparative: {...}}}`. Per-suite metrics match what's already printed today.
- **Diff command.** `bin/bench-diff [--against TAG]` reads the latest results JSON and the JSON for the named tag (default: previous tag from `git tag --sort=-creatordate`). Prints color-coded deltas for each metric. Threshold for "regression" is per-metric (e.g. Recall@5 ±2%, MRR ±3%, harm rate must not increase at all).
- **Release gate.** `/release` skill reads `latest.json` and the previous version's JSON before bumping; refuses to ship on regressions over threshold. Override with `--force-regression` for explicit acknowledgments (e.g. an intentional algorithm change).
- **Storage.** Results JSON committed to repo (small, <50KB per run) so any contributor can `bin/bench-diff` historically. `.gitignore` excludes intermediate timestamped files; only the per-version stable file is committed.

**Acceptance.**

- Running `bin/run-evals --all` writes `spec/benchmarks/results/<version>.json`.
- `bin/bench-diff` shows a clear delta table when there are changes.
- `/release` warns/blocks on regressions per the threshold.
- README "Latest Results" section is auto-generated from the JSON via a rake task to stop drift.

**Edge cases.**

- Stub mode (no real Claude) only fills retrieval/resolution/distillation suites; e2e/harm/comparative sections are absent. Diff command tolerates missing keys.
- Comparative results vary by adapter availability — schema accommodates absent adapters without diffing them as regressions.
- First run has no prior JSON: `bin/bench-diff` prints "no baseline" and `/release` proceeds without gating.

**Effort.** ~1 day. Mostly plumbing; the metrics already exist as Ruby variables in the specs.

**Why high priority.** Without longitudinal tracking every benchmark we run is a snapshot. Pairs with #49 (harm benchmark) — the harm rate is the metric most worth tracking release-to-release.

---

### 69. Self-Heal the FTS Rank Index After Concurrent Ingest

Source: 2026-06-16 live incident on `claude/observational-layer-design-7662r9` — observed first-hand, not a study.

**Gap.** The contentless FTS5 index (`content_fts`) silently drifts into a broken state under concurrent writers: the ingest hook (`claude-memory hook ingest`) and the MCP server (`store_extraction` → `Index::LexicalFTS#index_content_item`) both write the same WAL DB, and a large ingest produces `"Database busy, retrying"` (`Store::RetryHandler`) followed by an FTS index where **plain `MATCH` works but `... ORDER BY rank` raises `database disk image is malformed`**. `integrity_check` passes and all rows are intact — so `recall`/`recall_index` ranking is silently degraded (the rank query throws or returns nothing) while nothing looks wrong. The only fix today is the user manually running `claude-memory compact` (which `rebuild_fts` + vacuums). Documented in `docs/influence/...` gotchas and surfaced reactively in the dashboard (`lib/claude_memory/dashboard/api.rb:338`), but never repaired automatically. Severe form (btree corruption, plain `MATCH` also failing) was separately seen when **two** memory MCP servers ran concurrently — de-duping to a single server removed that, but the benign rank-artifact still recurs from hook-vs-MCP contention alone.

**Implementation.**

- **Cheap probe + self-heal in the sweep tail.** In `Sweep::Maintenance`, add a `repair_fts_rank` step: run a bounded `SELECT rowid FROM content_fts WHERE content_fts MATCH 'a' ORDER BY rank LIMIT 1`; on `malformed`, call `Index::LexicalFTS#rebuild!` (already contentless-safe) instead of requiring a manual `compact`. Sweep already runs on PreCompact/SessionEnd, so recall ranking self-repairs within the session that broke it. Guard with a time budget so a huge index doesn't blow the hook timeout.
- **Reduce the contention that triggers it.** Raise the SQLite `busy_timeout` and use `BEGIN IMMEDIATE` for the FTS-writing transactions so the ingest hook and MCP server serialize cleanly instead of racing (the retry-loop WARN is the symptom). Confirm both the hook path and `ManagementHandlers#store_extraction` open connections with the same pragmas via `Store::RetryHandler`.
- **Proactive detection.** Add a `doctor` check that runs the rank probe and reports "FTS rank index needs rebuild — run `claude-memory compact`" (or auto-heals if the sweep step lands). Optionally a `roi_nudge`-style one-liner.
- **Option (larger).** Evaluate external-content FTS5 over `content_items` instead of contentless — more robust to `rebuild` and avoids the auxiliary-index drift entirely. Note as a follow-up, not part of the first fix.

**Acceptance.**

- An integration test that interleaves a large `hook ingest` with an MCP `store_extraction` against the same DB leaves `MATCH ... ORDER BY rank` working (or self-healed by the next sweep) — no manual `compact` required.
- `doctor` flags the rank-artifact when present.
- `"Database busy, retrying"` WARN frequency drops under the contention test.

**Effort.** Medium (~2 days). Self-heal step + pragmas are small; the integration test reproducing concurrent writers is the bulk.

**Why high priority.** It silently degrades `recall` — a core feature — and the user has no signal except empty/unranked results until they happen to run `compact`. Recurs on normal usage (hit live 2026-06-16). Relates to the WAL/connection-release discipline already noted for the dashboard.

---

## cq Study (2026-04-28)

Source: docs/influence/cq.md — usefulness-focused study (not internals)

cq is complementary to ClaudeMemory, not competing: it's an out-of-band SQL audit tool over raw Claude Code transcripts (DuckDB cache + `tool_calls`/`messages`/`sessions` views), aimed at meta-questions like "is my skill firing?" or "where did context go in that bad session?" ClaudeMemory has data parity for the per-project case (its own `tool_calls` table) but lacks cross-project SQL ergonomics.

### High Priority Recommendations

- [ ] **Install cq as a developer audit tool for the ClaudeMemory plugin itself**
  - Value: Answer "is the memory plugin firing when it should?" — currently unanswerable
  - Evidence: cq's three documented patterns (skill-activation gap, silent failure, context budget) translate directly; only predicate names change
  - Effort: 5 minutes (`cargo install --git https://github.com/technicalpickles/cq`)
  - Trade-off: Adds Rust toolchain dep on dev machine; runs out-of-band so no project impact

- [x] **Capture reference audit queries in `docs/audit-queries.md`** (2026-04-28)
  - Five queries: activation rate, missed memory-shaped prompts, tool ranking, error rate, result-size distribution
  - Each runnable as `cq sql "..." --since 30d --table` against Claude Code transcripts (not ClaudeMemory's own SQLite — cq sees calls that bypassed the MCP server entirely)
  - Re-run before each release, after MCP server instruction changes, or when investigating "memory doesn't seem to do anything" reports

### Features to Avoid (from this study)

- DuckDB as a primary store — wrong tool for the curation workload
- Cross-project default scoping — breaks ClaudeMemory's project/global memory separation
- Re-indexing transcripts on every command — ClaudeMemory's hook-driven ingest is already the right pattern

---

## Strands Agent SOPs Study (2026-05-01)

Source: docs/influence/strands-agent-sops.md — article study (AWS Open Source Blog)

Amazon's Strands Agent SOPs describe markdown-based parameterized workflows for agents (RFC-2119 keywords, parameter blocks, sequential chaining via artifact handoff, MCP-prompt invocation). **ClaudeMemory has independently arrived at the same architecture** via Anthropic Skills (`/distill-transcripts`, `/release`, `/study-repo`), MCP `prompts/list`+`prompts/get` (`memory_guide`), and the `Ingest → Distill → Resolve → Publish` pipeline. The article is *validation*, not a roadmap.

### Medium Priority Recommendations

- [ ] **Add explicit `## Parameters` blocks to skill markdowns**
  - Value: Self-documenting skills; Claude can prompt the user for missing parameters instead of guessing from `$ARGUMENTS`
  - Evidence: Strands' `Required Parameters / Optional Parameters` block — the only verbatim format snippet in the article (`docs/influence/strands-agent-sops.md`)
  - Implementation: Add `## Parameters` section to `lib/claude_memory/commands/skills/distill-transcripts.md`, `release.md`, `study-repo.md`, `quality-update.md`, `improve.md`. Format: bullet list with `name: description (default: …)`
  - Effort: ~30 minutes total
  - Trade-off: Tiny doc maintenance; no runtime cost

### Deferred / Avoid (from this study)

- **Progress markers + checkpoint file in `/distill-transcripts`** — UX-only improvement; DB already handles correctness. Defer until usage data shows multi-hundred-item distillation runs.
- **MCP-prompt-exposed skill format spec** (analog of `strands-agents-sops rule`) — solves a problem we don't have; defer until ≥3 skill-authoring locations exist.
- **Strands Python package** — wrong language ecosystem.
- **`.sop/<name>/` artifact filesystem** — would parallel our DB-as-checkpoint substrate and double the cleanup burden.
- **Adopting "SOP" as user-facing terminology** — Anthropic Skills is the term Claude Code users know; renaming creates confusion for zero gain.

---

## AI Memory Systems Landscape Study (2026-05-23)

Source: `docs/influence/ai-memory-systems-2026.md` — meta-study of the Nakajima/Opus 4.6 Research article surveying 7 memory benchmarks and ~12 memory systems (Hindsight, Zep/Graphiti, MemGPT/Letta, Mem0, Cognee, HippoRAG, etc.).

**Headline finding.** ClaudeMemory's retrieval profile (vector + FTS, light graph, no temporal-aware ranking) sits architecturally closest to Mem0 (49% on LongMemEval). Two unforced gaps separate us from Zep-class systems (71.2%): we already store the graph but don't traverse it at query time, and we have temporal columns we don't rank by. Closing both is ~3-5 days of work without new dependencies.

### High Priority Recommendations

- [ ] **64. Graph Traversal as Third RRF Source** ⭐
  - Value: Field-wide validated as the difference between Mem0-class (49%) and Zep-class (71.2%) LongMemEval scores. We already store the graph (`entities`, `entity_aliases`, `fact_links`).
  - Evidence: Article Pattern 1 + Pattern 2; our `lib/claude_memory/recall.rb` has no BFS strategy; `lib/claude_memory/core/rr_fusion.rb` fuses only vec + FTS.
  - Implementation: Add `Recall::GraphTraversal` strategy that resolves query → seed entities → 1-2 hop BFS over `entities` ↔ `facts` ↔ `entities`, scored by hop distance × edge type. Fuse into existing RRF as a third source. Bound depth so latency stays sub-100ms.
  - Effort: Medium (2-3 days). Data shape already correct; new strategy class + RRF integration + tests.
  - Trade-off: Empty graphs degrade gracefully to zero rerank contribution.

- [ ] **65. Temporal-Aware Retrieval Strategy** ⭐
  - Value: Article identifies temporal reasoning as the hardest field-wide capability (up to 73% gap on LoCoMo). Schema already has `valid_from`, `valid_to`, `last_recalled_at`; ranker doesn't use them.
  - Evidence: Article Pattern 3.
  - Implementation: (1) Add `temporal_rank` input to `Core::RRFusion` — facts with newer `valid_from` get a small rank boost (capped at ~0.1× vec contribution). (2) Optional `as_of` ISO 8601 parameter on `memory.recall` filters to `valid_from <= as_of AND (valid_to IS NULL OR valid_to > as_of)`.
  - Effort: Small (1-2 days). Existing columns; thread parameter and ranker.
  - Trade-off: Recency over-ranking risk; cap boost weight and tune via eval harness.

- [ ] **66. Bi-Temporal Schema Cleanup (world vs ingest time)**
  - Value: Today `valid_to` does double duty — "fact ceased to be true in the world" *and* "we superseded this fact during ingestion." Article credits this distinction as Zep's most important innovation. Without it, point-in-time queries silently corrupt the temporal axis.
  - Evidence: Article: "Every entity edge tracks four timestamps: valid_at, invalid_at, created_at, expired_at." See also our schema (`db/migrations/001_create_initial_schema.rb:64-65`).
  - Implementation: Schema v18 migration: rename `valid_to` → `world_invalid_at`; add `ingest_expired_at` (datetime, nullable). Resolver sets `ingest_expired_at` on supersession; leaves `world_invalid_at` for explicit "this fact stopped being true on date X" updates. Backfill copies `valid_to` into both columns.
  - Effort: Medium (2-3 days). Schema migration + resolver update + MCP tool surface + tests. Public API break — needs deprecation alias for one minor version per `docs/api_stability.md`.
  - Trade-off: API surface change. Lower urgency than #64/#65 but cheaper to do before corpus grows.

- [ ] **67. LongMemEval Benchmark Integration** ⭐
  - Value: Article calls LongMemEval the "gold standard" — the only benchmark it describes as rigorous. Without an external benchmark score, we can't credibly position ClaudeMemory against the field.
  - Evidence: Article — Wu et al. ICLR 2025, 500 questions across 115K-1.5M token contexts, three-stage framework with LLM-as-judge.
  - Implementation: Add `spec/benchmarks/longmemeval/` adapter. Dataset is public. Wire into `bin/run-evals --longmemeval`. Report Recall@k, MRR, nDCG@10 like DevMemBench.
  - Effort: Medium (2-4 days). Mostly dataset wrangling + adapter code; existing DevMemBench pipeline has the right shape.
  - Trade-off: Real-mode runs (with LLM judge) cost API spend. Mitigation: stub mode for retrieval-only, real mode opt-in.

### Promotion (existing improvement, article-validated)

- [ ] **#57 Provenance-Strength-Aware Retrieval Ranking** — promote from Medium to High Priority
  - Rationale: Article describes Hindsight's "epistemic separation" (4 networks: world facts / agent experiences / entity observations / evolving opinions) as a key innovation. Our `provenance.strength` ∈ {stated, inferred, derived} is the soft version of this — already in the schema, just not used by the ranker. This article promotes the change from "nice to have" to "fits the field-wide pattern."
  - Implementation unchanged from existing #57 entry.

### Medium Priority

- [ ] **Reflect Pass — Background Consolidation on Idle** (see influence doc rec #5)
  - Value: Hindsight's reflect operation and Letta's sleep-time compute both re-examine stored facts using a background process. Article credits this with preventing noise growth at scale. We don't have it; today our corpus is small enough not to need it.
  - Recommendation: Track when largest project DB crosses 5K facts. Until then, premature. **CONSIDER for 1.0.0 or later.**

- [ ] **`memory.save_this` Tool — Agent-Initiated Storage** (see influence doc rec #6)
  - Value: Letta's striking result (74% vs Mem0's 68.5% on LoCoMo) suggests agent-controlled "save this" beats passive extraction. We have `memory.store_extraction` but it's framed as "report an extraction," not "I want to remember this."
  - Implementation: Thin wrapper over `store_extraction` with friendlier prompt. Document in MCP `memory_guide` prompt.
  - Effort: Small (1 day).
  - Recommendation: **CONSIDER** in 0.13.0 if first-week usage shows agents under-use `store_extraction` proactively.

### Features to Avoid (from this study)

- **Cross-encoder LLM reranking** — Article confirms cost as the reason (already in our avoid list).
- **Full 4-column Graphiti timestamp model** — Recommendation #66 above adopts the simpler 3-timestamp version (world_invalid_at + ingest_expired_at + created_at).
- **Hindsight 4-network hard epistemic split** — Over-complex for our scale; recommendation #57 promotion is the soft version.
- **Cloud-required graph DB** (Neo4j / FalkorDB) — Recommendation #64 traverses the graph we already have in SQLite.
- **Custom fine-tuned models in any pipeline stage** — Article confirms architecture > model size; we can't compete on model investment anyway.
- **LoCoMo benchmark for cross-vendor comparison** — Article explicitly discredits it: "Mem0 and Zep have publicly contradicted each other's reported scores, making LoCoMo rankings unreliable for cross-vendor comparison." If we cite LoCoMo at all, cite our own number standalone.
- **Cognee-style RDF/OWL ontology validation** — Our `entity_aliases` + `PredicatePolicy::SYNONYMS` are the right-sized version for a single-developer tool.
- **Letta-style filesystem-only memory as primary mode** — Consumes user-visible tokens on every interaction; our hook-based passive ingestion is cheaper per session.
- **Sleep-time compute as a separate background service** — We can achieve the same effect on the next SessionStart via Layer 2 distillation, for free. No separate process needed.

---

## Mastra Observational Memory Study (2026-06-16)

Source: `docs/influence/mastra-observational-memory.md` — architecture study of Mastra's Observational Memory (OM), a text-based dual-agent (Observer + Reflector) episodic memory that compresses raw messages into an append-only, dated observation log living in the context window. SOTA on LongMemEval (84–95%) at 3–6× compression, cache-stable by design.

**Headline finding.** In OM's taxonomy ClaudeMemory is the thing it positions against: a structured *semantic* store injected *dynamically per query*. The gap OM exposes is not retrieval quality — it's that **ClaudeMemory has no episodic layer at all.** Facts answer "what is true"; observations answer "what happened." OM is purely episodic, we are purely semantic. The two are complementary, and we already own analogues of OM's Observer (distillation pipeline) and Reflector (Resolve + Sweep) — they just emit facts, not a narrative log.

### High Priority Recommendations

- [ ] **68. Episodic Observation Layer (Observer + Reflector + promotion bridge)** ⭐
  - Value: Adds the missing episodic half of memory (narrative "what happened" log) and a cache-stable injection mode, on top of the existing semantic fact store. The promotion bridge (observation→fact on corroboration) doubles as an anti-hallucination gate for the documented reject-churn problem (distiller commits `uses_database`/`uses_framework` facts from one-off doc example text).
  - Evidence: `docs/influence/mastra-observational-memory.md`. Our distill pipeline (`lib/claude_memory/distill/`) is already an Observer that emits facts; `resolve/` + `sweep/` is already a Reflector over facts. No episodic store exists.
  - Implementation (phased):
    1. ✅ **Shipped 2026-06-16** (schema v19): `observations` table (`body`, `kind`, `priority` 🔴/🟡/🟢, `scope`, `source_content_item_id`, `consolidated_into` lineage, `token_count`); `Domain::Observation`; NullDistiller emits observation rows; Resolver persists them; `memory.observations` read tool. **Append-only with tombstoning, not lossy drop** — preserves provenance.
    2. ✅ **Shipped 2026-06-16**: two-block SessionStart injection via `ContextInjector` — Block 1 = observation log (🔴 marked, 🟡/🟢 stripped as Mastra does for the actor) ahead of Block 2 = undistilled tail; `Observe::ObservationsRenderer` shared with the published `.claude/rules/claude_memory.observations.md` snapshot; `observation_count` added to the `hook_context` activity event for token/compression measurement.
    3. ✅ **Shipped 2026-06-17**: `Observe::Reflector` — deterministic, free (no LLM) GC. Dedupes near-identical active observations into the newest (tombstone via `consolidated_into`) and expires stale info-level (🟢) ones past a TTL (`observation_info_ttl_days`, default 30); 🔴/🟡 never expire. Provenance-preserving (rows tombstoned, never deleted). Wired into `Sweep::Maintenance#reflect_observations` → `Sweeper#run!`, so it runs on the existing `PreCompact`/`SessionEnd` sweep — context-pressure-triggered, the analog of Mastra's ~40k-token threshold. (Semantic "merge related/surface patterns" deferred to phase 4 — needs the LLM.)
    4. **Automatic semantic reflection:** `PreCompact` injects an `additionalContext` consolidation instruction (Claude-as-reflector inline, next turn) + observation→fact promotion bridge. Retain a manual `/reflect` skill for on-demand deep passes.
  - Effort: Large, phased. Phase 1 ~2-3 days; full arc ~2 weeks. Reuses distill/resolve/sweep/publish/context-hook machinery and `context_tokens` telemetry.
  - Trade-off: reflection is automatic on *lifecycle events* (compaction/session boundaries), not a wall clock — Claude Code has no timer/cron hook, and Routines/subagents incur separate token budgets (rejected). Observer/Reflector reuse the existing session (no extra API cost). **Augments dynamic recall, does not replace it (user-confirmed 2026-06-16).** See claude-code-guide consultation in the influence doc.

### Medium Priority

- [ ] **Compression / cache telemetry + LongMemEval episodic suite** (see influence doc rec E)
  - Value: Report compression ratio and token reduction on Trust/Health panels using existing `context_tokens` events (0.11.0). Add a LongMemEval-style long-session suite to DevMemBench to score the episodic layer. Overlaps with existing item #67 (LongMemEval integration) — coordinate.
  - Effort: Medium. Depends on #68 phase 1-2.

### Features to Avoid (from this study)

- **Two always-on background LLM agents** — violates the no-separate-API-call convention. Observer = context-hook injection; Reflector = deterministic shell-side GC + `PreCompact`-injected semantic consolidation (rides the existing session).
- **Claude Code Routines / subagents for recurring reflection** — Routines run as a separate scheduled cloud session; subagents run in their own context (~7× tokens). Both incur extra spend; reserve only for an explicitly opted-in one-off backfill.
- **Lossy drop on reflection** ("never forgives") — we tombstone via `consolidated_into` and retain raw `content_items`; provenance is non-negotiable.
- **Replacing dynamic recall with a wholesale-loaded log** — augment, don't replace; keep `memory.recall` for targeted lookups.

---

## Medium Priority

### ~~18. Shell Completion for CLI~~ ✅ Implemented 2026-03-20

Added `claude-memory completion` command generating zsh and bash completion scripts. Auto-detects shell from `$SHELL`. Includes all 25 CLI commands, hook subcommands (ingest/sweep/publish/context), and context-aware flag completions for scope, index, and install-skill. Usage: `eval "$(claude-memory completion)"`.

### ~~19. Content-Addressed Deduplication for Embeddings~~ ✅ Implemented 2026-03-16

IndexCommand builds text→embedding cache from already-embedded facts before indexing. Identical fact texts reuse cached vectors, skipping generation. Cache hits tracked and reported (e.g., "Cache hits: 3/10 (30% dedup)").

### ~~20. Deduplication Before Vector Scoring~~ ✅ Implemented 2026-03-16

In Ruby fallback path (`search_by_vector_fallback`), facts are grouped by `embedding_json` before cosine similarity computation. Unique embeddings scored once, results fanned out to all matching fact_ids. Native sqlite-vec path unaffected (handles own dedup).

### 53. First-Week ROI Nudge — *targeted for 0.11.0 (moved up from post-1.0)*

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #7). Closes the cold-start gap. **Moved up from post-1.0 to 0.11.0** in the 2026-04-28 path-to-1.0 restructure — fits the "Trust & Cost" theme since it's the user-visible proof that memory is doing work.

**Gap.** New users install the gem, run a few sessions, and don't know whether memory is working. The dashboard exists but they have to know to look. The auto-memory mirror (#36) helps but isn't surfaced. We need a low-friction nudge in the first ~10 sessions that says "memory is working, here's what it did" — and then gets out of the way.

**Implementation.**

- **New hook command.** `claude-memory hook session-end-summary` runs on SessionEnd alongside the existing ingest/sweep. Reads the most recent `hook_context` activity event for the current session_id; emits a `systemMessage` (or `additionalContext` if the spec supports it for SessionEnd) summarizing: facts injected, % used, top subjects.
- **Sentinel.** Tracked in a new `Configuration#session_count` (or `.claude/.session_counter`) — only emit on sessions 1–10. After 10, the user has either seen enough or doesn't care; turn it off so we don't become noise.
- **Hooks config.** `HooksConfigurator#build_hooks_config` (hooks_configurator.rb:130) gains the new command in the SessionEnd block.
- **Opt-out.** `CLAUDE_MEMORY_NO_NUDGE=1` disables.

**Acceptance.**

- Sessions 1-10 print a one-line "memory contributed N facts; you used Y of them" summary at session end.
- Session 11+ stays silent unless the user opts in via `CLAUDE_MEMORY_ALWAYS_NUDGE=1`.
- Telemetry: each emitted nudge logs an `activity_event` so we can track whether users disable it (rough proxy for noise).

**Edge cases.**

- Sessions where `generate_context` returned nil: don't emit the nudge — there's nothing to celebrate.
- Multi-window sessions / tab-switches: the session counter is per-(project_path, claude_config_dir), not global. Two projects = two independent first-week windows.
- "% used" needs a recall event in the same session to compute; absent that, fall back to "memory contributed N facts (use them via /memory-recall)".

**Effort.** ~half day.

**Why post-1.0.** Nice onboarding polish, not a confidence gap. The token-budget, hallucination, and harm metrics in the must-have set already give the skeptic the answer they need.

---

### 54. Real-Session Repeat-Correction Detection

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #8). Production-side companion to #32 (synthetic harness).

**Gap.** The repeat-correction benchmark fires synthetic prompts and asks "did Claude repeat itself?". Production has no equivalent signal. When a user re-states something memory already injected, that's the strongest possible "memory failed silently" signal — and we don't capture it.

**Implementation.**

- **Detector.** New `Sweep::RepeatCorrectionDetector` (parallel to `Sweep::RecallTimestampRefresher`). Runs in the sweep cycle; reads `activity_events` for `event_type='hook_context'` over the last 7 days. For each session, takes the `top_subjects` (from `detail_json`) and looks at the next ingested transcript chunk for prompts that mention the same subject in a "we discussed this" / "I told you" / correction-shaped way.
- **Signal extraction.** Regex-light heuristic against ingested content: `/\b(again|already|told you|previously|as I said|reminder)\b/i` AND a subject keyword from the prior injection's `top_subjects`.
- **Surface.** New dashboard panel "Memory misses (last 30d)" + a `--missed` flag on `claude-memory stats`. Each row links to the offending session and the subject that was injected but not heeded.
- **Privacy posture.** Only surfaces subject names + session IDs, never the user's full prompt text. Same posture as census.

**Acceptance.**

- Stats command shows actionable list of "memory was injected but the user re-corrected" cases.
- Dashboard surfaces these with a link to the originating fact so users can act (reject / promote / rephrase).
- Aggregate "miss rate" appears in digest as a 30d trend.

**Edge cases.**

- Heuristic is lossy — we'll miss real misses and flag false positives. Treat as a trend signal not a precision tool, same posture as `relevance_ratio` (#31).
- Need to disambiguate "user re-stated for emphasis" vs "memory failed". Lean toward false-negative bias (only flag obvious cases) so the panel isn't crying wolf.

**Effort.** ~2 days. Detector logic is the bulk; UI is straightforward addition.

**Why post-1.0.** Good signal but not blocking — the synthetic harness in #32 already gives release-time guarantees. Production-side measurement is icing.

---

### 55. Token-Cost Growth Tracking

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #9). Builds on #47 (token budget telemetry).

**Gap.** Once #47 is recording context_tokens per session, the next question is: *is it growing?* DB bloat or context-injection going wide should be visible as an anomaly, not discoverable only by manual census.

**Implementation.**

- **Digest section.** `Commands::DigestCommand` adds a "Context cost trend" line: `current 7d avg vs 30d avg (delta %)`. Same window comparison shape as the existing `weekly_moments`.
- **Dashboard widget.** Trust panel's `token_budget` block (added in #47) gains `growth_30d` and `growth_7d` fields with color coding (>20% growth = yellow, >50% = red).
- **Alert threshold.** New `Configuration#token_growth_alert_pct` (default 30) controls the "is this concerning" line. Configurable via env var.

**Acceptance.**

- Digest shows directional trend at a glance.
- Dashboard surfaces sustained growth with appropriate severity.

**Effort.** ~3 hours after #47 lands.

**Why post-1.0.** Pure derivation from #47's data; doesn't add new instrumentation.

---

### 56. Drift Dashboard

Source: 2026-04-28 1.0 readiness review (`docs/1_0_punchlist.md` #10). Builds on #30 (Predicate Census).

**Gap.** `claude-memory census` (#30) gives a one-shot privacy-safe scan but it's not longitudinal. "Is my fact base going off?" requires comparing today's predicate distribution against historical ones — which today only exists in a user's git history of committed `.claude/memory.sqlite3` (and we don't recommend committing that).

**Implementation.**

- **Snapshot store.** New table `census_snapshots` (schema migration vNN) stores compact aggregates: `{snapshotted_at, predicate, status, count, scope}`. Bounded retention (keep last 12 weeks).
- **Capture.** Sweep cycle records a snapshot weekly (gated by "last snapshot > 6 days ago"). Cheap — single aggregate query.
- **Dashboard panel.** "Distribution drift" widget shows a small sparkline per predicate over the last 12 weeks. Anomalies (predicate count drops >50%, or rises >200%) get highlighted.
- **CLI.** `claude-memory drift` prints a text-mode version of the dashboard widget for terminal users.

**Acceptance.**

- Dashboard shows predicate distribution sparklines.
- A user who's been running the gem for 3 months can see "convention facts dropped 40% this week — what happened?".
- Snapshots stay <100KB total over 12 weeks (bounded by predicate × status × scope cardinality).

**Edge cases.**

- Fresh installs have no historical snapshots. Widget hides until 2+ snapshots exist.
- Schema migration touches the gem-core schema; needs round-trip migration tests per #f1fe317.

**Effort.** ~1.5 days.

**Why post-1.0.** Useful longitudinal signal but the must-have set already gives the headline confidence numbers. Drift is the "operate it long-term" question.

---

### 59. API Stability Audit (promoted to 0.12.0 — 2026-05-01)

*Originally slated as 1.0 release blocker; promoted to 0.12 because #52's benchmark scoreboard needs an explicit "what surfaces are stable" list to know what counts as a regression vs. internal change. The deprecation-warning module is also a prerequisite for any soft-rename work surfaced during the 0.12 → 1.0 soak.*

Source: 2026-04-28 path-to-1.0 review (`docs/1_0_punchlist.md` #11). Added after 0.10.0 ship. *(Renumbered from #57 to #59 during rebase against origin/main on 2026-04-28 — Mercury-article PR #5 had already taken #57 and #58.)*

**Gap.** "1.0 commits to semver" is meaningless without an explicit public/internal split. Many of the surfaces touched in 0.9.0 / 0.10.0 (MCP tool schemas, hook payload shapes, CLI flags, dashboard endpoints) have evolved organically and aren't formally documented as stable vs. internal. Without this audit, future "regression" complaints become un-arbitrable — was that flag/method/tool *promised*? We don't know.

**Implementation.**

- **New `docs/api_stability.md`** as the authoritative public-API reference. Sections:
  1. *Public CLI surface*: every `claude-memory <subcommand>` registered in `Commands::Registry::COMMANDS`, every documented flag, with stability tier per command (`stable` / `experimental` / `internal`).
  2. *Public MCP tools*: every entry in `MCP::ToolDefinitions.all` with its argument schema, return shape, and tool-annotation hints (`readOnlyHint`, `idempotentHint`, `destructiveHint`). Stability tier per tool.
  3. *Public hook contract*: payload field names accepted by `Hook::Handler` and `Commands::HookCommand`, return shapes (`hookSpecificOutput`, exit codes via `Hook::ExitCodes`), stability tier per hook event.
  4. *Public Ruby API*: the surface external Ruby callers can rely on. Candidates: `ClaudeMemory::Recall`, `Configuration`, `Store::StoreManager`, `Domain::*`. Everything else (resolver internals, dashboard internals, sweep internals) marked internal.
  5. *Schema stability*: column names, table names, predicate vocabulary in `PredicatePolicy::POLICIES`. Schema migrations remain forward-compatible per the round-trip-spec convention; column *removals* require deprecation cycle.
- **Deprecation policy paragraph**: "we'll mark X deprecated in N.x.0 (with a runtime warning), keep it functional for ≥1 minor cycle, and remove no earlier than (N+1).0.0." Mirrors Ruby/Rails conventions.
- **Deprecation-warning instrumentation**: tiny module `ClaudeMemory::Deprecations` with a `warn(name, replacement:, removed_in:)` helper. Anywhere we want to change a public surface in 1.x, we wrap with `Deprecations.warn` first.
- **README + CLAUDE.md** add a top-level link: "Public API: see [docs/api_stability.md](docs/api_stability.md)".

**Acceptance.**

- `docs/api_stability.md` exists and lists every CLI command, MCP tool, hook event, and key Ruby class with a stability tier.
- A reader of the doc can answer "is `claude-memory dashboard --port` stable?" / "will `Recall.new(manager).query(...)` keep its signature in 1.x?" in <30 seconds.
- `ClaudeMemory::Deprecations.warn` is wired up and used at least once (e.g. for a soon-to-be-renamed flag) so the mechanism is exercised.
- `/release` skill knows about `docs/api_stability.md` and reminds the operator to update it on any public-surface change.

**Edge cases.**

- We have to be honest about which Ruby surfaces are public. `Recall` and `Configuration` clearly are; `Sweep::Maintenance` clearly isn't; `Domain::Fact` is ambiguous (used by external benchmark adapters in `spec/benchmarks/`). Default to **internal** when ambiguous — easier to promote later than demote.
- Schema column names are tricky. Migrations can rename safely; external SQL tools (e.g. cq) read the schema directly. Document the column names as "best-effort stable, no removal without deprecation cycle."
- The dashboard JSON API is internal — explicitly call this out so users don't build scripts against it.

**Effort.** ~2 days. The doc is the bulk of the time; the deprecation warning module is ~50 LOC.

**Why 1.0 must-have.** Without this, the semver promise is vibes. Future regressions in non-listed areas can be argued away; future regressions in listed areas are bugs. Forces honesty about what we're committing to.

---

### 60. LLM Extractor Calibration Drift (surfaced by #48)

Source: 2026-04-30 production verification of #48 hallucination-rate metric. Surfaced when the metric was first run against real data on this very project.

**The signal.** First run of `claude-memory digest` against `claude_memory/.claude/memory.sqlite3` after the metric landed:

| Number | Value | Verdict |
|---|---|---|
| Quality score | 39/100 | bad |
| Suspect (predicate=`reference`) | 2 / 59 (3.4%) | acceptable |
| Bare conclusions (decision/convention without reason) | 34 / 59 (57.6%) | poor |
| 7-day rejection rate | 27 of 32 facts (84.4%) | very bad |

**What it means.** The 84% rejection rate over 7 days says the LLM extractor in this project was producing noise faster than usable knowledge — almost everything new it created got rejected within a week. The 57.6% bare-conclusion rate confirms the same drift from the prompt's *"every decision/convention MUST embed a reason clause"* requirement: the prompt asks for "because…" / "so that…" / "to avoid…" but recent extractions skipped the reason clause majority of the time.

**Why this is a finding, not a metric bug.** Spot-checked 5 flagged + 5 unflagged facts on 2026-04-30; the detector's regex correctly matches the prompt's strict reason-clause vocabulary in both directions. Not a false-positive issue. The metric is doing what it was designed to do: surface real LLM calibration drift that was previously invisible.

**Possible causes (to investigate).**

1. **Prompt drift in `lib/claude_memory/commands/skills/distill-transcripts.md`** — the reason-clause requirement may have been added to the prompt after a chunk of older facts were already extracted. Mostly historical noise rather than ongoing extraction problem. → check `git log -p lib/claude_memory/commands/skills/distill-transcripts.md` for when the reason-clause section landed and whether bare-conclusion facts cluster pre-that-commit.
2. **Auto-memory mirror regurgitation** — the `Hook::AutoMemoryMirror` (0.10.0) injects auto-memory file content as extraction candidates at SessionStart. If those auto-memory files have bare-conclusion content (likely, since they're written by Claude with no reason-clause discipline), the LLM may be re-extracting them faithfully without injecting reasons that weren't in the source. → grep auto-memory file content for the same bare conclusions appearing in flagged DB facts.
3. **Reference-material guard too narrow** — `ReferenceMaterialDetector` only retags `convention` predicates; "From QMD restudy: adopt X" facts (clearly third-party-project descriptions) come back as `decision` rather than `reference` and stay in the corpus. → expand `GUARDED_PREDICATES` to include `decision` for the same patterns.
4. **High rejection rate is correct + the corpus is junky** — 84% rejection in last 7 days might mean we (the team) are correctly rejecting noise that the LLM is producing too aggressively. → check whether rejected facts cluster by source (transcript topic, hook event type, time-of-day).

**Acceptance / next steps.**

- Investigation note in `docs/quality_review.md` capturing which of (1)–(4) above explains the bulk of the drift.
- If prompt drift (cause 1): the historical bulk-flag is fine, the live extraction rate is what matters. Expose "extraction rate" over a tighter window (last 24h vs 30-day baseline) so calibration drift becomes visible without historical noise drowning the signal.
- If auto-memory regurgitation (cause 2): patch the auto-memory-mirror prompt or distillation prompt to require reason-clause synthesis even when source text is bare.
- If reference-material guard too narrow (cause 3): expand `Distill::ReferenceMaterialDetector::GUARDED_PREDICATES` and re-run `claude-memory reclassify-references --predicate decision` against active corpus.
- If correct + junky (cause 4): the metric is healthy; the cleanup is `claude-memory reject` runs against high-frequency junk.

**Effort.** Investigation: 0.5d. Fix: depends on cause.

**Why this is in `improvements.md`.** Independently of which cause is correct, the verification of #48 surfaced a real signal worth tracking. The metric did its job (turning invisible drift into a visible 84%); now the work is the actual cleanup. Tracked here so it doesn't fall off the radar between 0.11 ship and the 1.0 soak.

**Update 2026-04-30: investigation complete.** Diagnostics ran for all four causes; results recorded in `docs/quality_review.md`. Summary: cause 1 (prompt drift) explains 97% of bare conclusions; cause 4 (`/study-repo` misattribution burst) explains 100% of the 7-day rejection cluster; causes 2 and 3 ruled out. Headline metric calibration fix landed in commit `7591da4` (live 30-day window + historical block). The two systemic issues split into entries #61 and #62 below.

---

### 61. /study-repo Misattribution Guard

Source: 2026-04-30 #60 investigation, cause 4. All 27 rejected facts in this project's 7-day window were `uses_database` (18) or `deployment_platform` (9) with `session_id=nil` (MCP-originated), all from a 2-day burst on 2026-04-23 to 04-24. The pattern: when running `/study-repo` on an external project, the LLM extracted that project's tech stack and asserted it as facts about *this* project. Cleanup happened correctly via `claude-memory reject` after detection, but the round-trip is wasteful and noisy.

**Phase 1 — prompt fix (LANDED 2026-05-01).**

`.claude/skills/study-repo/SKILL.md` gained a top-level "CRITICAL: Memory Discipline" section that explicitly forbids the LLM from calling `memory.store_extraction` with the studied project's tech stack as `uses_database` / `uses_framework` / `uses_language` / `deployment_platform` / `auth_method`. Allowed: `predicate=reference` for descriptions of the external project, plus genuine project-facing decisions/conventions/architecture derived from contrast (with reason clauses). The influence document (`docs/influence/<project>.md`) is named as the right home for "what tech does the studied project use" observations, taking memory entirely out of that loop.

**Phase 2 — defense-in-depth detector (DEFERRED to 0.12.x or later).**

If the prompt fix isn't enough on its own — measured by re-running `/study-repo` against ≥3 external projects post-2026-05-01 and counting any `uses_database`/`deployment_platform` rows that appear with non-self subjects — build `Distill::ExternalAttributionDetector` as a sister to `ReferenceMaterialDetector`. Heuristics: source content_item text containing "studying X", "/study-repo", a non-current-project repo URL, or "external project" → bias single-value-cardinality extractions toward `predicate=reference`.

False-positive risk to handle: legitimate facts ABOUT this project that mention an external one ("ClaudeMemory adopts SessionStart hook context injection like claude-supermemory does") must still land as `decision` with reason clause, not be retagged. Solution if needed: detector requires both (a) external-project marker in source AND (b) the extracted subject not being the current project's repo entity.

**Acceptance.**

- After Phase 1: re-run `/study-repo` on a fresh DB; observe zero `uses_database` or `deployment_platform` facts inserted that point to the external project's tech.
- After Phase 1: the 27-fact cluster pattern doesn't reappear in similar `/study-repo` sessions.
- Phase 2 trigger: only build if Phase 1 measurement shows persistent leakage.

**Effort.** Phase 1: 15 minutes (done). Phase 2 (if needed): ~½ day for detector + tests.

---

### 62. Historical Bare-Conclusion Backfill

Source: 2026-04-30 #60 investigation, cause 1. 34 bare-conclusion facts pre-date the 2026-04-20 reason-clause prompt commit (`f22d12f`). They satisfy the strict regex but most are factually informative ("MCP tools return dual content + structuredContent via TextSummary module" — describes mechanics implicitly without a "because"). The `quality_score` headline now correctly windows to the last 30 days (commit `7591da4`), but those 34 facts still appear in the historical line and may surface in `claude-memory show` and recall queries forever.

**Implementation options (pick one).**

A. **Reclassify to `legacy_observation` predicate.** New non-guarded predicate that the bare-conclusion detector ignores. Migration walks active `decision`/`convention` facts created before 2026-04-20 with no reason clause, reclassifies. Preserves the content; removes the metric pollution.

B. **One-shot prompt-rewrite pass.** For each pre-2026-04-20 bare fact, run a small LLM call asking "infer the reason from the original quote/content_item text" and rewrite the object. Higher fidelity; costs ~$1-5 in API calls.

C. **Retroactive rejection.** Mark them all `status=rejected`. Cheap and clean but throws away signal. Probably wrong.

**Recommendation.** Option A. Cheap, reversible (predicate change is just a column update), and the facts remain queryable just outside the bare-conclusion bucket.

**Acceptance.**

- Run the migration; verify the historical bare-conclusion count drops by ~34.
- Verify those facts still appear in `memory.recall` queries (predicate filter optional).
- `digest` quality section's historical block reports a meaningfully lower number afterwards.

**Effort.** ~½ day. Mostly a Sequel migration + a `claude-memory reclassify-bare-conclusions` command paralleling `reclassify-references`.

---

### 63. Pre-Release Hook Smoke Gate (0.12.0)

Source: 2026-04-30 verification incident during 0.11 work. Five commits landed for #47 token-budget telemetry with 156 specs green. The user asked "did you actually run claude-memory show on this project?" — at which point a smoke test revealed the installed gem was still 0.9.1 and 24 hours of real SessionStart hook events had recorded no `context_tokens` field. The bug was not in the code; the bug was in the *release process* — specs verify code correctness against the working tree, but production hooks invoke the installed gem via PATH. Without `rake install`, every hook/MCP code change is dead in production.

This already lives in memory (`feedback_hooks_run_installed_gem.md`) and as two project conventions stored via `memory.store_extraction`. It's a known trap that I (Claude) hit anyway. **Codify it into the release pipeline so the trap can't be sprung again.**

**Implementation.**

- **New `bin/pre-release-smoke`** script that:
  1. Runs `bundle exec rake install` (rebuild gem from current working tree).
  2. Verifies `which claude-memory` resolves to the installed-gem binary (sanity check).
  3. Triggers each gem-managed hook event with a synthetic payload via stdin: `claude-memory hook context`, `claude-memory hook ingest --db /tmp/smoke.sqlite3`, `claude-memory hook nudge`, etc. — populates a temp DB.
  4. Inspects `activity_events` table via `sqlite3 json_extract` for the fields the current version is supposed to record. Specifically:
     - `hook_context` events should carry both `context_length` and `context_tokens` (since 0.11.0).
     - `roi_nudge` events should carry `n`, `used`, `pct`, `prior_count` (since 0.11.0).
     - Any future field added under release becomes part of this checklist.
  5. Exits non-zero if any expected field is null or absent.
- **Per-version expectation manifest** at `spec/smoke/expected_fields.yml` — declarative list of `{event_type, fields, since_version}` so the script doesn't need code changes when a new field lands; just append to the YAML and the gate enforces it on the next release.
- **`/release` skill integration.** Phase 1 Step 5b (after specs, before lint) runs `bin/pre-release-smoke`. Failure aborts the release with the field name(s) that were null. Skill description gains a one-line "verifies installed gem actually fires hooks correctly".

**Acceptance.**

- `bin/pre-release-smoke` exits 0 when the installed gem matches the working tree and all expected fields populate.
- Deleting the `context_tokens:` line from `Hook::Handler#context` and re-running `bin/pre-release-smoke` produces a clear error pointing at the missing field on `hook_context.detail_json`.
- `/release` skill aborts Phase 1 if the smoke gate fails — never reaches `git push`.
- Test: `spec/smoke/pre_release_smoke_spec.rb` verifies the manifest schema and that the script's exit-code logic flips on simulated null fields.

**Edge cases.**

- The script uses a temp DB so it can't pollute the user's project DB. Cleans up on exit.
- If `rake install` fails (gemspec validation, signing, etc.), the script reports that as a separate failure mode, not a smoke-gate failure.
- The `hook nudge` synthetic payload needs a `session_id` of a real session that contributed facts — the script can pre-seed one fact and use a dedicated `smoke-test-NNNN` session id.

**Effort.** ~½ day for the script + manifest + skill integration. Spec is the bulk of the time.

**Why this release.** 0.11 verification gap directly motivated this. Release Discipline that doesn't catch the trap that's already hit twice (#47 today, plus the 2026-04-16 ActivityLog incident in `feedback_hooks_run_installed_gem.md`) isn't real discipline. Pairs naturally with #52 — scoreboard catches regressions in measurement; smoke gate catches the regression where the measurement itself doesn't fire.

---

### 21. Incremental Indexing with File Watching

Source: grepai study (reinforced 2026-03-02)

- **Value**: Eliminates manual `claude-memory ingest` calls
- **Implementation**: Add `Listen` gem, watch `.claude/projects/*/transcripts/*.jsonl`, debounce 500ms, trigger IngestCommand automatically
- **Evidence**: `watcher/watcher.go:30-59` — fsnotify with debouncing (300ms default), gitignore respect, event deduplication
- **Effort**: 2-3 days
- **Trade-off**: Background process ~10MB memory overhead

### 22. Document Chunking for Long Transcripts

Source: QMD study (updated 2026-03-02)

- **Value**: Better embeddings for long content (>3000 chars)
- **Implementation**: 900 tokens/chunk, 15% overlap, markdown-aware break points
- **Evidence**: QMD v1.1.0 `store.ts:53-219` — scored break point patterns (h1=100 → newline=1), code fence detection, squared distance decay
- **Consideration**: Only if users report issues with long transcripts
- **Effort**: 2-3 days

### ~~5. Background Processing for Hooks~~ ✅ Implemented 2026-03-02

`--async` flag on hook ingest/sweep/publish subcommands. Fork+detach for non-blocking execution, fallback to sync when fork unavailable.

### ~~26. CLAUDE_CONFIG_DIR Support~~ ✅ Implemented 2026-04-13

`Configuration#claude_config_dir` reads `CLAUDE_CONFIG_DIR` env var before falling back to `~/.claude`. `global_db_path` routes through it, so users with non-standard Claude Code config locations (or multiple profiles) can point the global memory DB anywhere without touching project DB resolution.

### 28. Code-Aware Transcript Chunking

Source: QMD v2.0.1+unreleased re-study (2026-03-30)

- **Value**: Better embeddings for transcripts containing code — detect fenced code blocks and apply AST-aware break points (function/class/import boundaries) rather than naive text splitting
- **Implementation**: Detect ` ```language ` fences in transcript content, parse code blocks with tree-sitter (via ruby_tree_sitter gem or shelling out), score break points (class=100, func=90, type=80, import=60), merge with markdown break points from #22
- **Evidence**: QMD `src/ast.ts` (392 lines) — web-tree-sitter with WASM grammars, `mergeBreakPoints()` combining AST + regex scores, graceful degradation on parse failure
- **Consideration**: Only useful in combination with #22 (Document Chunking). Transcripts often contain significant code in tool_use results and assistant responses
- **Effort**: 2-3 days (after #22)
- **Trade-off**: Adds tree-sitter dependency; graceful fallback to regex-only chunking when grammar unavailable

### ~~30. Predicate Census Command~~ ✅ Implemented 2026-04-20

`claude-memory census [--root DIR]` scans every `.claude/memory.sqlite3` under the root (plus the global DB unless `--no-global`), aggregates per-DB predicate × status counts, entity type counts, schema versions, novel predicates, and synonym candidates (Jaccard token overlap ≥ 0.4 against `PredicatePolicy.known_predicates`). Emits privacy-safe JSON — no object_literal, no entity names, no paths, no quotes; per-DB entries carry an SHA256-prefixed id rather than a path. Supports `--output FILE`, `--pretty`.

### ~~31. Relevance Ratio Metric for Eval Suite~~ ✅ Implemented 2026-04-20

Offline plumbing landed; the real-mode measurement will materialize the first time someone runs `EVAL_MODE=real` against the e2e suite.

- `Hook::ContextInjector` now exposes `emitted_fact_ids` / `emitted_subjects` reader accessors populated during `generate_context`. Existing callers unaffected — the context string return value is unchanged, tracking is a side channel.
- `BenchmarkHelpers::RelevanceMetrics` module in `spec/benchmarks/benchmark_helper.rb` adds `relevance_ratio(subjects, response)` — case-insensitive subject-substring match, deduped, returns 1.0 for empty-injection (keeps the metric monotone with recall semantics so it doesn't penalize abstention scenarios).
- `spec/benchmarks/e2e/devmemeval_spec.rb` captures injected subjects via a local `ContextInjector` against the scenario DB (same state in → same injection out — avoids having to scrape the running Claude process), computes the ratio against `result[:result]`, prints per-scenario `relevance=X.XX` alongside the existing score, and reports `avg relevance ratio` per ability group.

Response-side matching stays deliberately approximate — subject substring overlap. The metric is a trend signal (is memory being *applied*, not just retrieved), not a precision tool. Benchmark owner should sanity-check the first real-mode run and tighten the matcher if the ratios look implausibly high or low.

### ~~32. Repeat-Correction Benchmark~~ ⭐ Partially Implemented 2026-04-21

Harness landed with a 2-scenario starter set drawn from real, repeated corrections in the project's auto-memory (Sequel.sqlite adapter, rake-install/git-ls-files). Path to the 5–10 scenario set left for incremental growth.

- `spec/benchmarks/dataset/repeat_correction_scenarios.yml` — each scenario carries `memory_facts` (pre-loaded as a past session's correction), `prompt` (would re-trigger the bad pattern), and `violation_patterns` (regexes; any match = correction was repeated). Optional `expected_mentions` for diagnostic "correction aware" signal.
- `spec/benchmarks/e2e/repeat_correction_spec.rb` — stub mode validates schema + regex compile + fact loadability; real mode (`EVAL_MODE=real`) runs each prompt through Claude and reports pass rate. No hard assertion on pass rate yet — the metric is a trend signal; tighten once baseline data exists. Tagged `:benchmark :eval_real :slow` matching `devmemeval_spec.rb`.
- `BenchmarkHelpers::DatasetLoader.load_repeat_correction_scenarios` added for consistency with existing dataset loaders.

Deliberately no `acceptance_keywords`-style pass gate — the point is *absence* of the bad pattern, not positive proof of the good one. Per the improvements note, this runs nightly or on release, not per commit.

### ~~33. Conflict Cluster Audit — Fact 21 / 45 / 48~~ ✅ Implemented 2026-04-19/20

Audit completed inline during the dashboard Conflicts-tab work on 2026-04-19 and the cluster was eliminated via the resolver fixes shipped on 2026-04-20.

**Classification of the three anchor facts (all three were (b) distiller hallucination):**

- **Fact 21** (`repo uses_database sqlite`) — correct keeper. Contradictions came from CLAUDE.md example text ("this app uses PostgreSQL") being extracted as a literal claim. Fixed by rewriting the example in CLAUDE.md line 258 to self-describe the real stack ("claude_memory uses SQLite for storage") — commit `61666bc`.
- **Fact 45** (`repo uses_framework rails`) — correct keeper. Contradictions were artifacts of the `uses_framework` single→multi reclassification in 0.9.0; `claude-memory restore --predicate uses_framework` already exists for this case (0.9.0 CHANGELOG).
- **Fact 48** (`repo deployment_platform aws`) — correct keeper. Contradictions from platform-mention hallucinations; no further resolution machinery needed beyond rejecting contradicting rows.

**Delivered cleanup**: bulk-reject-similar UI in the Conflicts modal (commit `61666bc`), resolver dedup (commit `f571ba4`), scope-leakage fix (commit `50cf02e`). Project DB conflict count dropped from 31 → 15 during the session via bulk-reject, with further shrinkage from the dedup + scope passes. Going forward, the resolver's dedup and the CLAUDE.md rewrite prevent the same cluster from regenerating.

No separate `docs/conflict_audit_2026-04.md` file written — the classification and resolution are preserved in the relevant commit messages and memory entries.

### ~~34. "Why" Preservation Audit~~ ✅ Implemented 2026-04-20

Audit of 20 random project facts showed ~25% embed reasoning, ~75% are bare conclusions — a material gap. Updated two extraction surfaces to require a reason clause for `decision` and `convention` predicates:

- `lib/claude_memory/commands/skills/distill-transcripts.md` — added reasoning requirement to the Facts section, with contrasting ❌ bare / ✅ with-why examples drawn from the audit sample, plus a prefer-one-fact-with-reason-over-two-without guideline.
- `lib/claude_memory/hook/context_injector.rb#format_distillation_prompt` — added a **Reasoning requirement** block to the SessionStart extraction prompt that ships with every fresh session; locked in by a new spec assertion so the contract can't silently regress.

No schema change. Reasoning rides in `object_literal`. The plugin-copy mirror (`.claude-plugin/commands/distill-transcripts.md`) was left alone — it's already out of sync with the source skill on the predicate list and is manually maintained; a separate improvement should reconcile it.

### ~~36. Auto-Mirror Auto-Memory Observations into claude_memory on SessionStart~~ ⭐ Partially Implemented 2026-04-21

Core diff + emission landed. Dashboard indicator (pending mirror count) deferred until real-session usage data suggests the UI is needed.

- `Hook::AutoMemoryMirror` scans `~/.claude/projects/<slug>/memory/*.md` (slug = `project_path.tr("/", "-")`) and diffs each file's md5 against `.claude/auto_memory_mirror.json`. `pending_candidates(limit:)` returns only new/changed entries, sorted by mtime descending. Bounded at 5 per session, 1500 chars per entry.
- `Hook::ContextInjector#generate_context` appends an "Auto-Memory Mirror Candidates" section on fresh sessions (startup/resume/clear/nil source) when candidates exist, then `commit`s them as the new baseline so subsequent sessions won't re-emit unchanged files. Section explains the mirror is advisory — Claude reviews and calls `memory.store_extraction` only for high-signal entries, preserving the `**Why:**` / `**How to apply:**` reasoning (inherits #34 discipline via the sibling distillation prompt).
- Graceful fallbacks: missing auto-memory dir returns `[]`, malformed state JSON treated as empty baseline, file read errors skipped. Manager must expose `project_path` or the mirror is silently skipped — so non-project managers (plain global-only) never break.
- Test coverage: `spec/claude_memory/hook/auto_memory_mirror_spec.rb` covers slug derivation, initial scan, commit idempotence, changed-file re-emission, malformed state tolerance, and limit enforcement. `context_injector_spec.rb` adds integration tests for the mirror section, non-fresh-source suppression, and no-re-emission across sessions.

Still deferred:
- Dashboard "N auto-memory entries awaiting mirror" indicator — not wired until it's clear from real usage whether a visible backlog adds value beyond the SessionStart nudge.
- Scope-hint inference per file. The current emission is the raw file content; Claude decides subject/predicate/scope in the normal extraction review. A future upgrade could parse filename prefixes (`feedback_*`, `gotcha_*`, `reference_*`) into predicate hints.

### ~~35. Access-Based Staleness Scoring~~ ✅ Implemented 2026-04-27

Triggered by the digest (#46) surfacing 11% utilization with no way to point at the dead weight. Built as **Path B (sweep-derived from activity_events)** rather than the originally-proposed Path A (per-recall update buffer) — the v15 activity_events table eliminated the WAL-contention concern that drove Path A, since the (scope, fact_id) data already exists. No new hot-path writes.

- Migration v17 adds nullable `last_recalled_at` to `facts`.
- `Sweep::RecallTimestampRefresher.new(manager).refresh!` scans both stores' activity_events (event_type IN recall, hook_context) within a 90-day lookback, projects the most recent occurrence per (scope, fact_id) via `Dashboard::ScopedFactResolver`, and bulk-UPDATEs `last_recalled_at` across both DBs. Cross-DB by design — project events touching global facts update global rows.
- Wired into `Hook::Handler#sweep` and `Commands::SweepCommand` so every sweep cycle freshens timestamps.
- `Configuration#stale_days` reads `CLAUDE_MEMORY_STALE_DAYS` (default **14**, falls back on garbage / non-positive input).
- `Recall::StaleDetector.stale_facts(manager, threshold_days:)` and `.stale_count(manager, ...)` return active facts where `(last_recalled_at < cutoff OR last_recalled_at IS NULL) AND created_at < cutoff` — the AND-on-created_at is the grace window so freshly extracted facts don't surface as stale on day one.
- `claude-memory stats --stale [--stale-days N]` prints the list grouped by scope.
- `Dashboard::Trust#count_stale_facts` now reads through `StaleDetector#stale_count`, replacing the old "active facts minus seen-in-recall pairs" approximation that couldn't distinguish a never-touched 6-month-old fact from a freshly stored one.
- No auto-deletion. Staleness is informational; users decide what to reject.

Privacy posture: timestamps don't carry user content (different shape from the rejected `query_text` capture). Same posture as `mcp_tool_calls.called_at` — load-bearing but not content-revealing.

Specs cover: refresher updates from both stores including cross-DB project→global, lookback bound, latest-wins on multiple touches, stale detection grace window, scope-spanning, status filtering, limits, CLI flag output, Configuration env knob fallbacks.

### ~~27. Usage Stats / ROI Tracking~~ ✅ Implemented 2026-04-15

Schema migration v13 adds `mcp_tool_calls` telemetry table (tool_name, called_at, duration_ms, result_count, scope, error_class). `MCP::Telemetry` wraps `Server#handle_tools_call` with monotonic-clock timing, captures errors, and records to the project DB; DB errors are swallowed so telemetry never fails a real tool call. `StatsCommand` gains `--tools` and `--since DAYS` flags showing total calls, error rate, and per-tool breakdown (calls, avg ms, p95 ms, error rate). `Sweep::Maintenance#prune_old_mcp_tool_calls` enforces a 90-day retention window, wired into `Sweeper#run!`. Rejected NDJSON in favor of SQLite for schema/query consistency with the rest of the gem. Dropped query-text capture (YAGNI — the dedup insight the hash would enable also needs raw text). Also fixed a latent bug where `StatsCommand` opened the DB via `Sequel.sqlite` (requiring the unlisted `sqlite3` gem); now uses the extralite adapter consistently.

### 57. Provenance-Strength-Aware Retrieval Ranking

Source: 2026-04-28 article "Why Karpathy's Second Brain Breaks at Agent Scale" (Zaid, [@Ctrl_Alt_Zaid](https://x.com/Ctrl_Alt_Zaid/status/2049082538686382397)) — "Memories need metadata such as confidence" / "without scoring, everything competes equally."

**Gap.** `Domain::Provenance` already records `strength` ∈ {`stated`, `inferred`} (provenance.rb:7,14,22-26), but the value is only consumed as a boolean (`stated?` / `inferred?`) for display. `Index::IndexQuery` and the RRF fusion in `Recall` do not factor strength into ranking. Result: a fact that was inferred from one ambiguous transcript line ranks identically to one explicitly stated multiple times across sessions.

**Implementation.**

- **Strength score derivation.** Add `Domain::Provenance#confidence_weight` returning `1.0` for `stated`, `0.6` for `inferred`. Single-source — no new column.
- **Per-fact aggregate.** New `SQLiteStore#fact_confidence(fact_id)` returns max strength weight across all provenance rows (a fact stated once and inferred twice is still high-confidence).
- **Ranking integration.** `Index::IndexQuery` already returns scored candidates; multiply final RRF score by `(0.7 + 0.3 * confidence_weight)`. Bounded modifier (0.7-1.0 range) so a low-confidence fact still ranks if it's the only relevant one — we're nudging, not filtering.
- **Surfacing.** `score_trace` (introduced in #5) gains a `confidence_factor` field so the multiplier is auditable in `memory.recall_semantic --explain`.

**Acceptance.**

- `memory.recall` results re-rank in tests: an `inferred`-only fact loses to a `stated` fact when both have similar BM25/vector scores.
- Retrieval benchmark (`spec/benchmarks/retrieval/`) shows Recall@k unchanged or improved on the 155-query set.
- `score_trace.confidence_factor` populated for every result.

**Edge cases.**

- Facts with no provenance (legacy / direct stores): default to 0.8 (between stated and inferred). Don't penalize as 0.6 — those facts predate the field.
- `memory.store_extraction` callers don't always set strength; default already lands on `stated` per provenance.rb:14, which is the right behavior.

**Effort.** ~half day. No schema migration; `strength` already exists.

**Why medium.** The article calls this out as a structural reliability requirement, but ClaudeMemory already has the data — we're just not using it. Cheap win that closes a visible gap in the article's external critique.

---

### 58. Reinforcement-and-Decay Ranking Signal

Source: 2026-04-28 article "Why Karpathy's Second Brain Breaks at Agent Scale" (Zaid) — "Memories need metadata such as freshness, importance, reinforcement" / "Some memory should weaken, expire, or be archived."

**Gap.** `last_recalled_at` (schema v17, populated by `Sweep::RecallTimestampRefresher`) currently only feeds `Recall::StaleDetector` to *flag* unused facts (stale_detector.rb:57-61). It does not boost frequently-recalled facts in retrieval ranking, nor decay long-untouched ones. Result: a fact recalled 50 times in the last week and a fact recalled once 8 months ago compete on equal footing once their BM25/vector scores match — the inverse of what the article calls "the right memory, not the most memory."

**Implementation.**

- **Add `recall_count` column.** Migration vNN adds `facts.recall_count INTEGER DEFAULT 0`. `RecallTimestampRefresher` increments it alongside the `last_recalled_at` update (single UPDATE, no extra query).
- **Reinforcement-decay multiplier.** New `Recall::FreshnessScorer.weight(fact)` returns `max(0.5, min(1.5, log1p(recall_count) * exp(-age_days / HALF_LIFE)))` where `HALF_LIFE` defaults to 60 days. Bounded so a single hot fact can't dominate and a cold fact can't disappear.
- **Wire into RRF.** Same composition point as #57: `final_score = rrf_score * confidence_factor * freshness_factor`. Both factors land in `score_trace`.
- **Configuration.** `CLAUDE_MEMORY_RECALL_HALF_LIFE_DAYS` env var (default 60) for users who want longer/shorter memory.
- **Decay is soft, not destructive.** No facts are deleted or archived by this — that stays the user's job via `claude-memory reject`. The article's "decay" framing is correct in spirit (rank weight drops) but we don't auto-prune.

**Acceptance.**

- Two facts with identical BM25 scores: the one recalled 10× in the last week ranks above one not recalled in 6 months.
- Repeat-correction benchmark (#32) shows improvement: facts that "stuck" rank higher than abandoned ones.
- `score_trace.freshness_factor` populated; visible in `memory.recall_semantic --explain`.
- Telemetry: `activity_events` gain `freshness_factor` in the details JSON for hook_context events so we can backtest changes to `HALF_LIFE`.

**Edge cases.**

- Brand-new facts (recall_count=0, age=0): `log1p(0) = 0` would zero out the weight. Floor at 0.5 — new facts shouldn't be penalized for being new.
- Facts never recalled but still valid: clamped to 0.5 floor; ranked behind reinforced peers but not invisible.
- Cross-DB mixing: refresher already handles cross-DB project→global per memory fact "OperationTracker.reset_stuck_operations…"; recall_count lives on each fact in its own DB, which is the right shape.

**Effort.** ~1 day (migration, refresher update, ranking integration, tests).

**Why medium.** This pairs naturally with #57 — together they answer the article's "without scoring, everything competes equally" critique. Defer behind the 1.0 punchlist (#47-52) but ahead of the post-1.0 nudge/drift items, since these directly affect retrieval quality measured by the existing benchmarks.

---

## Low Priority / Defer

### ~~29. Derive CompletionCommand Descriptions from Registry~~ ✅ Implemented 2026-04-15

`Registry::COMMANDS` now stores `{class:, description:}` entries as the single source of truth. New `Registry.description` and `Registry.descriptions` accessors. `CompletionCommand` reads descriptions via `Registry.descriptions` instead of maintaining its own parallel hash. `Registry.find` also simplified — class references stored directly since command files are required before the Registry, eliminating `const_get` string indirection. Drift between the command list and completion output is now impossible without a deliberate edit to a single file.

### 23. REST API Endpoint

Source: QMD v2.0.1 study (2026-03-10)

- **Value**: POST `/query` alongside MCP — enables search from curl, scripts, CI, and non-MCP clients without the full MCP protocol handshake
- **Implementation**: Add optional HTTP server mode to `claude-memory serve-mcp --http` with POST `/recall` endpoint. Accept `{ query, scope, limit }`, return JSON facts
- **Evidence**: QMD `src/mcp/server.ts:626-675` — `/query` and `/search` endpoints with structured JSON
- **Effort**: 2 days
- **Trade-off**: Requires WEBrick or similar Ruby HTTP server dependency
- **Recommendation**: CONSIDER — Useful for CI/scripting, but MCP covers primary use case

### 24. Signal-Based Ingestion Filtering

Source: claude-supermemory study (2026-03-02)

- **Value**: Reduce noise by prioritizing transcript sections with signal keywords
- **Evidence**: supermemory `settings.json:signalKeywords` — keyword-triggered capture with context window
- **Implementation**: During ingest, weight transcript sections containing signal keywords ("decided", "convention", "always", "never", "prefer") higher
- **Effort**: 1-2 days
- **Trade-off**: May miss important but subtly-expressed facts. Our distiller already extracts structured facts, which inherently filters noise.
- **Recommendation**: DEFER — Distiller handles this naturally

### 25. HTTP MCP Transport

Source: QMD study (2026-03-02)

- **Value**: Shared server, models stay loaded, faster subsequent queries
- **Evidence**: QMD `mcp.ts:119-137` — WebStandardStreamableHTTPServerTransport with daemon mode
- **Implementation**: Add HTTP transport option alongside stdio
- **Effort**: 2-3 days
- **Trade-off**: Process management complexity
- **Recommendation**: DEFER — Only if MCP startup latency becomes an issue

### ~~38. Dashboard: Dedupe conflicts at display layer~~ ✅ Implemented 2026-04-24

`Dashboard::Conflicts#list` now groups rows by `(source, status, predicate, sorted-normalized-object-pair)` and returns each group as one row with a `group_size` count plus `group_member_ids`. `total` and the `counts` field reflect the distinct-contradiction count; a new `raw_counts` field preserves the underlying row totals for the Advanced drawer. `Trust#count_open_conflicts` delegates to a new `Conflicts#distinct_open_counts` helper so the `Needs review` sidebar alert stops overstating the backlog. Frontend renders a `×N` badge on the status cell when a group has more than one detection. Covered by new specs (`group_size`, order-swapped pair collapse, raw vs distinct counts, sidebar helper).

### ~~39. Resolver: Deduplicate conflict insertion~~ ✅ Implemented 2026-04-24

Source: 2026-04-24 dashboard data audit. Root cause traced to `facts_for_slot` defaulting to `status="active"`, which made the existing disputed fact invisible to the re-extraction path. Fixed in `Resolver#apply_conflict`: before creating a new disputed fact + conflict row, look up disputed facts in the same (subject, predicate) slot and reinforce the matching one with provenance instead of duplicating. New spec `resolver_spec.rb` "does not duplicate a conflict when the same contradiction is re-extracted" locks in the behavior. Historical DB rows (e.g. 11× sqlite vs postgresql) stay until an optional cleanup pass runs.

### ~~40. Cleanup: Prune historical rails-vs-react conflicts (data only — code already correct)~~ ✅ Implemented 2026-04-24

Shipped in commit `22eeaf1` as `claude-memory dedupe-conflicts` and `claude-memory reclassify-references`. `Sweep::Maintenance` gains two one-off maintenance methods:

- `dedupe_conflicts` groups open conflicts by `(subject_entity_id, predicate, normalized(object_a, object_b))`, keeps the earliest, rejects the duplicate disputed facts, and migrates their provenance onto the keeper.
- `reclassify_references` walks active convention facts through `ReferenceMaterialDetector` and retags matches to `predicate=reference`.

Both CLI commands accept `--dry-run` and `--scope`. Tightened `ReferenceMaterialDetector` so the `by Firstname Lastname` pattern is now a weak signal (fires only alongside a strong pattern). Covered by 9 new maintenance specs and 1 detector spec.

### ~~41. Distiller: Guard against reference material mislabeled as convention~~ ✅ Implemented 2026-04-24

Source: 2026-04-24 dashboard data audit. `Distill::ReferenceMaterialDetector` reclassifies convention facts whose object text matches any of: LOC counts (`~?\d+[,.]?\d*\s*(LOC|lines of code)`), star counts, `by Firstname Lastname` author attribution, or "is a (plugin|library|tool|gem|service|framework|extension|cli|mcp server)" templates. New predicate `reference` registered in `PredicatePolicy::POLICIES` (multi, non-exclusive) with its own section in `SECTION_MAP` → `:references`. Detector is applied in `ManagementHandlers#store_extraction` before the resolver runs, so mislabeling can't persist. New `References` section in `Dashboard::Knowledge`. 8 new specs lock in behavior. Historical mislabeled facts (project facts #1, #3) remain until manual reject or cleanup pass.

### ~~42. Dashboard: ROI diagnostic — extracted vs recalled~~ ✅ Implemented 2026-04-24

Shipped in commit `3906c23`. `Dashboard::Trust#snapshot` now returns a `utilization` section with `extracted` (active facts created in the last 30 days across both stores), `used` ((scope, id) pairs Claude has recalled or injected over the window), `used_from_extracted` (intersection), and `ratio_pct`. Rendered as a stat on the Most-used-this-week panel, color-coded (green ≥40%, yellow ≥15%, red below). Panel hides itself on fresh installs where there's no extraction or use yet. Covered by new `dashboard/trust_spec.rb` assertions.

### ~~43. Dashboard: 👍/👎 feedback on moments~~ ✅ Implemented 2026-04-24

Schema migration v16 adds a `moment_feedback` table with a unique index on `event_id` so repeat clicks upsert. `SQLiteStore#upsert_moment_feedback` and `#clear_moment_feedback` own the writes; `Dashboard::API` exposes `POST /api/moments/:id/feedback` (with `{verdict, note}`) and `DELETE /api/moments/:id/feedback` to clear. `Moments#list` now batch-attaches the current verdict to each moment. `Trust#snapshot` gains a `feedback` section (`up`, `down`, `net`, `ratio_pct`) windowed to the last 30 days, rendered inline on the Most-used-this-week panel whenever any feedback exists. Frontend adds 👍/👎 buttons on each moment card with active-state styling; repeat-click clears. Covered by store, API, Moments attach, and Trust ratio specs.

### 44. Dashboard: Universal search box

Source: 2026-04-22 dashboard exploration

- **Value**: One input spans facts / sessions / conflicts / moments with typed results — removes the drawer-tab nav for power users.
- **Implementation**: New `/api/search?q=` endpoint fanning out across stores + activity_events. Alfred-style typed result list.
- **Effort**: 2 days
- **Recommendation**: **LOW PRIORITY** — Nice-to-have; existing Knowledge/Facts drawer covers primary needs.

### 45. Dashboard: Live feed via SSE or WebSocket

Source: 2026-04-22 dashboard exploration

- **Value**: New moments animate in as hooks fire rather than waiting for 30s polling. Enables the "watch this" onboarding demo.
- **Implementation**: WEBrick doesn't support WebSockets cleanly; would need `async-websocket` or ServerSentEvents via `rack-sse`. 30s polling stays as fallback.
- **Effort**: 2-3 days
- **Recommendation**: **LOW PRIORITY** — Polling is adequate; SSE/WS is cosmetic polish.

### ~~46. Dashboard + CLI: Weekly digest~~ ✅ Implemented 2026-04-24

`claude-memory digest [--since DAYS] [--output FILE]` renders a markdown report from already-existing aggregates — no new schema, no cron. Sections: Activity (moments bucketed by event_type), New knowledge (active facts created in the window, grouped by predicate), Utilization (30d extracted-vs-used ratio from `Dashboard::Trust#utilization`), Conflicts (deduped open count via `Dashboard::Conflicts#distinct_open_counts`), Feedback (👍/👎 from the #43 moment_feedback table). `--output FILE` writes to disk; default is stdout. `--since 0` errors out so the user knows the window must be positive. Covered by command specs (baseline, activity grouping, predicate grouping, since-window, positive-only validation, output-file, feedback inclusion).

### ~~7. MCP Discovery Tools~~ ✅ Implemented 2026-03-02

Added `memory.list_projects` MCP tool. Shows global DB, current project, and discovers other projects from promoted facts/global fact paths with stats.

### ~~8. Database Compact Command~~ ✅ Implemented 2026-03-02

Added `claude-memory compact` command. Runs SQLite VACUUM with optional integrity check (`--check`). Supports `--scope` for global/project/all. Reports size before/after with savings.

### ~~9. Fact Export Command~~ ✅ Implemented 2026-03-02

Added `claude-memory export` command. Dumps facts with entities and provenance to JSON. Supports `--scope`, `--status` (active/all), `--output` (file), `--pretty`. Includes version metadata for import compatibility.

---

## Features to Avoid

- **Chroma Vector Database** — We use fastembed-rb with local ONNX model. sqlite-vec is the better upgrade path (claude-mem uses Chroma, but QMD/episodic-memory prove sqlite-vec is simpler and sufficient)
- **Claude Agent SDK for Distillation** — Direct API calls via `anthropic-rb` gem. Instead, Claude Code itself serves as the distiller via context hook injection and `/distill-transcripts` skill — zero extra cost
- **Worker Service Background Process** — Keep stdio-based MCP server. claude-mem's worker architecture adds significant complexity and failure modes.
- **Web Viewer UI** — CLI output is sufficient. Add if users request it
- **Neural Embeddings (EmbeddingGemma)** — Superseded by FastEmbed (BAAI/bge-small-en-v1.5)
- **Cross-Encoder Reranking (Qwen3-Reranker-0.6B)** — Over-engineering for fact retrieval
- **Query Expansion (LLM, Qwen3-1.7B)** — No LLM in recall path, too heavy
- **Custom Fine-Tuned Query Expansion** — 1.7B model too heavy for fact retrieval
- **YAML Collection System** — Our dual-database approach is cleaner
- **Content-Addressable Storage** — Facts deduplicated by signature, not content hash
- **Virtual Path System** — Dual-database provides clear namespace
- **Cloud Storage Dependency** — Local-first is superior (supermemory's weakness)
- **Tree-Sitter AST Code Navigation** — Out of scope for memory/fact retrieval (claude-mem's Smart Explore)
- **RPG Semantic Code Graph** — Wrong domain; code structure graph vs fact knowledge graph (grepai)
- **AGPL Licensing** — Too restrictive for developer tools (claude-mem)
- **Multiple AI Providers (Gemini/OpenRouter)** — Over-engineering; anthropic-rb is sufficient
- **Bubble Tea TUI** — CLI output is sufficient (grepai)
- **Query Document Format (lex/vec/hyde)** — Over-engineering for fact retrieval (QMD)
- **Team Memory via Cloud Sync** — Our dual-database handles scope well; cloud sync adds complexity (supermemory)
- **Raw Conversation Storage** — We distill into structured facts (episodic-memory stores raw exchanges)
- **KBS as Dependency (RETE inference engine)** — KBS (MadBomber/kbs) provides RETE inference, but solves a fundamentally different problem (forward-chaining rules vs knowledge recall). Architectural mismatch, schema incompatibility (JSON blobs vs normalized triples), performance regression (raw sqlite3 vs Sequel+Extralite), low adoption (2 stars, sole maintainer). See `docs/influence/kbs.md`.
- **KBS Redis Backend** — Redis store adds operational complexity; SQLite + Extralite is fast enough for our use case
- **KBS Message Queue** — Hook ordering already handles coordination; message queue adds unnecessary complexity
- **KBS Declarative Rule DSL** — Expressive but wrong paradigm for knowledge recall; our query/search approach is more appropriate
- **Mode/Domain System** — claude-mem v10.5.5 adds JSON-based mode profiles for domain-specific observation types. Our SPO fact model already generalizes across domains; only pursue if users request domain-specific support
- **Config Inheritance Pattern** — claude-mem's `parent--override` naming with deep merge. Not enough configuration variants to justify the complexity
- **HMAC Request Signing** — supermemory's `validate.js` uses HMAC but hardcodes the secret in a minified bundle. Security through obscurity, and we have no cloud API to protect
- **Codebase Indexing Command** — supermemory's `/index` actively explores codebases. Our hook-based passive capture is more appropriate; active indexing risks generating low-quality facts from code structure
- **SDK-First Architecture Refactor** — QMD v2.0 refactored to SDK-first with `QMDStore` interface consumed by CLI and MCP. Our gem + MCP architecture is already well-structured; major refactor for marginal gain
- **Write-Through YAML Config** — QMD v2.0 writes collection mutations to both SQLite and YAML. We don't use YAML config; dual-database is our config model
- **Multi-Session HTTP Transport** — QMD v2.0 supports concurrent MCP sessions via session map. Our MCP server is lightweight enough for stdio; no model loading latency to amortize
- **DAG-Based Conversation Compaction** — lossless-claw compresses conversations into a summary hierarchy; we distill structured facts. Fundamentally different paradigms that are complementary, not competing
- **LLM-Heavy Compaction Pipeline** — Every compaction in lossless-claw requires LLM summarization calls. Our no-LLM retrieval path is a significant cost and latency advantage
- **Go TUI for Debugging** — Adding a second language for an interactive debugging tool is over-engineering. CLI commands are sufficient (lossless-claw)
- **Per-Conversation Scoping** — lossless-claw scopes knowledge per-conversation only. Our dual-database (global/project) is more useful for knowledge spanning conversations
- **Sub-Agent Delegation for Deep Recall** — lossless-claw spawns sub-agents for DAG traversal. Adds latency and complexity; our direct MCP tool responses are simpler and faster
- **Message Parts Polymorphism** — lossless-claw's 10-column message_parts for tool calls, reasoning, patches. We don't store raw messages, so irrelevant
- **OpenClaw ContextEngine Interface** — Tight framework coupling. Our MCP + hooks approach is more portable
- **Chunk Strategy Option** — QMD's `--chunk-strategy auto` for code files. ClaudeMemory has no standalone chunking pipeline to configure (QMD v0.35.0)
- **Custom Instructions via Env Var** — lossless-claw's `LCM_CUSTOM_INSTRUCTIONS` config stub exists but is never wired to summarization prompts. Incomplete pattern; our skill-based prompts are better (lossless-claw v0.5.2)
- **OpenClaw Context Injection** — claude-mem v10.6.0's `appendSystemContext` with 60s cache replaces MEMORY.md writes. Our SessionStart hook context injection already does this (claude-mem v10.6.0)
- **Message Parts Polymorphism** — lossless-claw's 10-column message_parts for tool calls, reasoning, patches. We don't store raw messages, so irrelevant
- **OpenClaw ContextEngine Interface** — Tight framework coupling. Our MCP + hooks approach is more portable

---

## Design Decisions

### No Tag Count Limit (2026-01-23)

**Decision**: Removed MAX_TAG_COUNT limit from ContentSanitizer.

**Rationale**:
- The regex pattern `/<tag>.*?<\/tag>/m` is provably safe from ReDoS attacks
- Performance is O(n) and excellent even with 1000+ tags (~0.6ms)
- Real-world usage legitimately produces 100-200+ tags in long sessions
- No other similar tool enforces tag count limits

**Do not reintroduce**: Tag count validation is unnecessary and harmful.

---

## References

- [episodic-memory GitHub](https://github.com/obra/episodic-memory) - Semantic conversation search (v1.0.15)
- [claude-mem GitHub](https://github.com/thedotmack/claude-mem) - Memory compression system (v10.6.3)
- [grepai GitHub](https://github.com/yoanbernabeu/grepai) - Semantic code search (v0.35.0)
- [claude-supermemory GitHub](https://github.com/supermemoryai/claude-supermemory) - Cloud-backed memory (v2.0.1)
- [QMD GitHub](https://github.com/tobi/qmd) - On-device hybrid search engine (v2.0.1+unreleased)
- [KBS GitHub](https://github.com/MadBomber/kbs) - Knowledge-Based System with RETE inference (v0.2.1)
- [lossless-claw GitHub](https://github.com/martian-engineering/lossless-claw) - DAG-based lossless context management (v0.5.2)

Influence documents:
- [docs/influence/qmd.md](influence/qmd.md) - Re-studied 2026-03-30
- [docs/influence/episodic-memory.md](influence/episodic-memory.md) - Re-studied 2026-03-30
- [docs/influence/claude-mem.md](influence/claude-mem.md) - Re-studied 2026-03-30
- [docs/influence/grepai.md](influence/grepai.md) - Re-studied 2026-03-30
- [docs/influence/claude-supermemory.md](influence/claude-supermemory.md) - Re-studied 2026-03-30
- [docs/influence/kbs.md](influence/kbs.md) - Re-studied 2026-03-30 (no changes)
- [docs/influence/lossless-claw.md](influence/lossless-claw.md) - Re-studied 2026-03-30

---

*Last updated: 2026-04-28 (post-0.10.0 release, post-rebase). 1.0 punchlist restructured around milestone versions per `docs/1_0_punchlist.md`. **0.11.0** = #47/#48/#51/#53 + #49 prototype. **0.12.0** = #49 full + #50/#52. **1.0.0** = #54/#55/#56/#59 (the new API stability audit). #59 added 2026-04-28 as a 1.0 release blocker (originally #57; renumbered after rebase brought in Mercury-article entries #57/#58). #53 (first-week ROI nudge) moved up from post-1.0 to 0.11.0. Previously: 2026-04-27 - #35 (access-based staleness, sweep-derived) landed.*
