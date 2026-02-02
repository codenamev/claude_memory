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

        ## Tool Selection

        **memory.recall** — Full-text keyword search (fastest)
        - Use for: exact terms, known predicates, specific entity names
        - Example: "PostgreSQL", "authentication", "deployment"
        - Returns: facts with provenance receipts

        **memory.recall_semantic** — Vector similarity search
        - Use for: conceptual queries, paraphrased questions, "find things like X"
        - Modes: `vector` (embeddings only), `text` (FTS only), `both` (hybrid, recommended)
        - Example: "how does the app handle user sessions" (no exact keyword match needed)
        - Returns: facts ranked by similarity score (0.0-1.0)

        **memory.search_concepts** — Multi-concept AND query
        - Use for: intersection of 2-5 concepts that must ALL be present
        - Example: concepts=["authentication", "JWT", "middleware"]
        - Returns: facts matching all concepts, ranked by average similarity

        **memory.recall_index** → **memory.recall_details** — Progressive disclosure
        - Use for: browsing large result sets efficiently
        - Step 1: `recall_index` returns lightweight previews with token estimates
        - Step 2: `recall_details` fetches full data for selected fact IDs
        - Saves tokens when you only need a few facts from many matches

        ## Shortcut Tools

        **memory.decisions** — Architectural decisions and constraints
        **memory.conventions** — Coding style preferences and rules
        **memory.architecture** — Framework choices and patterns

        ## Context-Aware Tools

        **memory.facts_by_tool** — Facts discovered via specific tool (Read, Edit, Bash)
        **memory.facts_by_context** — Facts from specific git branch or directory

        ## Decision Tree

        1. Know the exact keyword? → `memory.recall`
        2. Conceptual/fuzzy question? → `memory.recall_semantic` (mode: both)
        3. Need intersection of topics? → `memory.search_concepts`
        4. Looking for decisions? → `memory.decisions`
        5. Looking for conventions? → `memory.conventions`
        6. Many results expected? → `memory.recall_index` then `memory.recall_details`
        7. Need provenance? → `memory.explain` with fact ID

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
