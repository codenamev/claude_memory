# frozen_string_literal: true

# Migration v15: Add activity_events table for debugging and observability
# Tracks hook executions, memory recalls, context injections, and sweep operations.
# Powers the dashboard timeline and efficacy reports.
Sequel.migration do
  up do
    create_table?(:activity_events) do
      primary_key :id
      String :event_type, null: false    # "hook_ingest", "hook_context", "hook_sweep", "recall", "store_extraction"
      String :session_id                 # Claude session that triggered the event
      String :status, null: false        # "success", "skipped", "error"
      Integer :duration_ms               # How long the operation took
      String :detail_json, text: true    # Event-specific details (JSON)
      String :occurred_at, null: false   # ISO 8601 timestamp
    end

    run "CREATE INDEX IF NOT EXISTS idx_activity_events_type ON activity_events(event_type)"
    run "CREATE INDEX IF NOT EXISTS idx_activity_events_occurred_at ON activity_events(occurred_at)"
    run "CREATE INDEX IF NOT EXISTS idx_activity_events_session ON activity_events(session_id)"
  end

  down do
    drop_table?(:activity_events)
  end
end
