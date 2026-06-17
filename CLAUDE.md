# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeMemory is a Ruby gem that provides long-term, self-managed memory for Claude Code using hooks, MCP tools, and output styles. It ingests transcripts, distills them into facts with provenance, resolves contradictions, and publishes curated snapshots.

**Key dependencies:**
- Ruby 3.2.0+
- Sequel (~> 5.0) for database access
- Extralite (~> 2.14) for high-performance SQLite storage

## Working with This Codebase

**Check memory before exploring code.** Use `memory.recall`, `memory.decisions`, `memory.architecture`, or `memory.conventions` to find existing knowledge before reading files.

**Public API contract:** [docs/api_stability.md](docs/api_stability.md) is the authoritative stable-surface list (CLI, MCP, hooks, Ruby API, schema, predicate vocabulary). When changing any of those surfaces, update the doc in the same commit; if it's a soft-rename, wire `ClaudeMemory::Deprecations.warn`.

**Audit memory health:** run `claude-memory audit` (or `/audit-memory` for an interactive walkthrough) to surface inconsistencies, regressions, and optimization opportunities. See [docs/audit_runbook.md](docs/audit_runbook.md) for per-check rationale and remediation steps.

### Git Usage & Best Practices

- Before each commit, apply the quality-review skill
- Iteratively commit related changes with their tests


## Development Commands

### Setup
```bash
bin/setup              # Install dependencies
```

### Testing
```bash
bundle exec rspec                              # Run unit/integration tests (~76s)
bundle exec rspec spec/claude_memory/cli_spec.rb  # Run single test file
bundle exec rspec spec/claude_memory/cli_spec.rb:42  # Run specific test by line number
bundle exec rake spec                          # Alternative test command
bundle exec rake                               # Run tests + Standard linter (default task)
```

