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
        when "memory.observations" then observations(arguments)
        when "memory.promote_observation" then promote_observation(arguments)
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
        session_id = extract_session_id(arguments)

        details = {tool: name}
        if event_type == "recall"
          details[:query] = arguments["query"] || arguments["concepts"]&.join(", ")
          details[:scope] = arguments["scope"]
          details[:result_count] = extract_result_count(result)
          # top_fact_ids is a flat list of the first 5 IDs; top_facts_by_scope
          # groups the same IDs by source so dashboard readers can resolve
          # each ID from the DB it actually came from. Fact IDs autoincrement
          # per-DB, so a bare ID without scope is ambiguous.
          scoped = extract_top_facts_scoped(result)
          details[:top_fact_ids] = scoped.values.flatten.first(5)
          details[:top_facts_by_scope] = scoped if scoped.any?
          details[:results_by_scope] = extract_scope_breakdown(result)
        else
          details[:facts_created] = result[:facts_created]
          details[:entities_created] = result[:entities_created]
          details[:content_item_id] = result[:content_item_id]
        end

        ActivityLog.record(store, event_type: event_type, status: status,
          session_id: session_id, duration_ms: duration_ms, details: details.compact)
      end

      # Probe a recall result for a count of returned items. Falls back to
      # counting the first array-valued key among the shapes emitted by the
      # various recall handlers (facts, results, items, concepts).
      def extract_result_count(result)
        return 0 unless result.is_a?(Hash)
        [:fact_count, :count, :results_count].each do |key|
          val = result[key]
          return val if val.is_a?(Integer)
        end
        [:facts, :results, :items, :concepts, :conflicts].each do |key|
          val = result[key]
          return val.size if val.is_a?(Array)
        end
        0
      end

      # Capture up to 5 fact ids from a recall result, grouped by source scope.
      # Fact IDs autoincrement per-DB, so without scope a bare ID is ambiguous
      # (project fact #1 and global fact #1 are different facts). Recall rows
      # carry either a :source or :scope field identifying which DB the fact
      # came from; we use that to group.
      #
      # @return [Hash{String => Array<Integer>}] e.g. {"project" => [5, 8], "global" => [1]}
      def extract_top_facts_scoped(result, limit: 5)
        return {} unless result.is_a?(Hash)
        collection = [:facts, :results, :items].map { |k| result[k] }.find { |v| v.is_a?(Array) }
        return {} unless collection

        grouped = Hash.new { |h, k| h[k] = [] }
        collection.first(limit).each do |row|
          next unless row.is_a?(Hash)
          fact = row[:fact] || row["fact"] || row
          id = fact.is_a?(Hash) ? (fact[:id] || fact["id"]) : nil
          next unless id
          scope = row[:source] || row["source"] || fact[:scope] || fact["scope"] || "project"
          grouped[scope.to_s] << id
        end
        grouped
      end

      def extract_session_id(arguments)
        (arguments.is_a?(Hash) && arguments["session_id"]) || Configuration.new.session_id
      end

      # Count returned items grouped by their :scope field so the dashboard
      # can show whether a recall's hits came from global preferences, project
      # facts, or both. Returns nil when the result shape doesn't carry facts.
      # @return [Hash{String => Integer}, nil]
      def extract_scope_breakdown(result)
        return nil unless result.is_a?(Hash)
        collection = [:facts, :results, :items].map { |k| result[k] }.find { |v| v.is_a?(Array) }
        return nil unless collection

        breakdown = Hash.new(0)
        collection.each { |row|
          next unless row.is_a?(Hash)
          scope = row[:scope] || row["scope"] || row[:source] || row["source"] || "unknown"
          breakdown[scope.to_s] += 1
        }
        breakdown.empty? ? nil : breakdown
      end

      # Return whichever store is available for activity logging. Delegates
      # to StoreManager#default_store which prefers the project store and
      # falls back to global — preventing silent drops of activity events
      # when the project DB hasn't been initialized yet.
      def default_store
        return @legacy_store unless @manager
        @manager.default_store(prefer: :project)
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
