# frozen_string_literal: true

module ClaudeMemory
  module Observe
    # Aggregates episodic-observation counts across one or more stores: totals
    # by status, counts by field (kind/priority), corroboration + promotion
    # readiness, and the source-vs-observation compression ratio.
    #
    # Extracted so the CLI (StatsCommand, ObservationsCommand) and the
    # dashboard panel (Dashboard::Observations) share one implementation
    # instead of three drifting copies. Takes stores already filtered to those
    # that have an observations table; each caller keeps its own scope
    # selection and "recent timeline" rendering (those legitimately differ).
    class ObservationStats
      def initialize(stores)
        @stores = stores
      end

      # Total observation rows across all statuses.
      def total_count
        @stores.sum { |s| s.observations.count }
      end

      def totals
        {
          active: count_where(status: "active"),
          consolidated: count_where(status: "consolidated"),
          expired: count_where(status: "expired"),
          promoted: @stores.sum { |s| s.observations.exclude(promoted_at: nil).count }
        }
      end

      # Count of active observations grouped by a column (e.g. :kind, :priority).
      def by_field(field)
        merged = Hash.new(0)
        @stores.each do |store|
          store.observations.where(status: "active").group_and_count(field).each do |row|
            merged[row[field]] += row[:count]
          end
        end
        merged
      end

      def corroboration
        threshold = Domain::Observation::PROMOTION_THRESHOLD
        {
          max: @stores.map { |s| s.observations.where(status: "active").max(:corroboration_count) || 0 }.max || 0,
          promotable: @stores.sum do |s|
            s.observations.where(status: "active", promoted_at: nil)
              .where { corroboration_count >= threshold }.count
          end
        }
      end

      # Source content tokens vs the tokens the observations distilled them
      # into. ratio > 1 means the episodic log is a compression of its source.
      def compression
        obs_tokens = @stores.sum { |s| s.observations.where(status: "active").sum(:token_count) || 0 }
        source_tokens = @stores.sum { |s| source_tokens_for(s) }
        ratio = obs_tokens.zero? ? nil : (source_tokens.to_f / obs_tokens).round(1)
        {observation_tokens: obs_tokens, source_tokens: source_tokens, ratio: ratio}
      end

      private

      def count_where(**filter)
        @stores.sum { |s| s.observations.where(**filter).count }
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
    end
  end
end
