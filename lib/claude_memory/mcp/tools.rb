# frozen_string_literal: true

require "json"
require "digest"
require_relative "tool_helpers"
require_relative "response_formatter"
require_relative "tool_definitions"
require_relative "setup_status_analyzer"
require_relative "error_classifier"
require_relative "handlers/query_handlers"
require_relative "handlers/shortcut_handlers"
require_relative "handlers/context_handlers"
require_relative "handlers/management_handlers"
require_relative "handlers/stats_handlers"
require_relative "handlers/setup_handlers"

module ClaudeMemory
  module MCP
    class Tools
      include ToolHelpers
      include Handlers::QueryHandlers
      include Handlers::ShortcutHandlers
      include Handlers::ContextHandlers
      include Handlers::ManagementHandlers
      include Handlers::StatsHandlers
      include Handlers::SetupHandlers

      def initialize(store_or_manager)
        @recall = Recall.new(store_or_manager)

        if store_or_manager.is_a?(Store::StoreManager)
          @manager = store_or_manager
        else
          @legacy_store = store_or_manager
        end
      end

      def definitions
        ToolDefinitions.all
      end

      def call(name, arguments)
        case name
        when "memory.recall" then recall(arguments)
        when "memory.recall_index" then recall_index(arguments)
        when "memory.recall_details" then recall_details(arguments)
        when "memory.explain" then explain(arguments)
        when "memory.changes" then changes(arguments)
        when "memory.conflicts" then conflicts(arguments)
        when "memory.sweep_now" then sweep_now(arguments)
        when "memory.status" then status
        when "memory.stats" then stats(arguments)
        when "memory.promote" then promote(arguments)
        when "memory.reject_fact" then reject_fact(arguments)
        when "memory.store_extraction" then store_extraction(arguments)
        when "memory.decisions" then decisions(arguments)
        when "memory.conventions" then conventions(arguments)
        when "memory.architecture" then architecture(arguments)
        when "memory.facts_by_tool" then facts_by_tool(arguments)
        when "memory.facts_by_context" then facts_by_context(arguments)
        when "memory.recall_semantic" then recall_semantic(arguments)
        when "memory.search_concepts" then search_concepts(arguments)
        when "memory.fact_graph" then fact_graph(arguments)
        when "memory.undistilled" then undistilled(arguments)
        when "memory.mark_distilled" then mark_distilled(arguments)
        when "memory.check_setup" then check_setup
        when "memory.list_projects" then list_projects
        else {error: "Unknown tool: #{name}"}
        end
      end

      private

      def databases_exist?
        if @manager
          config = Configuration.new
          File.exist?(config.global_db_path) || File.exist?(config.project_db_path)
        elsif @legacy_store
          db_path = @legacy_store.db.opts[:database]
          db_path && File.exist?(db_path)
        else
          false
        end
      end

      def database_not_found_error(error = nil)
        if error
          ErrorClassifier.build_error_response(error, tool_name: "recall")
        else
          ErrorClassifier.build_benign_response(:not_initialized, tool_name: "recall")
        end
      end

      def classified_error(error, tool_name: nil)
        ErrorClassifier.build_error_response(error, tool_name: tool_name)
      end

      def get_store_for_scope(scope)
        if @manager
          @manager.store_for_scope(scope)
        else
          @legacy_store
        end
      end
    end
  end
end
