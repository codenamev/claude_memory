# QMD Analysis: Quick Markdown Search (Updated)

*Analysis Date: 2026-02-02*
*Previous Analysis: 2026-01-26*
*Repository: https://github.com/tobi/qmd*
*Version/Commit: 63028fd (latest main)*

---

## Executive Summary

### Project Purpose

QMD (Quick Markdown Search) is an **on-device search engine** for markdown knowledge bases, notes, meeting transcripts, and documentation. It combines BM25 full-text search, vector semantic search, and LLM re-ranking — all running locally via node-llama-cpp with GGUF models.

### Key Innovation

QMD's standout innovations since last analysis:

1. **Custom fine-tuned query expansion model** (`qmd-query-expansion-1.7B`): A Qwen3-1.7B model trained with SFT + GRPO (reinforcement learning) specifically for structured search query expansion. Produces typed outputs (`lex:`, `vec:`, `hyde:`) that route to different search backends.

2. **Claude Code plugin ecosystem**: QMD ships as a Claude Code marketplace plugin (`.claude-plugin/marketplace.json`) with skills, MCP server integration, and inline status checks.

3. **Session-scoped LLM management** (`ILLMSession`): Structured lifecycle for LLM resources with abort signals, timeout management, and clean disposal.

### Technology Stack

- **Runtime**: Bun >= 1.0.0 (TypeScript)
- **Database**: SQLite with sqlite-vec extension (cosine distance)
- **Full-Text Search**: SQLite FTS5 with Porter tokenization
- **Embeddings**: EmbeddingGemma-300M (GGUF, ~300MB)
- **Reranking**: Qwen3-Reranker-0.6B (GGUF, ~640MB)
- **Query Expansion**: qmd-query-expansion-1.7B (custom fine-tuned, ~1.1GB)
- **MCP**: @modelcontextprotocol/sdk with stdio transport
- **Validation**: Zod v4 for MCP tool input schemas
- **Config**: YAML-based collection management (`~/.config/qmd/index.yml`)

### Production Readiness

- **Maturity**: Beta, actively developed, 5,700+ GitHub stars
- **Test Coverage**: Unit tests (store.test.ts, mcp.test.ts), eval harness (18 queries across 3 difficulty levels)
- **Documentation**: Comprehensive README, CLAUDE.md, inline code docs
- **Community**: 257 forks, 29 issues, 17 PRs, active maintainer (Tobi Lütke)
- **Plugin Distribution**: Available via Claude Code marketplace

---

## Architecture Overview

### Data Model

QMD uses content-addressable storage with a virtual filesystem layer:

```
content table (SHA256 hash → document body, deduplication)
    ↓
documents table (collection, path, title → hash, soft-delete via active flag)
    ↓
documents_fts (FTS5 full-text index, auto-synced via triggers)
    ↓
content_vectors (chunk metadata: hash, seq, pos, model)
    ↓
vectors_vec (sqlite-vec native KNN index, cosine distance)
    ↓
llm_cache (hash-keyed deterministic response cache)
```

### Key Design Patterns

1. **Content-Addressable Storage**: `content` table deduplicates by SHA256 hash — multiple documents with identical content share one row (`store.ts:440-450`)

2. **Two-Step Vector Query**: JOINs with sqlite-vec virtual tables hang indefinitely. QMD enforces separate queries for vec lookup and metadata join (`store.ts:1912-1915`):
   ```typescript
   // Step 1: KNN from vec table
   const vecResults = db.prepare(
     `SELECT hash_seq, distance FROM vectors_vec WHERE embedding MATCH ? AND k = ?`
   ).all(embedding, limit * 3);
   // Step 2: Join with documents separately
   ```

3. **YAML-Based Collection Config**: Collections migrated from SQLite foreign keys to `~/.config/qmd/index.yml` for easier user management. Schema migration in `migrate-schema.ts` handled the transition.

4. **Hierarchical Context System**: Context descriptions inherit along path hierarchy — a file at `/work/projects/api.md` gets global context + `/` context + `/work` context concatenated (`collections.ts:94-113`)

5. **Probabilistic Cache Cleanup**: 1% chance per query to prune LLM cache to latest 1000 entries (`store.ts:804-807`)

