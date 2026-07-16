# frozen_string_literal: true

module ClaudeMemory
  module Store
    # OTel metric/event/trace-span writers for SQLiteStore.
    #
    # Extracted from SQLiteStore (module inclusion — the public API is
    # unchanged) to keep the store focused on core fact/entity/provenance
    # storage. Depends on the +otel_metrics+/+otel_events+/+otel_traces+ table
    # accessors that remain on the including class.
    module OtelWrites
      # Insert one OTel metric data point. Two value columns let us preserve
      # int64 precision for counters (token counts) without losing fidelity in
      # Float — see migration 018.
      #
      # @param name [String] OTel metric name (e.g. "claude_code.token.usage")
      # @param value_type [String] "int" or "double"
      # @param value_int [Integer, nil] integer value when value_type == "int"
      # @param value_float [Float, nil] float value when value_type == "double"
      # @param unit [String, nil] OTel unit string ("tokens", "USD", "s", ...)
      # @param attributes [Hash, nil] flattened attribute map
      # @param resource [Hash, nil] resource attribute map
      # @param recorded_at [String] ISO 8601 timestamp
      # @return [Integer] inserted row id
      def insert_otel_metric(name:, value_type:, recorded_at:, value_int: nil, value_float: nil,
        unit: nil, attributes: nil, resource: nil)
        otel_metrics.insert(otel_metric_row(
          name: name, value_type: value_type, recorded_at: recorded_at,
          value_int: value_int, value_float: value_float, unit: unit,
          attributes: attributes, resource: resource
        ))
      end

      # Bulk insert OTel metric rows in a single SQL statement. Hot-path
      # callers (the OTLP receiver) batch dozens of points per request;
      # multi_insert avoids the per-row prepare/bind overhead.
      def bulk_insert_otel_metrics(rows)
        return 0 if rows.empty?
        otel_metrics.multi_insert(rows.map { |r| otel_metric_row(**r) })
        rows.size
      end

      # Insert one OTel log-style event row.
      #
      # @param event_name [String] e.g. "user_prompt", "tool_result", "api_request"
      # @param occurred_at [String] ISO 8601 timestamp
      # @param session_id [String, nil]
      # @param prompt_id [String, nil] UUID correlating events from one prompt
      # @param attributes [Hash, nil]
      # @param resource [Hash, nil]
      # @return [Integer] inserted row id
      def insert_otel_event(event_name:, occurred_at:, session_id: nil, prompt_id: nil,
        attributes: nil, resource: nil)
        otel_events.insert(otel_event_row(
          event_name: event_name, occurred_at: occurred_at,
          session_id: session_id, prompt_id: prompt_id,
          attributes: attributes, resource: resource
        ))
      end

      def bulk_insert_otel_events(rows)
        return 0 if rows.empty?
        otel_events.multi_insert(rows.map { |r| otel_event_row(**r) })
        rows.size
      end

      # Insert one OTel trace span row. Only used when traces are explicitly
      # opted in via Configuration#otel_traces_enabled?.
      #
      # @param trace_id [String]
      # @param span_id [String]
      # @param name [String]
      # @param recorded_at [String]
      # @param parent_span_id [String, nil]
      # @param session_id [String, nil]
      # @param prompt_id [String, nil]
      # @param start_unix_nano [Integer, nil]
      # @param end_unix_nano [Integer, nil]
      # @param duration_ms [Integer, nil]
      # @param status_code [String, nil]
      # @param attributes [Hash, nil]
      # @param resource [Hash, nil]
      # @return [Integer] inserted row id
      def insert_otel_trace_span(trace_id:, span_id:, name:, recorded_at:,
        parent_span_id: nil, session_id: nil, prompt_id: nil,
        start_unix_nano: nil, end_unix_nano: nil, duration_ms: nil,
        status_code: nil, attributes: nil, resource: nil)
        otel_traces.insert(otel_trace_row(
          trace_id: trace_id, span_id: span_id, name: name, recorded_at: recorded_at,
          parent_span_id: parent_span_id, session_id: session_id, prompt_id: prompt_id,
          start_unix_nano: start_unix_nano, end_unix_nano: end_unix_nano,
          duration_ms: duration_ms, status_code: status_code,
          attributes: attributes, resource: resource
        ))
      end

      def bulk_insert_otel_traces(rows)
        return 0 if rows.empty?
        otel_traces.multi_insert(rows.map { |r| otel_trace_row(**r) })
        rows.size
      end

      private

      def otel_metric_row(name:, value_type:, recorded_at:, value_int: nil, value_float: nil,
        unit: nil, attributes: nil, resource: nil)
        {
          name: name, value_type: value_type, value_int: value_int, value_float: value_float,
          unit: unit, attributes_json: attributes&.to_json, resource_json: resource&.to_json,
          recorded_at: recorded_at
        }
      end

      def otel_event_row(event_name:, occurred_at:, session_id: nil, prompt_id: nil,
        attributes: nil, resource: nil)
        {
          event_name: event_name, session_id: session_id, prompt_id: prompt_id,
          attributes_json: attributes&.to_json, resource_json: resource&.to_json,
          occurred_at: occurred_at
        }
      end

      def otel_trace_row(trace_id:, span_id:, name:, recorded_at:,
        parent_span_id: nil, session_id: nil, prompt_id: nil,
        start_unix_nano: nil, end_unix_nano: nil, duration_ms: nil,
        status_code: nil, attributes: nil, resource: nil)
        {
          trace_id: trace_id, span_id: span_id, parent_span_id: parent_span_id,
          name: name, session_id: session_id, prompt_id: prompt_id,
          start_unix_nano: start_unix_nano, end_unix_nano: end_unix_nano,
          duration_ms: duration_ms, status_code: status_code,
          attributes_json: attributes&.to_json, resource_json: resource&.to_json,
          recorded_at: recorded_at
        }
      end
    end
  end
end
