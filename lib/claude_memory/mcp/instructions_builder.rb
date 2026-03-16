# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Generates dynamic MCP server instructions from database state.
    # Injected into the LLM system prompt via the initialize response,
    # giving Claude immediate context about memory state without extra tool calls.
    #
    # Source: QMD mcp.ts:91-152 (buildInstructions pattern)
    module InstructionsBuilder
      DECISION_PREDICATES = %w[decided decision chose selected adopted rejected].freeze
      CONVENTION_PREDICATES = %w[convention style_rule prefers uses_style coding_standard].freeze

      module_function

      def build(store_or_manager)
        parts = ["ClaudeMemory v#{ClaudeMemory::VERSION} — long-term memory for Claude Code."]

        if store_or_manager.is_a?(Store::StoreManager)
          parts << database_summary(store_or_manager)
          parts << knowledge_summary(store_or_manager)
          parts << conflict_summary(store_or_manager)
        elsif store_or_manager.respond_to?(:facts)
          parts << single_db_summary(store_or_manager)
        end

        parts << usage_hint(store_or_manager)
        parts.compact.join("\n\n")
      rescue => _e
        # Never fail initialization — return minimal instructions
        "ClaudeMemory v#{ClaudeMemory::VERSION} — long-term memory for Claude Code."
      end

      def database_summary(manager)
        lines = []

        if manager.global_exists?
          manager.ensure_global!
          global = manager.global_store
          g_facts = global.facts.where(status: "active").count
          lines << "Global: #{g_facts} active facts"
        end

        if manager.project_exists?
          manager.ensure_project!
          project = manager.project_store
          p_facts = project.facts.where(status: "active").count
          lines << "Project: #{p_facts} active facts"
        end

        return nil if lines.empty?
        "Database state: #{lines.join(", ")}."
      end

      def knowledge_summary(manager)
        decisions = 0
        conventions = 0
        entities = 0

        [manager.global_exists? && manager.global_store,
          manager.project_exists? && manager.project_store].each do |store|
          next unless store

          decisions += count_by_predicates(store, DECISION_PREDICATES)
          conventions += count_by_predicates(store, CONVENTION_PREDICATES)
          entities += store.entities.count
        end

        return nil if decisions == 0 && conventions == 0 && entities == 0

        parts = []
        parts << "#{decisions} decision#{"s" unless decisions == 1}" if decisions > 0
        parts << "#{conventions} convention#{"s" unless conventions == 1}" if conventions > 0
        parts << "#{entities} #{(entities == 1) ? "entity" : "entities"}" if entities > 0
        "Knowledge: #{parts.join(", ")}."
      end

      def single_db_summary(store)
        facts = store.facts.where(status: "active").count
        "Database state: #{facts} active facts."
      end

      def conflict_summary(manager)
        count = 0

        if manager.global_exists?
          count += manager.global_store.conflicts.where(status: "open").count
        end

        if manager.project_exists?
          count += manager.project_store.conflicts.where(status: "open").count
        end

        return nil if count == 0
        "#{count} open conflict#{"s" unless count == 1} — use memory.conflicts to review."
      end

      def usage_hint(store_or_manager)
        lines = [
          "Use memory.recall to search facts, memory.decisions for architectural decisions, memory.conventions for coding style."
        ]

        vec = vec_available?(store_or_manager)
        if vec
          lines << "Semantic search available — use memory.recall_semantic for natural language queries, memory.search_concepts for multi-concept intersection."
        end

        escalation = vec ? "recall_semantic, explain, or fact_graph" : "explain or fact_graph"
        lines << "Start with fast tools (recall, decisions, conventions) before escalating to #{escalation}."
        lines.join("\n")
      end

      def count_by_predicates(store, predicates)
        store.facts
          .where(status: "active")
          .where(predicate: predicates)
          .count
      end

      def vec_available?(store_or_manager)
        if store_or_manager.is_a?(Store::StoreManager)
          [store_or_manager.global_exists? && store_or_manager.global_store,
            store_or_manager.project_exists? && store_or_manager.project_store].any? do |store|
            store&.vector_index&.available?
          end
        elsif store_or_manager.respond_to?(:vector_index)
          store_or_manager.vector_index.available?
        end
      rescue
        false
      end
    end
  end
end