6. **Lazy Model Singleton**: LLM models lazy-load on first use, keep in memory, and unload contexts after 2-minute idle (`llm.ts:920-951`)

### Module Organization

```
qmd/
├── src/
│   ├── qmd.ts          # CLI entry point (~750 lines, lazy-loaded store)
│   ├── store.ts         # Core store: schema, search, indexing (~2400 lines)
│   ├── mcp.ts           # MCP server: 6 tools + resource + prompt (~626 lines)
│   ├── llm.ts           # LLM abstraction: embed, rerank, expand (~1208 lines)
│   ├── collections.ts   # YAML config management (~390 lines)
│   ├── store.test.ts    # Comprehensive store unit tests
│   └── mcp.test.ts      # MCP integration tests
├── finetune/            # Query expansion model training pipeline
│   ├── reward.py        # Multi-dimensional reward function (5 dimensions, 120 pts)
│   ├── train.py         # Unified SFT + GRPO training
│   ├── eval.py          # Model evaluation with scoring
│   └── jobs/            # HuggingFace Jobs wrappers
├── test/
│   └── eval-harness.ts  # Search quality evaluation (18 queries)
├── skills/qmd/          # Claude Code plugin skill definition
└── .claude-plugin/      # Marketplace distribution metadata
```

### Comparison with ClaudeMemory

| Aspect | QMD | ClaudeMemory | Notes |
|--------|-----|--------------|-------|
| **Data Model** | Full markdown documents | Structured fact triples | Different paradigms: recall vs extraction |
| **Storage** | SQLite + sqlite-vec (native vectors) | SQLite + JSON embeddings | QMD has 10-100x faster KNN |
| **Search** | BM25 + Vector + RRF + Reranking | BM25 + Vector (hybrid) | QMD adds reranking + query expansion |
| **MCP** | 6 tools + resource + prompt | 18 tools | ClaudeMemory has richer tool surface |
| **Distribution** | Bun global install + plugin | Ruby gem + MCP + hooks | QMD has smoother install via plugin |
| **LLM Dependency** | 3 local GGUF models (~2GB total) | None (local ONNX only) | ClaudeMemory is dramatically lighter |
| **Query Expansion** | Custom fine-tuned model (1.7B) | None | QMD has ML-powered query improvement |
| **Truth Maintenance** | None (all docs valid) | Supersession + conflicts | ClaudeMemory handles contradictions |
| **Scope System** | YAML collections | Dual-database (global/project) | Both approaches valid for their use case |
| **Testing** | Unit + eval harness | Unit + evals + benchmarks (DevMemBench) | ClaudeMemory has more comprehensive benchmarks |

---

## Key Components Deep-Dive

### Component 1: Fine-Tuned Query Expansion

**Purpose**: Generate structured query variations (lex/vec/hyde) to improve search recall by routing different query types to appropriate backends.

**Location**: `finetune/`, `src/llm.ts:637-679`

**Implementation** (from `finetune/README.md`):

The custom model `qmd-query-expansion-1.7B` is trained in two stages:

1. **SFT (Supervised Fine-Tuning)**: Teaches format compliance
   - Base model: Qwen3-1.7B
   - LoRA rank 16, alpha 32 (all projection layers)
   - ~2,290 training examples, 5 epochs
   - Loss: train 0.472, val 0.304

2. **GRPO (Group Relative Policy Optimization)**: Refines quality
   - LoRA rank 4, alpha 8 (q_proj, v_proj only)
   - KL beta 0.04 (prevents drift from SFT)
   - 200 steps, mean reward 0.757

**Reward Function** (from `finetune/reward.py`):
5 dimensions totaling 120 points (140 with hyde):
- Format (0-30): Valid lex/vec/hyde lines
- Diversity (0-30): Multiple types, no echoing query
- HyDE (0-20): Presence, length, quality
- Quality (0-20): Lex < vec length, preserved terms
- Entity (±45 to +20): Named entity preservation
- Think penalty: No `<think>` blocks (uses `/no_think` directive)

**Output Format**:
```
lex: authentication configuration
lex: auth settings setup
vec: how to configure authentication settings
hyde: Authentication can be configured by setting the AUTH_SECRET environment variable.
```

