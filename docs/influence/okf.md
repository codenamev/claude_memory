# Open Knowledge Format (OKF) Analysis

*Analysis Date: 2026-07-16*
*Repository: https://github.com/GoogleCloudPlatform/knowledge-catalog (subdirectory `okf/`)*
*Version/Commit: d44368c (2026-06-20), OKF spec v0.1 Draft*

---

## Executive Summary

**Purpose.** OKF is a vendor-neutral *specification* for representing knowledge as plain
markdown files with YAML frontmatter, organized in a directory hierarchy ("knowledge
bundle"). The repo pairs the spec (`SPEC.md`) with a proof-of-concept **producer** (a
Google ADK reference agent that enriches BigQuery dataset metadata into bundles) and a
proof-of-concept **consumer** (a self-contained HTML graph viewer). The format is the
contribution; the agent and viewer exist to make it tangible at both ends.

**Key innovation.** Not any single mechanism — it's that the *format itself is specified*
(SPEC.md §10: "OKF differs primarily in being **specified**"). It pins down the minimal
rules for interoperability (one required frontmatter key: `type`; reserved filenames
`index.md`/`log.md`; permissive consumption) and leaves everything else to producers.
Progressive disclosure via auto-generated `index.md` files and graph-shaped cross-links
via ordinary markdown links are first-class.

**Technology stack** (reference agent only — the format needs none):

| Layer | Choice |
|---|---|
| Language | Python 3.11+ (~1,700 LOC src, ~830 LOC tests) |
| Agent framework | Google ADK (`google-adk>=2.0`), Gemini models |
| Metadata source | `google-cloud-bigquery` |
| Parsing | PyYAML frontmatter, `markdownify` for HTML→markdown |
| Viewer | Cytoscape.js + marked, CDN-loaded, single self-contained HTML |
| Tests | pytest, 7 files, no LLM calls in tests (deterministic seams injected) |

**Maturity.** v0.1 Draft spec, v0.1.0 agent. Proof-of-concept quality but carefully
engineered where it matters (tool-enforced budgets, augmentation guards). Three real
generated bundles are checked in (`bundles/ga4|stackoverflow|crypto_bitcoin`) — the
format is validated by its own outputs. Google Cloud Platform org backing suggests this
is a play for an interop standard in the agent-knowledge space.

---

## Architecture Overview

**Data model.** A *bundle* is a directory tree of markdown files. A *concept* is one file;
its concept ID is its path minus `.md` (`tables/users.md` → `tables/users`). Frontmatter
carries the queryable fields (`type` required; `title`, `description`, `resource`,
`tags`, `timestamp` recommended; arbitrary extensions preserved). The body carries prose,
`# Schema`, `# Examples`, `# Citations`. Cross-links are ordinary markdown links; a link
is an untyped directed edge whose semantics live in the surrounding prose (SPEC.md §5.3).
Broken links are legal — "not-yet-written knowledge" (SPEC.md §5.3).

**Module organization** (`okf/src/reference_agent/`):

```
bundle/          # Format core: document.py (parse/serialize/validate),
                 #   paths.py (concept-id ↔ path, segment validation),
                 #   index.py (bottom-up index.md regeneration),
                 #   synthesizer.py (LLM dir descriptions w/ deterministic fallback)
sources/         # Source abstraction: base.py (Source protocol, ConceptRef),
                 #   bigquery.py (schema/partitioning/sample-rows)
tools/           # Agent-facing FunctionTools: bundle_tools.py (read/write concept),
                 #   web_tools.py (budgeted fetch_url), source_tools.py,
                 #   context.py (module-global ToolContext/WebState)
web/fetcher.py   # stdlib urllib fetch → markdownify, 40KB truncation
agent.py         # Two ADK agents (BQ pass, web pass) built from prompts/*.md
runner.py        # Orchestration: per-concept BQ enrichment → web pass → reindex
viewer/          # generator.py walks bundle → JSON blob → templated viz.html
prompts/         # The real business logic: two long markdown instructions
```

**Design patterns.** Two-pass enrichment (deterministic metadata pass, then LLM-judged
web pass); tool-enforced hard limits (budget/allowlist/depth inside `fetch_url`, not the
prompt); write-time invariant guards (augmentation guard in `write_concept_doc`);
corrective error payloads that tell the LLM how to re-call; injectable seams for
determinism in tests (`regenerate_indexes(synthesize=...)` at `bundle/index.py:53`).

