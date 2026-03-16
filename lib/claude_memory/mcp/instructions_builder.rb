# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Generates dynamic MCP server instructions from database state.
    # Injected into the LLM system prompt via the initialize response,
    # giving Claude immediate context about memory state without extra tool calls.
    #
    # Source: QMD mcp.ts:91-98 (buildInstructions pattern)
    module InstructionsBuilder
      module_function

      def build(store_or_manager)
        parts = ["ClaudeMemory v#{ClaudeMemory::VERSION} — long-term memory for Claude Code."]

        if store_or_manager.is_a?(Store::StoreManager)
          parts << database_summary(store_or_manager)
          parts << conflict_summary(store_or_manager)
        elsif store_or_manager.respond_to?(:facts)
          parts << single_db_summary(store_or_manager)
        end

        parts << usage_hint
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

      def usage_hint
        "Use memory.recall to search facts, memory.decisions for architectural decisions, memory.conventions for coding style.\n" \
          "Start with fast tools (recall, decisions, conventions) before escalating to recall_semantic, explain, or fact_graph."
      end
    end
  end
end