**Design Decisions**:
- Structured output types (`lex:`, `vec:`, `hyde:`) route to different backends instead of generic rewrites
- `/no_think` Qwen3 directive suppresses chain-of-thought for direct output
- Grammar-constrained generation ensures format compliance at inference time
- Per-query caching avoids redundant expansion (80% hit rate)

**Relevance to ClaudeMemory**: The structured lex/vec/hyde output pattern is interesting — if we ever add query expansion to our recall pipeline, this type-routed approach is more sophisticated than simple query rewriting. The reward function design (multi-dimensional scoring with entity preservation) is also a good reference for evaluating any future distiller quality.

---

### Component 2: Claude Code Plugin System

**Purpose**: Package QMD for frictionless installation via Claude Code marketplace.

**Location**: `.claude-plugin/marketplace.json`, `skills/qmd/SKILL.md`

**Plugin Structure** (from `marketplace.json:1-29`):
```json
{
  "name": "qmd",
  "plugins": [{
    "name": "qmd",
    "skills": ["./skills/"],
    "mcpServers": {
      "qmd": { "command": "qmd", "args": ["mcp"] }
    }
  }]
}
```

**Skill Definition** (from `skills/qmd/SKILL.md:1-10`):
```yaml
---
name: qmd
description: Search personal markdown knowledge bases...
metadata:
  author: tobi
  version: "1.1.1"
allowed-tools: Bash(qmd:*), mcp__qmd__*
---
```

Key features:
- **Inline status check**: `!` prefix runs command during skill load (`SKILL.md:18`)
- **Trigger phrases**: "search my notes", "find in docs", "what did I write about"
- **Tool permissions**: Scoped to `qmd:*` bash commands and `mcp__qmd__*` tools
- **Score interpretation guide**: Embedded in skill for LLM consumption
- **Recommended workflow**: status → search → vsearch → query → get

**Relevance to ClaudeMemory**: This is the clearest example of how to package a memory/search tool as a Claude Code plugin. The skill definition format, tool permissions scoping, inline status checks, and MCP server bundling are all patterns we should adopt when ready to ship as a plugin. The `allowed-tools` pattern (`Bash(qmd:*)`) is particularly useful for security scoping.

---

### Component 3: MCP Server with Structured Content

**Purpose**: Expose QMD search as MCP tools with both human-readable text and machine-parseable structured content.

**Location**: `src/mcp.ts`

**Implementation** (from `mcp.ts:258-292`):
```typescript
server.registerTool("search", {
  title: "Search (BM25)",
  inputSchema: {
    query: z.string().describe("Search query"),
    limit: z.number().optional().default(10),
    minScore: z.number().optional().default(0),
    collection: z.string().optional(),
  },
}, async ({ query, limit, minScore, collection }) => {
  // ... search logic ...
  return {
    content: [{ type: "text", text: formatSearchSummary(filtered, query) }],
    structuredContent: { results: filtered },
  };
});
```

**Key patterns**:
1. **Dual output**: Both `content` (human-readable text) and `structuredContent` (JSON) returned from every tool
2. **Zod validation**: Input schemas use Zod v4 with `.describe()` for auto-documentation
3. **Resource template**: Documents accessible via `qmd://{+path}` URI pattern with suffix matching fallback (`mcp.ts:105-166`)
4. **Query guide prompt**: Registered prompt explaining search strategy to LLMs (`mcp.ts:172-252`)
5. **Line numbers**: Default in resource output for precise references
6. **Error handling**: `isError: true` flag for clear error signaling, fuzzy file suggestions on not-found

**Relevance to ClaudeMemory**: We already have 18 MCP tools, but QMD's dual `content`/`structuredContent` pattern is worth adopting — it ensures both human (text summary) and machine (JSON) consumers get optimal formats. The registered prompt for query guidance is also a good pattern for improving Claude's tool usage.

---

### Component 4: Session-Scoped LLM Lifecycle

**Purpose**: Manage LLM model loading, context creation, and cleanup with structured lifecycle guarantees.

**Location**: `src/llm.ts:126-146`

