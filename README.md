# ClaudeMemory

**Long-term memory for Claude Code** - automatic, intelligent, zero-configuration

[![Gem Version](https://badge.fury.io/rb/claude_memory.svg)](https://badge.fury.io/rb/claude_memory)

## What It Does

ClaudeMemory gives Claude Code a persistent memory across all your conversations.
It automatically:
- ✅ Extracts durable facts from conversations (tech stack, preferences, decisions)
- ✅ Remembers project-specific and global knowledge
- ✅ Provides instant recall without manual prompting
- ✅ Maintains truth (handles conflicts, supersession)
- ✅ Tracks *what happened*, not just *what's true* — an episodic observation log alongside the facts (0.13.0+)
- ✅ Promotes an observation to a fact only after it recurs — a corroboration gate against one-off noise

**No API keys. No configuration. Just works.**

ClaudeMemory now has **two complementary halves**: a *semantic* fact store ("what is true" — your stack, conventions, decisions) and an *episodic* observation layer ("what happened" — the narrative of your sessions). Observations are deduplicated and consolidated automatically, and only graduate to facts once corroborated — so fleeting mentions never harden into false memory. See [Episodic Memory](#episodic-memory-observations).

## Quick Start

### 1. Install the Gem
```bash
gem install claude_memory
```

### 2. Install the Plugin

From within Claude Code, add the marketplace and install the plugin:

```bash
# Add the marketplace (one-time setup)
/plugin marketplace add codenamev/claude_memory

# Install the plugin
/plugin install claude-memory
```

### 3. Initialize Memory

Initialize both global and project-specific memory:

```bash
claude-memory init
```

This creates:
- **Global database** (`~/.claude/memory.sqlite3`) - User-wide preferences
- **Project database** (`.claude/memory.sqlite3`) - Project-specific knowledge

### 4. Analyze Your Project (Optional)

Bootstrap memory with your project's tech stack:

```
/claude-memory:analyze
```

This reads your project files (Gemfile, package.json, etc.) and stores facts about languages, frameworks, tools, and conventions.

### 5. Verify Setup
```bash
claude-memory doctor
```

### Use with Claude Code
Just talk naturally! Memory happens automatically.

```
You: "I'm building a Rails app with PostgreSQL, deploying to Heroku"
Claude: [helps with setup]

# Behind the scenes:
# - Session transcript ingested
# - Facts extracted automatically
# - No user action needed
```

**Later:**
```
You: "Help me add a background job"
Claude: "Based on my memory, you're using Rails with PostgreSQL..."
```

👉 **[See Getting Started Guide →](docs/GETTING_STARTED.md)**
👉 **[View Example Conversations →](docs/EXAMPLES.md)**

## Why It Matters — Real A/B Test Results

We tested identical prompts with and without ClaudeMemory to measure the actual impact. Here's what we found:

### Architecture Recall Without File Traversal

> **Prompt:** "Explain the conflict detection and resolution system. Answer from knowledge only — do not read any files."

| | Without Memory | With Memory |
|---|---|---|
| **Response** | 16 lines: "I don't know this codebase — let me read the files" | 76 lines: correct 4-role PredicatePolicy explanation, resolution pipeline, specific examples |
| **Outcome** | Honest refusal — zero architectural understanding | Deep understanding without touching the filesystem |

### Correct File Paths vs Hallucinated Guesses

> **Prompt:** "I want to add a new predicate. Walk me through every file I need to update."

| | Without Memory | With Memory |
|---|---|---|
| **Response** | 6 steps targeting 3 **non-existent files** (`predicate.rb`, `predicate_synonyms.rb`, `json_schema.rb`) | 8 steps, all targeting **real files** with correct paths |
| **Outcome** | Plausible but wrong — would waste developer time | Actionable, correct, references actual commits |

### Cross-Project Preferences

> **Prompt:** "What are my standard development environment preferences across all my projects?"

| | Without Memory | With Memory |
|---|---|---|
| **Response** | "I don't have stored knowledge of your preferences" | Lists 7 real preferences: iTerm2, tmux, VS Code, PostgreSQL, Redis, Docker |
| **Outcome** | Blank slate every session | Personalized from day one |

### When Memory Doesn't Help

File-searchable questions ("what version is this?") and one-shot code generation without explicit recall don't benefit — `grep` is equally effective. Memory shines when the answer **isn't in any single file**: architecture spanning dozens of classes, conventions from past sessions, decisions with rationale, and user preferences.

## How It Works

1. **You chat with Claude** - Tell it about your project
2. **Facts are extracted** - Claude identifies durable knowledge
3. **Memory persists** - Stored locally in SQLite
4. **Automatic recall** - Claude remembers in future conversations

👉 **[Architecture Deep Dive →](docs/architecture.md)**

## Key Features

- **Dual Scope**: Project-specific + global user preferences
- **Hybrid Search**: FTS5 full-text + semantic vector search with Reciprocal Rank Fusion
- **Native Vector Storage**: [sqlite-vec](https://github.com/asg017/sqlite-vec) for fast KNN search with local embeddings ([fastembed-rb](https://github.com/khasinski/fastembed-rb), no API key)
- **Session Context**: Automatic context injection at session start with recent facts
- **Privacy First**: `<private>` tags exclude sensitive data
- **Progressive Disclosure**: Lightweight queries before full details
- **Semantic Shortcuts**: Quick access to decisions, conventions, architecture
- **Truth Maintenance**: Automatic conflict resolution
- **Episodic Memory** (0.13.0+): An append-only observation log of *what happened* alongside the semantic fact store. Auto-consolidated via deterministic + LLM reflection on `PreCompact`/`SessionEnd`; corroborated observations are promoted to facts (anti-hallucination gate). See **[Episodic Memory →](#episodic-memory-observations)**.
- **Claude-Powered**: Uses Claude's intelligence to extract facts (no API key needed)
- **Token Efficient**: 10x reduction in memory queries with progressive disclosure
- **Database Maintenance**: Compact, export, and backup commands
- **Built-in Observability** (0.10.0+): `claude-memory dashboard` opens a local web UI with a moments feed, trust panel (token budget, quality score, utilization, feedback), conflicts dedup, knowledge index, and 👍/👎 feedback. See **[Dashboard guide →](docs/dashboard.md)**. `claude-memory digest` writes a weekly markdown report (Activity, Context cost, Quality, New knowledge, Utilization, Conflicts, Feedback); `claude-memory show` prints what would be injected next SessionStart; `claude-memory census` audits the predicate vocabulary across projects.
- **OpenTelemetry ingestion** (Unreleased): point Claude Code's OTLP exporter at the dashboard and the new "Telemetry" tab shows per-API-call cost in USD, token usage by model, top tools by latency, and a per-prompt event waterfall. One-line setup:

  ```bash
  claude-memory dashboard --port 3377 &   # start the receiver
  claude-memory otel --enable              # writes telemetry env into .claude/settings.json
  claude-memory otel --enable-traces       # optional: include OpenTelemetry spans
  claude-memory otel --status              # confirm metrics are flowing
  ```

  Only metrics and event names are captured by default — verbatim prompts and bodies stay off until you explicitly opt in via `claude-memory otel --capture-prompts`. The receiver binds to `127.0.0.1` only.

## Episodic Memory (Observations)

Facts answer **"what is true"** (your stack, conventions, decisions). Observations answer **"what happened"** — a narrative log of the moments in your sessions. ClaudeMemory now keeps both, modeled on [Mastra's Observational Memory](docs/influence/mastra-observational-memory.md).

| | Facts (semantic) | Observations (episodic) |
|---|---|---|
| Capture | Durable truths — `uses_database: sqlite` | Narrative events — "decided to add a corroboration gate to avoid reject-churn" |
| Change | Explicitly, via supersession/rejection | Automatically — deduped, consolidated, low-priority ones expire |
| Promotion | — | Promoted to a fact only after corroboration (≥2 sightings) |

**Why it's a leap forward:** the distiller used to commit a fact the first time it saw a claim — so a database mentioned once in a comparison could harden into a false `uses_database`. The observation layer makes repeated sighting the gate: an observation becomes a fact only after it recurs. That's an **anti-hallucination defense built into the memory model**, not a cleanup afterthought.

**How it runs (no extra API cost):**
- **Observer** — a regex Layer-1 pass plus Claude-as-observer in the SessionStart context hook emit observations as sessions happen.
- **Reflector** — deterministic dedup + TTL-expiry runs on `PreCompact`/`SessionEnd`; semantic consolidation rides the next turn's context hook (Claude-as-reflector). Superseded observations are *tombstoned*, never deleted, preserving provenance.
- **Promotion bridge** — corroborated observations graduate to facts on the corroboration gate.

**See it / use it:** the dashboard's **Observations** panel (counts by kind/priority, corroboration + promotion readiness, source→observation compression ratio, recent timeline); the `claude-memory observations` CLI; the `memory.observations` / `memory.promote_observation` / `memory.consolidate_observations` MCP tools; and the `/reflect` skill for a guided survey→consolidate→promote pass.

## What's New in 0.13.0

**Episodic Observation Layer** — ClaudeMemory gains a second kind of memory (see [Episodic Memory](#episodic-memory-observations) above):

- New `observations` table (schema v19–v20), append-only with `consolidated_into` tombstone lineage and `corroboration_count` / `promoted_at` / `promoted_fact_id` promotion tracking.
- Two-block SessionStart injection: a stable observation log (🔴-marked) + the undistilled "pending knowledge" tail.
- Automatic reflection on `PreCompact` (context-pressure, Mastra's token-threshold analog) and `SessionEnd` — deterministic GC shell-side in Ruby, semantic consolidation via the context hook (no extra API spend).
- Corroboration-gated observation→fact promotion — repeated sightings required before commitment, an anti-hallucination gate against reject-churn from one-off doc/example text.
- New surfaces: dashboard **Observations** panel, `claude-memory observations` command (+ `claude-memory stats --observations`), `claude-memory audit` observation health checks, three `memory.*observation*` MCP tools, and the `/reflect` skill.
- Dependencies refreshed to current (sequel, standard, rubocop, and others).

## What's New in 0.11.0

Five user-visible signals so you can answer "is memory still worth it?" with
numbers, not vibes:

- **Token budget telemetry** — every SessionStart context injection now
  records its estimated `context_tokens`. `claude-memory stats --tokens
  [--since DAYS]` reports p50/p95/avg/min/max plus a histogram across
  <500 / 500-1k / 1-2k / 2-5k / 5k+ buckets so you can see the per-session
  cost at a glance. The dashboard's Trust panel and `claude-memory digest`
  surface the same numbers.
- **Hallucination-rate metric** — the dashboard now scores how *clean* the
  fact base is, not just how full it is. `Distill::BareConclusionDetector`
  flags `decision` / `convention` facts that skipped the reason-clause
  requirement. Trust panel shows `quality_score` (live 30-day window with
  historical baseline beneath). `claude-memory digest` adds a Quality
  section with rejection rate.
- **`claude-memory show`** — new command prints what memory *would* inject
  at the next SessionStart in plain Markdown. Footer reports fact count,
  ~token estimate, and char count so you see the cost at a glance. Default
  hides the raw-transcript "Pending Knowledge" dump for readability;
  `--pending` opts in. `--source startup|resume|clear` simulates each
  fresh-session entrypoint.
- **First-week ROI nudge** — at SessionEnd, memory now prints
  `memory contributed N facts this session, %used = X` for the first 10
  sessions, then quiets. Cold-start trust signal — you don't have to know
  about the dashboard. Opt out with `CLAUDE_MEMORY_NO_NUDGE=1`.
- **Harm benchmark prototype** — first ClaudeMemory benchmark that
  measures whether memory can make Claude *wrong*. Three hand-written
  cases (stale-tech, mismatched-scope, superseded-but-undetected) under
  `spec/benchmarks/e2e/harm_bench_spec.rb`. Real-mode run on the 0.11
  release reported 0/3 harm; the full 10-15-case corpus + release gate
  lands in 0.12.

## What's New in 0.10.0

Three behavior changes worth knowing about — they affect what you'll see in
extracted facts and SessionStart context, even if you don't change anything:

- **Auto-memory mirror** — On fresh sessions, the SessionStart context hook
  scans `~/.claude/projects/<slug>/memory/*.md` and surfaces new or changed
  entries as candidates for extraction into ClaudeMemory. You'll see a
  "Pending Knowledge Extraction" section in Claude's startup context citing
  files from your auto-memory directory. Claude reviews these and calls
  `memory.store_extraction` for the high-signal ones; you don't need to
  copy-paste manually anymore.
- **Why-clause enforcement** — When Claude distills `decision` and
  `convention` facts, it's now required to embed a reason ("…because…",
  "…so that…", "…to avoid…"). A bare conclusion is dead weight; a fact with
  a reason stays useful when the situation changes. You'll see this
  reflected in fact text being longer and more justified.
- **Reference predicate** — Active facts that look like reference material
  (LOC counts, "X is a plugin/library/tool" templates, "by Firstname
  Lastname" attributions) are auto-tagged `predicate=reference` instead of
  `convention`. Keeps the conventions list signal-rich. Browse them in the
  dashboard's Knowledge → References section, or run
  `claude-memory reclassify-references --dry-run` to see candidates.

Plus: **staleness detection** (`claude-memory stats --stale`) lists active
facts that haven't been recalled in N days, so you can prune dead weight
explicitly. The dashboard's Trust → Needs review panel surfaces the count.

## Privacy Control

Exclude sensitive data from memory using privacy tags:

```
You: "My API key is <private>sk-abc123</private>"
Claude: [uses it during session]

# Stored: "API endpoint configured with key"
# NOT stored: "sk-abc123"
```

Supported tags: `<private>`, `<no-memory>`, `<secret>`

## Upgrading

Existing users can upgrade seamlessly:

```bash
gem update claude_memory
```

All database migrations happen automatically. Run `claude-memory doctor` to verify.

### After upgrading: refresh the Claude Code plugin

If you installed claude-memory as a Claude Code plugin (via the marketplace), pull the latest plugin spec **and reload it in your current session**:

```
/plugin marketplace update claude-memory
/reload-plugins
```

`/plugin marketplace update` refreshes the plugin manifest from the source, but **the new slash commands won't appear until you run `/reload-plugins` (or restart Claude Code)** — slash commands are loaded once at session start. This bites every release that adds a new command (e.g. `/distill-transcripts` in 0.11, `/audit-memory` in 0.12); if a documented slash command doesn't autocomplete after upgrade, `/reload-plugins` is the fix.

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

## Troubleshooting

### Check Setup Status

If memory tools aren't working, check initialization status:

```
memory.check_setup
```

This returns:
- Initialization status (healthy, needs_upgrade, not_initialized)
- Version information
- Missing components
- Actionable recommendations

### Installation Help

Need help getting started? Run:

```
/setup-memory
```

This skill provides:
- Step-by-step installation instructions
- Common error solutions
- Post-installation verification
- Upgrade guidance

### Health Check

Verify your ClaudeMemory installation:

```bash
claude-memory doctor
```

This checks:
- Database existence and integrity
- Schema version compatibility
- sqlite-vec availability and index coverage
- Hooks configuration
- Snapshot status
- Stuck operations

### Uninstalling

To remove ClaudeMemory configuration:

```bash
# Remove hooks and MCP configuration (keeps databases)
claude-memory uninstall

# Remove everything including databases
claude-memory uninstall --full

# For global uninstall
claude-memory uninstall --global
claude-memory uninstall --global --full
```

The uninstall command removes:
- Hooks from `.claude/settings.json`
- MCP server from `.claude.json`
- ClaudeMemory section from `CLAUDE.md`
- Databases and generated files (with `--full`)

**Note:** The `doctor` command will warn you if orphaned hooks are detected (hooks configured but MCP plugin removed). Run `claude-memory uninstall` to clean them up.

## Documentation

- 📖 [Getting Started](docs/GETTING_STARTED.md) - Step-by-step onboarding
- 💡 [Examples](docs/EXAMPLES.md) - Use cases and workflows
- 📊 [Dashboard](docs/dashboard.md) - Local web UI for inspection and trust signals (0.10.0+)
- 🔧 [Plugin Setup](docs/plugin.md) - Claude Code integration
- 🏗️ [Architecture](docs/architecture.md) - Technical deep dive
- 🔒 [API Stability](docs/api_stability.md) - What's stable / experimental / internal across releases (0.12.0+)
- 📝 [Changelog](CHANGELOG.md) - Release notes

## Benchmarks

ClaudeMemory includes **DevMemBench**, a developer-domain benchmark suite that measures retrieval quality, truth maintenance accuracy, **negative-fact harm**, and **uplift over a hand-written CLAUDE.md baseline**. All offline benchmarks run locally at zero cost; end-to-end and comparative runs use real Claude (~$5-15 per full run).

### Does memory ever make Claude *wrong*?

Every other benchmark measures whether memory helps. The negative-fact harm benchmark measures whether memory can hurt — injecting a stale, mis-scoped, superseded, or reference-material fact and watching Claude follow it. 13 scenarios across 4 harm classes, each with a realistic project scaffold whose actual state contradicts the wrong fact, scored best-of-3 by majority vote. The run fails the build if any scenario reliably produces a harm (>1%).

```bash
EVAL_MODE=real HARM_BENCH_RUNS=3 EVAL_MAX_BUDGET_USD=0.50 bundle exec rspec spec/benchmarks/e2e/harm_bench_spec.rb
```

**0.12 baseline (2026-05-28): 0/13 harm.** See [`spec/benchmarks/README.md`](spec/benchmarks/README.md#harm_scenariosyml-13-scenarios-full-corpus-0120) for the full corpus and methodology.

### Is this better than a hand-written CLAUDE.md?

The single most important question for adoption is whether dynamic retrieval beats static context injection. ClaudeMemory ships a `CLAUDE.md baseline` adapter and a comparative E2E harness for exactly this. **The numbers aren't published yet (as of 0.12):** the current harness compares static CLAUDE.md (auto-loaded into every prompt) against ClaudeMemory's MCP-tool retrieval, but in headless `claude -p` mode Claude doesn't proactively call the recall tools, so the comparison doesn't yet exercise ClaudeMemory's retrieval path fairly. Publishing that gap as a headline number would mislead. The harness fix is tracked for 0.13 — see [`docs/1_0_punchlist.md`](docs/1_0_punchlist.md) #4.

### Latest Results

| Benchmark | Metric | Score |
|-----------|--------|-------|
| **Truth Maintenance** | Accuracy (100 cases) | **100%** |
| **FTS5 Retrieval** | Recall@5 (40 easy queries) | **97.5%** |
| **Semantic Retrieval** | Recall@5 (85 queries aggregate) | **78.6%** |
| **Semantic Retrieval** | Recall@5 (40 medium queries) | **69.6%** |
| **Hybrid Retrieval** | Recall@5 (100 queries aggregate) | **72.7%** |
| **Hybrid Retrieval** | Recall@10 (20 hard queries) | **62.8%** |
| **Scope Ranking** | Queries returning expected facts | **5/5** |
| **Negative-Fact Harm (prototype)** | 0.11 baseline (3 scenarios, real Claude) | **0/3** |
| **Negative-Fact Harm (full corpus)** | 0.12 baseline (13 scenarios, best-of-3, real Claude) | **0/13 (0.0%)** |
| **E2E vs CLAUDE.md baseline** | 0.12 acceptance-rate delta (10 scenarios) | *deferred to 0.13 — harness doesn't exercise headless retrieval (#4)* |

Semantic and hybrid retrieval use [fastembed-rb](https://github.com/khasinski/fastembed-rb) with the BAAI/bge-small-en-v1.5 model (384-dim, runs locally, no API key needed).

### What the benchmarks measure

**Retrieval accuracy** -- Given a database of ~105 developer-domain facts across 5 simulated projects, how well does search find the right facts? Measured with standard IR metrics (Recall@k, MRR, nDCG@10) across 155 queries at varying difficulty levels (exact keyword match, semantic paraphrase, cross-category synthesis, abstention, temporal).

**Truth maintenance** -- Given pairs of existing and incoming facts, does the resolver correctly determine the outcome? 100 FEVER-inspired cases test four outcomes: supersession (new stated fact replaces old), conflict (inferred fact contradicts stated), accumulation (multi-value predicates coexist), and corroboration (same fact adds provenance).

**End-to-end with Claude** -- 31 scenarios across 5 LongMemEval ability categories (information extraction, multi-session reasoning, temporal reasoning, knowledge updates, abstention). Requires `EVAL_MODE=real` and costs ~$2-8 per run.

### Running benchmarks

```bash
# Offline benchmarks ($0, ~8 seconds)
bundle exec rspec spec/benchmarks/ --tag benchmark --format documentation

# Full evals + benchmarks
./bin/run-evals --all

# End-to-end with real Claude (~$2-8)
EVAL_MODE=real bundle exec rspec spec/benchmarks/e2e/ --tag eval_real
```

The benchmark dataset draws from real CLAUDE.md patterns and is designed specifically for ClaudeMemory's 6 predicates and 8 entity types. Open IR datasets (BEIR, FEVER, LongMemEval) informed the methodology but don't cover developer-domain knowledge.

👉 **[Benchmark Details →](spec/benchmarks/README.md)**

## For Developers

- **Language:** Ruby 3.2+
- **Storage:** SQLite3 (no external services)
- **Testing:** 1964 examples (~1700 unit/integration + ~250 benchmarks/evals), 100% core coverage
- **Code Style:** Standard Ruby

```bash
git clone https://github.com/codenamev/claude_memory
cd claude_memory
bin/setup
bundle exec rspec
```

👉 **[Development Guide →](CLAUDE.md)**

## Support

- 🐛 [Report a bug](https://github.com/codenamev/claude_memory/issues)
- 💬 [Discussions](https://github.com/codenamev/claude_memory/discussions)

## License

MIT - see [LICENSE.txt](LICENSE.txt)

---

**Made with ❤️ by [Valentino Stoll](https://github.com/codenamev)**
