# frozen_string_literal: true

# Migration v18: OpenTelemetry ingestion tables.
#
# ClaudeMemory's dashboard accepts OTLP/HTTP/JSON exports from Claude Code so
# users can see cost-per-API-call, token usage by model, latency, and per-prompt
# event journeys without leaving the dashboard.
#
# Three storage tables:
#   - otel_metrics: numeric data points (token counts, USD cost, durations).
#     Two value columns (value_int + value_float) preserve int64 precision for
#     counters like token counts that exceed Float's 2^53 mantissa.
#   - otel_events: log-style records (user_prompt, tool_result, api_request,
#     skill_activated, ...). Indexed on prompt_id for the journey UNION.
#   - otel_traces: spans. Table ships now so the schema is forward-ready, but
#     the dashboard's POST /v1/traces returns 501 until the user opts in via
#     `claude-memory otel --enable-traces`.
#
# Plus an additive prompt_id column on activity_events so existing hook
# events (recall, hook_ingest, hook_context) can be UNION-joined into the
# Prompt Journey panel.
Sequel.migration do
  up do
    create_table?(:otel_metrics) do
      primary_key :id
      String :name, null: false
      String :value_type, null: false
      Bignum :value_int
      Float :value_float
      String :unit
      String :attributes_json, text: true
      String :resource_json, text: true
      String :recorded_at, null: false
    end
    run "CREATE INDEX IF NOT EXISTS idx_otel_metrics_name_time ON otel_metrics(name, recorded_at)"
    run "CREATE INDEX IF NOT EXISTS idx_otel_metrics_recorded_at ON otel_metrics(recorded_at)"

    create_table?(:otel_events) do
      primary_key :id
      String :event_name, null: false
      String :session_id
      String :prompt_id
      String :attributes_json, text: true
      String :resource_json, text: true
      String :occurred_at, null: false
    end
    run "CREATE INDEX IF NOT EXISTS idx_otel_events_name_time ON otel_events(event_name, occurred_at)"
    run "CREATE INDEX IF NOT EXISTS idx_otel_events_session ON otel_events(session_id)"
    run "CREATE INDEX IF NOT EXISTS idx_otel_events_prompt ON otel_events(prompt_id)"

    create_table?(:otel_traces) do
      primary_key :id
      String :trace_id, null: false
      String :span_id, null: false
      String :parent_span_id
      String :name, null: false
      String :session_id
      String :prompt_id
      Bignum :start_unix_nano
      Bignum :end_unix_nano
      Integer :duration_ms
      String :status_code
      String :attributes_json, text: true
      String :resource_json, text: true
      String :recorded_at, null: false
    end
    run "CREATE INDEX IF NOT EXISTS idx_otel_traces_trace ON otel_traces(trace_id)"
    run "CREATE INDEX IF NOT EXISTS idx_otel_traces_time ON otel_traces(recorded_at)"

    alter_table(:activity_events) { add_column :prompt_id, String }
    run "CREATE INDEX IF NOT EXISTS idx_activity_events_prompt ON activity_events(prompt_id)"
  end

  down do
    run "DROP INDEX IF EXISTS idx_activity_events_prompt"
    alter_table(:activity_events) { drop_column :prompt_id }
    drop_table?(:otel_traces)
    drop_table?(:otel_events)
    drop_table?(:otel_metrics)
  end
end