**Session Interface** (from `llm.ts:137-146`):
```typescript
export interface ILLMSession {
  embed(text: string, options?: EmbedOptions): Promise<EmbeddingResult | null>;
  embedBatch(texts: string[]): Promise<(EmbeddingResult | null)[]>;
  expandQuery(query: string, options?): Promise<Queryable[]>;
  rerank(query: string, documents: RerankDocument[]): Promise<RerankResult>;
  readonly isValid: boolean;
  readonly signal: AbortSignal;
}
```

**Key patterns**:
- Sessions have `isValid` flag and `signal` (AbortSignal) for lifecycle tracking
- Maximum duration timeout prevents runaway sessions
- Models lazy-load but stay resident; contexts dispose after 2-min idle
- Singleton pattern ensures only one LLM instance (memory management)

**Relevance to ClaudeMemory**: If we ever integrate local LLMs for distillation, this session-scoped lifecycle pattern is the right approach. Clean abort propagation via AbortSignal is a good practice for any long-running operation.

---

## Comparative Analysis

### What QMD Does Well (New Findings)

#### 1. Custom Fine-Tuned Model Pipeline
- **Description**: Full training pipeline (SFT → GRPO → GGUF conversion) for search-specific model
- **Evidence**: `finetune/reward.py` — multi-dimensional reward function; `finetune/train.py` — unified training script
- **Why It Works**: Domain-specific models outperform general-purpose LLMs for structured tasks. The two-stage approach (format learning via SFT, quality refinement via GRPO) is state-of-the-art.
- **Metric**: Min 92% average score required before deployment

#### 2. Plugin Distribution
- **Description**: Ships as a Claude Code marketplace plugin with zero-config MCP + skills
- **Evidence**: `.claude-plugin/marketplace.json`, `skills/qmd/SKILL.md`
- **Why It Works**: `claude marketplace add tobi/qmd` is dramatically simpler than manual gem install + MCP config + hook setup
- **Impact**: Massive UX improvement for installation

#### 3. Typed Query Routing
- **Description**: Query expansion produces typed outputs (`lex:`, `vec:`, `hyde:`) routed to appropriate backends
- **Evidence**: `llm.ts:637-679` — structured prompt; `llm.ts:1006-1013` — grammar constraint
- **Why It Works**: Different search backends have different strengths. Routing keyword queries to BM25 and semantic queries to vector search maximizes recall.

#### 4. Dual Content/StructuredContent MCP Responses
- **Description**: Every MCP tool returns both human-readable text summary and machine-parseable JSON
- **Evidence**: `mcp.ts:288-291` — `return { content: [...], structuredContent: {...} }`
- **Why It Works**: LLMs can parse both formats, but text summaries are more token-efficient for simple consumption

### What We Do Well

#### 1. Fact-Based Knowledge Graph
- Our subject-predicate-object triples enable structured queries and inference
- Truth maintenance resolves contradictions automatically
- Far richer than document-level retrieval for knowledge extraction

#### 2. Dual-Database Architecture
- Clean global/project separation without YAML collections
- Simpler queries, clearer data ownership

#### 3. Comprehensive MCP Surface
- 18 tools vs QMD's 6 — we cover recall, explain, manage, monitor
- Progressive disclosure (recall_index → recall_details) for token efficiency

#### 4. Lightweight Dependencies
- ~5MB gem vs ~2GB+ with GGUF models
- fastembed-rb (67MB ONNX) vs EmbeddingGemma (300MB GGUF)
- No runtime LLM dependency

#### 5. Robust Benchmarking
- DevMemBench: 155 queries, Recall@k, MRR, nDCG@10
- 100 truth maintenance test cases
- 31 end-to-end scenarios with real Claude
- QMD has 18 eval queries — our evaluation is more comprehensive

### Trade-offs

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **QMD's LLM-powered search** | Better semantic recall, typed query routing | 2GB+ models, 2-3s cold start, complex deps | Large document collections, conceptual search |
| **Our FastEmbed search** | Lightweight (67MB), fast (<100ms), no LLM | Lower semantic quality for vague queries | Structured fact retrieval, quick lookups |
| **QMD's plugin distribution** | Zero-config install, marketplace discovery | Requires plugin ecosystem maturity | Wide user adoption |
| **Our gem + MCP + hooks** | Fine-grained control, works today | Complex setup, multiple config files | Power users, custom integrations |

---

## Adoption Opportunities

