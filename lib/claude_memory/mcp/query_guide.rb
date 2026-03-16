# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # MCP prompt that teaches Claude when to use each memory tool.
    # Registered as "memory_guide" via prompts/list.
    module QueryGuide
      PROMPT_NAME = "memory_guide"
      PROMPT_DESCRIPTION = "Guide for choosing the right memory search tool"

      PROMPT_TEXT = <<~GUIDE
        # ClaudeMemory Search Strategy Guide

        ## Tool Escalation — Cheap to Expensive

        Start with fast, cheap tools. Escalate only when you need more detail.

        ### Tier 1: Fast Lookup (< 50ms, low tokens)

        **memory.recall** — Full-text keyword search
        - Use for: exact terms, known predicates, specific entity names
        - Example: "PostgreSQL", "authentication", "deployment"
        - Returns: facts with provenance receipts
        - Cost: ~200-500 tokens per call

        **memory.decisions** / **memory.conventions** / **memory.architecture**
        - Use for: quick access to known categories
        - Cost: ~100-300 tokens per call

        ### Tier 2: Broad Search (< 200ms, moderate tokens)

        **memory.recall_semantic** — Vector similarity search
        - Use for: conceptual queries, paraphrased questions, "find things like X"
        - Modes: `vector` (embeddings only), `text` (FTS only), `both` (hybrid, recommended)
        - Example: "how does the app handle user sessions"
        - Returns: facts ranked by similarity score (0.0-1.0)
        - Cost: ~300-800 tokens per call

        **memory.search_concepts** — Multi-concept AND query
        - Use for: intersection of 2-5 concepts that must ALL be present
        - Example: concepts=["authentication", "JWT", "middleware"]
        - Cost: ~300-800 tokens per call

        **memory.recall_index** — Lightweight previews
        - Use for: browsing large result sets before committing to full details
        - Cost: ~100-200 tokens (compact previews)

        ### Tier 3: Targeted Deep Dive (moderate tokens)

        **memory.recall_details** — Full details for selected fact IDs
        - Use after: `recall_index` to fetch only the facts you need
        - Cost: ~200-600 tokens per call

        **memory.explain** — Detailed provenance for a specific fact
        - Use when: you need to know where a fact came from and how confident it is
        - Cost: ~300-500 tokens per call

        ### Tier 4: Relationship Exploration (higher tokens)

        **memory.fact_graph** — Dependency graph visualization
        - Use when: you need to understand how facts relate (supersession chains, conflicts)
        - Cost: ~400-1000 tokens per call

        **memory.facts_by_tool** — Facts discovered via specific tool (Read, Edit, Bash)
        **memory.facts_by_context** — Facts from specific git branch or directory
        - Use when: you need facts from a specific workflow context
        - Cost: ~300-800 tokens per call

        ## Recommended Workflow

        1. **Start broad**: `memory.recall` or shortcut tools (decisions/conventions/architecture)
        2. **Refine if needed**: `memory.recall_semantic` for fuzzy matches
        3. **Drill into specifics**: `memory.recall_details` or `memory.explain` for selected facts
        4. **Explore relationships**: `memory.fact_graph` only when you need lineage/conflicts

        Do NOT jump to Tier 3-4 tools first. Tier 1 tools answer most questions.

        ## Score Interpretation (semantic search)

        - **> 0.85**: Strong match, high confidence
        - **0.70-0.85**: Good match, likely relevant
        - **0.55-0.70**: Moderate match, may be tangentially related
        - **< 0.55**: Weak match, probably not relevant

        ## Scope Parameter

        All query tools accept `scope`: `"all"` (default), `"global"`, or `"project"`.
        - `global`: User-wide preferences and conventions
        - `project`: Current project facts only
        - `all`: Both (project facts take precedence)
      GUIDE

      def self.definition
        {
          name: PROMPT_NAME,
          description: PROMPT_DESCRIPTION
        }
      end

      def self.content
        {
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: PROMPT_TEXT
              }
            }
          ]
        }
      end
    end
  end
end
