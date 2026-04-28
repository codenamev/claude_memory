# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Daily activity rollup for the dashboard timeline view. Aggregates three
    # event sources (fact creation, content ingestion, activity events) into
    # per-day buckets covering the last 30 days. Returns the empty shape
    # ({days: []}) when no project store is available so the dashboard can
    # render before the first ingest.
    class Timeline
      LOOKBACK_DAYS = 30

      def initialize(manager)
        @manager = manager
      end

      def days
        store = @manager.default_store(prefer: :project)
        return {days: []} unless store

        cutoff = (Time.now - LOOKBACK_DAYS * 86_400).utc.iso8601
        {days: build_days(store, cutoff)}
      end

      private

      def build_days(store, cutoff)
        fact_rows = group_count(store.facts, cutoff_field: :created_at, cutoff: cutoff)
        content_rows = group_count(store.content_items, cutoff_field: :ingested_at, cutoff: cutoff)
        event_rows = activity_event_rows(store, cutoff)

        all_days = (fact_rows + content_rows + event_rows).map { |r| r[:day] }.uniq.sort
        all_days.map { |day| compose_day(day, fact_rows, content_rows, event_rows) }
      end

      def group_count(dataset, cutoff_field:, cutoff:)
        dataset
          .where { Sequel[cutoff_field] >= cutoff }
          .select_group(Sequel.lit("DATE(#{cutoff_field})").as(:day))
          .select_append { count(id).as(:count) }
          .order(:day)
          .all
      end

      def activity_event_rows(store, cutoff)
        return [] unless store.db.table_exists?(:activity_events)

        store.activity_events
          .where { occurred_at >= cutoff }
          .select_group(Sequel.lit("DATE(occurred_at)").as(:day), :event_type)
          .select_append { count(id).as(:count) }
          .order(:day)
          .all
      end

      def compose_day(day, fact_rows, content_rows, event_rows)
        day_events = event_rows.select { |r| r[:day] == day }
        {
          date: day,
          facts_created: fact_rows.find { |r| r[:day] == day }&.dig(:count) || 0,
          content_ingested: content_rows.find { |r| r[:day] == day }&.dig(:count) || 0,
          hook_events: day_events.sum { |r| r[:count] },
          recalls: day_events.select { |r| r[:event_type] == "recall" }.sum { |r| r[:count] }
        }
      end
    end
  end
end