**Comparison vs ClaudeMemory:**

| Dimension | OKF | ClaudeMemory |
|---|---|---|
| Store of record | Markdown files in git | SQLite (dual DB), facts+provenance+observations |
| Unit of knowledge | Concept doc (prose + frontmatter) | Fact triple (subject/predicate/object) + observation rows |
| Truth maintenance | None — humans/git resolve | Resolver: supersession, conflicts, cardinality |
| Provenance | `# Citations` convention, git blame | `provenance` table linking facts→content_items |
| Retrieval | Progressive disclosure (index.md), grep, viewer | FTS5 + sqlite-vec RRF hybrid, MCP tools |
| Publish/export | The files ARE the format | `.claude/rules/claude_memory.generated.md` monolith |
| Interop | Vendor-neutral spec, anyone produces/consumes | Claude Code-specific (hooks/MCP) |
| Anti-hallucination | Tool-side guards + prompt gates | ReferenceMaterialDetector, BareConclusionDetector, corroboration gate |
| Change history | `log.md` per directory | `activity_events`, `memory.changes` |

The two systems are almost perfectly complementary: OKF specifies the *interchange
surface* and has no engine; ClaudeMemory is an *engine* whose interchange surface is one
generated monolith. OKF is what ClaudeMemory's publish step could speak.

---

## Key Components Deep-Dive

### 1. The spec's permissive consumption model (SPEC.md §9)

Conformance requires only: parseable frontmatter, non-empty `type`, reserved-filename
structure. Consumers MUST NOT reject on missing optional fields, unknown types, unknown
keys, broken links, or missing indexes. Rationale stated in-spec: bundles "grow, get
refactored, and are partially generated by agents" — a format for agent-written content
must tolerate agent imperfection structurally, not police it.

### 2. Progressive disclosure via bottom-up index regeneration (`bundle/index.py`)

