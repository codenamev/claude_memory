# frozen_string_literal: true

require "time"

module ClaudeMemory
  module OTel
    # Pure functional core for OTLP/HTTP/JSON payloads. Walks the canonical
    # OTLP envelope shapes (resourceMetrics → scopeMetrics → metrics →
    # dataPoints; resourceLogs → scopeLogs → logRecords; resourceSpans →
    # scopeSpans → spans), flattens KeyValue attribute arrays into Ruby
    # hashes, and returns plain row hashes ready to insert.
    #
    # No Time.now, no ENV reads, no DB. Pass a clock object that responds
    # to `now` (or just `Time`) for fallback timestamps when the payload
    # omits one. Required keys raise via Hash#fetch; optional containers
    # default to empty arrays.
    #
    # All public methods return Arrays of Hashes whose keys match the
    # SQLiteStore.insert_otel_* helpers exactly.
    module OtlpJsonEnvelope
      module_function

      # @param payload [Hash] parsed OTLP MetricsServiceRequest JSON
      # @param clock [#now] used for fallback when timeUnixNano is missing
      # @return [Array<Hash>] rows for SQLiteStore#insert_otel_metric
      def parse_metrics(payload, clock: Time)
        rows = []
        Array(payload["resourceMetrics"]).each do |resource_metric|
          resource = flatten_attributes(dig_attributes(resource_metric["resource"]))
          Array(resource_metric["scopeMetrics"]).each do |scope_metric|
            Array(scope_metric["metrics"]).each do |metric|
              metric_name = metric.fetch("name")
              unit = metric["unit"]
              data_points = collect_data_points(metric)
              data_points.each do |point|
                value_type, value_int, value_float = decode_metric_value(point)
                next if value_type.nil?

                rows << {
                  name: metric_name,
                  value_type: value_type,
                  value_int: value_int,
                  value_float: value_float,
                  unit: unit,
                  attributes: flatten_attributes(point["attributes"]),
                  resource: resource,
                  recorded_at: timestamp_from_point(point, clock)
                }
              end
            end
          end
        end
        rows
      end

      # @param payload [Hash] parsed OTLP LogsServiceRequest JSON
      # @param clock [#now]
      # @return [Array<Hash>] rows for SQLiteStore#insert_otel_event
      def parse_logs(payload, clock: Time)
        rows = []
        Array(payload["resourceLogs"]).each do |resource_log|
          resource = flatten_attributes(dig_attributes(resource_log["resource"]))
          Array(resource_log["scopeLogs"]).each do |scope_log|
            Array(scope_log["logRecords"]).each do |record|
              attributes = flatten_attributes(record["attributes"])
              rows << {
                event_name: event_name_for(record, attributes),
                occurred_at: timestamp_from_record(record, clock),
                session_id: attributes["session.id"],
                prompt_id: attributes["prompt.id"],
                attributes: attributes,
                resource: resource
              }
            end
          end
        end
        rows
      end

      # @param payload [Hash] parsed OTLP TracesServiceRequest JSON
      # @param clock [#now]
      # @return [Array<Hash>] rows for SQLiteStore#insert_otel_trace_span
      def parse_traces(payload, clock: Time)
        rows = []
        Array(payload["resourceSpans"]).each do |resource_span|
          resource = flatten_attributes(dig_attributes(resource_span["resource"]))
          Array(resource_span["scopeSpans"]).each do |scope_span|
            Array(scope_span["spans"]).each do |span|
              attributes = flatten_attributes(span["attributes"])
              start_nano = parse_unix_nano(span["startTimeUnixNano"])
              end_nano = parse_unix_nano(span["endTimeUnixNano"])
              rows << {
                trace_id: span.fetch("traceId"),
                span_id: span.fetch("spanId"),
                parent_span_id: span["parentSpanId"],
                name: span.fetch("name"),
                session_id: attributes["session.id"],
                prompt_id: attributes["prompt.id"],
                start_unix_nano: start_nano,
                end_unix_nano: end_nano,
                duration_ms: duration_ms_from(start_nano, end_nano),
                status_code: span.dig("status", "code")&.to_s,
                attributes: attributes,
                resource: resource,
                recorded_at: timestamp_from_unix_nano(start_nano, clock)
              }
            end
          end
        end
        rows
      end

      # Flatten OTel KeyValue array (`[{key:, value: {stringValue: ...}}, ...]`)
      # into a plain Hash.
      def flatten_attributes(kv_array)
        result = {}
        Array(kv_array).each do |kv|
          next unless kv.is_a?(Hash)
          key = kv["key"]
          next if key.nil? || key.empty?
          result[key] = decode_any_value(kv["value"])
        end
        result
      end

      def decode_any_value(value)
        return nil unless value.is_a?(Hash)
        return value["stringValue"] if value.key?("stringValue")
        # OTLP JSON encodes int64 as a string to avoid JS precision loss.
        return decode_int_string(value["intValue"]) if value.key?("intValue")
        return value["doubleValue"] if value.key?("doubleValue")
        return value["boolValue"] if value.key?("boolValue")
        if value.key?("arrayValue")
          values = value.dig("arrayValue", "values") || []
          return values.map { |v| decode_any_value(v) }
        end
        if value.key?("kvlistValue")
          kvs = value.dig("kvlistValue", "values") || []
          return flatten_attributes(kvs)
        end
        nil
      end

      private_class_method :decode_any_value

      def decode_int_string(value)
        return value if value.is_a?(Integer)
        return nil if value.nil?
        Integer(value.to_s, 10)
      rescue ArgumentError
        nil
      end

      private_class_method :decode_int_string

      def dig_attributes(container)
        container.is_a?(Hash) ? container["attributes"] : nil
      end

      private_class_method :dig_attributes

      # Pull dataPoints out of whichever metric type wrapper is present.
      # Histograms and summaries (rare in Claude Code's exports) return
      # their data points; we record the count value when present.
      def collect_data_points(metric)
        %w[sum gauge histogram exponentialHistogram summary].each do |kind|
          wrapper = metric[kind]
          next unless wrapper.is_a?(Hash)
          points = wrapper["dataPoints"]
          return Array(points) if points
        end
        []
      end

      private_class_method :collect_data_points

      # Returns [value_type, value_int, value_float] tuple. nil value_type
      # means we couldn't decode anything storable.
      def decode_metric_value(point)
        if point.key?("asInt")
          int_value = decode_int_string(point["asInt"])
          return [ValueType::INT, int_value, nil] unless int_value.nil?
        end
        if point.key?("asDouble")
          d = point["asDouble"]
          return [ValueType::DOUBLE, nil, d.to_f] unless d.nil?
        end
        # Histogram / summary fall-back: store sum when present, count
        # otherwise. Skip when neither is available.
        if point.key?("sum")
          s = point["sum"]
          return [ValueType::DOUBLE, nil, s.to_f] unless s.nil?
        end
        if point.key?("count")
          count = decode_int_string(point["count"])
          return [ValueType::INT, count, nil] unless count.nil?
        end
        [nil, nil, nil]
      end

      private_class_method :decode_metric_value

      def event_name_for(record, attributes)
        # OTel logs/events: the event name lives on the attribute
        # "event.name" by convention. Claude Code sets it as
        # "claude_code.<name>" on its instrumentation scope, so we strip
        # the prefix when present so panels see "user_prompt", not
        # "claude_code.user_prompt".
        raw = attributes["event.name"] || record["eventName"] || record.dig("body", "stringValue") || "log"
        raw.to_s.sub(/\Aclaude_code\./, "")
      end

      private_class_method :event_name_for

      def timestamp_from_point(point, clock)
        nano = parse_unix_nano(point["timeUnixNano"]) || parse_unix_nano(point["startTimeUnixNano"])
        timestamp_from_unix_nano(nano, clock)
      end

      private_class_method :timestamp_from_point

      def timestamp_from_record(record, clock)
        nano = parse_unix_nano(record["timeUnixNano"]) || parse_unix_nano(record["observedTimeUnixNano"])
        timestamp_from_unix_nano(nano, clock)
      end

      private_class_method :timestamp_from_record

      def timestamp_from_unix_nano(nano, clock)
        return clock.now.utc.iso8601 if nano.nil?
        Time.at(nano / 1_000_000_000.0).utc.iso8601
      end

      private_class_method :timestamp_from_unix_nano

      def parse_unix_nano(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)
        Integer(value.to_s, 10)
      rescue ArgumentError
        nil
      end

      private_class_method :parse_unix_nano

      def duration_ms_from(start_nano, end_nano)
        return nil if start_nano.nil? || end_nano.nil?
        ((end_nano - start_nano) / 1_000_000).to_i
      end

      private_class_method :duration_ms_from
    end
  end
end