**Note:** Benchmarks and evals are excluded from the default `rspec` run via `.rspec`. See the [Evals](#evals) and [Benchmarks](#benchmarks-devmembench) sections for running those separately.

### Linting
```bash
bundle exec rake standard        # Run Standard Ruby linter
bundle exec rake standard:fix    # Auto-fix linting issues
```

### Build & Release
```bash
bundle exec rake build   # Build gem to pkg/
bundle exec rake install # Install gem locally
bundle exec rake release # Tag + push to RubyGems (requires credentials)
```

### Running the CLI
```bash
# During development, use the executable directly
./exe/claude-memory <command>

# Or via bundle exec
bundle exec claude-memory <command>
```

### Evals
```bash
# Run automated evaluation suite (stub mode - fast, free)
./bin/run-evals                # Run all evals with summary report

# Run real eval validation (slow, costs ~$0.12)
./bin/run-real-evals all       # Run all scenarios with real Claude
./bin/run-real-evals convention_recall,tech_stack_recall  # Specific scenarios

# Or run directly with RSpec
bundle exec rspec spec/evals/  # Run all eval scenarios (stub mode)
bundle exec rspec --tag eval   # Run only eval-tagged tests
EVAL_MODE=real bundle exec rspec spec/evals/ --tag eval_real  # Real mode
```

The eval framework tests ClaudeMemory's effectiveness by comparing baseline (no memory) vs memory-enabled responses. See `spec/evals/README.md` for details, `spec/evals/REAL_MODE.md` for real Claude execution, and `spec/evals/CI_INTEGRATION.md` for GitHub Actions integration.

### Benchmarks (DevMemBench)
```bash
# Run offline benchmarks - retrieval accuracy + truth maintenance ($0, ~8s)
bundle exec rspec spec/benchmarks/ --tag benchmark --format documentation

# Run all evals + benchmarks together
./bin/run-evals --all

# Run only benchmarks (skip evals)
./bin/run-evals --benchmarks-only

# End-to-end with real Claude (~$2-8)
EVAL_MODE=real bundle exec rspec spec/benchmarks/e2e/ --tag eval_real
```

DevMemBench measures retrieval accuracy (Recall@k, MRR, nDCG@10) across 155 queries, truth maintenance correctness across 100 cases, and end-to-end Claude response quality across 31 scenarios. Semantic and hybrid retrieval use [fastembed-rb](https://github.com/khasinski/fastembed-rb) (BAAI/bge-small-en-v1.5, local ONNX, no API key). See `spec/benchmarks/README.md` for full details.

### Comparative Benchmarks
```bash
bin/setup-competitors              # Install QMD + grepai + dependencies (~3GB)
bin/setup-competitors --check      # Show what's installed
bin/setup-competitors --qmd-only   # Only install QMD + Bun
bin/setup-competitors --grepai-only # Only install grepai + Ollama
bin/run-evals --comparative        # Run benchmarks with available tools
bin/run-evals --comparative --setup-competitors  # Install + run in one step
```

### Distillation Extraction Accuracy

NullDistiller (regex, Layer 1):
  - Concept Recall: 0.952 (regex-detectable entities/facts)
  - Fact Precision: 1.000, Fact Recall: 1.000 (on 31 test cases)
  - Pipeline latency: P95 < 5ms (medium text)

Claude Code (LLM, Layers 2+3):
  - Concept Recall: 0.902 (all 41 cases)
  - Concept Recall on semantic cases: 0.900 (vs NullDistiller's 0.333)
  - Avg facts stored per case: 1.6

## Architecture

### Dual-Database System
ClaudeMemory uses two SQLite databases for memory separation:

- **Global DB** (`~/.claude/memory.sqlite3`): User-wide knowledge across all projects (preferences, conventions)
- **Project DB** (`.claude/memory.sqlite3`): Project-specific facts and decisions

The `Store::StoreManager` class manages both connections. Commands query both databases by default, with project facts taking precedence.

### Core Pipeline

```
Transcripts → Ingest → Index (FTS5)
                   ↓
             Distill → Extract entities/facts + scope hints
                   ↓
             Resolve → Truth maintenance (supersession/conflicts)
                   ↓
             Store → SQLite (facts, provenance, entities)
                   ↓
             Publish → .claude/rules/claude_memory.generated.md
```

### Three-Layer Distillation

The distillation pipeline operates at three levels of depth:

- **Layer 1: NullDistiller** (automatic, regex, free) — Runs in the ingest pipeline on every hook event. Extracts entities, facts, and scope hints using pattern matching. P95 latency < 5ms.
- **Layer 2: Context Hook Injection** (automatic, LLM, zero extra cost) — At SessionStart, undistilled content is injected into the session via `hookSpecificOutput.additionalContext` with extraction instructions. Claude Code itself acts as the distiller, extracting structured facts at no additional API cost. The same prompt also asks Claude to emit episodic **observations** (the Layer-2 Claude-as-observer) in the `observations` field of its `memory.store_extraction` call — coerced/validated at the handler border and persisted via the resolver alongside facts.
- **Layer 3: `/distill-transcripts` Skill** (manual, on-demand) — Deep extraction triggered by the user. Processes undistilled content with depth-aware prompts (initial extraction, consolidation, contradiction resolution).

New MCP tools `memory.undistilled` and `memory.mark_distilled` support the pipeline by tracking which content items have been deeply distilled.

### Module Structure

#### Application Layer

- **`CLI`**: Thin command router (`cli.rb`) - 41 lines
  - Routes commands to dedicated command classes via Registry
  - No business logic (pure dispatcher)

- **`Commands`**: Individual command classes (`commands/`)
  - Each command is a separate class (HelpCommand, DoctorCommand, etc.)
  - All commands inherit from BaseCommand
  - Dependency injection for I/O (stdout, stderr, stdin)
  - 38 commands total, each focused on single responsibility

- **`Configuration`**: Centralized ENV access (`configuration.rb`)
  - Single source of truth for paths and environment variables
  - Testable with custom ENV hash

#### Core Domain Layer

- **`Domain`**: Rich domain models with business logic (`domain/`)
  - `Fact`: Facts with validation, status checking (active?, superseded?, rejected?)
  - `Entity`: Entities with type checking (database?, framework?)
  - `Provenance`: Evidence with strength checking (stated?, inferred?)
  - `Conflict`: Conflicts with status tracking (open?, resolved?)
  - All domain objects are immutable (frozen) and self-validating

- **`Core`**: Value objects and null objects (`core/`)
  - Value objects: SessionId, TranscriptPath, FactId (type-safe primitives)
  - Null objects: NullFact, NullExplanation (eliminates nil checks)
  - Result: Success/Failure pattern for consistent error handling

#### Infrastructure Layer

- **`Store`**: SQLite database access via Sequel (`store/`)
  - `SQLiteStore`: Database operations
  - `StoreManager`: Dual-database connection manager
  - Schema includes: content_items, entities, facts, provenance, fact_links, conflicts, mcp_tool_calls
  - Transaction safety for multi-step operations

- **`Infrastructure`**: I/O abstractions (`infrastructure/`)
  - `FileSystem`: Real filesystem wrapper
  - `InMemoryFileSystem`: Fast in-memory testing without disk I/O

#### Business Logic Layer

- **`Ingest`**: Transcript reading and delta-based ingestion (`ingest/`)
  - Tracks cursor position per session to avoid re-processing

- **`Index`**: Full-text search and vector indexing (`index/`)
  - `LexicalFTS`: SQLite FTS5 full-text search
  - `VectorIndex`: sqlite-vec native KNN search with vec0 virtual tables
  - Optimized with batch queries to eliminate N+1 issues

- **`Distill`**: Fact extraction interface (`distill/`)
  - Pluggable distiller design (current: NullDistiller stub)
  - Extracts entities, facts, scope hints from content
  - `ReferenceMaterialDetector`: classifies "X is a plugin/library/tool" templates, LOC counts, "by Firstname Lastname" attributions as reference material. Runs in `ManagementHandlers#store_extraction` so mislabeling can't persist
  - `BareConclusionDetector` (0.11.0+): production-side mirror of the SessionStart prompt's reason-clause requirement. Pure function — flags `decision` / `convention` facts whose object lacks a reason-clause signal ("because", "so that", "to avoid", etc.). Powers the `quality_score` metric on the Trust panel and the digest's Quality section.
  - SessionStart distillation prompt enforces reason clauses ("because…", "so that…") for `decision` and `convention` predicates — bare conclusions are explicitly disallowed

- **`Resolve`**: Truth maintenance and conflict resolution (`resolve/`)
  - Determines equivalence, supersession, or conflicts
  - PredicatePolicy: single source of truth for predicate vocabulary, cardinality, section mapping, and synonym canonicalization
  - Transaction safety for atomic operations

- **`Recall`**: Query interface for facts (`recall.rb`)
  - Searches both global + project databases
  - Batch queries to avoid N+1 performance issues
  - Returns facts with provenance receipts

- **`Sweep`**: Maintenance and pruning (`sweep/`)

- **`Publish`**: Snapshot generation (`publish.rb`)
  - Uses FileSystem abstraction for testability
  - Modes: shared (repo), local (uncommitted), home (user directory)

- **`MCP`**: Model Context Protocol server and tools (`mcp/`)
  - Exposes memory tools to Claude Code (23 tools total)
  - `Telemetry`: Records tool invocations to `mcp_tool_calls` table for usage stats
  - Dual content/structuredContent responses with compact mode

- **`Hook`**: Hook entrypoint handlers (`hook/`)
  - Reads stdin JSON from Claude Code hooks
  - Routes to ingest/sweep/publish commands
  - `DistillationRunner`: Manages context hook injection with undistilled content for LLM extraction
  - `AutoMemoryMirror` (0.10.0): On fresh sessions, scans `~/.claude/projects/<slug>/memory/*.md` for new/changed entries and surfaces them as extraction candidates in the SessionStart context. State diffed by md5 in `.claude/auto_memory_mirror.json`; bounded to 5 candidates per session, 1500 chars each.

### Database Schema

Key tables (defined in `sqlite_store.rb`):
- `content_items`: Ingested transcript chunks with cursor tracking
- `entities`: Named entities (people, repos, concepts)
- `entity_aliases`: Alternative names for entities
- `facts`: Subject-predicate-object triples with validity windows and scope
- `provenance`: Links facts to source content_items
- `fact_links`: Supersession and conflict relationships
- `conflicts`: Open contradictions
- `mcp_tool_calls`: MCP server tool invocation telemetry (schema v13)
- `activity_events`: Hook/recall/context/sweep/nudge telemetry (schema v15) — powers the dashboard timeline, moments feed, efficacy reports. Event types: `hook_ingest`, `hook_context` (carries `context_tokens` since 0.11.0), `hook_sweep`, `hook_publish`, `recall`, `store_extraction`, `roi_nudge` (since 0.11.0).
- `moment_feedback`: Per-moment 👍/👎 verdicts with optional notes (schema v16) — unique on event_id, repeat clicks upsert
- `observations`: Episodic "what happened" layer (schema v19–v20) — append-only narrative rows complementing facts ("what is true"). Columns: `body`, `kind` (decision/preference/event/…), `priority` (1=🔴/2=🟡/3=info), `scope`, `source_content_item_id` (provenance), `consolidated_into` (Reflector tombstone lineage — never hard-deleted), `token_count`, `status`, `corroboration_count` (folded by dedup; the promotion-gate signal), `promoted_at`/`promoted_fact_id` (set when promoted to a fact). Written by the Resolver from `Extraction#observations` (NullDistiller is the Layer-1 Observer). The full observational layer (Observer → injection → deterministic Reflector → promotion bridge) is in `lib/claude_memory/observe/`; see [docs/influence/mastra-observational-memory.md](docs/influence/mastra-observational-memory.md).

Facts include:
- `scope`: "global" or "project" (determines applicability)
- `project_path`: Set for project-scoped facts
- `valid_from`/`valid_to`: Temporal validity window
- `last_recalled_at` (schema v17): Set by `Sweep::RecallTimestampRefresher` from activity_events; powers `claude-memory stats --stale` and the dashboard's "stale" needs-review count

### Scope System

Facts are scoped to control where they apply:

<no-memory>
- **project**: Current project only (e.g., "claude_memory uses SQLite for storage")
- **global**: All projects (e.g., "I prefer 4-space indentation")

Distiller detects signals like "always", "in all projects", "my preference" and sets `scope_hint: "global"`. Users can manually promote facts via `claude-memory promote <fact_id>` or the `memory.promote` MCP tool.
</no-memory>

## Testing Strategy

Tests are in `spec/claude_memory/` organized by module. Use RSpec's `--format documentation` for readable output.

When writing tests:
- Mock external dependencies (file I/O, database where appropriate)
- Use `let` blocks for shared test data
- Focus on behavior, not implementation details

## Common Development Tasks

### Adding a New CLI Command

1. Create new command class in `lib/claude_memory/commands/` (e.g., `my_command.rb`)
2. Inherit from `BaseCommand` and implement `call(args)` method
3. Add command to `Commands::Registry::COMMANDS` hash
4. Add corresponding tests in `spec/claude_memory/commands/my_command_spec.rb`
5. Use dependency injection for I/O (stdout, stderr, stdin) for testability

Example:
```ruby
class MyCommand < BaseCommand
  def call(args)
    opts = parse_options(args, {flag: false}) do |o|
      OptionParser.new do |parser|
        parser.on("--flag", "Enable flag") { o[:flag] = true }
      end
    end
    return 1 if opts.nil?

    stdout.puts "Command executed!"
    0  # Exit code
  end
end
```

### Adding a New MCP Tool

1. Add tool definition to `ToolDefinitions.all` array in `lib/claude_memory/mcp/tool_definitions.rb`
2. Add `when` clause in `Tools#call` dispatch in `lib/claude_memory/mcp/tools.rb`
3. Implement handler method in the appropriate handler module in `mcp/handlers/`
4. Ensure tool queries appropriate database(s) via StoreManager
5. Add tests in `spec/claude_memory/mcp/`

### Modifying Database Schema

1. Increment `SCHEMA_VERSION` in `store/schema_manager.rb`
2. Create a new Sequel migration file in `db/migrations/` (e.g., `013_add_mcp_tool_calls.rb`)
3. Sequel::Migrator runs migrations automatically in `ensure_schema!`
4. Test migration on existing database files
5. Update documentation if schema changes affect external interfaces

### Adding a New Predicate

Edit `PredicatePolicy::POLICIES` in `lib/claude_memory/resolve/predicate_policy.rb` — this is the single source of truth. Choose cardinality:

- **single** (exclusive: true): Facts supersede or conflict (e.g., `uses_database` — one per project)
- **multi** (exclusive: false): Facts accumulate (e.g., `convention`, `uses_framework`)

Also update `SECTION_MAP` if the predicate should appear in a specific snapshot section (`:decisions`, `:conventions`, `:constraints`). The `ToolDefinitions` predicate list updates automatically via `PredicatePolicy.known_predicates`. Add entries to `SYNONYMS` if the distiller might emit variant names.

## Important Files

- `lib/claude_memory.rb`: Main module, requires, database path helpers
- `lib/claude_memory/cli.rb`: Thin command router (41 lines)
- `lib/claude_memory/commands/`: Individual command classes (38 commands)
- `lib/claude_memory/configuration.rb`: Centralized configuration and ENV access
- `lib/claude_memory/domain/`: Domain models (Fact, Entity, Provenance, Conflict)
- `lib/claude_memory/core/`: Value objects and null objects
- `lib/claude_memory/infrastructure/`: I/O abstractions (FileSystem)
- `lib/claude_memory/store/store_manager.rb`: Dual-database connection manager
- `lib/claude_memory/resolve/resolver.rb`: Truth maintenance with transaction safety
- `lib/claude_memory/recall.rb`: Optimized fact query with batch loading
- `docs/quality_review.md`: Quality improvements and refactoring notes
- `claude_memory.gemspec`: Gem metadata and dependencies

## MCP Integration

The gem includes an MCP server (`claude-memory serve-mcp`) that exposes memory operations as tools. Configuration should be in `.mcp.json` at project root.

Available MCP tools (23 total):
- **Query & Recall**: `memory.recall`, `memory.recall_index`, `memory.recall_details`, `memory.recall_semantic`, `memory.search_concepts`
- **Provenance**: `memory.explain`, `memory.fact_graph`
- **Shortcuts**: `memory.decisions`, `memory.conventions`, `memory.architecture`
- **Context**: `memory.facts_by_tool`, `memory.facts_by_context`
- **Management**: `memory.promote`, `memory.reject_fact`, `memory.store_extraction`
- **Distillation**: `memory.undistilled`, `memory.mark_distilled`
- **Monitoring**: `memory.status`, `memory.stats`, `memory.changes`, `memory.conflicts`, `memory.activity`
- **Observational layer** (experimental): `memory.observations` (read-only episodic log), `memory.promote_observation` (corroboration-gated observation→fact promotion)
- **Maintenance**: `memory.sweep_now`
- **Discovery**: `memory.check_setup`, `memory.list_projects`

## Hook Integration

ClaudeMemory integrates with Claude Code via hooks in `.claude/settings.json`:

- **Ingest hook**: Triggers on Stop/SessionStart/PreCompact/SessionEnd/TaskCompleted/TeammateIdle events
  - Calls `claude-memory hook ingest` with stdin JSON
  - Reads transcript delta and updates both global and project databases

- **Context hook**: Triggers on SessionStart
  - Calls `claude-memory hook context`
  - Injects recent facts via `hookSpecificOutput.additionalContext`
  - Two-block layout (observational layer): Block 1 = the episodic observation log (`Observe::ObservationsRenderer`, 🔴-marked), Block 2 = the undistilled "Pending Knowledge Extraction" tail. `ContextInjector#emitted_observation_count` feeds the `hook_context` telemetry.

- **Sweep hook**: Triggers on PreCompact/SessionEnd events
  - Runs time-bounded maintenance on both databases
  - Cleans up vec0 entries for superseded/expired facts
  - Runs the deterministic observation Reflector (`Observe::Reflector` via `Maintenance#reflect_observations`): dedupes near-identical observations + expires stale 🟢 info-level ones (TTL `observation_info_ttl_days`). Free/no-LLM, provenance-preserving (tombstone). Context-pressure-triggered — the analog of Mastra's token-threshold reflection.

- **Nudge hook** (0.11.0+): Triggers on SessionEnd, fires after ingest+sweep
  - Calls `claude-memory hook nudge`
  - For the first 10 sessions only, prints "memory contributed N facts this session, %used = X" to stdout so new users see ROI inline before they discover the dashboard
  - Records `roi_nudge` activity_events; quiets after `MAX_NUDGES` emissions
  - Opt out with `CLAUDE_MEMORY_NO_NUDGE=1` (no event recorded on opt-out)
  - Empty sessions (n=0) silently no-op so quiet sessions don't burn nudge slots

Hook commands read JSON payloads from stdin for robustness. Supports `--async` flag for non-blocking execution.

## Dashboard

Local web UI for inspecting memory state. Started via `claude-memory dashboard` (default port 3377). Reads from both global and project databases; no write side effects from page loads.

The dashboard is a thin web layer over the same `Recall`/`Conflicts`/`Trust`/`Moments`/`Knowledge`/`Reuse`/`Health`/`Timeline` classes the MCP server uses. Each panel is backed by a dedicated module under `lib/claude_memory/dashboard/`; `Dashboard::API` holds HTTP-shape glue and per-endpoint formatting (delegating non-trivial logic to the panel classes).

Connections are released after each request — never holds a WAL writer lock open across page loads.

See [docs/dashboard.md](docs/dashboard.md) for the user-facing guide (panels, common workflows, related CLI commands).

## Code Style

This project uses [Standard Ruby](https://github.com/standardrb/standard) for linting. Run `bundle exec rake standard:fix` before committing.

Key conventions:
- Use `frozen_string_literal: true` at top of all Ruby files
- Prefer explicit returns only when control flow is complex
- Use Sequel's dataset methods (avoid raw SQL where possible)
- Keep CLI commands focused; extract complex logic to dedicated classes

## Custom Commands

### `/review-for-quality`

Runs a comprehensive quality review of the entire codebase.

**What it does:**
1. Launches a Plan agent to thoroughly explore the codebase
2. Critically reviews code for Ruby best-practices, idiom use, and overall quality
3. Analyzes through the perspectives of 5 Ruby experts:
   - **Sandi Metz** - POODR principles, single responsibility, small objects
   - **Jeremy Evans** - Sequel best practices, performance, simplicity
   - **Kent Beck** - Test-driven development, simple design, revealing intent
   - **Avdi Grimm** - Confident Ruby, explicit code, null objects, tell-don't-ask
   - **Gary Bernhardt** - Boundaries, functional core/imperative shell, fast tests
4. Updates `docs/quality_review.md` with findings including:
   - Specific file:line references for every issue
   - Which expert's principle is violated
   - Concrete improvement suggestions with code examples
   - Priority levels (Critical 🔴 / High / Medium 🟡 / Low)
   - Metrics comparison showing progress since last review
   - Quick wins that can be done immediately

**Usage:**
```
/review-for-quality
```

**Output:** Updated `docs/quality_review.md` with dated review and actionable refactoring recommendations.

### `/review-commit`

Quick quality review of staged changes for pre-commit validation through expert perspectives.

**What it does:**
1. Reviews only staged Ruby files (fast, < 30 seconds)
2. Applies Ruby best practices from 5 experts:
   - **Sandi Metz**: SRP, small methods (<15 lines), DRY, frozen_string_literal
   - **Jeremy Evans**: Sequel datasets over raw SQL, transaction safety, no N+1 queries
   - **Kent Beck**: Simple design, revealing names, Command-Query Separation
   - **Avdi Grimm**: Null objects, explicit returns, Law of Demeter, tell-don't-ask
   - **Gary Bernhardt**: Functional core/imperative shell, immutable values, fast tests
3. Returns clear BLOCK / WARNING / PASS verdict with expert attributions
4. Designed for headless mode (runs in git pre-commit hook)

**Critical checks (BLOCK):**
- Missing frozen_string_literal, methods >15 lines, classes >200 lines
- Raw SQL, DB writes without transactions, N+1 queries
- Nested conditionals >3 levels, Command-Query violations
- Implicit nil returns, defensive nil checks, bare rescue
- I/O mixed with logic, mutable value objects, I/O in tests
- New public methods without tests

**Warning checks:**
- Methods 10-15 lines, classes 100-200 lines, >3 parameters
- Poor naming, methods doing multiple things
- Law of Demeter violations, ask-don't-tell patterns
- Missing value objects, business logic in imperative shell

**Usage:**
```
/review-commit
```

**Output:** Console output with file:line references, expert attributions, and concrete fixes.

**Hook Integration:** Automatically runs via lefthook pre-commit hook when Ruby files are staged.

### `/study-repo`

Deep analysis of an external repository's architecture, patterns, and design decisions.

**What it does:**
1. Requires user to manually clone the target repository first
2. Performs systematic exploration through 6 phases:
   - Repository Context (metadata, dependencies, purpose)
   - Architecture Mapping (structure, modules, components)
   - Pattern Recognition (design patterns, conventions)
   - Code Quality Assessment (testing, docs, performance)
   - Comparative Analysis (vs ClaudeMemory's approach)
   - Adoption Opportunities (prioritized recommendations)
3. Creates comprehensive influence document in `docs/influence/<project>.md`
4. Updates `docs/improvements.md` with high-priority recommendations
5. Follows QMD analysis format with priority markers

**Usage:**
```bash
# Step 1: Clone repository to study
git clone --depth 1 https://github.com/user/project /tmp/study-repos/project

# Step 2: Run analysis
/study-repo /tmp/study-repos/project

# Optional: Focus on specific aspect
/study-repo /tmp/study-repos/project --focus="MCP implementation"

# Step 3: Review generated documents
# - docs/influence/project.md (detailed analysis)
# - docs/improvements.md (updated with recommendations)

# Step 4: Implement selected improvements
/improve
```

**Output:**
- `docs/influence/<project_name>.md` - Comprehensive analysis with code examples
- `docs/improvements.md` - Updated with dated section of recommendations
- Console summary of key findings and priorities

**Integration with `/improve`:**
The recommendations added to `docs/improvements.md` can be implemented using the `/improve` skill, creating a complete workflow:
```
/study-repo → adds recommendations → /improve → implements features
```

**Focus Mode:**
Use `--focus` to narrow analysis to specific aspects (testing, MCP, database, CLI, performance). See `.claude/skills/study-repo/focus-examples.md` for examples.
