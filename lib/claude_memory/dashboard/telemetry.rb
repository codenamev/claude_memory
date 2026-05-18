# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Cost & Tokens dashboard panel. Aggregates Claude Code's OTel metric
    # exports — server-side via Sequel datasets so the API returns
    # final-rendered bins and the JS does no reduce.
    #
    # Returns the empty shape ({status:, cost_over_time: [], ...}) when no
    # store or no rows exist so the dashboard renders before the first
    # ingest.
    class Telemetry
      LOOKBACK_DAYS = 7
      TOP_TOOLS_LIMIT = 10

      def initialize(manager)
        @manager = manager
      end

      def snapshot
        store = @manager.default_store(prefer: :global)
        return empty_snapshot(store) unless store&.db&.table_exists?(:otel_metrics)

        cutoff = (Time.now - LOOKBACK_DAYS * 86_400).utc.iso8601
        metrics = store.otel_metrics.where { recorded_at >= cutoff }
        events = events_dataset(store, cutoff)

        {
          status: status_payload(store),
          cost_over_time: cost_over_time(metrics),
          tokens_by_model: tokens_by_model(metrics),
          top_tools_by_latency: top_tools(events),
          error_rate: error_rate(events),
          recent_metrics: recent_metrics(metrics),
          contains_prompt_content: contains_prompt_content?(events)
        }
      end

      private

      def empty_snapshot(store)
        {
          status: status_payload(store),
          cost_over_time: [],
          tokens_by_model: [],
          top_tools_by_latency: [],
          error_rate: {total: 0, errors: 0, ratio: 0.0},
          recent_metrics: [],
          contains_prompt_content: false
        }
      end

      def status_payload(store)
        OTel::Status.new(store, configuration: ClaudeMemory::Configuration.new).snapshot
      end

      def cost_over_time(metrics)
        rows = metrics
          .where(name: OTel::MetricName::COST_USAGE)
          .select_group(Sequel.lit("substr(recorded_at, 1, 13)").as(:hour))
          .select_append { sum(value_float).as(:cost_usd) }
          .select_append { count(id).as(:requests) }
          .order(:hour)
          .all
        rows.map { |r|
          {
            hour: r[:hour],
            cost_usd: (r[:cost_usd] || 0.0).to_f.round(6),
            requests: r[:requests].to_i
          }
        }
      end

      # SQLite's json_extract was added in 3.38.0 (2022-02). Sequel runs it
      # via Sequel.lit so we group by (model, type) at the DB layer instead
      # of materializing the whole window into Ruby.
      def tokens_by_model(metrics)
        model_expr = Sequel.lit("json_extract(attributes_json, '$.model')")
        type_expr = Sequel.lit("json_extract(attributes_json, '$.type')")
        rows = metrics
          .where(name: OTel::MetricName::TOKEN_USAGE)
          .select_group(model_expr.as(:model), type_expr.as(:type))
          .select_append { sum(Sequel.function(:coalesce, :value_int, :value_float)).as(:tokens) }
          .order(Sequel.desc(:tokens))
          .all
        rows.map { |r|
          {model: r[:model] || "unknown", type: r[:type] || "unknown", tokens: r[:tokens].to_i}
        }
      end

      def top_tools(events)
        return [] if events.nil?
        tool_expr = Sequel.lit("json_extract(attributes_json, '$.tool_name')")
        duration_expr = Sequel.lit("json_extract(attributes_json, '$.duration_ms')")
        rows = events
          .where(event_name: OTel::EventName::TOOL_RESULT)
          .select_group(tool_expr.as(:tool))
          .select_append { count(id).as(:count) }
          .select_append { avg(duration_expr).as(:avg_duration_ms) }
          .order(Sequel.desc(:avg_duration_ms))
          .limit(TOP_TOOLS_LIMIT)
          .all
        rows.map { |r|
          {tool: r[:tool] || "unknown", count: r[:count].to_i, avg_duration_ms: r[:avg_duration_ms].to_i}
        }
      end

      def error_rate(events)
        return {total: 0, errors: 0, ratio: 0.0} if events.nil?
        total = events.where(event_name: OTel::EventName::API_PAIR).count
        errors = events.where(event_name: OTel::EventName::API_ERROR).count
        ratio = total.zero? ? 0.0 : (errors.to_f / total).round(4)
        {total: total, errors: errors, ratio: ratio}
      end

      def recent_metrics(metrics)
        rows = metrics
          .where(name: OTel::MetricName::TOKEN_USAGE)
          .order(Sequel.desc(:recorded_at))
          .limit(100)
          .all
        rows.map { |row|
          attrs = OTel::Attributes.from_json(row[:attributes_json])
          {
            recorded_at: row[:recorded_at],
            model: attrs.model,
            type: attrs.token_type,
            tokens: OTel::Attributes.token_count(row),
            session_id: attrs.session_id,
            prompt_id: attrs.prompt_id
          }.compact
        }
      end

      def events_dataset(store, cutoff)
        return nil unless store.db.table_exists?(:otel_events)
        store.otel_events.where { occurred_at >= cutoff }
      end

      # SQL pre-filter via LIKE on each prompt-content key, short-circuited
      # by .any?. JSON encodes object keys as `"key":` (compact), so the
      # patterns can't false-match longer keys (e.g. "prompt_length").
      def contains_prompt_content?(events)
        return false if events.nil?
        clauses = OTel::Attributes::PROMPT_CONTENT_KEYS.map { |key|
          Sequel.lit("attributes_json LIKE ?", %("#{key}":))
        }
        events
          .where(event_name: OTel::EventName::PROMPT_BODY_FAMILY)
          .where(Sequel.|(*clauses))
          .limit(1)
          .any?
      end
    end
  end
end
