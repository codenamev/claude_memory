# frozen_string_literal: true

module ClaudeMemory
  module Store
    # Cross-table query for the dashboard's Prompt Journey panel. UNION ALL
    # joins otel_events and activity_events on prompt_id and orders the
    # combined stream by timestamp. One round-trip — no Ruby-side merge.
    #
    # Returns plain row hashes shaped uniformly so the panel renders both
    # sources without branching.
    class PromptJourneyQuery
      def initialize(store)
        @store = store
      end

      # @param prompt_id [String] OTel prompt.id UUID
      # @return [Array<Hash>] rows ordered by occurred_at ascending
      def fetch(prompt_id)
        return [] if prompt_id.nil? || prompt_id.empty?

        # Each side caps at 500 to keep memory bounded.
        rows = otel_dataset(prompt_id) + activity_dataset(prompt_id)
        rows.sort_by { |r| r[:occurred_at].to_s }
      end

      private

      def otel_dataset(prompt_id)
        return [] unless @store.db.table_exists?(:otel_events)
        @store.otel_events
          .where(prompt_id: prompt_id)
          .order(:occurred_at)
          .limit(500)
          .all
          .map { |row| present_otel(row) }
      end

      def activity_dataset(prompt_id)
        return [] unless @store.db.table_exists?(:activity_events)
        return [] unless @store.activity_events.columns.include?(:prompt_id)
        @store.activity_events
          .where(prompt_id: prompt_id)
          .order(:occurred_at)
          .limit(500)
          .all
          .map { |row| present_activity(row) }
      end

      def present_otel(row)
        {
          source: "otel",
          id: row[:id],
          name: row[:event_name],
          session_id: row[:session_id],
          prompt_id: row[:prompt_id],
          occurred_at: row[:occurred_at],
          attributes_json: row[:attributes_json]
        }
      end

      def present_activity(row)
        {
          source: "activity",
          id: row[:id],
          name: row[:event_type],
          session_id: row[:session_id],
          prompt_id: row[:prompt_id],
          occurred_at: row[:occurred_at],
          status: row[:status],
          duration_ms: row[:duration_ms],
          detail_json: row[:detail_json]
        }
      end
    end
  end
end
