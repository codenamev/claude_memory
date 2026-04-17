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
    # Dispatcher that routes MCP tool calls to handler modules.
    # Each handler module (QueryHandlers, ShortcutHandlers, etc.) provides
    # the implementation for a group of related tools.
    class Tools
      include ToolHelpers
      include Handlers::QueryHandlers
      include Handlers::ShortcutHandlers
      include Handlers::ContextHandlers
      include Handlers::ManagementHandlers
      include Handlers::StatsHandlers
      include Handlers::SetupHandlers

      # @param store_or_manager [Store::SQLiteStore, Store::StoreManager] database backend
      def initialize(store_or_manager)
        @recall = Recall.new(store_or_manager)

        if store_or_manager.is_a?(Store::StoreManager)
          @manager = store_or_manager
        else
          @legacy_store = store_or_manager
        end
      end

      # @return [Array<Hash>] MCP tool definition hashes for tools/list
      def definitions
        ToolDefinitions.all
      end

      # Tools that represent recall/query usage - tracked for efficacy
      RECALL_TOOLS = %w[
        memory.recall memory.recall_index memory.recall_semantic
        memory.search_concepts memory.decisions memory.conventions memory.architecture
      ].freeze

      # Write tools worth tracking
      WRITE_TOOLS = %w[memory.store_extraction].freeze

      TRACKED_TOOLS = (RECALL_TOOLS + WRITE_TOOLS).freeze

      # Dispatch a tool call to the appropriate handler method.
      # @param name [String] fully-qualified tool name (e.g. "memory.recall")
      # @param arguments [Hash] tool arguments from the MCP request
      # @return [Hash] structured result hash for the tool response
      def call(name, arguments)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        result = dispatch(name, arguments)

        log_tool_activity(name, arguments, result, t0) if TRACKED_TOOLS.include?(name)

        result
      end

      private

      def dispatch(name, arguments)
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
        when "memory.activity" then activity(arguments)
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

      def log_tool_activity(name, arguments, result, t0)
        store = default_store
        return unless store

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        event_type = WRITE_TOOLS.include?(name) ? "store_extraction" : "recall"
        status = result[:error] ? "error" : "success"

        details = {tool: name}
        if event_type == "recall"
          details[:query] = arguments["query"] || arguments["concepts"]&.join(", ")
          details[:result_count] = result[:fact_count] || result[:count] || 0
        else
          details[:facts_created] = result[:facts_created]
          details[:entities_created] = result[:entities_created]
          details[:content_item_id] = result[:content_item_id]
        end

        ActivityLog.record(store, event_type: event_type, status: status,
          duration_ms: duration_ms, details: details.compact)
      end

      def default_store
        if @manager
          if @manager.project_exists?
            @manager.ensure_project!
            @manager.project_store
          end
        else
          @legacy_store
        end
      end

      def activity(args)
        store = default_store
        return {error: "No database available"} unless store

        limit = args["limit"] || 50
        event_type = args["event_type"]
        since = args["since"]

        events = ActivityLog.recent(store, limit: limit, event_type: event_type, since: since)
        summary = ActivityLog.summary(store, since: since)

        {
          event_count: events.size,
          summary: summary,
          events: events.map { |e|
            e[:occurred_ago] = Core::RelativeTime.format(e[:occurred_at])
            e
          }
        }
      end
    end
  end
end