### High Priority ⭐

#### 1. Claude Code Plugin Distribution Format ⭐ NEW
- **Value**: 10x easier installation (single command vs multi-step gem + MCP + hook config)
- **Evidence**: `.claude-plugin/marketplace.json` — complete plugin spec; `skills/qmd/SKILL.md` — skill definition with tool scoping
- **Implementation**: Create `.claude-plugin/marketplace.json` with `mcpServers` pointing to `claude-memory serve-mcp`, skill definition from existing MCP tools, and `allowed-tools: mcp__claude-memory__*`
- **Effort**: 2-3 days (plugin metadata, skill definition, testing, documentation)
- **Trade-off**: Depends on Claude Code plugin ecosystem maturity; current hooks integration may still be needed
- **Recommendation**: **ADOPT** — QMD proves the format works. Start with plugin skeleton, iterate as ecosystem matures
- **Integration Points**: New `.claude-plugin/` directory, `skills/` directory, update installation docs

#### 2. MCP Structured Content Pattern ⭐ NEW
- **Value**: Better MCP response quality — dual human-readable + machine-parseable output
- **Evidence**: `mcp.ts:288-291` — `{ content: [{ type: "text", text: summary }], structuredContent: { results } }`
- **Implementation**: Update all 18 MCP tool handlers to return both `content` (text summary) and `structuredContent` (JSON). Text content would be a concise summary; structured content preserves full data.
- **Effort**: 1-2 days (update tool handlers, update tests)
- **Trade-off**: Slightly more code per tool handler; may need to verify Claude Code MCP client supports `structuredContent`
- **Recommendation**: **ADOPT** — Pure improvement, no downside if client supports it
- **Integration Points**: `lib/claude_memory/mcp/server.rb`, all tool handler methods

#### 3. MCP Registered Prompt for Query Guidance ⭐ NEW
- **Value**: Claude uses memory tools more effectively with embedded search strategy
- **Evidence**: `mcp.ts:172-252` — registered prompt explaining when to use recall vs recall_semantic vs search_concepts
- **Implementation**: Register a `memory_guide` prompt in our MCP server explaining tool selection strategy (recall for keywords, recall_semantic for concepts, search_concepts for multi-faceted queries, explain for provenance)
- **Effort**: 4-6 hours (write prompt, register in server, test)
- **Trade-off**: Minimal; prompt is only loaded on request
- **Recommendation**: **ADOPT** — Simple way to improve tool usage quality
- **Integration Points**: `lib/claude_memory/mcp/server.rb`

#### 4. Inline Status Check in Skills ⭐ NEW
- **Value**: Immediate feedback on memory system health when skill loads
- **Evidence**: `SKILL.md:18` — `!` prefix runs `qmd status 2>/dev/null || echo "Not installed"`
- **Implementation**: Add inline check to our skill definition: `!claude-memory doctor --brief 2>/dev/null || echo "Not configured. Run: gem install claude_memory"`
- **Effort**: 1-2 hours
- **Trade-off**: None
- **Recommendation**: **ADOPT** — Trivial improvement with clear benefit
- **Integration Points**: Skill definition file

### Previously Identified (Carried Forward)

These items from the 2026-01-26 analysis remain relevant:

#### 5. ⭐ Native Vector Storage (sqlite-vec) — STILL CRITICAL
- **Value**: 10-100x faster KNN queries
- **Status**: Not yet implemented in ClaudeMemory
- **Updated Evidence**: QMD now handles 10,000+ documents in production (5,700+ star project)
- **Recommendation**: **ADOPT IMMEDIATELY** — Foundational improvement

#### 6. ⭐ Reciprocal Rank Fusion (RRF) Algorithm — STILL HIGH VALUE
- **Value**: 50% improvement in Hit@3 for medium-difficulty queries
- **Status**: Not yet implemented in ClaudeMemory
- **Recommendation**: **ADOPT IMMEDIATELY** — Pure algorithmic improvement

#### 7. ⭐ Docid Short Hash System — STILL MEDIUM VALUE
- **Value**: Better UX, cross-database fact references
- **Status**: Not yet implemented
- **Recommendation**: **ADOPT IN PHASE 2**

