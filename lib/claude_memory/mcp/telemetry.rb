# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Records MCP tool invocations into the project database for usage stats.
    # Timing and error capture wrap the tool call; the insert is synchronous
    # and best-effort — telemetry failures are swallowed so they never break
    # a real tool response.
    class Telemetry
      def initialize(store_or_manager)
        @store_or_manager = store_or_manager
      end

      # Time a tool invocation and record the outcome. Yields to the caller
      # and returns whatever the block returns; re-raises any exception after
      # recording it as an error.
      def record(tool_name, arguments)
        started = monotonic_ms
        begin
          result = yield
        rescue => e
          duration = monotonic_ms - started
          write(
            tool_name: tool_name,
            duration_ms: duration,
            result_count: nil,
            scope: extract_scope(arguments),
            error_class: e.class.name
          )
          raise
        end

        duration = monotonic_ms - started
        write(
          tool_name: tool_name,
          duration_ms: duration,
          result_count: extract_result_count(result),
          scope: extract_scope(arguments),
          error_class: nil
        )
        result
      end

      private

      def monotonic_ms
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      end

      def write(**row)
        store = writable_store
        return unless store
        store.insert_mcp_tool_call(**row)
      rescue Sequel::DatabaseError, Extralite::Error
        # Telemetry is best-effort; never fail the user's tool call
        # because stats couldn't be written.
      end

      def writable_store
        if @store_or_manager.is_a?(Store::StoreManager)
          @store_or_manager.ensure_project!
        elsif @store_or_manager.respond_to?(:insert_mcp_tool_call)
          @store_or_manager
        end
      end

      def extract_scope(arguments)
        return nil unless arguments.is_a?(Hash)
        arguments["scope"] || arguments[:scope]
      end

      # Inspect a tool result for a countable field. Most query tools
      # return hashes with :facts, :results, :conflicts, or :changes;
      # fall back to nil for shapes we don't recognize.
      def extract_result_count(result)
        return nil unless result.is_a?(Hash)

        %i[facts results conflicts changes entities items].each do |key|
          value = result[key] || result[key.to_s]
          return value.size if value.is_a?(Array)
        end
        nil
      end
    end
  end
end
