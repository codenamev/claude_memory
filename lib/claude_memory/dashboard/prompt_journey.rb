# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Per-prompt waterfall view. Calls Store::PromptJourneyQuery to UNION
    # otel_events and activity_events on prompt_id, then shapes results
    # for the frontend (relative timestamps, parsed attributes).
    class PromptJourney
      def initialize(manager)
        @manager = manager
      end

      def for(prompt_id)
        store = @manager.default_store(prefer: :global)
        return empty_payload(prompt_id) unless store

        rows = ClaudeMemory::Store::PromptJourneyQuery.new(store).fetch(prompt_id)
        {
          prompt_id: prompt_id,
          event_count: rows.size,
          events: rows.map { |row| present(row) }
        }
      end

      private

      def empty_payload(prompt_id)
        {prompt_id: prompt_id, event_count: 0, events: []}
      end

      def present(row)
        attrs = OTel::Attributes.from_json(row[:attributes_json])
        {
          source: row[:source],
          name: row[:name],
          occurred_at: row[:occurred_at],
          occurred_ago: Core::RelativeTime.format(row[:occurred_at]),
          session_id: row[:session_id],
          status: row[:status],
          duration_ms: row[:duration_ms] || attrs.duration_ms,
          model: attrs.model,
          tool_name: attrs.tool_name
        }.compact
      end
    end
  end
end