#### 8. ⭐ Smart Expansion Detection — STILL MEDIUM VALUE
- **Value**: Skip unnecessary vector search when FTS has strong signal
- **Status**: Not yet implemented
- **Recommendation**: **ADOPT IN PHASE 3**

### Medium Priority

#### 9. Skill Definition with Tool Scoping
- **Value**: Security and UX — limit tool access to memory-related commands
- **Evidence**: `SKILL.md:9` — `allowed-tools: Bash(qmd:*), mcp__qmd__*`
- **Implementation**: Define skill with `allowed-tools: Bash(claude-memory:*), mcp__claude-memory__*`
- **Effort**: Included in plugin distribution work
- **Recommendation**: **CONSIDER** — Good practice for plugin security
- **Integration Points**: Skills directory

#### 10. Evaluation Harness Improvements
- **Value**: QMD's eval structure with difficulty levels and Hit@K metrics is cleaner
- **Evidence**: `test/eval-harness.ts:11-16` — typed queries with difficulty + description
- **Implementation**: Already have DevMemBench (more comprehensive). Could adopt difficulty classification.
- **Recommendation**: **CONSIDER** — Our evals are already better; could add difficulty labels

### Low Priority

#### 11. YAML-Based Collection Configuration
- **Value**: User-editable config for what gets indexed
- **Evidence**: `collections.ts`, `example-index.yml`
- **Recommendation**: **REJECT** — Our dual-database provides cleaner separation

#### 12. Custom Query Expansion Model
- **Value**: Better search recall via ML-powered query rewriting
- **Evidence**: `finetune/` — complete training pipeline
- **Recommendation**: **REJECT** — Too heavy (1.7B model) for our fact retrieval use case. If we need expansion, we can leverage Claude's own capabilities during recall.

#### 13. LLM-Based Reranking
- **Value**: Better ranking precision
- **Recommendation**: **REJECT** — Over-engineering for structured fact retrieval

### Features to Avoid

#### 1. Heavy Local LLM Dependencies
- **What It Is**: Three GGUF models totaling ~2GB for search operations
- **Why Avoid**: ClaudeMemory targets lightweight, instant search. 2-3s cold start and 3GB memory is inappropriate for a fact lookup tool.
- **Our Alternative**: FastEmbed (67MB ONNX, <100ms) provides adequate semantic search for structured facts.

#### 2. Content-Addressable Document Storage
- **What It Is**: SHA256 hash-based deduplication of full documents
- **Why Avoid**: We store facts, not documents. Our deduplication is by fact signature.
- **Our Alternative**: Existing fact signature-based deduplication.

---

## Implementation Recommendations

### Phase 1: Plugin Foundation (NEW)

**Goals**: Establish ClaudeMemory as a Claude Code plugin with improved MCP output

**Tasks**:
- [ ] Create `.claude-plugin/marketplace.json` with plugin metadata
- [ ] Create skill definition with tool scoping and inline health check
- [ ] Add MCP structured content pattern to all 18 tool handlers
- [ ] Register query guidance prompt in MCP server
- [ ] Test plugin installation workflow
- [ ] Update installation docs

**Success Criteria**:
- ClaudeMemory installable via `claude plugin add`
- MCP tools return both text summaries and structured JSON
- Query guide prompt available via MCP

**Risks**: Plugin ecosystem may change; maintain backward compatibility with manual setup

---

### Phase 2: Vector Storage Upgrade (CARRIED FORWARD)

**Goals**: Adopt sqlite-vec for native KNN and RRF fusion for search quality

**Tasks**:
- [ ] Add sqlite-vec extension support
- [ ] Schema migration for `facts_vec` virtual table (two-step query pattern)
- [ ] Implement `Recall::RRFusion` class
- [ ] Backfill existing embeddings
- [ ] Benchmark: target 10x KNN improvement

**Success Criteria**:
- Vector search uses native sqlite-vec
- RRF fusion active for hybrid queries
- DevMemBench shows improved retrieval metrics

---

### Phase 3: UX Polish (CARRIED FORWARD)

**Goals**: Docid hashes and smart expansion detection

**Tasks**:
- [ ] Schema migration for `docid` column (8-char hash)
- [ ] Implement `Recall::ExpansionDetector`
- [ ] Update CLI and MCP tools for docid support