`regenerate_indexes` (index.py:49-103) walks directories **deepest-first** so each parent
index can embed a description of its child directories. Entries group by `type`, carry
the child's frontmatter `description` verbatim, and directory descriptions are LLM-
synthesized with a deterministic fallback (`synthesizer.py:21-23`: "Contains N entries:
…"). Net effect: an agent can navigate a large bundle one `index.md` at a time instead of
loading everything — the file-system analog of ClaudeMemory's `memory.recall_index` →
`memory.recall_details` two-step.

### 3. Augmentation guard — loss-refusing writes (`tools/bundle_tools.py:114-154`)

During the web pass, `write_concept_doc` **refuses** any write that would shrink an
existing BigQuery Table doc's `# Schema` field set or `# Citations` entry count:

```python
missing = sorted(old_fields - new_fields)
if missing:
    return {"error": f"Refusing to write: the existing # Schema section lists
        {len(old_fields)} field(s) populated from BigQuery metadata, but your new
        # Schema is missing {len(missing)} of them: {shown}. Augment by adding to
        the existing schema, not replacing it. Re-call read_existing_doc …"}
```

The deterministic pass's ground truth cannot be destroyed by a later LLM pass. Note the
error is not a diagnostic — it's a **corrective re-prompt**: it names the invariant,
explains the fix, and tells the model exactly which tools to re-call in what order. Same
pattern on validation failure (bundle_tools.py:100-108).

### 4. Tool-enforced crawl discipline (`tools/web_tools.py`, `tools/context.py`)

Every crawl limit lives inside `fetch_url`, not the prompt: max-pages budget, allowed
hosts, path-prefix allowlist, denied substrings, visited-set, and a hop-depth map seeded
at depth 0. The sharpest detail (web_tools.py:65-74): a URL with **no recorded depth is
rejected** — it can only mean the agent *invented* a URL rather than following a link
returned by a fetched page. Hallucinated URLs are structurally unfetchable. The prompt
then restates the limits so the model doesn't waste turns discovering them
(runner.py:136-151: "Hard limits enforced by the fetch_url tool — do not retry rejected
URLs").

### 5. The four-gate reference mint test (`prompts/web_ingestion_instruction.md`)

Before the web agent may mint a standalone `references/<slug>` doc, the page must pass
four gates: **(1) topic shape** — defines something referenceable by name (entity,
metric, enum, glossary); **(2) not bundle-level meta** — hard slug blocklist (`overview`,
`intro`, `getting-started`, `quickstart`, `tutorial`, `changelog`, `faq`…); **(3)
citation test** — you can plausibly write `See the [X reference](/references/x.md) for …`
where X is a concrete noun; **(4) reuse test** — ≥2 existing concepts would cite it, or
one needs it as load-bearing background. "When in doubt, **skip**. A bundle with zero
`references/` docs is fine; a bundle full of `references/overview` is noise."
Structured extractions (metrics with concrete SQL, join paths with concrete `ON`
clauses) *bypass* the gates because they are "inherently concept-shaped" — each gets a
prescribed home (`references/metrics/<slug>.md`, `references/joins/<a>__<b>.md` with
sorted pair naming so there's one canonical file per join regardless of discovery
direction).

### 6. `log.md` — human-readable change history (SPEC.md §7)

An optional per-directory changelog: date-grouped bullets, newest first, each a prose
sentence with a bold verb (`**Update**`, `**Creation**`, `**Deprecation**`) and links to
the affected concepts. Git history gives the mechanical diff; `log.md` gives the
*narrative* — the episodic layer of a file-based knowledge store.

---

## Comparative Analysis

**What OKF does well:**

- **Specifies the interchange surface.** Multiple memory tools we've studied (claude-mem,
  supermemory, QMD, auto-memory's own `memory/*.md`) each invented a private
  markdown-ish convention. OKF writes the treaty: minimal required keys, reserved names,
  permissive consumption. Being right about only a few things is what makes it adoptable.
- **Guards invariants at the tool border with corrective errors** (bundle_tools.py:100,
  114-154). ClaudeMemory validates at the handler border too (ReferenceMaterialDetector
  in `store_extraction`), but OKF's errors are better *re-prompts* — they instruct the
  model how to recover, turning a failed call into a self-healing loop.
- **Makes hallucination structurally impossible where it can** (depth-tracked URL
  rejection, "cite only URLs you actually fetched") rather than merely discouraged.
- **Deterministic-first, LLM-second layering.** The BQ pass writes ground truth from
  metadata; the web pass may only augment. Mirrors ClaudeMemory's Layer 1 (NullDistiller)
  → Layer 2 (Claude-as-distiller) split, and independently arrives at the same rule we
  learned the hard way: the LLM layer must not overwrite the deterministic layer's facts.
- **Testable seams without mocking frameworks** — `regenerate_indexes` takes
  `synthesize:` as a callable (index.py:53); tests inject a stub and never touch Gemini.

**What ClaudeMemory does well (that OKF lacks entirely):**

- **Truth maintenance.** OKF has no supersession, no conflict detection, no cardinality.
  Two contradictory concept docs simply coexist until a human notices.
- **Provenance as data.** `# Citations` is a convention in prose; our `provenance` table
  is queryable, and `memory.explain` reconstructs why a fact exists.
- **Retrieval.** OKF's answer to "find the relevant knowledge" is directory navigation
  and a viewer; ours is FTS5+vec hybrid ranking with score traces.
- **Zero-extra-cost LLM integration.** OKF's synthesizer and both agent passes are
  separate Gemini API calls; our Layer 2/3 ride the existing Claude Code session.
- **Automatic ingestion.** OKF bundles are written by explicitly-run agents; our hooks
  ingest every session with no operator action.

**Trade-offs:**

| Axis | OKF (files) | ClaudeMemory (SQLite) |
|---|---|---|
| Diffable/reviewable | Native (git PRs per concept) | Only via generated snapshot |
| Queryable | grep + frontmatter scan | Indexed, ranked, scored |
| Interop | Any tool that reads markdown | Claude Code only |
| Consistency | None enforced | Resolver-enforced |
| Scale | Human-navigable to ~10³ docs | Indexed to far beyond |

---

## Adoption Opportunities

### High Priority ⭐

#### 1. OKF export target — `claude-memory export --format okf` ⭐

- **Value**: A vendor-neutral, git-reviewable, per-concept escape hatch for the whole
  memory corpus. One directory: `facts/<predicate>/<slug>.md` (or per-entity), each file
  carrying frontmatter (`type` from predicate section, `description`, `tags` from scope,
  `timestamp` from valid_from, plus `fact_id`/`status` as extension keys) and a body with
  the fact statement, reason clause, `# Citations` built from the provenance table, and
  cross-links for supersession/conflict edges. Auto-generated `index.md` files give
  progressive disclosure; `log.md` derives from `memory.changes`. This positions
  ClaudeMemory as an OKF *producer* in an interop space Google is seeding, answers the
  standing lock-in question ("what if I stop using this gem? — you keep a plain-markdown
  bundle"), and makes the corpus reviewable file-by-file in PRs instead of via one
  monolithic generated snapshot.
- **Evidence**: SPEC.md §3-§9 (format is small: frontmatter parse/serialize is 61 lines,
  `bundle/document.py`; index regeneration is 103 lines, `bundle/index.py`). Our publish
  layer already renders facts to markdown (`publish.rb`); this is a second renderer, not
  new infrastructure.
- **Implementation**: New `ExportCommand` (or `publish --format okf`); pure Ruby, reuses
  Recall + provenance queries. Conformance is cheap — required key is just `type`.
  Round-trip import is explicitly out of scope for v1 (resolver is the write path).
- **Effort**: Small-Medium (2-3 days incl. specs against SPEC.md §9 conformance).
- **Trade-off**: A second serialization to keep in sync with the snapshot renderer;
  OKF is a v0.1 draft and could shift (minor-version additive per §11, low risk).
- **Recommendation**: **ADOPT**

#### 2. Corrective re-prompt errors + loss-refusing guards in `memory.store_extraction` ⭐

- **Value**: Turn validation failures into self-healing loops. OKF's write tool never
  just says "invalid" — it names the violated invariant, states what to preserve, and
  says exactly which tool to re-call (`bundle_tools.py:100-108, 124-154`). Applying the
  same shape to our handler-border rejections (ReferenceMaterialDetector reclassification,
  observation coercion failures, unknown predicates) raises the odds the in-session Claude
  corrects itself instead of silently dropping the extraction — directly relevant to the
  Layer-2 dormancy problem (#72), where every lost `store_extraction` call is precious.
  The loss-refusing half: when an extraction *updates* an existing multi-value fact set
  or consolidates observations, refuse net-information-loss writes (e.g., a `decision`
  fact resubmitted without its reason clause when the stored one has it) with a
  re-prompt error — the write-time enforcement BareConclusionDetector currently only
  *scores*.
- **Evidence**: `bundle_tools.py:114-154` (schema/citation shrink guard);
  `web_ingestion_instruction.md` "Augmentation rules" (frontmatter full-dict replacement
  semantics spelled out to the model). Our analog surface:
  `mcp/handlers/management_handlers.rb` (`store_extraction`), resolver update paths.
- **Implementation**: Audit current rejection/coercion messages; rewrite to the
  three-part shape (invariant → what to keep → which tool to re-call with what). Add the
  reason-clause-loss guard behind the existing BareConclusionDetector.
- **Effort**: Small (1-2 days; mostly message-shape work + a few guard specs).
- **Trade-off**: Longer error payloads (tokens); guards must not be so strict they cause
  new reject-churn — start with warn-mode telemetry on the loss guard if in doubt.
- **Recommendation**: **ADOPT** (error shape) / **CONSIDER** (loss guard strictness)

#### 3. Four-gate reference mint test in the SessionStart distillation prompt ⭐

- **Value**: Our `reference` predicate accumulates junk from doc/tutorial text — the same
  failure OKF's gates exist to prevent, and adjacent to our documented distiller-
  hallucination pattern. Adding the gates (concrete-noun citation test, meta-page slug
  blocklist, reuse test, "when in doubt, skip — zero references is fine") to
  `ContextInjector`'s extraction prompt gives Claude a crisp *refusal* rubric,
  complementing ReferenceMaterialDetector's production-side catch. Prompt-side gate +
  tool-side detector is exactly OKF's dual defense (prompt gates + write guard).
- **Evidence**: `prompts/web_ingestion_instruction.md` "Mint a new reference concept —
  only if the page meets all four"; the checked-in bundles show the outcome — GA4's
  `references/` contains only metrics and joins, zero `overview`/`getting-started` junk.
- **Implementation**: Extend `ContextInjector#format_distillation_prompt` reference
  guidance; add the slug/title blocklist to `ReferenceMaterialDetector` as a
  corroborating signal.
- **Effort**: Small (half-day + prompt-eval spot check).
- **Trade-off**: Prompt length grows; gates tuned for web pages need rewording for
  transcript text.
- **Recommendation**: **ADOPT**

### Medium Priority

#### 4. `log.md`-style narrative changelog in the published snapshot

- **Value**: A `## Recent Changes` section (or sibling `claude_memory.log.md`) rendered
  from `memory.changes` — date-grouped, newest-first, bold-verb entries per SPEC.md §7.
  Makes memory evolution reviewable in the repo where the snapshot already travels;
  doubles as the episodic layer's human-facing surface.
- **Evidence**: SPEC.md §7; our `activity_events` + `memory.changes` already have the data.
- **Effort**: Small. **Recommendation**: CONSIDER (bundle with #1's `log.md` renderer).

#### 5. Sorted-pair canonical naming for symmetric relationships

- **Value**: OKF names join docs `references/joins/<a>__<b>.md` with the pair sorted
  alphabetically, guaranteeing one canonical doc regardless of which side the agent came
  from. Our resolver's equivalence checks for symmetric predicates (`related_to`-style,
  fact_links) could use the same canonicalization to prevent A→B / B→A duplicates.
- **Evidence**: `web_ingestion_instruction.md` join-path rules; `bundles/ga4/references/joins/events___ads_clickstats.md`.
- **Effort**: Small, but only pays off if/when symmetric predicates land.
  **Recommendation**: DEFER until a symmetric predicate exists.

### Low Priority

#### 6. Self-contained HTML graph export of the fact graph

- **Value**: `viz.html`-style shareable artifact (force-directed fact/entity graph +
  detail panel + backlinks) generated from `memory.fact_graph`, no server needed —
  a portable complement to the live dashboard.
- **Evidence**: `viewer/generator.py` (175 lines: walk → JSON blob → template).
- **Trade-off**: OKF's viewer loads Cytoscape/marked from CDN; ours would need vendored
  assets. Dashboard already covers the interactive need.
  **Recommendation**: DEFER.

### Features to Avoid

- **Separate LLM API calls for synthesis** (`bundle/synthesizer.py:40-47` calls Gemini
  per directory; both agent passes are metered API runs). Violates our no-extra-API-cost
  convention — any OKF-export index descriptions should render deterministically from
  fact data, with LLM polish only via in-session skills.
- **Module-global mutable tool context** (`tools/context.py:27-33` — `_ctx`/`_web`
  globals with setter/getter). Understandable for ADK FunctionTool signatures, but the
  opposite of our DI-everywhere testing strategy; do not import the pattern.
- **CDN-dependent generated artifacts** (viz.html loads Cytoscape.js/marked from CDN) —
  breaks offline and violates self-containedness we'd want in an exported artifact.
- **Markdown files as the store of record.** OKF has no resolver; adopting the format as
  our *storage* would forfeit truth maintenance, provenance queries, and hybrid
  retrieval. OKF is our export surface, never our engine.

---

## Implementation Recommendations

- **Phase 1 (small, immediate):** #3 four-gate prompt hardening + #2 error-shape audit.
  Both are prompt/message work targeting documented pain (reference junk, Layer-2
  extraction loss) with no schema impact.
- **Phase 2 (the headline):** #1 `export --format okf` with per-fact concept docs,
  provenance-derived citations, generated indexes, and (#4) the `log.md` renderer.
  Ship behind a plain CLI command; mention in README as the lock-in answer.
- **Phase 3 (opportunistic):** revisit #5/#6 when symmetric predicates or a
  share-the-graph use case actually appear.

## Architecture Decisions

- **Preserve**: SQLite + resolver as the engine; snapshot publish; no-extra-API-cost.
- **Adopt**: OKF as an export dialect; corrective re-prompt error shape; prompt-side
  mint gates layered over tool-side detectors; loss-refusing write guards (warn-first).
- **Reject**: files as store of record; per-call LLM synthesis; global tool state.

## Key Takeaways

1. **OKF is a treaty, not a tool** — the spec's value is being small, permissive, and
   explicit. ClaudeMemory can speak it from the publish layer for ~3 days of work and
   gain a lock-in-free interchange story.
2. **The best guardrails are structural**: budgets inside the tool, invented URLs
   unfetchable by construction, ground-truth sections that refuse to shrink. Prompts
   restate the rules; tools enforce them.
3. **Error messages are prompts.** OKF's write-tool errors are miniature re-prompts
   (invariant → preserve-what → re-call-how), and that shape is directly transplantable
   to our handler-border rejections where every recovered extraction matters.
4. **Independent convergence validates our layering**: deterministic pass writes ground
   truth, LLM pass may only augment — OKF arrived at the same rule as our Layer 1/2
   split and our scope_hint-is-advisory lesson.
5. **Their gaps are our moat**: no truth maintenance, no queryable provenance, no ranked
   retrieval, metered API costs. Interop with OKF adds reach without ceding any of it.
