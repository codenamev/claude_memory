# frozen_string_literal: true

module ClaudeMemory
  module Store
    # Cross-store query for the dashboard's Prompt Journey panel. OTel
    # events live in the global DB (writes hit the receiver, which is
    # process-wide); activity_events with a back-tagged prompt_id can
    # live in either store (hooks fire per-project, so hook_ingest /
    # hook_context rows land in the project DB, while global may carry
    # cross-project events). The query reads from all available stores
    # and orders the merged stream by occurred_at.
    #
    # Accepts either a single store (legacy callers) or a StoreManager.
    # Returns plain row hashes shaped uniformly so the panel renders
    # both sources without branching.
    class PromptJourneyQuery
      def initialize(store_or_manager)
        @stores = if store_or_manager.respond_to?(:project_store) || store_or_manager.respond_to?(:global_store)
          [store_or_manager.respond_to?(:project_store) ? store_or_manager.project_store : nil,
            store_or_manager.respond_to?(:global_store) ? store_or_manager.global_store : nil].compact
        else
          [store_or_manager].compact
        end
      end

      # @param prompt_id [String] OTel prompt.id UUID
      # @return [Array<Hash>] rows ordered by occurred_at ascending
      def fetch(prompt_id)
        return [] if prompt_id.nil? || prompt_id.empty?

        rows = @stores.flat_map { |store|
          otel_rows(store, prompt_id) + activity_rows(store, prompt_id)
        }
        rows.sort_by { |r| r[:occurred_at].to_s }
      end

      private

      def otel_rows(store, prompt_id)
        return [] unless store&.db&.table_exists?(:otel_events)
        store.otel_events
          .where(prompt_id: prompt_id)
          .order(:occurred_at)
          .limit(500)
          .all
          .map { |row| present_otel(row) }
      end

      def activity_rows(store, prompt_id)
        return [] unless store&.db&.table_exists?(:activity_events)
        return [] unless store.activity_events.columns.include?(:prompt_id)
        store.activity_events
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
