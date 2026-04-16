# frozen_string_literal: true

require "json"

module ClaudeMemory
  # Records activity events for debugging and observability.
  # Events are stored in the activity_events table and surfaced
  # via the dashboard and `memory.activity` MCP tool.
  module ActivityLog
    module_function

    # Record an activity event in the given store.
    #
    # @param store [Store::SQLiteStore] database to write to
    # @param event_type [String] e.g. "hook_ingest", "hook_context", "recall"
    # @param status [String] "success", "skipped", or "error"
    # @param session_id [String, nil] Claude session ID
    # @param duration_ms [Integer, nil] operation duration in milliseconds
    # @param details [Hash, nil] event-specific metadata
    def record(store, event_type:, status:, session_id: nil, duration_ms: nil, details: nil)
      store.activity_events.insert(
        event_type: event_type,
        session_id: session_id,
        status: status,
        duration_ms: duration_ms,
        detail_json: details&.to_json,
        occurred_at: Time.now.utc.iso8601
      )
    rescue => e
      ClaudeMemory.logger.warn("activity_log", message: "Failed to record event", error: e.message)
      nil
    end

    # Query recent activity events.
    #
    # @param store [Store::SQLiteStore] database to read from
    # @param limit [Integer] max events to return
    # @param event_type [String, nil] filter by type
    # @param since [String, nil] ISO 8601 lower bound
    # @return [Array<Hash>] event records with parsed details
    def recent(store, limit: 50, event_type: nil, since: nil)
      dataset = store.activity_events.order(Sequel.desc(:occurred_at)).limit(limit)
      dataset = dataset.where(event_type: event_type) if event_type
      dataset = dataset.where { occurred_at >= since } if since

      dataset.all.map do |row|
        row[:details] = row[:detail_json] ? JSON.parse(row[:detail_json], symbolize_names: true) : nil
        row.delete(:detail_json)
        row
      end
    rescue => e
      ClaudeMemory.logger.warn("activity_log", message: "Failed to query events", error: e.message)
      []
    end

    # Summarize activity counts grouped by event_type.
    #
    # @param store [Store::SQLiteStore]
    # @param since [String, nil] ISO 8601 lower bound
    # @return [Hash] e.g. {"hook_ingest" => {success: 5, error: 1}, ...}
    def summary(store, since: nil)
      dataset = store.activity_events
      dataset = dataset.where { occurred_at >= since } if since

      rows = dataset
        .group_and_count(:event_type, :status)
        .all

      result = {}
      rows.each do |row|
        result[row[:event_type]] ||= {}
        result[row[:event_type]][row[:status].to_sym] = row[:count]
      end
      result
    rescue => e
      ClaudeMemory.logger.warn("activity_log", message: "Failed to summarize events", error: e.message)
      {}
    end
  end
end