---

## Architecture Decisions

### What to Preserve

- **Fact-Based Knowledge Graph**: Our structured triples are fundamentally different from (and better suited for knowledge extraction than) QMD's document storage
- **Truth Maintenance**: Supersession + conflict resolution is a core differentiator
- **Dual-Database Architecture**: Cleaner than YAML collections for our use case
- **Lightweight Dependencies**: Ruby gem + ONNX embeddings vs 2GB+ GGUF models

### What to Adopt (NEW)

- **Plugin Distribution Format**: `.claude-plugin/marketplace.json` + skills for frictionless installation
- **Structured MCP Content**: Dual `content`/`structuredContent` responses for all tools
- **MCP Query Guide Prompt**: Registered prompt teaching Claude how to use memory tools effectively
- **Inline Status Checks**: Skill-level health verification on load

### What to Adopt (CARRIED FORWARD)

- **sqlite-vec Native Vectors**: 10-100x faster KNN (critical)
- **RRF Fusion**: 50% search quality improvement (critical)
- **Docid Short Hashes**: Better UX for fact references
- **Smart Expansion Detection**: Skip vector search when FTS is confident

### What to Reject

- **Local LLM Models for Search**: Too heavy (2GB+, 3s cold start)
- **Custom Fine-Tuned Models**: Training pipeline is impressive but overkill for fact retrieval
- **YAML Collection System**: Our dual-DB is better for our use case
- **Content-Addressable Storage**: Different data model
- **Virtual Path System**: Unnecessary for fact-based storage

---

## Key Takeaways

### Main Learnings

1. **Plugin distribution is the future**: QMD's marketplace plugin reduces installation from "read docs, install gem, configure MCP, set up hooks, restart Claude" to one command. This is the single most impactful UX improvement we should adopt.

2. **Structured MCP responses matter**: Returning both text summary and structured JSON is a simple pattern that significantly improves how Claude consumes tool output.

3. **Fine-tuned models for specific tasks work**: QMD's two-stage SFT→GRPO pipeline for query expansion is state-of-the-art. While we shouldn't adopt the models themselves (too heavy), the reward function design and structured output routing are good reference patterns.

4. **Eval methodology with difficulty levels**: QMD's easy/medium/hard query classification provides clearer signal about where improvements matter. Our DevMemBench is more comprehensive but could benefit from this labeling.

5. **The previous QMD analysis recommendations remain valid**: sqlite-vec, RRF, docids, and smart expansion are still unimplemented and still valuable.

### Recommended Adoption Order

1. **First**: Plugin distribution format — highest UX impact, unblocks ecosystem adoption
2. **Second**: MCP structured content + query guide prompt — low effort, immediate quality gain
3. **Third**: sqlite-vec + RRF fusion — foundational performance and quality
4. **Fourth**: Docids + smart expansion — polish and optimization

### Expected Impact

- **Installation**: 10x easier (single command vs multi-step)
- **MCP Quality**: Better Claude tool usage with structured responses + query guidance
- **Search Performance**: 10-100x faster KNN (sqlite-vec), 50% better Hit@3 (RRF)
- **UX**: Human-friendly fact references (#abc123de), smarter search skipping

### Next Actions

- [ ] Review plugin distribution feasibility (check Claude Code plugin spec)
- [ ] Implement MCP structured content pattern (quick win)
- [ ] Register query guide MCP prompt (quick win)
- [ ] Continue with sqlite-vec + RRF adoption plan from previous analysis
- [ ] Store analysis findings in memory

---

## References

- **Repository**: https://github.com/tobi/qmd
- **Previous Analysis**: docs/influence/qmd.md (2026-01-26)
- **Claude Code Plugins**: https://code.claude.com/docs/en/plugins.md
- **MCP Spec**: https://modelcontextprotocol.io
- **sqlite-vec**: https://github.com/asg017/sqlite-vec
- **RRF Paper**: Cormack et al., "Reciprocal Rank Fusion outperforms Condorcet and individual Rank Learning Methods" (2009)

---

*Analysis completed: 2026-02-02*
*Analyst: Claude Code*
*Review Status: Draft — Updated from 2026-01-26 analysis with new findings on plugin distribution, fine-tuned models, and MCP patterns*
