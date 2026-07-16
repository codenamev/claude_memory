# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Observability for the episodic observation layer. Surfaces counts by
    # status/kind/priority, corroboration + promotion readiness, a Mastra-style
    # compression ratio (source content tokens ÷ observation tokens), and a
    # recent timeline. Aggregated across the project and global stores.
    #
    # Pulled out of Dashboard::API so the queries live next to the data.
    class Observations
      RECENT_LIMIT = 20

      def initialize(manager)
        @manager = manager
      end

      def report
        stores = observation_stores
        return empty_report if stores.empty?

        stats = Observe::ObservationStats.new(stores)
        {
          totals: stats.totals,
          by_kind: stats.by_field(:kind),
          by_priority: stats.by_field(:priority),
          corroboration: stats.corroboration,
          compression: stats.compression,
          recent: recent(stores)
        }
      end

      private

      def observation_stores
        [@manager.project_store, @manager.global_store].compact.select { |s| s.db.table_exists?(:observations) }
      end

      def empty_report
        {
          totals: {active: 0, consolidated: 0, expired: 0, promoted: 0},
          by_kind: {}, by_priority: {},
          corroboration: {max: 0, promotable: 0},
          compression: {observation_tokens: 0, source_tokens: 0, ratio: nil},
          recent: []
        }
      end

      def recent(stores)
        stores
          .flat_map { |s| s.recent_observations(limit: RECENT_LIMIT) }
          .sort_by { |o| o[:observed_at].to_s }.reverse.first(RECENT_LIMIT)
          .map do |o|
            {
              id: o[:id], kind: o[:kind], priority: o[:priority],
              corroboration_count: o[:corroboration_count], body: o[:body],
              observed_ago: Core::RelativeTime.format(o[:observed_at])
            }
          end
      end
    end
  end
end
