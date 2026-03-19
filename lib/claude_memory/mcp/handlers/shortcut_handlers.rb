# frozen_string_literal: true

module ClaudeMemory
  module MCP
    module Handlers
      # Shortcut tool handlers (decisions, conventions, architecture)
      module ShortcutHandlers
        def decisions(args)
          return {error: "Decisions shortcut requires StoreManager"} unless @manager

          results = Recall.recent_decisions(@manager, limit: args["limit"] || 10)
          format_shortcut_results(results, "decisions")
        end

        def conventions(args)
          return {error: "Conventions shortcut requires StoreManager"} unless @manager

          results = Recall.conventions(@manager, limit: args["limit"] || 20)
          format_shortcut_results(results, "conventions")
        end

        def architecture(args)
          return {error: "Architecture shortcut requires StoreManager"} unless @manager

          results = Recall.architecture_choices(@manager, limit: args["limit"] || 10)
          format_shortcut_results(results, "architecture")
        end

        private

        def format_shortcut_results(results, category)
          ResponseFormatter.format_shortcut_results(category, results)
        end
      end
    end
  end
end
