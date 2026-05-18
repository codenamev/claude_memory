# frozen_string_literal: true

module ClaudeMemory
  module OTel
    # Single source of truth for "what does telemetry look like right now?"
    # Used by both the `claude-memory otel --status` CLI and the dashboard's
    # Telemetry header. Pure read query — no writes.
    class Status
      def initialize(store, configuration: nil, settings_writer: nil)
        @store = store
        @configuration = configuration || ClaudeMemory::Configuration.new
        @settings_writer = settings_writer
      end

      # @return [Hash]
      def snapshot
        {
          metric_count: count_safely(:otel_metrics),
          event_count: count_safely(:otel_events),
          trace_count: count_safely(:otel_traces),
          last_metric_at: last_timestamp(:otel_metrics, :recorded_at),
          last_event_at: last_timestamp(:otel_events, :occurred_at),
          last_trace_at: last_timestamp(:otel_traces, :recorded_at),
          traces_enabled: @configuration.otel_traces_enabled?,
          configured_env: configured_env,
          endpoint: configured_endpoint
        }
      end

      private

      def count_safely(table)
        return 0 unless @store&.db&.table_exists?(table)
        @store.db[table].count
      rescue Sequel::DatabaseError
        0
      end

      def last_timestamp(table, column)
        return nil unless @store&.db&.table_exists?(table)
        @store.db[table].max(column)
      rescue Sequel::DatabaseError
        nil
      end

      def configured_env
        return {} unless @settings_writer
        @settings_writer.current_env
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def configured_endpoint
        configured_env["OTEL_EXPORTER_OTLP_ENDPOINT"]
      end
    end
  end
end
