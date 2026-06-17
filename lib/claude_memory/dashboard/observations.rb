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

        {
          totals: totals(stores),
          by_kind: by_field(stores, :kind),
          by_priority: by_field(stores, :priority),
          corroboration: corroboration(stores),
          compression: compression(stores),
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

      def totals(stores)
        {
          active: count_where(stores, status: "active"),
          consolidated: count_where(stores, status: "consolidated"),
          expired: count_where(stores, status: "expired"),
          promoted: stores.sum { |s| s.observations.exclude(promoted_at: nil).count }
        }
      end

      def count_where(stores, **filter)
        stores.sum { |s| s.observations.where(**filter).count }
      end

      def by_field(stores, field)
        merged = Hash.new(0)
        stores.each do |store|
          store.observations.where(status: "active").group_and_count(field).each do |row|
            merged[row[field]] += row[:count]
          end
        end
        merged
      end

      def corroboration(stores)
        threshold = Domain::Observation::PROMOTION_THRESHOLD
        {
          max: stores.map { |s| s.observations.where(status: "active").max(:corroboration_count) || 0 }.max,
          promotable: stores.sum { |s|
            s.observations.where(status: "active", promoted_at: nil).where { corroboration_count >= threshold }.count
          }
        }
      end

      # Source content tokens vs the tokens the observations distilled them into.
      # ratio > 1 means the episodic log is a compression of its source.
      def compression(stores)
        obs_tokens = stores.sum { |s| s.observations.where(status: "active").sum(:token_count) || 0 }
        source_tokens = stores.sum { |s| source_tokens_for(s) }
        ratio = obs_tokens.zero? ? nil : (source_tokens.to_f / obs_tokens).round(1)
        {observation_tokens: obs_tokens, source_tokens: source_tokens, ratio: ratio}
      end

      def source_tokens_for(store)
        ids = store.observations
          .where(status: "active").exclude(source_content_item_id: nil)
          .distinct.select(:source_content_item_id)
          .map { |r| r[:source_content_item_id] }
        return 0 if ids.empty?

        bytes = store.content_items.where(id: ids).sum(:byte_len) || 0
        (bytes / 4.0).round
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
